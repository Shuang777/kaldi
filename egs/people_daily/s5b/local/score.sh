#!/bin/bash
# Copyright Johns Hopkins University (Author: Daniel Povey) 2012.  Apache 2.0.

orig_args=
for x in "$@"; do orig_args="$orig_args '$x'"; done

# begin configuration section.  we include all the options that score_sclite.sh or
# score_basic.sh might need, or parse_options.sh will die.
# CAUTION: these default values do not have any effect because of the
# way pass things through to the scripts that this script calls.
cmd=run.pl
stage=0
min_lmwt=16
max_lmwt=25
reverse=false
#end configuration section.

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 3 ]; then
  echo "Usage: local/score.sh [options] <data-dir> <lang-dir|graph-dir> <decode-dir>" && exit;
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "    --stage (0|1|2)                 # start scoring script from part-way through."
  echo "    --min_lmwt <int>                # minumum LM-weight for lattice rescoring "
  echo "    --max_lmwt <int>                # maximum LM-weight for lattice rescoring "
  echo "    --reverse (true/false)          # score with time reversed features "
  exit 1;
fi

data=$1

if [ -f $data/stm ]; then # use sclite scoring.
  echo "$data/stm exists: using local/score_sclite.sh"
  eval local/score_sclite.sh --min-lmwt $min_lmwt --max-lmwt $max_lmwt $orig_args 
else
  echo "$data/stm does not exist: using local/score_basic.sh"
  eval local/score_basic.sh $orig_args
fi
