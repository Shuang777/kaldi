
mkdir exp/train_plp_pitch_tri9_multidnn
cd exp/train_plp_pitch_tri9_multidnn
ln -s ../../../multillp1/exp/train_fmllr_dnn/final.2.nnet final.nnet
ln -s ../../../multillp1/exp/train_fmllr_dnn/final.feature_transform
for i in ali_train_pdf.counts final.mdl final.mat tree; do ln -s ../train_plp_pitch_tri8_dnn/$i; done
