#!/bin/bash

set -e		# exit on errors
set -o pipefail # 

function die {
  echo -e "\nERROR:$1\n"; exit 1;
}

# Begin configuration.
stage=0
stage2=100
feattype=plp      # plp, swd, mfcc, flow
cmd=./cmd.sh
langext=
flatstart=true    # decide which alignment to use, for run-2-triphone.sh
semi=false        # for run-3b-bnf.sh
nnetfeattype=     # for run-3b-bnf.sh, empty or traps
# End of configuration.

echo "$0 $@"

. ./path.sh || die "no ./path.sh file"
. parse_options.sh || die "no parse_options.sh found!"
. $cmd || die "no $cmd file"
. ./lang.conf || die "no ./lang.conf file"

if [ $# -gt 0 ]; then
  echo "usage: $0"
  echo " e.g.: $0 --stage 0 --stage2 4 --langconf lang.conf"
  echo "       run script from stage 0 to stage 4 (included)"
  die
fi

[ $feattype == plp ] && feattype=plp_pitch
traindata=train_$feattype

