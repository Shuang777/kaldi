#!/bin/bash
{

set -e
set -o pipefail

paste_length_tolerance=2
nj=4
cmd=run.pl
compress=true
. parse_options.sh

if [ $# != 5 ]; then
  echo "Usage: $0 [options] <data-dir> <zcr-feat> <mfcc-feat-scp> <log-dir> <mfcc-zcr-dir>"
  exit 1;
fi

data=$1
zcr_feat=$2
mfcc_feat_scp=$3
logdir=$4
mfcc_zcr_dir=$5

name=`basename $data`

[ -d $mfcc_zcr_dir ] || mkdir -p $mfcc_zcr_dir

zcr_feats="ark:$zcr_feat.JOB.ark"

$cmd JOB=1:$nj $logdir/make_mfcc_zcr_$name.JOB.log \
  paste-feats --length-tolerance=$paste_length_tolerance "$zcr_feats" "scp:$mfcc_feat_scp" ark:- \| \
  copy-feats --compress=$compress ark:- \
    ark,scp:$mfcc_zcr_dir/raw_mfcc_zcr_$name.JOB.ark,$mfcc_zcr_dir/raw_mfcc_zcr_$name.JOB.scp

for n in $(seq $nj); do
  cat $mfcc_zcr_dir/raw_mfcc_zcr_$name.$n.scp || exit 1;
done > $data/feats.scp

}
