#!/usr/bin/perl -w

if (@ARGV != 3) {
  die "Usage: $0 rttm inWav outBase\n";
}

$rttm = $ARGV[0];
$inWav = $ARGV[1];
$outBase = $ARGV[2];

open(rttmF, $rttm) || die "Unable to open input rttm file\n";

$count = 0;
while($line = <rttmF>) {
  if ($line !~ 'SPEAKER' or $line !~ 'SPEECH') {
    next;
  }
  ($spk, $nonSpeech, $chn, $tbeg, $tdur, $others) = split(/\s+/, $line);
  if ($tdur < 0.5) {
    print "Warning: ${outBase}_${count}.wav duration less than 0.5\n";
  }
  system("sox $inWav ${outBase}_${count}.wav trim $tbeg $tdur");
  $count = $count + 1;
}
print "$count segments generated for $inWav\n";
