#!/usr/bin/perl

# Copyright 2014  International Computer Science Institute (author Hang Su)

if ($#ARGV == 2) {
  $alignFile = $ARGV[0];
  $lexFile = $ARGV[1];
  $stmFile = $ARGV[2];
} else {
  print STDERR ("Usage: $0 alignFile lexFile stmFile\n");
  print STDERR (" e.g.: $0 syl_text lexiconp.wrd2syl.txt data/dev10h/stm");
  exit(1);
}

open (ALIGNF, $alignFile) || die "Unable to open input alignFile $alignFile";

open (LEXF, $lexFile) || die "Unable to open input lexFile $lexFile";

open (STMF, $stmFile) || die "Unable to open input stmFile $stmFile";

%transcription = ();
while ($line = <ALIGNF>) {
  chomp; 
  if ($line =~ m:^([^\s]+)(\s+)(.+)$:) {
    $utt = $1;
    $text = $3;
    $transcription{$utt} = $text;
  } else {
    die "$0: cannot parse $alignFile\n";
  }
}

while ($line = <LEXF>) {
  chomp;
  if ($line =~ m:^([^\s]+)\s([^\s]+)\s(.+)$:) {
    $w = $1;
    $prob = $2;
    $pron = $3;
    $pron =~ s:\t: :g;
    $wrd2syl{$w} = $pron;
  } else {
    die "$0: cannot parse $lexFile\n";
  }
}

while ($line = <STMF>) {
  chomp;
  @A = split (/\s/, $line, 6);
  $utt = shift @A;
  $channel = shift @A;
  $timestamps = shift @A;
  $seg_start = shift @A;
  $seg_end = shift @A;
  $text = shift @A;
  if (exists $transcription{$utt}){
    $syltext = $transcription{$utt};
  } else {
    $syltext = "";
    @tokens = split(/\s/, $text);
    while ($w = shift(@tokens)) {
      if (exists $wrd2syl{$w}) {
        $syltext .= " ". $wrd2syl{$w};
      } else {
        $syltext .= " ". $w;
      }
    }
  }
  $syltext =~ s:^\s+::;
  print "$utt $channel $timestamps $seg_start $seg_end $syltext\n";
}
