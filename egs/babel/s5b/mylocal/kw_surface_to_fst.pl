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
This script reads the keywords, the symbol table and the keywords surfaces, then writes an fst for each keyword
to represent all the surface forms of the keyword.

Usage: $0 [options] <keywords> <symtab> <kw_surfaces_in|-> <kw_fsts_out|->

Allowed options:
  --silence-word              : Optional silence word added in between words                              (string,  default = "")
  --iv-keywords-out           : Output file for IV keywords (e.g. has one surface with only IV tokens)    (string,  default = "")
  --oov-keywords-out          : Output file for OOV keywords (e.g. all surfaces have OOV tokens)          (string,  default = "")

EOU

my $silence_word = "";
my $iv_keywords_out = "";
my $oov_keywords_out = "";
GetOptions('silence-word=s'   =>   \$silence_word,
  'iv-keywords-out=s'    =>  \$iv_keywords_out,
  'oov-keywords-out=s'   =>  \$oov_keywords_out);

if (@ARGV != 4) {
  die $Usage;
}

# Get parameters
my $keyword_in = shift @ARGV;
my $symtab_in = shift @ARGV;
my $kw_surfaces_in = shift @ARGV;
my $kw_fsts_out = shift @ARGV;

# Get keywords
my %keywords;
open(KW, "<$keyword_in") || die "$0: Fail to open the symbol table $keyword_in\n";
binmode(KW,":utf8");
print STDERR "Loading keywords from $keyword_in ...\n";
while (<KW>) {
  chomp;
  my @col = split(/\t/, $_);
  @col == 2 || die "$0: Bad number of columns in $keyword_in \"$_\"\n";
  my $kwid = $col[0];
  my $keyword = $col[1];
  defined $keywords{$kwid} && die "$0: Duplicate keyword ID in $keyword_in \"$_\"\n";
  $keywords{$kwid} = $keyword;
}
close KW;
my $total_kw_count = scalar(keys %keywords);
print STDERR "Loaded $total_kw_count keywords\n";

# Get symbol table
my %word_id;
open(SYM, "<$symtab_in") || die "$0: Fail to open the symbol table $symtab_in\n";
binmode(SYM,":utf8");
while (<SYM>) {
  chomp;
  my @col = split(/ /, $_);
  @col == 2 || die "$0: Bad number of columns in $symtab_in \"$_\"\n";
  my $word = $col[0];
  my $id = $col[1];
  defined $word_id{$word} && die "$0: Duplicate word in $symtab_in \"$_\"\n";
  $word_id{$word} = $id;
}
close SYM;

# Get silence word id
my $silence_id = "";
if ($silence_word ne "") {
  if (defined $word_id{$silence_word}) {
    $silence_id = $word_id{$silence_word};
  } else {
    die "$0: No silence word $silence_word in the symbol table $symtab_in\n";
  }
}

# Get the source for keywords surface forms
my $source = "";
if ($kw_surfaces_in eq "-") {
  $source = "STDIN";
} else {
  open(I, "<$kw_surfaces_in") || die "$0: Fail to open the keywords surfaces file $kw_surfaces_in\n";
  binmode(I,":utf8");
  $source = "I";
}

# Get keywords surface forms
my %kw_surfaces;
my $total_kw_count_from_surfaces = 0;
my $total_surface_count = 0;
print STDERR "Loading keywords surface forms from $kw_surfaces_in ...\n";
while (<$source>) {
  chomp;
  my @col = split(/\t/, $_);
  @col == 2 || die "$0: Bad number of columns in $kw_surfaces_in \"$_\"\n";
  my $kwid = $col[0];
  my $surface = $col[1];
  if (! defined $kw_surfaces{$kwid}) {
    $kw_surfaces{$kwid} = [];
    ++$total_kw_count_from_surfaces;
  }
  push(@{ $kw_surfaces{$kwid} }, $surface);
  ++$total_surface_count;
}
if ($kw_surfaces_in ne "-") {
  close(I);
}
print STDERR "Loaded $total_surface_count surface forms for $total_kw_count_from_surfaces keywords\n";
$total_kw_count == $total_kw_count_from_surfaces ||
  print STDERR "The number of keywords are different between $keyword_in and $kw_surfaces_in\n";

# print keyword fsts to string
my $outstr = "";
my %iv_kwid;
my %oov_kwid;
foreach my $kwid (sort(keys %kw_surfaces)) {
  my $outstr_kw = "";
  my $oov = 1;
  my $cur_state = 0;
  my $start_state = $cur_state++;
  #my $final_state = $cur_state++;
  SURFACE: foreach my $surface (sort @{ $kw_surfaces{$kwid} }) {
    my @surf_toks = split(/ /, $surface);
    foreach my $tok (@surf_toks) {
      next SURFACE unless defined $word_id{$tok};
    }
    $oov = 0;
    foreach my $i (0..$#surf_toks) {
      my $prev_state = $cur_state - 1;
      $prev_state = $start_state if $i == 0;
      my $tok = $surf_toks[$i];
      if ($silence_id ne "" && $i != 0) {
        # add the optional silence in between tokens, but not at the beginning or the end of the token sequence.
	$outstr_kw .= sprintf("%d\t%d\t%d\t%d\n", $prev_state, $prev_state, $silence_id, $silence_id);
      }
      $outstr_kw .= sprintf("%d\t%d\t%d\t%d\n", $prev_state, $cur_state++, $word_id{$tok}, $word_id{$tok});
    }
    $outstr_kw .= sprintf("%d\n", $cur_state-1);
  }
  if ($oov == 0) {
    #$outstr_kw .= sprintf("%d\n", $final_state);
    $outstr_kw = "$kwid \n" . $outstr_kw . "\n";
    $outstr .= $outstr_kw;
    $iv_kwid{$kwid} = 1;
  } else {
    $oov_kwid{$kwid} = 1;
  }
}
print STDERR "The total number of IV keywords (those KWs that have at least one surfaces with only IV tokens) : " . scalar(keys %iv_kwid) . "\n";
print STDERR "The total number of OOV keywords (those KWs whose surfaces all contain OOV tokens)              : " . scalar(keys %oov_kwid) . "\n";

# output the iv keywords
if ($iv_keywords_out ne "") {
  open(IV, ">$iv_keywords_out") || die "$0: Fail to open the iv keywords output file $iv_keywords_out\n";
  binmode(IV,":utf8");
  foreach my $kwid (sort(keys %iv_kwid)) {
    print IV "$kwid\t$keywords{$kwid}\n";
  }
  close(IV);
}

# output the oov keywords
if ($oov_keywords_out ne "") {
  open(OOV, ">$oov_keywords_out") || die "$0: Fail to open the oov keywords output file $oov_keywords_out\n";
  binmode(OOV,":utf8");
  foreach my $kwid (sort(keys %oov_kwid)) {
    print OOV "$kwid\t$keywords{$kwid}\n";
  }
  close(OOV);
}

# output the fsts string
if ($kw_fsts_out eq "-") {
  print STDOUT $outstr;
} else {
  open(O, ">$kw_fsts_out") || die "$0: Fail to open the fst output file $kw_fsts_out\n";
  binmode(O,":utf8");
  print O $outstr;
  close(O);
}

