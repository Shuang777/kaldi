#!/bin/bash 
# Copyright 2014       International Computer Science Institute (suhang)
# Apache 2.0
# To be run from .. (one directory up from here)
# convert lattice to slf format for ICSI's use

set -e
set -u
set -o pipefail

function die () {
  echo -e "ERROR:$1\n"
  exit 1
}

# Begin configuration section.
nj=4
cmd=run.pl
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || die "parse_options.sh exit 1"

if [ $# != 2 ]; then
   echo "Usage: wrdarc2node.sh [options] <lat-dir> <exp-dir>";
   echo "Push word in slf lattice from arcs to nodes"
   echo "E.g.: wrdarc2node.sh exp/tri6_nnet/decode/convertlat exp/tri6_nnet/decode"
   echo "Options: "
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

latdir=$1
expdir=$2

outputdir=$expdir/wrdarc2nodelat
logdir=$expdir/log

[ -d $outputdir ] || mkdir -p $outputdir

nj=`cat $expdir/num_jobs`
split_lats=""
for ((n=1; n<=nj; n++)); do
  split_lats="$split_lats $logdir/latslist.$n"
done

ls $latdir | sed "s#^#$latdir/#g" > $expdir/latslist

utils/split_scp.pl $expdir/latslist $split_lats || exit 1;

$cmd JOB=1:$nj $expdir/log/wrdarc2node.JOB.log \
  lattice-tool -read-htk -write-htk -htk-logbase 2.718281 -htk-words-on-nodes -in-lattice-list $logdir/latslist.JOB -out-lattice-dir ${outputdir}.JOB

mv ${outputdir}.*/* $outputdir
rmdir ${outputdir}.*

exit 0
