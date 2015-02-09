# This is as arpa2G.sh but specialized for the per-syllable setup.  This is
# specific to the BABEL setup.
# The difference from arpa2G.sh is that (1) we have to change <unk> to <oov>, because
# <oov> is the name of the phone that was chosen to represent the unknown word [note:
# <unk> is special to SRILM, which is why it appears in the vocab]; and (2) we have
# a special step with fstrhocompose which we use to ensure that silence cannot appear
# twice in succession.  [Silence appears in the language model, which would naturally
# allow it to appear twice in succession.]

# input side, because <oov> is the name of the
{
set -e
set -o pipefail

echo "$0 $@"

# Begin configuration
midext=
# End configuration

. parse_options.sh

lmfile=$1
langdir=$2
destdir=$3

mkdir -p $destdir;

gunzip -c $lmfile | \
    grep -v '<s> <s>' | grep -v '</s> <s>' |  grep -v '</s> </s>' | \
    arpa2fst - | \
    fstprint | \
    utils/eps2disambig.pl | \
    utils/s2eps.pl | \
    fstcompile --isymbols=$langdir/words.merge.txt \
    --osymbols=$langdir/words.merge.txt  --keep_isymbols=false --keep_osymbols=false | \
    fstrmepsilon > $destdir/G.boost$midext.fst || exit 1

fstisstochastic $destdir/G.boost$midext.fst || true

fsttablecompose $langdir/L_disambig.wrd2syl.fst $destdir/G.boost$midext.fst | fstdeterminizestar --use-log=true | fstrmsymbols $langdir/phones/disambig.wrd2syl.int | fstminimizeencoded > $destdir/LGdet.boost$midext.fst

exit 0

}
