#!/usr/bin/perl

# Copyright 2014  International Computer Science Institute (Hang Su)

# Remove the epsilons in Kaldi Lattices

use utf8;
use List::Util qw(max);

binmode(STDIN, ":encoding(utf8)");
binmode(STDOUT, ":encoding(utf8)");

# defaults
$eps = '<eps>';

$usage="Remove the epsilons in Kaldi Lattices\n".
       "Usage: $0 [options] lat-file-in.txt lat-file-out.txt\n".
       "  e.g. lattice-align-words lang/phones/word_boundary.int final.mdl 'ark:gunzip -c lat.gz |' ark,t:- | utils/int2sym.pl -f 3 lang/words.txt | $0 - \n".
       "\n";

# parse options
while (@ARGV gt 0 and $ARGV[0] =~ m/^--/) {
  $param = shift @ARGV;
  if ($param eq "--eps") { $eps = shift @ARGV; }
  else {
    print STDERR "Unknown option $param\n";
    print STDERR;
    print STDERR $usage;
    exit 1;
  }
}

# check positional arg count
if (@ARGV < 1 || @ARGV > 2) {
  print STDERR $usage;
  exit 1;
}

# store gzipped lattices individually to outdir:
if (@ARGV == 2) {
  $outfile = pop @ARGV;
  open(FH, $outfile) or die "Could not open file $outfile\n";
} else {    # print to stdout
  open(FH, ">-") or die "Could not write to stdout (???)\n";
}

### parse kaldi lattices:

open (FI, $ARGV[0]) or die "Could not read from file\n";
binmode(FI, ":encoding(utf8)");

%nodes = ();  # map old nodes to new nodes, and preserve time
%cacheinfo = ();  # cached eps weights
$utt = "";

while(<FI>) {
  chomp;

  @A = split /\s+/;

  if (@A == 1 and $utt eq "") {
    # new lattice
    $utt = $A[0];
    $nodes{0} = {s=>0}; # initial node
    printf FH "%s \n", $utt;
  } elsif (@A == 1) {
    # accepting state
    $s = $A[0];
    defined $nodes{$s} or die "accepting state $s not visited before";
    $ms = $nodes{$s}{s};    # mapped state
    if (defined $cacheinfo{$s}) {
      $gs = $cacheinfo{$s}{gs};
      $as = $cacheinfo{$s}{as};
      $ss = $cacheinfo{$s}{ss};
      printf FH "%d %s,%s,%s \n", $ms, $gs, $as, $ss;
    } else {
      printf FH "%d \n", $ms;
    }
  } elsif (@A == 2) {
    # accepting state with FST weight on it, again store data for the link
    ($s, $info) = @A;
    ($gs, $as, $ss) = split(/,/, $info);

    defined $nodes{$s} or die "accepting state $s not visited before";
    $ms = $nodes{$s}{s};
    
    if (defined $cacheinfo{$s}) {
      $gs += $cacheinfo{$s}{gs};
      $as += $cacheinfo{$s}{as};
      $ss = "_" . $ss unless $ss eq "";
      $ss = $cacheinfo{$s}{ss} . $ss;
      printf FH "%d %s,%s,%s \n", $ms, $gs, $as, $ss;
    } else {
      printf FH "%d %d \n", $ms, $info;
    }
  } elsif (@A == 4 or @A == 3) {
    # FST arc
    ($s, $e, $w, $info) = @A;
    if ($info ne "") {
      ($gs, $as, $ss) = split(/,/, $info);
    } else {
      $gs = 0; $as = 0;
      $ss = '';
    }
    $ms = $nodes{$s}{s};

    # the state sequence is something like 1_2_4_56_45, get number of tokens after splitting by '_':
    if ($w eq $eps) {
      if (defined $cacheinfo{$s}) {
        $gs += $cacheinfo{$s}{gs};
        $as += $cacheinfo{$s}{as};
        $ss = "_" . $ss unless $ss eq "";
        $ss = $cacheinfo{$s}{ss} . $ss;
      }
      $nodes{$e} = {s=>$nodes{$s}{s}};
      $cacheinfo{$e} = {gs=>$gs,as=>$as,ss=>$ss};
    } else {
      if (defined $cacheinfo{$s}) {
        $gs += $cacheinfo{$s}{gs};
        $as += $cacheinfo{$s}{as}; 
        $ss = "_" . $ss unless $ss eq "";
        $ss = $cacheinfo{$s}{ss} . $ss;
      }
      $nodes{$e} = {s=>$e};
      printf FH "%d %d %s %s,%s,%s \n", $ms, $e, $w, $gs, $as, $ss;
    }
  } elsif (@A == 0) { # end of lattice reading
    print FH "\n";
    # clear data
    $utt = "";
    %nodes = ();
    %cacheinfo = ();
  } else {
    die "Unexpected column number of input line\n$_";
  }
}

if ($utt != "") {
  print STDERR "Last lattice was not printed as it might be incomplete?  Missing empty line?\n";
}

