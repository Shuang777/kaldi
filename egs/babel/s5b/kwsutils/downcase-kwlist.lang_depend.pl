#!/usr/bin/env perl
#
# Downcase a kwlist file, optionally with language-dependent normalization.
#

use strict;
use FileHandle;
use Encode;
use File::Basename;
use Swordfish::Normalization;

binmode(STDOUT,":utf8");
binmode(STDERR,":utf8");

my $KwList;

if ($#ARGV == 0) {
    $KwList = shift;
} else {
    usage();
}

my $BABEL_LANG;

my $KwList_filename = `basename $KwList`;
chop($KwList_filename);
$BABEL_LANG = `babelname -lang $KwList_filename`;
chop($BABEL_LANG);

downcase($KwList);

sub usage {
    print STDERR "Usage: $0 babel105b-v0.4_conv-eval.kwlist2.xml\n\n";
    print STDERR "Downcase a kwlist file, optionally with language-dependent normalization.\n\n";
    exit(1);
}

sub downcase {
    my($n) = @_;
    my($fh, $line, $kwtext);
    $fh = new FileHandle($n) or die "Couldn't open $n: $!";
    $fh->binmode(":utf8");
    while ($line = <$fh>) {
	chomp($line);
	if ($line =~ /^(\s*<kwtext>)(.*)(<\/kwtext>\s*)$/) {
            if ($BABEL_LANG eq "Turkish") {
                $kwtext = Swordfish::Normalization::turkish_lc($2);
            } else {
                $kwtext = lc($2);
            }
	    print "$1" . "$kwtext" . "$3\n";
        } else {
	    print "$line\n";
	}
    }
    $fh->close();
}

