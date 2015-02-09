#!/usr/bin/env perl
#
# Given a kwlist file, generate a list of kwid oovcount.
#
# This script was original for sanity checking, which is why it does
# a lot more work than needed for this particular task.
#
# Jan 20, 2014 - OOPS! Lexicon included dev words. Now only includes training or sub-training words.
#
# Feb 26 2014 Ryan He - Used the basename of the KwList instead of the full name so if the directory coincidentally contains a match it doesn't use it.
#

use strict;
use FileHandle;
use DirHandle;
use Encode;
use File::Basename;

my $KwList;
my $IsLLP = "0";

if ($#ARGV == 0) {
    $KwList = shift;
} elsif ($#ARGV == 1) {
    $KwList = shift;
    $IsLLP = shift;
} else {
    usage();
}

# The top level to the Babel corpora directories.
my $BABEL_CORPORA;
if (defined($ENV{BABEL_CORPORA})) {
    $BABEL_CORPORA = $ENV{BABEL_CORPORA};
} elsif (-d '/corpora') {
    $BABEL_CORPORA = '/corpora';
} elsif (-d '/u/drspeech/data/swordfish/corpora') {
    $BABEL_CORPORA = '/u/drspeech/data/swordfish/corpora';
} else {
    die "Couldn't find BABEL_CORPUS directory.\n";
}

my $BaseLP;  # LP without _LLP (if any)
my $LP;
my %Lexicon;
my %OOV;
my @OOV;
my %KW;
my @KW;
my %TrainingWords;

my $KwList_filename = `basename $KwList`;
chop($KwList_filename);
$BaseLP = `babelname -lp $KwList_filename`;
chop($BaseLP);
if ($IsLLP) {
    $LP = "${BaseLP}_LLP";
} else {
    $LP = $BaseLP;
}

%TrainingWords = read_trans_words($LP, 'training');
read_lexicon($LP);
checkcontents($KwList);

sub usage {
    print STDERR "Usage: kwlist2oov.pl babel105b-v0.4_conv-eval.kwlist2.xml [llp]\n\n";
    print STDERR "Prints a list of kwid oovcount, where the oovcount is the number of words\n";
    print STDERR "in the keyphrase specified by kwid that are not in the corresponding lexicon.\n\n";
    print STDERR "If llp is provided and not \"0\", the Limited Language Pack lexicon will be used.\n\n";
    exit(1);
}

# Read the lexicon, only including words that are in %TrainingWords.

sub read_lexicon {
    my($lp) = @_;
    my($fh, $line, $word, $pron);
    $fh = new FileHandle("$BABEL_CORPORA/$lp/conversational/reference_materials/lexicon.txt") or die "Couldn't open lexicon for $lp: $!";
    $fh->binmode(":utf8");
    while ($line = <$fh>) {
	chop($line);
	if ($line =~ /^(.*?)\t(.*)$/) {
	    $word = lc($1);
	    $pron = $2;
	    next if !exists($TrainingWords{$word});
	    $Lexicon{$word} = $pron;
	} else {
	    die "Bad line $line in lexicon for $lp";
	}
    }
}

# Read transcript words from $lp/conversational/$cond/transcription
# Return a hash of them.

sub read_trans_words {
    my($lp, $cond) = @_;
    my($fn, $fh, $dh, $line, $word);
    my(%words);
    $dh = new DirHandle("$BABEL_CORPORA/$lp/conversational/$cond/transcription") or die "Couldn't open $cond transcriptions for $lp: $!";
    while ($fn = $dh->read()) {
	next if $fn !~ /$BaseLP.*\.txt$/;
	$fh = new FileHandle("$BABEL_CORPORA/$lp/conversational/$cond/transcription/$fn") or die "Couldn't open $fn: $!";
	$fh->binmode(":utf8");
	while ($line = <$fh>) {
	    chop($line);
	    next if $line =~ /^\[[0-9.]+\]$/;
	    foreach $word (split(/\s+/, $line)) {
		$words{lc($word)}++;
	    }
	}
	$fh->close();
    }
    $dh->close();
    return %words;
}
    

sub checkcontents {
    my($n) = @_;
    my($fh, $line, $kwid, $kwtext, @kwtext, $inkw, $sawend, $oovcount);
    $fh = new FileHandle($n) or die "Couldn't open $n: $!";
    $fh->binmode(":utf8");
    $line = <$fh>;
    if ($line !~ /^<kwlist/) {
	die "Bad first line $line\n";
    }
    $inkw = 0;
    $sawend = 0;
    while ($line = <$fh>) {
	if ($line =~ /^\s*<kw kwid=\"(.*)\">\s+$/) {
	    if ($inkw) {
		die "Found <kw> inside a <kw>\n";
	    }
	    $inkw = 1;
	    $kwid = $1;
	} elsif ($line =~ /^\s*<kwtext>(.*)<\/kwtext>\s*$/) {
	    if (! $inkw) {
		die "Found <kwtext> outside of <kw>\n";
	    }
	    $kwtext = lc($1);
	    if (exists($KW{$kwtext})) {
		warn "Duplicate '$kwtext' $kwid $KW{$kwtext}\n";
	    }
	    $KW{$kwtext} = $kwid;
	    @kwtext = split(/\s+/, $kwtext);
	    $oovcount = 0;
	    if (!exists($Lexicon{$kwtext})) {
		foreach my $word (@kwtext) {
		    if (!exists($Lexicon{$word})) {
			$oovcount++
		    }
		}
	    }
	    print "$kwid $oovcount\n";
	} elsif ($line =~ /^\s*<\/kw>\s*$/) {
	    if (! $inkw) {
		die "Found </kw> outside <kw>\n";
	    }
	    $inkw = 0;
	} elsif ($line =~ /^\s*<\/kwlist>\s*$/) {
	    if ($inkw) {
		die "Found </kwlist> inside <kw>\n";
	    }
	    $sawend = 1;
	    last;
	} else {
	    die "Unexpected line $line\n";
	}
    }
    if (!$sawend) {
	die "Missing </kwlist>";
    }
    while ($line = <$fh>) {
	if ($line !~ /^\s*$/) {
	    die "Found extra stuff after </kwlist>\n";
	}	       
    }
    $fh->close();
}

