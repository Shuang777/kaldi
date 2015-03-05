#!/usr/bin/env perl

use warnings;

#$TIME_GAP = 0.5;
$FRAMES_PER_SEC = 100;

print $0 . " ". (join " ", @ARGV) . "\n";

@ARGV >= 11 || die "search_index.pl <ecf> <term_list_xml> <oov count file> <keyword_terms_surface_forms_file [None|*]> <time gap> <use min prob?> <index> <out> <term_list_basename> <language_name> <systemid>\n";

$ecfFile = shift @ARGV;
$termList = shift @ARGV;
$oovCountFile = shift @ARGV;
$keywordSurfaceFormFile = shift @ARGV;
$time_gap = shift @ARGV;
$USE_MIN =  shift @ARGV;
$index = shift @ARGV;
$out = shift @ARGV;
$kwslist_basename = shift @ARGV;
$language_name = shift @ARGV;

$system_id = "@ARGV";

&loadEcf($ecfFile);

&loadIndex($index);

@termids = &loadTerms($termList);

&loadOovCounts($oovCountFile, @termids);

&loadTermSurfaceForm($keywordSurfaceFormFile);

&searchIndex();

&mergeDuplicates(@termids);

&dumpResults($termList, $out, @termids);

exit;

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
#    int($start) == 0 || die "Need to skip data at the start\n$_\nstopped";
    
    die "Dups\n$_\nstopped" if defined($endHash{$id});
    $endHash{$id} = $dur;
    $count++;
    }

    close IN;

    printf "Loaded info from $count files from ecf\nTotal time: %.3f\n", $totalTime / 2;
  
    return $totalTime / 2;
}

sub loadIndex
{
  my ($index) = @_;
  my ($fStart, $start, $dur, $score, $term, $file);

  print "Loading index...\n";

  if ($index =~ /\.bz2$/)
  {
    open(IN, "bzcat $index |" ) || die "Cannot open pipe: bzcat $index |\n";
  }
  else
  {
    open(IN, $index) || die "Cannot open $index\n";
  }

  while(<IN>)
  {
    chomp;

    ($file, $fStart, $start, $end, $score, $term) = /^(\S+)_([0-9]+)[_-][0-9]+ ([0-9\.]+) ([0-9\.]+) ([0-9\.e\-\+]+) (.*)$/;
    defined($file) && defined($fStart) && defined($start) && defined($end) && defined($score) && defined($term) || die "Unexpected format\n$_\nstopped";
    
    #next if $term =~ /^<s/ || $term =~ /<\/s>/;
    #next if $term =~ /^<\S+>$/;

    next unless $score > 0;

    $term =~ s/^ //g;
    $term =~ s/ $//g;

    $dur = $end - $start;
    $start += $fStart / $FRAMES_PER_SEC;

    $dur = sprintf "%.2f", $dur;
    $start = sprintf "%.2f",$start;
    
    if(defined($wordIndex{$term}{$file}{$start}{$dur}))
    {
      if ($score > $wordIndex{$term}{$file}{$start}{$dur})
      {
        $wordIndex{$term}{$file}{$start}{$dur} = $score;
      }
    }
    else
    {
      $wordIndex{$term}{$file}{$start}{$dur} = $score;
    }

  }

  close IN;
}

sub loadTerms
{
    my ($file) = @_;

    my($count, $term, $termid, @termids);

    print "Loading terms...\n";
    open(IN, $file) || die "Cannot open $file\n";
    
    @termids = ();
    $count = 0;
    while(<IN>)
    {
        if (/<kw kwid/)
        {
            ($termid) = /kwid=\"([A-Za-z0-9_\-]+)\">/;
            defined($termid) || die "Unexpected format\n$_\nstopped";
            
            push (@termids, $termid);

            $_ = <IN>;
            ($term) = /<kwtext>\s*(.*?)\s*<\/kwtext>/;
            defined($term) || die "Unexpected format\n$_\nstopped";

            die "Duplicate terms\n$_\nstopped" if defined($termHash{$term});
            
            $termHash{$term} = $termid;

            $count++;
        }
    }

    close IN;

    print "Loaded $count terms from $file\n";
    return @termids;
}


sub loadOovCounts
{
    my ($file, @kws) = @_;

    my (@data, $kw, $count);
    
    if (not open (IN, $file)) { 
      print "No $file found, assuming no oov.\n"; 
      foreach $kw (@kws) {
        $oovHash{$kw} = 0;
      }
    } else {
    
      while(<IN>)
      {
        chomp;

        ($kw, $count) = /^(\S+) ([0-9]+)/;
        defined($kw) && defined($count) || 
            die "Unexpected format\n$_\nstopped";
        
        $oovHash{$kw} = $count;
      }
    
      close IN;

      foreach $kw (@kws)
      {
        die "Missing count for $kw stopped" unless defined($oovHash{$kw});
      }
    }

}

