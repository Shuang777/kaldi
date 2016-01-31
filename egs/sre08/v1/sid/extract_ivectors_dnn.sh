#!/bin/bash

# Copyright     2013  Daniel Povey
#          2014-2015  David Snyder
#               2015  Johns Hopkins University (Author: Daniel Garcia-Romero)
#               2015  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0.

# This script extracts iVectors for a set of utterances, given
# features and a trained DNN-based iVector extractor.

# Begin configuration section.
nj=30
cmd="run.pl"
stage=0
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)
posterior_scale=1.0 # This scale helps to control for successive features being highly
                    # correlated.  E.g. try 0.1 or 0.3.
post_cmd=
use_gpu=no
nnet=
feat_type=traps
transform_dir=
feature_transform=
subsample=1
add_delta=true
cmvn=true
cmvn_opts="--norm-vars=false"
vad=true
post_from=
dnnfeats2feats=none

# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# != 5 ]; then
  echo "Usage: $0 <extractor-dir> <data> <ivector-dir>"
  echo " e.g.: $0 exp/extractor_2048_male data/train_male exp/ivectors_male"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --num-iters <#iters|10>                          # Number of iterations of E-M"
  echo "  --nj <n|10>                                      # Number of jobs (also see num-processes and num-threads)"
  echo "  --num-threads <n|8>                              # Number of threads for each process"
  echo "  --stage <stage|0>                                # To control partial reruns"
  echo "  --num-gselect <n|20>                             # Number of Gaussians to select using"
  echo "                                                   # diagonal model."
  echo "  --min-post <min-post|0.025>                      # Pruning threshold for posteriors"
  exit 1;
fi

srcdir=$1
dnndir=$2
data=$3
data_dnn=$4
dir=$5

for f in $srcdir/final.ie $srcdir/final.ubm $data/feats.scp ; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

[ -z "$post_cmd" ] && post_cmd="$cmd"

# Set various variables.
mkdir -p $dir/log
sdata=$data/split$nj;
[[ -d $sdata && $data/feats.scp -ot $sdata ]] || utils/split_data.sh $data $nj

sdata_dnn=$data_dnn/split$nj;
[[ -d $sdata_dnn && $data_dnn/feats.scp -ot $sdata_dnn ]] || utils/split_data.sh $data_dnn $nj

delta_opts=`cat $srcdir/delta_opts 2>/dev/null`
[ -f $dnndir/splice_opts ] && splice_opts=`cat $dnndir/splice_opts 2>/dev/null` # frame-splicing options           

## Set up features.
feats="ark,s,cs:copy-feats scp:$sdata/JOB/feats.scp ark:- |"
if [ $add_delta == true ]; then
  feats=$feats" add-deltas $delta_opts ark:- ark:- |"
fi
if [ $cmvn == true ]; then
  feats=$feats" apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- |"
fi
if [ $vad == true ]; then
  feats=$feats" select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"
fi
feats=$feats" subsample-feats --n=$subsample ark:- ark:- |"

if [ -z "$nnet" ]; then nnet=$dnndir/final.nnet; fi
if [ -z "$feature_transform" ]; then feature_transform=$dnndir/final.feature_transform; fi
case $feat_type in
  raw) nnet_feats="scp:$sdata_dnn/JOB/feats.scp";;
  traps) nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- |";;
  delta) nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- | add-deltas ark:- ark:- |";;
  lda|fmllr) nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $dnndir/final.mat ark:- ark:- |" ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac
if [ $dnnfeats2feats == lda ]; then
  feats=$nnet_feats
  if [ $vad == true ]; then
    feats=$feats" select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"
  fi
  feats=$feats" subsample-feats --n=$subsample ark:- ark:- |"
fi
if [ ! -z "$transform_dir" ]; then
  echo "$0: using transforms from $transform_dir"
  if [ "$feat_type" == "fmllr" ]; then
    [ ! -f $transform_dir/trans.1 ] && echo "$0: no such file $transform_dir/trans.1" && exit 1;
    [ "$nj" -ne "`cat $transform_dir/num_jobs`" ] \
      && echo "$0: #jobs mismatch with transform-dir." && exit 1;
    nnet_feats="$nnet_feats transform-feats --utt2spk=ark:$sdata_dnn/JOB/utt2spk ark,s,cs:$transform_dir/trans.JOB ark:- ark:- |"
  elif [[ "$feat_type" == "raw" || "$feat_type" == "fmllr" ]]; then
    [ ! -f $transform_dir/raw_trans.1 ] && echo "$0: no such file $transform_dir/raw_trans.1" && exit 1;
    [ "$nj" -ne "`cat $transform_dir/num_jobs`" ] \
      && echo "$0: #jobs mismatch with transform-dir." && exit 1;
    nnet_feats="$nnet_feats transform-feats --utt2spk=ark:$sdata_dnn/JOB/utt2spk ark,s,cs:$transform_dir/raw_trans.JOB ark:- ark:- |"
  fi
elif grep 'transform-feats --utt2spk' $dnndir/log/train.1.log >&/dev/null; then
  echo "$0: **WARNING**: you seem to be using a neural net system trained with transforms,"
  echo "  but you are not providing the --transform-dir option in test time."
fi

if [ $dnnfeats2feats == fmllr ]; then
  feats=$nnet_feats
  if [ $vad == true ]; then
    feats=$feats" select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"
  fi
  feats=$feats" subsample-feats --n=$subsample ark:- ark:- |"
fi

if [ $stage -le 0 ]; then
  if [ -z $post_from ]; then
    echo "$0: extracting iVectors"
    $post_cmd JOB=1:$nj $dir/log/extract_ivectors.JOB.log \
      nnet-forward --frames-per-batch=4096 --feature-transform=$feature_transform \
        --use-gpu=$use_gpu $nnet "$nnet_feats" ark:- \
      \| select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- \
      \| prob-to-post --min-post=$min_post ark:- ark:- \| \
      scale-post ark:- $posterior_scale ark:- \| \
      ivector-extract --verbose=2 $srcdir/final.ie "$feats" ark,s,cs:- \
        ark,scp,t:$dir/ivector.JOB.ark,$dir/ivector.JOB.scp
  else
    [ -f $dir/post.1.gz ] && rm $dir/post.*.gz
    (cd  $dir; for i in $(ls ../../$post_from/post.*.gz); do ln -s $i; done)
    $post_cmd JOB=1:$nj $dir/log/extract_ivectors.JOB.log \
      ivector-extract --verbose=2 $srcdir/final.ie "$feats" "ark:gunzip -c $dir/post.JOB.gz |" \
        ark,scp,t:$dir/ivector.JOB.ark,$dir/ivector.JOB.scp
  fi
fi

if [ $stage -le 1 ]; then
  echo "$0: combining iVectors across jobs"
  for j in $(seq $nj); do cat $dir/ivector.$j.scp; done >$dir/ivector.scp || exit 1;
fi

if [ $stage -le 2 ]; then
  # Be careful here: the speaker-level iVectors are now length-normalized,
  # even if they are otherwise the same as the utterance-level ones.
  echo "$0: computing mean of iVectors for each speaker and length-normalizing"
  $cmd $dir/log/speaker_mean.log \
    ivector-normalize-length scp:$dir/ivector.scp  ark:- \| \
    ivector-mean ark:$data/spk2utt ark:- ark:- ark,t:$dir/num_utts.ark \| \
    ivector-normalize-length ark:- ark,scp:$dir/spk_ivector.ark,$dir/spk_ivector.scp || exit 1;
fi
