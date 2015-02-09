#!/bin/bash  
# Copyright 2013  Johns Hopkins University (authors: Yenda Trmal)
# Copyright 2014  ICSI (Author: Hang Su)
# Copyright 2014  The Ohio State University (Author: Yanzhang He)

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

#Simple BABEL-only script to be run on generated lattices (to produce the
#files for scoring and for NIST submission
{
set -u
set -e
set -o pipefail

#Begin options
min_lmwt=8
max_lmwt=12
lmwt=
post_scale=  # posterior scale for kws
empirical=false     # whether to use empirical thresholding
fraction=           # for empirical thresholding
final_thresh=       # threshold on the final (possibly normalized) score
cer=0
skip_kws=false
skip_stt=false
skip_scoring=false
extra_kws=false
cmd=run.pl
max_states=150000
dev2shadow=
eval2shadow=
wip=0.5 #Word insertion penalty
wrdsyl=   # empty, syl or syl2wrd
kwsext=
kwsdatadir=
kwsout_dir=
#End of options

if [ $(basename $0) == score.sh ]; then
  skip_kws=true
fi

echo $0 "$@"
. utils/parse_options.sh     

if [ $# -ne 3 ]; then
  echo "Usage: $0 [options] <data-dir> <lang-dir> <decode-dir>"
  echo " e.g.: $0 data/dev10h data/lang exp/tri6/decode_dev10h"
  exit 1;
fi

data_dir=$1; 
lang_dir=$2;
decode_dir=$3; 

type=normal
if [ ! -z ${dev2shadow}  ] && [ ! -z ${eval2shadow} ] ; then
  type=shadow
elif [ -z ${dev2shadow}  ] && [ -z ${eval2shadow} ] ; then
  type=normal
else
  echo "Switches --dev2shadow and --eval2shadow must be used simultaneously" > /dev/stderr
  exit 1
fi

if [ ! -z $lmwt ]; then
  min_lmwt=$lmwt
  max_lmwt=$lmwt
fi

[ ! -z $post_scale ] && post_scale_opt="--post-scale $post_scale" || post_scale_opt=
[ ! -z $fraction ] && fraction_opt="--fraction $fraction" || fraction_opt=
[ ! -z $final_thresh ] && final_thresh_opt="--final-thresh $final_thresh" || final_thresh_opt=
[ ! -z $kwsext ] && kwsext_opt="--kwsext $kwsext" || kwsext_opt=
[ ! -z $kwsdatadir ] && kwsdatadir_opt="--kwsdatadir $kwsdatadir" || kwsdatadir_opt=
[ ! -z $kwsout_dir ] && kwsoutdir_opt="--kwsout-dir $kwsout_dir" || kwsoutdir_opt=

##NB: The first ".done" files are used for backward compatibility only
##NB: should be removed in a near future...
if ! $skip_stt ; then
  [ "$wrdsyl" == "syl2wrd" ] && scoredone=$decode_dir/.done.transscore || scoredone=$decode_dir/.done.score
  if  [ ! -f $scoredone ]; then 
    mylocal/lattice_to_ctm.sh --cmd "$cmd" --word-ins-penalty $wip --wrdsyl "$wrdsyl" \
      --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
      $data_dir $lang_dir $decode_dir

    if [[ "$type" == shadow* ]]; then
      local/split_ctms.sh --cmd "$cmd" --cer $cer \
        --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt}\
        $data_dir $decode_dir ${dev2shadow} ${eval2shadow}
    elif ! $skip_scoring ; then
      mylocal/score_stm.sh --cmd "$cmd"  --cer $cer --wrdsyl "$wrdsyl" \
        --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt}\
        $data_dir $lang_dir $decode_dir
    fi
    touch $scoredone
  fi
fi

if ! $skip_kws ; then
  #if [ ! -f $decode_dir/.kws.done ] && [ ! -f $decode_dir/.done.kws ]; then 
  #  if [[ "$type" == shadow* ]]; then
  #    local/shadow_set_kws_search.sh --cmd "$cmd" --max-states ${max_states} \
  #      --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} \
  #      $kwsext_opt $kwsdatadir_opt $kwsoutdir_opt \
  #      $data_dir $lang_dir $decode_dir ${dev2shadow} ${eval2shadow}
  #  else
      mylocal/kws_search.sh --cmd "$cmd" --max-states ${max_states} \
        --min-lmwt ${min_lmwt} --max-lmwt ${max_lmwt} $post_scale_opt \
        $fraction_opt --empirical $empirical $final_thresh_opt \
        $kwsext_opt $kwsdatadir_opt $kwsoutdir_opt \
        $lang_dir $data_dir $decode_dir
  #  fi
  #  touch $decode_dir/.done.kws
  #fi
  #if $extra_kws && [ -f $data_dir/extra_kws_tasks ]; then
  #  for extraid in `cat $data_dir/extra_kws_tasks` ; do
  #    [ -f $decode_dir/.done.kws.$extraid ] && continue;
  #    mylocal/kws_search.sh --cmd "$cmd" --extraid $extraid  \
  #      --max-states ${max_states} --min-lmwt ${min_lmwt} \
  #      --max-lmwt ${max_lmwt} --indices-dir $decode_dir/kws_indices \
  #      $kwsext_opt $kwsoutdir_opt \
  #      $lang_dir $data_dir $decode_dir
  #    touch $decode_dir/.done.kws.$extraid
  #  done
  #fi
fi

}