# load surface form for keyword terms from file
sub loadTermSurfaceForm
{
  my ($file) = @_;

  my($term_count, $surface_count, $term, $surface, %uniqEntries);

  %uniqEntries = ();
  $term_count = 0;
  $surface_count = 0;

  print "Loading keyword term surface forms...\n";

  # if the surface form file is unset
  if ($file eq "None")
  {
    print "No keyword surface form file. Use the keyword terms themselves as the surface form.\n";
  
    foreach $term (keys %termHash)
    {
      if (defined $termSurfaceHash{$term}) {
          die "Error: Duplicate term: $term\n";
      } else {
        my @surface_array = ($term);
        $termSurfaceHash{$term} = \@surface_array;
      }
    }

    return;
  }

  # if the surface form file is set
  open(IN, $file) || die "Cannot open $file\n";
  while(<IN>)
  {
    chomp;

    # skip duplicate lines
    next if (defined $uniqEntries{$_});
        
    $uniqEntries{$_} = 1;

    ($term, $surface) = split(/\t/, $_, 2);

    # skip the line if the word/phrase is not a keyword term
    next unless (defined $termHash{$term});

    unless (defined $termSurfaceHash{$term})
    {
      my @surface_array = ();
      $termSurfaceHash{$term} = \@surface_array;
      $term_count++;
    }
    push(@{$termSurfaceHash{$term}}, $surface);
    $surface_count++;
  }
  close IN;

  print "Loaded $surface_count surface forms for $term_count keyword terms from $file\n";

  # process those terms that are not in the surface form file
  foreach $term (keys %termHash)
  {
    if (! defined $termSurfaceHash{$term}) {
      my @surface_array = ($term);
      $termSurfaceHash{$term} = \@surface_array;
      print STDERR "Warning: no surface form for the keyword term $term, use the term itself.\n";
    }
  }

}


sub searchIndex
{
  my ($id, $channel, $start, $dur, $score, $term, $termid, $record, $token, @tokens);
  print "Searching index...\n";
  foreach $term (keys %termHash)
  {
    $termid = $termHash{$term};

    # search for all surface forms of a word
    # for the retrieved entries that share the same start and end time, only keep the one with the highest score
    # (the merge is done inside searchSingle and searchMultiple)
    unless (defined $termSurfaceHash{$term}) {
      die "Error: surface form undefined yet for term $term\n";
    }
    foreach $termSurface (@{ $termSurfaceHash{$term} })
    {
      @tokens = split(/ /, $termSurface);
      if (@tokens == 1)
      {
        &searchSingle($termid, $termSurface);
      }
      else
      {
        &searchMultiple($termid, @tokens);
      }
    }
  }
}

