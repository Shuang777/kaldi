#!/usr/bin/perl

#TODO: write out FST mapping syllable position to ONC, FSA constraining types

# Usage: $0 fst-model dictionary constrainer-model
$fst=$ARGV[0];
$dict=$ARGV[1];
$outfst=$ARGV[2];
$tmpdir=$ARGV[3];

$prefix="$tmpdir/g2p_buildsyl.$$";
$syms="$prefix.osyms";
$mapper="$prefix.mapper.fst";
$oncphsyms="$prefix.oncphsyms";
$oncsyms="$prefix.oncsyms";
$oncmapper="$prefix.oncmapper.fst";
$oncconstraint="$prefix.onc.fsa";
$jointfst="$prefix.joint.fst";

%type=("<eps>"=>{});

# Step 0: ensure that dictionary does not have a romanization column
$romanized=1;
open(DICT,$dict);
while(<DICT>) {
  ($word,$cand,$rest)=split(/\t/);
  @c=split(/ +/,$cand);
  if ($#c>0) {
    $romanized=0;
    last;
  }
}
close(DICT);


# Step 1: Open dictionary, and syllabify.  Store syllable patterns as
#         well as what letters can be onset/nucleus/coda

open(DICT,$dict) || die("Can't open dictionary $dict for reading");
while(<DICT>) {
  chomp;
  ($word,@prons)=split(/\t/);
  shift(@prons) if $romanized;  #NB Special processing determined in step 0
  foreach $pron (@prons) {
    @p=split(/ /,$pron);
    $seennuc=0;
    $pattern="";
    foreach $p (@p) {
      if ($p =~ /^[\.\#]/) {
        $seennuc=0;
        if ($pattern ne "") {
          $patterntotal++;
          $patterncount{$pattern}++;
        }
        $pattern="";
      } else {
        $class=&phoneclass($p);
        if ($class eq "V") {
          $pattern=$pattern."N";
          $seennuc=1;
          &register($p,"N");
        } elsif ($class eq "C") {
          if ($seennuc) {
            $pattern=$pattern."C";
            &register($p,"C");
          } else {
            $pattern=$pattern."O";
            &register($p,"O");
          }
        } 
      }
    }
    if ($pattern ne "") {
      $patterntotal++;
      $patterncount{$pattern}++;
    }
  }
}
close(DICT);        
  
# Step 2: Read in the output symbols from the G2P fst.  These are phones,
#         or possibly multiphones separated by |.  Note that | can occur
#         by itself as a symbol, so needs to be handled separately.
#
#         Write out: (a) a symbol set of phone+ONC, (b) a mapping from
#         multiphones to phone+ONC symbols
#
# NB: May want in future to have the separator symbol as an option.
#

# write out multiphone symbol set
&system_wcheck("fstsymbols --save_osymbols=$syms $fst /dev/null");


# write out PH+ONC symbols
# at the same time, write the PH to ONC mapper
open(ONCPHSYMS,">$oncphsyms") || die("Can't open $oncphsyms for writing");
open(ONCMAPPER,">$oncmapper.txt") || die("Can't open $oncmapper.txt for writing");
@oncphsyms=();
foreach $ph (keys %type) {
  @t=keys %{$type{$ph}};
  if ($#t<0) {  # <eps> symbol
    push(@oncphsyms,$ph);
  } else {
    foreach $t (@t) {
      push(@oncphsyms,"$ph/$t");
      print ONCMAPPER "0 0 $ph/$t $t\n";
    }
  }
}
@oncphsymssort=sort bysymbol @oncphsyms;
for($i=0;$i<=$#oncphsymssort;$i++) {
  print ONCPHSYMS "$oncphsymssort[$i]\t$i\n";
}
close(ONCPHSYMS);
print ONCMAPPER "0\n";
close(ONCMAPPER);
open(ONCSYMS,">$oncsyms") || die("Can't open $oncsyms for writing");
print ONCSYMS "<eps>\t0\n";
print ONCSYMS "O\t1\n";
print ONCSYMS "N\t2\n";
print ONCSYMS "C\t3\n";
close(ONCSYMS);
&system_wcheck("fstcompile --isymbols=$oncphsyms --osymbols=$oncsyms --keep_isymbols=true --keep_osymbols=true $oncmapper.txt $oncmapper.tmp");
&system_wcheck("fstarcsort --sort_type='olabel' $oncmapper.tmp $oncmapper ");


# Create the mapper fst
$statecounter=1;
open(SYMS,"$syms") || die("Can't open $syms for reading");
open(MAPPER,">$mapper.txt") || die("Can't open $mapper.txt for writing");

while(<SYMS>) {
  chomp;
  ($sym,$num)=split;
  if ($sym eq "|") {
    @sparts=($sym);
  } else {
    @sparts=split(/\|/,$sym);
  }

  # iterate over phones and create an fst
  $cur=0; 
  $printsym=$sym;
  for ($si=0;$si<=$#sparts;$si++) {
    if ($si==$#sparts) {
      $next=0;
    } else {
      $next=$statecounter;
      $statecounter++;
    }
    if (defined($type{$sparts[$si]})) {
      foreach $t (keys %{$type{$sparts[$si]}}) {
        print MAPPER "$cur $next $printsym $sparts[$si]/$t\n";
      }
    } else {
      print MAPPER "$cur $next $printsym <eps>\n";
    }
    $cur=$next;
    $printsym="<eps>";
  }
}

print MAPPER "0\n";
close(MAPPER);

# compile to binary
&system_wcheck("fstcompile --isymbols=$syms --osymbols=$oncphsyms --keep_isymbols=true --keep_osymbols=true $mapper.txt $mapper.tmp");
&system_wcheck("fstarcsort --sort_type='olabel' $mapper.tmp $mapper");

# Step 3: Write out constraints provided by syllable structures

open(ONCCONSTRAINT,">$oncconstraint.txt") || die("Can't open $oncconstraint.txt for writing.");
$statecounter=1;
# score is neglog(patterncount / patterntotal)
# which is the same as log(patterntotal)-log(patterncount)
#
$lpt=log($patterntotal);
foreach $pattern (keys %patterncount) {
  @pparts=split(//,$pattern);
  $cur=0;
  for ($pix=0;$pix<=$#pparts;$pix++) {
    if ($pix==$#pparts) {
      $next=0;
    } else {
      $next=$statecounter;
      $statecounter++;
    }
    if ($pix==0) {
      $score=sprintf("%.6g",$lpt-log($patterncount{$pattern}));
    } else {
      $score=0;
    }
    print ONCCONSTRAINT "$cur $next $pparts[$pix] $score\n";
    $cur=$next;
  }
}
print ONCCONSTRAINT "0\n";
close(ONCCONSTRAINT);

&system_wcheck("fstcompile --acceptor=true --isymbols=$oncsyms --keep_isymbols --keep_osymbols $oncconstraint.txt $oncconstraint.tmp");
&system_wcheck("fstarcsort --sort_type='ilabel' $oncconstraint.tmp $oncconstraint");

# Step 4: now build a constraint fst and project to the input side

#&system_wcheck("fstcompose $mapper $oncmapper | fstarcsort --sort_type='olabel' | fstcompose - $oncconstraint | fstproject --project_output=false - $jointfst");
&system_wcheck("fstcompose $oncmapper $oncconstraint | fstproject --project_output=false - | fstarcsort --sort_type='ilabel' | fstcompose $mapper - $jointfst");
#&system_wcheck("fstcompose $mapper $oncmapper | fstproject --project_output=true - | fstarcsort --sort_type='olabel' | fstcompose - $oncconstraint | fstproject --project_output=false - $jointfst");


# Step 5: finally, compose with original FST to provide constraints

&system_wcheck("fstarcsort --sort_type='olabel' $fst | fstcompose - $jointfst | fstarcsort - $outfst");

#unlink("$mapper");
#unlink("$mapper.tmp");
#unlink("$oncconstraint");
#unlink("$oncconstraint.txt");
#unlink("$oncmapper");
#unlink("$jointfst");
#unlink("$oncmapper.txt");
#unlink("$mapper.txt");
#unlink($oncsyms);
#unlink($syms);
#unlink($oncphsyms);

exit(0);

sub phoneclass {
  my $a=shift(@_);

  if ($a =~ /^[aeiuo36AEIOUV\{\@]/) {
    return "V";
  } elsif ($a =~ /^[[:alnum:]\?]/) {
    return "C";
  } else {
    return "O";
  }
}

sub register {
  my $phone=shift(@_);
  my $class=shift(@_);

  $type{$phone}={} if !defined($type{$phone});
  $type{$phone}->{$class}=1;
}


sub bysymbol {
  if ($a eq $b) {
    return 0;
  } elsif ($a eq "<eps>") {
    return -1;
  } elsif ($b eq "<eps>") {
    return 1;
  } elsif ($a eq "|") {
    return -1;
  } elsif ($b eq "|") {
    return 1;
  } elsif ($a eq "<phi>") {
    return -1;
  } elsif ($b eq "<phi>") {
    return 1;
  } else {
    return $a cmp $b;
  }
}

sub system_wcheck {
  system($_[0]);
  if ($? == 0) {
    return;
  }
  if ($? == -1) {
    die("$0: failed to execute '$_[0]': $!\n");
  } elsif ($? & 127) {
    my $signal=$? & 127;
    die("$0: child died with signal $signal.\n\tWas executing '$_[0]'.\n");
  } else {
    $exitcode=$?>>8;
    die("child exited with value $exitcode\n\tWas executing '$_[0]'.\n");
  }
}
