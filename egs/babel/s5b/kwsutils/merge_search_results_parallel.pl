#!/usr/bin/perl -w

@ARGV > 1 || die "merge_search_results_parallel.pl <kw list> <search result files>\n";

# exp(-1)
$GLOBAL_THRESH = 3.678794e-01;

my $kwKeepList = shift @ARGV;

my $nFiles = @ARGV;
my $results = shift @ARGV;

&loadKW($kwKeepList);

my ($header, @keywords) = &load($results);

foreach $results (@ARGV)
{
    &load($results);
}

&mergeDuplicatesOverlapsSumProbs(@keywords);

&process($header, $nFiles, @keywords);

exit;

sub loadKW
{
    my ($file) = @_;
    
    my ($keyword);

    open (IN, $file) || die "Cannot open $file\n";

    while(<IN>)
    {
	chomp;
	($keyword) = /^(\S+)$/;
	defined($keyword) || die "Unexpected format\n$_\nstopped";

	$keep{$keyword} = 1;
    }

    close IN;
}

sub mergeDuplicatesOverlapsSumProbs
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
			    $recordHash{$keyword}{$file}{$start}{$maxDur} += $recordHash{$keyword}{$file}{$start}{$dur};

			    delete $recordHash{$keyword}{$file}{$start}{$dur};
			}
		    }
		    else
		    {
			$end{$start} = sprintf "%.2f", $start + $durs[0];
			$dur{$start} = $durs[0];
		    }
		}
		
                # Merge nested sub paths		
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
				    $recordHash{$keyword}{$file}{$starts[$i]}{$dur{$starts[$i]}} += $recordHash{$keyword}{$file}{$starts[$j]}{$dur{$starts[$j]}};
				    				    
				    delete $recordHash{$keyword}{$file}{$starts[$j]}{$dur{$starts[$j]}};
				}
			    }
			}
		    }
		}
		
		# Merge overlapping (including sub) paths
		for($i=0; $i<$#starts; $i++)
		{
		    # We may have removed it
		    if (defined($recordHash{$keyword}{$file}{$starts[$i]}{$dur{$starts[$i]}}))
		    {
			for($j=$i+1; $j<=$#starts; $j++)
			{
			    if ($starts[$j] <= $end{$starts[$i]})
			    {
				#We may have already removed it
				if (defined($recordHash{$keyword}{$file}{$starts[$j]}{$dur{$starts[$j]}}))
				{
				    $prob = $recordHash{$keyword}{$file}{$starts[$i]}{$dur{$starts[$i]}};
				    $prob += $recordHash{$keyword}{$file}{$starts[$j]}{$dur{$starts[$j]}};
				    # Delete both records
				    delete $recordHash{$keyword}{$file}{$starts[$j]}{$dur{$starts[$j]}};
				    delete $recordHash{$keyword}{$file}{$starts[$i]}{$dur{$starts[$i]}};

				    if ($end{$starts[$j]} > $end{$starts[$i]})
				    {
					## Overalapping path, extend it
					$end{$starts[$i]} = sprintf "%.2f", 
					$end{$starts[$j]};
					
					$dur{$starts[$i]} = sprintf "%.2f", 
					$end{$starts[$i]} - $starts[$i];
				    }
				    
				    $recordHash{$keyword}{$file}{$starts[$i]}{$dur{$starts[$i]}} = $prob;
				}
			    }
			}
		    }
		}
	    }
	}
    }
}

sub process
{
    my ($header, $nFiles, @keyords) = @_;

    my ($keyword, $file, $start, $dur, $prob);

    print $header;

    foreach $keyword (@keywords)
    {
	print $headerHash{$keyword};

	if (defined($recordHash{$keyword}))
	{
	    foreach $file (sort keys %{ $recordHash{$keyword} } )
	    {
		foreach $start (sort {$a <=> $b} keys %{ $recordHash{$keyword}{$file} })
		{
		    foreach $dur (sort {$a <=> $b} keys %{ $recordHash{$keyword}{$file}{$start} })
		    {
			$prob = $recordHash{$keyword}{$file}{$start}{$dur};

			# Use global thresh for now
			# Can be overwitten later

			if ($prob >= $GLOBAL_THRESH)
			{
			    printf "<kw file=\"$file\" channel=\"1\" tbeg=\"$start\" dur=\"$dur\" score=\"%.6e\" decision=\"YES\"\/>\n", $prob / $nFiles;
			}
			else
			{
			    printf "<kw file=\"$file\" channel=\"1\" tbeg=\"$start\" dur=\"$dur\" score=\"%.6e\" decision=\"NO\"\/>\n", $prob / $nFiles;
			}
		    }
		}
	    }
	}
	
	print "</detected_kwlist>\n";
    }
    
    print "</kwslist>\n";
}

sub load
{
    my ($file) = @_;

    my ($fileId, $tbeg, $dur, $score, $decision, $keyword, $tend, $header, @keywords);

    open (IN, $file) || die "Cannot open $file\n";

    $header = <IN>;

    @keywords = ();
    while(<IN>)
    {
	if (/^<detected_kwlist kwid/)
	{
	    ($keyword) = / kwid=\"(\S+)\"/;
	    defined($keyword) || die "Unexpected format\n$_\nstopped";
	    push(@keywords, $keyword) if defined($keep{$keyword});
	    $headerHash{$keyword} = $_;

	    while(<IN>)
	    {
		last if /<\/detected_kwlist>/;
		
		next unless defined($keep{$keyword});

		($fileId, $tbeg, $dur, $score, $decision) = /<kw file=\"(\S+)\" channel=\"1\" tbeg=\"([0-9\.]+)\" dur=\"([0-9\.]+)\" score=\"([0-9\.e\-\+]+)\" decision=\"([YESNO]+)\"/;
		defined($file) && defined($tbeg) && defined($dur) && defined($score) && 
		    defined($decision) || die "Unexpected format\n$_\nstopped";
		
		$tbeg = sprintf "%.2f", $tbeg;
		$dur = sprintf "%.2f", $dur;
		
		next unless $score > 0; 

		if (defined($recordHash{$keyword}{$fileId}{"$tbeg"}{"$dur"}))
		{
		    $recordHash{$keyword}{$fileId}{"$tbeg"}{"$dur"} += $score;
		}
		else
		{
		    $recordHash{$keyword}{$fileId}{"$tbeg"}{"$dur"} = $score;
		}
	    }
	}
	elsif (/<\/kwslist>/)
	{
	    last;
	}
	else
	{
	    die "Unexpected format\n$_\nstopped";
	}
    }

    close IN;
    
    return $header, @keywords;

}

