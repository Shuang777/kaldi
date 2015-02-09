#!/usr/bin/env perl

# Copyright 2012  Johns Hopkins University (Author: Guoguo Chen)
# Copyright 2014  The Ohio State University (Author: Yanzhang He)
# Apache 2.0.
#
use strict;
use warnings;
use Getopt::Long;

my $Usage = <<EOU;
This script reads the raw keyword search results [result.*] and writes them as the kwslist.xml file.
It can also do things like score normalization, decision making, duplicates removal, etc.

Usage: $0 [options] <raw_result_in|-> <kwslist_out|->
 e.g.: $0 --flen=0.01 --duration=1000 --segments=data/eval/segments
                              --normalize=true --map-utter=data/kws/utter_map raw_results kwslist.xml

Allowed options:
  --beta                      : Beta value when computing ATWV              (float,   default = 999.9)
  --digits                    : How many digits should the score use        (int,     default = "infinite")
  --duptime                   : Tolerance for duplicates                    (float,   default = 0.5)
  --duration                  : Duration of all audio, you must set this    (float,   default = 999.9)
  --ecf-filename              : ECF file name                               (string,  default = "") 
  --flen                      : Frame length                                (float,   default = 0.01)
  --index-size                : Size of index                               (float,   default = 0)
  --kwlist-filename           : Kwlist.xml file name                        (string,  default = "") 
  --language                  : Language type                               (string,  default = "cantonese")
  --map-utter                 : Map utterance for evaluation                (string,  default = "")
  --normalize                 : Normalize scores or not                     (boolean, default = false)
  --Ntrue-scale               : Keyword independent scale factor for Ntrue  (float,   default = 1.0)
  --empirical                 : Use empirical thresholding (with fraction)  (boolean, default = false)
  --fraction                  : The fraction for the empirical thresholding (float,   default = 0.1, between 0 and 1)
  --final-thresh              : The threshold on the final output score     (float,   default = 9999, not being used)
  --remove-dup                : Remove duplicates                           (boolean, default = false)
  --remove-NO                 : Remove the "NO" decision instances          (boolean, default = false)
  --segments                  : Segments file from Kaldi                    (string,  default = "")
  --system-id                 : System ID                                   (string,  default = "")
  --verbose                   : Verbose level (higher --> more kws section) (integer, default 0)
  --YES-cutoff                : Only keep "\$YES-cutoff" yeses for each kw  (int,     default = -1)
  --oov-count-file            : File with OOV word count for each keyword   (string,  default = "")

EOU

my $segment = "";
my $flen = 0.01;
my $beta = 999.9;
my $duration = 999.9;
my $language = "cantonese";
my $ecf_filename = "";
my $index_size = 0;
my $system_id = "";
my $normalize = "false";
my $map_utter = "";
my $Ntrue_scale = 1.0;
my $empirical = "false";
my $fraction = 0.1;
my $final_thresh = 9999;
my $digits = 0;
my $kwlist_filename = "";
my $verbose = 0;
my $duptime = 0.5;
my $remove_dup = "false";
my $remove_NO = "false";
my $YES_cutoff = -1;
my $oov_count_file = "";
GetOptions('segments=s'     => \$segment,
  'flen=f'         => \$flen,
  'beta=f'         => \$beta,
  'duration=f'     => \$duration,
  'language=s'     => \$language,
  'ecf-filename=s' => \$ecf_filename,
  'index-size=f'   => \$index_size,
  'system-id=s'    => \$system_id,
  'normalize=s'    => \$normalize,
  'map-utter=s'    => \$map_utter,
  'Ntrue-scale=f'  => \$Ntrue_scale,
  'empirical=s'  => \$empirical,
  'fraction=f'  => \$fraction,
  'final-thresh=f'  => \$final_thresh,
  'digits=i'       => \$digits,
  'kwlist-filename=s' => \$kwlist_filename,
  'verbose=i'         => \$verbose,
  'duptime=f'         => \$duptime,
  'remove-dup=s'      => \$remove_dup,
  'YES-cutoff=i'      => \$YES_cutoff,
  'remove-NO=s'       => \$remove_NO,
  'oov-count-file=s'  => \$oov_count_file);

($normalize eq "true" || $normalize eq "false") || die "$0: Bad value for option --normalize\n";
($empirical eq "true" || $empirical eq "false") || die "$0: Bad value for option --empirical\n";
($remove_dup eq "true" || $remove_dup eq "false") || die "$0: Bad value for option --remove-dup\n";
($remove_NO eq "true" || $remove_NO eq "false") || die "$0: Bad value for option --remove-NO\n";

my $GLOBAL_THRESH = 0.5;

