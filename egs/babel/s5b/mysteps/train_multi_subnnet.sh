#!/bin/bash

# Copyright 2012/2013  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0
{
set -e
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
featlist=

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

[ -z "$featlist" ] && featlist=$dir/feat.list

for f in $alidir/ali.1.gz $data/feats.scp $featlist; do
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
  echo "Using PDF targets from dirs '$alidir'"
  # define pdf-alignment rspecifiers
  labels_tr_ali="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark:- |" # for analyze-counts.
  labels_tr="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark,t:- | ali-to-post ark,t:- ark:- |"
  labels_cv="ark:ali-to-pdf $alidir/final.mdl \"ark:gunzip -c $alidir/ali.*.gz |\" ark,t:- | ali-to-post ark,t:- ark:- |"

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

ori_feat=$(head -n 1 $featlist)
echo "ori_feat is $ori_feat"
for i in `cat $featlist`; do
  echo "adding feat: $i"
  featdata=$(echo $data | sed -e "s#$ori_feat#$i#g")
  if [ $uttbase == true ]; then
    tail -$num_utts_subset $featdata/feats.scp > $dir/shuffle.$i.cv.scp
    cat $featdata/feats.scp | utils/filter_scp.pl --exclude $dir/shuffle.$i.cv.scp | utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.$i.train.scp
  else
    cat $featdata/feats.scp | utils/shuffle_list.pl --srand ${seed:-777} > $dir/shuffle.$i.scp
    head -$num_utts_subset $dir/shuffle.$i.scp > $dir/shuffle.$i.cv.scp
    cat $dir/shuffle.$i.scp | utils/filter_scp.pl --exclude $dir/shuffle.$i.cv.scp > $dir/shuffle.$i.train.scp
  fi
done

###### PREPARE FEATURES ######
echo
echo "# PREPARING FEATURES"
#read the features
if [ -z $feat_type ]; then
  if [ -f $alidir/final.mat ]; then feat_type=lda; else feat_type=delta; fi
fi

echo "$0: feature type is $feat_type"

case $feat_type in
  delta) feats_tr="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.$ori_feat.train.scp ark:- | add-deltas ark:- ark:- |"
         feats_cv="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.$ori_feat.cv.scp ark:- | add-deltas ark:- ark:- |"
   ;;
  raw) feats_tr="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.$ori_feat.train.scp ark:- |"
       feats_cv="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.$ori_feat.cv.scp ark:- |"
   ;;
  lda) feats_tr="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.$ori_feat.train.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $alidir/final.mat ark:- ark:- |"
       feats_cv="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:$data/utt2spk scp:$data/cmvn.scp scp:$dir/shuffle.$ori_feat.cv.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $alidir/final.mat ark:- ark:- |"
   ;;
  fmllr) feats_tr="scp:$dir/shuffle.$ori_feat.train.scp"
         feats_cv="scp:$dir/shuffle.$ori_feat.cv.scp"
   ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac

if [ -f $alidir/trans.1 ] && [ $feat_type == "lda" ]; then
  echo "$0: using transforms from $alidir"
  feats_cv="$feats_cv transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $alidir/trans.*|' ark:- ark:- |"
  feats_tr="$feats_tr transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $alidir/trans.*|' ark:- ark:- |"
fi
if [ -f $alidir/raw_trans.1 ] && [ $feat_type == "raw" ]; then
  echo "$0: using raw-fMLLR transforms from $alidir"
  feats_tr="$feats_tr transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $alidir/raw_trans.*|' ark:- ark:- |"
  feats_cv="$feats_cv transform-feats --utt2spk=ark:$data/utt2spk 'ark:cat $alidir/raw_trans.*|' ark:- ark:- |"
fi

[ -f $dir/feats.list ] && rm -f $dir/feats.list

# re-save the shuffled features, so they are stored sequentially on the disk in /tmp/
tmpdir=$dir/feature_shuffled; mkdir -p $tmpdir; 
# remove data on exit...
trap "echo \"Removing features tmpdir $tmpdir @ $(hostname)\"; rm -r $tmpdir" EXIT

[ -f $dir/feats.tr.list ] && rm -f $dir/feats.tr.list
[ -f $dir/feats.cv.list ] && rm -f $dir/feats.cv.list
for i in `cat $featlist`; do
  this_feats_tr=$(echo "$feats_tr" | sed -e "s#$ori_feat#$i#g")
  this_feats_cv=$(echo "$feats_cv" | sed -e "s#$ori_feat#$i#g")
  
  #get feature dim
  echo -n "Getting feature dim of $i: "
  feat_dim=$(feat-to-dim "$this_feats_tr" -)
  echo $feat_dim

  copy-feats "$this_feats_tr" ark,scp:$tmpdir/feats.$i.tr.ark,$dir/$i.train.scp
  copy-feats "$this_feats_cv" ark,scp:$tmpdir/feats.$i.cv.ark,$dir/$i.cv.scp

  #create a 10k utt subset for global cmvn estimates
  head -n 10000 $dir/$i.train.scp > $dir/$i.train.scp.10k

  # print the list sizes
  wc -l $dir/$i.train.scp $dir/$i.cv.scp
  
  # read the features
  this_feats_tr="ark:copy-feats scp:$dir/$i.train.scp ark:- |"
  this_feats_cv="ark:copy-feats scp:$dir/$i.cv.scp ark:- |"
  echo $this_feats_tr >> $dir/feats.tr.list
  echo $this_feats_cv >> $dir/feats.cv.list
