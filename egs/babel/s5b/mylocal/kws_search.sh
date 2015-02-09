#!/bin/bash

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen, Yenda Trmal, Hang Su)
# Copyright 2014  ICSI (Author: Hang Su)
# Copyright 2014  The Ohio State University (Author: Yanzhang He)
# Apache 2.0.
{
set -u
set -e
set -o pipefail

help_message="$(basename $0): do keyword indexing and search.  data-dir is assumed to have
                 kws/ subdirectory that specifies the terms to search for.  Output is in
                 decode-dir/kws/
             Usage:
                 $(basename $0) <lang-dir> <data-dir> <decode-dir>"

# Begin configuration section.  
#acwt=0.0909091
min_lmwt=7
max_lmwt=17
post_scale=  # posterior scale
empirical=false     # whether to use empirical thresholding
fraction=           # for empirical thresholding
final_thresh=       # threshold on the final (possibly normalized) score
duptime=0.6
cmd=run.pl
model=
skip_scoring=false
skip_optimization=false # true can speed it up if #keywords is small.
max_states=150000
kwsout_dir=
stage=0
word_ins_penalty=0
silence_word=  # specify this if you did to in kws_setup.sh, it's more accurate.
ntrue_scale=1.0
max_silence_frames=50
kwsext=
kwsdatadir=
verbose=0
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;


if [[ "$#" -ne "3" ]] ; then
    echo -e "$0: FATAL: wrong number of script parameters!\n\n"
    printf "$help_message\n\n"
    exit 1;
fi

silence_opt=

langdir=$1
datadir=$2
decodedir=$3

if [ -z $kwsdatadir ]; then
  kwsdatadir=$datadir/kws${kwsext}
fi

if [ -z $kwsout_dir ] ; then
  kwsoutdir=$decodedir/kws${kwsext}
else
  kwsoutdir=$kwsout_dir
fi
mkdir -p $kwsoutdir
mkdir -p $kwsoutdir/log

if [ ! -d "$datadir"  ] || [ ! -d "$kwsdatadir" ] ; then
    echo "FATAL: the data directory does not exist"
    exit 1;
fi
if [[ ! -d "$langdir"  ]] ; then
    echo "FATAL: the lang directory does not exist"
    exit 1;
fi
if [[ ! -d "$decodedir"  ]] ; then
    echo "FATAL: the directory with decoded files does not exist"
    exit 1;
fi
if [[ ! -f "$kwsdatadir/ecf.xml"  ]] ; then
    echo "$0: FATAL: the $kwsdatadir does not contain the ecf.xml file"
    exit 1;
fi

echo $kwsdatadir
duration=`head -1 $kwsdatadir/ecf.xml |\
    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
    perl -e 'while($m=<>) {$m=~s/.*\"([0-9.]+)\".*/\1/; print $m/2;}'`

#duration=`head -1 $kwsdatadir/ecf.xml |\
#    grep -o -E "duration=\"[0-9]*[    \.]*[0-9]*\"" |\
#    grep -o -E "[0-9]*[\.]*[0-9]*" |\
#    perl -e 'while(<>) {print $_/2;}'`

echo "Duration: $duration"

if [ ! -z "$model" ]; then
    model_flags="--model $model"
else
    model_flags=
fi

[ ! -z $fraction ] && fraction_opt="--fraction=$fraction" || fraction_opt=
[ ! -z $final_thresh ] && final_thresh_opt="--final-thresh $final_thresh" || final_thresh_opt=

[ -f $kwsdatadir/oov.counts ] && oov_count_opt="--oov-count-file=$kwsdatadir/oov.counts" || oov_count_opt=

if [ -f $kwsoutdir/.done ]; then
  echo "KWS in $kwsoutdir has already been done. Skip."
  echo "If you want to re-run it, delete the file $kwsoutdir/.done"
  exit 0
fi

rm -f $kwsoutdir/lmwt.txt $kwsoutdir/post_scale.txt $kwsoutdir/fraction.txt $kwsoutdir/wip.txt
if [ $stage -le 0 ] ; then
  if [ ! -f $kwsoutdir/.done.index ] ; then
    for lmwt in `seq $min_lmwt $max_lmwt` ; do
        indices=${kwsoutdir}/indices_$lmwt
        mkdir -p $indices
  
        # posterior scale is by default the same as the lm scale
        [ ! -z $post_scale ] && post_scale_curr=$post_scale || post_scale_curr=$lmwt
        echo $lmwt >> $kwsoutdir/lmwt.txt
        echo $post_scale_curr >> $kwsoutdir/post_scale.txt
        echo $fraction >> $kwsoutdir/fraction.txt
        echo $word_ins_penalty >> $kwsoutdir/wip.txt

        #acwt=`echo "scale=5; 1/$lmwt" | bc -l | sed "s/^./0./g"` 
        #acwt=`perl -e "print (1.0/$lmwt);"` 
        acwt=`perl -e "print (1.0/$post_scale_curr);"` 
        lmwt=`perl -e "print ($lmwt/$post_scale_curr);"` 
        [ ! -z $silence_word ] && silence_opt="--silence-word $silence_word"
        mysteps/make_index.sh $silence_opt --cmd "$cmd" --acwt $acwt --lmwt $lmwt \
          $model_flags --skip-optimization $skip_optimization --max-states $max_states \
          --word-ins-penalty $word_ins_penalty --max-silence-frames $max_silence_frames \
          $kwsdatadir $langdir $decodedir $indices  || exit 1
    done
    touch $kwsoutdir/.done.index
  else
    echo "Assuming indexing has been aready done. If you really need to re-run "
    echo "the indexing again, delete the file $kwsoutdir/.done.index"
  fi
fi


if [ $stage -le 1 ]; then
  if [ ! -f $kwsoutdir/.done.search ]; then
    for lmwt in `seq $min_lmwt $max_lmwt` ; do
        kwsoutput=${kwsoutdir}/search_$lmwt
        indices=${kwsoutdir}/indices_$lmwt
        mkdir -p $kwsoutput
        mysteps/search_index.sh --cmd "$cmd" --indices-dir $indices \
          $kwsdatadir $kwsoutput  || exit 1
    done
    touch $kwsoutdir/.done.search
  fi
fi

if [ "$min_lmwt" == "$max_lmwt" ]; then
  LMWT_tag=$min_lmwt
  LMWT_opt=
else
  LMWT_tag=LMWT
  LMWT_opt="LMWT=$min_lmwt:$max_lmwt"
fi

if [ $stage -le 2 ]; then
  if [ ! -f $kwsoutdir/.done.writenorm ]; then
    echo "Writing normalized results"
    $cmd $LMWT_opt $kwsoutdir/log/write_normalized.${LMWT_tag}.log \
      set -e ';' set -o pipefail ';'\
      cat ${kwsoutdir}/search_${LMWT_tag}/result.* \| \
        myutils/write_kwslist.pl  --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
          --segments=$datadir/segments --normalize=true --duptime=$duptime --remove-dup=true\
          --map-utter=$kwsdatadir/utter_map --digits=3 $oov_count_opt \
          $fraction_opt --empirical=$empirical $final_thresh_opt --verbose $verbose \
          - ${kwsoutdir}/search_${LMWT_tag}/kwslist.xml || exit 1
    touch $kwsoutdir/.done.writenorm
  fi
fi

if [ $stage -le 3 ]; then
  if [ ! -f $kwsoutdir/.done.writeunnorm ]; then
    echo "Writing unnormalized results"
    $cmd $LMWT_opt $kwsoutdir/log/write_unnormalized.${LMWT_tag}.log \
      set -e ';' set -o pipefail ';'\
      cat ${kwsoutdir}/search_${LMWT_tag}/result.* \| \
          myutils/write_kwslist.pl --Ntrue-scale=$ntrue_scale --flen=0.01 --duration=$duration \
            --segments=$datadir/segments --normalize=false --duptime=$duptime --remove-dup=true\
            --map-utter=$kwsdatadir/utter_map $oov_count_opt \
            $fraction_opt --empirical=$empirical $final_thresh_opt --verbose $verbose \
            - ${kwsoutdir}/search_${LMWT_tag}/kwslist.unnormalized.xml || exit 1;
    touch $kwsoutdir/.done.writeunnorm
  fi
fi

if [ $stage -le 4 ]; then
  if [[ (! -x mylocal/kws_score.sh ) ]] ; then
    echo "Not scoring, because the file mylocal/kws_score.sh is not present"
  elif [[ $skip_scoring == true ]] ; then
    echo "Not scoring, because --skip-scoring true was issued"
  else
    echo "Scoring KWS results"
    $cmd $LMWT_opt $kwsoutdir/log/scoring.${LMWT_tag}.log \
       mylocal/kws_score.sh $kwsdatadir ${kwsoutdir}/search_${LMWT_tag} || exit 1;
  fi
fi

touch $kwsoutdir/.done

exit 0
}
