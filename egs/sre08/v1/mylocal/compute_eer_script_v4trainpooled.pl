#!/usr/bin/perl

require "getopt.pl";

use List::Util qw(first max maxstr min minstr reduce shuffle sum);

&Getopt('aesr');

$trainlabsfile = $opt_a;
$testlabsfile = $opt_e;
$scorematfile = $opt_s;
$resultsdir = $opt_r;

## CDET parameters ##
$cmiss = 1;
$cfalsealarm = 1;
$ptarget = 0.001;
#####################

print "$trainlabsfile\n";
print "$testlabsfile\n";
print "$scorematfile\n";
print "$resultsdir\n";

print `mkdir -p $resultsdir`;

print "Reading score matrix file\n";

@scoresmat = ();
$ii=0;
$jj=0;
open(IN, $scorematfile) || die "can't open $scorematfile\n";
while (<IN>) {
  chomp;
	@line = split(' ', $_);
	for ($jj=0;$jj<@line;$jj++) {
		$scoresmat[$ii][$jj] = @line[$jj];
	}
	$ii+=1;
}
close IN;

print "$ii by $jj mat read\n";

$maxtrain=$ii;
$maxtest=$jj;

@trainspkrs = ();
@testspkrs = ();
@testconvs = ();

print "Reading train labels file\n";

open(IN, $trainlabsfile) || die "can't open $trainlabsfile\n";
while (<IN>) {
  chomp;
	$trainspkr = $_;
	push(@trainspkrs,$trainspkr);

}
close IN;
print "Train labels read\n";

print "Reading test labels file\n";

open(IN, $testlabsfile) || die "can't open $testlabsfile\n";
while (<IN>) {
  chomp;
	@comps = split(' ',$_);
	if (@comps == 2) {
	  $testspkr = $comps[0];
	  $testconvspath = $comps[1];
	  @comps = split("/",$testconvspath);
	  $testconv = $comps[-1];

	  push(@testspkrs,$testspkr);
	  push(@testconvs,$testconv);
	}
	else {
	  print "WARNING: NULL test speaker conv for @comps\n";
	  push(@testspkrs, $comps[0]);
	  push(@testconvs,"NULL");
	}
}
close IN;
print "Test label read\n";

print "Outputting scorefile\n";

@truescores = ();
@impostorscores = ();
@truescoresid = ();
@impostorscoresid = ();

for ($ii=0;$ii<$maxtrain;$ii++) {
  for ($jj=0;$jj<$maxtest;$jj++) {

    $trainspkr = $trainspkrs[$ii];
    
    $testspkr = $testspkrs[$jj];
    $testconv = $testconvs[$jj];

    if ($testspkr ne "NULL") {
      $score = $scoresmat[$ii][$jj];

      if ("$trainspkr" eq "$testspkr") {
        push(@truescores,$score);
        push(@truescoresid,"$trainspkr $testconv");
      }
      else {
        push(@impostorscores,$score);
        push(@impostorscoresid,"$trainspkr $testconv");
      }
    }
    else {
      print "skipping test speaker (NULL)\n";
    }
  }
}

close IN;

print "Done\n";

$maxscore = 0;
$minscore = 0;

$maxtruescore = max @truescores;
$maximpscore = max @impostorscores;
$mintruescore = min @truescores;
$minimpscore = min @impostorscores;

#print "$maxtruescore  $maximpscore  $mintruescore  $minimpscore\n";

if ($maxtruescore >= $maximpscore) {
	$maxscore = $maxtruescore;
}
else {
	$maxscore = $maximpscore;
}

if ($mintruescore <= $minimpscore) {
	$minscore = $mintruescore;
}
else {
	$minscore = $minimpscore;
}

$eerthresh = $maxscore;

$prevmin=1000000;

for ($ii=0;$ii<@impostorscores;$ii++) {
  if (($impostorscores[$ii] < $prevmin) && ($impostorscores[$ii] != -100)) {
    $prevmin = $impostorscores[$ii];
  }
}

$prevmax = $maxscore;

$delta = 2;
$prevdelta = 3;
$prevprevdelta = 4;

$numtruescores = @truescores;
$numimpostorscores = @impostorscores;

print "numtruescores: $numtruescores\nnumimpostorscores: $numimpostorscores\n";

print "Computing EER\n";

