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
This script reads the keywords and the word surface file, then writes
all cross product surface forms for each keyword term.

Usage: $0 <keywords> <word_surfaces_in|-> <kw_surfaces_out|->

EOU

if (@ARGV != 3) {
  die $Usage;
}

# Get parameters
my $keyword_in = shift @ARGV;
my $word_surfaces_in = shift @ARGV;
my $kw_surfaces_out = shift @ARGV;

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

# Get the source for single-words surface forms
my $source = "";
if ($word_surfaces_in eq "-") {
  $source = "STDIN";
} else {
  open(I, "<$word_surfaces_in") || die "$0: Fail to open the word surface file $word_surfaces_in\n";
  binmode(I,":utf8");
  $source = "I";
}

# Get single-words surface forms
my %surfaces;
my $word_count = 0;
my $surface_count = 0;
print STDERR "Loading single-word surface forms from $word_surfaces_in ...\n";
while (<$source>) {
  chomp;
  my @col = split(/\t/, $_);
  @col == 2 || die "$0: Bad number of columns in $word_surfaces_in \"$_\"\n";
  my $word = $col[0];
  my $surface = $col[1];
  if (! defined $surfaces{$word}) {
    $surfaces{$word} = [];
    ++$word_count;
  }
  push(@{ $surfaces{$word} }, $surface);
  ++$surface_count;
}
if ($word_surfaces_in ne "-") {
  close(I);
}
print STDERR "Loaded $surface_count surface forms for $word_count words\n";

# construct multiple surface forms for each keyword term:
my %kw_surfaces;
my $total_surface_count = 0;
print STDERR "Constructing keyword terms surface forms ...\n";
foreach my $kwid (keys %keywords)
{
  my $term = $keywords{$kwid};
  my @tokens = split(/ /, $term);
  my $cross_product_surfaces_ref = &getCrossProductSurfaces(\@tokens);
  $kw_surfaces{$kwid} = $cross_product_surfaces_ref;
  $total_surface_count += scalar(@{ $kw_surfaces{$kwid} });
}
print STDERR "Constructed $total_surface_count surface forms for $total_kw_count keywords.\n";

# print keyword surfaces
my $outstr = "";
foreach my $kwid (sort(keys %kw_surfaces)) {
  foreach my $surface (sort @{ $kw_surfaces{$kwid} }) {
    $outstr .= sprintf("%s\t%s\n", $kwid, $surface);
  }
}
if ($kw_surfaces_out eq "-") {
  print STDOUT $outstr;
} else {
  open(O, ">$kw_surfaces_out") || die "$0: Fail to open the output file $kw_surfaces_out\n";
  binmode(O,":utf8");
  print O $outstr;
  close(O);
}


############ functions #############

# function for getting all cross-product surface forms from a sequence of words
#
# for single word terms, use all surface forms for the word
# for multiple word terms, use all cross-product surface forms from each individual words
#
sub getCrossProductSurfaces
{
  my ($tokens_ref) = @_;

  my @tokens_surfaces = ();
  foreach my $token (@$tokens_ref) {
    if (defined $surfaces{$token}) {
      push(@tokens_surfaces, $surfaces{$token});
    } else {
      # surface form not found, use the word itself.
      push(@tokens_surfaces, [$token]);
      print STDERR "Warning: no surface form for the word $token, use the word itself.\n";
    }
  }

  return &getCrossProductSurfacesHelper(0, "", \@tokens_surfaces);
}

# helper subroutine recursively called by getCrossProductSurfaces
#
# given one specific expansion of previous tokens in the sequence,
# expand all following tokens in the sequence to all possible surfaces
#
# arguments:
#   - current token position: from which this subsequence expansion starts
#   - prefix: one specific expansion of previous tokens
#   - tokens surfaces (reference):
#       - the first dimension indexes the token in the original token sequence
#       - the second dimension indexes the surface in the surface list of that token
# return:
#   - (reference of) a list of all cross product surface forms that start with the same given prefix.
#
sub getCrossProductSurfacesHelper
{
  my ($cur_tok_pos, $prefix, $tokens_surfaces_ref) = @_;
  my @ret_surfaces = ();

  # sanity check
  if ($cur_tok_pos == 0 && $prefix ne "") {
    die "Error: getCrossProductSurfacesHelper(): The prefix has to be empty string \"\" when current token position is 0.\n";
  }
  if ($cur_tok_pos < 0 || $cur_tok_pos > @$tokens_surfaces_ref) {
    die "Error: getCrossProductSurfacesHelper(): The current token position is out of bound.\n";
  }

  if ($cur_tok_pos == @$tokens_surfaces_ref) {
    # Last token. End of recursion.
    if (defined $prefix && $prefix ne "") {
      push(@ret_surfaces, $prefix);
    }
    return \@ret_surfaces;
  }
  else {
    for my $cur_tok_surface (@{ $tokens_surfaces_ref->[$cur_tok_pos] }) {
      # concatenate the current token surface with previous tokens expansions
      my $newPrefix;
      if ($cur_tok_pos == 0) {
        $newPrefix = "$cur_tok_surface";
      } else {
        $newPrefix = "$prefix $cur_tok_surface";
      }
      # recursively expand following tokens
      my $cross_product_surfaces_ref = &getCrossProductSurfacesHelper($cur_tok_pos + 1, $newPrefix, $tokens_surfaces_ref);
      push(@ret_surfaces, @$cross_product_surfaces_ref);
    }
    return \@ret_surfaces;
  }
}
