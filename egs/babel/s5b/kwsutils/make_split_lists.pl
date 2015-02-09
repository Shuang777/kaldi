#!/usr/bin/env perl

use warnings;

@ARGV == 3 || die "get_kws.pl <search result file list> <njobs> <outbase>\n";

($fileList, $njobs, $outBase) = @ARGV;

$njobs > 0 || die "njobs < 0!!\n";

open(LIST, $fileList) || die "Cannot open $fileList\n";

@results = ();
while(<LIST>)
{
    chomp;
    push(@results, $_);
}

close LIST;

foreach $results (@results)
{
    &load($results);
}

@keywords = sort keys %kwHash;

$kwsPerFile = int(($#keywords + 1) / $njobs);

for($i=0; $i<$njobs; $i++)
{
    open(OUT, ">${outBase}_in.$i") || die "Cannot open ${outBase}_in.$i\n";
    
    for($j=0; $j<$kwsPerFile; $j++)
    {
	$keyword = shift @keywords;
	print OUT "$keyword\n";
    }

    print OUT join("\n", @keywords), "\n" if $i == $njobs - 1; 
    close OUT;
}

open(OUT, ">${outBase}_in.list") || die "Cannot open ${outBase}_in.list\n";

for($i=0; $i<$njobs; $i++)
{
    print OUT "${outBase}_in.$i\n";
}

close OUT;

open(OUT, ">${outBase}_out.list") || die "Cannot open ${outBase}_in.list\n";

for($i=0; $i<$njobs; $i++)
{
    print OUT "${outBase}_out.$i\n";
}

close OUT;


exit;

sub load
{
    my ($file) = @_;

    my ($keyword);

    open (IN, $file) || die "Cannot open $file\n";

    while(<IN>)
    {
	if (/^<detected_kwlist kwid/)
	{
	    ($keyword) = / kwid=\"(\S+)\"/;
	    defined($keyword) || die "Unexpected format\n$_\nstopped";
	    $kwHash{$keyword} = $_;
	}
    }

    close IN;    
}

