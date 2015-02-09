#!/usr/bin/perl -w

if (@ARGV != 3) {
  die "Usage: $0 keywords.txt trans.txt align.txt\n";
}

$keywordFile = $ARGV[0];
$transFile = $ARGV[1];
$alignsFile = $ARGV[2];

open (INKEYWORDS, $keywordFile) || die "Unable to open input keyword file $keywordFile";

%keywords = ();
%keyword2Id = ();
while ($line = <INKEYWORDS>) {
  $line =~ /^([^\d]+)\s+(\d+)$/g;
  $keyword = $1;
  $id = $2;
  $keyword =~ s/^\s+//;
  $keyword =~ s/\s+$//;
  $keywords{$keyword} = $keyword =~ s/((^|\s)\S)/$1/g;
  $keyword2Id{$keyword} = $id;
}

open (INTRANS, $transFile) || die "Unable to open input translation file $transFile";
open (INALIGNS, $alignsFile) || die "Unable to open input alignment file $alignsFile";

#for my $key (keys %keywords) {
#  print "$key $keywords{$key}\n";
#}

while ($line = <INTRANS>) {
  $line =~ m/^(\S+)\s+(.+)$/g;
  $utt = $1;
  $txt = " " . $2 . " ";    # we need space as keyword boundary
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
    if ($_ =~ /_[BS]/) {
      $wordPos2Phone{$countWords} = $countPhones;
    }
    if ($_ =~ /_[ES]/) {
      $wordPos2PhoneEnd{$countWords} = $countPhones;
      $countWords += 1;
    }
    $countPhones += 1;
  }
#  for my $key (keys %wordPos2Phone) {
#    print "$key $wordPos2Phone{$key} $wordPos2PhoneEnd{$key}\n";
#  }
  for my $key (keys %keywords) {    # loop over keywords
    my @occs = ();
    $index = 0;
    $keyWithSpace = " " . $key . " ";
    while ($index != -1) {          # loop over observations of keywords
      $index = index($txt, $keyWithSpace, $index);
      if ($index != -1) {
        $posWords = (substr($txt, 0, $index+1) =~ tr/ //)-1; # omit the first space
        push @occs, $posWords;
        $index += 1;
      }
    }
    # find alingments for those keywords
    foreach (@occs) {
      $startPhonePos = $wordPos2Phone{$_};
      $endPhonePos = $wordPos2PhoneEnd{$_+$keywords{$key}-1};
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
      #print "$utt $key $startStatePos $endStatePos\n";
      if (substr($phoneLine, $startStatePos, $endStatePos-$startStatePos) =~ /sil/) {   # we don't want sil in this short keyword
        next;
      }
      $startStateIndex = (substr($alignLine, 0, $startStatePos) =~ s/ (\d+)/ $1/g);
      if ($startStateIndex eq "") {
        $startStateIndex = 0;
      }
      $stateLength = (substr($alignLine, $startStatePos, $endStatePos-$startStatePos) =~ s/ (\d+)/ $1/g);
      print "$utt $keyword2Id{$key} $startStateIndex $stateLength\n";
    }
  }
}
