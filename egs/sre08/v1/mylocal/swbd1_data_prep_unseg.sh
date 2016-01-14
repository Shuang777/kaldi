#!/bin/bash

# Switchboard-1 training data preparation customized for Edinburgh
# Author:  Arnab Ghoshal (Jan 2013)

# To be run from one directory above this script.

## The input is some directory containing the switchboard-1 release 2
## corpus (LDC97S62).  Note: we don't make many assumptions about how
## you unpacked this.  We are just doing a "find" command to locate
## the .sph files.

## The second input is optional, which should point to a directory containing
## Switchboard transcriptions/documentations (specifically, the conv.tab file).
## If specified, the script will try to use the actual speaker PINs provided 
## with the corpus instead of the conversation side ID (Kaldi default). We 
## will be using "find" to locate this file so we don't make any assumptions
## on the directory structure. (Peng Qi, Aug 2014)

transdir=

. parse_options.sh

. path.sh

#check existing directories
if [ $# != 3 ]; then
  echo "Usage: $0 /path/to/SWBD <gender-map> <data-dir>"
  echo " e.g.: $0 /u/drspeech/data/SWB1r2 gender.map data/swbd"
  exit 1; 
fi 

SWBD_DIR=$1
gendermap=$2
dir=$3

mkdir -p $dir

# Audio data directory check
if [ ! -d $SWBD_DIR ]; then
  echo "Error: run.sh requires a directory argument"
  exit 1; 
fi  

sph2pipe=$KALDI_ROOT/tools/sph2pipe_v2.5/sph2pipe
[ ! -x $sph2pipe ] \
  && echo "Could not execute the sph2pipe program at $sph2pipe" && exit 1;

# find sph audio files
find $SWBD_DIR -iname '*.sph' | sort > $dir/sph.flist

n=`cat $dir/sph.flist | wc -l`
[ $n -ne 2435 ] && \
  echo Warning: expected 2435 data data files, found $n


sed -e 's?.*/??' -e 's?.sph??' -e 's#sw0##' $dir/sph.flist | paste - $dir/sph.flist \
  > $dir/sph.scp

awk -v sph2pipe=$sph2pipe '{
  printf("%s_A %s -f wav -p -c 1 %s |\n", $1, sph2pipe, $2); 
  printf("%s_B %s -f wav -p -c 2 %s |\n", $1, sph2pipe, $2);
}' < $dir/sph.scp | sort > $dir/wav.scp || exit 1;
#side A - channel 1, side B - channel 2

awk 'NR==FNR{a[$1]=1;next;} {if (a[$1]) print}' $dir/wav.scp $gendermap > $dir/utt2spkgender

awk '{print $2,$3}' $dir/utt2spkgender | sort -u | sed -e 's#FEMALE#f#' -e 's#MALE#m#' > $dir/spk2gender

awk '{print $1, $2}' $dir/utt2spkgender > $dir/utt2spk

utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt

awk -v dir=$dir 'NR==FNR {a[$1]=$2; next} {
  if (NF <= 2) next;
  if (a[$1] == "m") file=dir "/spk2utt_male";
  else file=dir "/spk2utt_female";
  train_file=file "_train";
  test_file=file "_test";
  printf "%s",$1 > train_file;
  printf "%s",$1 > test_file;
  for (i=1;i<=(NF-1)/2;i++)
    printf " %s",$(i+1) > train_file;
  for (i=int((NF-1)/2+1); i <= NF-1; i++)
    printf " %s",$(i+1) > test_file;
  print "" > train_file;
  print "" > test_file;
}' $dir/spk2gender $dir/spk2utt

for gen in male female; do
  for type in train test; do
    thisdir=${dir}_${type}_$gen
    mkdir -p $thisdir
    cp $dir/spk2utt_${gen}_${type} $thisdir/spk2utt
    utils/spk2utt_to_utt2spk.pl $thisdir/spk2utt > $thisdir/utt2spk
    cp $dir/spk2gender $thisdir
    if [ $type == test ]; then
      mv $thisdir/utt2spk $thisdir/utt2spk.truth
      awk '{print $1,$1}' $thisdir/utt2spk.truth > $thisdir/utt2spk
      utils/utt2spk_to_spk2utt.pl $thisdir/utt2spk > $thisdir/spk2utt
      [ $gen == male ] && awk '{print $1,"m"}' $thisdir/spk2utt > $thisdir/spk2gender
      [ $gen == female ] && awk '{print $1,"f"}' $thisdir/spk2utt > $thisdir/spk2gender
    fi
    cp $dir/wav.scp $thisdir
    myutils/fix_data_dir.sh $thisdir
  done
done



