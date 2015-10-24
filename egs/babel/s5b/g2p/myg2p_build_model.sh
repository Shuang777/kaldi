#!/bin/bash 

function usage () {
    ( echo "Usage:"
      echo "$0 \\"
      echo "  -d dictionary \\"
      echo "  -o output_model \\"
      echo "  [-p prefix (=dictionary)] \\"
      echo "  [-c column (auto-determined if not set)] \\"
      echo "  [-s (syllable=false)] \\"
      echo "  [-b (break_syllables=false)] \\"
      echo "  [-S (constrain_syllables=false)] \\"
      echo "  [-r (roman_phones=false)] \\ "
      echo "  [-u (remove_underscores=false)] \\ "
      echo "  [-G max_grapheme_cluster (=2)] \\"
      echo "  [-P max_phoneme_cluster (=4)] \\"
      echo "  [-i interpolate (=1.0)] \\"
      echo "  [-z (clean=false)] \\" 
      echo "  [-h (help=false)]"
    ) 1>&2
    exit 1
}

function help () {
    ( echo "Help for $0:"
	echo "This program will create the joint multigram FST used for grapheme to"
	echo "phoneme conversion, based on the phonetisaurus toolchain."
	echo "Options include:"
	echo "-d / --dictionary: input dictionary.  Assumes that the columns of the"
	echo "                  dictionary are tab-separated"
	echo "-o / --output_model: FST model that is output, encoding multigram"
	echo "-p / --prefix: prefix for all intermediate files.  Default is just"
	echo "              the dictionary file"
	echo "-c / --column: which column is used as the pronunciation, autodetermined"
	echo "-s / --syllable: make this a grapheme-to-syllable converter.  Predicts"
	echo "                 on a syllable basis. Assumes that the syllables are"
        echo "                 separated with a '.' char."
	echo "-b / --break_syllables: if the numbers of characters equals the"
	echo "                        number of syllables, also train each character"
	echo "                        separately (for Cantonese, e.g.)"
	echo "-S / --constrain_syllables: build a grapheme-to-phoneme predictor"
	echo "                            but then constrain to have syllable output"
	echo "                            advised for most purposes"
	echo "-r / --roman_phones: for syllable grammar, also grab words with roman phones"
	echo "                     and create phone-based models"
        echo "-u / --remove_underscores: use underscores for acronym detection and then delete."
	echo "-G / --max_grapheme_cluster: controls the maximum number of graphemes"
	echo "                            in the multigram cluster."
	echo "-P / --max_phoneme_cluster: controls the number of phonemes/syllables"
	echo "                           in the multigram cluster."
	echo "NOTE: the defaults for cluster size are set assuming phonemes."
	echo "      For syllables, you may need to adjust these."
	echo "-t / --move_tones: move the tones to the syllable nucelus before starting"
	echo "-i / --interpolate: mix the main lm with an lm created using unigrams (-G 1)."
	echo "                    A value of 1.0 (the default) means don't interpolate" 
	echo "                    with a unigram lm and a value of 0.0"
	echo "                    means use only the unigram lm."
	echo "-z / --clean: clean up intermediate files"
	echo "-h / --help: this message"
	) 1>&2
    exit 0
}

function add_to_clean () {
    CLEANLIST="$CLEANLIST $1"
}

# passed a lexicon as argument, determines appropriate column
function determine_column () {
    cut -f2 $1 | awk 'NF>1 {print 2; foo=1; exit} END {if (!foo) {print 3}}'
    return $?;
}

#####################################################################
# The floating point functions below were taken from:
#
#    http://www.linuxjournal.com/content/floating-point-math-bash
#
# usage examples can be found on that page.
#

# Default scale used by float functions.
float_scale=4

#####################################################################
# Evaluate a floating point number expression.

