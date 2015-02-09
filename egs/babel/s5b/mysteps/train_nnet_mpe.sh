#!/bin/bash
# Copyright 2013  Brno University of Technology (Author: Karel Vesely)  
# Copyright 2014  International Computer Science Institute (Author: Hang Su)
# Apache 2.0.

# Sequence-discriminative MPE/sMBR training of DNN.
# 4 iterations (by default) of Stochastic Gradient Descent with per-utterance updates.
# We select between MPE/sMBR optimization by '--do-smbr <bool>' option.

# For the numerator we have a fixed alignment rather than a lattice--
# this actually follows from the way lattices are defined in Kaldi, which
# is to have a single path for each word (output-symbol) sequence.

{

set -e
set -o pipefail

# Begin configuration section.
cmd=run.pl
num_iters=4
acwt=0.1
lmwt=1.0
learn_rate=0.00001
halving_factor=1.0 #ie. disable halving
do_smbr=true
use_silphones=false #setting this to something will enable giving siphones to nnet-mpe
verbose=1
transform_dir=
scp_splits=
seed=777    # seed value used for training data shuffling
# End configuration section

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $# -ne 6 ]; then
  echo "Usage: steps/$0 <data> <lang> <srcdir> <ali> <denlats> <exp>"
  echo " e.g.: steps/$0 data/train_all data/lang exp/tri3b_dnn exp/tri3b_dnn_ali exp/tri3b_dnn_denlats exp/tri3b_dnn_smbr"
  echo "Main options (for others, see top of script file)"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --config <config-file>                           # config containing options"
  echo "  --num-iters <N>                                  # number of iterations to run"
  echo "  --acwt <float>                                   # acoustic score scaling"
  echo "  --lmwt <float>                                   # linguistic score scaling"
  echo "  --learn-rate <float>                             # learning rate for NN training"
  echo "  --do-smbr <bool>                                 # do sMBR training, otherwise MPE"
  echo "  --transform-dir <transform-dir>                  # directory to find fMLLR transforms."
  
  exit 1;
fi

data=$1
lang=$2
srcdir=$3
alidir=$4
denlatdir=$5
dir=$6
mkdir -p $dir/log

for f in $data/feats.scp $alidir/{tree,final.mdl,ali.1.gz} $denlatdir/lat.scp $srcdir/{final.nnet,final.feature_transform}; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

mkdir -p $dir/log

cp $alidir/{final.mdl,tree} $dir

silphonelist=`cat $lang/phones/silence.csl` || exit 1;


#Get the files we will need
nnet=$srcdir/$(readlink $srcdir/final.nnet || echo final.nnet);
[ -z "$nnet" ] && echo "Error nnet '$nnet' does not exist!" && exit 1;
cp $nnet $dir/0.nnet; nnet=$dir/0.nnet

class_frame_counts=$srcdir/ali_train_pdf.counts
[ -z "$class_frame_counts" ] && echo "Error class_frame_counts '$class_frame_counts' does not exist!" && exit 1;
cp $srcdir/ali_train_pdf.counts $dir

feature_transform=$srcdir/final.feature_transform
if [ ! -f $feature_transform ]; then
  echo "Missing feature_transform '$feature_transform'"
  exit 1
fi
cp $feature_transform $dir/final.feature_transform

model=$dir/final.mdl
[ -z "$model" ] && echo "Error transition model '$model' does not exist!" && exit 1;

#enable/disable silphones from MPE training
mpe_silphones_arg= #empty
[ "$use_silphones" == "true" ] && mpe_silphones_arg="--silence-phones=$silphonelist"

###### PREPARE FEATURES ######

# shuffle the list
echo "Preparing train/cv lists"
cat $data/feats.scp | utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.scp
echo
echo "# PREPARING FEATURES"
#read the features
if [ -z $feat_type ]; then
  if [ -f $alidir/final.mat ]; then feat_type=lda; else feat_type=delta; fi
fi
echo "$0: feature type is $feat_type"

case $feat_type in
  delta) feats="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.scp ark:- | add-deltas ark:- ark:- |"
   ;;
  raw) feats="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.scp ark:- |"
   ;;
  lda) feats="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $dir/final.mat ark:- ark:- |"
    cp $alidir/final.mat $dir    
    ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac

