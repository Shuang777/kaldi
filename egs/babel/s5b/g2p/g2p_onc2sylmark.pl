#!/usr/bin/perl

$DELIMITER="=";

$hyphens=0;
if ($ARGV[0] eq "-h") {
    $hyphens=1;
    shift(@ARGV);
}

while(<>) {
    chomp;
    @phones=split;
    $state=0;
    @out=();
    foreach $p (@phones) {
	if ($p=~s/\/O$//) {
	    if ($state==1) {
		push(@out,".");
	    }
	    $state=0;
	    $p=~s/\/O$//;
	    push(@out,$p);
	} elsif ($p=~/\/N$/) {
	    if ($state==1) {
		push(@out,".");
	    }
	    $state=1;
	    $p=~s/\/N$//;
	    push(@out,$p);
	} else {
	    $p=~s/\/C$//;
	    push(@out,$p);
	}
    }

    if ($hyphens) {
	$out=join($DELIMITER,@out);
	$out=~s/$DELIMITER\.$DELIMITER/ /g;
	print $out,"\n";
    } else {
	print join(" ",@out),"\n";
    }
}

	    
	    
