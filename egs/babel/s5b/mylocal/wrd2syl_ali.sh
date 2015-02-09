#!/bin/bash

# koried, 2/18/2013
# suhang, 5/11/2014

# Convert forced word alignments to sequences of syllables to be used for 
# syllable LM training;  outputs utt ids.
{

set -e
set -o pipefail

echo "$0 $@"

# Begin configuration
cmd=utils/run.pl
sil_prob=0.5
posphone=false
# End configuration

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

if [ $# != 6 ]; then
  echo "Usage: $0 <wrd-lex> <syl-lex> <lang-dir> <data-dir> <ali-dir> <out-dir>"
  echo " e.g.: $0 data/local/tmp.lang/lexiconp.txt data/local/tmp.lang/lexiconp.wrd2syl.txt data/lang data/train exp/tri5_ali exp/tri5/text"
  exit 1;
fi

wrdlex=$1
wrd2syllex=$2
lang=$3
data=$4
alidir=$5
dir=$6

for f in $wrdlex $wrd2syllex $alidir/final.mdl $lang/{phones,words}.txt $alidir/num_jobs; do
  [ -f $f ] || ( echo "$0:  no such file $f";  exit 1; )
done

nj=`cat $alidir/num_jobs`
silphone=`cat $lang/phones/optional_silence.txt`

echo "Building L_align.fst"
cat $wrdlex | \
  awk '{printf("%s #1 ", $1); for (n=3; n <= NF; n++) { printf("%s ", $n); } print "#2"; }' | \
  utils/make_lexicon_fst.pl - $sil_prob $silphone | \
  fstcompile --isymbols=$lang/phones.txt --osymbols=$lang/words.txt \
  --keep_isymbols=false --keep_osymbols=false | \
  fstarcsort --sort_type=olabel > $lang/L_align.fst || exit 1;

# word begin/end symbols
wbegin=`awk '/#1/ { print $2 }' $lang/phones.txt`
wend=`awk '/#2/ { print $2 }' $lang/phones.txt`

oov=`cat $lang/oov.int`

mkdir -p $dir/log

echo "Converting word alignments to pronunciations..."
# convert to intermediate files;  they will contain lines like
#   uttid  w1 phn1 phn2 phn3 ; word2 phn4 phn5 phn6 [; ...]
$cmd JOB=1:$nj $dir/log/ali2pron.JOB.log \
  ali-to-phones $alidir/final.mdl "ark:gunzip -c $alidir/ali.JOB.gz |" ark:- \| \
  phones-to-prons $lang/L_align.fst $wbegin $wend ark:- \
    "ark:utils/sym2int.pl --map-oov $oov -f 2- $lang/words.txt $data/split$nj/JOB/text |" "ark,t:|gzip -c > $dir/pron.JOB.int.gz" 

echo "Pronunciations to syllables..."
# convert the pronunciations to syllabifications
$cmd JOB=1:$nj $dir/log/pron2syl.JOB.log \
  gunzip -c $dir/pron.JOB.int.gz \| \
    mylocal/prons_to_syll.pl --posphone $posphone $wrd2syllex $lang/{words,phones}.txt \| \
    gzip -c ">" $dir/syll.JOB.tra.gz 

echo "Merging text"
# merge files, strip uttids
gunzip -c $dir/syll.*.tra.gz > $dir/text

}
