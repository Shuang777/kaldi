#!/usr/bin/perl

# change reserved pronunciaiton symbols

while(<>) {
  ($word,@prons)=split("\t",$_);
  foreach $p (@prons) {
    $p=~s/\|\\/vbar\\/g;
  }
  print join("\t",$word,@prons);
}
