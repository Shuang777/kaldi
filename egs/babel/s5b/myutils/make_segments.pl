#!/usr/bin/perl -w

if (@ARGV != 2) {
  die "Usage: $0 keywordSegFile outDir\n";
}

$keywordSegFile = $ARGV[0];
$outDir = $ARGV[1];

if (not -d $outDir) {
  `mkdir -p $outDir`;
}

$outSegments = $outDir . "/segments";
$outUtt2Id = $outDir . "/utt2id";

open (SEGFILE, $keywordSegFile) || die "Unable to open input keywordSegFile $keywordSegFile\n";
open (UTTSEGFILE, "| sort > $outSegments") || die "Unable to open output segments file\n";
open (UTT2IDFILE, "| sort > $outUtt2Id") || die "Unable to open output utt2id file\n";

while ($line = <SEGFILE>) {
  ($utt, $keywordId, $segStartFrame, $segLength) = split(/\s+/, $line);
  ($channel, $timeInfo) = split(/_/, $utt);
  ($uttStartFrame, $uttEndFrame) = split(/-/, $timeInfo);
  $wavchannel = $channel;   # wav channel use another representation
  $wavchannel =~ s/sw0//g;
  $wavchannel =~ s/-/_/g;
  $startFrame = $uttStartFrame + $segStartFrame;
  $endFrame = $startFrame + $segLength;
  $utt = sprintf("%s_%06d-%06d", $channel, $startFrame, $endFrame);
  printf UTTSEGFILE "%s %s %.2f %.2f\n" , $utt, $wavchannel, ($startFrame / 100), ($endFrame / 100);
  printf UTT2IDFILE "%s %d\n", $utt, $keywordId;
}
