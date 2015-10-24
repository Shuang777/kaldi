#!/usr/bin/perl

while(<>) {
  chomp;
  ($word, @pron)=split(/\t/);
  foreach $p (@pron) {
    @syls=split(/ \. /,$p);
    foreach $s (@syls) {
      @phones=split(/ /,$s);
      $tone=pop(@phones);
      $tone=~s/_/-/;

      $tone_found=0;
      foreach $ph (@phones) {
        if ($ph =~ /^[aeiouyAEIOUY6910\@]/) {
          $ph=$ph.$tone;
          $tone_found=1;
        }
      }
      if (!$tone_found) {
        for ($i=$#phones;$i>0;$i--) {
          if ($phones[$i] =~ /^[Nm]/) {
            $phones[$i]=$phones[$i].$tone;
            break;
          }
        }
      }
      $s=join(" ",@phones);
    }
  $p=join(" . ",@syls);
  }

  print "$word\t",join("\t", @pron),"\n";
}
