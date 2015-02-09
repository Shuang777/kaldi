#!/usr/bin/env perl

use warnings;

@ARGV == 3 || die "get_alignment_stats.pl <ecf> <raw kwlist> <csv>\n";

$BETA = 999.9;

($ecfFile, $kwlist, $csv) = @ARGV;

my $timeTotal = &loadEcf($ecfFile);

&load($kwlist);

&getTargets($csv);

&process($csv, $timeTotal);

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
#	int($start) == 0 || die "Need to skip data at the start\n$_\nstopped";
	
	$count++;
    }

    close IN;

    return $totalTime / 2;
}

sub load
{
    my ($file) = @_;

    my ($fileId, $tbeg, $dur, $score, $decision, $keyword, $tend, $label);

    open (IN, $file) || die "Cannot open $file\n";

    $_ = <IN>;

    while(<IN>)
    {
	if (/^<detected_kwlist kwid/)
	{
	    ($keyword) = / kwid=\"(\S+)\"/;
	    defined($keyword) || die "Unexpected format\n$_\nstopped";

	    while(<IN>)
	    {
		last if /<\/detected_kwlist>/;
		
		($fileId, $tbeg, $dur, $score, $decision) = /<kw file=\"(\S+)\" channel=\"1\" tbeg=\"([0-9\.]+)\" dur=\"([0-9\.]+)\" score=\"([0-9\.e\-\+]+)\" decision=\"([YESNO]+)\"/;
		defined($file) && defined($tbeg) && defined($dur) && defined($score) && 
		    defined($decision) || die "Unexpected format\n$_\nstopped";

		#die "Bad prob\n$_\nstopped" unless $score > 0.0;
		$tend = sprintf "%.2f", $tbeg + $dur;
		$tbeg = sprintf "%.2f", $tbeg;

		if (defined($rawHash{$fileId}{$keyword}{"$tbeg"}{"$tend"}))
		{
		    die "Dups\n$_\nstopped" if $score != $rawHash{$fileId}{$keyword}{"$tbeg"}{"$tend"};
		}
		else
		{
		    $rawHash{$fileId}{$keyword}{"$tbeg"}{"$tend"} = $score;
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
}

sub getTargets
{
    ##
    ## Keywords actually have to be present to be scored
    ##

    my ($file) = @_;

    my ($keyword);

    open (IN, $file) || die "Cannot open $file\n";

    $_ = <IN>;

    while(<IN>)
    {
	chomp;

	@array = split(/,/);
	@array == 12 || die "Unexpected format\n$_\nstopped";
	
	$keyword = $array[3];
	

	if (/,MISS$/ || /CORR$/)
	{
	    $refCount{$keyword} = 0 unless defined($refCount{$keyword});
	    $refCount{$keyword}++;
	}
    }

    close IN;
}

sub process
{
    my ($file, $T) = @_;

    my ($fileId, $keyword, $score, $tbeg, $tend, $hyp, $ref, $label, $scoreThisKW);
    my ($nMiss, $nCorr, $nFA, $nUnHyped, $cost, @array, @tokens, $nTokens, $dur);

    $nMiss = $nCorr = $nFA = $nUnHyped = 0;
    open (IN, $file) || die "Cannot open $file\n";

    $_ = <IN>;

    print "keyword prob score_this_keyword hyp ref\n";

    while(<IN>)
    {
	chomp;

	@array = split(/,/);
	@array == 12 || die "Unexpected format\n$_\nstopped";
	
	$array[2] == 1 || die "Unexpected channel Id\n$array[2]\nstopped";

	$fileId = $array[1];
	$keyword = $array[3];

	if (defined($refCount{$keyword}))
	{
	    $scoreThisKW = 1;
	    
	    $fom{$keyword} = 0 unless defined($fom{$keyword});
	}
	else
	{
	    $scoreThisKW = 0;
	}

	if (/,,MISS$/)
	{
	    $nUnHyped++;
	    $nMiss++;
	    print "$keyword unhyped miss\n";
	    next;
	}
	elsif (/YES,FA$/)
	{
	    $hyp = 1;
	    $ref = 0;

	    if ($scoreThisKW)
	    {
		$nFA++;
		$cost = $BETA /($T - $refCount{$keyword});
		$fom{$keyword} -= $cost;
	    }
	}
	#elsif (/NO,FA$/)
	elsif (/NO,CORR\!DET$/)
	{
	    $hyp = 0;
	    $ref = 0;
	}
	elsif (/YES,CORR$/)
	{
	    $nCorr++;
	    $hyp = 1;
	    $ref = 1;
	    $cost = 1 / $refCount{$keyword};
	    $fom{$keyword} += $cost;
	}
	elsif (/NO,MISS$/)
	{
	    $nMiss++;
	    $hyp = 0;
	    $ref = 1;
	}
	else
	{
	    die "Unexpected format\n$_\nstopped";
	}
	
	$tbeg = sprintf "%.2f", $array[7];
	$tend = sprintf "%.2f", $array[8];

	if (defined($rawHash{$fileId}{$keyword}{"$tbeg"}{"$tend"}))
	{
	    $score = $rawHash{$fileId}{$keyword}{"$tbeg"}{"$tend"};
	}
	else
	{
	    die "Missing hash\n$_\n$fileId $keyword $tbeg $tend\nstopped";
	}
	
	printf "$keyword %.6e $scoreThisKW $hyp $ref\n", $score;
	
    }

    close IN;

    print "Number of no hyp misses: $nUnHyped\n";
    print "Corr: $nCorr FAs $nFA Misses $nMiss\n";

    $count = $fom = 0;
    foreach $keyword (sort keys %fom)
    {
	$fom += $fom{$keyword};
	$count++;
    }
    printf "FOM: %.4f\n", $fom / $count;
}
