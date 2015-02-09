#!/bin/bash
# Copyright 2014  International Computer Science Institute (Author: Hang Su)
#

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
{
set -e
set -o pipefail

# Begin configuration
nj=32
cmd=myutils/slurm.pl
ivoov=oov
# End configuration

. utils/parse_options.sh 

if [ $# -ne 2 ]; then
  echo "Usage: $0 <local-dir> <exp-dir>"
  echo " E.g.: $0 data/local exp/map_unseen_syl"
  exit 1
fi

localdir=$1
dir=$2
[ -d $dir ] || mkdir -p $dir

cat $localdir/${ivoov}_lexicon.txt | sed -e 's#\t #\t#g' -e 's#\t$##g' -e 's# #=#g' > $localdir/${ivoov}_lexicon.wrd2syl.txt

cut -f1 $localdir/lexiconp.syl2phn.txt | sort -u > $localdir/seen.syl
awk 'NR==FNR {a[$i]; next;} {for(i=2; i<=NF; i++) {if (!($i in a)) {print $i}}}' $localdir/seen.syl $localdir/oov_lexicon.wrd2syl.txt | sort -u > $localdir/unseen.syl

split_unseens=""
for ((n=1; n<=nj; n++)); do
  split_unseens="$split_unseens $dir/unseen.${n}.list"
done

utils/split_scp.pl $localdir/unseen.syl $split_unseens

$cmd JOB=1:$nj $dir/log/map_unseen.JOB.log /u/fosler/research/iarpa/closesyls/closesyls.pl $localdir/seen.syl $dir/unseen.JOB.list '>' $dir/unseen.JOB.syl.map

cat $dir/unseen.*.syl.map > $localdir/unseen.syl.map

awk 'NR==FNR {a[$1]=$2; next;} {for (i=2; i <= NF; i++) {if ($i in a) {$i=a[$i]}} print}' $localdir/unseen.syl.map $localdir/oov_lexicon.wrd2syl.txt | sort -u | perl -ape 's/(\S+\s+)(.+)/${1}1.0\t$2/;' | cat $localdir/lexiconp.wrd2syl.txt /dev/stdin > $localdir/merge_lexiconp.wrd2syl.txt

exit 0;
}
