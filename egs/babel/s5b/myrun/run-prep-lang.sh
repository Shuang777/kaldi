#!/bin/bash
{

set -e
set -o pipefail

function die () {
  echo -e "ERROR: $1\n"
  exit 1
}

echo "$0 $@"

# Begin configuration
langext=        # _boost
langsyl=false
langwrd2syl=false
posphone=true
lowerword=false
replacelex=false
# End of configuration

. ./path.sh
. parse_options.sh
. ./lang.conf

langext_ori=$langext
[[ "$langext" =~ ^_nop ]] && die "we don't support langext == _nop*, please switch"
[ "$posphone" == "false" ] && langext=_nop$langext

[ -d data/local${langext} ] || mkdir -p data/local${langext}
if [[ ! -f data/local${langext}/lexicon.txt || data/local${langext}/lexicon.txt -ot "$lexicon_file" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing lexicon in data/local${langext} on" `date`
  echo ---------------------------------------------------------------------
  local/make_lexicon_subset.sh $train_data_dir/transcription/ $lexicon_file data/local/filtered_lexicon.txt
  lexicon_file=data/local/filtered_lexicon.txt
  echo filtered new lexicon $lexicon_file
  
  [[ $lexiconFlags =~ .*--romanized.* ]] && roman_opt="--romanized true" || roman_opt="--romanized false"

  if [ "$lowerword" == "true" ]; then
    lexicon_lower=data/local/filtered_lower_lexicon.txt
    mylocal/lower_lexicon.pl $roman_opt $lexicon_file $lexicon_lower
    lexicon_file=$lexicon_lower
  fi

  if [ ! -z "$langext_ori" ]; then
    lexiconnew=$( eval echo \$lexicon_file${langext_ori})
    [ ! -f "$lexiconnew" ] && die "no lexicon file $lexiconnew for langext $langext_ori"
    if [ "$replacelex" == "true" ]; then
      echo mylocal/new_lexicon.pl $roman_opt $lexicon_file $lexiconnew data/lexicon${langext}.txt
      mylocal/new_lexicon.pl $roman_opt $lexicon_file $lexiconnew data/lexicon${langext}.txt
    else
      if [[ $lexiconFlags =~ .*--romanized.* ]]; then
        awk 'NR==FNR {a[$1]=1; print} !($1 in a) && !($1 ~ /<.*/) {printf "%s\t",$1; $1="xxxx\t"; print}'  $lexicon_file $lexiconnew > data/lexicon${langext}.txt
      else
        awk 'NR==FNR {a[$1]=1; print} !($1 in a) && !($1 ~ /<.*/) {print}'  $lexicon_file $lexiconnew > data/lexicon${langext}.txt
      fi
    fi
    lexicon_file=data/lexicon${langext}.txt
    echo new lexicon $lexicon_file
  fi

  local/prepare_lexicon.pl  --phonemap "$phoneme_mapping" \
    $lexiconFlags $lexicon_file data/local${langext}
fi

[ -d data/lang${langext} ] || mkdir -p data/lang${langext}
if [[ ! -f data/lang${langext}/L.fst || data/lang${langext}/L.fst -ot data/local${langext}/lexicon.txt ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating L.fst etc in data/lang${langext} on" `date`
  echo ---------------------------------------------------------------------
  utils/prepare_lang.sh \
    --share-silence-phones true \
    --position-dependent-phones $posphone \
    data/local${langext} $oovSymbol data/local${langext}/tmp.lang data/lang${langext}
fi

if [ $langsyl == "true" ]; then
  if [[ ! -f data/local${langext}/lexiconp.syl2phn.txt || data/local${langext}/lexiconp.syl2phn.txt -ot data/local${langext}/lexicon.txt ]]; then
    echo ---------------------------------------------------------------------
    echo "Preparing lexicon.wrd2syl.txt in data/local${langext} on" `date`
    echo ---------------------------------------------------------------------
    myutils/prepare_syl_lexicon.pl data/local${langext} data/local${langext}/tmp.lang
  fi

  if [[ ! -f data/lang${langext}/L.fst || data/lang${langext}/L.fst -ot data/local${langext}/lexiconp.syl2phn.txt ]]; then
    echo ---------------------------------------------------------------------
    echo "Creating L.fst etc in data/lang${langext} on" `date`
    echo ---------------------------------------------------------------------
    myutils/prepare_syl_lang.sh \
      --share-silence-phones true \
      --position-dependent-phones $posphone \
      data/local${langext} $oovSymbol data/local${langext}/tmp.lang data/lang${langext}
  fi
fi

if [ $langwrd2syl == true ]; then
  if [ ! -f exp/gen_oov_lex/.done ]; then
    grep '<kwtext>' $dev10h_kwlist_file | cut -f2 -d'>' | cut -f1 -d'<' | tr ' ' '\n' | sort -u | awk 'NR==FNR {a[$1]; next} !($1 in a)' data/local${langext}/lexiconp.wrd2syl.txt /dev/stdin > data/local${langext}/kw.oov.list
    mylocal/gen_oov_lex.sh data/local${langext}/kw.oov.list $g2p_lex_fst exp/gen_oov_lex
    cp exp/gen_oov_lex/oov_lexicon.raw.txt data/local${langext} 
    [[ $lexiconFlags =~ '--romanized' ]] && sed -i -e 's#\t#\txxxxx\t#' -e 's#\-\([0-9]\)# _\1#g' data/local${langext}/oov_lexicon.raw.txt
    touch exp/gen_oov_lex/.done
  fi
  if [[ ! -f data/local${langext}/oov_lexicon.txt || data/local${langext}/oov_lexicon.txt -ot data/local${langext}/oov_lexicon.raw.txt ]]; then
    mylocal/prepare_oov_lexicon.pl --phonemap "$phoneme_mapping" $lexiconFlags data/local${langext}/oov_lexicon.raw.txt data/local${langext}
  fi
  if [[ ! -f data/local${langext}/merge_lexiconp.wrd2syl.txt || data/local${langext}/merge_lexiconp.wrd2syl.txt -ot data/local${langext}/oov_lexicon.txt ]]; then
    mylocal/map_oov_syl.sh data/local${langext} exp/map_oov_syl
    cat data/local${langext}/merge_lexiconp.wrd2syl.txt | awk '{$2="";print}' | sed 's#  #\t#' | myutils/hescii_lex.py > data/local${langext}/merge_lexiconp.wrd2syl.txt.hescii
    grep -v '^<' data/local${langext}/seen.syl  | awk '{printf "%s\t%.1f\t%s\n",$1,0.5,$1}' | cat data/local${langext}/merge_lexiconp.wrd2syl.txt /dev/stdin  > data/local${langext}/mixed_lexiconp.wrd2syl.txt
  fi
  if [[ ! -s data/lang${langext}/Ldet.wrd2syl.fst || data/lang${langext}/Ldet.wrd2syl.fst -ot data/local${langext}/merge_lexiconp.wrd2syl.txt ]]; then
    myutils/prepare_wrd2syl_lang.sh \
      --position-dependent-phones $posphone \
      data/local${langext}/merge_lexiconp.wrd2syl.txt data/local${langext}/tmp.lang data/lang${langext}
  fi
fi

}