if ($segment) {
  open(SEG, "<$segment") || die "$0: Fail to open segment file $segment\n";
}

if ($map_utter) {
  open(UTT, "<$map_utter") || die "$0: Fail to open utterance table $map_utter\n";
}

if (@ARGV != 2) {
  die $Usage;
}

# Get parameters
my $filein = shift @ARGV;
my $fileout = shift @ARGV;

# Get input source
my $source = "";
if ($filein eq "-") {
  $source = "STDIN";
} else {
  open(I, "<$filein") || die "$0: Fail to open input file $filein\n";
  $source = "I";
}

# Get symbol table and start time
my %tbeg;
if ($segment) {
  while (<SEG>) {
    chomp;
    my @col = split(" ", $_);
    @col == 4 || die "$0: Bad number of columns in $segment \"$_\"\n";
    $tbeg{$col[0]} = $col[2];
  }
}

# Get utterance mapper
my %utter_mapper;
if ($map_utter) {
  while (<UTT>) {
    chomp;
    my @col = split(" ", $_);
    @col == 2 || die "$0: Bad number of columns in $map_utter \"$_\"\n";
    $utter_mapper{$col[0]} = $col[1];
  }
}

# Get oov count
my %oovHash;
if ($oov_count_file ne "") {
  open (OOV_COUNT, $oov_count_file) || die "$0: Cannot open $oov_count_file\n";
  while(<OOV_COUNT>)
  {
    chomp;
    my ($kwid, $count) = /^(\S+) ([0-9]+)/;
    defined($kwid) && defined($count) ||
      die "$0: Unexpected format in $oov_count_file\n$_\nstopped\n";
    $oovHash{$kwid} = $count;
  }
  close OOV_COUNT;
}

# Function for printing Kwslist.xml
sub PrintKwslist {
  my ($info, $KWS) = @_;

  my $kwslist = "";
  my %printed_kw;

  # Start printing
  $kwslist .= "<kwslist kwlist_filename=\"$info->[0]\" language=\"$info->[1]\" system_id=\"$info->[2]\">\n";
  my $prev_kw = "";
  foreach my $kwentry (@{$KWS}) {
    if ($prev_kw ne $kwentry->[0]) {
      if ($prev_kw ne "") {$kwslist .= "  </detected_kwlist>\n";}
      my $kwid = $kwentry->[0];
      my $oov_count = 0;
      if ($oov_count_file ne "") {
        if (defined $oovHash{$kwid}) {
          $oov_count = $oovHash{$kwid};
          $printed_kw{$kwid} = 1;
        } else {
          die "$0: Missing oov count for $kwid in $oov_count_file\nstopped\n";
        }
      }
      $kwslist .= "  <detected_kwlist search_time=\"1\" kwid=\"$kwentry->[0]\" oov_count=\"$oov_count\">\n";
      $prev_kw = $kwentry->[0];
    }
    $kwslist .= "    <kw file=\"$kwentry->[1]\" channel=\"$kwentry->[2]\" tbeg=\"$kwentry->[3]\" dur=\"$kwentry->[4]\" score=\"$kwentry->[5]\" decision=\"$kwentry->[6]\"";
    if (defined($kwentry->[7])) {$kwslist .= " threshold=\"$kwentry->[7]\"";}
    if (defined($kwentry->[8])) {$kwslist .= " raw_score=\"$kwentry->[8]\"";}
    $kwslist .= "/>\n";
  }
  $kwslist .= "  </detected_kwlist>\n";
  foreach my $kwid (sort(keys %oovHash)) {
    if (! defined $printed_kw{$kwid}) {
      my $oov_count = $oovHash{$kwid};
      $kwslist .= "  <detected_kwlist search_time=\"1\" kwid=\"$kwid\" oov_count=\"$oov_count\">\n";
      $kwslist .= "  </detected_kwlist>\n";
      $printed_kw{$kwid} = 1;
    }
  }
  $kwslist .= "</kwslist>\n";

  return $kwslist;
}

# Function for sorting
sub KwslistOutputSort {
  if ($a->[0] ne $b->[0]) {
    if ($a->[0] =~ m/[0-9]+$/ && $b->[0] =~ m/[0-9]+$/) {
      ($a->[0] =~ /([0-9]*)$/)[0] <=> ($b->[0] =~ /([0-9]*)$/)[0]
    } else {
      $a->[0] cmp $b->[0];
    }
  } elsif ($a->[5] ne $b->[5]) {
    $b->[5] <=> $a->[5];
  } else {
    $a->[1] cmp $b->[1];
  }
}
sub KwslistDupSort {
  my ($a, $b, $duptime) = @_;
  if ($a->[0] ne $b->[0]) {
    $a->[0] cmp $b->[0];
  } elsif ($a->[1] ne $b->[1]) {
    $a->[1] cmp $b->[1];
  } elsif ($a->[2] ne $b->[2]) {
    $a->[2] cmp $b->[2];
  } elsif (abs($a->[3]-$b->[3]) >= $duptime){
    $a->[3] <=> $b->[3];
  } elsif ($a->[5] ne $b->[5]) {
    $b->[5] <=> $a->[5];
  } else {
    $b->[4] <=> $a->[4];
  }
}

