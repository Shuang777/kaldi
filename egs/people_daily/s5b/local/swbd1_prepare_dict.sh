#!/bin/bash

# Formatting the Mississippi State dictionary for use in Edinburgh. Differs 
# from the one in Kaldi s5 recipe in that it uses lower-case --Arnab (Jan 2013)

# To be run from one directory above this script.
{
set -e
. path.sh

#check existing directories
[ $# != 1 ] && echo "Usage: $0 <dict>" && exit 1;

srcdir=data/local/data  # This is where we downloaded some stuff..
dir=data/local/dict
mkdir -p $dir
srcdict=$1

# assume swbd_p1_data_prep.sh was done already.
[ ! -f "$srcdict" ] && echo "No such file $srcdict"

cp $srcdict $dir/lexicon0.txt

#(2a) Dictionary preparation:
# Pre-processing (lower-case, remove comments)
awk 'BEGIN{getline}($0 !~ /^#/) {$0=tolower($0); print}' \
  $srcdict | sort -u | awk '($0 !~ /^[[:space:]]*$/) {print}' | grep -v "</s>" | grep -v "<s>" \
   > $dir/lexicon1.txt


cat $dir/lexicon1.txt | awk '{ for(n=2;n<=NF;n++){ phones[$n] = 1; }} END{for (p in phones) print p;}' | \
  grep -v sil > $dir/nonsilence_phones.txt

( echo sil; echo spn; echo nsn; echo lau ) > $dir/silence_phones.txt

echo sil > $dir/optional_silence.txt

# No "extra questions" in the input to this setup, as we don't
# have stress or tone.
echo -n >$dir/extra_questions.txt

# Add to the lexicon the silences, noises etc.
( echo '!sil sil'; echo '[vocalized-noise] spn'; echo '[noise] nsn'; \
  echo '[laughter] lau'; echo '<unk> spn' ) \
  | cat - $dir/lexicon1.txt  > $dir/lexicon2.txt

pushd $dir >&/dev/null
ln -sf lexicon2.txt lexicon.txt # This is the final lexicon.
popd >&/dev/null
echo Prepared input dictionary and phone-sets for people\'s daily
}
