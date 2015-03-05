#!/bin/bash
# Copyright 2010-2012 Microsoft Corporation
#           2012-2013 Johns Hopkins University (Author: Daniel Povey)
#           2014      International Computer Science Institute (Author: Hang Su)
# Apache 2.0

# This script creates a fully expanded decoding graph (HCLG) that represents
# all the language-model, pronunciation dictionary (lexicon), context-dependency,
# and HMM structure in our model.  The output is a Finite State Transducer
# that has word-ids on the output, and pdf-ids on the input (these are indexes
# that resolve to Gaussian Mixture Models).  
# See
#  http://kaldi.sourceforge.net/graph_recipe_test.html
# (this is compiled from this repository using Doxygen,
# the source for this part is in src/doc/graph_recipe_test.dox)
{
# Begin configuration
N=3
P=1
reverse=false
Gmiddle=
Lmiddle=
# End configuration

echo $0 $@

for x in `seq 2`; do 
  [ "$1" == "--mono" ] && N=1 && P=0 && shift;
  [ "$1" == "--quinphone" ] && N=5 && P=2 && shift;
  [ "$1" == "--reverse" ] && reverse=true && shift;
done

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh

if [ $# != 3 ]; then
   echo "Usage: utils/mkgraph.sh [options] <lang-dir> <model-dir> <graphdir>"
   echo "e.g.: utils/mkgraph.sh data/lang_test exp/tri1/ exp/tri1/graph"
   echo " Options:"
   echo " --mono          #  For monophone models."
   echo " --quinphone     #  For models with 5-phone context (3 is default)"
   exit 1;
fi


lang=$1
tree=$2/tree
model=$2/final.mdl
dir=$3

Gfst=G${Gmiddle}.fst
Lfst=L${Lmiddle}.fst
Ldisfst=L_disambig${Lmiddle}.fst

mkdir -p $dir

tscale=1.0
loopscale=0.1

# If $tmpdir/LG.fst does not exist or is older than its sources, make it...
# (note: the [[ ]] brackets make the || type operators work (inside [ ], we
# would have to use -o instead),  -f means file exists, and -ot means older than).

required="$lang/$Lfst $lang/$Gfst $lang/phones.txt $lang/words.txt $lang/phones/silence.csl $lang/phones/disambig.int $model $tree"
for f in $required; do
  [ ! -f $f ] && echo "mkgraph.sh: expected $f to exist" && exit 1;
done

tmpdir=$dir/tmp
mkdir -p $tmpdir

# Note: [[ ]] is like [ ] but enables certain extra constructs, e.g. || in 
# place of -o
if [[ ! -s $tmpdir/LG.fst || $tmpdir/LG.fst -ot $lang/$Gfst || \
      $tmpdir/LG.fst -ot $lang/L_disambig.fst ]]; then
  fsttablecompose $lang/$Ldisfst $lang/$Gfst | fstdeterminizestar --use-log=true | \
    fstminimizeencoded  > $tmpdir/LG.fst || exit 1;
  fstisstochastic $tmpdir/LG.fst || echo "[info]: LG not stochastic."
fi

clg=$tmpdir/CLG_${N}_${P}.fst

[ ! -z $Lmiddle ] && [[ ! $Lmiddle =~ "syl2phn" ]] && Lmiddle='.merge'

if [[ ! -s $clg || $clg -ot $tmpdir/LG.fst ]]; then
  fstcomposecontext --context-size=$N --central-position=$P \
   --read-disambig-syms=$lang/phones/disambig${Lmiddle}.int \
   --write-disambig-syms=$tmpdir/disambig_ilabels_${N}_${P}.int \
    $tmpdir/ilabels_${N}_${P} < $tmpdir/LG.fst >$clg
  fstisstochastic $clg  || echo "[info]: CLG not stochastic."
fi

if [[ ! -s $dir/Ha.fst || $dir/Ha.fst -ot $model  \
    || $dir/Ha.fst -ot $tmpdir/ilabels_${N}_${P} ]]; then
  if $reverse; then
    make-h-transducer --reverse=true --push_weights=true \
      --disambig-syms-out=$dir/disambig_tid.int \
      --transition-scale=$tscale $tmpdir/ilabels_${N}_${P} $tree $model \
      > $dir/Ha.fst  || exit 1;
  else
    make-h-transducer --disambig-syms-out=$dir/disambig_tid.int \
      --transition-scale=$tscale $tmpdir/ilabels_${N}_${P} $tree $model \
       > $dir/Ha.fst  || exit 1;
  fi
fi

if [[ ! -s $dir/HCLGa.fst || $dir/HCLGa.fst -ot $dir/Ha.fst || \
      $dir/HCLGa.fst -ot $clg ]]; then
  fsttablecompose $dir/Ha.fst $clg | fstdeterminizestar --use-log=true \
    | fstrmsymbols $dir/disambig_tid.int | fstrmepslocal | \
     fstminimizeencoded > $dir/HCLGa.fst || exit 1;
  fstisstochastic $dir/HCLGa.fst || echo "HCLGa is not stochastic"
fi

if [[ ! -s $dir/HCLG.fst || $dir/HCLG.fst -ot $dir/HCLGa.fst ]]; then
  add-self-loops --self-loop-scale=$loopscale --reorder=true \
    $model < $dir/HCLGa.fst > $dir/HCLG.fst || exit 1;

  if [ $tscale == 1.0 -a $loopscale == 1.0 ]; then
    # No point doing this test if transition-scale not 1, as it is bound to fail. 
    fstisstochastic $dir/HCLG.fst || echo "[info]: final HCLG is not stochastic."
  fi
fi

# keep a copy of the lexicon and a list of silence phones with HCLG...
# this means we can decode without reference to the $lang directory.

if [ -z $Lmiddle ]; then
  cp $lang/words.txt $dir
elif [[ $Lmiddle =~ "syl2phn" ]]; then
  cp $lang/syls.txt $dir/words.txt
else
  cp $lang/words.merge.txt $dir/words.txt
fi

mkdir -p $dir/phones
files="word_boundary align_lexicon disambig"
[ ! -z "$Lmiddle" ] && files="align_lexicon disambig"
for i in word_boundary align_lexicon disambig; do
  [ -f $lang/phones/${i}${Lmiddle}.int ] && cp $lang/phones/${i}${Lmiddle}.int $dir/phones/${i}.int
  [ -f $lang/phones/${i}${Lmiddle}.txt ] && cp $lang/phones/${i}${Lmiddle}.txt $dir/phones/${i}.txt
done
cp $lang/phones/silence.csl $dir/phones/
cp $lang/phones${Lmiddle}.txt $dir/phone.txt

# to make const fst:
# fstconvert --fst_type=const $dir/HCLG.fst $dir/HCLG_c.fst
}