sub searchMultiple
{
  my ($termid, @tokens) = @_;
  my ($file, $start, $dur, $prob, $minprob, $firstTerm, $tStart, $tDur, $lEnd, 
  @endTimeProb, @successors, @array, $i, $j, $count, $pathEndTime);
    
  foreach $term (@tokens)
  { 
    unless (defined($wordIndex{$term}))
    {
      return;
    }
  }
  $firstTerm = $tokens[0];
  FILE: foreach $file (keys %{ $wordIndex{$firstTerm} } )
  {
    for($i=1; $i<=$#tokens; $i++)
    {
      next FILE unless defined($wordIndex{$tokens[$i]}{$file})
    }

    foreach $start (sort {$a <=> $b} keys %{ $wordIndex{$firstTerm}{$file} })
    {
      FIRST_END: foreach $dur (sort {$a <=> $b} keys 
                   %{ $wordIndex{$firstTerm}{$file}{$start} })
      {
                ##
                ## Have the first token's start and end time
        ## Walk through the remaining tokens, keeping track of
        ## the start and durs, and the minprob along the path.
        ## If paths intersect, take the max rather than sum probs.
        ##
        undef @endTimeProb;
        undef @successors;
        $endTimeProb[0]{$start + $dur} = 
            $wordIndex{$firstTerm}{$file}{$start}{$dur};
        for($i=1; $i<=$#tokens; $i++)
        {
            $count = 0;
            foreach $lEnd (sort {$a <=> $b} keys %{ $endTimeProb[$i-1]} )
            {
            #$minprob = $endTimeProb[$i-1]{$lEnd};
            @array = ();
            foreach $tStart (sort {$a <=> $b} keys 
                     %{ $wordIndex{$tokens[$i]}{$file} })
            {
              ## Used to allow $tStart >= $lEnd - $TIME_GAP
              ## Just gives false alarms
              if ($tStart >= $lEnd && $tStart <= $lEnd+$time_gap)
              {            
                foreach $tDur (sort {$a <=> $b} keys 
                           %{ $wordIndex{$tokens[$i]}{$file}{$tStart} })
                {
                  if ($USE_MIN == 1)
                  {
                    #First get the prob for this path by taking min
                    if ($wordIndex{$tokens[$i]}{$file}{$tStart}{$tDur} < $endTimeProb[$i-1]{$lEnd})
                    {
                      $minprob = $wordIndex{$tokens[$i]}{$file}{$tStart}{$tDur};
                    }
                    else
                    {
                      $minprob = $endTimeProb[$i-1]{$lEnd};
                    }
                  }
                  else
                  {
                    #Multiply path probs
                    $minprob = $wordIndex{$tokens[$i]}{$file}{$tStart}{$tDur} * $endTimeProb[$i-1]{$lEnd};
                  }
                    
                    #Check to see if any previous paths end at this time
                  if (defined($endTimeProb[$i] {$tStart + $tDur}))
                  {
                    ## A path with this token already exists and ends 
                    ## at this time: rather than sum probs, take max
                    ## (too many approximations in play to make
                    ## summing reasonable)
                    if ($minprob > $endTimeProb[$i] {$tStart + $tDur})
                    {
                      $endTimeProb[$i] {$tStart + $tDur} = $minprob;
                    }
                  }
                  else
                  {
                    $endTimeProb[$i] {$tStart + $tDur} = $minprob;
                  }

                  push (@array, $tStart, $tDur);
                }
              }
            }
            
            if (@array > 0)
            {
              $successors[$i-1]{$lEnd} = [ @array ];
              $count++;
            }

          }
            
          next FIRST_END if $count == 0;
        }

        $i = $#tokens;
        foreach $lEnd (sort {$a <=> $b} keys %{ $successors[$i-1]} )
        {
          @array = @{ $successors[$i-1]{$lEnd} };
            
          for($j=0; $j<$#array; $j+=2)
          {
            $tStart = $array[$j];
            $tDur = $array[$j+1];
            $prob = $endTimeProb[$i] {$tStart + $tDur};
            defined($endTimeProb[$i] {$tStart + $tDur}) || 
                die "Missing record\nstopped";

            ## Overwrite $tDur, so use $prob instead of
            ## $endTimeProb[$i] {$tStart + $tDur} from now on
            $tDur = $tStart + $tDur - $start;
            
            ##
            ## If there are multiple paths ending at the same time
            ## approximate the sum by the max
            if (defined($recordHash{$termid}{$file}{$start}{$tDur}))
            {
              if ($prob > $recordHash{$termid}{$file}{$start}{$tDur})
              {
                $recordHash{$termid}{$file}{$start}{$tDur} = $prob;
              }
            }
            else
            {
              $recordHash{$termid}{$file}{$start}{$tDur} = $prob;
            }
          }
        }        
      }
    }
  }
}

sub searchSingle
{
  my ($termid, $term) = @_;
  my ($file, $start, $dur);

  if (defined($wordIndex{$term}))
  {
    foreach $file (keys %{ $wordIndex{$term} } )
    {
      foreach $start (keys %{ $wordIndex{$term}{$file} })
      {
        foreach $dur (keys %{ $wordIndex{$term}{$file}{$start} })
        {
          # check duplication and merge
          if (defined($recordHash{$termid}{$file}{$start}{$dur}))
          {
            if ($recordHash{$termid}{$file}{$start}{$dur} < $wordIndex{$term}{$file}{$start}{$dur})
            {
              $recordHash{$termid}{$file}{$start}{$dur} = $wordIndex{$term}{$file}{$start}{$dur};
            }
          }
          else
          {
            $recordHash{$termid}{$file}{$start}{$dur} = $wordIndex{$term}{$file}{$start}{$dur};
          }
        }
      }
    }
  }
}



sub mergeDuplicates
{
  my (@keywords) = @_;

  my ($keyword, $file, $start, $dur, @durs, $maxDur, $prob);
  my (%end, %dur, @starts, $i, $j);

  foreach $keyword (@keywords)
  {
    if (defined($recordHash{$keyword}))
    {
      foreach $file (sort keys %{ $recordHash{$keyword} } )
      {
        # In ascending order
        @starts = sort {$a <=> $b} keys %{ $recordHash{$keyword}{$file} };
        undef %end;
        undef %dur;
        foreach $start (@starts)
        {
          #Sort in descending order
          @durs = sort {$b <=> $a} keys %{ $recordHash{$keyword}{$file}{$start} };
          @durs > 0 || die "Something wrong $keyword\n$file\nstopped";

          if (@durs > 1)
          {
            $maxDur = shift @durs;
            $end{$start} = sprintf "%.2f", $start + $maxDur;
            $dur{$start} = $maxDur;

            foreach $dur (@durs)
            {
              if ($recordHash{$keyword}{$file}{$start}{$dur} > $recordHash{$keyword}{$file}{$start}{$maxDur})
              {
                $recordHash{$keyword}{$file}{$start}{$maxDur} = $recordHash{$keyword}{$file}{$start}{$dur};
              }
                
              delete $recordHash{$keyword}{$file}{$start}{$dur};
            }
          }
          else
          {
            $end{$start} = sprintf "%.2f", $start + $durs[0];
            $dur{$start} = $durs[0];
          }
        }

        # Merge sub paths        
        for($i=0; $i<$#starts; $i++)
        {
          # We may have removed it
          if (defined($recordHash{$keyword}{$file}{$starts[$i]}{$dur{$starts[$i]}}))
          {
            for($j=$i+1; $j<=$#starts; $j++)
            {
              if ($end{$starts[$j]} <= $end{$starts[$i]})
              {
                #We may have already removed it
                if (defined($recordHash{$keyword}{$file}{$starts[$j]}{$dur{$starts[$j]}}))
                {
                  if ($recordHash{$keyword}{$file}{$starts[$j]}{$dur{$starts[$j]}} > $recordHash{$keyword}{$file}{$starts[$i]}{$dur{$starts[$i]}})
                  {
                    $recordHash{$keyword}{$file}{$starts[$i]}{$dur{$starts[$i]}} = $recordHash{$keyword}{$file}{$starts[$j]}{$dur{$starts[$j]}};
                  }
                    
                  delete $recordHash{$keyword}{$file}{$starts[$j]}{$dur{$starts[$j]}};
                }
              }
            }
          }
        }
      }
    }    
  }
}

sub dumpResults
{
  my ($listName, $out, @termids) = @_;
  
  my ($termid, $record, $file, $id, $channel, $start, $dur, $prob);
  my (%dupHash, $dupRecord);

  print "Dumping results...\n";

  open (OUT, ">$out") || die "Cannot open $out\n";
  
  print OUT "<kwslist kwlist_filename=\"$kwslist_basename\" language=\"$language_name\" system_id=\"$system_id\">\n";
  
  foreach $termid (@termids)
  {
    if (defined($recordHash{$termid}))
    {
      $record = "";
      foreach $file (sort keys %{ $recordHash{$termid} } )
      {
        foreach $start (sort {$a <=> $b} keys %{ $recordHash{$termid}{$file} })
        {
          foreach $dur (sort {$a <=> $b} keys %{ $recordHash{$termid}{$file}{$start} })
          {
            $prob = $recordHash{$termid}{$file}{$start}{$dur};
            
            defined($endHash{$file}) || 
                die "Missing end time info for $file\nstopped";
            
            ## These can be zero or even negative
            $dur = 0.01 if $dur <= 0;
            
            if ($start + $dur >= $endHash{$file})
            {
              if ($start < $endHash{$file})
              {
                printf "Adjusting time in $file $start %.2f -> ", $dur;
                $dur = $endHash{$file} - $start - 0.01;
                printf "%.2f", $dur;
                if ($dur < 0.01)
                {
                  print " dur to small, skipping\n";
                  next;
                }
                else
                {
                    print "\n";
                }
              }
              else
              {
                print "Skipping term in $file $start $dur\n";
                next;
              }
            }
            
            $dupRecord = sprintf("$termid $file tbeg=\"$start\" dur=\"%.2f\" ", $dur);
            
            if (defined($dupHash{$dupRecord}))
            {
              print "Skipping duplicate term: $file $start $dur $prob\n";
            }
            else
            {
              $dupHash{$dupRecord} = $prob;
               
              # Dummy decision, thresholding happens later
              $record .= sprintf "<kw file=\"$file\" channel=\"1\" tbeg=\"$start\" dur=\"%.2f\" score=\"%.6e\" decision=\"YES\"\/>\n", $dur, $prob;

            }
          }
        }
      }
        
      print OUT "<detected_kwlist kwid=\"$termid\" search_time=\"1\" oov_count=\"$oovHash{$termid}\">\n";
      print OUT $record if $record ne "";
      print OUT "</detected_kwlist>\n";
        
    }
    else
    {
      print OUT "<detected_kwlist kwid=\"$termid\" search_time=\"1\" oov_count=\"$oovHash{$termid}\">\n";
      print OUT "</detected_kwlist>\n";

    }
  }

  print OUT "</kwslist>\n";

  close OUT;
}


