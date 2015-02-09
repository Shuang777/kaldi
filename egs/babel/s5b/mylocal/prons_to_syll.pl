#!/usr/bin/perl -W

# koried, 2/12/2013

# Translate word/pronunciation symbol vectors into text ones;  ignores non-words (id: 0).
# Input will be in form of
# utt-id  word1 phn1 phn2 phn3 ; word2 phn1 phn2 phn3 ;

$print_word_delimiter = 0;
$posphone = "false";

while ($ARGV[0] =~ /^-/) {
  if ($ARGV[0] eq "-w") {
    shift @ARGV;
    $print_word_delimiter = 1;
  } elsif ($ARGV[0] eq "--posphone") {
    shift @ARGV;
    $posphone = shift @ARGV;
  }
}

if (scalar @ARGV != 3) {
  print STDERR "usage: $0 w2c_lex.txt words.txt phones.txt < in.tra.int > out.tra.txt\n";
  exit 1;
}

$w2clex = shift @ARGV;
open (F, "<$w2clex") || die "Error opening word to syll lex";
while (<F>) {
  chomp;
  @A = split /\s+/;
  $w = shift @A;
  $prob = shift @A;
  $p = join(" ", @A);
  $pflat = $p; $pflat =~ s/=/ /g;
  $wordpron2syl{"$w $pflat"} = $p;
}

$symtab1 = shift @ARGV;
open(F, "<$symtab1") || die "Error opening symbol table file $symtab1";
while(<F>) {
  @A = split(" ", $_);
  @A == 2 || die "bad line in symbol table file: $_";
  $int2sym1{$A[1]} = $A[0];
}

sub int2sym1 {
  my $a = shift @_;
  my $pos = shift @_;
  if($a !~  m:^\d+$:) { # not all digits..
    $pos1 = $pos+1; # make it one-based.
    die "int2sym.pl: found noninteger token $a [in position $pos1]\n";
  }
  $s = $int2sym1{$a};
  if(!defined ($s)) {
    die "int2sym.pl: integer $a not in symbol table $symtab1.";
  }
  return $s;
}

$symtab2 = shift @ARGV;
open(F, "<$symtab2") || die "Error opening symbol table file $symtab2";
while(<F>) {
  @A = split(" ", $_);
  @A == 2 || die "bad line in symbol table file: $_";
  $int2sym2{$A[1]} = $A[0];
}

sub int2sym2 {
  my $a = shift @_;
  my $pos = shift @_;
  if($a !~  m:^\d+$:) { # not all digits..
    $pos1 = $pos+1; # make it one-based.
    die "int2sym.pl: found noninteger token $a [in position $pos1]\n";
  }
  $s = $int2sym2{$a};
  if(!defined ($s)) {
    die "int2sym.pl: integer $a not in symbol table $symtab2.";
  }
  return $s;
}

sub trim {
  $a = shift @_;
  $a =~ s/^\s+//;
  $a =~ s/\s+$//;
  return $a;
}

while (<>) {
  chomp;

  # insert ';' after utt-id
  s/ / ; /;
  @A = split /;/;
  $utt = trim(shift @A);

  print "$utt ";

  if (scalar @A == 0) {
    print "\n";
    next;
  }

  for ($i = 0; $i < @A; $i++) {
    $w = trim($A[$i]);
    next if (length $w == 0 or $w =~ m/^0 /);
    
    @B = split (/ /, $w);
    $w = int2sym1(shift @B);

    next if $w =~ m/^\[/;

    for ($j = 0; $j < @B; $j++) {
      $B[$j] = int2sym2($B[$j], $i);
      if ($posphone eq "true") {
        $B[$j] =~ s/_[^_]+$//;
      }
    }
    $p = join(" ", @B);

    $hash = "$w $p";
    if (defined $wordpron2syl{$hash}) {
      print " ".$wordpron2syl{"$hash"};
    } else {
      print " <unk>";
    }

    print " ;" if ($print_word_delimiter == 1 and $i < @A - 1);
  }
  print "\n";

}

