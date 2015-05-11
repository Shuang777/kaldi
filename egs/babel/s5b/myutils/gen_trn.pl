#!/usr/bin/perl

# Copyright 2014  International Computer Science Institute (author Hang Su)

if ($#ARGV == 2) {
  $g2pLex = $ARGV[0];
  $refLex = $ARGV[1];
  $outDir = $ARGV[2];
} else {
  print STDERR ("Usage: $0 g2pLex realLex outDir\n");
  print STDERR (" e.g.: $0 oov_lex.txt lexiconp.wrd2syl.txt exp/gen_oov_lex");
  exit(1);
}

open (G2PLEX, $g2pLex) || die "Unable to open input g2pLex $g2pLex";
open (REFLEX, $refLex) || die "Unable to open input refLex $refLex";

while ($line = <REFLEX>) {
  chomp;
  if ($line =~ m:^([^\s]+)\s([^\s]+)\s(.+)$:) {
    $w = $1;
    $prob = $2;
    $pron = $3;
    push (@{$prons{$w}}, $pron);
  } else {
    die "$0: cannot parse $refLex\n";
  }
}

mkdir($outDir) unless (-d $dir);

open (G2PTRN, "> $outDir/hyp.trn") || die "Unable to open output trn file $outDir/hyp.trn";
open (REFTRN, "> $outDir/ref.trn") || die "Unable to open output trn file $outDir/ref.trn";

$count = 0;
while ($line = <G2PLEX>) {
  chomp;
  if ($line =~ m:^([^\s]+)\s([^\s]+)\s(.+)$:) {
    $w = $1;
    $prob = $2;
    $pron = $3;
    $uttid = "word_" . $count;
    print G2PTRN "$pron ($uttid)\n";
    if ($#{$prons{$w}} == 0){
      print REFTRN "$prons{$w}[0] ($uttid)\n";
    } elsif ($#{$prons{$w}} > 0) {
      print REFTRN "{ $prons{$w}[0]";
      for my $i (1..$#{$prons{$w}}) {
        print REFTRN " / $prons{$w}[$i]";
      }
      print REFTRN " } ($uttid)\n";
    } else {
      die "$0: no word $w found in refLex $refLex, please check. count $count\n";
    }
    $count += 1;
  } else {
    die "$0: cannot parse $g2pLex\n";
  }
}
