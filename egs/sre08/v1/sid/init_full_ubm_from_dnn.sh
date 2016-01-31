#!/bin/bash
# Copyright 2015   David Snyder
#           2015   Johns Hopkins University (Author: Daniel Garcia-Romero)
#           2015   Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0

# This script derives a full-covariance UBM from DNN posteriors and
# speaker recognition features.
{
set -e
set -o pipefail

# Begin configuration section.
nj=40
cmd="run.pl"
stage=0
add_delta=true
cmvn=true
cmvn_opts="--norm-vars=false"
vad=true
nnet=
feat_type=traps
transform_dir=      # dir to find fMLLR transforms
feature_transform=
use_gpu=no
delta_window=3
delta_order=2
subsample=1
dnnfeats2feats=none
post_from=

posterior_scale=1.0 # This scale helps to control for successve features being highly
                    # correlated.  E.g. try 0.1 or 0.3
# End configuration 

echo "$0 $@"  # Print the command line for logging

if [ -f path_v2.sh ]; then . ./path_v2.sh; fi
. parse_options.sh || exit 1;

if [ $# != 4 ]; then
  echo "Usage: steps/init_full_ubm_from_dnn.sh <data-speaker-id> <data-dnn> <dnn-model> <new-ubm-dir>"
  echo "Initializes a full-covariance UBM from DNN posteriors and speaker recognition features."
  echo " e.g.: steps/init_full_ubm_from_dnn.sh data/train data/train_dnn exp/dnn/final.mdl exp/full_ubm"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --nj <n|16>                                      # number of parallel training jobs"
  echo "  --delta-window <n|3>                             # delta window size"
  echo "  --delta-order <n|2>                              # delta order"
  echo "  --number-components <n|5297>                     # number of components in the final GMM needs"
  echo "                                                   # to be equal to the size of the DNN output layer."
  exit 1;
fi

data=$1
data_dnn=$2
dnndir=$3
dir=$4

for f in $data/feats.scp $data/vad.scp; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

mkdir -p $dir/log
echo $nj > $dir/num_jobs
sdata=$data/split$nj;
[[ -d $sdata && $data/feats.scp -ot $sdata ]] || utils/split_data.sh $data $nj || exit 1;

sdata_dnn=$data_dnn/split$nj;
[[ -d $sdata_dnn && $sdata_dnn/feats.scp -ot $sdata_dnn ]] || utils/split_data.sh $data_dnn $nj || exit 1;

delta_opts="--delta-window=$delta_window --delta-order=$delta_order"
echo $delta_opts > $dir/delta_opts

logdir=$dir/log

if [ -z "$nnet" ]; then nnet=$dnndir/final.nnet; fi
if [ -z "$feature_transform" ]; then feature_transform=$dnndir/final.feature_transform; fi

num_components=$(nnet-info $nnet | grep Softmax | tr ',' ' ' | awk '{print $NF}')

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

## set up nnet feature

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
fi
if [ ! -z "$transform_dir" ]; then
  echo "$0: using transforms from $transform_dir"
  if [ "$feat_type" == "fmllr" ]; then
    [ ! -f $transform_dir/trans.1 ] && echo "$0: no such file $transform_dir/trans.1" && exit 1;
    if [ "$nj" -ne "`cat $transform_dir/num_jobs`" ]; then
      echo "$0: #jobs mismatch with transform-dir." && exit 1;
    fi
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
fi

if [ -z $post_from ]; then
  if [ $stage -le 0 ]; then
  $cmd JOB=1:$nj $logdir/post.JOB.log \
    nnet-forward --frames-per-batch=4096 --feature-transform=$feature_transform \
      --use-gpu=$use_gpu $nnet "$nnet_feats" ark:- \
      \| select-voiced-frames ark:- scp,s,cs:$sdata_dnn/JOB/vad.scp ark:- \
      \| prob-to-post ark:- ark:- \
      \| scale-post ark:- $posterior_scale "ark:|gzip -c >$dir/post.JOB.gz"
  fi
else
  [ -f $dir/post.1.gz ] && rm $dir/post.*.gz
  (cd  $dir; for i in $(ls ../../$post_from/post.*.gz); do ln -s $i; done)
fi

if [ $stage -le 1 ]; then
$cmd JOB=1:$nj $logdir/make_stats.JOB.log \
  fgmm-global-acc-stats-post "ark:gunzip -c $dir/post.JOB.gz |" $num_components "$feats" \
    $dir/stats.JOB.acc
fi

if [ $stage -le 2 ]; then
$cmd $dir/log/init.log \
  fgmm-global-init-from-accs --verbose=2 \
  "fgmm-global-sum-accs - $dir/stats.*.acc |" $num_components \
  $dir/final.ubm
fi

rm $dir/stats.*.acc

exit 0;
}
