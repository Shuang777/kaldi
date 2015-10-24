#!/usr/bin/perl

while(<>) {
    @outg=();
    @outs=();
    @endoutg=();
    @endouts=();

    chomp;
    ($grapheme,$syllables)=split(/	/);
    @g=split(/ /,$grapheme);
    @s=split(/ /,$syllables);

    # try to peel syllables off the front

    $done=0;
    while (!$done) {
	if ($g[0] =~ /\+$/ || $g[0] =~ /^x[a-f0-9][a-f0-9]+/) {
	    push(@outg,shift(@g));
	    push(@outs,shift(@s));
	} elsif ($g[0] eq "_") {
	    shift(@g);
	} else {
	    $done=1;
	}
    }

    # try to peel syllables off the back
    $done=0;
    while (!$done) {
	if ($g[$#g] =~ /\+$/ || $g[$#g] =~ /^x[a-f0-9][a-f0-9]+/) {
	    unshift(@endoutg,pop(@g));
	    unshift(@endouts,pop(@s));
	} elsif ($g[$#g] eq "_") {
	    pop(@g);
	} else {
	    $done=1;
	}
    }

    $s=join(" ",@s);
    
    if ($#g>=0) {
	$s=~s/_/ /g;
    }


    $outg=join(" ",@outg,@g,@endoutg);
    $outg=~s/^ //;
    $outg=~s/  */ /g;
    $outg=~s/ *$//;

    $outs=join(" ",@outs,$s,@endouts);
    $outs=~s/^ //;
    $outs=~s/  */ /g;
    $outs=~s/ *$//;

    print "$outg\t$outs\n";
}

	
