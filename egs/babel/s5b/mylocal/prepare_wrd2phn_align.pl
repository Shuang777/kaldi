#!/usr/bin/perl -W
use lib '/u/suhang/local/perl5/site_perl/5.8.9';
use Set::CrossProduct;

# suhang, 4/15/2013
sub trim {
  $a = shift @_;
  $a =~ s/^\s+//;
  $a =~ s/\s+$//;
  return $a;
}

if (@ARGV != 1) {
  die "Usage: prepare_wrd2phn_align.pl syl2phn_lexicon [wrd2syl_lexicon] > [wrd2phn_lexicon]";
}

$syl2phnlex = shift @ARGV;
%syl2phn = ();
open (F, "<$syl2phnlex") || die "Could not open syl2phn lexicon file $syl2phnlex";
while(<F>) {
  @A = split(/\s/, $_);
  $syl = shift @A;
  shift @A; # probability
  $pron = trim(join(' ',@A));
  push(@{$syl2phn{$syl}}, $pron);
}

while (<>) {
  chomp;
  @A = split(/\s+/, $_);
  $wrd = trim(shift @A);
  shift @A; # probability
  @toprint=();
  for ($i = 0; $i < @A; $i++) {
    $w = trim($A[$i]);
    if (defined $syl2phn{$w}) {
      push(@toprint, \@{$syl2phn{$w}});
    } else {
      push(@toprint, ["<unk>"]);
    }
  }
  if ($#toprint == 0) {
      foreach (@{$toprint[0]}) {
          print "$wrd $_" . "\n";
      }
  } else {
      $iter = Set::CrossProduct->new(\@toprint);
      foreach($iter->combinations){
        print "$wrd";
        for $p (0 .. $#toprint) {
            print " ",$_->[$p];
        }
        print "\n";
      }
  }
}
