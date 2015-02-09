#!/bin/bash

{
set -e
set -o pipefail

nj=32
cmd=cmd.sh
type=dev10h
decision_threshold=1
fraction=0.1
echo "$0 $@"

. parse_options.sh
. $cmd
. ./lang.conf
. ./path.sh

mergelist=$1
expdir=$2

kwlist_file=$(eval echo "\$${type}_kwlist_file")
ecf_file=$(eval echo "\$${type}_ecf_file")
rttm_file=$(eval echo "\$${type}_rttm_file")

[ -d $expdir ] || mkdir -p $expdir

mykwsutils/make_split_lists.pl $mergelist $nj $expdir/split

$decode_cmd JOB=0:$(($nj-1)) $expdir/log/merge.JOB.log \
  mykwsutils/merge_search_results_parallel.pl $expdir/split_in.JOB \`cat $mergelist\` \> $expdir/split_out.JOB

mykwsutils/gather_search_results.pl `cat $expdir/split_out.list` > $expdir/merged.kws.xml

mykwsutils/empirical_thresh.pl $ecf_file $expdir/merged.kws.xml $decision_threshold $fraction > $expdir/dec.merged.kws.xml

KWSEval -e $ecf_file -r $rttm_file -t $kwlist_file -o -b -O -B -c --words-oov -f $expdir/dec.merged.kws -s $expdir/dec.merged.kws.xml

mykwsutils/get_alignment_stats.pl $ecf_file $expdir/merged.kws.xml $expdir/dec.merged.kws.alignment.csv > $expdir/stats_file.txt
mykwsutils/kst_stats.pl $ecf_file $expdir/stats_file.txt > $expdir/kst_results.txt
kst_thresh=`head -1 $expdir/kst_results.txt | gawk '{print $5}'`

mykwsutils/kst_norm_thresh_kwlist.pl $ecf_file $kst_thresh $expdir/merged.kws.xml > $expdir/kst_norm.xml

KWSEval -e $ecf_file -r $rttm_file -t $kwlist_file -o -b -O -B -c --words-oov -f $expdir/kst_norm -s $expdir/kst_norm.xml
}
