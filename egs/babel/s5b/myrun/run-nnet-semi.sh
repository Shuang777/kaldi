#!/bin/bash
{

set -e
set -o pipefail

supcopy=1
semi_cv=false
feattype=plp_pitch
traindata=train_$feattype
dnndir=exp/${traindata}_tri8_dnn_semi_dnnaliall
adpdir=${dnndir}_adp
stage=0
echo "$0 $@"

. ./path.sh
. parse_options.sh
. ./cmd.sh
. ./lang.conf


dbndir=exp/${traindata}_tri8_dbn

if [ $stage -le 0 ]; then
$cuda_cmd $dnndir/train_nnet.log \
  mysteps/train_nnet.sh --feature-transform $dbndir/final.feature_transform --dbn $dbndir/6.dbn --hid-layers 0 \
    --learn-rate 0.008 --cv-subset-factor 0.1 --semidata data/unsup_pem_${feattype} \
    --semitransdir exp/${traindata}_tri5/decode_unsup_pem_${feattype} \
    --semialidir exp/${traindata}_tri8_dnn/decode_unsup_pem_${feattype} \
    --supcopy $supcopy --semi-cv $semi_cv \
    data/$traindata data/lang exp/${traindata}_tri8_dnn_ali $dnndir
fi

if [ $stage -le 1 ]; then
$cuda_cmd $adpdir/train_nnet.log \
  mysteps/train_nnet.sh --feature-transform $dbndir/final.feature_transform --mlp-init $dnndir/final.nnet \
    --learn-rate 0.0008 --cv-subset-factor 0.1 --max-iters 3\
    data/${traindata} data/lang exp/${traindata}_tri5_ali $adpdir
fi


}
