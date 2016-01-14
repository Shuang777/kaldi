#!/usr/bin/perl -w

$ori_utt2spk = $ARGV[0];
$segment = $ARGV[1];

open (UTT2SPK, $ori_utt2spk) || die "Unable to open input utt2spk file $ori_utt2spk";
open (SEGMENT, $segment) || die "Unable to open input segment file $segment";

%utt2spk = ();

while ($line = <UTT2SPK>) {
  @A = split(/\s/, $line);
  $utt = shift @A;
  $spk = shift @A;
  $utt2spk{$utt} = $spk;
}

while ($line = <SEGMENT>) {
  @A = split(/\s/, $line);
  $new_utt = shift @A;
  $old_utt = shift @A;
  print "$new_utt $utt2spk{$old_utt}\n";
}
