#!/bin/bash

if [ $# != 3 ]; then
  echo "Usage: $0 <plda-data-dir> <enroll-data-dir> <test-data-dir>"
fi
plda_data_dir=${1%/}
enroll_data_dir=${2%/}
test_data_dir=${3%/}

if [ ! -f ${test_data_dir}/trials ]; then 
  echo "${test_data_dir} needs a trial file."
  exit;
fi

mkdir -p local/.tmp

# Partition the SRE data into male and female subsets.
cat ${test_data_dir}/spk2gender | grep -w f > local/.tmp/female_spklist
utils/subset_data_dir.sh --spk-list local/.tmp/female_spklist ${test_data_dir} ${test_data_dir}_female
cat ${enroll_data_dir}/spk2gender | grep -w f > local/.tmp/female_spklist
utils/subset_data_dir.sh --spk-list local/.tmp/female_spklist ${enroll_data_dir} ${enroll_data_dir}_female
cat ${test_data_dir}/spk2gender | grep -w m > local/.tmp/male_spklist
utils/subset_data_dir.sh --spk-list local/.tmp/male_spklist ${test_data_dir} ${test_data_dir}_male
cat ${enroll_data_dir}/spk2gender | grep -w m > local/.tmp/male_spklist
utils/subset_data_dir.sh --spk-list local/.tmp/male_spklist ${enroll_data_dir} ${enroll_data_dir}_male
cat ${plda_data_dir}/spk2gender | grep -w f > local/.tmp/female_spklist
utils/subset_data_dir.sh --spk-list local/.tmp/female_spklist ${plda_data_dir} ${plda_data_dir}_female
cat ${plda_data_dir}/spk2gender | grep -w m > local/.tmp/male_spklist
utils/subset_data_dir.sh --spk-list local/.tmp/male_spklist ${plda_data_dir} ${plda_data_dir}_male

# Prepare female and male trials.
trials_female=${test_data_dir}_female/trials
cat ${test_data_dir}/trials | awk '{print $2, $0}' | \
  utils/filter_scp.pl ${test_data_dir}_female/utt2spk | cut -d ' ' -f 2- \
  > $trials_female
trials_male=${test_data_dir}_male/trials
cat ${test_data_dir}/trials | awk '{print $2, $0}' | \
  utils/filter_scp.pl ${test_data_dir}_male/utt2spk | cut -d ' ' -f 2- \
  > $trials_male


