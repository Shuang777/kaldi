#!/bin/bash

# Hub-5 Eval 2000 data preparation 
# Author:  Arnab Ghoshal (Jan 2013)

# To be run from one directory above this script.

# The input is two directory names (possibly the same) containing the 
# 2000 Hub5 english evaluation test set and transcripts, which are
# respectively: LDC2002S09  LDC2002T43
# e.g. see
# http://www.ldc.upenn.edu/Catalog/catalogEntry.jsp?catalogId=LDC2002S09
# http://www.ldc.upenn.edu/Catalog/CatalogEntry.jsp?catalogId=LDC2002T43
#
if [ $# -ne 1 ]; then
  echo "Usage: "`basename $0`" <dir>"
  echo "See comments in the script for more details"
  exit 1
fi

sdir=$1
[ ! -d $sdir/wavfile ] \
  && echo Expecting directory $sdir/wavfile to be present && exit 1;
[ ! -d $sdir/trans ] \
  && echo Expecting directory $sdir/trans to be present && exit 1;

. path.sh 

dir=data/local/eval2000
mkdir -p $dir

# stm file has lines like:
# en_4156 A en_4156_A 357.64 359.64 <O,en,F,en-F>  HE IS A POLICE OFFICER 
# TODO(arnab): We should really be lowercasing this since the Edinburgh
# recipe uses lowercase. This is not used in the actual scoring.
grep -v ';;' $sdir/trans/hub5e00.english.000405.stm \
  | awk '{
           spk=$1"_"$2;
           utt=sprintf("%s_%07d_%07d",spk,$4*100,$5*100);
           printf utt; for(n=7;n<=NF;n++) printf(" %s", tolower($n)); print ""; }' \
  | sort > $dir/text.all

# next line uses command substitution

grep -v IGNORE_TIME_SEGMENT_ $dir/text.all > $dir/text

find $sdir/wavfile -iname '*.wav' | sort > $dir/sph.flist
awk '{print $1}' $dir/text.all | paste - $dir/sph.flist \
  > $dir/sph.scp

sph2pipe=$KALDI_ROOT/tools/sph2pipe_v2.5/sph2pipe
[ ! -x $sph2pipe ] \
  && echo "Could not execute the sph2pipe program at $sph2pipe" && exit 1;

awk -v sph2pipe=$sph2pipe '{
  printf("%s %s -f wav -p -c 1 %s |\n", $1, sph2pipe, $2); 
}' < $dir/sph.scp | sort > $dir/wav.scp || exit 1;

# create an utt2spk file that assumes each conversation side is
# a separate speaker.
awk '{spk=substr($1,0,9); print $1,spk;}' $dir/sph.scp > $dir/utt2spk  
utils/utt2spk_to_spk2utt.pl $dir/utt2spk > $dir/spk2utt

awk '{channel=substr($2,length($2),1); printf("%s %s %s\n",$1,$1, channel);}' $dir/utt2spk \
  > $dir/reco2file_and_channel || exit 1;

awk '{print $1,$(NF-1)}' $dir/wav.scp | \
  perl -ane '@A = split(" ", $_);
             $utt = $A[0];
             $_=~s/\s$//; 
             $_ =~ m:^(\S+)_([0-9]*)_([0-9]*) (\S+)\/(\S+)_([0-9]*)_([0-9]*)\.wav$:;
             printf("%s %s %.3f %.3f\n", $utt, $utt, ($2-$6)/100-0.005, ($3-$6)/100-0.005); ' \
  > $dir/segments

# We'll use the stm file for sclite scoring.  There seem to be various errors
# in the stm file that upset hubscr.pl, and we fix them here.
sed -e 's:((:(:' -e 's:<B_ASIDE>::g' -e 's:<E_ASIDE>::g' \
  $sdir/trans/hub5e00.english.000405.stm |\
  awk 'NR==FNR {start[$1]=$3; end[$1]=$4; next;}
       /^;;/ {print;next;}
       {
         spk=$1"_"$2;
         utt=sprintf("%s_%07d_%07d",spk,$4*100,$5*100);
         printf ("%s %s %s %s %s %s ",utt,$2,utt,start[utt],end[utt],$6);
         for(n=7;n<=NF;n++) printf(" %s", tolower($n)); print "";
       }' $dir/segments /dev/stdin > $dir/stm
cp $sdir/trans/en20000405_hub5.glm  $dir/glm


awk '{print $1}' $dir/utt2spk | \
  perl -ane '$_=~s/\s$//; 
             $_ =~ m:^(\S+)_([0-9]*)_([0-9]*)$:;
             printf("%s %s 0.000 %.3f\n", $_, $_, ($3-$2+9)/100+0.005); ' \
  > $dir/segments

dest=data/eval2000
mkdir -p $dest
for x in wav.scp text utt2spk spk2utt stm glm reco2file_and_channel segments; do
  cp $dir/$x $dest/$x
done

echo Data preparation and formatting completed for Eval 2000
echo "(but not MFCC extraction)"

myutils/fix_data_dir.sh $dest

