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
cmd=myutils/run.pl
feattype=plp
posphone=true
# End of configuration

. ./path.sh
. parse_options.sh
. ./lang.conf

langext_ori=$langext
[[ "$langext" =~ ^_nop ]] && die "we don't support langext == _nop*, please switch"
[ "$posphone" == "false" ] && langext=_nop$langext

[ -d data/srilm${langext} ] || mkdir -p data/srilm${langext}
if [ ! -f data/srilm${langext}/lm.gz ]; then
  if [ ! -z "$langext_ori" ]; then
    lmnew=$(eval echo \$lm${langext_ori})
    [ -f "$lmnew" ] || die "no lm $lmnew matched, please provide lm${langext_ori}"
    echo ---------------------------------------------------------------------
    echo "Copy language model $lmnew to data/srilm${langext} on" `date`
    echo ---------------------------------------------------------------------
    cp $lmnew data/srilm${langext}/lm
    gzip data/srilm${langext}/lm
  else
    echo ---------------------------------------------------------------------
    echo "Training SRILM language models on" `date`
    echo ---------------------------------------------------------------------
    local/train_lms_srilm.sh --dev-text data/dev10h/text \
      --train-text data/train/text data data/srilm${langext}
  fi
fi

if [[ ! -f data/lang${langext}/G.fst || data/lang${langext}/G.fst -ot data/srilm${langext}/lm.gz ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating G.fst on " `date`
  echo ---------------------------------------------------------------------
  local/arpa2G.sh data/srilm${langext}/lm.gz data/lang${langext} data/lang${langext}
fi

if [ $langsyl == "true" ]; then
  echo ---------------------------------------------------------------------
  echo "Preparing syllable transcription on " `date`
  echo ---------------------------------------------------------------------
  [ $posphone == 'false' ] && expext='_nop'

  [ -z $feattype ] && echo "please provide an alignment dir for syl lm training" && exit 1;
  [ $feattype == plp ] && traindata=train_plp_pitch || traindata=train_$feattype
  if [ ! -f exp/${traindata}_tri5_ali${expext}/syl_text/.done ]; then
    mylocal/wrd2syl_ali.sh --cmd $cmd --posphone $posphone data/local${langext}/tmp.lang/lexiconp.txt data/local${langext}/lexiconp.wrd2syl.txt data/lang${langext} data/$traindata exp/${traindata}_tri5_ali${expext} exp/${traindata}_tri5_ali${expext}/syl_text
    touch exp/${traindata}_tri5_ali${expext}/syl_text/.done
  fi

  if [[ ! -f exp/${traindata}_tri5_ali${expext}/syl_text/srilm/lm.gz || exp/${traindata}_tri5_ali${expext}/syl_text/srilm/lm.gz -ot exp/${traindata}_tri5_ali${expext}/syl_text/text ]]; then
    mylocal/wrd2syl.pl data/local${langext}/lexiconp.wrd2syl.txt < data/dev10h/text > data/dev10h/syl_text
    local/train_lms_srilm.sh --words-file data/lang${langext}/syls.txt --train-text exp/${traindata}_tri5_ali${expext}/syl_text/text --dev-text data/dev10h/syl_text data exp/${traindata}_tri5_ali${expext}/syl_text/srilm
  fi

  if [[ ! -f data/lang${langext}/G.syl.fst || data/lang${langext}/G.syl.fst -ot exp/${traindata}_tri5_ali${expext}/syl_text/srilm/lm.gz ]]; then
    mylocal/arpa2G.sh --Gfst G.syl.fst --words syls.txt exp/${traindata}_tri5_ali${expext}/syl_text/srilm/lm.gz data/lang${langext} data/lang${langext}
  fi

fi

if [ $langwrd2syl == "true" ]; then
  echo ---------------------------------------------------------------------
  echo "Creating G.boost.fst on " `date`
  echo ---------------------------------------------------------------------
#  mine is not as good
#  if [[ ! -f data/srilm${langext}/lm.boost.gz || data/srilm${langext}/lm.boost.gz -ot data/srilm${langext}/lm.gz ]]; then
#    mylocal/boost_lm.sh $dev10h_kwlist_file data/srilm${langext}
#  fi

  gzip -c lm/boost/SRS-GO/data/lms/origseg/llp.mKN.wkeywords.eval.lm > data/srilm${langext}/lm.boost.gz

  if [[ ! -s data/lang${langext}/G.boost.fst || data/lang${langext}/G.boost.fst -ot data/srilm${langext}/lm.boost.gz ]]; then
    mylocal/arpa2G_wrd2syl.sh data/srilm${langext}/lm.boost.gz data/lang${langext} data/lang${langext}
  fi

fi
}
