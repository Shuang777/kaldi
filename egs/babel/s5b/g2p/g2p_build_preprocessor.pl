#!/usr/bin/perl

# take a symbol file from a "cleaned" alignment
# allow insertions of unpronouncable symbols



%unpronouncible=("_"=>1,
		 "-"=>1,
		 "'"=>1);

open(ISYMS,$ARGV[0]);
open(OSYMS,">$ARGV[1]");
open(MAPFST,">$ARGV[2]");

while(<ISYMS>) {
  print OSYMS $_;
  chomp;
  ($sym,$num)=split;

  if (defined($unprouncible{$sym})) {
    undef($unpronuncible{$sym});
  }
  if ($num == 0) {
    $eps=$sym;
  } else {
    print MAPFST "0 0 $sym $sym\n";
  }
}

foreach $u (keys %unpronouncible) {
  $num++;
  print OSYMS "$u\t$num\n";
  print MAPFST "0 0 $u $eps\n";
}

print MAPFST "0\n";

close(ISYMS);
close(OSYMS);
close(MAPFST);
