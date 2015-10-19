#!/bin/bash
{

set -e
set -o pipefail
semi_layers=-1
supcopy=1
dnndir=exp/${traindata}_tri8_dnn_semi

echo "$0 $@"

. ./path.sh
. parse_options.sh
. ./cmd.sh
. ./lang.conf

feattype=plp_pitch
traindata=train_$feattype


dbndir=exp/${traindata}_tri8_dbn

$cuda_cmd $dnndir/train_nnet.log \
  mysteps/train_nnet.sh --feature-transform $dbndir/final.feature_transform --dbn $dbndir/6.dbn --hid-layers 0 \
    --learn-rate 0.008 --cv-subset-factor 0.1 --semidata data/unsup_pem_${feattype} \
    --semitransdir exp/${traindata}_tri5/decode_unsup_pem_${feattype} \
    --semialidir exp/${traindata}_tri6_nnet/decode_unsup_pem_${feattype} \
    --train-opts "--frame-weights $dnndir/frame_weights.ark" \
    --supcopy $supcopy \
    data/$traindata data/lang exp/${traindata}_tri5_ali $dnndir

#     --semi-layers $semi_layers \
}
