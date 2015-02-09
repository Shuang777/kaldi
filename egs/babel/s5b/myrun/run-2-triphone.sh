#!/bin/bash
{

. ./run-header.sh

if [ $stage -le 0 ] && [ $stage2 -ge 0 ]; then
echo ---------------------------------------------------------------------
echo "Starting (lda_mllt) triphone training in exp/${traindata}_tri4${langext} on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/${traindata}_tri4${langext}/.done ]; then
  if [ $flatstart == true ]; then   # this is for plp_pitch feature
    steps/align_si.sh \
      --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
      data/${traindata} data/lang${langext} exp/${traindata}_tri3${langext} exp/${traindata}_tri3_ali${langext}
    steps/train_lda_mllt.sh \
      --boost-silence $boost_sil --cmd "$train_cmd" \
      $numLeavesMLLT $numGaussMLLT data/${traindata} data/lang${langext} exp/${traindata}_tri3_ali${langext} exp/${traindata}_tri4${langext}
  else
    steps/train_lda_mllt.sh \
      --boost-silence $boost_sil --cmd "$train_cmd" \
      $numLeavesMLLT $numGaussMLLT data/${traindata} data/lang${langext} exp/train_plp_pitch_tri5_ali${langext} exp/${traindata}_tri4${langext}
  fi
  touch exp/${traindata}_tri4${langext}/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (SAT) triphone training in exp/${traindata}_tri5${langext} on" `date`
echo ---------------------------------------------------------------------

if [ ! -f exp/${traindata}_tri5${langext}/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/${traindata} data/lang${langext} exp/${traindata}_tri4${langext} exp/${traindata}_tri4_ali${langext}
  steps/train_sat.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesSAT $numGaussSAT data/${traindata} data/lang${langext} exp/${traindata}_tri4_ali${langext} exp/${traindata}_tri5${langext}
  touch exp/${traindata}_tri5${langext}/.done
fi

if [ ! -f exp/${traindata}_tri5_ali${langext}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/${traindata}_tri5_ali${langext} on" `date`
  echo ---------------------------------------------------------------------
  steps/align_fmllr.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/${traindata} data/lang${langext} exp/${traindata}_tri5${langext} exp/${traindata}_tri5_ali${langext}
  touch exp/${traindata}_tri5_ali${langext}/.done
fi

fi	# end of stage 0

echo ---------------------------------------------------------------------
echo "Finished successfully on" `date`
echo ---------------------------------------------------------------------
}
