#!/bin/bash

# Copyright 2014  Vimal Manohar, Johns Hopkins University (Author: Jan Trmal)
#                 Hang Su, International Computer Science Institute
# Apache 2.0

{
set -e
set -o pipefail

# Begin configuration section
cmd=./cmd.sh
silence_segment_fraction=1.0  # What fraction of segment we should keep
boost_sil=1.0
feattype=plp
type=dev10h     # dev10h, eval, unsup, evalp1
# End configuration section

. ./path.sh
. utils/parse_options.sh
. $cmd
. ./lang.conf

if [ $# -gt 0 ]; then
  echo "Usage: $0"
  echo " E.g.: $0 --stage 0 --stage2 2"
  die
fi

[ $feattype == plp ] && feattype=plp_pitch
traindata=train_$feattype
trainalldata=trainall_$feattype
typedata=${type}_unseg_$feattype
type_nj=$(eval echo \$${type}_nj)

# ./run-prep-data.sh --type trainall
# ./run-prep-feat.sh --type trainall
# ./run-prep-feat.sh --type dev10h --segmode unseg

if [ ! -f exp/${trainalldata}_tri4/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Training segmentation model in exp/${traindata}_tri4"
  echo ---------------------------------------------------------------------
  steps/align_fmllr.sh --nj $train_nj --cmd $train_cmd --boost-silence $boost_sil \
    data/$trainalldata data/lang exp/${traindata}_tri4 exp/${trainalldata}_tri4_preali

  steps/train_lda_mllt.sh --cmd $train_cmd --realign-iters "" --boost-silence $boost_sil \
    1000 10000 data/${trainalldata} data/lang exp/${trainalldata}_tri4_preali exp/${trainalldata}_tri4
 
  steps/make_phone_graph.sh data/lang exp/${trainalldata}_tri4_preali exp/${trainalldata}_tri4

  touch exp/${trainalldata}_tri4/.done
fi

decode=exp/${trainalldata}_tri4/decode_$typedata
if [ ! -f $decode/.done ]; then
  steps/decode_nolats.sh --write-words false --write-alignments true \
    --cmd $decode_cmd --nj $type_nj --beam 7 --max-active 1000 exp/${trainalldata}_tri4/phone_graph data/$typedata $decode
  touch $decode/.done
fi

lang=data/lang
segmentation_opts="--min-inter-utt-silence-length 1.0 --silence-proportion 0.05"
silphone=`cat $lang/phones/optional_silence.txt` 
# silphone will typically be "sil" or "SIL". 

(
echo "$silphone 0"
grep -v -w $silphone $lang/phones/silence.txt \
  | awk '{print $1, 1;}' \
  | sed 's/SIL\(.*\)1/SIL\10/' \
  | sed 's/<oov>\(.*\)1/<oov>\12/'
cat $lang/phones/nonsilence.txt | awk '{print $1, 2;}' | sed 's/\(<.*>.*\)2/\11/' | sed 's/<oov>\(.*\)1/<oov>\12/'
) > $decode/phone_map.txt

$decode_cmd JOB=1:$dev10h_nj $decode/log/predict.JOB.log \
  gunzip -c $decode/ali.JOB.gz \| \
  ali-to-phones --per-frame=true exp/${trainalldata}_tri4/final.mdl ark:- ark,t:- \| \
  utils/int2sym.pl -f 2- data/lang/phones.txt \| \
  mylocal/resegment/segmentation.py --verbose 2 $segmentation_opts \
  $decode/phone_map.txt \> $decode/segments.JOB

cat $decode/segments.* | sort > $decode/segments

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------

exit 0
}
