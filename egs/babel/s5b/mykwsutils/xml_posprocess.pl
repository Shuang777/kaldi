#!/usr/bin/perl -w

my ($file) = shift @ARGV;
my ($keywordsF) = shift @ARGV;

my ($fileId, $tbeg, $dur, $score, $decision, $keyword, $tend, $header, @keywords);

open (IN, $file) || die "Cannot open $file\n";
open (KEYF, $keywordsF) || die "Cannot open $keywordsF\n";

my %keywords = ();
my %allkeywords = ();

while(<KEYF>) {
  $line = $_;
  $line =~ s/(\s+)//g;
  $allkeywords{$line} = 1;
}

while(<IN>) {
  if (/<detected_kwlist /) {
    ($time, $kwId, $oovCount) = /<detected_kwlist search_time=\"(\S+)\" kwid=\"(\S+)\" oov_count=\"(\S+)\">/;
    if (exists $allkeywords{$kwId} ) {
      $keywords{$kwId} = 1;
      printf("<detected_kwlist kwid=\"%s\" search_time=\"$time\" oov_count=\"1\">\n", $kwId, $time);
      while(<IN>) {
        last if /<\/detected_kwlist>/;
        if (/(\s+)</) {
          $line = $_;
          $line =~ s/(\s+)</</;
          $line =~ s/score="0.0000000000"/score="0.00000000004"/;
          print $line;
        }
      }
      printf("<\/detected_kwlist>\n");
    } else {
      while(<IN>) {
        last if /<\/detected_kwlist>/;
      }
    }
  } elsif(/<\/kwslist>/) {
    for my $key ( keys %allkeywords ) { 
      if (not exists $keywords{$key}) {
        printf("<detected_kwlist kwid=\"%s\" search_time=\"1\" oov_count=\"1\">\n", $key);
        printf("</detected_kwlist>\n");
      }
    }
  } else {
    print $_;
  }
}

close IN;
