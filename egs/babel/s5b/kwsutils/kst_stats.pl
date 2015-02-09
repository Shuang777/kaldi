#!/usr/bin/env perl

use warnings;

$BETA = 999.9;

$MAX_PROB = 0.999;

@ARGV == 2 || die "kst_stats.pl <ecf file> <stats file>\n";

($ecfFile, $stats) = @ARGV;

my $timeTotal = &loadEcf($ecfFile);

&load($stats);

#Restrict to KWs that occur in the data 
@keywords = sort keys %count;

$total = 0;
foreach $keyword (@keywords)
{
    #We may never have hyped a keyword
    if (defined($dataHash{$keyword}))
    {
    &process($keyword, $timeTotal);
    }

    $total++;
}

#Restrict to KWs where we have hyps
@keywords = sort keys %fomHash;

&dump($total, @keywords);

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
    
    $count++;
    }

    close IN;

    return $totalTime / 2;
}

sub dump
{
    my ($kwTotal, @keywords) = @_;

    my ($keyword, $fom, $prob, @probs, $i, $j, @kwFom, $max, $maxIndex, @fomArray, $thresh);
    my (@kwProbs, $decision_fom, $decision_thresh);

    $decision_thresh = sprintf "%.6e", exp(-1);
    $decision_fom = 0;

    #descending order
    @probs = sort {$b <=> $a} keys %probToKW;

    for($j=0; $j<=$#keywords; $j++)
    {
    $kwFom[$j] = 0;
    }

    $maxIndex = -1;
    $thresh = 1.1;
    $max = -10000000000;
    @fomArray = ();
    for($i=0; $i<=$#probs; $i++)
    {
    $fom = 0;
    for($j=0; $j<=$#keywords; $j++)
    {
        if (defined($fomHash{$keywords[$j]}) && defined($fomHash{$keywords[$j]}{$probs[$i]}))
        {
        $kwFom[$j] = $fomHash{$keywords[$j]}{$probs[$i]};
        delete $fomHash{$keywords[$j]}{$probs[$i]};
        }

        $fom += $kwFom[$j];
    }
    
    $fom /= $kwTotal;

    if ($probs[$i] >= $decision_thresh)
    {
        $decision_fom = $fom;
    }

    if ($fom > $max)
    {
        $max = $fom;
        $maxIndex = $i;
        $thresh = $probs[$i];
    }
 
    }

    # Sanity check
    for($j=0; $j<=$#keywords; $j++)
    {
    @kwProbs = sort {$b <=> $a} keys %{ $fomHash{$keywords[$j]} };
    next unless @kwProbs > 0;
    $kwProbs[0] < $probs[$#probs] || die 
        "bad stuff $keywords[$j] $kwProbs[0] $probs[$#probs]\nstopped";
    }
    

    printf "Best FOM: %.4f Thresh: %.6e Index: $maxIndex nProbs: $#probs Min prob: %.6e\n", $max, $thresh, $probs[$#probs];
    printf "Decision FOM: %.4f Thresh: %.6f\n", $decision_fom, $decision_thresh;
}

sub process
{
    my ($keyword, $totalTime) = @_;
    
    my ($faCost, $hitBen, $ref, $prob, @probs, $fom, @fomArray, $i, $totalProb);
    my (@kws, $threshold, $neg_log_threshold);

    $time_beta_ratio = $totalTime / $BETA;

    $faCost = -$BETA / ($totalTime - $count{$keyword});
    $hitBen = 1 / $count{$keyword};
    
    #descending order
    @probs = sort {$b <=> $a} keys %{ $dataHash{$keyword} };
    
    #scores
    #@probs = sort {$a <=> $b} keys %{ $dataHash{$keyword} };
    
    @fomArray = ();
    $fom = 0;
    $totalProb = 0;
    foreach $prob (@probs)
    {
    $fom += $dataHash{$keyword}{$prob}{1} * $hitBen + 
        $dataHash{$keyword}{$prob}{0} * $faCost;
    push(@fomArray, $fom);

    $totalProb += $prob * ($dataHash{$keyword}{$prob}{1} + 
                   $dataHash{$keyword}{$prob}{0});

    delete $dataHash{$keyword}{$prob}{1};
    delete $dataHash{$keyword}{$prob}{0};
    delete $dataHash{$keyword}{$prob};
    }

    delete $dataHash{$keyword};
    $totalProb > 0 || die "Bad probs stopped";

    $threshold = $totalProb /($time_beta_ratio + ($BETA - 1) * $totalProb / $BETA);
    
    $neg_log_threshold = -1.0 * log($threshold);

    for($i=0; $i<=$#probs; $i++)
    {
    # only need to worry about prob above the decision threshold
    last if $probs[$i] < $threshold;

    $probs[$i] = sprintf "%.6e", exp(log($probs[$i]) / $neg_log_threshold);
    
    $probToKW{"$probs[$i]"} = 1;

    # If dups (from mapping using sprintf above) take the fom
    # from the lower prob
    
    $fomHash{$keyword}{"$probs[$i]"} = $fomArray[$i];
    }

}

sub load
{
    my ($file) = @_;
    
    my ($keyword, $prob, $ref, $keep);

    open(IN, $file) || die "cannot open $file\n";
    
    while(<IN>)
    {
    next unless /^[KWTERM0-9\-]+/;
    
    ($keyword) = /^([KWTERM0-9\-]+) /;
    defined($keyword) || die "Unexpected format\n$_\nstopped";

    $totalProb{$keyword} = 0 unless defined($totalProb{$keyword});

    if (/unhyped miss/)
    {
        $count{$keyword} = 0 unless defined($count{$keyword});
        $count{$keyword}++;
    }
    else
    {
        chomp;
        ($prob, $keep, $ref) = 
        /^[KWTERM0-9\-]+ ([0-9\.e\-\+]+) ([01]) [01] ([01])$/;
        defined($prob) && defined($keep) && defined($ref) || die 
        "Unexpected format\n$_\nstopped";

        next unless $keep == 1;

        $count{$keyword} = 0 unless defined($count{$keyword});
        $count{$keyword}++ if $ref == 1;

        $prob = $MAX_PROB if $prob > $MAX_PROB;
        
        $totalProb{$keyword} += $prob;

        $dataHash{$keyword}{$prob}{0} = 0 unless
        defined($dataHash{$keyword}{$prob}{0});
        $dataHash{$keyword}{$prob}{1} = 0 unless
        defined($dataHash{$keyword}{$prob}{1});
        $dataHash{$keyword}{$prob}{$ref}++;

    }
    }
    
    close IN;
}

