#!/bin/bash
{

set -e
set -o pipefail

export LC_ALL=C

# Begin configuration
vocab=
train_text=
dev_text=
vocab=
orilm=
lambda=0.5
outlm=lm.boost.gz
# End of configuration

echo "$0 $@"

. ./utils/parse_options.sh

kwlist=$1
tgtdir=$2

[ -z $train_text ] && train_text=$tgtdir/train.txt
[ -z $dev_text ] && dev_text=$tgtdir/dev.txt
[ -z $vocab ] && vocab=$tgtdir/vocab
[ -z $orilm ] && orilm=$tgtdir/lm.gz

echo "Using words file: $words_file"
echo "Using train text: $train_text"
echo "Using dev text  : $dev_text"
echo "Using original lm: $orilm"

for f in $vocab $train_text $dev_text $orilm; do
  [ ! -s $f ] && echo "No such file $f" && exit 1;
done

# Prepare the destination directory
[ -d $tgtdir ] && mkdir -p $tgtdir

# Extract the word list from the training dictionary; exclude special symbols
grep '<kwtext>' $kwlist | cut -f2 -d'>' | cut -f1 -d'<' | tr ' ' '\n' > $tgtdir/keywords.txt

cat $tgtdir/keywords.txt $vocab | sort -u > $tgtdir/vocab.merge
vocab_merge=$tgtdir/vocab.merge

# Regular text unigram
ngram-count -order 1 -text $train_text -vocab $vocab_merge -unk -kndiscount -lm $tgtdir/unigram.lm.gz 

# Keywords unigram
ngram-count -order 1 -text $tgtdir/keywords.txt -vocab $vocab_merge -unk -kndiscount -lm $tgtdir/unigram.kw.lm.gz

# Interpolate the unigram models
comb_uni_lm=$tgtdir/combined.unigram.$lambda.lm.gz
ngram -vocab $vocab_merge -lm $tgtdir/unigram.lm.gz -lambda $lambda -mix-lm $tgtdir/unigram.kw.lm.gz -write-lm $comb_uni_lm -unk

comb_uni_norm_lm=$tgtdir/combined.unigram.$lambda.lm.norm.gz
ngram -lm $comb_uni_lm -renorm -write-lm $comb_uni_norm_lm

ngram -lm $orilm -vocab $tgtdir/vocab.merge -renorm -write-lm $tgtdir/lm.norm.gz

ngram -vocab $vocab_merge -lm $tgtdir/lm.norm.gz -adapt-marginals $comb_uni_norm_lm -rescore-ngram $tgtdir/lm.norm.gz -write-lm $tgtdir/$outlm

}
