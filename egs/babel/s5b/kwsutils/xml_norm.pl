#!/usr/bin/perl -w

my ($file) = shift @ARGV;

my ($fileId, $tbeg, $dur, $score, $decision, $keyword, $tend, $header, @keywords);

open (IN, $file) || die "Cannot open $file\n";

while(<IN>) {
  if (/<detected_kwlist /) {
    ($time, $kwId, $oovCount) = /<detected_kwlist search_time=\"(\S+)\" kwid=\"(\S+)\" oov_count=\"(\S+)\">/;
    printf("<detected_kwlist kwid=\"%s\" search_time=\"$time\" oov_count=\"1\">\n", $kwId, $time);
  } elsif (/(\s+)</) {
    $line = $_;
    $line =~ s/(\s+)</</;
    $line =~ s/score="0.0000000000"/score="0.00000000004"/;
    print $line;
  } else {
    print $_;
  }
}

close IN;