# function for calculating the empirical threshold for a keyword
sub computeThresholdEmpirical
{    
    my ($fraction, $beta, $totalTime, @probs) = @_;

    my ($prob, $totalProb);
    my (%probCount, @hitArray, @faArray, $hitAccum, $faAccum, $i);
    my ($fomEstimate, $thresh);

    # Get total prob and set up to remove duplicate probs 
    $totalProb = 0;
    foreach $prob (@probs)
    {
	$totalProb += $prob;
	$probCount{$prob} = 0 unless defined($probCount{$prob});
	$probCount{$prob}++;
    }

    #In descending order and unique
    @probs = sort {$b <=> $a} keys %probCount;

    $i = $hitAccum = $faAccum = 0;
    foreach $prob (@probs)
    {
	#FAs ~ $fraction * -log($prob)
	$hitAccum += $prob * ($probCount{$prob} +  $fraction * log ($prob));
	$hitArray[$i] = $hitAccum / $totalProb;

	$faAccum += $probCount{$prob};	  
	$faArray[$i] = $faAccum / ($totalTime - $totalProb);

	$i++;
    }
	
    $fomEstimate = $hitArray[0] - $beta * $faArray[0];
    $thresh = $probs[0];
    for ($i=1; $i<=$#probs; $i++)
    {
	if ($hitArray[$i] - $beta * $faArray[$i] > $fomEstimate)
	{
	    $fomEstimate = $hitArray[$i] - $beta * $faArray[$i];
	    $thresh = $probs[$i];
	}
    }

    $thresh > 0 || die "Bad threshold\nstopped";

    return $thresh;
}

# Processing
my @KWS;
while (<$source>) {
  chomp;
  my @col = split(" ", $_);
  @col == 5 || die "$0: Bad number of columns in raw results \"$_\"\n";
  my $kwid = shift @col;
  my $utter = $col[0];
  my $start = sprintf("%.2f", $col[1]*$flen);
  my $dur = sprintf("%.2f", $col[2]*$flen-$start);
  my $score = exp(-$col[3]);

  if ($segment) {
    $start = sprintf("%.2f", $start+$tbeg{$utter});
  }
  if ($map_utter) {
    $utter = $utter_mapper{$utter};
  }

  push(@KWS, [$kwid, $utter, 1, $start, $dur, $score, ""]);
}

my %Ntrue = ();
my %kw_probs = ();
foreach my $kwentry (@KWS) {
  my $kwid = $kwentry->[0];
  my $prob = $kwentry->[5];
  if (!defined($Ntrue{$kwid})) {
    $Ntrue{$kwid} = 0.0;
    $kw_probs{$kwid} = [];
  }
  $Ntrue{$kwid} += $prob;
  push(@{ $kw_probs{$kwid} }, $prob); 
}

my %threshold;

# Scale the Ntrue, calculate the thresholds
foreach my $key (keys %Ntrue) {
  $Ntrue{$key} *= $Ntrue_scale;
  if ($empirical eq "true") {
    # empirical thresholding
    $threshold{$key} = &computeThresholdEmpirical($fraction, $beta, $duration, @{$kw_probs{$key}});
  } else {
    # decision theoretic thresholding
    $threshold{$key} = $Ntrue{$key}/($duration/$beta+($beta-1)/$beta*$Ntrue{$key});
  }
}

# Removing duplicates
if ($remove_dup eq "true") {
  my @tmp = sort {KwslistDupSort($a, $b, $duptime)} @KWS;
  @KWS = ();
  push(@KWS, $tmp[0]);
  for (my $i = 1; $i < scalar(@tmp); $i ++) {
    my $prev = $KWS[-1];
    my $curr = $tmp[$i];
    if ((abs($prev->[3]-$curr->[3]) < $duptime ) &&
        ($prev->[2] eq $curr->[2]) &&
        ($prev->[1] eq $curr->[1]) &&
        ($prev->[0] eq $curr->[0])) {
      next;
    } else {
      push(@KWS, $curr);
    }
  }
}

# generate decisions
foreach my $kwentry (@KWS) {
  my $threshold = $threshold{$kwentry->[0]};
  my $offset_score;
  if ($empirical eq "true") {
    # empirical thresholding
    # just apply offset for normalization
    #$offset_score = $kwentry->[5] + $GLOBAL_THRESH - $threshold;
    #if ($offset_score >= $GLOBAL_THRESH) {
    #if ($kwentry->[5] >= $threshold) {
    if ($kwentry->[5] - $threshold >= -1e-12) {
      $kwentry->[6] = "YES";
    } else {
      $kwentry->[6] = "NO";
    }
  } else {
    # decision theoretic thresholding
    #if ($kwentry->[5] > $threshold) {
    if ($kwentry->[5] >= $threshold) {
      $kwentry->[6] = "YES";
    } else {
      $kwentry->[6] = "NO";
    }
  }
  if ($verbose > 0) {
    #push(@{$kwentry}, sprintf("%g", $threshold));
    push(@{$kwentry}, sprintf("%.19f", $threshold));
    #push(@{$kwentry}, $threshold);
  }
}

# normalize scores
my $format_string = "%g";
if ($digits gt 0 ) {
  $format_string = "%." . $digits ."f";
}
foreach my $kwentry (@KWS) {
  if ($normalize eq "true") {
    if ($verbose > 0) {
      #push(@{$kwentry}, $kwentry->[5]);
      push(@{$kwentry}, sprintf("%.19f", $kwentry->[5]));
    }
    my $threshold = $threshold{$kwentry->[0]};
    if ($empirical eq "true") {
      # empirical thresholding
      # just apply offset for normalization
      my $offset_score = $kwentry->[5] + $GLOBAL_THRESH - $threshold;
      $kwentry->[5] = sprintf($format_string, $offset_score);
    } else {
      # decision theoretic thresholding
      my $numerator = (1-$threshold)*$kwentry->[5];
      my $denominator = (1-$threshold)*$kwentry->[5]+(1-$kwentry->[5])*$threshold;
      if ($denominator != 0) {
        $kwentry->[5] = sprintf($format_string, $numerator/$denominator);
      } else {
        $kwentry->[5] = sprintf($format_string, $kwentry->[5]);
      }
    }
  } else {
    $kwentry->[5] = sprintf($format_string, $kwentry->[5]);
  }
  # if --final-thresh is set, re-do the decision on the final score
  if (abs($final_thresh - 9999) > 1e-12) {
    if ($kwentry->[5] - $final_thresh >= -1e-12) {
      $kwentry->[6] = "YES";
    } else {
      $kwentry->[6] = "NO";
    }
  }
}

# counting YES decisions
my %YES_count;
foreach my $kwentry (@KWS) {
  if ($kwentry->[6] eq "YES") {
    if (defined($YES_count{$kwentry->[0]})) {
      $YES_count{$kwentry->[0]} ++;
    } else {
      $YES_count{$kwentry->[0]} = 1;
    }
  } else {
    if (!defined($YES_count{$kwentry->[0]})) {
      $YES_count{$kwentry->[0]} = 0;
    }
  }
}

# Output sorting
my @tmp = sort KwslistOutputSort @KWS;

# Process the YES-cutoff. Note that you don't need this for the normal cases where
# hits and false alarms are balanced
if ($YES_cutoff != -1) {
  my $count = 1;
  for (my $i = 1; $i < scalar(@tmp); $i ++) { 
    if ($tmp[$i]->[0] ne $tmp[$i-1]->[0]) {
      $count = 1;
      next;
    }
    if ($YES_count{$tmp[$i]->[0]} > $YES_cutoff*2) {
      $tmp[$i]->[6] = "NO";
      $tmp[$i]->[5] = 0;
      next;
    }
    if (($count == $YES_cutoff) && ($tmp[$i]->[6] eq "YES")) {
      $tmp[$i]->[6] = "NO";
      $tmp[$i]->[5] = 0;
      next;
    }
    if ($tmp[$i]->[6] eq "YES") {
      $count ++;
    }
  }
}

# Process the remove-NO decision
if ($remove_NO eq "true") {
  my @KWS = @tmp;
  @tmp = ();
  for (my $i = 0; $i < scalar(@KWS); $i ++) {
    if ($KWS[$i]->[6] eq "YES") {
      push(@tmp, $KWS[$i]);
    }
  }
}

# Printing
my @info = ($kwlist_filename, $language, $system_id);
my $kwslist = PrintKwslist(\@info, \@tmp);

if ($segment) {close(SEG);}
if ($map_utter) {close(UTT);}
if ($filein  ne "-") {close(I);}
if ($fileout eq "-") {
    print $kwslist;
} else {
  open(O, ">$fileout") || die "$0: Fail to open output file $fileout\n";
  print O $kwslist;
  close(O);
}
