This file describe steps to build kaldi in ICSI.

cd tools
make -j 10		# this speed up building
# you may want to copy /u/drspeech/projects/swordfish/ThirdParty/kaldi/kaldi-trunk-r3409/tools/openfst-1.3.2.tar.gz to tools

cd ../src
./configure --static --cudatk-dir=/usr/local64/lang/cuda-5.0 --mkl-root=/usr/local/lib/mkl-10.3.2/mkl --fst-root=/u/drspeech/data/swordfish/users/suhang/projects/swordfish/kaldi/kaldi-effort/vendor/kaldi-trunk/tools/openfst --omp-libdir=/usr/local/lib/mkl-10.3.2/compiler/lib/intel64
make depend
make -j 10
