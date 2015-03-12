#!/bin/bash

# Copyright 2012/2013  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0
{
set -o pipefail

# Begin configuration.
config=            # config, which is also sent to all other scripts

# NETWORK INITIALIZATION
mlp_init=          # select initialized MLP (override initialization)
mlp_proto=         # select network prototype (initialize it)
proto_opts=        # non-default options for 'make_nnet_proto.py'
feature_transform= # provide feature transform (=splice,rescaling,...) (don't build new one)
#
hid_layers=4       # nr. of hidden layers (prior to sotfmax or bottleneck)
hid_dim=1024       # select hidden dimension
bn_dim=            # set a value to get a bottleneck network
dbn=               # select DBN to prepend to the MLP initialization
#
init_opts=         # options, passed to the initialization script

# FEATURE PROCESSING
# feature config (applies always)
apply_cmvn=false # apply normalization to input features?
norm_vars=false # use variance normalization?
delta_order=
# feature_transform:
splice=5         # temporal splicing
splice_step=1    # stepsize of the splicing (1 == no gap between frames)
feat_type=       # traps?
# feature config (applies to feat_type traps)
traps_dct_basis=11 # nr. od DCT basis (applies to `traps` feat_type, splice10 )
# feature config (applies to feat_type transf) (ie. LDA+MLLT, no fMLLR)
transf=
splice_after_transf=5
# feature config (applies to feat_type lda)
lda_dim=300        # LDA dimension (applies to `lda` feat_type)

# LABELS
labels=            # use these labels to train (override deafault pdf alignments) 
num_tgt=           # force to use number of outputs in the MLP (default is autodetect)

# TRAINING SCHEDULER
learn_rate=0.008   # initial learning rate
train_opts=        # options, passed to the training script
train_tool=        # optionally change the training tool

# OTHER
use_gpu_id= # manually select GPU id to run on, (-1 disables GPU)
seed=777    # seed value used for training data shuffling and initialization
cv_subset_factor=0.1
uttbase=true    # by default, we choose last 10% utterances for CV
resume_anneal=true
# semi-supervised training
supcopy=1
semidata=
semialidir=
semitransdir=
semi_layers=-1
multi_split=0

# End configuration.

echo "$0 $@"  # Print the command line for logging

. path.sh || exit 1;
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "Usage: $0 <data-dir> <ali-dir> <exp-dir>"
   echo " e.g.: $0 data/train exp/mono_ali exp/mono_nnet"
   echo "main options (for others, see top of script file)"
   echo "  --config <config-file>  # config containing options"
   exit 1;
fi

data=$1
alidir=$2
dir=$3


for f in $alidir/frame_subnnet_ids.ark $alidir/post.info $data/feats.scp; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

echo
echo "# INFO"
echo "$0 : Training Neural Network"
printf "\t dir       : $dir \n"
printf "\t Train-set : $data $alidir \n"

mkdir -p $dir/{log,nnet}

# skip when already trained
[ -e $dir/final.nnet ] && printf "\nSKIPPING TRAINING... ($0)\nnnet already trained : $dir/final.nnet ($(readlink $dir/final.nnet))\n\n" && exit 0

###### PREPARE ALIGNMENTS ######
echo
echo "# PREPARING ALIGNMENTS"
if [ ! -z $labels ]; then
  echo "Using targets '$labels' (by force)"
  labels_tr="$labels"
  labels_cv="$labels"
else
  # this is for multi softmax semi-supervised training
  echo "Using PDF targets from dirs '$alidir'"
  # define pdf-alignment rspecifiers
  labels_tr_ali="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark:- |" # for analyze-counts.
  labels_tr="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark,t:- | ali-to-post ark,t:- ark:- |"
  labels_cv="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark,t:- | ali-to-post ark,t:- ark:- |"

  if [ ! -z $semialidir ]; then
    labels_tr_ali="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz $semialidir/ali.*.gz |\" ark:- |" # for analyze-counts.
    labels_tr="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz $semialidir/ali.*.gz |\" ark,t:- | ali-to-post ark,t:- ark:- |"
  fi

  # get pdf-counts, used later to post-process DNN posteriors
  analyze-counts --binary=false "$labels_tr_ali" $dir/ali_train_pdf.counts || exit 1
  # copy the old transition model, will be needed by decoder
  copy-transition-model --binary=false $alidir/final.mdl $dir/final.mdl || exit 1
  # copy the tree
  cp $alidir/tree $dir/tree || exit 1
fi

# shuffle the list
echo "Preparing train/cv lists :"
num_utts_all=$(wc $data/feats.scp | awk '{print $1}')
num_utts_subset=$(awk "BEGIN {print(int( $num_utts_all * $cv_subset_factor))}")

if [ $uttbase == true ]; then
  tail -$num_utts_subset $data/feats.scp > $dir/shuffle.cv.scp
  cat $data/feats.scp | utils/filter_scp.pl --exclude $dir/shuffle.cv.scp | utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.train.scp
else
  cat $data/feats.scp | utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.scp
  head -$num_utts_subset $dir/shuffle.scp > $dir/shuffle.cv.scp
  cat $dir/shuffle.scp | utils/filter_scp.pl --exclude $dir/shuffle.cv.scp > $dir/shuffle.train.scp
fi

if [ ! -z "$semidata" ]; then
  echo "Preparing semi-supervised lists"
  [ -f $dir/sup.train.copy.scp ] && rm -f $dir/sup.train.copy.scp
  echo "Copy supervised data for $supcopy times"
  for ((c = 1; c <= $supcopy; c++))
  do
    cat $dir/shuffle.train.scp >> $dir/sup.train.copy.scp
  done
  cat $semidata/feats.scp $dir/sup.train.copy.scp | utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.semitrain.scp
  cat $semidata/utt2spk $data/utt2spk | sort > $dir/semitrain.utt2spk
  cat $semidata/cmvn.scp $data/cmvn.scp | sort > $dir/semitrain.cmvn.scp
  (set -e;
   cd $dir
   if [ ! -f cmvn.scp ]; then
     ln -s semitrain.cmvn.scp cmvn.scp
     ln -s semitrain.utt2spk utt2spk; 
     mv shuffle.train.scp shuffle.train.scp.bak; 
     ln -s shuffle.semitrain.scp shuffle.train.scp
   fi
  )
    
  data=$dir
fi

###### PREPARE FEATURES ######
echo
echo "# PREPARING FEATURES"
#read the features
if [ -z $feat_type ]; then
  if [ -f $alidir/final.mat ]; then feat_type=lda; else feat_type=delta; fi
  echo "$0: feature type is $feat_type"

  case $feat_type in
    delta) feats_tr="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.train.scp ark:- | add-deltas ark:- ark:- |"
           feats_cv="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.cv.scp ark:- | add-deltas ark:- ark:- |"
     ;;
    raw) feats_tr="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.train.scp ark:- |"
         feats_cv="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.cv.scp ark:- |"
     ;;
    lda) feats_tr="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.train.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $dir/final.mat ark:- ark:- |"
         feats_cv="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.cv.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $dir/final.mat ark:- ark:- |"
      cp $alidir/final.mat $dir    
     ;;
    fmllr) feats="scp:$dir/shuffle.scp"
     ;;
    *) echo "$0: invalid feature type $feat_type" && exit 1;
  esac

  if [ -f $alidir/trans.1 ] && [ $feat_type != "raw" ]; then
    echo "$0: using transforms from $alidir"
    feats_cv="$feats_cv transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $alidir/trans.*|' ark:- ark:- |"
    if [ -z $semitransdir ]; then
      feats_tr="$feats_tr transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $alidir/trans.*|' ark:- ark:- |"
    else
      echo "$0: also using transform from $semitransdir for semi data"
      feats_tr="$feats_tr transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $alidir/trans.* $semitransdir/trans.* |' ark:- ark:- |"
    fi
  fi
  if [ -f $alidir/raw_trans.1 ] && [ $feat_type == "raw" ]; then
    echo "$0: using raw-fMLLR transforms from $alidir"
    feats_tr="$feats_tr transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $alidir/raw_trans.*|' ark:- ark:- |"
    feats_cv="$feats_cv transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $alidir/raw_trans.*|' ark:- ark:- |"
  fi
