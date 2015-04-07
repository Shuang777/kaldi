#!/bin/bash

# Copyright 2012-2013 Karel Vesely, Daniel Povey
# Apache 2.0

# This script does decoding with a neural-net.  If the neural net was built on
# top of fMLLR transforms from a conventional system, you should provide the
# --transform-dir option.
{

set -e
set -o pipefail

# Begin configuration section. 
multinnet=               # non-default location of DNN (optional)
feature_transform_list=  # non-default location of feature_transform (optional)
model=              # non-default location of transition model (optional)
class_frame_counts= # non-default location of PDF counts (optional)
srcdir=             # non-default location of DNN-dir (decouples model dir from decode dir)
transform_dir=      # dir to find fMLLR transforms

stage=0 # stage=1 skips lattice generation
nj=4
cmd=run.pl

acwt=0.10 # note: only really affects pruning (scoring is on lattices).
beam=13.0
latbeam=8.0
max_active=7000 # limit of active tokens
max_mem=50000000 # approx. limit to memory consumption during minimization in bytes

skip_scoring=false
scoring_opts="--min-lmwt 4 --max-lmwt 15"

num_threads=1 # if >1, will use latgen-faster-parallel
parallel_opts="-pe smp $((num_threads+1))" # use 2 CPUs (1 DNN-forward, 1 decoder)
use_gpu="no" # yes|no|optionaly
align_lex=false
feat_type=
featlist=
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh

if [ $# != 4 ]; then
   echo "Usage: $0 [options] <graph-dir> <data-dir> <nnet-dir> <decode-dir>"
   echo "... where <decode-dir> is assumed to be a sub-directory of the directory"
   echo " where the DNN and transition model is."
   echo "e.g.: $0 exp/dnn1/graph_tgpr data/test exp/dnn1/decode_tgpr"
   echo ""
   echo "This script works on plain or modified features (CMN,delta+delta-delta),"
   echo "which are then sent through feature-transform-list. It works out what type"
   echo "of features you used from content of srcdir."
   echo ""
   echo "main options (for others, see top of script file)"
   echo "  --transform-dir <decoding-dir>                   # directory of previous decoding"
   echo "                                                   # where we can find transforms for SAT systems."
   echo "  --config <config-file>                           # config containing options"
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo ""
   echo "  --multinnet <multinnet>                                    # non-default location of DNN (opt.)"
   echo "  --srcdir <dir>                                   # non-default dir with DNN/models, can be different"
   echo "                                                   # from parent dir of <decode-dir>' (opt.)"
   echo ""
   echo "  --acwt <float>                                   # select acoustic scale for decoding"
   echo "  --scoring-opts <opts>                            # options forwarded to local/score.sh"
   echo "  --num-threads <N>                                # N>1: run multi-threaded decoder"
   exit 1;
fi


graphdir=$1
data=$2
nnetdir=$3
dir=$4

[ -z $srcdir ] && srcdir=`dirname $dir`; # Default model directory one level up from decoding directory.
sdata=$data/split$nj;

mkdir -p $dir/log

echo $nj > $dir/num_jobs

# Select prepare files for decoding
if [ -z "$featlist" ]; then featlist=$srcdir/feat.list; fi
[ ! -f "$featlist" ] && echo "not featlist found!" && exit 1
cp $featlist $dir
featlist=$dir/feat.list

if [ -z "$model" ]; then 
  model=$srcdir/final.mdl; 
  if [ ! -f $model ] && [ "$nnetdir" != "$srcdir" ]; then
    cp $nnetdir/final.mdl $model;
  fi
fi

if [ -z "$class_frame_counts" ]; then 
  class_frame_counts=$srcdir/ali_train_pdf.counts; 
  if [ ! -f $class_frame_counts ] && [ "$nnetdir" != "$srcdir" ]; then
    cp $nnetdir/ali_train_pdf.counts $class_frame_counts;
  fi
fi

if [ -z "$feature_transform_list" ]; then 
  feature_transform_list=$srcdir/feature_transforms.list; 
fi

if [ -z "$multinnet" ]; then
  multinnet=$srcdir/final.nnet;
fi

ori_feat=$(head -n 1 $featlist)

if [ ! -f $feature_transform_list ]; then
  for i in `cat $featlist`; do
    featnnetdir=$(echo $nnetdir | sed -e "s#$ori_feat#$i#g")
    echo "$featnnetdir/final.feature_transform" >> $feature_transform_list
  done
fi

if [ ! -f $multinnet ]; then
  for i in `cat $featlist`; do
    featnnetdir=$(echo $nnetdir | sed -e "s#$ori_feat#$i#g")
    nnets="$nnets $featnnetdir/final.nnet"
  done
  nnet-to-multi-merge-nnet $nnets InverseEntropy $multinnet
fi

# Check that files exist
for f in $sdata/1/feats.scp $featlist $multinnet $model $feature_transform_list $class_frame_counts $graphdir/HCLG.fst; do
  [ ! -f $f ] && echo "$0: missing file $f" && exit 1;
done

# Possibly use multi-threaded decoder
thread_string=
[ $num_threads -gt 1 ] && thread_string="-parallel --num-threads=$num_threads" 

# PREPARE FEATURE EXTRACTION PIPELINE
## Set up features.
if [ -z "$feat_type" ]; then
  if [ -f $nnetdir/final.mat ]; then feat_type=lda; else feat_type=raw; fi
  echo "$0: feature type is $feat_type"
fi

[ -f $nnetdir/norm_vars ] && cp $nnetdir/norm_vars $srcdir
norm_vars=`cat $srcdir/norm_vars 2>/dev/null` || norm_vars=false # cmn/cmvn option, default false.

# Create the feature stream:
case $feat_type in
  delta) feats="ark,s,cs:apply-cmvn --norm-vars=$norm_vars --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | add-deltas ark:- ark:- |";;
  raw) feats="ark,s,cs:apply-cmvn --norm-vars=$norm_vars --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- |";;
  raw) feats="ark,s,cs:apply-cmvn --norm-vars=$norm_vars --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- |";;
  lda) feats="ark,s,cs:apply-cmvn --norm-vars=$norm_vars --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $nnetdir/final.mat ark:- ark:- |"
   ;;
  fmllr) feats="scp:$sdata/JOB/feats.scp"
   ;;
  traps) feats="scp:$sdata/JOB/feats.scp"
   ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac
