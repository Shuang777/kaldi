#!/usr/bin/perl -w

# This script converts a segment file to vad.ark file

$segFile = $ARGV[0];
$frameRate = 10;    # 10 ms per frame

while ($line = <STDIN>) {
  @arr = split(/\s+/, $line);
  $chn = $arr[0];
  $frame = $arr[1];
  $chn2frames{$chn} = $frame;
}

open(SEGF, $segFile) || die "Unable to open input segment file $segFile";

$lastChn = "";
while ($line = <SEGF>) {
  @arr = split(/\s+/, $line);
  $chn = $arr[1];
  $start = $arr[2];
  $end = $arr[3];
  if ($chn ne $lastChn) {
    if ($lastChn ne "") {
      while ($t < $chn2frames{$lastChn}) {
        print "0 ";
        $t++;
      }
      print "]\n";
    }
    print "$chn  [ ";
    $t = 0;
  }
  if (not exists $chn2frames{$chn}) {
    next;
  }
  $startFrame = $start * 1000 / $frameRate;
  $endFrame = $end * 1000 / $frameRate;
  while( $t < $startFrame and $t < $chn2frames{$chn}) {
    print "0 ";
    $t++;
  }
  while ( $t <= $endFrame and $t < $chn2frames{$chn}) {
    print "1 ";
    $t++;
  }
  $lastChn = $chn;
}

# last bracket
while ($t < $chn2frames{$lastChn}) {
  print "0 ";
  $t++;
}

print "]\n";
