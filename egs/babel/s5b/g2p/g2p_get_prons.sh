#!/bin/sh 
{

DEFAULTPRON="s n s n s n s"
DEFAULTSILPRON="sil"
SYLDELIMITER="=";

# needed for indexgrep
export PERLLIB=$PERLLIB:/u/drspeech/share/lib/icsiargs.pl

function usage () {
    ( echo "Usage:"
      echo "$0 \\"
      echo "  -m model \\"
      echo "  -v vocablist \\"
      echo "  -d directory \\"
      echo "  [-s (syllable=false)] \\"
      echo "  [-S (constrain_syllables=false)] \\"
      echo "  [-h (hyphens=false)] \\"
      echo "  [-n (no_MBR=false)] \\"
      echo "  [-o output (stdout)] \\"
      echo "  [-e error_output (stderr)] \\"
      echo "  [-p (default_pron=$DEFAULTPRON)] \\"
      echo "  [-q (default_silence_pron=$DEFAULTSILPRON)] \\"
      echo "  [-e error_output (stderr)] \\"
      echo "  [-N (nbest=1) number of pronunciations to predict]\\"
    ) 1>&2
    exit 1
}

# phonetisaurus may dump core if there are unseen sequences
ulimit -c 0

# since we're checking status of pipes
#set -o pipefail

MBR="Y"

ARGS=`getopt -o 'm:v:o:d:e:N:sShn' -l 'model:,vocablist:,output:,directory:,error_output:,nbest:,syllable,constrain_syllables,hyphens,no_MBR' -- "$@"`

#check for bad args
if [ $? -ne 0 ]; then usage; fi

eval set -- "$ARGS"

# begin defaults
nbest=1
OUTPUT=/dev/stdout
ERRORS=/dev/stderr
# end defaults

while /bin/true; do
    case "$1" in
	-m|--model)
	    MODEL=$2;
	    shift 2;;
	-v|--vocablist) 
	    VOCAB=$2;
	    shift 2;;
	-o|--output)
	    OUTPUT=$2;
      [ -f $OUTPUT ] && rm $OUTPUT;
	    shift 2;;
  -d|--directory)
      TMPDIR=$2;
      [ -d $TMPDIR ] || mkdir -p $TMPDIR
      shift 2;;
	-e|--error_output)
	    ERRORS=$2;
      [ -f $ERRORS ] && rm $ERRORS;
	    shift 2;;
	-p|--default_pron)
	    DEFAULTPRON=$2;
	    shift 2;;
	-q|--default_silence_pron)
	    DEFAULTSILPRON=$2;
	    shift 2;;
  -N|--nbest)
      nbest=$2;
      shift 2;;
	-s|--syllable)
	    SYLLABLE="Y"
	    shift;;
	-S|--constrain_syllables)
	    CONSTRAIN_SYLLABLES="Y"
	    shift;;
	-h|--hyphens)
	    HYPHENS="-h"
	    shift;;
	-n|--no_MBR)
	    MBR="N";
	    shift;;
	--)
	    shift;
	    break;;
	*)
	    break;;
    esac
done

if [ -z "$VOCAB" -o -z "$MODEL" ]; then
    usage;
fi

if [ ! -e "$VOCAB" ]; then
    echo "$0: Can't find vocab file $VOCAB" 1>&2
    exit 1
fi

if [ ! -e "$MODEL" ]; then
    echo "$0: Can't find model file $MODEL" 1>&2
    exit 1
fi

if [ "$CONSTRAIN_SYLLABLES" = "Y" ]; then
    if [ ! -z "$HYPHENS" ]; then
	if [ "$DEFAULTPRON" = "s n s n s n s" ]; then
	    DEFAULTPRON="s${SYLDELIMITER}n s${SYLDELIMITER}n s${SYLDELIMITER}n${SYLDELIMITER}s"
	fi
    else
	if [ "$DEFAULTPRON" = "s n s n s n s" ]; then
	    DEFAULTPRON="s n . s n . s n s"
	fi
    fi
fi
    
if [ "$SYLLABLE" = "Y" ]; then
    cat > $TMPDIR/g2p.sed.$$ <<EOF
s/  */ . /g
s/__/~~/g
s/_/ /g
s/~~/ _/g
EOF
    filter="sed -f $TMPDIR/g2p.sed.$$"
elif [ "$CONSTRAIN_SYLLABLES" = "Y" ]; then
    filter="g2p/g2p_onc2sylmark.pl $HYPHENS"
else
    filter="cat"
fi

echo "filter is $filter"

#g2p/g2p_format_dictionary.py -c 2 < $VOCAB | sed 's/\t//' > $INPUT

if [ $MBR != "Y" ]; then
    use_mbr="false"
else
    use_mbr="true"
fi

#echo $INPUT
#set -x
echo "begin predicting"

phonetisaurus-g2p \
	--model=$MODEL \
	--input="$VOCAB" \
	--isfile=true \
	--sep='' \
	--mbr=$use_mbr \
  --words=true \
  --nbest=$nbest \
  1> $OUTPUT.tmp

cut -f3- $OUTPUT.tmp  | g2p/g2p_filter_nulls.sed | $filter > $OUTPUT.pron
cut -f1 $OUTPUT.tmp | paste /dev/stdin $OUTPUT.pron > $OUTPUT

exit 0
if [ -z "$OUTPUT" ]; then
    cut -f3 $TMPDIR/g2p.output.$$ | 
    sed -e 's/ \.//g' -e 's/^\. //' -e 's/ <\/s>//' | 
    $filter | 
    paste -d'	' $VOCAB - #|
#    sed 's/-/_/g'
else 
    cut -f3 $TMPDIR/g2p.output.$$ | 
    sed -e 's/ \.//g' -e 's/^\. //' -e 's/ <\/s>//' | 
    $filter |
    paste -d'	' $VOCAB - > $OUTPUT
    #sed 's/-/_/g' 
fi

}
