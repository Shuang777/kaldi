#!/usr/bin/perl -W

# suhang, 4/15/2013
sub trim {
  $a = shift @_;
  $a =~ s/^\s+//;
  $a =~ s/\s+$//;
  return $a;
}

if (@ARGV != 1) {
  die "Usage: wrd2syl.pl wrd2syl_lexicon [in.txt] > out.txt";
}

$wrd2syllex = shift @ARGV;
%wrd2syl = ();
open (F, "<$wrd2syllex") || die "Could not open wrd2syl lexicon file $wrd2syllex";
while(<F>) {
  @A = split(/\t/, $_);
  $wrd = shift @A;
  shift @A;     # probility term
  $pron = trim(join(' ',@A));
  push(@{$wrd2syl{$wrd}}, $pron);
}

#for $wrd ( keys %wrd2syl ) {
#  print $wrd;
#  foreach (@{$wrd2syl{$wrd}}) {
#    print "\t$_";
#  }
#  print "\n";
#}

while (<>) {
  chomp;
  @A = split(/\s+/, $_);
  $utt = trim(shift @A);
  print "$utt";

  for ($i = 0; $i < @A; $i++) {
    $w = trim($A[$i]);
    if (defined $wrd2syl{$w}) {
      $pron = shift @{$wrd2syl{$w}};
      push(@{$wrd2syl{$w}}, $pron);
      print " $pron";
    } else {
      print " <unk>";
    }
  }
  print "\n";
}
