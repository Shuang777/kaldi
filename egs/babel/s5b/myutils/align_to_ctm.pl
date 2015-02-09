#!/usr/bin/perl -w

if (@ARGV != 2) {
  die "Usage: $0 trans.txt align.txt\n";
}

$transFile = $ARGV[0];
$alignsFile = $ARGV[1];

open (INTRANS, $transFile) || die "Unable to open input translation file $transFile";
open (INALIGNS, $alignsFile) || die "Unable to open input alignment file $alignsFile";

while ($line = <INTRANS>) {
  $line =~ m/^(\S+)\s+(.+)$/g;
  $utt = $1;
  $txt = $2;    # we need space as keyword boundary
  if (eof(INALIGNS)) { last; }
  $alignLine = <INALIGNS>;
  $phoneLine = <INALIGNS>;
  $emptyLine = <INALIGNS>;
  $phoneLine =~ m/^(\S+)\s+(.+)$/;
  $uttAlign = $1;
  $phoneSeq = $2;
  while ($utt ne $uttAlign) {     # some utts are not aligned, so we just obselete them.
    $line = <INTRANS>;
    $line =~ m/^(\S+)\s+(.+)$/g;
    $utt = $1;
    $txt = $2;
  }
  @phones = split(/\s+/,$phoneSeq);
  %wordPos2Phone = ();
  %wordPos2PhoneEnd = ();
  $countWords = 0;
  $countPhones = 0;
  foreach (@phones) {
    if ($_ =~ /_[BS]/ and $_ !~ /SIL/ and $_ !~ /sil/) {
      $wordPos2Phone{$countWords} = $countPhones;
    }
    if ($_ =~ /_[ES]/ and $_ !~ /SIL/ and $_ !~ /sil/) {
      $wordPos2PhoneEnd{$countWords} = $countPhones;
      $countWords += 1;
    }
    $countPhones += 1;
  }
  #foreach (keys %wordPos2Phone) {
  #  print "$_ $wordPos2Phone{$_}\n";
  #}
  $txt =~ s/^\s+//;
  $txt =~ s/\s+$//;
  @words = split(/\s+/,$txt);
  $countWords = 0;
  foreach (@words) {
    if ($_ =~ /silence/) { next; }
    $startPhonePos = $wordPos2Phone{$countWords};
    $endPhonePos = $wordPos2PhoneEnd{$countWords};
    $index = 0;
    $countFind = 0;
    while ($countFind <= $startPhonePos) {
      $index = index($alignLine, '[', $index);
      if ($index != -1) {
        $index += 1;
        $countFind += 1;
      } else {
        die "shall not get here: number of [ shall be bigger than startPhonePos\n";
      }
    }
    $startStatePos = $index;
    while ($countFind <= $endPhonePos+1) {    # have additional ] here
      $index = index($alignLine, ']', $index);
      if ($index != -1) {
        $index += 1;
        $countFind += 1;
      } else {
        die "shall not get here: number of ] shall be bigger than endPhonePos\n";
      }
    }
    $endStatePos = $index;
    #print "$utt $_ $startStatePos $endStatePos\n";
    $startStateIndex = (substr($alignLine, 0, $startStatePos) =~ s/ (\d+)/ $1/g);
    if ($startStateIndex eq "") {
      $startStateIndex = 0;
    }
    $stateLength = (substr($alignLine, $startStatePos, $endStatePos-$startStatePos) =~ s/ (\d+)/ $1/g);
    print "$utt $_ $startStateIndex $stateLength\n";
    $countWords += 1;
  }
}
