#!/bin/bash
{

set -e
set -o pipefail

format=ps    # pdf svg
mode=display # display save

. utils/parse_options.sh

if [ $# != 4 ]; then
   echo "usage: $0 [--mode display|save] [--format pdf|svg] <utt-id> <lattice-ark> <word-list> <dir>"
   echo "e.g.:  $0 utt-0001 \"test/lat.*.gz\" tri1/graph/words.txt"
   exit 1;
fi

. path.sh

uttid=$1
lat=$2
words=$3
tmpdir=$4

if [[ $lat =~ '.gz' ]]; then
  gunzip -c $lat | lattice-to-fst --rm-eps=false ark:- ark,scp:$tmpdir/fst.ark,$tmpdir/fst.scp
else
  lattice-to-fst --rm-eps=false ark:$lat ark,scp:$tmpdir/fst.ark,$tmpdir/fst.scp
fi

! grep "^$uttid " $tmpdir/fst.scp && echo "ERROR : Missing utterance '$uttid' from gzipped lattice ark '$lat'" && exit 1
fstcopy "scp:grep '^$uttid ' $tmpdir/fst.scp |" "scp:echo $uttid $tmpdir/$uttid.fst |"
fstdraw --portrait=true --osymbols=$words $tmpdir/$uttid.fst | dot -T${format} > $tmpdir/$uttid.${format}

cp $tmpdir/$uttid.${format} .

exit 0

}
