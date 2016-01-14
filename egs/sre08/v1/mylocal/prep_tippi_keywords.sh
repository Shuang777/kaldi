#!/bin/bash

if [ $# -ne 2 ]; then
  echo "Usage: $0 <abs-data-path> <data-dir>"
  echo " e.g.: $0 \`pwd\`/processed data/tippi_keywords"
  exit 1
fi

datadir=$1
dir=$2

for i in `ls $datadir`; do
  thisdatadir=$datadir/$i
  thisdir=$dir/$i
  [ -d $thisdir ] || mkdir -p $thisdir
  awk '{if ($0 != "") printf "%03d %s\n", NR, $1}' $thisdatadir/gender | sort > $thisdir/spk2gender
  find $thisdatadir -name "*_[0-9]*.wav" | perl -e 'while ($line = <>) { $line =~ s/\s+$//; $line =~ m/.*\/([0-9]*.*[0-9]*).wav/; $utt=$1; printf("%s %s\n", $utt, $line);}' | sort > $thisdir/wav.scp
  find $thisdatadir -name "*_[0-9]*.wav" | perl -e 'while ($line = <>) { $line =~ s/\s+$//; $line =~ m/.*\/([0-9]*.*[0-9]*).wav/; $utt=$1; $utt =~ m/([0-9]*).*/; $spk=$1; printf("%s %s\n", $utt, $spk);}' | sort -u > $thisdir/utt2spk
  utils/utt2spk_to_spk2utt.pl $thisdir/utt2spk > $thisdir/spk2utt
done
