#!/bin/bash
{

set -e
set -o pipefail

nj=20
cmd=run.pl

echo "$0 $@"

. ./path.sh
. parse_options.sh

if [ $# -ne 3 ] && [ $# -ne 5 ]; then
  echo "Usage: $0 <trail> (<postdir1> <postdir2>) <dir> <output>"
  echo " e.g.: $0 trails.diff exp/posts_studio_male exp/posts_studio_male/distance.diff" 
  exit 1;
fi

trails=$1
if [ $# -eq 3 ]; then
  dir=$2
  output=$3
  postdir1=$dir
  postdir2=$dir
else
  postdir1=$2
  postdir2=$3
  dir=$4
  output=$5
fi

split_trials=""
for n in $(seq $nj); do
  split_trials="$split_trials $dir/trails.$$.$n"
done

utils/split_scp.pl $trails $split_trials

$cmd JOB=1:$nj $dir/log/dtw.JOB.log cat $dir/trails.$$.JOB \| fgmm-global-dtw - \"ark:gunzip -c $postdir1/post.*.gz \|\" \"ark:gunzip -c $postdir2/post.*.gz \|\" $dir/distance.$$.JOB

[ -f $output ] && rm $output
for n in $(seq $nj); do
  cat $dir/distance.$$.$n >> $output
done

rm $dir/distance.$$.* $dir/trails.$$.*

}
