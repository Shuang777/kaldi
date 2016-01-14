#!/bin/bash
{
set -e
set -o pipefail

function die () {
  echo -e "ERROR:$1"
  exit 1
}

echo "$0 $@"

nj=2
stage=0
. parse_options.sh

. ./path.sh
. ./cmd.sh

keywordID=$1
dir=data/swbd_keywords/separate/$keywordID

mkdir -p data/swbd_keywords/separate/$keywordID

if [ $stage -le 0 ]; then
awk -v i=$keywordID '{if ($2 == i) print}' data/swbd_keywords/utt2id | awk 'NR==FNR{a[$1]; next;} {if ($1 in a) print}' /dev/stdin data/swbd_keywords/utt2spk > data/swbd_keywords/separate/$keywordID/utt2spk

numutts=$(wc -l data/swbd_keywords/separate/$keywordID/utt2spk | cut -f1 -d' ')
if [ $numutts -lt 40 ]; then
  die "Not enough utterance! $numutts found for keywordID $keywordID.";
fi
numuttmax=$(cat data/swbd_keywords/separate/$keywordID/utt2spk | awk '{a[$2]++;} END{max=0; for (key in a) {if (a[key] > max) max=a[key]} print max}')
if [ $numuttmax -lt 10 ]; then
  die "Not enough utterance for primary speaker! $numuttmax found.";
fi

cp data/swbd_keywords/{feats.scp,wav.scp,spk2utt,spk2gender,segments} data/swbd_keywords/separate/$keywordID/
myutils/fix_data_dir.sh data/swbd_keywords/separate/$keywordID

awk -v dir=$dir 'NR==FNR {a[$1]=$2; next} {
  if (NF <= 2) next;
  if (a[$1] == "m") file=dir "/spk2utt_male";
  else file=dir "/spk2utt_female";
  train_file=file "_train";
  test_file=file "_test";
  printf "%s",$1 > train_file;
  printf "%s",$1 > test_file;
  for (i=1;i<=(NF-1)/2;i++)
    printf " %s",$(i+1) > train_file;
  for (i=int((NF-1)/2+1); i <= NF-1; i++)
    printf " %s",$(i+1) > test_file;
  print "" > train_file;
  print "" > test_file;
}' $dir/spk2gender $dir/spk2utt


for gen in male female; do
  for type in train test; do
    thisdir=${dir}/${type}_$gen
    mkdir -p $thisdir
    if [ $type == train ]; then
      awk -v dir=$dir -v gen=$gen '{if (NF > 4) {spkmap[$1]=$1;} else {spkmap[$1]="background"; $1="background";} print} END {spkmapfile=dir"/spkmap_"gen; for (key in spkmap) {print key, spkmap[key] > spkmapfile;} }' $dir/spk2utt_${gen}_${type} > $thisdir/spk2utt
      utils/spk2utt_to_utt2spk.pl $thisdir/spk2utt > $thisdir/utt2spk
    else
      awk 'NR==FNR{spkmap[$1]=$2; next} {$1=spkmap[$1]; print}' $dir/spkmap_${gen} $dir/spk2utt_${gen}_${type} > $thisdir/spk2utt
      utils/spk2utt_to_utt2spk.pl $thisdir/spk2utt > $thisdir/utt2spk.truth
      awk '{print $1,$1}' $thisdir/utt2spk.truth > $thisdir/utt2spk
      utils/utt2spk_to_spk2utt.pl $thisdir/utt2spk > $thisdir/spk2utt
    fi
    [ $gen == male ] && awk '{print $1,"m"}' $thisdir/spk2utt > $thisdir/spk2gender
    [ $gen == female ] && awk '{print $1,"f"}' $thisdir/spk2utt > $thisdir/spk2gender
    cp $dir/wav.scp $thisdir
    cp $dir/segments $thisdir
    cp $dir/feats.scp $thisdir
    myutils/fix_data_dir.sh $thisdir
  done
done

fi

genders=""
numspkmaletrain=$(wc -l $dir/train_male/spk2utt | cut -f1 -d ' ')
if [ $numspkmaletrain -lt 2 ]; then
  echo "INFO: not enough speaker for male ivector training, only $numspkmaletrain found.";
else
  genders="male";
fi
numspkfemaletrain=$(wc -l $dir/train_female/spk2utt | cut -f1 -d ' ')
if [ $numspkfemaletrain -lt 2 ]; then
  echo "INFO: not enough speaker for female ivector training, only $numspkfemaletrain found.";
else
  genders=$genders" female";
fi
if [ -z "$genders" ]; then
  die "potential genders for experiments are zero, not proceeding.";
fi


datadir=data/swbd_keywords/separate/$keywordID
swbddir=swbd_keywords/$keywordID

if [ $stage -le 1 ]; then

mkdir -p ${datadir}/trial 
awk 'BEGIN{count=0} NR==FNR{utt[count]=$1; spk[count]=$2; count++; next;} {for (i=0;i<count;i++){printf("%s %s ",$1,utt[i]); if ($1==spk[i]){print "target"} else {print "nontarget"}}}' ${datadir}/test_male/utt2spk.truth ${datadir}/train_male/spk2utt > ${datadir}/trial/male.trial
awk 'BEGIN{count=0} NR==FNR{utt[count]=$1; spk[count]=$2; count++; next;} {for (i=0;i<count;i++){printf("%s %s ",$1,utt[i]); if ($1==spk[i]){print "target"} else {print "nontarget"}}}' ${datadir}/test_female/utt2spk.truth ${datadir}/train_female/spk2utt > ${datadir}/trial/female.trial

for gender in $genders; do
mysid/extract_ivectors.sh --cmd "$train_cmd -l mem_free=6G,ram_free=6G" --nj $nj --vad false \
   --framesort false exp/extractor_2048_${gender}$model ${datadir}/train_${gender} \
   exp/ivectors_${swbddir}/train_${gender}$model
mysid/extract_ivectors.sh --cmd "$train_cmd -l mem_free=6G,ram_free=6G" --nj $nj --vad false\
   --framesort false exp/extractor_2048_${gender}$model ${datadir}/test_${gender} \
   exp/ivectors_${swbddir}/test_${gender}$model
done
fi

if [ $stage -le 2 ]; then

for gender in $genders; do
trials=${datadir}/trial/${gender}.trial
expdir=exp/scoring_${swbddir}/test_$gender
mkdir -p $expdir
cat $trials | awk '{print $1, $2}' | \
 ivector-compute-dot-products - \
  scp:exp/ivectors_${swbddir}/train_${gender}$model/spk_ivector.scp \
  scp:exp/ivectors_${swbddir}/test_${gender}$model/spk_ivector.scp \
   $expdir/score

awk '{if (($2 in utt2spk) && (utt2spkscore[$2] < $3) || !($2in utt2spk)){utt2spk[$2]=$1; utt2spkscore[$2]=$3;}} END{for (key in utt2spk) {print key, utt2spk[key]}}' $expdir/score > $expdir/decision

awk 'NR==FNR{utt2spktruth[$1]=$2;next} {if (utt2spktruth[$1] == $2) true++; else false++;} END{printf "true:%4d\tfalse:%4d\tprecision:%4.2f%\n", true, false, true/(true+false) * 100;}' ${datadir}/test_$gender/utt2spk.truth $expdir/decision | tee $expdir/decision.score
done

fi

}
