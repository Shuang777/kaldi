#!/bin/bash

# Copyright 2014   International Computer Science Institute (Author: Hang Su)
# Apache 2.0.

# This is for generating lexicon for iv keywords using g2p
{
set -e
set -o pipefail

# Begin configuration
nj=32
nbest=1
cmd=myutils/slurm.pl
# End configuration

echo $0 $@
[ -f ./path.sh ] && . ./path.sh
. parse_options.sh

if [ $# -ne 4 ]; then
    echo "Usage: $0 <kwlist> <g2p-model> <local-dir> <exp-dir>"
    echo " E.g.: $0 kwlist4 lexicon.fst data/local exp/gen_iv_lex"
    echo "Options:"
    echo "       --nj  "
    echo "       --cmd "
    exit 1
fi

kwlist=$1
model=$2
localdir=$3
dir=$4

[ -d $dir ] || mkdir -p $dir

grep '<kwtext>' $kwlist | cut -f2 -d'>' | cut -f1 -d'<' | tr ' ' '\n' | sort -u | awk 'NR==FNR {a[$1]; next} ($1 in a)' $localdir/lexiconp.wrd2syl.txt /dev/stdin > $localdir/kw.iv.list

split_ivs=""
for ((n=1; n<=nj; n++)); do
  split_ivs="$split_ivs $dir/iv.${n}.list"
done

utils/split_scp.pl $localdir/kw.iv.list $split_ivs

$cmd JOB=1:$nj $dir/log/split.JOB.log mylocal/g2p_get_prons.sh -m $model -v $dir/iv.JOB.list -S -h -o $dir/iv.JOB.lex -N $nbest

cat $dir/iv.*.lex | sed -e 's#vbar#|#g' -e 's# # . #g' -e 's#=# #g' > $localdir/iv_lexicon.raw.txt

exit 0
}
