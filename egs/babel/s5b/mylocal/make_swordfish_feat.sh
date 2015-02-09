#!/bin/bash 
# Copyright 2012-2013  Johns Hopkins University (Author: Daniel Povey)
#                      Bagher BabaAli
# Copyright 2014       International Computer Science Institute (arlo)
# Apache 2.0
# To be run from .. (one directory up from here)
# Modified Kaldi's steps/make_plp.sh... to instead use ICSI features

# Begin configuration section.
nj=4
cmd=run.pl
stage=0
compress=true
cleanup=true
swd_feat_range=':'
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
   echo "Usage: make_swordfish_feat.sh [options] <data-dir> <exp-dir> <path-to-featdir>";
   echo "Make Kaldi-formatted features from externally provided HTK featueres"
   echo "E.g.: make_swordfish_feat.sh data/train exp/make_feat_train feat/"
   echo "Options: "
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

data=$1
expdir=$2
featdir=$3

# make $featdir an absolute pathname.
featdir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $featdir ${PWD}`
# make $expdir an absolute pathname.
expdir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $expdir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data`

mkdir -p $featdir || exit 1;
mkdir -p $expdir/log || exit 1;

# NOTE: this scp file is not standard!  It is an externally-prepared
# HTK-formatted scp file, containing pseudo-aliased paths and frame
# ranges, and must be specially inserted in the Kaldi data directory
# to exist prior to standard Kaldi tools running.
scp=$data/swd.feats.scp

# NOTE: the Kaldi-prepared segments are required.  Although the
# HTK-formatted scp will define its own segmentation (which may or may
# not differ from the Kaldi segments -- which could have been produced
# via UEM), we still need this segments file to map the IDs.
segments=$data/segments

[ ! -s $KALDI_ROOT ] && KALDI_ROOT=../../.. 

required="$scp $segments"

for f in $required; do
  if [ ! -f $f ]; then
    echo "make_swordfish_feat.sh: no such file $f"
    exit 1;
  fi
done

basename=`basename $data`

split_scps=""
for ((n=1; n<=nj; n++)); do
    split_scps="$split_scps $expdir/swordfish_feat.$n.scp"
done
utils/split_scp.pl $scp $split_scps || exit 1;

$cmd JOB=1:$nj $expdir/make_swordfish_feat_${basename}.JOB.log \
    mylocal/htk2kaldi.py $segments $expdir/swordfish_feat.JOB.scp $swd_feat_range \| \
    copy-feats --compress=$compress ark,t,cs:- ark,scp:$featdir/swordfish_feat_${basename}.JOB.ark,$featdir/swordfish_feat_${basename}.JOB.scp \
    || exit 1;

# concatenate the .scp files together.
for ((n=1; n<=nj; n++)); do
  cat $featdir/swordfish_feat_$basename.$n.scp || exit 1;
done > $data/feats.scp

nf=`cat $data/feats.scp | wc -l` 
nu=`cat $data/utt2spk | wc -l` 
if [ $nf -ne $nu ]; then
  echo "It seems not all of the feature files were successfully ($nf != $nu);"
  echo "consider using utils/fix_data_dir.sh $data"
fi

echo "Finished extracting pitch features for $basename"
exit 0;
