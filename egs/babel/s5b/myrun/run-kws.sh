#!/bin/bash

# Copyright 2014  The Ohio State University (Author: Yanzhang He)
# Apache 2.0.

{

#set -u
set -e
set -o pipefail

function die {
  echo -e "\nERROR:$1\n"; exit 1;
}

echo "$0 $@"

# Begin configuration.
feattype=plp
type=dev10h     # dev10h, eval, evalp1
segmode=uem     # uem, pem
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
sgmm=true
nnet=true
dnn=false
smbr=false
Gorder=
boost=
surfext=
dirext=
decodemode=nnet     # nnet, sgmm
kwsdir=
lmwt=
post_scale=
empirical=false     # whether to use empirical thresholding
fraction=           # for empirical thresholding
final_thresh=       # threshold on the final (possibly normalized) score

# for tuning
tune=false          # set it true for tuning
tune_type=all       # all, iv, oov
lmwt_init=8
lmwt_step=5
post_scale_init=8
post_scale_step=5
fraction_init=0.1
fraction_step=0.05
# End of configuration.

. ./path.sh

. parse_options.sh || die "no parse_options.sh found!"

if [ $# -gt 0 ]; then
  echo "usage: ./run-decode.sh"
  echo " e.g.: ./run-decode.sh --stage=0 --stage2=5 --traindata=train_swb"
  echo "       run script from stage 0 to stage 5 (included)"
  die
fi

. lang.conf || die "no lang.conf file"
. $cmd || die "no $cmd file"

[ $feattype == "plp" ] && feattype=plp_pitch 
traindata=train_$feattype
typedata=${type}_${segmode}_$feattype
[ $type == eval ] && skip_scoring=true
[ $langsyl == true ] && sylext=_syl && skip_scoring=true && sgmm=false && nnet=true && dnn=false          # we don't do sgmm decoding for syl mode now

# if trainlangext is not set and langext starts with _nop, set trainlangext as _nop
#[ -z $trainlangext ] && [[ "$langext" =~ ^_nop ]] && trainlangext="_nop"
[ -z $trainlangext ] && [[ "$langext" =~ ^_nop ]] && trainlangext="$langext"


type_nj=$(eval echo \$${type}_nj)

if [ ! -z "$acwt" ]; then acwtarg="--acwt $acwt "; acwtext="_acwt$acwt"; fi

if [ "$decodemode" == "sgmm" ]; then
  decode=exp/${traindata}_sgmm5${trainlangext}/decode_${typedata}${langext}${acwtext}${boost}
elif [ "$decodemode" == "nnet" ]; then
  [ -z $nnetdir ] && nnetdir=${traindata}_tri6_nnet${trainlangext}
  [ $nnetlatbeam != 8 ] && beamext=_beam$nnetlatbeam || beamext=''
  decode=exp/${nnetdir}/decode_${typedata}${langext}${acwtext}${beamext}${sylext}${Gorder}${boost}
else
  echo "Error in $0: Bad value for decodemode."
  exit 1
fi

echo "Waiting till $decode/.done exists...."
while [ ! -f $decode/.done ]; do sleep 30; done
echo "...done waiting for $decode/.done"

kwsext=${surfext}${dirext}
#[ ! -z $kwsext ] && kwsext_opt="--kwsext $kwsext" || kwsext_opt=
[ ! -z $final_thresh ] && final_thresh_opt="--final-thresh $final_thresh" || final_thresh_opt=

if [ ! -z $surfext ]; then
  word_surface=$( eval echo \$word_surface${surfext})
  word_surface_opt="--word-surface $word_surface"
else
  word_surface_opt=
fi

[ -z $kwsdir ] && kwsdir=$decode/kws${kwsext}
kwsdatadir=$kwsdir/data

echo "kwsdir=$kwsdir"
echo "kwsdatadir=$kwsdatadir"

echo ---------------------------------------------------------------------
echo "Begin preparing kws data in $kwsdatadir on" `date`
echo ---------------------------------------------------------------------

if [ ! -f $kwsdatadir/.done ]; then
  if [[ "$type" =~ "dev10h" || "$type" =~ "evalp1" ]]; then
    rttm_file=$(eval echo \$${type}_rttm_file)
    ecf_file=$(eval echo \$${type}_ecf_file)
    kwlist_file=$(eval echo \$${type}_kwlist_file)
    scoring_ecf_file=$(eval echo \$${type}_scoring_ecf_file)
    mylocal/kws_setup.sh --case_insensitive $case_insensitive \
      --rttm-file $rttm_file "${icu_opt[@]}" \
      --kwsdatadir $kwsdatadir $word_surface_opt \
      $ecf_file $kwlist_file data/lang${langext} data/$typedata
    cp $scoring_ecf_file $kwsdatadir/scoring.ecf.xml
    chmod 644 $kwsdatadir/scoring.ecf.xml
    [[ "$langpack" =~ _LLP$ ]] && is_llp=1 || is_llp=0
    echo "kwlist2oov.pl $kwlist_file $is_llp > $kwsdatadir/oov.counts"
    kwlist2oov.pl $kwlist_file $is_llp > $kwsdatadir/oov.counts
    touch $kwsdatadir/.done
  else
    echo "Error in $0: currently can only do KWS on the dev10h or the evalp1 set."
    exit 1
  fi
fi

if [ ! -f $kwsdir/.done ] ; then

  if [ "$tune" == "true" ]; then

    echo ---------------------------------------------------------------------
    echo "Starting kws tuning in ${kwsdir}.tmp.xxxxx on" `date`
    echo ---------------------------------------------------------------------
 
    [ ! -z $lmwt_init ] && [ ! -z $lmwt_step ] && \
      [ ! -z $post_scale_init ] && [ ! -z $post_scale_step ] || \
      die "Missing initialized values or step sizes for tuning."

    if [ "$empirical" == "true" ]; then
      [ ! -z $fraction_init ] && [ ! -z $fraction_step ] || \
        die "Missing initialized values or step sizes for tuning with empirical thresholding."
    fi

    tune_log=${kwsdir}.tune.log
    echo "log file: $tune_log"

    if [ "$empirical" == "true" ]; then
      fraction_opt="--fraction #3"
      fraction_step_opt="$fraction_init $fraction_step"
    else
      fraction_opt=
      fraction_step_opt=
    fi

    minimize_nm.pl --tol 0.0005 --n 50 --timeout 18000 --v 2 -- "
      set -u; set -e; set -o pipefail;
      date 1>&2; echo 1>&2;
      kwsdir_tmp=${kwsdir}.tmp.\$\$;
      kwsdir_tmp_log=\${kwsdir_tmp}.log;
      echo logfile: \$kwsdir_tmp_log 1>&2; echo 1>&2;
      mylocal/run_kws_stt_task.sh \
        --cer $cer --max-states $max_states --cmd $decode_cmd \
        --skip-kws false --skip-stt true --wip $wip \
        --lmwt #1 --post-scale #2 $fraction_opt --empirical $empirical \
        $final_thresh_opt \
        --kwsdatadir $kwsdatadir --kwsout_dir \$kwsdir_tmp \
        data/$typedata data/lang${langext} $decode &> \$kwsdir_tmp_log;
      lmwt_curr=\`head -1 \$kwsdir_tmp/lmwt.txt\`;
      post_scale_curr=\`head -1 \$kwsdir_tmp/post_scale.txt\`;
      fraction_curr=\`head -1 \$kwsdir_tmp/fraction.txt\`;
      wip_curr=\`head -1 \$kwsdir_tmp/wip.txt\`;
      echo lmwt: \$lmwt_curr, post_scale: \$post_scale_curr, fraction: \$fraction_curr, wip: \$wip_curr 1>&2;
      mylocal/show_atwv.sh \${kwsdir_tmp}/search_\$lmwt_curr 1>&2;
      atwv=\`mylocal/show_atwv.sh --type $tune_type \${kwsdir_tmp}/search_\$lmwt_curr\`;
      [[ \"\$atwv\" =~ ^- ]] && neg_atwv=\${atwv:1} || neg_atwv=\"-\$atwv\";
      echo \$neg_atwv;
      rm -r \${kwsdir_tmp}*;
      echo 1>&2; date 1>&2; echo 1>&2;" \
      $lmwt_init $lmwt_step \
      $post_scale_init $post_scale_step \
      $fraction_step_opt \
      > $tune_log 2>&1

    # get the tuned parameter values
    if ! `tail -1 $tune_log | grep -q "^Best Values: "`; then
	echo "Error: the tuning was not successful for $tune_log!"
	exit 1
    fi

    lmwt=`tail -1 $tune_log | cut -d' ' -f3`
    post_scale=`tail -1 $tune_log | cut -d' ' -f4`
    [ "$empirical" == "true" ] && fraction=`tail -1 $tune_log | cut -d' ' -f5`

    printf -v lmwt "%.2f" $lmwt
    printf -v post_scale "%.2f" $post_scale
    [ "$empirical" == "true" ] && printf -v fraction "%.4f" $fraction

    # Write config
    echo best values:
    echo "lmwt $lmwt"
    echo "post_scale $post_scale"
    [ "$empirical" == "true" ] && echo "fraction $fraction"
    #echo "wip $wip"

    echo ---------------------------------------------------------------------
    echo "Finished kws tuning successfully on" `date`
    echo ---------------------------------------------------------------------

  fi
  
  lmwt_opt=${lmwt_plp_extra_opts[@]}
  [ ! -z $lmwt ] && lmwt_opt="--lmwt $lmwt"
  [ ! -z $post_scale ] && post_scale_opt="--post-scale $post_scale" || post_scale_opt=
  [ ! -z $fraction ] && fraction_opt="--fraction $fraction" || fraction_opt=

  echo ---------------------------------------------------------------------
  echo "Starting kws in $kwsdir on" `date`
  echo ---------------------------------------------------------------------
  mylocal/run_kws_stt_task.sh --cer $cer --max-states $max_states \
    --cmd $decode_cmd --skip-kws false --skip-stt true --wip $wip \
    $lmwt_opt $post_scale_opt $fraction_opt --empirical $empirical $final_thresh_opt \
    --kwsdatadir $kwsdatadir --kwsout_dir $kwsdir \
    data/$typedata data/lang${langext} $decode

  touch $kwsdir/.done
fi

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------

exit 0
}
