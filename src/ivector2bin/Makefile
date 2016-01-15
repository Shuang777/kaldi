
all:

EXTRA_CXXFLAGS = -Wno-sign-compare
include ../kaldi.mk

BINFILES = gen-gmm-supervector ivector-model-init

OBJFILES =



TESTFILES =


ADDLIBS = ../ivector2/kaldi-ivector2.a ../hmm/kaldi-hmm.a ../gmm/kaldi-gmm.a \
    ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a \
    ../util/kaldi-util.a ../base/kaldi-base.a

include ../makefiles/default_rules.mk
