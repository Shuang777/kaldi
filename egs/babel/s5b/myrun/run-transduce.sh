#!/bin/bash

{

set -e
set -o pipefail

function die {
  echo -e "\nERROR:$1\n"; exit 1;
}

echo "$0 $@"

# Begin configuration.
feattype=plp
type=dev10h
nnetlatbeam=8
nnet=true
Gorder=
LGmiddle=""
Lmiddle='.wrd2syl'
stage=0
stage2=100
cmd=cmd.sh
langext=
segmode=uem
# End configuration

. ./path.sh;
. parse_options.sh || die "no parse_options.sh found!"
. $cmd || die "no $cmd file"
. lang.conf || die "no lang.conf file"

if [ $# -gt 0 ]; then
  echo "usage: ./run-decode.sh"
  echo " e.g.: ./run-decode.sh --stage=0 --stage2=5 --traindata=train_swb"
  echo "       run script from stage 0 to stage 5 (included)"
  die
fi

[ $feattype == "plp" ] && feattype=plp_pitch 
traindata=train_$feattype
typedata=${type}_${segmode}_$feattype
[ "$langext" == "_nop" ] && trainlangext="_nop" || trainlangext=""

type_nj=$(eval echo \$${type}_nj)

if [ $nnet == true ]; then
[ -z $nnetdir ] && nnetdir=${traindata}_tri6_nnet${trainlangext}
[ $nnetlatbeam != 8 ] && beamext=_beam$nnetlatbeam || beamext=''
decode=exp/${nnetdir}/decode_${typedata}${langext}${acwtext}${beamext}_syl${Gorder}

if [ $stage -le 1 ] && [ $stage2 -ge 1 ]; then
if [ ! -f $decode/.done.trans ] || [ ! -f $decode/.done.transscore ] || [ ! -z "$LGmiddle" ]; then
  echo ---------------------------------------------------------------------
  echo "Starting transduction in $decode on" `date`
  echo ---------------------------------------------------------------------

  [ ! -f $decode/.done.trans ] && nnetstage=1 || nnetstage=2      # do decode if not done, do scoring depend on skip-scoring otherwise
  [ ! -z "$LGmiddle" ] && nnetstage=1
    mysteps/transduce.sh --cmd "$decode_cmd" "${convert_extra_opts[@]}" --stage $nnetstage --Lmiddle $Lmiddle --LGmiddle "$LGmiddle" data/lang${langext} data/$typedata $decode
  touch $decode/.done.trans
fi
fi

if [ $stage -le 2 ] && [ $stage2 -ge 2 ]; then
if [ ! -f $decode/.done.convert ] && [ -f $decode/.done.trans ] || [ ! -z "$LGmiddle" ]; then
  [ -z "$LGmiddle" ] && latname=wrdlat || latname=wrdlatG
  myutils/convert_slf.sh --cmd "$decode_cmd" "${convert_extra_opts[@]}" --latname $latname --wordsmiddle ".merge" data/$typedata data/lang${langext} exp/${nnetdir} $decode
  touch $decode/.done.convert
fi
fi

fi
echo "$0 done $date"
}
