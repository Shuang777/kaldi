#!/usr/bin/perl -w


if (@ARGV != 3) {
  die "Usage: $0 <nj> <data-dir> <seg-dir>"
}

$nj = $ARGV[0];
$data = $ARGV[1];
$segdir = $ARGV[2];

for my $i (1..$nj) {
  my %utts = ();
  open(FEATF, "$data/split$nj/$i/feats.scp") || die "Unable to open input $data/split$nj/$i/feats.scp";
  while(<FEATF>) {
    my @A = split(/\s+/, $_);
    $utts{$A[0]} = 1;
  }
  my @matched = ();
  for my $j (1..$nj) {
    open(SEGF, "$segdir/split$nj/$j/wav.scp") || die "Unable to open input $segdir/split$nj/$j/wav.scp";
    while(<SEGF>) {
      my @A = split(/\s+/, $_);
      if (exists $utts{$A[0]}) {
        push @matched, $j;
        last;
      }
    }
  }
  foreach $i (@matched) {
    print "$i ";
  }
  print "\n";
  close(FEATF);
}