done

feats_tr="ark:copy-feats scp:$dir/$ori_feat.train.scp ark:- |"
feats_cv="ark:copy-feats scp:$dir/$ori_feat.cv.scp ark:- |"
feats_tr1=$(echo $feats_tr | sed -e "s#scp:$dir/$ori_feat.train.scp#\"scp:head -1 $dir/$i.train.scp |\"#g")

###### PREPARE FEATURE PIPELINE ######
# Now we will start building complex feature_transform which will 
# be forwarded in CUDA to have fast run-time.
#
# We will use 1GPU for both feature_transform and MLP training in one binary tool. 
# This is against the kaldi spirit to have many independent small processing units, 
# but it is necessary because of compute exclusive mode, where GPU cannot be shared
# by multiple processes.

[ -z "$feature_transform" ] || feature_transform_list=$dir/feature_transforms.list
[ -z "$feature_transform_list" ] || [ -f $feature_transform_list ] && rm $feature_transform_list

for i in `cat $featlist`; do
  if [ ! -z "$feature_transform" ]; then
    this_feature_transform=$(echo $feature_transform | sed -e  "s#$ori_feat#$i#g")
    echo "Using pre-computed feature-transform : '$this_feature_transform'"
    tmp=$dir/$i.$(basename $this_feature_transform) 
    cp $this_feature_transform $tmp; this_feature_transform=$tmp
  else
    echo "not supported yet, please check feature_transform_list" && exit 1;
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
  echo $this_feature_transform >> $feature_transform_list
done

###### INITIALIZE THE NNET ######
echo 
echo "# NN-INITIALIZATION"
[ ! -z "$mlp_init" ] && echo "Using pre-initialized network '$mlp_init'";
if [ ! -z "$mlp_proto" ]; then
  echo "Initializing using network prototype '$mlp_proto'";
  mlp_init=$dir/multi.nnet.init; log=$dir/log/nnet_initialize.log
  multi-nnet-initialize $mlp_proto $mlp_init 2>$log || { cat $log; exit 1; } 
fi
if [[ -z "$mlp_init" && -z "$mlp_proto" ]]; then
  mlp_inits=""
  for i in `cat $featlist`; do
    this_dbn=$(echo $dbn | sed -e "s#$ori_feat#$i#")
    echo "Getting input/output dims :"
    #initializing the MLP, get the i/o dims...
    #input-dim
    num_fea=$(feat-to-dim "$feats_tr1 nnet-forward $feature_transform ark:- ark:- |" - )
    { #optioanlly take output dim of DBN
      [ ! -z $dbn ] && num_fea=$(nnet-forward "nnet-concat $feature_transform $this_dbn -|" "$feats_tr1" ark:- | feat-to-dim ark:- -)
      [ -z "$num_fea" ] && echo "Getting nnet input dimension failed!!" && exit 1
    }

    [ -z $num_tgt ] && num_tgt=$(hmm-info --print-args=false $alidir/final.mdl | grep pdfs | awk '{ print $NF }')

    # make network prototype
    mlp_proto=$dir/nnet.proto
    echo "Genrating network prototype $mlp_proto"
    myutils/nnet/make_nnet_proto.py $proto_opts \
      --no-softmax \
      ${bn_dim:+ --bottleneck-dim=$bn_dim} \
      $num_fea $num_tgt $hid_layers $hid_dim >$mlp_proto || exit 1
    # initialize
    mlp_init=$dir/nnet.$i.init; log=$dir/log/nnet_initialize.log
    echo "Initializing $mlp_proto -> $mlp_init"
    nnet-initialize $mlp_proto $mlp_init 2>$log || { cat $log; exit 1; }

    #optionally prepend dbn to the initialization
    if [ ! -z $dbn ]; then
      mlp_init_old=$mlp_init; mlp_init=$dir/nnet_$(basename $this_dbn)_dnn.$i.init
      nnet-concat $this_dbn $mlp_init_old $mlp_init || exit 1
    fi
    mlp_inits="$mlp_inits $mlp_init"
  done
  mlp_init=$dir/multi.nnet.init
  nnet-to-multi-merge-nnet $mlp_inits BlockAdd $mlp_init
  multi-nnet-add-softmax $dir/multi.nnet.init $mlp_init
fi

###### TRAIN ######
echo
echo "# RUNNING THE NN-TRAINING SCHEDULER"
mysteps/train_nnet_scheduler.sh \
  --feature-transform-list $feature_transform_list \
  --learn-rate $learn_rate \
  --randomizer-seed $seed \
  --resume-anneal $resume_anneal \
  --train-tool multi-nnet-train-frmshuff-subnnets \
  ${train_opts} \
  ${train_tool:+ --train-tool "$train_tool"} \
  ${config:+ --config $config} \
  $mlp_init $dir/feats.tr.list $dir/feats.cv.list "$labels_tr" "$labels_cv" $dir || exit 1


echo "$0 successfuly finished.. $dir"

sleep 3
exit 0
}
