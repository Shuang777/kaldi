#!/usr/bin/perl -w

if (@ARGV != 4) {
  die "Usage: $0 keyword2Id.txt wordSeg.txt wav.scp outDir\n";
}

$word2IdFile = $ARGV[0];
$segmentsFile = $ARGV[1];
$wavScpFile = $ARGV[2];
$outDir = $ARGV[3];

if (not -d $outDir) {
  `mkdir -p $outDir`;
}

open (WORD2ID, $word2IdFile) || die "Uable to open input word2IdFile $word2IdFile\n";

%id2Keyword = ();
while ($line = <WORD2ID>) {
  $line =~ /^([^\d]+)\s+(\d+)$/g;
  $keyword = $1;
  $id = $2;
  $id2Keyword{$id} = $keyword;
}

open (WAVSCPFILE, $wavScpFile) || die "Uable to open input wavScpFile $wavScpFile\n";

%chn2Sph = ();
while ($line = <WAVSCPFILE>) {
  $line =~ /^(\S+)\s+(.+)\s+\|$/g;
  $channel = $1;
  $sph = $2;
  $chn2Sph{$channel} = $sph;
}

open (SEGFILE, $segmentsFile) || die "Uable to open input segmentsFile $segmentsFile\n";

while ($line = <SEGFILE>) {
  ($utt, $keywordId, $segStartFrame, $segLength) = split(/\s+/, $line);
  ($channel, $timeInfo) = split(/_/, $utt);
  ($uttStartFrame, $uttEndFrame) = split(/-/, $timeInfo);
  $wavFile = $outDir . "/" . $channel . ".wav";
  if (not -e $wavFile) {
    `$chn2Sph{$channel} > $wavFile`;
  }
  $startFrame = $uttStartFrame + $segStartFrame;
  $keywordName = $id2Keyword{$keywordId};
  $keywordName =~ s/\s+/_/g;
  $keywordName =~ s/'//g;
  $segFile = $outDir . "/" . $channel . "_" . $startFrame . "_" . $keywordName . ".wav";
  $startSeconds = ($startFrame / 100) . "s";
  $segLengthSeconds = ($segLength / 100) . "s";
  print "Segmenting $segFile\n";
  `sox $wavFile $segFile trim $startSeconds $segLengthSeconds\n`;
}
