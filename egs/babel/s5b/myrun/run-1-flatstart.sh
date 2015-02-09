#!/bin/bash
{

. ./run-header.sh

if [ $stage -le 1 ] && [ $stage2 -ge 1 ]; then
[ -d exp ] || mkdir -p exp

if [ ! -f data/${traindata}_sub3/.done ]; then

  echo ---------------------------------------------------------------------
  echo "Subsetting monophone training data in data/${traindata}_sub[123] on" `date`
  echo ---------------------------------------------------------------------
  numutt=`cat data/$traindata/feats.scp | wc -l`;
  utils/subset_data_dir.sh data/$traindata  5000 data/${traindata}_sub1
  if [ $numutt -gt 10000 ] ; then
    utils/subset_data_dir.sh data/$traindata 10000 data/${traindata}_sub2
  else
    (cd data; ln -s $traindata ${traindata}_sub2 )
  fi
  if [ $numutt -gt 20000 ] ; then
    utils/subset_data_dir.sh data/$traindata 20000 data/${traindata}_sub3
  else
    (cd data; ln -s $traindata ${traindata}_sub3 )
  fi

  touch data/${traindata}_sub3/.done
fi
fi 	# end of stage 1

if [ $stage -le 2 ] && [ $stage2 -ge 2 ]; then
if [ ! -f exp/${traindata}_mono${langext}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) monophone training in exp/${traindata}_mono${langext} on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mono.sh \
    --boost-silence $boost_sil --nj 8 --cmd "$train_cmd" \
    data/${traindata}_sub1 data/lang${langext} exp/${traindata}_mono${langext}
  touch exp/${traindata}_mono${langext}/.done
fi

if [ ! -f exp/${traindata}_tri1${langext}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) triphone training in exp/${traindata}_tri1${langext} on" `date`
  echo ---------------------------------------------------------------------
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 12 --cmd "$train_cmd" \
    data/${traindata}_sub2 data/lang${langext} exp/${traindata}_mono${langext} exp/${traindata}_mono_ali_sub2${langext}
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri1 $numGaussTri1 \
    data/${traindata}_sub2 data/lang${langext} exp/${traindata}_mono_ali_sub2${langext} exp/${traindata}_tri1${langext}
  touch exp/${traindata}_tri1${langext}/.done
fi


echo ---------------------------------------------------------------------
echo "Starting (medium) triphone training in exp/${traindata}_tri2${langext} on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/${traindata}_tri2${langext}/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 24 --cmd "$train_cmd" \
    data/${traindata}_sub3 data/lang${langext} exp/${traindata}_tri1${langext} exp/${traindata}_tri1_ali_sub3${langext}
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri2 $numGaussTri2 \
    data/${traindata}_sub3 data/lang${langext} exp/${traindata}_tri1_ali_sub3${langext} exp/${traindata}_tri2${langext}
  touch exp/${traindata}_tri2${langext}/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (full) triphone training in exp/${traindata}_tri3${langext} on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/${traindata}_tri3${langext}/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/${traindata} data/lang${langext} exp/${traindata}_tri2${langext} exp/${traindata}_tri2_ali${langext}
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesTri3 $numGaussTri3 data/${traindata} data/lang${langext} exp/${traindata}_tri2_ali${langext} exp/${traindata}_tri3${langext}
  touch exp/${traindata}_tri3${langext}/.done
fi

fi # end of stage 2

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------
}
