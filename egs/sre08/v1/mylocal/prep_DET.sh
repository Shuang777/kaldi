#!/bin/bash

scorefile=score
. parse_options.sh

if [ $# != 3 ]; then
  echo "Usage: $0 <expdir> <test-truth> <train-spk2utt>"
  echo " e.g.: $0 exp/scoring_swbd_keywords/merge/test_male data/swbd_keywords/merge/test_male/utt2spk.truth data/swbd_keywords/merge/train_male/spk2utt"
  exit 1;
fi

expdir=$1
utt2spktruth=$2
spk2utt=$3

[ ! -f $expdir/$scorefile ] && echo "no $expdir/$scorefile found!" && exit 1

awk 'BEGIN{spk=""} {if (spk != $1 && spk != "") printf "\n" ; spk=$1; printf "%s ",$3}' $expdir/$scorefile > $expdir/score.mat

awk '{print $2,$1}' $utt2spktruth > $expdir/test.label
awk '{print $1}' $spk2utt > $expdir/train.label

mylocal/compute_eer_script_v4trainpooled.pl -a $expdir/train.label -e $expdir/test.label -s $expdir/score.mat -r $expdir
cat $expdir/extended_results.A.min
