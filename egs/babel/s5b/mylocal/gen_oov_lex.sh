#!/bin/bash

# Copyright 2014   International Computer Science Institute (Author: Hang Su)
# Apache 2.0.

# This is for generating lexicon for oov keywords using g2p
{
set -e
set -o pipefail

# Begin configuration
nj=32
nbest=1
cmd=myutils/slurm.pl
phnsyl=phn
# End configuration

echo $0 $@
[ -f ./path.sh ] && . ./path.sh
. parse_options.sh

if [ $# -ne 3 ]; then
    echo "Usage: $0 <oov_list> <g2p-model> <exp-dir>"
    echo " E.g.: $0 kw.oov.list lexicon.fst exp/gen_oov_lex"
    echo "Options:"
    echo "       --nj  "
    echo "       --cmd "
    exit 1
fi

oov_list=$1
model=$2
dir=$3

[ -d $dir ] || mkdir -p $dir

split_oovs=""
for ((n=1; n<=nj; n++)); do
  split_oovs="$split_oovs $dir/oov.${n}.list"
done

utils/split_scp.pl $oov_list $split_oovs
sylargu=""
[ $phnsyl == syl ] && sylargu="-S"

$cmd JOB=1:$nj $dir/log/split.JOB.log g2p/g2p_get_prons.sh -d $dir -m $model -v $dir/oov.JOB.list -h -o $dir/oov.JOB.lex -N $nbest $sylargu

cat $dir/oov.*.lex | sed -e 's#vbar#|#g' -e 's# # . #g' -e 's#=# #g' > $dir/oov_lexicon.raw.txt

exit 0
}
