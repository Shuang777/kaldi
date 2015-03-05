#!/bin/bash
{

set -e
set -o pipefail

posterior_scale=40
lm_scale=20
wdpenalty=0.0
minpost=0.0
timetol=0.1
ngram_order=1
kws_use_min_prob=1
kws_time_gap=0.00
hescii=true
echo "$0 $@"

. parse_options.sh

kwlist_file=$1
ecf_file=$2
expdir=$3
lat_list=$4

ngram_temp=`echo $lat_list | sed 's#list#temp#'`
ngram_index=`echo $lat_list | sed 's#list#index#'`

lattice-tool -posterior-scale $posterior_scale -htk-lmscale $lm_scale -htk-acscale 1.0 -htk-wdpenalty $wdpenalty -min-count $minpost -ngrams-time-tolerance $timetol -in-lattice-list $lat_list -write-ngram-index $ngram_temp -order $ngram_order -read-htk

if [ $hescii == true ]; then
  mykwsutils/unigram_index_split_hescii_multiwords.py $ngram_temp $ngram_index
else
  ngram_index=$ngram_temp
fi

langname=$(head -1 $ecf_file | grep -o 'language="[^ ]*"' | sed -e 's#language="##g' -e 's#"##')

search_result=`echo $lat_list | sed 's#list#search_results.xml#'`
mykwsutils/search_index.pl $ecf_file $kwlist_file $expdir/oov.counts $expdir/keywords_surface_forms.txt $kws_time_gap $kws_use_min_prob $ngram_index $search_result $(basename $kwlist_file) $langname "Internal debugging system"

bzip2 -f $ngram_index

}