if [ ! -z $transform_dir ]; then
  if [ -f $transform_dir/trans.1 ] && [ $feat_type != "raw" ]; then
    echo "$0: using transforms from $transform_dir"
    feats="$feats transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $transform_dir/trans.*|' ark:- ark:- |"
  fi
  if [ -f $transform_dir/raw_trans.1 ] && [ $feat_type == "raw" ]; then
    echo "$0: using raw-fMLLR transforms from $transform_dir"
    feats="$feats transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $transform_dir/raw_trans.*|' ark:- ark:- |"
  fi
fi

#re-save the shuffled features, so they are stored sequentially on the disk in /tmp/
echo "Resaving the features for rbm training"
tmpdir=$dir/feature_shuffled; mkdir -p $tmpdir; 
copy-feats "$feats" ark,scp:$tmpdir/feats.ark,$dir/train.scp
#remove data on exit...
trap "echo \"Removing features tmpdir $tmpdir @ $(hostname)\"; rm -r $tmpdir" EXIT

if [ ! -z $scp_splits ]; then
  split_scps=""
  for ((n=1; n<=scp_splits; n++)); do
    split_scps="$split_scps $dir/train.scp.$n"
  done
  utils/split_scp.pl $dir/train.scp $split_scps
fi

feats="ark,s,cs:copy-feats scp:$dir/train.scp ark:- |"
echo "Substitute feats with $feats"

###
### Prepare the alignments
### 
# Assuming all alignments will fit into memory
ali="ark:gunzip -c $alidir/ali.*.gz |"


###
### Prepare the lattices
###
# The lattices are indexed by SCP (they are not gziped because of the random access in SGD)
lats="scp:$denlatdir/lat.scp"


# Run several iterations of the MPE/sMBR training
cur_mdl=$nnet
x=1
while [ $x -le $num_iters ]; do
  echo "Pass $x (learnrate $learn_rate)"
  if [ -f $dir/$x.nnet ]; then
    echo "Skipped, file $dir/$x.nnet exists"
  else
    if [ -z $scp_splits ]; then
    #train
    $cmd $dir/log/mpe.$x.log \
     nnet-train-mpe-sequential \
       --feature-transform=$feature_transform \
       --class-frame-counts=$class_frame_counts \
       --acoustic-scale=$acwt \
       --lm-scale=$lmwt \
       --learn-rate=$learn_rate \
       --do-smbr=$do_smbr \
       --verbose=$verbose \
       $mpe_silphones_arg \
       $cur_mdl $alidir/final.mdl "$feats" "$lats" "$ali" $dir/$x.nnet || exit 1
    else
      y=1
      while [ $y -le $scp_splits ]; do
        echo "Sub pass $y (learnrate $learn_rate)"
        if [ -f $dir/$x.$y.nnet ]; then
          echo "Skipped, file $dir/$x.$y.nnet exists"
        else
          yfeats=$(echo $feats | sed "s#train.scp#train.scp.$y#")

          $cmd $dir/log/mpe.$x.$y.log \
           nnet-train-mpe-sequential \
             --feature-transform=$feature_transform \
             --class-frame-counts=$class_frame_counts \
             --acoustic-scale=$acwt \
             --lm-scale=$lmwt \
             --learn-rate=$learn_rate \
             --do-smbr=$do_smbr \
             --verbose=$verbose \
             $mpe_silphones_arg \
             $cur_mdl $alidir/final.mdl "$yfeats" "$lats" "$ali" $dir/$x.$y.nnet || exit 1
        fi
        cur_mdl=$dir/$x.$y.nnet

        #report the progress
        grep -B 2 "Overall average frame-accuracy" $dir/log/mpe.$x.$y.log | sed -e 's|.*)||'

        y=$((y+1))
      done
      (cd $dir; ln -s $cur_mdl $x.nnet)
    fi
  fi
  cur_mdl=$dir/$x.nnet

  #report the progress
  grep -B 2 "Overall average frame-accuracy" $dir/log/mpe.$x.log | sed -e 's|.*)||'

  x=$((x+1))
  learn_rate=$(awk "BEGIN{print($learn_rate*$halving_factor)}")
  
done

(cd $dir; [ -e final.nnet ] && unlink final.nnet; ln -s $((x-1)).nnet final.nnet)

echo "MPE/sMBR training finished"



exit 0
}
