#!/bin/bash

{
set -e
set -o pipefail

function die () {
  echo -e "ERROR: $1\n"
  exit 1
}

echo "$0 $@"

# Begin configuration
type=train      # train, dev10h, eval, unsup, trainall, dev10hunseg, evalp1
# End configuration

. ./path.sh
. parse_options.sh
. ./lang.conf

[ $type == "trainall" ] && type=train && whole_trans=true && trainext='all' || whole_trans=false

nj=$(eval echo "\$${type}_nj") 
datadir=$(eval echo "\$${type}_data_dir") 
datalist=$(eval echo "\$${type}_data_list") 

if [[ ! -f data/raw_${type}_data/.done || data/raw_${type}_data/.done -ot "$datalist" ]]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting the $type set"
  echo ---------------------------------------------------------------------
  [[ "$type" =~ 'eval' ]] && ignore_missing_txt=true || ignore_missing_txt=false
  local/make_corpus_subset.sh --ignore-missing-txt $ignore_missing_txt "$datadir" "$datalist" ./data/raw_${type}_data
  touch data/raw_${type}_data/.done
  nj_max=`cat $datalist | wc -l`
  if [[ "$nj_max" -lt "$nj" ]] ; then
    die "The maximum reasonable number of jobs is $nj_max (you have $train_nj)! (The training and decoding process has file-granularity)"
  fi
fi
datadir=`readlink -f ./data/raw_${type}_data`

if [[ ! -s data/${type}$trainext/wav.scp || data/${type}$trainext/wav.scp -ot "$datadir" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing acoustic training lists in data/${type}$trainext on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p data/${type}$trainext
  [[ "$type" =~ 'eval' ]] && ignore_trans=true || ignore_trans=false
  mylocal/prepare_acoustic_training_data.pl --ignore-transcripts $ignore_trans\
    --vocab data/local/lexicon.txt --fragmentMarkers \-\*\~ \
    --get-whole-transcripts $whole_trans \
    $datadir data/${type}$trainext > data/${type}/skipped_utts.log
fi

if [[ $type == "dev10h" ]] && [[ ! -f data/$type/stm || data/$type/glm -ot "$glmFile" ]]; then
# not well written
  echo ---------------------------------------------------------------------
  echo "Preparing $type stm files in data/$type on" `date`
  echo ---------------------------------------------------------------------
  if [ -z $dev10h_stm_file ]; then
    echo "WARNING: You should define the variable stm_file pointing to the IndusDB stm"
    echo "WARNING: Doing that, it will give you scoring close to the NIST scoring.    "
    mylocal/prepare_stm.pl --fragmentMarkers \-\*\~ data/dev10h
  else
    echo $dev10h_stm_file here
    local/augment_original_stm.pl $dev10h_stm_file data/dev10h
  fi
  [ ! -z $glmFile ] && cp $glmFile data/dev10h/glm
fi

if [ $type == "evalp1" ]; then
  [ -f $evalp1_stm_file ] || die "evalp1_stm_file $evalp1_stm_file does not exist"
  awk '{$3=$1; gsub(";;","",$3); if (NF ==5) {$5=$5 " ";} print}' $evalp1_stm_file > data/evalp1/stm
fi
}
