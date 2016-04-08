
all:

EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = ivector3-model-init ivector3-extract ivector3-model-stats-copy \
					 ivector3-model-acc-stats ivector3-model-sum-stats ivector3-model-est \
					 ivector3-model-info ivector3-model-copy ivector3-model-init-from-feat

OBJFILES =



TESTFILES =


ADDLIBS = ../ivector3/kaldi-ivector3.a ../hmm/kaldi-hmm.a ../gmm/kaldi-gmm.a \
    ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a \
    ../util/kaldi-util.a ../base/kaldi-base.a

include ../makefiles/default_rules.mk
