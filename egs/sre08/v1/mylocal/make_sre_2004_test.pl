#!/usr/bin/perl
#
# Copyright 2014  David Snyder
# Apache 2.0.

if (! -f "data/local/sre04_key-v2.txt") {
  `mkdir -p data/local/`;
  `wget -P data/local/ http://www.openslr.org/resources/10/sre04_key-v2.txt.gz`;
  `gunzip data/local/sre04_key-v2.txt.gz`;
}

if (@ARGV != 2) {
  print STDERR "Usage: $0 <path-to-LDC2011S09> <path-to-output>\n";
  print STDERR "e.g. $0 /export/corpora5/LDC/LDC2011S09 data\n";
  exit(1);
}

($db_base, $out_dir) = @ARGV;
$out_dir = "$out_dir/sre04_test";

if (system("mkdir -p $out_dir")) {
  die "Error making directory $out_dir";
}

open(TRIALS, "<data/local/sre04_key-v2.txt")
  or die "Could not open data/local/sre04_key-v2.txt";
open(GNDR,">", "$out_dir/spk2gender")
  or die "Could not open the output file $out_dir/spk2gender";
open(SPKR,">", "$out_dir/utt2spk")
  or die "Could not open the output file $out_dir/utt2spk";
open(WAV,">", "$out_dir/wav.scp")
  or die "Could not open the output file $out_dir/wav.scp";

$data_src_suffix =`basename \$\(dirname $db_base\)`;
chomp ($data_src_suffix);

%types = ();
while($line=<TRIALS>) {
  @attrs = split(" ", $line);
  $basename = $attrs[0];
  $side = uc $attrs[3];
  $testType = $attrs[4];
  $spkr = $attrs[5] . "_$data_src_suffix";
  $gender = lc $attrs[6];
  print GNDR "$spkr $gender\n";
  $wav = $db_base."/wavfiles/test/$basename.sph";
  $basename =~ s/.sph//;
  $uttId = $spkr . "-" . $basename . "_" . $side;
  if ( $side eq "A" || $side eq "X1" ) {
    $channel = 1;
  } elsif ( $side eq "B" || $side eq "X2" ) {
    $channel = 2;
  } else {
    die "unknown channel $side\n";
  }
  if ($wav && -e $wav) {
    print WAV "$uttId"," sph2pipe -f wav -p -c $channel $wav |\n";
    $types{$uttId} = $testType;
    print SPKR "$uttId"," $spkr","\n";
  } else {
    print STDERR "Missing $wav\n";
  }
}
close(GNDR) || die;
close(SPKR) || die;
close(WAV) || die;
close(TRIALS) || die;

if (system(
  "utils/utt2spk_to_spk2utt.pl $out_dir/utt2spk >$out_dir/spk2utt") != 0) {
  die "Error creating spk2utt file in directory $out_dir";
}
  system("utils/fix_data_dir.sh $out_dir");
if (system(
  "utils/validate_data_dir.sh --no-text --no-feats $out_dir") != 0) {
  die "Error validating directory $out_dir";
}
exit(0);

@type_list = ("1s"); 
foreach $type (@type_list) {
  $type_out_dir = $out_dir . "_" . $type;
  mkdir $type_out_dir;
  system("cp $out_dir/wav.scp $type_out_dir");
  system("cp $out_dir/spk2gender $type_out_dir");
  system("cp $out_dir/spk2utt $type_out_dir");
  open(SPKR,"< $out_dir/utt2spk")
    or die "Could not open the input file $out_dir/utt2spk";
  open(SPKRT,">", "$type_out_dir/utt2spk")
    or die "Could not open the output file $type_out_dir/utt2spk";
  while($line = <SPKR>) {
    chomp($line);
    @attrs = split(" ", $line);
    $uttId = $attrs[0];
    $spkr = $attrs[1];
    if ($types{$uttId} eq $type) {
      print SPKRT "$uttId"," $spkr","\n";
    }
  }
  system("utils/fix_data_dir.sh $type_out_dir");
}

