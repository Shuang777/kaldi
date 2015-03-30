#!/bin/bash
{
set -e
set -o pipefail

# Copyright     2013  Daniel Povey
#               2015  Hang Su
# Apache 2.0.

# This script check the condition number of the matrix (V^T*W*T) in ivector inference. 

# Begin configuration section.
nj=30
cmd="run.pl"
stage=0
num_gselect=20 # Gaussian-selection using diagonal model: number of Gaussians to select
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)
posterior_scale=1.0 # This scale helps to control for successve features being highly
                    # correlated.  E.g. try 0.1 or 0.3.
vad=true
add_delta=true
lambda=1.0
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# != 3 ]; then
  echo "Usage: $0 <extractor-dir> <data> <expdir>"
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
data=$2
dir=$3

for f in $srcdir/final.ie $srcdir/final.ubm $data/feats.scp ; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

# Set various variables.
mkdir -p $dir/log
sdata=$data/split$nj;
[[ -d $sdata && $data/feats.scp -ot $sdata ]] || utils/split_data.sh --per-utt $data $nj

[ -f $srcdir/delta_opts ] && delta_opts=`cat $srcdir/delta_opts 2>/dev/null`

## Set up features.
feats="ark,s,cs:copy-feats scp:$sdata/JOB/feats.scp ark:- |"
if [ $add_delta == true ]; then
  feats=$feats" add-deltas $delta_opts ark:- ark:- |"
fi
feats=$feats" apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- |"
if [ $vad == true ]; then
  feats=$feats" select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"
fi

if [ $stage -le 0 ]; then
  echo "$0: extracting iVectors"
  dubm="fgmm-global-to-gmm $srcdir/final.ubm -|"

  $cmd JOB=1:$nj $dir/log/check_cond.lambda$lambda.JOB.log \
    gmm-gselect --n=$num_gselect "$dubm" "$feats" ark:- \| \
    fgmm-global-gselect-to-post --min-post=$min_post $srcdir/final.ubm "$feats" \
       ark,s,cs:- ark:- \| scale-post ark:- $posterior_scale ark:- \| \
    ivector-check-condition-number --lambda=$lambda $srcdir/final.ie "$feats" ark,s,cs:-
fi

}
