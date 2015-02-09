#!/bin/bash
{

. ./run-header.sh

if [ $stage -le 0 ] && [ $stage2 -ge 0 ]; then
################################################################################
# Ready to start SGMM training
################################################################################

echo "Waiting till exp/${traindata}_tri5_ali${langext}/.done exists...."
while [ ! -f exp/${traindata}_tri5_ali${langext}/.done ]; do sleep 30; done
echo "...done waiting for exp/${traindata}_tri5_ali${langext}/.done"

if [ ! -f exp/${traindata}_ubm5${langext}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/${traindata}_ubm5${langext} on" `date`
  echo ---------------------------------------------------------------------
  steps/train_ubm.sh \
    --cmd "$train_cmd" $numGaussUBM \
    data/${traindata} data/lang${langext} exp/${traindata}_tri5_ali${langext} exp/${traindata}_ubm5${langext}
  touch exp/${traindata}_ubm5${langext}/.done
fi

if [ ! -f exp/${traindata}_sgmm5${langext}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/${traindata}_sgmm5${langext} on" `date`
  echo ---------------------------------------------------------------------
  steps/train_sgmm2.sh \
    --cmd "$train_cmd" "${sgmm_train_extra_opts[@]}" $numLeavesSGMM $numGaussSGMM \
    data/${traindata} data/lang${langext} exp/${traindata}_tri5_ali${langext} exp/${traindata}_ubm5${langext}/final.ubm exp/${traindata}_sgmm5${langext}
  #steps/train_sgmm2_group.sh \
  #  --cmd "$train_cmd" "${sgmm_group_extra_opts[@]-}" $numLeavesSGMM $numGaussSGMM \
  #  data/train data/lang${langext} exp/tri5_ali exp/ubm5/final.ubm exp/sgmm5
  touch exp/${traindata}_sgmm5${langext}/.done
fi
fi	# end of stage 4

echo ---------------------------------------------------------------------
echo "Finished sgmm training successfully on" `date`
echo ---------------------------------------------------------------------

exit 0;

if [ $stage -le 1 ] && [ $stage2 -ge 1 ]; then
################################################################################
# Ready to start discriminative SGMM training
################################################################################

if [ ! -f exp/${traindata}_sgmm5_ali${langext}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/${traindata}_sgmm5_ali${langext} on" `date`
  echo ---------------------------------------------------------------------
  steps/align_sgmm2.sh \
    --nj $train_nj --cmd "$train_cmd" --transform-dir exp/${traindata}_tri5_ali${langext} \
    --use-graphs true --use-gselect true \
    data/${traindata} data/lang${langext} exp/${traindata}_sgmm5${langext} exp/${traindata}_sgmm5_ali${langext}
  touch exp/${traindata}_sgmm5_ali${langext}/.done
fi
fi  # end of stage 1

if [ $stage -le 2 ] && [ $stage2 -ge 2 ]; then
if [ ! -f exp/${traindata}_sgmm5_denlats/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/${traindata}_sgmm5_denlats on" `date`
  echo ---------------------------------------------------------------------
  steps/make_denlats_sgmm2.sh \
    --nj $train_nj --sub-split $train_nj "${sgmm_denlats_extra_opts[@]}" \
    --beam 10.0 --lattice-beam 6 --cmd "$decode_cmd" --transform-dir exp/${traindata}_tri5_ali \
    data/${traindata} data/lang${langext} exp/${traindata}_sgmm5_ali exp/${traindata}_sgmm5_denlats
  touch exp/${traindata}_sgmm5_denlats/.done
fi

if [ ! -f exp/${traindata}_sgmm5_mmi_b0.1/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/${traindata}_sgmm5_mmi_b0.1 on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mmi_sgmm2.sh \
    --cmd "$train_cmd" "${sgmm_mmi_extra_opts[@]}" \
    --drop-frames true --transform-dir exp/${traindata}_tri5_ali --boost 0.1 \
    data/${traindata} data/lang${langext} exp/${traindata}_sgmm5_ali exp/${traindata}_sgmm5_denlats \
    exp/${traindata}_sgmm5_mmi_b0.1
  touch exp/${traindata}_sgmm5_mmi_b0.1/.done
fi
fi 	# end of stage 2

}
