#!/bin/bash
{

set -e
set -o pipefail

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

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.

. ./path.sh ## Source the tools/utils (import the queue.pl)

# Config:
gmmdir=exp/tri4b
data_fmllr=data-fmllr-tri4b
lm=tg
traindata=data/trainori
stage=0 # resume training with --stage=N
# End of config.
. utils/parse_options.sh
#
if [ $stage -le 0 ]; then
  utils/subset_data_dir_tr_cv.sh ${traindata}_nodup ${traindata}_nodup_tr90 ${traindata}_nodup_cv10
fi

if [ $stage -le 1 ]; then
  # Pre-train DBN, i.e. a stack of RBMs
  dir=exp/dnn5b_pretrain-dbn
  $cuda_cmd $dir/log/pretrain_dbn.log \
    mysteps/pretrain_dbn.sh --rbm-iter 1 ${traindata}_nodup exp/tri4b_ali_nodup $dir
fi

if [ $stage -le 2 ]; then
  # Train the DNN optimizing per-frame cross-entropy.
  dir=exp/dnn5b_pretrain-dbn_dnn_re2
  ali=${gmmdir}_ali_nodup
  feature_transform=exp/dnn5b_pretrain-dbn/final.feature_transform
  dbn=exp/dnn5b_pretrain-dbn/6.dbn
  # Train
  $cuda_cmd $dir/log/train_nnet.log \
    mysteps/train_nnet.sh --feature-transform $feature_transform --dbn $dbn --hid-layers 0 --learn-rate 0.008 \
    --resume-anneal false \
    ${traindata}_nodup data/lang $ali $dir || exit 1;
  # Decode (reuse HCLG graph)
  mysteps/decode_nnet.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config --acwt 0.08333 \
    --transform-dir exp/tri4b/decode_eval2000_sw1_${lm} \
    $gmmdir/graph_sw1_${lm} data/eval2000 $dir/decode_eval2000_sw1_${lm} || exit 1;
  # Rescore using unpruned trigram sw1_fsh
#  steps/lmrescore.sh --mode 3 --cmd "$mkgraph_cmd" data/lang_sw1_fsh_tg data/lang_sw1_fsh_tg data/eval2000 \
#    $dir/decode_eval2000_sw1_fsh_tg $dir/decode_eval2000_sw1_fsh_tg.3 || exit 1 
fi

# Sequence training using sMBR criterion, we do Stochastic-GD 
# with per-utterance updates. We use usually good acwt 0.1
# Lattices are re-generated after 1st epoch, to get faster convergence.
dir=exp/dnn5b_pretrain-dbn_dnn_smbr
srcdir=exp/dnn5b_pretrain-dbn_dnn
acwt=0.0909

if [ $stage -le 3 ]; then
  # First we generate lattices and alignments:
  mysteps/align_nnet.sh --nj 100 --cmd "$train_cmd" \
    --transform-dir exp/tri4b_ali_nodup \
    ${traindata}_nodup data/lang $srcdir ${srcdir}_ali || exit 1;
#  mysteps/make_denlats_nnet.sh --nj 10 --sub-split 100 --cmd "$decode_cmd" --config conf/decode_dnn.config \
#    --acwt $acwt ${traindata}_nodup data/lang $srcdir ${srcdir}_denlats || exit 1;
fi
exit

if [ $stage -le 4 ]; then
  # Re-train the DNN by 1 iteration of sMBR 
  mysteps/train_nnet_mpe.sh --cmd "$cuda_cmd" --num-iters 1 --acwt $acwt --do-smbr true \
    ${traindata}_nodup data/lang $srcdir ${srcdir}_ali ${srcdir}_denlats $dir || exit 1
  # Decode (reuse HCLG graph)
  for ITER in 1; do
    mysteps/decode_nnet.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config \
      --nnet $dir/${ITER}.nnet --acwt $acwt \
      $gmmdir/graph_sw1_${lm} data/eval2000 $dir/decode_eval2000_sw1_${lm} || exit 1;
    # Rescore using unpruned trigram sw1_fsh
#    steps/lmrescore.sh --mode 3 --cmd "$mkgraph_cmd" data/lang_sw1_${lm} data/lang_sw1_fsh_tg data/eval2000 \
#      $dir/decode_eval2000_sw1_${lm} $dir/decode_eval2000_sw1_fsh_tg.3 || exit 1 
  done 
fi

# Re-generate lattices, run 4 more sMBR iterations
dir=exp/dnn5b_pretrain-dbn_dnn_smbr_i1lats
srcdir=exp/dnn5b_pretrain-dbn_dnn_smbr
acwt=0.0909

if [ $stage -le 5 ]; then
  # First we generate lattices and alignments:
  mysteps/align_nnet.sh --nj 250 --cmd "$train_cmd" \
    ${traindata}_nodup data/lang $srcdir ${srcdir}_ali || exit 1;
  mysteps/make_denlats_nnet.sh --nj 10 --sub-split 100 --cmd "$decode_cmd" --config conf/decode_dnn.config \
    --acwt $acwt ${traindata}_nodup data/lang $srcdir ${srcdir}_denlats || exit 1;
fi

if [ $stage -le 6 ]; then
  # Re-train the DNN by 1 iteration of sMBR 
  mysteps/train_nnet_mpe.sh --cmd "$cuda_cmd" --num-iters 2 --acwt $acwt --do-smbr true \
    ${traindata}_nodup data/lang $srcdir ${srcdir}_ali ${srcdir}_denlats $dir || exit 1
  # Decode (reuse HCLG graph)
  for ITER in 1 2; do
    mysteps/decode_nnet.sh --nj 20 --cmd "$decode_cmd" --config conf/decode_dnn.config \
      --nnet $dir/${ITER}.nnet --acwt $acwt \
      $gmmdir/graph_sw1_${lm} data/eval2000 $dir/decode_eval2000_sw1_${lm} || exit 1;
    # Rescore using unpruned trigram sw1_fsh
#    steps/lmrescore.sh --mode 3 --cmd "$mkgraph_cmd" data/lang_sw1_${lm} data/lang_sw1_fsh_tg data/eval2000 \
#      $dir/decode_eval2000_sw1_${lm} $dir/decode_eval2000_sw1_fsh_tg.3 || exit 1 
  done 
fi

# Getting results [see RESULTS file]
# for x in exp/*/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done

}
