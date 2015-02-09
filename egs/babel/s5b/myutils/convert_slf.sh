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
feat_frame_digits=7
feat_frame_rate=100
lower=true
mem_req=
outputext=
latname=lat
wordsmiddle=
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || die "parse_options.sh exit 1"

if [ $# != 4 ]; then
   echo "Usage: convert_slf.sh [options] <data> <lang> <mdl-dir> <exp-dir>";
   echo "Make slf lattice from kaldi lattice"
   echo "E.g.: convert_slf.sh data/dev10h data/lang exp/tri5 exp/tri5/decode_dev10h"
   echo "Options: "
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

data=$1
lang=$2
mdldir=$3
expdir=$4

[ "$latname" == wrdlatG ] && outputext=G
outputdir=$expdir/convertlat$outputext

[ -d $outputdir ] || mkdir -p $outputdir

required="$lang/words.txt $expdir/num_jobs $mdldir/final.mdl"

for f in $required; do
  if [ ! -f $f ]; then
    die "$0: no such file $f"
  fi
done

nj=`cat $expdir/num_jobs`

words=$lang/words$wordsmiddle.txt
myutils/hescii_words.py --lower $lower < $words > ${words}.hescii
wordshes=${words}.hescii

if [ $latname == "lat" ]; then
  $cmd $mem_req JOB=1:$nj $expdir/log/convert$outputext.JOB.log \
    lattice-copy "ark:gunzip -c $expdir/${latname}.JOB.gz |" ark,t:- \| \
    utils/int2sym.pl -f 3 $wordshes \| \
    myutils/convert_slf.pl - $outputdir
else
  $cmd $mem_req JOB=1:$nj $expdir/log/convert$outputext.JOB.log \
    lattice-copy "ark:gunzip -c $expdir/${latname}.JOB.gz |" ark,t:- \| \
    utils/int2sym.pl -f 3 $wordshes \| \
    myutils/convert_slf.pl - $outputdir
fi

exit 0
