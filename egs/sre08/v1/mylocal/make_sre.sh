#!/bin/bash
# Copyright 2015 Hang Su
# Apache 2.0.
{

set -e
set -o pipefail

<<sre
mylocal/make_sre_2004_train.pl /u/drspeech/data/SpeakerID/SRE2004/unsegmented data
mylocal/make_sre_2004_test.pl /u/drspeech/data/SpeakerID/SRE2004/unsegmented data
mylocal/make_sre_2005_train.pl /u/drspeech/data/SpeakerID/SRE2005/unsegmented/train data
mylocal/make_sre_2006_train.pl /u/drspeech/data/NIST_SRE/LDC2011S09-2006SRETrain data
mylocal/make_sre_2008_train.pl /u/drspeech/data/NIST_SRE/LDC2011S05-2008SRETrain data
mylocal/make_sre_2008_test.sh /u/drspeech/data/NIST_SRE/LDC2011S08-2008SRETest data
sre

wget -P data/local/ http://www.openslr.org/resources/15/speaker_list.tgz
tar -C data/local/ -xvf data/local/speaker_list.tgz
sre_ref=data/local/speaker_list

local/make_sre.pl /u/drspeech/data/swordfish/users/suhang/data/LDC2006S44 sre2004 $sre_ref $data_dir/sre2004
local/make_sre.pl /u/drspeech/data/swordfish/users/suhang/data/LDC2011S04 sre2005 $sre_ref $data_dir/sre2005_test
local/make_sre.pl /u/drspeech/data/SpeakerID/SRE2005/unsegmented/train sre2005 $sre_ref $data_dir/sre2005_train
local/make_sre.pl /u/drspeech/data/NIST_SRE/LDC2011S09-2006SRETrain sre2006 $sre_ref $data_dir/sre2006_train
local/make_sre.pl /u/drspeech/data/swordfish/users/suhang/data/LDC2011S10 sre2006 $sre_ref $data_dir/sre2006_test_1
local/make_sre.pl /u/drspeech/data/swordfish/users/suhang/data/LDC2012S01 sre2006 $sre_ref $data_dir/sre2006_test_2
local/make_sre.pl /u/drspeech/data/NIST_SRE/LDC2011S05-2008SRETrain sre2008 $sre_ref $data_dir/sre2008_train
local/make_sre.pl /u/drspeech/data/NIST_SRE/LDC2011S08-2008SRETest sre2008 $sre_ref $data_dir/sre2008_test

utils/combine_data.sh $data_dir/sre \
  $data_dir/sre2004 $data_dir/sre2005_train \
  $data_dir/sre2005_test $data_dir/sre2006_train \
  $data_dir/sre2006_test_1 $data_dir/sre2006_test_2 \
  $data_dir/sre2008_train $data_dir/sre2008_test

utils/validate_data_dir.sh --no-text --no-feats $data_dir/sre
utils/fix_data_dir.sh $data_dir/sre

}
