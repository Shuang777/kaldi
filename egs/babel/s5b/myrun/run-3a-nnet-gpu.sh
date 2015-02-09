#!/bin/bash
{

set -e
set -o pipefail
set -u

echo "$0 $@"

# Begin configuration
stage=0
stage2=100      # we don't have more than 100 stages, isn't it?
feattype=mfcc
nnetdir=
decodedir=
cmd=cmd.sh
# End of configuration

. path.sh
. parse_options.sh
. $cmd
. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

if [ $# -ne 0 ]; then
  echo "usage: ./run-2a-nnet.sh \$stage \$stage2"
  echo " e.g.: ./run-2a-nnet.sh 0 5"
  echo "       run script from stage 0 to stage 5 (included)"
  echo "       you may also call without those two arguments, then those argument will be default value (start from 0 to 100)"
  exit 1
fi

[ $feattype == plp ] && feattype=plp_pitch
traindata=train_$feattype

devnj=$dev10h_nj

# Wait till the main run.sh gets to the stage where's it's 
# finished aligning the tri5 model.
echo "Waiting till exp/${traindata}_tri5_ali/.done exists...."
while [ ! -f exp/${traindata}_tri5_ali/.done ]; do sleep 30; done
echo "...done waiting for exp/${traindata}_tri5_ali/.done"

[ -z $nnetdir ] && nnetdir=${traindata}_tri6_nnet
if [ $stage -le 0 ] && [ $stage2 -ge 0 ]; then
if [ ! -f exp/$nnetdir/.done ]; then
  steps/nnet2/train_tanh.sh  \
    --mix-up "$dnn_mixup" \
    --initial-learning-rate "$dnn_initial_learning_rate" \
    --final-learning-rate "$dnn_final_learning_rate" \
    --num-hidden-layers "$dnn_num_hidden_layers" \
    --hidden-layer-dim "$dnn_hidden_layer_dim" \
    --cmd "$train_cmd" \
    "${dnn_gpu_parallel_opts[@]}" \
    data/${traindata} data/lang exp/${traindata}_tri5_ali exp/$nnetdir
  touch exp/$nnetdir/.done
fi
fi

}