function float_eval()
{
    local stat=0
    local result=0.0
    if [[ $# -gt 0 ]]; then
        result=$(echo "scale=$float_scale; $*" | bc -q 2>/dev/null)
        stat=$?
        if [[ $stat -eq 0  &&  -z "$result" ]]; then stat=1; fi
    fi
    echo $result
    return $stat
}

#####################################################################
# Evaluate a floating point number conditional expression.

function float_cond()
{
    local cond=0
    if [[ $# -gt 0 ]]; then
        cond=$(echo "$*" | bc -q 2>/dev/null)
        if [[ -z "$cond" ]]; then cond=0; fi
        if [[ "$cond" != 0  &&  "$cond" != 1 ]]; then cond=0; fi
    fi
    local stat=$((cond == 0))
    return $stat
}

#defaults
#COLUMN=2  -- autodetermined later
SYLLABLE=""
MAX_GRAPHEME_CLUSTER=2
MAX_PHONEME_CLUSTER=4
CLEAN=N
INTERP=1.0
VERBOSE=""

ARGS=`getopt -o "d:p:c:sbSruG:P:o:i:mzh" -l "dictionary:,prefix:,column:,syllable,break_syllables,constrain_syllables,roman_phones,remove_underscores,max_grapheme_cluster:,max_phoneme_cluster:,output_model:,interpolate:,multiple_em_estimations,clean,help" -- "$@"`

#check for bad args
if [ $? -ne 0 ]; then usage; fi

eval set -- "$ARGS"

while /bin/true; do
    case "$1" in
	-d|--dictionary)
	    BASEDICT=$2
	    shift 2;;
	-p|--prefix)
	    PREFIX=$2
	    shift 2;;
	-c|--column)
	    if [ -n "$2" ]; then
		COLUMN=$2;
	    else
		echo "$0: Column argument must be a number" 1>&2
		exit 1
	    fi
	    shift 2;;
	-s|--syllable)
	    SYLLABLE="-s -t-"
	    shift;;
	-b|--break_syllables)
	    BREAK_SYLLABLES="Y"
	    shift;;
	-S|--constrain_syllables)
	    CONSTRAIN_SYLLABLES="Y"
	    shift;;
	-r|--roman_phones)
	    echo roman
	    ROMAN="Y"
	    shift;;
        -u|--remove_underscores)
            REMOVE_UNDERSCORES="Y"
            shift;;
	-G|--max_grapheme_cluster)
	    if [ -n "$2" ]; then
		MAX_GRAPHEME_CLUSTER=$2;
		MAX_GRAPHEME_CLUSTER_SET=Y
	    else
		echo "$0: max_grapheme_cluster argument must be a number" 1>&2
		exit 1
	    fi
	    shift 2;;
	-P|--max_phoneme_cluster)
	    if [ -n "$2" ]; then
		MAX_PHONEME_CLUSTER=$2;
		MAX_PHONEME_CLUSTER_SET=Y
	    else
		echo "$0: max_phoneme_cluster argument must be a number" 1>&2
		exit 1
	    fi
	    shift 2;;
	-o|--output_model)
	    MODEL=$2
	    shift 2;;
	-i|--interpolate)
	    if [ -n "$2" ]; then
		INTERP=$2;
		if float_cond "$INTERP > 1.0"; then
		    echo "$0: interpolate arg must be <= 1.0"
		    exit 1
		fi
		if float_cond "$INTERP < 0.0"; then
		    echo "$0: interpolate arg must be >= 0.0"
		    exit 1
		fi
	    else
		echo "$0: --interpolate requires an argument" 1>&2
		exit 1
	    fi
	    shift 2;;
	-z|--clean)
	    CLEAN=Y
	    shift;;
	-h|--help)
	    help
	    shift;;
	--)
	    shift
	    break;;
	*) 
	    break;;
    esac
done

if [ -z "$BASEDICT" -o -z "$MODEL" ]; then
    usage;
fi

if [ -z "$PREFIX" ]; then
    PREFIX=$BASEDICT
fi

if [ -z "$COLUMN" ];then
    COLUMN=`determine_column $BASEDICT`
fi

CLEANLIST="";		

echo COLUMN=$COLUMN

grep -v '^<' $BASEDICT | g2p/g2p_preprocess_lexicon.pl > $BASEDICT.preprocess
BASEDICT=$PREFIX.preprocess

python2 g2p/myg2p_format_dictionary.py -c $COLUMN $SYLLABLE < $BASEDICT > $PREFIX.g2p_corpus

cp $PREFIX.g2p_corpus $PREFIX.g2p_corpus.hold

