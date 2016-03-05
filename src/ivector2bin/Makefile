
all:

EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = gen-gmm-supervector ivector2-model-init ivector2-extract \
					 ivector2-model-acc-stats ivector2-model-sum-stats ivector2-model-est \
					 ivector2-model-info ivector2-model-copy

OBJFILES =



TESTFILES =


ADDLIBS = ../ivector2/kaldi-ivector2.a ../hmm/kaldi-hmm.a ../gmm/kaldi-gmm.a \
    ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a \
    ../util/kaldi-util.a ../base/kaldi-base.a

include ../makefiles/default_rules.mk
