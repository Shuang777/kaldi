#!/usr/bin/perl

# Copyright 2014 International Computer Science Institute (Author: Hang Su)

# Convert alignment in kaldi-lattice to end time; for syllable composition use

$utt = "";

while(<STDIN>) {
  chomp;
  @A = split /\s+/;

  if (@A == 1 and $utt eq ""){
    $utt = $A[0];
    print "$utt\n";
  } elsif (@A == 1) { # accepting node without FST weight
    print "$A[0]\n";
  } elsif (@A == 2) { # accepting node with FST weight, process the frames
    ($s, $info) = @A;
    ($gs, $as, $ss) = split(/,/, $info);

    print "$s\t$gs,$as,$ss\n";
  } elsif (@A == 4 or @A == 3) {
    # FSA arc
    ($s, $e, $out, $info) = @A;
    if ($info ne "") {
      ($gs, $as, $ss) = split(/,/, $info);
    } else {
      $gs = 0; $as = 0; $ss = "";
    }

    $ss =~ s/([^_]+)/$out/g;
    
    print "$s\t$e\t$out\t$gs,$as,$ss\n";
  } elsif (@A == 0) { # end of lattice reading
    print "\n";

    # clear data
    $utt = "";
  } else {
    die "Unexpected column number of input line\n$_";
  }
}