while (1) {
 
  $prevprevdelta = $prevdelta;
  $prevdelta = $delta;

  $eerthresh = ($prevmax - $prevmin)/2 + $prevmin;
  
  $mi = 0;
  $fa = 0;
  for ($ii=0;$ii<@truescores;$ii++) {
    if ($truescores[$ii] < $eerthresh) {
      $mi += 1;
    }
  }

  $mip = $mi / $numtruescores;

  for ($ii=0;$ii<@impostorscores;$ii++) {
    if ($impostorscores[$ii] >= $eerthresh) {
      $fa += 1;
    }
  }

  $fap = $fa / $numimpostorscores;
  
  $delta = $mip - $fap;

  if (($delta == $prevdelta) || ($delta == $prevprevdelta)) {
    last;
  }
  
  if ($mip > $fap) {
    $prevmax = $eerthresh;
  }
  else {
    $prevmin = $eerthresh;
  }
  
}
  
$eer = ($fap + $mip)/2;

$mip = 1;
$fap = 0;

$scoreind = 0;

@impostorscoressorted = sort {$b <=> $a} @impostorscores;
@truescoressorted = sort {$b <=> $a} @truescores;

$fourpercentindex = 0.04 * $numimpostorscores;
$twoeightpercentindex = 0.028 * $numimpostorscores;
$onetenthpercentindex = 0.001 * $numimpostorscores;
$onehundredthpercentindex = 0.0001 * $numimpostorscores;

open(OUT, "> $resultsdir/extended_results.A.min");

print OUT "EER: $eer\n";

$threshind = int($fourpercentindex + 0.5);
$thresh = $impostorscoressorted[$threshind];

$mi = 0;
$fa = 0;
for ($ii=0;$ii<@truescores;$ii++) {
  if ($truescores[$ii] < $thresh) {
    $mi += 1;
  }
}
for ($ii = 0;$ii<@impostorscores;$ii++) {
  if ($impostorscores[$ii] >= $thresh) {
    $fa += 1;
  }
}

$mip = $mi / $numtruescores;
$fap = $fa / $numimpostorscores;

print OUT "Four percent FA: $fap  $mip\n";

$threshind = int($twoeightpercentindex + 0.5);
$thresh = $impostorscoressorted[$threshind];

$mi = 0;
$fa = 0;
for ($ii=0;$ii<@truescores;$ii++) {
  if ($truescores[$ii] < $thresh) {
    $mi += 1;
  }
}
for ($ii = 0;$ii<@impostorscores;$ii++) {
  if ($impostorscores[$ii] >= $thresh) {
    $fa += 1;
  }
}
  
$mip = $mi / $numtruescores;
$fap = $fa / $numimpostorscores;

print OUT "Two point Eight percent FA: $fap  $mip\n";

$threshind = int($onetenthpercentindex + 0.5);
$thresh = $impostorscoressorted[$threshind];

$mi = 0;
$fa = 0;
for ($ii=0;$ii<@truescores;$ii++) {
  if ($truescores[$ii] < $thresh) {
    $mi += 1;
  }
}
for ($ii = 0;$ii<@impostorscores;$ii++) {
  if ($impostorscores[$ii] >= $thresh) {
    $fa += 1;
  }
}
  
$mip = $mi / $numtruescores;
$fap = $fa / $numimpostorscores;

print OUT "One tenth percent FA: $fap  $mip\n";

$threshind = int($onehundredthpercentindex + 0.5);
$thresh = $impostorscoressorted[$threshind];

$mi = 0;
$fa = 0;
for ($ii=0;$ii<@truescores;$ii++) {
  if ($truescores[$ii] < $thresh) {
    $mi += 1;
  }
}
for ($ii = 0;$ii<@impostorscores;$ii++) {
  if ($impostorscores[$ii] >= $thresh) {
    $fa += 1;
  }
}
  
$mip = $mi / $numtruescores;
$fap = $fa / $numimpostorscores;

print OUT "One hundredth percent FA: $fap  $mip\n";

close OUT;


open(OUT, "> $resultsdir/true_speaker_scores.A");

for ($ii=0;$ii<$numtruescores;$ii++) {
  print OUT "$truescores[$ii]\n";
}

close OUT;

open(OUT, "> $resultsdir/impostor_scores.A");

for ($ii=0;$ii<$numimpostorscores;$ii++) {
  print OUT "$impostorscores[$ii]\n";
}

close OUT;
