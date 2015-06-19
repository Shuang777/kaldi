#!/bin/bash

# Copyright 2012  Karel Vesely (Brno University of Technology)
# Apache 2.0

# Train neural network
{

set -e
set -o pipefail

# Begin configuration.

# training options
learn_rate=0.008
momentum=0
l1_penalty=0
l2_penalty=0
# data processing
minibatch_size=256
randomizer_size=32768
randomizer_seed=777
feature_transform=
feature_transform_list=
# learn rate scheduling
max_iters=20
min_iters=
lr_schedule=halve     # halve, fixed, exp
learn_rate_shrink=0.01  # for exponential shrink of learning rate
#start_halving_inc=0.5
#end_halving_inc=0.1
start_halving_impr=0.01
end_halving_impr=0.0001
halving_factor=0.5
resume_anneal=true
# misc.
verbose=1
# tool
train_tool="nnet-train-frmshuff"
frame_weights=
subnnet_ids=
semi_layers=
updatable_layers=
frames_per_reduce=
reduce_per_iter_tr=
reduce_type=
reduce_content=

# End configuration.

echo "$0 $@"  # Print the command line for logging
[ -f path.sh ] && . ./path.sh; 

. parse_options.sh || exit 1;

if [ $# != 6 ]; then
   echo "Usage: $0 <mlp-init> <feats-tr> <feats-cv> <labels-tr> <labels-cv> <exp-dir>"
   echo " e.g.: $0 0.nnet scp:train.scp scp:cv.scp ark:labels_tr.ark ark:labels_cv.ark exp/dnn1"
   echo "main options (for others, see top of script file)"
   echo "  --config <config-file>  # config containing options"
   exit 1;
fi

mlp_init=$1
feats_tr=$2
feats_cv=$3
labels_tr=$4
labels_cv=$5
dir=$6

[ ! -d $dir ] && mkdir $dir
[ ! -d $dir/log ] && mkdir $dir/log
[ ! -d $dir/nnet ] && mkdir $dir/nnet

# Skip training
[ -e $dir/final.nnet ] && echo "'$dir/final.nnet' exists, skipping training" && exit 0


##############################
#start training

# choose mlp to start with
mlp_best=$mlp_init
mlp_base=${mlp_init##*/}; mlp_base=${mlp_base%.*}
# optionally resume training from the best epoch
[ -e $dir/.mlp_best ] && mlp_best=$(cat $dir/.mlp_best)
[ -e $dir/.learn_rate ] && learn_rate=$(cat $dir/.learn_rate)

[ ! -z "$subnnet_ids" ] && subnnet_ids_arg="ark:$subnnet_ids"     # this is for multi_nnet_training

# cross-validation on original network
$train_tool --cross-validate=true \
 --minibatch-size=$minibatch_size --randomizer-size=$randomizer_size --verbose=$verbose \
 ${feature_transform:+ --feature-transform=$feature_transform} \
 ${feature_transform_list:+ --feature-transform-list=$feature_transform_list} \
 "$feats_cv" "$labels_cv" $subnnet_ids_arg $mlp_best \
 2> $dir/log/iter00.initial.log || exit 1;

loss=$(cat $dir/log/iter00.initial.log | grep "AvgLoss:" | tail -n 1 | awk '{ print $4; }')
loss_type=$(cat $dir/log/iter00.initial.log | grep "AvgLoss:" | tail -n 1 | awk '{ print $5; }')
echo "CROSSVAL PRERUN AVG.LOSS $(printf "%.4f" $loss) $loss_type"

if [ $lr_schedule == 'halve' ]; then
  # resume lr-halving
  halving=0
  [ -e $dir/.halving ] && halving=$(cat $dir/.halving)
  nnet_learn_rate=$learn_rate
fi

# training
for iter in $(seq -w $max_iters); do
  echo -n "ITERATION $iter: "
  mlp_next=$dir/nnet/${mlp_base}_iter${iter}

  if [ $lr_schedule == 'fixed' ]; then
    nnet_learn_rate=$(echo $learn_rate | tr ':' ' ' | awk -v i=$iter '{if(i < NF) print $i; else print $NF}')
  elif [ $lr_schedule == 'exp' ]; then
    final_learn_rate=$(echo "scale=5;$learn_rate*$learn_rate_shrink" | bc)
    nnet_learn_rate=$(perl -e '($x,$n,$i,$f)=@ARGV; $x=$x-1; $n=$n-1; print ($x >= $n ? $f : $i*exp($x*log($f/$i)/$n));' $iter $max_iters $learn_rate $final_learn_rate)
  fi
  
  # skip iteration if already done
  if [ -e $dir/.done_iter$iter ]; then 
    mlp_next=$(ls ${mlp_next}*| tr '/' ' ' | awk '{print $NF}')
    perl -e '$line = $ARGV[0]; if ($line =~ /rejected/) { $accrej = "rejected"; } else {$accrej = "accepted";}; $line =~ /.*\/([^\/]+)/; $nnet = $1; $line =~/.*learnrate([^_]+)_tr([^_]+)_cv([^_]+)/; printf "TRAIN AVG.LOSS %.4f, (lrate%s), CROSSVAL AVG.LOSS %.4f, nnet %s (%s) skipping...\n", $2, $1, $3, $accrej, $nnet;' $mlp_next
    continue
  fi
  iter_reduce_type=$reduce_type
  num_iter=$(echo $iter | awk '{printf "%d", $1}')
  if [ "$reduce_type" == butterfly ] && [ $num_iter == 1 ] ; then
    iter_reduce_type=allreduce
  fi

  # training
  [ ! -z "$frame_weights" ] && frame_weights_opt="--frame-weights=ark:$frame_weights"
  $train_tool \
   --learn-rate=$nnet_learn_rate --momentum=$momentum --l1-penalty=$l1_penalty --l2-penalty=$l2_penalty \
   --minibatch-size=$minibatch_size --randomizer-size=$randomizer_size --randomize=true --verbose=$verbose \
   --binary=true $frame_weights_opt \
   ${semi_layers:+ --semi-layers=$semi_layers} \
   ${updatable_layers:+ --updatable-layers=$updatable_layers} \
   ${reduce_per_iter_tr:+ --max-reduce-count=$reduce_per_iter_tr} \
   ${iter_reduce_type:+ --reduce-type=$iter_reduce_type} \
   ${reduce_content:+ --reduce-content=$reduce_content} \
   ${frames_per_reduce:+ --frames-per-reduce=$frames_per_reduce} \
   ${feature_transform:+ --feature-transform=$feature_transform} \
   ${feature_transform_list:+ --feature-transform-list=$feature_transform_list} \
   ${randomizer_seed:+ --randomizer-seed=$randomizer_seed} \
   "$feats_tr" "$labels_tr" $subnnet_ids_arg $mlp_best $mlp_next \
   2> $dir/log/iter${iter}.tr.log || exit 1; 

  tr_loss=$(cat $dir/log/iter${iter}.tr.log | grep "AvgLoss:" | tail -n 1 | awk '{ print $4; }')
  echo -n "TRAIN AVG.LOSS $(printf "%.4f" $tr_loss), (lrate$(printf "%.6g" $nnet_learn_rate)), "
  
  # cross-validation
  $train_tool --cross-validate=true \
   --minibatch-size=$minibatch_size --randomizer-size=$randomizer_size --verbose=$verbose \
   ${feature_transform:+ --feature-transform=$feature_transform} \
   ${feature_transform_list:+ --feature-transform-list=$feature_transform_list} \
   "$feats_cv" "$labels_cv" $subnnet_ids_arg $mlp_next \
   2>$dir/log/iter${iter}.cv.log || exit 1;

  loss_new=$(cat $dir/log/iter${iter}.cv.log | grep "AvgLoss:" | tail -n 1 | awk '{ print $4; }')
  echo -n "CROSSVAL AVG.LOSS $(printf "%.4f" $loss_new), "

  # accept or reject new parameters (based on objective function)
  loss_prev=$loss
  if [ "1" == "$(awk "BEGIN{print($loss_new<$loss);}")" ] || [ $lr_schedule == "fixed" ] || [ $lr_schedule == "exp" ]; then
    loss=$loss_new
    mlp_best=$dir/nnet/${mlp_base}_iter${iter}_learnrate${nnet_learn_rate}_tr$(printf "%.4f" $tr_loss)_cv$(printf "%.4f" $loss_new)
    mv $mlp_next $mlp_best
    echo "nnet accepted ($(basename $mlp_best))"
    echo $mlp_best > $dir/.mlp_best 
  else
    mlp_reject=$dir/nnet/${mlp_base}_iter${iter}_learnrate${nnet_learn_rate}_tr$(printf "%.4f" $tr_loss)_cv$(printf "%.4f" $loss_new)_rejected
    mv $mlp_next $mlp_reject
    echo "nnet rejected ($(basename $mlp_reject))"
  fi

  # create .done file as a mark that iteration is over
  touch $dir/.done_iter$iter

  if [ $lr_schedule == 'halve' ]; then
    # stopping criterion
    if [[ "1" == "$halving" && "1" == "$(awk "BEGIN{print(($loss_prev-$loss)/$loss_prev < $end_halving_impr)}")" ]]; then
      if [[ "$min_iters" != "" ]]; then
        if [ $min_iters -gt $iter ]; then
          echo we were supposed to finish, but we continue, min_iters : $min_iters
          continue
        fi
      fi
      echo finished, too small rel. improvement $(awk "BEGIN{print(($loss_prev-$loss)/$loss_prev)}")
      break
    fi

    # start annealing when improvement is low
    if [ "1" == "$(awk "BEGIN{print(($loss_prev-$loss)/$loss_prev < $start_halving_impr)}")" ]; then
      halving=1
      echo $halving >$dir/.halving
    fi
    
    # do annealing
    if [ "1" == "$halving" ]; then
      nnet_learn_rate=$(awk "BEGIN{print($nnet_learn_rate*$halving_factor)}")
      echo $nnet_learn_rate >$dir/.learn_rate
      if [ $resume_anneal == true ]; then
        halving=0
        echo $halving >$dir/.halving
      fi
    fi
  fi
done

# select the best network
if [ $mlp_best != $mlp_init ]; then 
  mlp_final=${mlp_best}_final_
  ( cd $dir/nnet; ln -s $(basename $mlp_best) $(basename $mlp_final); )
  ( cd $dir; ln -s nnet/$(basename $mlp_final) final.nnet; )
  echo "Succeeded training the Neural Network : $dir/final.nnet"
else
  "Error training neural network..."
  exit 1
fi

}
