#!/usr/bin/perl
#
# Copyright   2013   Daniel Povey
# Apache 2.0

if (@ARGV != 2) {
  print STDERR "Usage: $0 <path-to-LDC2001S13> <path-to-output>\n";
  print STDERR "e.g. $0 /export/corpora5/LDC/LDC2001S13 data/swbd_cellular1_train\n";
  exit(1);
}
($db_base, $out_dir) = @ARGV;

if (system("mkdir -p $out_dir")) {
  die "Error making directory $out_dir";
}

open(MAP, "<$db_base/sw2p2_32/master.tbl") || die "Could not open $db_base/sw2p2_32/master.tbl";
while(<MAP>) {
  chomp;
  $line = $_;
  @A = split(" ", $line);
  $sph = $A[1];
  $fileid = $A[2];
  $map{$sph} = $fileid;
}

$tmp_dir = "$out_dir/tmp";
if (system("mkdir -p $tmp_dir") != 0) {
  die "Error making directory $tmp_dir";
}

if (system("find $db_base -name '*.sph' > $tmp_dir/sph.list") != 0) {
  die "Error getting list of sph files";
}

open(WAVLIST, "<", "$tmp_dir/sph.list") or die "cannot open wav list";

while(<WAVLIST>) {
  chomp;
  $sph = $_;
  @A = split("/", $sph);
  $basename = $A[$#A];
  $fileid = $map{$basename};
  $wav{$fileid} = $sph;
}

open(CS, "<$db_base/sw2p2_32/doc/callstat.tbl") || die  "Could not open $db_base/sw2p2_32/doc/callstat.tbl";
open(GNDR, ">$out_dir/spk2gender") || die "Could not open the output file $out_dir/spk2gender";
open(SPKR, ">$out_dir/utt2spk") || die "Could not open the output file $out_dir/utt2spk";
open(WAV, ">$out_dir/wav.scp") || die "Could not open the output file $out_dir/wav.scp";

@badAudio = ("40019", "45024", "40022");
$combBadAudio = join("|",@badAudio);

while (<CS>) {
  $line = $_ ;
  @A = split(",", $line);
  if ($A[0] =~ /($combBadAudio)/) {
    # do nothing 
  } else {
    $wavname = $A[0] . "_" . $A[2] . "_" . $A[3];
    $spkr1= "swc" . $A[1];
    $spkr2= "swc" . $A[2];
    $gender1 = $A[4];
    $gender2 = $A[5];
    if ($gender1 eq "M") {
      $gender1 = "m";
    } elsif ($gender1 eq "F") {
      $gender1 = "f";
    } else {
      die "Unknown Gender in $line";
    }
    if ($gender2 eq "M") {
      $gender2 = "m";
    } elsif ($gender2 eq "F") {
      $gender2 = "f";
    } else {
      die "Unknown Gender in $line";
    }
    if (exists $wav{$wavname}) {
      $wave = $wav{$wavname};
    } else {
      print STDERR "Missing $wavname\n";
      next
    }
    if (-e $wave) {
      $uttId = $spkr1 . "-swbdc_" . $wavname ."_1";
      if (!$spk2gender{$spkr1}) {
        $spk2gender{$spkr1} = $gender1;
        print GNDR "$spkr1"," $gender1\n";
      }
      print WAV "$uttId"," sph2pipe -f wav -p -c 1 $wave |\n";
      print SPKR "$uttId"," $spkr1","\n";

      $uttId = $spkr2 . "-swbdc_" . $wavname ."_2";
      if (!$spk2gender{$spkr2}) {
        $spk2gender{$spkr2} = $gender2;
        print GNDR "$spkr2"," $gender2\n";
      }
      print WAV "$uttId"," sph2pipe -f wav -p -c 2 $wave |\n";
      print SPKR "$uttId"," $spkr2","\n";
    } else {
      print STDERR "Missing $wave\n";
    }
  }
}


close(WAV) || die;
close(SPKR) || die;
close(GNDR) || die;
if (system("utils/utt2spk_to_spk2utt.pl $out_dir/utt2spk >$out_dir/spk2utt") != 0) {
  die "Error creating spk2utt file in directory $out_dir";
}
if (system("utils/fix_data_dir.sh $out_dir") != 0) {
  die "Error fixing data dir $out_dir";
}
if (system("utils/validate_data_dir.sh --no-text --no-feats $out_dir") != 0) {
  die "Error validating directory $out_dir";
}
