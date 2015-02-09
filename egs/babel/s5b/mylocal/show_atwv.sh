#!/usr/bin/env bash

# Copyright 2014  The Ohio State University (Author: Yanzhang He)
# Apache 2.0.

{
set -e
set -o pipefail
set -u

#all, iv, oov, all_mtwv
type=

. /u/hey/exp/my_utils/parse_options.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 <dir>"
  exit 1
fi

dir=$1

sum_report=
cond_sum_report=

if [ -f $dir/SRS-GO/data/scratch_ttmp/scoring.sum.txt ]; then
  sum_report=$dir/SRS-GO/data/scratch_ttmp/scoring.sum.txt
  cond_sum_report=$dir/SRS-GO/data/scratch_ttmp/scoring.cond.sum.txt
elif [ -f $dir/sum.txt ]; then
  sum_report=$dir/sum.txt
  cond_sum_report=$dir/cond.sum.txt
else
  echo "Error in $0: Cannot find KWS scoring result files."
  exit 1
fi

if [ -z $type ]; then
  tail -5 $sum_report
  tail -6 $cond_sum_report
  echo
  for i in 2 1; do
    cond=`tail -n $i $cond_sum_report | head -n1 | cut -f2 -d'|' | sed 's/ //g'`
    if [ "$cond" == "IV" -o "$cond" == "OOV" ]; then
      targ=`tail -n $i $cond_sum_report | head -n1 | cut -f4 -d'|' | sed 's/ //g'`
      ntarg=`tail -n $i $cond_sum_report | head -n1 | cut -f5 -d'|' | sed 's/ //g'`
      sys=`tail -n $i $cond_sum_report | head -n1 | cut -f6 -d'|' | sed 's/ //g'`
      hit=`tail -n $i $cond_sum_report | head -n1 | cut -f7 -d'|' | sed 's/ //g'`
      FA=`tail -n $i $cond_sum_report | head -n1 | cut -f9 -d'|' | sed 's/ //g'`
      TWV=`tail -n $i $cond_sum_report | head -n1 | cut -f13 -d'|' | sed 's/ //g'`
      plist_targ=`bc <<< "$sys - $ntarg"`
      recall=`bc <<< "scale=2; $plist_targ * 100 / $targ"`
      #echo -e "$cond:\t#Targ: $targ \t#Targ in posting list: $plist_targ \tHit: $hit \tFA: $FA \tTWV: $TWV"
      echo -e "$cond:\t#Targ in posting list: $plist_targ \tRecall: ${recall}%"
    fi
  done
  echo
else
  if [ "$type" == "all" ]; then
    atwv=`tail -n1 $sum_report | cut -f13 -d'|' | sed 's/ //g'`
    echo $atwv
  elif [ "$type" == "all_mtwv" ]; then
    mtwv=`tail -n1 $sum_report | cut -f17 -d'|' | sed 's/ //g'`
    if [ "$mtwv" == "" ]; then
      echo "Cannot get MTWV from the report file $sum_report"
      exit 1
    fi
    echo $mtwv
  elif [ $type == "iv" ]; then
    if [ ! -f $cond_sum_report ]; then
      echo "File not exist: $cond_sum_report"
      exit 1
    fi
    cond=`tail -n1 $cond_sum_report | cut -f2 -d'|' | sed 's/ //g'`
    if [ $cond == "IV" ]; then
      atwv=`tail -n1 $cond_sum_report | cut -f13 -d'|' | sed 's/ //g'`
    else
      cond=`tail -n2 $cond_sum_report | head -n1 | cut -f2 -d'|' | sed 's/ //g'`
      if [ $cond == "IV" ]; then
        atwv=`tail -n2 $cond_sum_report | head -n1 | cut -f13 -d'|' | sed 's/ //g'`
      else
        echo "Error: the last two lines in $cond_sum_report are not IV condition."
        exit 1
      fi
    fi
    echo $atwv
  elif [ "$type" == "oov" ]; then
    if [ ! -f $cond_sum_report ]; then
      echo "File not exist: $cond_sum_report"
      exit 1
    fi
    cond=`tail -n1 $cond_sum_report | cut -f2 -d'|' | sed 's/ //g'`
    if [ $cond != "OOV" ]; then
      echo "Error: the last line in $cond_sum_report is not OOV condition."
      exit 1
    fi
    atwv=`tail -n1 $cond_sum_report | cut -f13 -d'|' | sed 's/ //g'`
    echo $atwv
  else
    echo "$0: type has to be all/iv/oov."
    exit 1
  fi
fi

}
