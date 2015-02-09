#!/usr/bin/perl

# Copyright 2014  The Ohio State University (Author: Yanzhang He)
# Apache 2.0.

use strict;
use warnings;
use Getopt::Long;

use utf8;
binmode(STDIN,":utf8");
binmode(STDOUT,":utf8");
binmode(STDERR,":utf8");

my $Usage = <<EOU;
This script reads the training lexicon and a new lexicon, then generate a decoding lexicon from the new lexicon
but optionally replacing the pronunciations of IV words with their pronunciations from the training lexicon.

Usage: $0 [options] <input_lexicon> <output_lexicon|->

Allowed options:
  --romanized                 : Has the romanized column in the lexicon                                   (boolean, default = false)

EOU

my $romanized = "false";
GetOptions('romanized=s'          =>  \$romanized);

($romanized eq "true" || $romanized eq "false") || die "$0: Bad value for option --romanized\n";

if (@ARGV != 2) {
  die $Usage;
}

# Get parameters
my $lexicon_in = shift @ARGV;
my $lexicon_out = shift @ARGV;

# Get the input training lexicon
my %lexicon;
open(IN, "<$lexicon_in") || die "$0: Fail to open the input training lexicon $lexicon_in\n";
binmode(IN,":utf8");
while (<IN>) {
  chomp;
  my @cols;
  if ($romanized eq "true") {
    @cols = split(/\t/, $_, 3);
    defined $cols[0] && defined $cols[1] && defined $cols[2] || die "$0: Bad format in $lexicon_in:\n$_\nStopped.\n";
  } else {
    @cols = split(/\t/, $_, 2);
    defined $cols[0] && defined $cols[1] || die "$0: Bad format in $lexicon_in:\n$_\nStopped.\n";
  }
  my $word = lc($cols[0]);
  my @prons = split(/\t/, $cols[-1]);
  foreach my $pron (@prons) {
    $lexicon{$word}{$pron} = 1;
  }
}
close IN;

# Generate the new lexicon
my $outstr = "";
my $word;
foreach $word (sort(keys %lexicon)) {
  $outstr .= $word . "\t";
  $outstr .= "xxxx\t" if ($romanized eq "true");
  $outstr .= join("\t", (keys %{$lexicon{$word}}));
  $outstr .= "\n";
}

# output the new lexicon
if ($lexicon_out eq "-") {
  print STDOUT $outstr;
} else {
  open(O, ">$lexicon_out") || die "$0: Fail to open the lexicon output file $lexicon_out\n";
  binmode(O,":utf8");
  print O $outstr;
  close(O);
}

