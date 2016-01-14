#!/usr/bin/perl -w
use List::Util qw(shuffle);

$spkDiff = "";

if ($ARGV[0] eq "--spkdiff") {
  shift @ARGV;
  $spkDiff = shift @ARGV;
}

if ($#ARGV == 1) {
  $spk2utt = $ARGV[0];
  $dir = $ARGV[1];
  $spk2utt2 = "";
} elsif ($#ARGV == 2) {
  $spk2utt = $ARGV[0];
  $spk2utt2 = $ARGV[1];
  $trial = $ARGV[2];
} else {
  print STDERR ("Usage: $0 spk2utt dir\n");
  exit(1);
}

open(SPK2UTT, $spk2utt) || die "Unable to open input spk2utt $spk2utt";

if ($spk2utt2 ne "") {
  open(SPK2UTT2, $spk2utt2) || die "Unable to open input spk2utt $spk2utt2";
}

while($line = <SPK2UTT>) {
  $line =~ s/\s+$//;
  @info = split(/\s+/, $line);
  $spk = shift @info;
  push @spks, $spk;
  push @utts_all, [ @info ];
}

if ($spk2utt2 ne "") {
  $count=0;
  while($line = <SPK2UTT2>) {
    $line =~ s/\s+$//;
    @info = split(/\s+/, $line);
    $spk = shift @info;
    $spk2hash{$spk} = $count;
    $count += 1;
    push @utts2_all, [ @info ];
  }
}

if ($spk2utt2 eq "") {
  open(SAMEF, "> $dir/trials.same") || die "Unable to open output trials $dir/trials.same\n";
  open(DIFFF, "> $dir/trials.diff") || die "Unable to open output trials $dir/trials.diff\n";

  for my $row (0..$#utts_all) {
    $utts = $utts_all[$row];
    for my $i (0..$#{$utts}) {
      for my $j (($i+1)..$#{$utts}) {
        printf SAMEF "%s %s\n", $utts->[$i], $utts->[$j];
      }
    }
  }

  for my $row (0..$#utts_all) {
    $utts = $utts_all[$row];
    for my $row2 (($row+1)..$#utts_all) {
      $utts2 = $utts_all[$row2];
      for my $i (0..$#{$utts}) {
        for my $j (0..$#{$utts2}) {
          printf DIFFF "%s %s\n", $utts->[$i], $utts2->[$j];
        }
      }
    }
  }

} else {
  open(CROSSF, "> $trial") || die "Unable to open output trial $trial\n";
  for my $row (0..$#utts_all) {
    $utts = $utts_all[$row];
    $spk = $spks[$row] . $spkDiff;
    $row2 = $spk2hash{$spk};
    $utts2 = $utts2_all[$row2];
    for my $i (0..$#{$utts}) {
      for my $j (0..$#{$utts2}) {
        printf CROSSF "%s %s\n", $utts->[$i], $utts2->[$j];
      }
    }
  }
}