if [ ! -z "$transform_dir" ]; then
  echo "$0: using transforms from $transform_dir"
  if [ "$feat_type" == "lda" ]; then
    [ ! -f $transform_dir/trans.1 ] && echo "$0: no such file $transform_dir/trans.1" && exit 1;
    [ "$nj" -ne "`cat $transform_dir/num_jobs`" ] \
      && echo "$0: #jobs mismatch with transform-dir." && exit 1;
    feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark,s,cs:$transform_dir/trans.JOB ark:- ark:- |"
  elif [[ "$feat_type" == "raw" ]]; then
    [ ! -f $transform_dir/raw_trans.1 ] && echo "$0: no such file $transform_dir/raw_trans.1" && exit 1;
    [ "$nj" -ne "`cat $transform_dir/num_jobs`" ] \
      && echo "$0: #jobs mismatch with transform-dir." && exit 1;
    feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk ark,s,cs:$transform_dir/raw_trans.JOB ark:- ark:- |"
  fi
elif grep 'transform-feats --utt2spk' $srcdir/log/train.1.log >&/dev/null; then
  echo "$0: **WARNING**: you seem to be using a neural net system trained with transforms,"
  echo "  but you are not providing the --transform-dir option in test time."
fi
##

ori_feat=$(head -n 1 $featlist)
[ -f $srcdir/feats.list ] && rm -f $srcdir/feats.list
for i in `cat $featlist`; do
  featsdata=$(echo $sdata | sed -e "s#$ori_feat#$i#g")
  featdata=$(echo $data | sed -e  "s#$ori_feat#$i#g")
  [[ -d $featsdata && $featdata/feats.scp -ot $featsdata ]] || split_data.sh $featdata $nj
  echo "$feats" | sed -e "s#$ori_feat#$i#g" >> $srcdir/feats.list
done

aligncmd="lattice-align-words $graphdir/phones/word_boundary.int"
[ ! -f $graphdir/phones/word_boundary.int ] && align_lex=true
[ $align_lex == "true" ] && aligncmd="lattice-align-words-lexicon $graphdir/phones/align_lexicon.int"

# Run the decoding in the queue
if [ $stage -le 0 ]; then
  for i in `seq $nj`; do
    sed -e "s#JOB#$i#g" $srcdir/feats.list > $srcdir/feats.list.$i
  done

  $cmd $parallel_opts JOB=1:$nj $dir/log/decode.JOB.log \
    multi-nnet-forward-subnnets --apply-log=true --class-frame-counts=$class_frame_counts \
    ${feature_transform_list:+ --feature-transform-list=$feature_transform_list} \
    --use-gpu=$use_gpu $multinnet $srcdir/feats.list.JOB ark:- \| \
    latgen-faster-mapped$thread_string --max-active=$max_active --max-mem=$max_mem --beam=$beam \
    --lattice-beam=$latbeam --acoustic-scale=$acwt --allow-partial=true --word-symbol-table=$graphdir/words.txt \
    $model $graphdir/HCLG.fst ark:- ark:- \| \
    $aligncmd "$model" ark:- \
    "ark:|gzip -c > $dir/lat.JOB.gz" || exit 1;
  touch $dir/.done.align

  rm $srcdir/feats.list.*
fi

# Run the scoring
if ! $skip_scoring ; then
  if [ -x mylocal/score.sh ]; then
    mylocal/score.sh $scoring_opts --cmd "$cmd" $data $graphdir $dir
  elif [ -x local/score.sh ]; then
    local/score.sh $scoring_opts --cmd "$cmd" $data $graphdir $dir
  else
    echo "Not scoring because neither mylocal/score.sh nor local/score.sh is found"
    exit 1
  fi
fi

}
