#!/bin/bash

# Copyright 2013   (Authors: Bagher BabaAli, Daniel Povey, Arnab Ghoshal)
#           2014   Brno University of Technology (Author: Karel Vesely)
#           2015   International Computer Science Institute (Author: Hang Su)
# Apache 2.0.
{
set -e
. ./path.sh

if [ $# -ne 1 ]; then
   echo "Argument should be the people_daily directory, see ../run.sh for example."
   exit 1;
fi

data=$1
localdir=`pwd`/data/local/data
lmdir=`pwd`/data/local/nist_lm
mkdir -p $localdir $lmdir

# First check if the train & test directories exist (these can either be upper-
# or lower-cased
if [[ ! -d $data/TRAIN || ! -d $data/TEST ]] && [[ ! -d $data/train || ! -d $data/test ]]; then
  echo "$0: Spot check of command line argument failed"
  echo "Command line argument must be absolute pathname to people_daily directory"
  echo "with name like /export/corpora5/863"
  exit 1;
fi

# Now check what case the directory structure is
uppercased=false
train_dir=train
test_dir=test
if [ -d $data/TRAIN ]; then
  uppercased=true
  train_dir=TRAIN
  test_dir=TEST
fi

tmpdir=$localdir/tmp
[ ! -d $tmpdir ] && mkdir -p $tmpdir
#trap 'rm -rf "$tmpdir"' EXIT

# Get the list of speakers. The list of speakers in the 24-speaker core test 
# set and the 50-speaker development set must be supplied to the script. All
# speakers in the 'train' directory are used for training.
ls $data/$test_dir > $tmpdir/test_spk
ls $data/$train_dir > $tmpdir/train_spk

for x in train test; do
  # First, find the list of audio files (use only si & sx utterances).
  # Note: train & test sets are under different directories, but doing find on 
  # both and grepping for the speakers will work correctly.
  dir=data/$x
  [ -d $dir ] || mkdir -p $dir
  find $data -name '*.WAV' \
    | grep -f $tmpdir/${x}_spk > $localdir/${x}_sph.flist

  sed -e 's:.*/\(.*\)/\(.*\).WAV$:\1_\2:i' $localdir/${x}_sph.flist \
    > $tmpdir/${x}_sph.uttids
  paste $tmpdir/${x}_sph.uttids $localdir/${x}_sph.flist \
    | sort -k1,1 > $dir/wav.scp

  cat $dir/wav.scp | awk '{print $1}' > $localdir/${x}.uttids

  # Now, Convert the transcripts into our format (no normalization yet)
  # Get the transcripts: each line of the output contains an utterance 
  # ID followed by the transcript.
  find $data -name '*.phn' \
    | grep -f $tmpdir/${x}_spk | grep -v 'F76D1.phn' | grep -v 'F76D3.phn' > $tmpdir/${x}_phn.flist   # two of them are not correctly transcribed
  sed -e 's:.*/\(.*\)/\(.*\).PHN$:\1_\2:i' $tmpdir/${x}_phn.flist \
    > $tmpdir/${x}_phn.uttids
  while read line; do
    [ -f $line ] || error_exit "Cannot find transcription file '$line'";
    cut -f3 -d' ' "$line" | grep -v "<s>" | grep -v "</s>" | tr '\n' ' ' | sed -e 's: *$:\n:'
  done < $tmpdir/${x}_phn.flist |\
    iconv --from-code=gb2312 --to-code=UTF-8 > $tmpdir/${x}_phn.trans
  paste $tmpdir/${x}_phn.uttids $tmpdir/${x}_phn.trans \
    | sort -k1,1 > $dir/text

  # Make the utt2spk and spk2utt files.
  cut -f1 -d'_'  $localdir/$x.uttids | paste -d' ' $localdir/$x.uttids - > $dir/utt2spk 
  cat $dir/utt2spk | utils/utt2spk_to_spk2utt.pl > $dir/spk2utt

  # Prepare gender mapping
  cat $dir/spk2utt | awk '{print $1}' | perl -ane 'chop; m:^.:; $g = lc($&); print "$_ $g\n";' > $dir/spk2gender

  # Prepare STM file for sclite:
  wav-to-duration scp:$dir/wav.scp ark,t:$localdir/${x}_dur.ark
  if [ $x == test ]; then
    awk '{printf "%s %s 0.000 %.2f5\n",$1,$1,$2}' $localdir/${x}_dur.ark > $dir/segments
    awk '{printf "%s %s 1\n", $1, $1}' $localdir/${x}_dur.ark > $dir/reco2file_and_channel
  fi
  awk -v dur=$localdir/${x}_dur.ark \
  'BEGIN{ 
     while(getline < dur) { durH[$1]=$2; } 
     print ";; LABEL \"O\" \"Overall\" \"Overall\"";
     print ";; LABEL \"F\" \"Female\" \"Female speakers\"";
     print ";; LABEL \"M\" \"Male\" \"Male speakers\""; 
   } 
   { wav=$1; spk=gensub(/_.*/,"",1,wav); $1=""; ref=$0;
     gender=(substr(spk,0,1) == "f" ? "F" : "M");
     printf("%s 1 %s 0.0 %f <O,%s> %s\n", wav, spk, durH[wav], gender, ref);
   }
  ' $dir/text > $dir/stm

  # Create dummy GLM file for sclite:
  echo ';; empty.glm
  [FAKE]     =>  %HESITATION     / [ ] __ [ ] ;; hesitation token
  ' > $dir/glm
done

echo "Data preparation succeeded"
}
