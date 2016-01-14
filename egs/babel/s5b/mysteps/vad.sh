#!/bin/bash

{
set -e
set -o pipefail

# Begin configuration
nj=30
boost_sil=1.0
stage=0
cmd=local/run.pl
# End of cofiguration

. ./path.sh
. parse_options.sh

if [ $# -ne 5 ]; then
  echo "Usage: $0 <model-dir> <lang-dir> <graph-dir> <data-name> <decode-dir>"
  echo " e.g.: $0 exp/tri4a_trainseg_100k_nodup data/lang exp/tri4a_trainseg_100k_nodup/phone_graph testseg exp/tri4a_trainseg_100k_nodup/decode_testseg"
  exit 1
fi

modeldir=$1
langdir=$2
graphdir=$3
name=$4
decode=$5

data=data/$name

if [ $stage -le -1 ]; then
  steps/make_mfcc.sh --cmd "$decode_cmd" --nj $nj $data exp/make_mfcc/$name mfcc
  sid/compute_vad_decision.sh --nj $nj --cmd "$decode_cmd" $data exp/make_vad/$name mfcc
  mysteps/compute_cmvn_stats.sh --vad true $data exp/make_mfcc/$name mfcc
fi

if [ $stage -le 0 ]; then
  steps/decode_nolats.sh --write-words false --write-alignments true \
    --cmd "$decode_cmd" --nj $nj --beam 7 --max-active 1000 $graphdir $data $decode
fi

segmentation_opts="--min-inter-utt-silence-length 1.0 --silence-proportion 0.10"
silphone=`cat $langdir/phones/optional_silence.txt`
# silphone will typically be "sil" or "SIL". 

(
echo "$silphone 0"
grep -v -w $silphone $langdir/phones/silence.txt \
  | awk '{print $1, 1;}' \
  | sed 's/SIL\(.*\)1/SIL\10/' \
  | sed 's/<oov>\(.*\)1/<oov>\12/'
cat $langdir/phones/nonsilence.txt | awk '{print $1, 2;}' | sed 's/\(<.*>.*\)2/\11/' | sed 's/<oov>\(.*\)1/<oov>\12/'
) > $decode/phone_map.txt

if [ $stage -le 1 ]; then
$decode_cmd JOB=1:$nj $decode/log/predict.JOB.log \
  gunzip -c $decode/ali.JOB.gz \| \
  ali-to-phones --per-frame=true $modeldir/final.mdl ark:- ark,t:- \| \
  utils/int2sym.pl -f 2- $langdir/phones.txt \| \
  mylocal/resegment/segmentation.py --verbose 2 $segmentation_opts \
  $decode/phone_map.txt \> $decode/segments.JOB
fi

cat $decode/segments.* | sort > $decode/segments

#[ -f $data/segments_nosil.truth ] && local/resegment/evaluate_segmentation.pl $data/segments_nosil.truth $decode/segments

}
