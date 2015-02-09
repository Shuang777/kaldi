#!/bin/bash

# Copyright 2014 International Computer Science Institute (Author: Hang Su)
# Apache 2.0.

# This script transduce syllable lattices to word lattices
{

set -e 
set -o pipefail

# Begin configuration section.
stage=1
cmd=run.pl
scoring_opts=
skip_scoring=false
iter=final
mem_req=
Lmiddle=".wrd2syl"
LGmiddle=""
latname="wrdlat"
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: $0 [options] <graph-dir> <data-dir> <decode-dir>"
  echo " e.g.: $0 data/lang data/dev10h exp/tri4a_nnet/decode_dev93_tgpr_syl"
  echo "main options (for others, see top of script file)"
  echo "  --cmd <cmd>                              # Command to run in parallel with"
  echo "  --scoring-opts <string>                  # options to local/score.sh"
  exit 1;
fi

graphdir=$1
data=$2
dir=$3
srcdir=`dirname $dir`; # Assume model directory one level up from decoding directory.
model=$srcdir/$iter.mdl

for f in $graphdir/Ldet.wrd2syl.fst $model; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

nj=`cat $dir/num_jobs`

if [ $stage -le 1 ]; then
  if [ -z "$LGmiddle" ]; then
    $cmd $mem_req JOB=1:$nj $dir/log/syl2wrd.JOB.log \
      lattice-compose "ark:gunzip -c $dir/lat.JOB.gz |" $graphdir/Ldet$Lmiddle.fst ark:- \| \
      lattice-determinize ark:- ark:- \| \
      lattice-align-words-lexicon $graphdir/phones/align_lexicon.wrd2syl.int $model ark:- \
      "ark:| gzip -c > $dir/$latname.JOB.gz"
      touch $dir/.done.align
  else
    $cmd $mem_req JOB=1:$nj $dir/log/syl2wrdG.JOB.log \
      lattice-scale --lm-scale=0.0 "ark:gunzip -c $dir/lat.JOB.gz |" ark:- \| lattice-compose ark:- $graphdir/LGdet$LGmiddle.fst ark:- \| \
      lattice-determinize ark:- ark:- \| \
      lattice-align-words-lexicon $graphdir/phones/align_lexicon.wrd2syl.int $model ark:- \
      "ark:| gzip -c > $dir/${latname}G.JOB.gz"
      touch $dir/.done.align
  fi
fi


if [ $stage -le 2 ]; then
  if ! $skip_scoring ; then
    echo "score best paths"
    if [ -z "$LGmiddle" ]; then
      mylocal/score.sh $scoring_opts --cmd "$cmd" --wrdsyl syl2wrd $data $graphdir $dir
    fi
    echo "score confidence and timing with sclite"
  fi
fi

echo "Transduction done."
exit 0

}
