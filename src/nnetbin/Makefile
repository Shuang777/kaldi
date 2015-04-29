
all:
EXTRA_CXXFLAGS = -Wno-sign-compare -I/usr/include/mpi
include ../kaldi.mk

LDFLAGS += $(CUDA_LDFLAGS)
LDLIBS += $(CUDA_LDLIBS) -I/n/shokuji/da/suhang/local/include -L/n/shokuji/da/suhang/local/lib -lmpi_cxx -lmpi

BINFILES = nnet-train-frmshuff \
        nnet-train-perutt \
        nnet-train-mmi-sequential \
        nnet-train-mpe-sequential \
        rbm-train-cd1-frmshuff rbm-convert-to-nnet \
        nnet-forward nnet-copy nnet-info nnet-concat \
        transf-to-nnet cmvn-to-nnet nnet-initialize \
        nnet-kl-hmm-acc nnet-kl-hmm-mat-to-component \
				multi-nnet-initialize multi-nnet-copy multi-nnet-info \
				multi-nnet-to-nnet nnet-to-multi-nnet \
				multi-nnet-add-subnnet multi-nnet-forward \
				multi-nnet-train-frmshuff multi-nnet-split \
				multi-nnet-propagateback multi-nnet-train-frmshuff-subnnets \
				multi-nnet-forward-subnnets multi-nnet-propagate \
				nnet-to-multi-merge-nnet multi-nnet-add-softmax \
				rbm-train-cd1-frmshuff-mpi \
				nnet-train-frmshuff-mpi


OBJFILES =



TESTFILES =

ADDLIBS = ../nnet/kaldi-nnet.a ../cudamatrix/kaldi-cudamatrix.a ../lat/kaldi-lat.a \
          ../hmm/kaldi-hmm.a ../tree/kaldi-tree.a ../matrix/kaldi-matrix.a \
          ../util/kaldi-util.a ../base/kaldi-base.a ../thread/kaldi-thread.a

include ../makefiles/default_rules.mk
