#!/bin/bash

{
set -e
set -o pipefail

nj=64
word_surface_file=None
decision_threshold=0
fraction=0.1
lm_scale=20
posterior_scale=40
stage=0
hescii=true
llp=1
cmd=cmd.sh

echo "$0 $@"

. parse_options.sh
. $cmd
. ./path.sh

latdir=$1
expdir=$2
kwlist_file=$3
ecf_file=$4
rttm_file=$5

if [ $stage -le 0 ]; then
[ -d $expdir ] || mkdir -p $expdir

find -L $latdir -name '*.slf.gz' -o -name '*.slf' -o -name '*.lat.gz' -o -name '*.lat' > $expdir/lat.list

if [ $hescii == true ]; then
  mykwsutils/downcase-kwlist.lang_depend.pl $kwlist_file > $expdir/lc.kwlist.xml
  mykwsutils/hescii-downcase-kwlist.py $expdir/lc.kwlist.xml > $expdir/lc.hescii.kwlist.xml
  mykwsutils/kwlist2oov.pl $kwlist_file $llp > $expdir/oov.counts
  kwlist_file=$expdir/lc.hescii.kwlist.xml
fi

mykwsutils/create_keywords_surface_forms.pl $kwlist_file $word_surface_file $expdir/keywords_surface_forms.txt
fi

if [ $stage -le 1 ]; then
split_lats=""
for ((n=1; n<=$nj; n++)); do
    split_lats="$split_lats $expdir/lat.$n.list"
done
utils/split_scp.pl $expdir/lat.list $split_lats

$decode_cmd JOB=1:$nj $expdir/log/create_index.JOB.log \
  mykwsutils/create_index.sh --hescii $hescii --posterior-scale $posterior_scale --lm-scale $lm_scale $kwlist_file $ecf_file $expdir $expdir/lat.JOB.list

mykwsutils/merge_search_results.pl $expdir/lat.*.search_results.xml > $expdir/kws_output.raw.xml
fi

if [ $stage -le 2 ]; then
mykwsutils/empirical_thresh.pl $ecf_file $expdir/kws_output.raw.xml $decision_threshold $fraction > $expdir/kws_output.xml
fi

KWSEval -e $ecf_file -r $rttm_file -t $kwlist_file -o -b -O -B -c --words-oov -f $expdir/scoring -s $expdir/kws_output.xml
}
