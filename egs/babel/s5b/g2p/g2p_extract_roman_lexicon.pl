#!/usr/bin/perl

while(<>) {
    chomp;
    ($word,$yale,@pron)=split(/\t/);
    if ($word =~ /^[a-zA-Z][a-zA-Z]+$/ &&
	$word =~ /[a-z]/) {
	foreach $p (@pron) {
	    $p=~s/ \.//g;
	    @phones=split(/ /,$p);
	    for ($ph=0;$ph<=$#phones;$ph++) {
		if ($phones[$ph]=~/^[aeiouyEO6]/) {
		    $lastvowel=$ph;
		} elsif ($phones[$ph]=~/^[mnMN]/) {
		    $lastnasal=$ph;
		} elsif ($phones[$ph]=~/^_/) {
		    if (defined($lastvowel)) {
			$phones[$lastvowel].=$phones[$ph];
		    } else {
			$phones[$lastnasal].=$phones[$ph];
		    }
		    splice(@phones,$ph,1);
		    $ph--;
		    undef($lastvowel);
		    undef($lastnasal);
		}
	    }
	    print join("\t",$word,
		       join(" ",@phones)),"\n";	
	}
    }
}
		  
		    
