#!/bin/bash
# 10/4/2014 Hang Su 
#
# Computes the score of DEV or EVAL keywords on given lattices.
#
# Prints the negative ATWV. Cleans up after itself.
#
# The lattices must be in hescii format
#
# Useful for calling with minimize_nm.pl to optimize scaling parameters.
#
{

set -o errexit
set -o pipefail

type=dev10h     # dev10h, evalp1
mode=dryrun     # dryrun, tuning
obj=all         # iv, oov, all
lm_scale=20
fraction=0.1
posterior_scale=40
decision_threshold=0
word_surface_file=None
cmd=cmd.sh

arguments="$@"
. parse_options.sh
. ./path.sh
[ "$mode" == dryrun ] && echo "$0 $arguments"

if [ $# -ne 2 ]; then
  echo "Usage: $0 <latticedir> <expdir>"
  echo " e.g.: $0 exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop/convertlat exp/train_plp_pitch_tri6_nnet_nop/decode_dev10h_uem_plp_pitch_nop/convertlat.search"
  exit 1
fi

lattice=$1
expdir=$2

[ -d $expdir/log ] || mkdir -p $expdir/log
mysteps/kws.sh --posterior-scale $posterior_scale \
  --lm-scale $lm_scale --fraction $fraction \
  --decision-threshold $decision_threshold \
  --word-surface-file $word_surface_file \
  --type $type --cmd $cmd \
  $lattice $expdir &> $expdir/log/kws.sh.log

[ ! -f $expdir/scoring.sum.txt ] && echo "no scoring output $expdir/scoring.sum.txt" && exit 1

if [ $obj == all ]; then
  atwv=$(tail -n1 $expdir/scoring.sum.txt | awk '{print $24}')
elif [ $obj == iv ]; then
  atwv=$(tail -n2 $expdir/scoring.cond.sum.txt | head -n1 |  awk '{print $24}')
elif [ $obj == oov ]; then
  atwv=$(tail -n1 $expdir/scoring.cond.sum.txt | awk '{print $24}')
fi

echo -$atwv

}
