#!/usr/bin/env perl

use warnings;

@ARGV > 0 || die "gather_search_results.pl <search result files>\n";

my $results = shift @ARGV;

my ($header) = &load($results);

foreach $results (@ARGV)
{
    &load($results);
}

@keywords = sort keys %headerHash;

&process($header, @keywords);

exit;

sub process
{
    my ($header, @keyords) = @_;

    my ($keyword, $file, $start, $dur, $prob);

    print $header;

    foreach $keyword (@keywords)
    {
	print $headerHash{$keyword};

	print $recordHash{$keyword} if defined($recordHash{$keyword});
	
	print "</detected_kwlist>\n";
    }
    
    print "</kwslist>\n";
}

sub load
{
    my ($file) = @_;

    my ($fileId, $tbeg, $dur, $score, $decision, $keyword, $tend, $header, $record);

    open (IN, $file) || die "Cannot open $file\n";

    $header = <IN>;

    while(<IN>)
    {
	if (/^<detected_kwlist kwid/)
	{
	    ($keyword) = / kwid=\"(\S+)\"/;
	    defined($keyword) || die "Unexpected format\n$_\nstopped";
	    $headerHash{$keyword} = $_;

	    while(<IN>)
	    {
		last if /<\/detected_kwlist>/;
		
		# The fields can get switched around by various processing scripts
		# Try the default ordering and if that fails, try alphabetical...
		$valid = 0;
		($fileId, $tbeg, $dur, $score, $decision) = /<kw file=\"(\S+)\" channel=\"1\" tbeg=\"([0-9\.]+)\" dur=\"([0-9\.]+)\" score=\"([0-9\.e\-\+]+)\" decision=\"([YESNO]+)\"/;
		
		if (defined($fileId) && defined($tbeg) && defined($dur) && defined($score) && 
		    defined($decision))
		{
		    $valid = 1;
		}
		else # try alphabetical order...
		{
                    ($decision, $dur, $fileId, $score, $tbeg) = /<kw channel=\"1\" decision=\"([YESNO]+)\" dur=\"([0-9\.]+)\" file=\"(\S+)\" score=\"([0-9\.e\-\+]+)\" tbeg=\"([0-9\.]+)\"/;
                    if (defined($fileId) && defined($tbeg) && defined($dur) && defined($score) && 
                        defined($decision)) 
                    {
                        $valid = 1;
                    }
                }

		$valid != 0 || die "Unexpected format\n$_\nstopped";
		
		next unless $score > 0; 
	
		$recordHash{$keyword} = "" unless defined($recordHash{$keyword});
		
		$recordHash{$keyword} .= sprintf "<kw file=\"$fileId\" channel=\"1\" tbeg=\"%.2f\" dur=\"%.2f\" score=\"%.6e\" decision=\"$decision\"\/>\n", $tbeg, $dur, $score;
	
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

