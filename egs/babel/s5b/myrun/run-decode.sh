#!/bin/bash

{

set -e
set -o pipefail

function die {
  echo -e "\nERROR:$1\n"; exit 1;
}

echo "$0 $@"

# Begin configuration.
stage=0
stage2=100      # we don't have more than 100 stages, isn't it?
feattype=plp
type=dev10h     # dev10h, eval
segmode=pem     # uem, pem
skip_scoring=false
cmd='./cmd.sh'
acwt=
langext=
langsyl=false
nnetdir=
sgmmbeam=
sgmmlatbeam=13
nnetlatbeam=8
dnnlatbeam=8
sgmm=false
nnet=false
dnn=true
dnndir=
dnnfeattype=
smbr=false
sgmmmmi=false
skip_convert=true
Gorder=
boost=
flatstart=true
# End of configuration.

. ./path.sh
. parse_options.sh || die "no parse_options.sh found!"
. $cmd || die "no $cmd file"
. ./lang.conf || die "no lang.conf file"

if [ $# -gt 0 ]; then
  echo "usage: ./run-decode.sh"
  echo " e.g.: ./run-decode.sh --stage=0 --stage2=5 --traindata=train_swb"
  echo "       run script from stage 0 to stage 5 (included)"
  die
fi

[ $feattype == "plp" ] && feattype=plp_pitch 
traindata=train_$feattype
typedata=${type}_${segmode}_$feattype

[ "$type" == eval ] && skip_scoring=true
[ "$type" == unsup ] && skip_scoring=true && skip_convert=true && scoring_opts="--skip-scoring true"
[ "$segmode" == unseg ] && skip_scoring=true && skip_convert=true
[ $langsyl == true ] && sylext=_syl && skip_scoring=true && sgmm=false && nnet=true && dnn=false && skip_convert=true         # we don't do sgmm decoding for syl mode now

[[ "$langext" =~ _nop ]] && trainlangext="${langext}" || trainlangext=""
echo "trainlangext=$trainlangext"
if [ $flatstart == false ]; then
  trainlangext="${trainlangext}_plpalign"
fi

type_nj=$(eval echo \$${type}_nj)

if [ ! -z "$acwt" ]; then acwtarg="--acwt $acwt "; acwtext="_acwt$acwt"; fi

echo ---------------------------------------------------------------------
echo "Begin decoding on" `date`
echo ---------------------------------------------------------------------

echo "Waiting till exp/${traindata}_tri5${trainlangext}/.done exists...."
while [ ! -f exp/${traindata}_tri5${trainlangext}/.done ]; do sleep 30; done
echo "...done waiting for exp/${traindata}_tri5${trainlangext}/.done"

if [ $langsyl == "false" ]; then  # default graph
  if [ -z $boost ]; then
    graphdir=exp/${traindata}_tri5${trainlangext}/graph${langext}
    if [ ! -f $graphdir/.done ]; then
      myutils/mkgraph.sh data/lang${langext} exp/${traindata}_tri5${trainlangext} $graphdir
      touch $graphdir/.done
    fi
  else
    graphdir=exp/${traindata}_tri5${trainlangext}/graph${langext}${boost}
    if [ ! -f $graphdir/.done ]; then
      Gmiddle=$(echo $boost | sed 's#_#.#')
      Lmiddle=$(echo $boost | sed 's#_#.#')
      myutils/mkgraph.sh --Gmiddle $Gmiddle --Lmiddle $Lmiddle data/lang${langext} exp/${traindata}_tri5${trainlangext} $graphdir
      touch $graphdir/.done
    fi
  fi
else
  graphdir=exp/${traindata}_tri5${trainlangext}/graph${langext}${sylext}${Gorder}
  if [ ! -f $graphdir/.done ]; then
    myutils/mkgraph.sh --Gmiddle $Gorder'.syl' --Lmiddle '.syl2phn' data/lang${langext} exp/${traindata}_tri5${trainlangext} $graphdir
    touch $graphdir/.done
  fi
fi

decode=exp/${traindata}_tri5${trainlangext}/decode_${typedata}${langext}${acwtext}${sylext}${Gorder}${boost}
if [ ! -f $decode/.done ]; then
  #By default, we do not care about the lattices for this step -- we just want the transforms
  #Therefore, we will reduce the beam sizes, to reduce the decoding times
  # but for unsup data, we do care the WER
  beam=10
  lattice_beam=4
  [ $type == unsup ] && beam=13 && lattice_beam=8
  mysteps/decode_fmllr_extra.sh --skip-scoring true --beam $beam --lattice-beam $lattice_beam $acwtarg \
    --nj $type_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}" \
    $graphdir data/${typedata} $decode

  touch $decode/.done
fi

if [ "$type" == unsup ] && [ ! -f $decode/.done.bestpath ]; then
  $decode_cmd JOB=1:$type_nj $decode/log/best_path.JOB.log \
    lattice-best-path --acoustic-scale=0.1 \
    "ark,s,cs:gunzip -c $decode/lat.JOB.gz |" \
    ark:/dev/null "ark:| gzip -c > $decode/ali.JOB.gz"

  touch $decode/.done.bestpath
fi

if [ $nnet == true ]; then

[ -z $nnetdir ] && nnetdir=${traindata}_tri6_nnet${trainlangext}
echo "Waiting till exp/${nnetdir}/final.mdl exists...."
while [ ! -f exp/${nnetdir}/final.mdl ]; do sleep 30; done
echo "...done waiting for exp/${nnetdir}/final.mdl"
[ $nnetlatbeam != 8 ] && beamext=_beam$nnetlatbeam || beamext=''
decode=exp/${nnetdir}/decode_${typedata}${langext}${acwtext}${beamext}${sylext}${Gorder}${boost}
if [ ! -f $decode/.done ] || [ ! -f $decode/.done.score ]; then
  echo ---------------------------------------------------------------------
  echo "Starting $decode on" `date`
  echo ---------------------------------------------------------------------

  [ ! -f $decode/.done ] && nnetstage=1 || nnetstage=2      # do decode if not done, do scoring depend on skip-scoring otherwise
  mysteps/decode_nnet_cpu.sh --cmd "$decode_cmd" --nj $type_nj $acwtarg --lat-beam $nnetlatbeam \
  "${decode_extra_opts[@]}" --transform-dir exp/${traindata}_tri5${trainlangext}/decode_${typedata}${langext}${acwtext}${sylext}${Gorder}${boost} --skip-scoring $skip_scoring --stage $nnetstage --scoring-opts "$scoring_opts" \
    $graphdir data/$typedata $decode
  touch $decode/.done
fi

if [ ! -f $decode/.done.convert ] && [ -f $decode/.done ] && [ "$skip_convert" == false ]; then
  if [ -z $boost ]; then
    myutils/convert_slf.sh --cmd "$decode_cmd" "${convert_extra_opts[@]}" data/$typedata data/lang${langext} exp/${nnetdir} $decode
  else 
    myutils/convert_slf.sh --cmd "$decode_cmd" "${convert_extra_opts[@]}" --wordsmiddle ".merge" data/$typedata data/lang${langext} exp/${nnetdir} $decode
  fi

  touch $decode/.done.convert
fi

if [ ! -f $decode/.done.convertsyl ] && [ -f $decode/.done ] && [ "$langsyl" == true ]; then
  myutils/convert_slf.sh --cmd "$decode_cmd" "${convert_extra_opts[@]}" --outputext syl --lower false data/$typedata $graphdir exp/${nnetdir} $decode
  touch $decode/.done.convertsyl
fi

if ! $fast_path ; then
  if [ ! -f exp/${nnetdir}/decode_${typedata}${langext}/.kws.done ]; then
    echo ---------------------------------------------------------------------
    echo "Starting exp/${nnetdir}/decode_${typedata}${langext}/kws on" `date`
    echo ---------------------------------------------------------------------
    mylocal/run_kws_stt_task.sh --cer $cer --max-states $max_states \
      --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
      "${lmwt_plp_extra_opts[@]}" \
      data/${typedata} data/lang${langext}  exp/${nnetdir}/decode_${typedata}${langext}
    
    touch exp/${nnetdir}/decode_${typedata}${langext}/.kws.done
  fi
fi

fi

if [ $sgmm == true ]; then
echo "Waiting till exp/${traindata}_sgmm5${trainlangext}/.done exists...."
while [ ! -f exp/${traindata}_sgmm5${trainlangext}/.done ]; do sleep 30; done
echo "...done waiting for exp/${traindata}_sgmm5${trainlangext}/.done"
decode=exp/${traindata}_sgmm5${trainlangext}/decode_${typedata}${langext}${acwtext}${boost}
if [ ! -f $decode/.done ] || [ ! -f $decode/.done.score ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning $decode on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang${langext} exp/${traindata}_sgmm5${trainlangext} exp/${traindata}_sgmm5${trainlangext}/graph${langext} |tee exp/${traindata}_sgmm5${trainlangext}/mkgraph${langext}.log

  mkdir -p $decode
  [ ! -f $decode/.done ] && sgmmstage=1 || sgmmstage=7      # do decode if not done, do scoring depend on skip-scoring otherwise
  mysteps/decode_sgmm2.sh --skip-scoring $skip_scoring --use-fmllr true --nj $type_nj $acwtarg \
    --cmd "$decode_cmd" --transform-dir exp/${traindata}_tri5${trainlangext}/decode_${typedata}${langext}${acwtext} "${decode_extra_opts[@]}" --lattice-beam $sgmmlatbeam --stage $sgmmstage \
    exp/${traindata}_sgmm5${trainlangext}/graph${langext} data/$typedata $decode |tee $decode/decode.log
  touch $decode/.done
fi

if [ ! -f $decode/.done.convert ] && [ -f $decode/.done ] && [ "$skip_convert" == false ]; then
  myutils/convert_slf.sh --cmd "$decode_cmd" "${convert_extra_opts[@]}" data/$typedata data/lang${langext} exp/${traindata}_sgmm5${trainlangext} $decode
  touch $decode/.done.convert
fi

if ! $fast_path ; then
  local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
    data/$typedata data/lang${langext}  $decode
fi

fi

if [ $dnn == true ]; then

[ -z $dnndir ] && dnndir=exp/${traindata}_tri8_dnn${trainlangext}
echo "Waiting till ${dnndir}/final.mdl exists...."
while [ -d $dnndir ] && [ ! -f ${dnndir}/final.mdl ]; do sleep 30; done
echo "...done waiting for ${dnndir}/final.mdl"
decode=${dnndir}/decode_${typedata}${langext}${acwtext}${beamext}
if [ -d $dnndir ] && [[ ! -f $decode/.done || ! -f $decode/.done.score ]]; then
  echo ---------------------------------------------------------------------
  echo "Starting $decode on" `date`
  echo ---------------------------------------------------------------------

  [ ! -f $decode/.done ] && dnnstage=0 || dnnstage=1      # do decode if not done, do scoring depend on skip-scoring otherwise
  [[ $typedata =~ "semi_fmllr" ]] && $feattype_opt="--feat-type fmllr"
  mysteps/decode_nnet.sh --cmd "$decode_cmd -l mem_free=6G" --nj $type_nj --latbeam $dnnlatbeam --acwt 0.0833 \
    --scoring-opts "--min-lmwt 6 --max-lmwt 16 --wip 0.2" --stage $dnnstage $feattype_opt --feat-type "$dnnfeattype" \
    --transform-dir exp/${traindata}_tri5${trainlangext}/decode_${typedata}${langext}${acwtext} --skip-scoring $skip_scoring \
    exp/${traindata}_tri5${trainlangext}/graph${langext} data/$typedata $decode
  touch $decode/.done
fi

if [ "$type" == unsup ] && [ ! -f $decode/.done.bestpath ]; then
  $decode_cmd JOB=1:$type_nj $decode/log/best_path.JOB.log \
    lattice-best-path --acoustic-scale=0.1 \
    "ark,s,cs:gunzip -c $decode/lat.JOB.gz |" \
    ark:/dev/null "ark:| gzip -c > $decode/ali.JOB.gz"

  touch $decode/.done.bestpath
fi

if [ ! -f $decode/.done.convert ] && [ -f $decode/.done ] && [ "$skip_convert" == false ]; then
  myutils/convert_slf.sh --cmd "$decode_cmd" "${convert_extra_opts[@]}" data/$typedata data/lang${langext} exp/${dnndir} $decode
  touch $decode/.done.convert
fi

fi

if [ $smbr == true ]; then

[ -z $smbrdir ] && smbrdir=${traindata}_tri8_dnn_smbr${trainlangext}
echo "Waiting till exp/${smbrdir}/final.mdl exists...."
while [ -d $smbrdir ] &&  [ ! -f exp/${smbrdir}/final.mdl ]; do sleep 30; done
echo "...done waiting for exp/${smbrdir}/final.mdl"
decode=exp/${smbrdir}/decode_${typedata}${langext}${acwtext}${beamext}
if [ -d $smbrdir ] && [[ ! -f $decode/.done || ! -f $decode/.done.score ]]; then
  echo ---------------------------------------------------------------------
  echo "Starting $decode on" `date`
  echo ---------------------------------------------------------------------

  [ ! -f $decode/.done ] && smbrstage=0 || smbrstage=1      # do decode if not done, do scoring depend on skip-scoring otherwise
  mysteps/decode_nnet.sh --cmd "$decode_cmd" --nj $type_nj --latbeam $dnnlatbeam --acwt 0.0833 \
    --scoring-opts "--min-lmwt 4 --max-lmwt 20 --wip 0.2" --stage $smbrstage \
    --transform-dir exp/${traindata}_tri5${trainlangext}/decode_${typedata}${langext}${acwtext} --skip-scoring $skip_scoring \
    exp/${traindata}_tri5${trainlangext}/graph${langext} data/$typedata $decode
  touch $decode/.done
fi

if [ ! -f $decode/.done.convert ] && [ -f $decode/.done ]; then
  myutils/convert_slf.sh --cmd "$decode_cmd" "${convert_extra_opts[@]}" data/$typedata data/lang${langext} exp/${smbrdir} $decode
  touch $decode/.done.convert
fi

fi

if [ $sgmmmmi == true ]; then
echo "Waiting till exp/${traindata}_sgmm5_mmi_b0.1${trainlangext}/.done exists...."
while [ ! -f exp/${traindata}_sgmm5_mmi_b0.1${trainlangext}/.done ]; do sleep 30; done
echo "...done waiting for exp/${traindata}_sgmm5_mmi_b0.1${trainlangext}/.done"
for iter in 1 2 3 4; do
decode=exp/${traindata}_sgmm5_mmi_b0.1${trainlangext}/decode_${typedata}${langext}${acwtext}${boost}_it$iter
if [ ! -f $decode/.done ] || [ ! -f $decode/.done.score ]; then
  echo ---------------------------------------------------------------------
  echo "Start $decode on" `date`
  echo ---------------------------------------------------------------------
  [ -d $decode ] || mkdir -p $decode
  steps/decode_sgmm2_rescore.sh --skip-scoring $skip_scoring \
    --cmd "$decode_cmd" --iter $iter --transform-dir exp/${traindata}_tri5${trainlangext}/decode_${typedata}${langext}${acwtext} \
    data/lang data/$typedata exp/${traindata}_sgmm5${trainlangext}/decode_${typedata}${langext}${acwtext}${boost} \
    $decode |tee $decode/decode.log
  touch $decode/.done
fi
#if [ ! -f $decode/.done.convert ] && [ -f $decode/.done ] && [ $langsyl == false ] && [ $type != "unsup" ]; then
#  myutils/convert_slf.sh --cmd "$decode_cmd" "${convert_extra_opts[@]}" data/$typedata data/lang${langext} exp/${traindata}_sgmm5_mmi_b0.1${trainlangext} $decode
#  touch $decode/.done.convert
#fi
done
fi

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------

exit 0
}
