#!/usr/bin/env perl

use warnings;

$MAX_PROB = 0.999;
$BETA = 999.9;

@ARGV == 3 || die "kst_norm_kwlist.pl <ecf> <thresh: 0 use default exp(-1)> <kwlist>\n";
my ($ecfFile, $globalThresh, $kwlist) = @ARGV;

my $timeTotal = &loadEcf($ecfFile);

&process($kwlist, $BETA, $timeTotal, $globalThresh);

exit;

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
#	int($start) == 0 || die "Need to skip data at the start\n$_\nstopped";
	
	$count++;
    }

    close IN;

    return $totalTime / 2;
}

sub process
{
    my ($file, $beta, $totalTime, $globalThresh) = @_;

    my ($score, @scores, $record, @records, $threshold, $i);
    my ($neg_log_threshold, $normedProb);

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
		
		$score > 0 || die "Bad prob\n$file\n$_\nstopped";
		
		$score = $MAX_PROB if $score > $MAX_PROB;
		
		push (@scores, $score);
		push (@records, $record);
	      
	    }
	    
	    if ($#scores >= 0)
	    {

		$threshold = &computeThreshold($beta, $totalTime, @scores);
		$neg_log_threshold = -1.0 * log($threshold);
		for($i=0; $i<=$#records; $i++)
		{

		    $normedProb = exp(log($scores[$i]) / $neg_log_threshold);

		    if ($globalThresh > 0)
		    {
			if ($normedProb >= $globalThresh)
			{
			    printf "$records[$i] score=\"%.6e\" decision=\"YES\"\/>\n",
			    $normedProb;
			}
			else
			{
			    printf "$records[$i] score=\"%.6e\" decision=\"NO\"\/>\n",
			    $normedProb;
			}
		    }
		    else
		    {
			if ($scores[$i] >= $threshold)
			{
			    printf "$records[$i] score=\"%.6e\" decision=\"YES\"\/>\n",
			    $normedProb;
			}
			else
			{
			    printf "$records[$i] score=\"%.6e\" decision=\"NO\"\/>\n",
			    $normedProb;
			}
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

