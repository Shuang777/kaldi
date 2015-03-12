#!/bin/bash
# This is written by Hang Su (ICSI)
# mostly copied from $KALDI_ROOT/egs/swbd/s5/local/run_tandem_uc.sh
# but made some changed to adapt to Babel data
{

. ./run-header.sh

# Wait till the main run.sh gets to the stage where's it's 
# finished aligning the tri5 model.
echo "Waiting till exp/${traindata}_tri5_ali${langext}/.done exists...."
while [ ! -f exp/${traindata}_tri5_ali${langext}/.done ]; do sleep 30; done
echo "...done waiting for exp/${traindata}_tri5_ali${langext}/.done"

dir=exp/${traindata}_tri7_${nnetfeattype}bn1${langext}
[ $semi == true ] && dir=${dir}_semi
if [ ! -f $dir/.done ]; then
  # Let's train the first network:
  # - the topology will be 90_1200_1200_80_1200_NSTATES, the bottleneck is linear 

  # for traps feature
  # mysteps/train_nnet.sh --hid-layers 2 --hid-dim 1200 --bn-dim 80 --feat-type traps --splice 5 --traps-dct-basis $basis --apply-cmvn $cmvn --learn-rate 0.004 --cv-subset-factor 0.1 \

  # for fmllr feature
  if [ $semi == false ]; then
    $cuda_cmd $dir/train_nnet.log \
    mysteps/train_nnet.sh --hid-layers 2 --hid-dim 1200 --bn-dim 80 --learn-rate 0.002 --cv-subset-factor 0.1 --feat-type "$nnetfeattype" \
      data/$traindata exp/${traindata}_tri5_ali${langext} $dir || exit 1;
  else
    $cuda_cmd $dir/train_nnet.log \
    mysteps/train_nnet.sh --hid-layers 2 --hid-dim 1200 --bn-dim 80 --learn-rate 0.002 --cv-subset-factor 0.1 \
      --semidata data/unsup_pem_${feattype} --semitransdir exp/${traindata}_tri5${langext}/decode_unsup_pem_${feattype} \
      --semialidir exp/${traindata}_tri6_nnet${langext}/decode_unsup_pem_${feattype} \
      data/$traindata exp/${traindata}_tri5_ali${langext} $dir || exit 1;
  fi
  touch $dir/.done
fi

# Compose feature_transform for the next stage 
# - remaining part of the first network is fixed
feature_transform=$dir/final.feature_transform.part1
if [ ! -f $feature_transform ] || [ $feature_transform -ot $dir/final.nnet ]; then
  nnet-concat $dir/final.feature_transform \
    "nnet-copy --remove-last-layers=4 --binary=false $dir/final.nnet - |" \
    "utils/nnet/gen_splice.py --fea-dim=80 --splice=2 --splice-step=5 |" \
    $feature_transform
fi

# Let's train the second network:
# - the topology will be 400_1200_1200_30_1200_NSTATES, again, the bottleneck is linear
# Train the MLP
dir=exp/${traindata}_tri7_${nnetfeattype}bn2${langext}
[ $semi == true ] && dir=${dir}_semi
if [ ! -f $dir/.done ]; then
  if [ $semi == false ]; then
    $cuda_cmd $dir/train_nnet.log \
    mysteps/train_nnet.sh --hid-layers 2 --hid-dim 1200 --bn-dim 30 --feature-transform $feature_transform --learn-rate 0.002 --cv-subset-factor 0.1 --feat-type "$nnetfeattype" \
      data/$traindata exp/${traindata}_tri5_ali${langext} $dir || exit 1;
  else
    $cuda_cmd $dir/train_nnet.log \
    mysteps/train_nnet.sh --hid-layers 2 --hid-dim 1200 --bn-dim 30 --feature-transform $feature_transform --learn-rate 0.002 --cv-subset-factor 0.1 \
      --semidata data/unsup_pem_${feattype} --semitransdir exp/${traindata}_tri5${langext}/decode_unsup_pem_${feattype} \
      --semialidir exp/${traindata}_tri6_nnet${langext}/decode_unsup_pem_${feattype} \
      data/$traindata exp/${traindata}_tri5_ali${langext} $dir || exit 1;
  fi
  touch $dir/.done
fi

echo "Bottleneck feature trained successfully on " `date`
exit 0
}

