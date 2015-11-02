#!/bin/bash
{
set -e
set -o pipefail

. ./lang.conf
. ./cmd.sh


interp=0.9

echo "Processing $langpack ..."

ext=_inter${interp}
dir=exp/g2p${ext}

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
g2p/format_dict.pl $dir/lexicon.train.txt > $dir/lexicon.train.formated.txt

#g2p/myg2p_build_model.sh -d $dir/lexicon.train.formated.txt -o $dir/lexicon.phn.fst -G 2 -P 7 -b -i $interp
#g2p/myg2p_build_model.sh -d $dir/lexicon.train.formated.txt -o $dir/lexicon.syl.fst -G 2 -P 7 -b -i $interp -S

for i in phn; do
  lexdir=exp/gen_oov_lex${ext}_$i
  mylocal/gen_oov_lex.sh --nj 64 --phnsyl $i data/local_nop/flplex.oov.list $dir/lexicon.$i.fst $lexdir
  trndir=exp/gen_trn${ext}_$i
  myutils/gen_trn2.pl $lexdir/oov_lexicon.raw.txt /u/drspeech/data/swordfish/corpora/${langpack%*_LLP}/conversational/reference_materials/lexicon.txt $trndir
  echo "Performing sclite"
  sclite -i rm -r $trndir/ref.trn trn -h $trndir/hyp.trn trn -s -f 0 -D -F -o sum rsum prf dtl sgml -e utf-8 -n sclite
done

echo "Done"
}
