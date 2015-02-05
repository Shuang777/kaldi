#!/bin/bash

# Copyright 2012-2014  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0

# This example script trains a DNN on top of fMLLR features. 
# The training is done in 3 stages,
#
# 1) RBM pre-training:
#    in this unsupervised stage we train stack of RBMs, 
#    a good starting point for frame cross-entropy trainig.
# 2) frame cross-entropy training:
#    the objective is to classify frames to correct pdfs.
# 3) sequence-training optimizing sMBR: 
#    the objective is to emphasize state-sequences with better 
#    frame accuracy w.r.t. reference alignment.
{
set -e
. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. ./path.sh ## Source the tools/utils (import the queue.pl)

# Config:
gmmdir=exp/tri4b
traindata=data/train
stage=0 # resume training with --stage=N
# End of config.
. utils/parse_options.sh || exit 1;
#

if [ $stage -le 0 ]; then
  # Pre-train DBN, i.e. a stack of RBMs
  dir=exp/dnn5b_pretrain-dbn
  $cuda_cmd $dir/log/pretrain_dbn.log \
    mysteps/pretrain_dbn.sh --rbm-iter 1 $traindata ${gmmdir}_ali $dir
fi

dir=exp/dnn5b_pretrain-dbn_dnn
if [ $stage -le 1 ]; then
  # Train the DNN optimizing per-frame cross-entropy.
  ali=${gmmdir}_ali
  feature_transform=exp/dnn5b_pretrain-dbn/final.feature_transform
  dbn=exp/dnn5b_pretrain-dbn/6.dbn
  # Train
  $cuda_cmd $dir/log/train_nnet.log \
    mysteps/train_nnet.sh --feature-transform $feature_transform --dbn $dbn --hid-layers 0 --learn-rate 0.008 \
    $traindata data/lang $ali $dir
fi

if [ $stage -le 2 ]; then
  # Decode (reuse HCLG graph)
  mysteps/decode_nnet.sh --nj 8 --cmd "$decode_cmd" --config conf/decode_dnn.config --acwt 0.08333 \
    --transform-dir exp/tri4b/decode_test \
    $gmmdir/graph_pr data/test $dir/decode_test_pr
  # Rescore using unpruned trigram sw1_fsh
  steps/lmrescore.sh --mode 3 --cmd "$mkgraph_cmd" data/lang_test_pr data/lang_test data/test \
    $dir/decode_test_pr $dir/decode_test.3
fi

exit

# Sequence training using sMBR criterion, we do Stochastic-GD 
# with per-utterance updates. We use usually good acwt 0.1
# Lattices are re-generated after 1st epoch, to get faster convergence.
dir=exp/dnn5b_pretrain-dbn_dnn_smbr
srcdir=exp/dnn5b_pretrain-dbn_dnn
acwt=0.0909

if [ $stage -le 3 ]; then
  # First we generate lattices and alignments:
  steps/nnet/align.sh --nj 250 --cmd "$train_cmd" \
    $data_fmllr/train_nodup data/lang $srcdir ${srcdir}_ali || exit 1;
  steps/nnet/make_denlats.sh --nj 10 --sub-split 100 --cmd "$decode_cmd" --config conf/decode_dnn.config \
    --acwt $acwt $data_fmllr/train_nodup data/lang $srcdir ${srcdir}_denlats || exit 1;
fi

if [ $stage -le 4 ]; then
  # Re-train the DNN by 1 iteration of sMBR 
  steps/nnet/train_mpe.sh --cmd "$cuda_cmd" --num-iters 1 --acwt $acwt --do-smbr true \
    $data_fmllr/train_nodup data/lang $srcdir ${srcdir}_ali ${srcdir}_denlats $dir || exit 1
  # Decode (reuse HCLG graph)
  for ITER in 1; do
    steps/nnet/decode.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config \
      --nnet $dir/${ITER}.nnet --acwt $acwt \
      $gmmdir/graph_sw1_fsh_tgpr $data_fmllr/eval2000 $dir/decode_eval2000_sw1_fsh_tgpr || exit 1;
    # Rescore using unpruned trigram sw1_fsh
    steps/lmrescore.sh --mode 3 --cmd "$mkgraph_cmd" data/lang_sw1_fsh_tgpr data/lang_sw1_fsh_tg data/eval2000 \
      $dir/decode_eval2000_sw1_fsh_tgpr $dir/decode_eval2000_sw1_fsh_tg.3 || exit 1 
  done 
fi

# Re-generate lattices, run 4 more sMBR iterations
dir=exp/dnn5b_pretrain-dbn_dnn_smbr_i1lats
srcdir=exp/dnn5b_pretrain-dbn_dnn_smbr
acwt=0.0909

if [ $stage -le 5 ]; then
  # First we generate lattices and alignments:
  steps/nnet/align.sh --nj 250 --cmd "$train_cmd" \
    $data_fmllr/train_nodup data/lang $srcdir ${srcdir}_ali || exit 1;
  steps/nnet/make_denlats.sh --nj 10 --sub-split 100 --cmd "$decode_cmd" --config conf/decode_dnn.config \
    --acwt $acwt $data_fmllr/train_nodup data/lang $srcdir ${srcdir}_denlats || exit 1;
fi

if [ $stage -le 6 ]; then
  # Re-train the DNN by 1 iteration of sMBR 
  steps/nnet/train_mpe.sh --cmd "$cuda_cmd" --num-iters 2 --acwt $acwt --do-smbr true \
    $data_fmllr/train_nodup data/lang $srcdir ${srcdir}_ali ${srcdir}_denlats $dir || exit 1
  # Decode (reuse HCLG graph)
  for ITER in 1 2; do
    steps/nnet/decode.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config \
      --nnet $dir/${ITER}.nnet --acwt $acwt \
      $gmmdir/graph_sw1_fsh_tgpr $data_fmllr/eval2000 $dir/decode_eval2000_sw1_fsh_tgpr || exit 1;
    # Rescore using unpruned trigram sw1_fsh
    steps/lmrescore.sh --mode 3 --cmd "$mkgraph_cmd" data/lang_sw1_fsh_tgpr data/lang_sw1_fsh_tg data/eval2000 \
      $dir/decode_eval2000_sw1_fsh_tgpr $dir/decode_eval2000_sw1_fsh_tg.3 || exit 1 
  done 
fi

# Getting results [see RESULTS file]
# for x in exp/*/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done
}