else
  feats_tr="ark:copy-feats scp:$dir/shuffle.train.scp ark:- |"
  feats_cv="ark:copy-feats scp:$dir/shuffle.cv.scp ark:- |"
fi

#get feature dim
echo -n "Getting feature dim : "
feat_dim=$(feat-to-dim "$feats_tr" -)
echo $feat_dim

# re-save the shuffled features, so they are stored sequentially on the disk in /tmp/
tmpdir=$dir/feature_shuffled; mkdir -p $tmpdir; 
copy-feats "$feats_tr" ark,scp:$tmpdir/feats.tr.ark,$dir/train.scp
copy-feats "$feats_cv" ark,scp:$tmpdir/feats.cv.ark,$dir/cv.scp
# remove data on exit...
trap "echo \"Removing features tmpdir $tmpdir @ $(hostname)\"; rm -r $tmpdir" EXIT

#create a 10k utt subset for global cmvn estimates
head -n 10000 $dir/train.scp > $dir/train.scp.10k

# print the list sizes
wc -l $dir/train.scp $dir/cv.scp

###### PREPARE FEATURE PIPELINE ######
# read the features
feats_tr="ark:copy-feats scp:$dir/train.scp ark:- |"
feats_cv="ark:copy-feats scp:$dir/cv.scp ark:- |"
echo substituting feats_tr with $feats_tr
echo substituting feats_cv with $feats_cv

