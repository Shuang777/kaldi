#!/usr/bin/perl
use Getopt::Long;

print $0 . " ". (join " ", @ARGV) . "\n";

# Copyright 2014  International Computer Science Institute (author Hang Su)

GetOptions("romanized!" => \$romanized);

if ($#ARGV == 2) {
  $g2pLex = $ARGV[0];
  $refLex = $ARGV[1];
  $outDir = $ARGV[2];
} else {
  print STDERR ("Usage: $0 g2pLex realLex outDir\n");
  print STDERR (" e.g.: $0 oov_lex.txt lexiconp.wrd2syl.txt exp/gen_oov_lex\n");
  exit(1);
}

open (G2PLEX, $g2pLex) || die "Unable to open input g2pLex $g2pLex";
open (REFLEX, $refLex) || die "Unable to open input refLex $refLex";

while ($line = <REFLEX>) {
  chomp;
  if ( ($romanized && ($line =~ m:^([^\t]+)\t\S+((\t[^\t]+)+)$:)) ||
       ((!$romanized) && ($line =~ m:^([^\t]+)((\t[^\t]+)+)$:)) ) {
    $word  = $1;
    $prons = $2;
    $prons =~ s:^\s+::;           # Remove leading white-space
    $prons =~ s:\s+$::;           # Remove trailing white-space
    @pron  = split("\t", $prons);
    for ($p=0; $p<=$#pron; ++$p) {
      $new_pron = "";
      while ($pron[$p] =~ s:^([^\.\#]+)[\.\#]{0,1}::) { push (@syllables, $1); }
      while ($syllable = shift @syllables) {
        $syllable =~ s:^\s+::;
        $syllable =~ s:\s+$::;
        $syllable =~ s:\s+: :g;
        @original_phones = split(" ", $syllable);

        $new_phones = "";
        while ($phone = shift @original_phones) {
          if ($phone =~ m:^\_\S+:) {
            # It is a tag; save it for later
            $is_original_tag{$phone} = 1;
            $sylTag .= $phone;
          } elsif ($phone =~ m:^[\"\%]$:) {
            # It is a stress marker; save it like a tag
            $phone = "_$phone";
            $is_original_tag{$phone} = 1;
            $sylTag .= $phone;
          } else {
            # It is a phone
            $new_phones .= " $phone";
          }
        }
#        $new_pron .= $new_phones . " .";
        $new_pron .= $new_phones;
      }
      $new_pron =~ s: \.$::;
      $new_pron =~ s:^ ::;
      $new_pron =~ s:\{:brk:g;
      push (@{$totalprons{$word}}, $new_pron);
#      print("$word $new_pron\n");
    }
  } else {
    die "$0: cannot parse $refLex\n";
  }
}

mkdir($outDir) unless (-d $dir);

open (G2PTRN, "> $outDir/hyp.trn") || die "Unable to open output trn file $outDir/hyp.trn";
open (REFTRN, "> $outDir/ref.trn") || die "Unable to open output trn file $outDir/ref.trn";

$count = 0;
while ($line = <G2PLEX>) {
  chomp;
  if ($line =~ m:^([^\s]+)\t(.+)$:) {
    $w = $1;
    $pron = $2;
    $pron =~ s: \.::g;
    $pron =~ s:\{:brk:g;
    $uttid = "word_" . $count;
    print G2PTRN "$pron ($uttid)\n";
    if ($#{$totalprons{$w}} >= 0) {
      print REFTRN "{ $totalprons{$w}[0]";
      for my $i (1..$#{$totalprons{$w}}) {
        print REFTRN " / $totalprons{$w}[$i]";
      }
      print REFTRN " } ($uttid)\n";
    } else {
      die "$0: no word $w found in refLex $refLex, please check. count $count\n";
    }
    $count += 1;
  } else {
    die "$0: cannot parse $g2pLex\n";
  }
}
