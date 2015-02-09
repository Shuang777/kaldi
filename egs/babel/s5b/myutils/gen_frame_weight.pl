#!/usr/bin/perl -w

# This script picks the word segment, generate segments, and frame level weights using confidence score from ctm file

$ctmFile = $ARGV[0];
$outAlignFile = $ARGV[1];
$outWeightFile = $ARGV[2];
$threshold = 0.8;

open (CTMF, "<$ctmFile") || die "Unable to open input ctmFile $ctmFile\n";
open (OUTALIGNF, ">$outAlignFile") || die "Unable to open output outAlignFile $outAlignFile\n";
open (OUTWEIGHTF, ">$outWeightFile") || die "Unable to open output outWeightFile $outWeightFile\n";

$ctmitem = <CTMF>;
while ($line = <STDIN>) {
  $line =~ m/^(\S+)\s+(.+)$/g;
  $utt = $1;
  $alignments = $2;
  @alignment = split(/\s+/, $alignments);
  if (not defined($ctmitem)) {
    last;
  }
  $ctmutt = $ctmitem;
  $ctmutt =~ s/\s+.*$//g;
  if ($ctmutt gt $utt) {
    next;
  }
  while ($ctmutt eq $utt) {
    ($utt, $chn, $start, $dur, $word, $confidence) = split(/\s+/, $ctmitem);
    if ($confidence > $threshold and ($word !~ /</)) {
      $startindex = $start * 100;
      $duration = $dur * 100;
      $utt =~ /^(\S+)_([0-9]+)_([0-9]+)$/;
      $chn = $1;
      $oristart = $2;
      $oriend= $3;
      $newstart = sprintf("%07d", $oristart + $startindex);
      $newend = sprintf("%07d", $oristart + $startindex + $duration);
      print OUTALIGNF "$chn". "_" . "$newstart" . "_" . "$newend [ ";
      print OUTWEIGHTF "$chn". "_" . "$newstart" . "_" . "$newend [ ";
      for ($index = $startindex; $index < $startindex + $duration - 2; $index++) {
        print OUTALIGNF "$alignment[$index] ";
        print OUTWEIGHTF "$confidence ";
      }
      print OUTALIGNF "]\n";
      print OUTWEIGHTF "]\n";
    }
    $ctmitem = <CTMF>;
    if (not defined($ctmitem)) {
      last;
    }
    $ctmutt = $ctmitem;
    $ctmutt =~ s/\s+.*$//g;
  }

}