# get feature dim
echo "Getting feature dim : "
feats_tr1=$(echo $feats_tr | sed -e "s#scp:$dir/train.scp#\"scp:head -1 $dir/train.scp |\"#g")
feat_dim=$(feat-to-dim --print-args=false "$feats_tr1" -)
echo "Feature dim is : $feat_dim"

# Now we will start building complex feature_transform which will 
# be forwarded in CUDA to have fast run-time.
#
# We will use 1GPU for both feature_transform and MLP training in one binary tool. 
# This is against the kaldi spirit to have many independent small processing units, 
# but it is necessary because of compute exclusive mode, where GPU cannot be shared
# by multiple processes.

if [ ! -z "$feature_transform" ]; then
  echo "Using pre-computed feature-transform : '$feature_transform'"
  tmp=$dir/$(basename $feature_transform) 
  cp $feature_transform $tmp; feature_transform=$tmp
else
  # Generate the splice transform
  echo "Using splice +/- $splice , step $splice_step"
  feature_transform=$dir/tr_splice$splice-$splice_step.nnet
  utils/nnet/gen_splice.py --fea-dim=$feat_dim --splice=$splice --splice-step=$splice_step > $feature_transform

  # Choose further processing of spliced features
  echo "Feature type : $feat_type"
  case $feat_type in
    plain)
    ;;
    traps)
      #generate hamming+dct transform
      feature_transform_old=$feature_transform
      feature_transform=${feature_transform%.nnet}_hamm_dct${traps_dct_basis}.nnet
      echo "Preparing Hamming DCT transform into : $feature_transform"
      #prepare matrices with time-transposed hamming and dct
      utils/nnet/gen_hamm_mat.py --fea-dim=$feat_dim --splice=$splice > $dir/hamm.mat
      utils/nnet/gen_dct_mat.py --fea-dim=$feat_dim --splice=$splice --dct-basis=$traps_dct_basis > $dir/dct.mat
      #put everything together
      compose-transforms --binary=false $dir/dct.mat $dir/hamm.mat - | \
        transf-to-nnet - - | \
        nnet-concat --binary=false $feature_transform_old - $feature_transform || exit 1
    ;;
    transf)
      feature_transform_old=$feature_transform
      feature_transform=${feature_transform%.nnet}_transf_splice${splice_after_transf}.nnet
      [ -z $transf ] && $alidir/final.mat
      [ ! -f $transf ] && echo "Missing transf $transf" && exit 1
      feat_dim=$(feat-to-dim "$feats_tr1 nnet-forward 'nnet-concat $feature_transform_old \"transf-to-nnet $transf - |\" - |' ark:- ark:- |" -)
      nnet-concat --binary=false $feature_transform_old \
        "transf-to-nnet $transf - |" \
        "utils/nnet/gen_splice.py --fea-dim=$feat_dim --splice=$splice_after_transf |" \
        $feature_transform || exit 1
    ;;
    lda)
      echo "LDA transform applied already!";
    ;;
    *)
      echo "Unknown feature type $feat_type"
      exit 1;
    ;;
  esac
  # keep track of feat_type
  echo $feat_type > $dir/feat_type

  # Renormalize the MLP input to zero mean and unit variance
  feature_transform_old=$feature_transform
  feature_transform=${feature_transform%.nnet}_cmvn-g.nnet
  echo "Renormalizing MLP input features into $feature_transform"
  nnet-forward --use-gpu=yes \
    $feature_transform_old "$(echo $feats_tr | sed 's|train.scp|train.scp.10k|')" \
    ark:- 2>$dir/log/nnet-forward-cmvn.log |\
  compute-cmvn-stats ark:- - | cmvn-to-nnet - - |\
  nnet-concat --binary=false $feature_transform_old - $feature_transform
