#!/usr/bin/env perl

use warnings;

@ARGV > 0 || die "merge_search_results.pl <search result files>\n";

my $results = shift @ARGV;

my ($header) = &load($results);

foreach $results (@ARGV)
{
    &load($results);
}

@keywords = sort keys %headerHash;

# This is actually redundant
&mergeDuplicates(@keywords);

&process($header, @keywords);

exit;

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

sub process
{
    my ($header, @keyords) = @_;

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

            #Thresholds will come later
            printf "<kw file=\"$file\" channel=\"1\" tbeg=\"$start\" dur=\"$dur\" score=\"%.6e\" decision=\"YES\"\/>\n", $prob;
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
    my ($file, $label) = @_;

    my ($fileId, $tbeg, $dur, $score, $decision, $keyword, $tend, $header);

    open (IN, $file) || die "Cannot open $file\n";

    $header = <IN>;

    while(<IN>)
    {
    if (/^<detected_kwlist kwid/)
    {
        ($keyword) = / kwid="([^\"]+)"/;
        defined($keyword) || die "Unexpected format\n$_\nstopped";
        $headerHash{$keyword} = $_;

        while(<IN>)
        {
        last if /<\/detected_kwlist>/;
        
        # The fields can get switched around by various processing scripts
        # Try the default ordering and if that fails, try alphabetical...
        $valid = 0;
        ($fileId, $tbeg, $dur, $score, $decision) = /<kw file=\"(\S+)\" channel=\"1\" tbeg=\"([0-9\.]+)\" dur=\"([0-9\.]+)\" score=\"([0-9\.e\-\+]+)\" decision=\"([YESNO]+)\"/;
        
        if (defined($file) && defined($tbeg) && defined($dur) && defined($score) && 
            defined($decision))
        {
            $valid = 1;
        }
        else # try alphabetical order...
        {
                    ($decision, $dur, $fileId, $score, $tbeg) = /<kw channel=\"1\" decision=\"([YESNO]+)\" dur=\"([0-9\.]+)\" file=\"(\S+)\" score=\"([0-9\.e\-\+]+)\" tbeg=\"([0-9\.]+)\"/;
                    if (defined($file) && defined($tbeg) && defined($dur) && defined($score) && 
                        defined($decision)) 
                    {
                        $valid = 1;
                    }
                }

        $valid != 0 || die "Unexpected format\n$_\nstopped";
        
        $tbeg = sprintf "%.2f", $tbeg;
        $dur = sprintf "%.2f", $dur;
        
        ## Skip them instead
        #$score > 0 || die "Bad prob\n$file\n$_\nstopped";
        
        next unless $score > 0; 
        

        if (defined($recordHash{$keyword}{$fileId}{"$tbeg"}{"$dur"}))
        {
            #Take max
            if ($score > $recordHash{$keyword}{$fileId}{"$tbeg"}{"$dur"})
            {
            $recordHash{$keyword}{$fileId}{"$tbeg"}{"$dur"} = $score;
            }
        }
        else
        {
            $recordHash{$keyword}{$fileId}{"$tbeg"}{"$dur"} = $score;
        }

        if (defined($labelHash{$keyword}{$fileId}{"$tbeg"}{"$dur"}))
        {
            if ($label != $labelHash{$keyword}{$fileId}{"$tbeg"}{"$dur"})
            {
            $labelHash{$keyword}{$fileId}{"$tbeg"}{"$dur"} = 3;
            }
        }
        else
        {
            $labelHash{$keyword}{$fileId}{"$tbeg"}{"$dur"} = $label;

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
    
    return $header;

}

