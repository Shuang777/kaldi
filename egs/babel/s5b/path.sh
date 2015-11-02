export LD_LIBRARY_PATH=/u/suhang/libtmp:$LD_LIBRARY_PATH
export PYTHONPATH=${SWORDFISH_ROOT}/share/lib/python:${PYTHONPATH}
#export PATH=${SWORDFISH_ROOT}/share/bin:${SWORDFISH_ROOT}/${SWORDFISH_ARCH}/bin:${F4DE_BASE}/bin:${PATH}
export PATH=$PWD/utils/:$KALDI_ROOT/tools/sph2pipe_v2.5/:$KALDI_ROOT/src/bin:$KALDI_ROOT/tools/openfst/bin:$KALDI_ROOT/src/fstbin/:$KALDI_ROOT/src/gmmbin/:$KALDI_ROOT/src/featbin/:$KALDI_ROOT/src/lm/:$KALDI_ROOT/src/sgmmbin/:$KALDI_ROOT/src/sgmm2bin/:$KALDI_ROOT/src/fgmmbin/:$KALDI_ROOT/src/latbin/:$KALDI_ROOT/src/nnetbin:$KALDI_ROOT/src/nnet2bin/:$KALDI_ROOT/src/kwsbin:$KALDI_ROOT/tools/srilm/bin:$KALDI_ROOT/tools/srilm/bin/i686-m64:$KALDI_ROOT/tools/srilm/bin/i686:$KALDI_ROOT/tools/irstlm/bin:/u/drspeech/data/swordfish/users/suhang/projects/Phonetisaurus/phonetisaurus-0.7.8:/u/drspeech/projects/swordfish/x86_64-linux/bin:$PWD:$PATH
export IRSTLM=$KALDI_ROOT/tools/irstlm
export LC_ALL=C

