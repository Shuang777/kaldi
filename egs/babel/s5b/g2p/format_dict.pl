#!/usr/bin/perl
# remove tones, and substitute # with . (view word boundaries as syllable boundaries)

while(<>) {
  chomp;
  ($word, @prons)=split(/\t/);
  $new_prons = "";
  foreach $p (@prons) {
    $p =~ s/ # / . /g;
    @syls=split(/ \. /,$p);
    $new_pron = "";
    foreach $syl (@syls) {
      $syl =~ s:^\s+::;
      $syl =~ s:\s+$::;
      $syl =~ s:\s+: :g;
      @original_phones = split(" ", $syl);
      $sylTag = "";
      $new_phones = "";
      while ($phone = shift @original_phones) {
        if ($phone =~ m:^\_\S+:) {
            # It is a tag; save it for later
            $is_original_tag{$phone} = 1;
            $sylTag .= $phone;
        } elsif ($phone =~ m:^[\"\%]$:) {
            # It is a stress marker; save it like a tag
            $phone = "_$phone";
            $is_original_tag{$phone} = 1;
            $sylTag .= $phone;
        } else {
          $new_phones .= " $phone";
        }
      }
      $new_phones =~ s:(\S+):$1${sylTag}:g;
      $new_pron .= $new_phones . " ."; # the tab added by Dan, to keep track of
                                       # syllable boundaries.
    }
    $new_pron =~ s:^\s+::;
    $new_pron =~ s: \.$::;
    $new_prons = "\t" . $new_pron;
  }
  print "$word$new_prons\n";
}