if [ ! -z "$SYLLABLE" ]; then
  # break apart into phones for words that are all phones
  g2p/g2p_break_syllables_for_roman.pl $PREFIX.g2p_corpus > $PREFIX.g2p_corpus.romanbreak
  mv $PREFIX.g2p_corpus.romanbreak $PREFIX.g2p_corpus
  if [ ! -z "$BREAK_SYLLABLES" ]; then
    perl -n -e 'print;
                chomp;
                ($grapheme,$syl)=split(/	/);
                $grapheme=~s/ _//g;
                @g=split(/ /,$grapheme);
                @s=split(/ /,$syl);
                if ($#g==$#s) { for ($i=0;$i<=$#g;$i++) {print "$g[$i]\t$s[$i]\n";} }' $PREFIX.g2p_corpus > $PREFIX.g2p_corpus.withbreaks
    mv $PREFIX.g2p_corpus.withbreaks $PREFIX.g2p_corpus
  fi
fi

if [ ! -z "$REMOVE_UNDERSCORES" ]; then
    cut -f1 $PREFIX.g2p_corpus | sed 's/ [_-]//g' > $PREFIX.g2p_corpus.vocab
    cut -f2 $PREFIX.g2p_corpus > $PREFIX.g2p_corpus.pron
    paste $PREFIX.g2p_corpus.vocab $PREFIX.g2p_corpus.pron > $PREFIX.g2p_corpus
#    rm $PREFIX.g2p_corpus.{vocab,pron}
fi

add_to_clean $PREFIX.g2p_corpus

IGNORE_UNPRONOUNCEABLE="Y"

if [ ! -z "$IGNORE_UNPRONOUNCEABLE" ]; then
    mv $PREFIX.g2p_corpus $PREFIX.g2p_corpus.wunpron
    g2p/g2p_remove_unpronounceable.pl $PREFIX.g2p_corpus.wunpron > $PREFIX.g2p_corpus
    add_to_clean $PREFIX.g2p_corpus.wunpron
fi

phonetisaurus-align \
    --input=$PREFIX.g2p_corpus \
    --ofile=$PREFIX.g2p_corpus.aligned \
    --s1_char_delim=" " \
    --skip='.' \
    --seq1_del=false \
    --seq2_del=false \
    --seq1_max=$MAX_GRAPHEME_CLUSTER \
    --seq2_max=$MAX_PHONEME_CLUSTER ;

for order in 7 6 5 4 3 2 1; do
  ngram-count \
    -order $order \
    -kn-modify-counts-at-end \
    -gt1min 0 -gt2min 0 -gt3min 0 -gt4min 0 \
    -gt5min 0 -gt6min 0 -gt7min 0 \
    -ukndiscount -ukndiscount1 -ukndiscount2 \
    -ukndiscount3 -ukndiscount4 -ukndiscount5 \
    -ukndiscount6 -ukndiscount7 \
    -text $PREFIX.g2p_corpus.aligned \
    -lm $PREFIX.lm

  if [ $? -eq 0 ]; then
    echo "LM of order $order built"
    break
  else
    echo "Problems building LM order $order... backing off"
  fi
done


if float_cond "$INTERP < 1.0"; then

    # Build a non-multigram lm to interpolate with the main lm
  phonetisaurus-align \
    --input=$PREFIX.g2p_corpus \
    --ofile=$PREFIX.g2p_corpus.aligned_G1 \
    --s1_char_delim=" " \
    --skip='.' \
    --seq1_max=1 \
    --seq2_max=7 ;

  ngram-count \
    -order $order \
    -kn-modify-counts-at-end \
    -gt1min 0 -gt2min 0 -gt3min 0 -gt4min 0 \
    -gt5min 0 -gt6min 0 -gt7min 0 \
    -ukndiscount -ukndiscount1 -ukndiscount2 \
    -ukndiscount3 -ukndiscount4 -ukndiscount5 \
    -ukndiscount6 -ukndiscount7 \
    -text $PREFIX.g2p_corpus.aligned_G1 \
    -lm $PREFIX.lm_G1

  ngram \
    -order $order \
    -lm $PREFIX.lm \
    -mix-lm $PREFIX.lm_G1 \
    -lambda $INTERP \
    -write-lm $PREFIX.lm_interp

else
  ln -s `basename $PREFIX.lm` $PREFIX.lm_interp
fi

add_to_clean $PREFIX.lm

phonetisaurus-arpa2fst \
  --null_sep='.' \
  --input=$PREFIX.lm_interp \
  --prefix=$PREFIX

mv $PREFIX.fst $MODEL

if [ ! -z "$IGNORE_UNPRONOUNCABLE" ]; then
    fstsymbols --save_isymbols=$PREFIX.isyms $MODEL /dev/null
    g2p/g2p_build_preprocessor.pl $PREFIX.isyms $PREFIX.presyms $MODEL.prefst.txt
    fstcompile --keep_symbols --isymbols=$PREFIX.presyms --osymbols=$PREFIX.isyms $MODEL.prefst.txt $MODEL.prefst
    mv $MODEL $MODEL.mainfst
    fstcompose $MODEL.prefst $MODEL.mainfst $MODEL
fi


if [ ! -z "$CONSTRAIN_SYLLABLES" ]; then
  mv $MODEL $MODEL.nosylconstrfst
  g2p/g2p_build_syllable_constrainer.pl $MODEL.nosylconstrfst $BASEDICT $MODEL
fi

