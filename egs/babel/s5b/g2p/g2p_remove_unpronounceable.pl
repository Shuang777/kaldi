#!/usr/bin/perl

while(<>) {
    chomp;
    ($letters,$prons)=split("\t");
    $letters=~s/[-_\'] *//g;
    print "$letters\t$prons\n";
}
