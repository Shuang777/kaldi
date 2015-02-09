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

Usage: $0 [options] <train_lexicon> <input_decode_lexicon> <output_decode_lexicon|->

Allowed options:
  --use-train-prons           : Use the training pronunciations for IV words                              (boolean, default = true)
  --romanized                 : Has the romanized column in the lexicon                                   (boolean, default = false)

EOU

my $use_train_prons = "true";
my $romanized = "false";
GetOptions('use-train-prons=s'   =>   \$use_train_prons,
  'romanized=s'          =>  \$romanized);

($use_train_prons eq "true" || $use_train_prons eq "false") || die "$0: Bad value for option --use-train-prons\n";
($romanized eq "true" || $romanized eq "false") || die "$0: Bad value for option --romanized\n";

if (@ARGV != 3) {
  die $Usage;
}

# Get parameters
my $train_lexicon_in = shift @ARGV;
my $decode_lexicon_in = shift @ARGV;
my $decode_lexicon_out = shift @ARGV;

# Get the input training lexicon
my %train_lexicon;
open(TRAIN, "<$train_lexicon_in") || die "$0: Fail to open the input training lexicon $train_lexicon_in\n";
binmode(TRAIN,":utf8");
while (<TRAIN>) {
  chomp;
  my @cols;
  if ($romanized eq "true") {
    @cols = split(/\t/, $_, 3);
    defined $cols[0] && defined $cols[1] && defined $cols[2] || die "$0: Bad format in $train_lexicon_in:\n$_\nStopped.\n";
  } else {
    @cols = split(/\t/, $_, 2);
    defined $cols[0] && defined $cols[1] || die "$0: Bad format in $train_lexicon_in:\n$_\nStopped.\n";
  }
  my $word = $cols[0];
  $train_lexicon{$word} = [] unless defined $train_lexicon{$word};
  push(@{ $train_lexicon{$word} }, \@cols);
}
close TRAIN;

# Get the input decoding lexicon
my %decode_lexicon;
open(DECODE, "<$decode_lexicon_in") || die "$0: Fail to open the input decoding lexicon $decode_lexicon_in\n";
binmode(DECODE,":utf8");
while (<DECODE>) {
  chomp;
  my @cols;
  my ($word, $prons) = split(/\t/, $_, 2);
  defined $word && defined $prons || die "$0: Bad format in $decode_lexicon_in:\n$_\nStopped.\n";
  if ($romanized eq "true") {
    push(@cols, ($word, "xxxx", $prons));
  } else {
    push(@cols, ($word, $prons));
  }
  $decode_lexicon{$word} = [] unless defined $decode_lexicon{$word};
  push(@{ $decode_lexicon{$word} }, \@cols);
}
close DECODE;

# Generate the new decoding lexicon
my %chosen_words;
my $outstr = "";
my $word;
foreach $word (sort(keys %decode_lexicon)) {
  my $entries;
  if ($use_train_prons eq "true" && defined $train_lexicon{$word}) {
    $entries = $train_lexicon{$word};
  } else {
    $entries = $decode_lexicon{$word};
  }
  foreach my $entry (@$entries) {
    $outstr .= join("\t", @$entry) . "\n";
  }
  $chosen_words{$word} = 1;
}
# keep the special tag words
foreach $word (sort(keys %train_lexicon)) {
  next if defined $chosen_words{$word} || $word !~ /^<.+>$/;
  my $entries = $train_lexicon{$word};
  foreach my $entry (@$entries) {
    $outstr .= join("\t", @$entry) . "\n";
  }
  $chosen_words{$word} = 1;
}

# output the new decoding lexicon
if ($decode_lexicon_out eq "-") {
  print STDOUT $outstr;
} else {
  open(O, ">$decode_lexicon_out") || die "$0: Fail to open the lexicon output file $decode_lexicon_out\n";
  binmode(O,":utf8");
  print O $outstr;
  close(O);
}

