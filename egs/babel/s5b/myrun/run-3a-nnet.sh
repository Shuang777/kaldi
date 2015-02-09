#!/bin/bash
{

. ./run-header.sh

echo "Waiting till exp/${traindata}_tri5_ali${langext}/.done exists...."
while [ ! -f exp/${traindata}_tri5_ali${langext}/.done ]; do sleep 30; done
echo "...done waiting for exp/${traindata}_tri5_ali${langext}/.done"

[ -z $nnetdir ] && nnetdir=${traindata}_tri6_nnet${langext}
if [ $stage -le 0 ] && [ $stage2 -ge 0 ]; then
if [ ! -f exp/$nnetdir/.done ]; then
  steps/nnet2/train_tanh.sh  \
    --mix-up "$dnn_mixup" \
    --initial-learning-rate "$dnn_initial_learning_rate" \
    --final-learning-rate "$dnn_final_learning_rate" \
    --num-epochs "$dnn_num_epochs" \
    --num-epochs-extra "$dnn_num_epochs_extra" \
    --num-iters-final "$dnn_num_iters_final" \
    --num-hidden-layers "$dnn_num_hidden_layers" \
    --hidden-layer-dim "$dnn_hidden_layer_dim" \
    --num-jobs-nnet "$dnn_num_jobs" \
    --cmd "$train_cmd" \
    "${dnn_train_extra_opts[@]}" \
    data/${traindata} data/lang${langext} exp/${traindata}_tri5_ali${langext} exp/$nnetdir
  touch exp/$nnetdir/.done
fi
fi

echo ---------------------------------------------------------------------
echo "Finished nnet training successfully on" `date`
echo ---------------------------------------------------------------------

exit 0

}
