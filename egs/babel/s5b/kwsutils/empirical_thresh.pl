#!/usr/bin/env perl

use warnings;

$BETA = 999.9;

$GLOBAL_THRESH = 0.5;

@ARGV == 4 || die "thresh.pl <ecf> <kwlist> <decision thresh?:[01]> <frac>\n";
my ($ecfFile, $kwlist, $decisionThresh, $frac) = @ARGV;

my $timeTotal = &loadEcf($ecfFile);

&process($kwlist, $BETA, $timeTotal, $decisionThresh, $frac);

exit;

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

sub computeThreshold
{    
  my ($beta, $totalTime, @probs) = @_;

  my ($prob, $totalProb, $time_beta_ratio, $thresh);

  # Get total prob
  $totalProb = 0;
  foreach $prob (@probs)
  {
    $totalProb += $prob;
  }

  $time_beta_ratio = $totalTime / $beta;

  $thresh = $totalProb / ($time_beta_ratio + $totalProb);

  $thresh > 0 || die "Bad threshold\nstopped";

  return $thresh;
}

sub loadEcf
{
  my ($file) = @_;

  my ($totalTime, $id, $start, $dur, $count);

  open (IN, $file) || die "Cannot open $file\n";
  
  $_ = <IN>;
  ($totalTime) = /ecf source_signal_duration=\"([0-9\.]+)\"/;
  defined($totalTime) || die "Unexpected format\n$_\nstopped";
  
  $count = 0;
  while(<IN>)
  {
    next unless /excerpt audio_filename=/;
    ($id, $start, $dur) = /excerpt audio_filename=\"(\S+)\" channel=\"1\" tbeg=\"([0-9\.]+)\" dur=\"([0-9\.]+)\"/;
    defined($id) && defined($start) && defined($dur) || die "Unexpected format\n$_\nstopped";
    
    $count++;
  }

  close IN;

  return $totalTime / 2;
}

sub process
{
  my ($file, $beta, $totalTime, $decisionThresh, $fraction) = @_;

  my ($score, @scores, $record, @records, $threshold, $i);

  open (IN, $file) || die "Cannot open $file\n";

  $_ = <IN>;
  print;

  while(<IN>)
  {
    if (/^<detected_kwlist kwid/)
    {
      print;
      
      @scores = @records = ();
      while(<IN>)
      {
        last if /<\/detected_kwlist>/;
        
        ($record, $score) = /(<kw file=\"\S+\" channel=\"1\" tbeg=\"[0-9\.]+\" dur=\"[0-9\.]+\") score=\"([0-9\.e\-\+]+)\" decision=\"[YESNO]+\"/;
        defined($record) && defined($score) || 
                      die "Unexpected format\n$_\nstopped";
         
        if ($score == 0) {
          $score = 0.000002;
        }
        $score > 0 || die "Bad prob\n$file\n$_\nstopped";
        
        push (@scores, $score);
        push (@records, $record);
          
      }
        
      if ($#scores >= 0)
      {

        if ($decisionThresh == 1)
        {
          $threshold = &computeThreshold($beta, $totalTime, @scores);
        }
        else
        {
          $threshold = &computeThresholdEmpirical($fraction, $beta, $totalTime, @scores);
        }

        for($i=0; $i<=$#records; $i++)
        {
          # Apply offset
          $scores[$i] += $GLOBAL_THRESH - $threshold;
            
          if ($scores[$i] >= $GLOBAL_THRESH)
          {
            printf "$records[$i] score=\"%.6e\" decision=\"YES\"\/>\n",$scores[$i];
          }
          else
          {
            printf "$records[$i] score=\"%.6e\" decision=\"NO\"\/>\n", $scores[$i];
          }
        }
      }
      print "<\/detected_kwlist>\n";
    }
    elsif (/<\/kwslist>/)
    {
      print;
      last;
    }
    else
    {
      die "Unexpected format\n$_\nstopped";
    }
  }

  close IN;
}

