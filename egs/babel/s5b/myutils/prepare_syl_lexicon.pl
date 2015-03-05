#!/usr/bin/perl
use Getopt::Long;
use Data::Dumper;

###############################################################################
#
# Convert a kaldi word dictionary to syllable dictionary and syllable to phone 
# mapping
#
# Convert dictionary from entries of the form
#
#       WORD	prob	sylpron1	sylpron2	...
#
# where each sylpron has pronounciation
#
#       Phone1 Phone2 Phone3
#
# and so on, e.g.
#
#       অ	1.0	S O	r e	O
#
# to entries of the form
#
#       অ	1.0	S=O	r=e
#
# and
#       S=O	1.0	S O
#       r=e	1.0	r e
#       O	1.0	O
#
# Write only one pronunciation per line
#
# This script will create 4 new files
#
#   -  lexiconp.wrd2syl.txt
#
#   -  lexiconp.syl2phn.txt
#
#   -  lexiconp.wrd2syl.txt
#
#   -  lexiconp.syl2phn.txt
#
###############################################################################
$posphone = false;
GetOptions("posphone=s" => \$posphone);

if ($#ARGV == 1) {
    $expDir = $ARGV[0];
    $tmpDir = $ARGV[1];
    $inDict = "$expDir/lexiconp.txt";
    print STDERR ("$0: $expDir $tmpDir\n");
} else {
    print STDERR ("Usage: $0 [--options] expDir tmpDir\n");
    print STDERR (" e.g.: $0 data/local data/local/tmp.lang\n");
    exit(1);
}

unless (-e $inDict) {
    die "$0: $inDict does not exist! Please prepare that first.\n";
}

mkdir ($tmpDir) unless (-d $tmpDir);

$outWrd2SylLex = "$expDir/lexiconp.wrd2syl.txt";
$outSyl2PhnLex = "$expDir/lexiconp.syl2phn.txt";
$outPosWrd2SylLex = "$tmpDir/lexiconp.wrd2phn.txt";
$outPosSyl2PhnLex = "$tmpDir/lexiconp.syl2phn.txt";
$outPosSylWrd2PhnLex = "$tmpDir/lexiconp.sylwrd2phn.txt";

###############################################################################
# Read input lexicon, write output lexicon, and save the set of phones & tags.
###############################################################################

open (INLEX, $inDict)
    || die "Unable to open input dictionary $inDict";

open (OUTLEX, "| sort -u > $outWrd2SylLex")
    || die "Unable to open output dictionary $outWrd2SylLex";

open (OUTSYLLEX, "| sort -u > $outSyl2PhnLex")
    || die "Unable to open output dictionary $outSyl2PhnLex";

open (OUTPOSLEX, "| sort -u > $outPosWrd2SylLex")
    || die "Unable to open output dictionary $outPosWrd2SylLex";

open (OUTPOSSYLLEX, "| sort -u > $outPosSyl2PhnLex")
    || die "Unable to open output dictionary $outPosSyl2PhnLex";

open (OUTPOSSYLWRDLEX, "| sort -u > $outPosSylWrd2PhnLex")
    || die "Unable to open output dictionary $outPosSylWrd2PhnLex";

while ($line=<INLEX>) {
    chomp;
    if ($line =~ m:^([^\t]+)\t([^\t]+)((\t[^\t]+)+)$:)  {
        $word = $1;
        $prob = $2;
        $sylprons = $3;
        $sylprons =~ s:^\s+::;           # Remove leading white-space
        $sylprons =~ s:\s+$::;           # Remove trailing white-space
        @sylpron  = split("\t", $sylprons);
        $newpron = '';

        print OUTPOSLEX ("$word $prob");

        for $p (0 .. $#sylpron) {
            $sylpronp = $sylpron[$p];
            $sylpronp =~ s:^\s+::;
            $sylpronp =~ s:\s+$::;
            $syl = $sylpronp;
            if ($syl =~ m:<([^\t]+)>$:) {   # something like <silence>
                $syl = $word;
            } else {
                $syl =~ s:\s+:=:g;
            }
            print OUTSYLLEX ("$syl\t1.0\t$sylpronp\n");
            print OUTPOSSYLLEX ("$syl 1.0");
            print OUTPOSSYLWRDLEX ("$syl 1.0");

            @sylpronpsplit=split(" ",$sylpronp);
            for $i (0 .. $#sylpronpsplit) {
                if ($#sylpronpsplit == 0) { $sylpos="_S"; 
                } elsif ($i == 0) { $sylpos="_B"; 
                } elsif ($i == $#sylpronpsplit) { $sylpos="_E"; 
                } else { $sylpos="_I"; 
                }
                if ($#sylpronpsplit == 0 and $#sylpron == 0) { $wrdpos="_S";
                } elsif ($i == 0 and $p == 0) { $wrdpos="_B";
                } elsif ($i == $#sylpronpsplit and $p == $#sylpron) { $wrdpos="_E";
                } else { $wrdpos="_I";
                }
                if ($posphone eq 'false') {
                  $wrdpos = "";
                  $sylpos = "";
                }
                print OUTPOSLEX (" $sylpronpsplit[$i]". "$wrdpos");
                print OUTPOSSYLLEX (" $sylpronpsplit[$i]". "$wrdpos");
                print OUTPOSSYLWRDLEX (" $sylpronpsplit[$i]". "$sylpos");
            }
           $newpron .= "\t" . $syl;
           print OUTPOSSYLLEX ("\n");
           print OUTPOSSYLWRDLEX ("\n");
        }
        print OUTPOSLEX ("\n");
        print OUTLEX ("$word\t$prob$newpron\n");
    } else {
        print STDERR ("$0 WARNING: Skipping unparsable line $. in $inDict\n");
    }
}
close(INLEX);
close(OUTLEX);
close(OUTSYLLEX);
close(OUTPOSLEX);
close(OUTPOSSYLLEX);
close(OUTPOSSYLWRDLEX);
