#!/bin/bash
{

. ./lang.conf
. ./cmd.sh

set -e
set -o pipefail

INTERP="-i 0.9"

echo "Processing $langpack ..."

dir=exp/g2p

[ -d $dir ] || mkdir -p $dir

lexicon=data/local/filtered_lexicon.txt

for f in $lexicon; do
  [ ! -f "$f" ] && echo "$f not found!" && exit 1;
done

# separate pronunciations
if [[ "$lexiconFlags" =~ "romanized" ]]; then
  sed 's/\t[^\t]*\t/\t/' $lexicon | grep -v '^<' | \
    awk --field-separator '\t' '{OFS="\t"; for(i=2;i<=NF;i++) {print $1,$i}}' > $dir/lexicon.train.txt
else
  grep -v '^<' $LP/lexicon.txt | \
    awk --field-separator '\t' '{OFS="\t"; for(i=2;i<=NF;i++) {print $1,$i}}' > $dir/lexicon.train.txt
fi
if [[ $langpack =~ 107 || $langpack =~ 203 ]]; then
  g2p/g2p_move_tones.pl $dir/lexicon.train.txt > $dir/lexicon.train.txt.tones_moved
  mv $dir/lexicon.train.txt.tones_moved $dir/lexicon.train.txt
fi

g2p/myg2p_build_model.sh -d $dir/lexicon.train.txt -o $dir/lexicon.fst -G 2 -P 7 -b $INTERP
g2p/myg2p_build_model.sh -d $dir/lexicon.train.txt -o $dir/lexicon.syl.fst -G 2 -P 7 -b $INTERP -S
}