fi

###### MAKE LINK TO THE FINAL feature_transform, so the other scripts will find it ######
(cd $dir; [ ! -f final.feature_transform ] && ln -s $(basename $feature_transform) final.feature_transform )

###### INITIALIZE THE NNET ######
echo 
echo "# NN-INITIALIZATION"
[ ! -z "$mlp_init" ] && echo "Using pre-initialized network '$mlp_init'";
if [ ! -z "$mlp_proto" ]; then 
  echo "Initializing using network prototype '$mlp_proto'";
  mlp_init=$dir/nnet.init; log=$dir/log/nnet_initialize.log
  nnet-initialize $mlp_proto $mlp_init 2>$log || { cat $log; exit 1; } 
fi
if [[ -z "$mlp_init" && -z "$mlp_proto" ]]; then
  echo "Getting input/output dims :"
  #initializing the MLP, get the i/o dims...
  #input-dim
  num_fea=$(feat-to-dim "$feats_tr1 nnet-forward $feature_transform ark:- ark:- |" - )
  { #optioanlly take output dim of DBN
    [ ! -z $dbn ] && num_fea=$(nnet-forward "nnet-concat $feature_transform $dbn -|" "$feats_tr1" ark:- | feat-to-dim ark:- -)
    [ -z "$num_fea" ] && echo "Getting nnet input dimension failed!!" && exit 1
  }

  count_subnnet=0
  subnnets=""
  while read line ;do 
    countnew=$(($countold + 1))
    num_tgt=$(echo $line | awk '{print $NF}')
    mlp_proto=$dir/nnet.proto.${count_subnnet}
    echo "Genrating network prototype $mlp_proto"
    myutils/nnet/make_nnet_proto.py $proto_opts \
      ${bn_dim:+ --bottleneck-dim=$bn_dim} \
      $num_fea $num_tgt $hid_layers $hid_dim >$mlp_proto || exit 1
    mlp_init=$dir/nnet.init.$count_subnnet; log=$dir/log/nnet_initialize.${count_subnnet}.log
    echo "Initializing $mlp_proto -> $mlp_init"
    nnet-initialize $mlp_proto $mlp_init 2>$log || { cat $log; exit 1; }
    subnnets="${subnnets} ${mlp_init}"
    count_subnnet=$(($count_subnnet+1))
  done < $alidir/post.info
  mlp_init=$dir/multi_nnet.init
  nnet-to-multi-nnet $dbn $subnnets $mlp_init
  if [ $multi_split != 0 ]; then
    multi-nnet-split $mlp_init 0 $multi_split $mlp_init.split
    mlp_init=$mlp_init.split
  fi
fi

###### TRAIN ######
echo
echo "# RUNNING THE NN-TRAINING SCHEDULER"
mysteps/train_nnet_scheduler.sh \
  --feature-transform $feature_transform \
  --learn-rate $learn_rate \
  --randomizer-seed $seed \
  --resume-anneal $resume_anneal \
  --semi-layers $semi_layers \
  --train_tool multi-nnet-train-frmshuff \
  --subnnet-ids $alidir/frame_subnnet_ids.ark \
  ${train_opts} \
  ${train_tool:+ --train-tool "$train_tool"} \
  ${config:+ --config $config} \
  $mlp_init "$feats_tr" "$feats_cv" "$labels_tr" "$labels_cv" $dir || exit 1


echo "$0 successfuly finished.. $dir"

sleep 3
exit 0
}
