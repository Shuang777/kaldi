#!/bin/bash
{
. ./run-header.sh

# Wait till the main run.sh gets to the stage where's it's 
# finished aligning the tri5 model.
echo "Waiting till exp/${traindata}_tri5_ali/.done exists...."
while [ ! -f exp/${traindata}_tri5_ali/.done ]; do sleep 30; done
echo "...done waiting for exp/${traindata}_tri5_ali/.done"

[ -z $nnetdir ] && nnetdir=${traindata}_tri6_nnet_pnorm
if [ $stage -le 0 ] && [ $stage2 -ge 0 ]; then
if [ ! -f exp/$nnetdir/.done ]; then
  steps/nnet2/train_pnorm.sh  \
    --mix-up "$dnn_mixup" \
    --initial-learning-rate "$pnorm_initial_learning_rate" \
    --final-learning-rate "$pnorm_final_learning_rate" \
    --num-hidden-layers "$dnn_num_hidden_layers" \
    --pnorm-input-dim "$pnorm_input_dim" \
    --pnorm-output-dim "$pnorm_output_dim" \
    --cmd "$train_cmd" \
    "${dnn_cpu_parallel_opts[@]}" \
    data/${traindata} data/lang exp/${traindata}_tri5_ali exp/$nnetdir
  touch exp/$nnetdir/.done
fi
fi

}

