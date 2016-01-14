#!/bin/bash
# Copyright 2015   David Snyder
# Apache 2.0.
#
if [ $# != 6 ]; then
  echo "Usage: $0 <plda-data-dir> <enroll-data-dir> <test-data-dir> <plda-ivec-dir> <enroll-ivec-dir> <test-ivec-dir>"
fi
plda_data_dir=${1%/}
enroll_data_dir=${2%/}
test_data_dir=${3%/}
plda_ivec_dir=${4%/}
enroll_ivec_dir=${5%/}
test_ivec_dir=${6%/}

if [ ! -f ${test_data_dir}/trials ]; then 
  echo "${test_data_dir} needs a trial file."
  exit;
fi

mkdir -p ${test_ivec_dir}_male
mkdir -p ${test_ivec_dir}_female
mkdir -p ${enroll_ivec_dir}_male
mkdir -p ${enroll_ivec_dir}_female
mkdir -p ${plda_ivec_dir}_male
mkdir -p ${plda_ivec_dir}_female

# Partition the i-vectors into male and female subsets.
utils/filter_scp.pl ${enroll_data_dir}_male/utt2spk \
  ${enroll_ivec_dir}/ivector.scp > ${enroll_ivec_dir}_male/ivector.scp
utils/filter_scp.pl ${test_data_dir}_male/utt2spk \
  ${test_ivec_dir}/ivector.scp > ${test_ivec_dir}_male/ivector.scp
utils/filter_scp.pl ${enroll_data_dir}_female/utt2spk \
  ${enroll_ivec_dir}/ivector.scp > ${enroll_ivec_dir}_female/ivector.scp
utils/filter_scp.pl ${test_data_dir}_female/utt2spk \
  ${test_ivec_dir}/ivector.scp > ${test_ivec_dir}_female/ivector.scp
utils/filter_scp.pl ${plda_data_dir}_female/utt2spk \
  ${plda_ivec_dir}/ivector.scp > ${plda_ivec_dir}_female/ivector.scp
utils/filter_scp.pl ${plda_data_dir}_male/utt2spk \
  ${plda_ivec_dir}/ivector.scp > ${plda_ivec_dir}_male/ivector.scp
utils/filter_scp.pl ${enroll_data_dir}_male/spk2utt \
  ${enroll_ivec_dir}/spk_ivector.scp > ${enroll_ivec_dir}_male/spk_ivector.scp
utils/filter_scp.pl ${enroll_data_dir}_female/spk2utt \
  ${enroll_ivec_dir}/spk_ivector.scp > ${enroll_ivec_dir}_female/spk_ivector.scp
utils/filter_scp.pl ${enroll_data_dir}_male/spk2utt \
  ${enroll_ivec_dir}/num_utts.ark > ${enroll_ivec_dir}_male/num_utts.ark
utils/filter_scp.pl ${enroll_data_dir}_female/spk2utt \
  ${enroll_ivec_dir}/num_utts.ark > ${enroll_ivec_dir}_female/num_utts.ark
utils/filter_scp.pl ${plda_data_dir}_male/spk2utt \
  ${plda_ivec_dir}/spk_ivector.scp > ${plda_ivec_dir}_male/spk_ivector.scp
utils/filter_scp.pl ${plda_data_dir}_female/spk2utt \
  ${plda_ivec_dir}/spk_ivector.scp > ${plda_ivec_dir}_female/spk_ivector.scp
utils/filter_scp.pl ${plda_data_dir}_male/spk2utt \
  ${plda_ivec_dir}/num_utts.ark > ${plda_ivec_dir}_male/num_utts.ark
utils/filter_scp.pl ${plda_data_dir}_female/spk2utt \
  ${plda_ivec_dir}/num_utts.ark > ${plda_ivec_dir}_female/num_utts.ark

# Compute gender independent and dependent i-vector means.
ivector-mean scp:${plda_ivec_dir}/ivector.scp ${plda_ivec_dir}/mean.vec
ivector-mean scp:${plda_ivec_dir}_male/ivector.scp ${plda_ivec_dir}_male/mean.vec
ivector-mean scp:${plda_ivec_dir}_female/ivector.scp ${plda_ivec_dir}_female/mean.vec

rm -rf local/.tmp
