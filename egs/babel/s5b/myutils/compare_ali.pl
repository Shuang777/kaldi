#!/usr/bin/perl -w

if (@ARGV != 2) {
  die "Usage: $0 <ali-dir-1> <ali-dir-2>\n";
}

$align1FileDir = $ARGV[0];
$align2FileDir = $ARGV[1];

open (INALIGN1, "copy-int-vector 'ark:gunzip -c $align1FileDir/ali.*.gz |' ark,t:- | sort |") || die "Unable to open input ali.*.gz files in $align1FileDir";
open (INALIGN2, "copy-int-vector 'ark:gunzip -c $align2FileDir/ali.*.gz |' ark,t:- | sort |") || die "Unable to open input ali.*.gz files in $align2FileDir";

$line1 = <INALIGN1>;
$line2 = <INALIGN2>;

$count = 0;
$countequal = 0;

while (defined $line1 and defined $line2) {
  $line1copy = $line1;
  $line2copy = $line2;

  $line1copy =~ m/^(\S+) (.+)/g;
  $utt1 = $1;
  $alignments1 = $2;
  
  $line2copy =~ m/^(\S+) (.+)/g;
  $utt2 = $1;
  $alignments2 = $2;
  
  $utt1 =~ m/^(\S+)_([0-9]*)_([0-9]*)/;
  $chn1 = $1;
  $s1 = $2;
  $e1 = $3;
  
  $utt2 =~ m/^(\S+)_([0-9]*)_([0-9]*)/;
  $chn2 = $1;
  $s2 = $2;
  $e2 = $3;


  if ($chn1 lt $chn2) {
    $line1 = <INALIGN1>;
    next;
  } elsif ($chn1 gt $chn2) {
    $line2 = <INALIGN2>;
    next;
  } else {
    if ($e1 < $s2) {
      $line1 = <INALIGN1>;
      next;
    } elsif ($s1 > $e2) {
      $line2 = <INALIGN2>;
      next;
    } else {
      @alignids1 = split(/\s+/, $alignments1);
      @alignids2 = split(/\s+/, $alignments2);
      $i = 0;
      if ($s1 < $s2) {
        $i = $s2 - $s1;
      }
      while ($i < @alignids1 and ($i+$s1-$s2) < @alignids2) {
        if ($alignids1[$i] == $alignids2[$i+$s1-$s2]) {
          $countequal += 1;
        }
        $count += 1;
        $i += 1;
      }
      if ($i < @alignids1) {
        $line2 = <INALIGN2>;
        next;
      } else {
        $line1 = <INALIGN1>;
        next;
      }
    }
  }
}

printf "%d %d %f%%\n", $count, $countequal, 100 * $countequal / $count;
