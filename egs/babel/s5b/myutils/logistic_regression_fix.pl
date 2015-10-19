#!/usr/bin/perl -w

$num_hid_layers = $ARGV[0];
$init_file = $ARGV[1];

open (INIT_F, "<$init_file") || die "Cannot open input file $init_file!";
open (OUT_F, ">$init_file.fix") || die "Cannot open output file $init_file.fix";

$count = 0;
while (<INIT_F>) {
  if ($_ =~ /AffineTransform/) {
    if ($count == $num_hid_layers) {
      $_ =~ s/AffineTransform/LogisticAffine/;
    } else {
      $count += 1;
    }
  }
  print OUT_F $_;
}
close(INIT_F);
close(OUT_F);

system("mv $init_file.fix $init_file");
