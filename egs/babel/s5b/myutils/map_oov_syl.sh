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

if [ $# -ne 3 ]; then
  echo "Usage: $0 <inlex> <local-dir> <exp-dir>"
  echo " E.g.: $0 oov.lex.txt data/local exp/map_unseen_syl"
  exit 1
fi

inlex=$1
localdir=$2
dir=$3
[ -d $dir ] || mkdir -p $dir

cat $inlex | sed -e 's#\t #\t#g' -e 's#\t$##g' -e 's# #=#g' > $dir/lex.wrd2syl.txt

cut -f1 $localdir/lexiconp.syl2phn.txt | sort -u > $localdir/seen.syl
awk 'NR==FNR {a[$i]; next;} {for(i=2; i<=NF; i++) {if (!($i in a)) {print $i}}}' $localdir/seen.syl $dir/lex.wrd2syl.txt | sort -u > $dir/unseen.syl

split_unseens=""
for ((n=1; n<=nj; n++)); do
  split_unseens="$split_unseens $dir/unseen.${n}.list"
done

utils/split_scp.pl $dir/unseen.syl $split_unseens

$cmd JOB=1:$nj $dir/log/map_unseen.JOB.log /u/fosler/research/iarpa/closesyls/closesyls.pl $localdir/seen.syl $dir/unseen.JOB.list '>' $dir/unseen.JOB.syl.map

cat $dir/unseen.*.syl.map > $dir/unseen.syl.map

awk 'NR==FNR {a[$1]=$2; next;} {for (i=2; i <= NF; i++) {if ($i in a) {$i=a[$i]}} print}' $dir/unseen.syl.map $inlex | sort -u | perl -ape 's/(\S+\s+)(.+)/${1}1.0\t$2/;' > $dir/lexiconp.wrd2syl.txt

exit 0;
}
