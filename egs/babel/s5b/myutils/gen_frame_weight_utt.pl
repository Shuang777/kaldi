#!/usr/bin/perl -w

# This script generates frame-level weights using ctm confidence score
# Frames within the same word shares the same score
# For words not appeared in ctm, those frames are set to lower_threshold

$ctmFile = $ARGV[0];
$outWeightFile = $ARGV[1];
$lower_threshold = 0.01;

open (CTMF, "<$ctmFile") || die "Unable to open input ctmFile $ctmFile\n";
open (OUTWEIGHTF, ">$outWeightFile") || die "Unable to open output outWeightFile $outWeightFile\n";

$ctmitem = <CTMF>;
while ($line = <STDIN>) {
  $line =~ m/^(\S+)\s+(.+)$/g;
  $utt = $1;
  $alignments = $2;
  @alignment = split(/\s+/, $alignments);
  undef @weight;
  foreach ( 0 .. $#alignment) {
    $weight[$_] = $lower_threshold;
  }
  if (defined($ctmitem)) {
    $ctmutt = $ctmitem;
    $ctmutt =~ s/\s+.*$//g;
    if ($ctmutt gt $utt) {
      print OUTWEIGHTF "$utt [ ";
      for (0 .. $#weight) {
        print OUTWEIGHTF "$weight[$_] ";
      }
      print OUTWEIGHTF "]\n";
      next;
    } 
    while ($ctmutt eq $utt) {
      ($utt, $chn, $start, $dur, $word, $confidence) = split(/\s+/, $ctmitem);
      $startindex = $start * 100;
      $duration = $dur * 100;
      $utt =~ /^(\S+)_([0-9]+)_([0-9]+)$/;
      $chn = $1;
      $oristart = $2;
      $oriend= $3;
      for ($index = $startindex; $index < $startindex + $duration - 1; $index++) {
        $weight[$index] = $confidence;
      }
      $ctmitem = <CTMF>;
      if (not defined($ctmitem)) {
        last;
      }
      $ctmutt = $ctmitem;
      $ctmutt =~ s/\s+.*$//g;
    }
    print OUTWEIGHTF "$utt [ ";
      for (0 .. $#weight) {
        print OUTWEIGHTF "$weight[$_] ";
      } 
    print OUTWEIGHTF "]\n";
  }
}
