#!/usr/bin/perl -w

if (@ARGV != 1) {
  die "Usage: $0 <fileBaseName> \n";
}

$fileBaseName = $ARGV[0];

@lines = `grep '(code ' $fileBaseName.*.log | grep -v '(code 0)'`;

foreach $line (@lines) {
  $line =~ m/^([^:]+):.*/;
  $file = $1;

  $childpid = fork();
  if (!defined $childpid) { die "Error forking in slurm.pl (writing to $logfile)"; }
  if ($childpid == 0) { # We're in the child... this branch
    # executes the job and returns (possibly with an error status).
    open (LOGF, "<$file");
    $logfile = $file . ".re";
    print "$logfile\n";

    $firstLine = <LOGF>;
    $firstLine =~ s/^# //;
    open(F, ">$logfile") || die "Error opening log file $logfile";
    if ($firstLine =~ m/srun/) {
      open(B, "|-", "$firstLine") || die "Error opening shell command";
      $cmd = <LOGF>;
      $cmd =~ s/^# //;
      print F "# " . $firstLine . "\n";
      print F "# " . $cmd . "\n";
    } else {
      open(B, "|-", "bash") || die "Error opening shell command";
      $cmd = $firstLine;
      print F "# " . $cmd . "\n";
    }
    print F "# Started at " . `date`;
    $starttime = `date +'%s'`;
    print F "#\n";
    close(F);
    print B "( " . $cmd . ") 2>>$logfile >> $logfile";
    close(B);                   # If there was an error, exit status is in $?
    close(LOGF);
    $ret = $?;

    $endtime = `date +'%s'`;
    open(F, ">>$logfile") || die "Error opening log file $logfile (again)";
    $enddate = `date`;
    chop $enddate;
    print F "# Ended (code $ret) at " . $enddate . ", elapsed time " . ($endtime-$starttime) . " seconds\n";
    close(F);
    exit($ret == 0 ? 0 : 1);
  }
}

$ret = 0;
$numfail = 0;
foreach $line (@lines) {
  $r = wait();
  if ($r == -1) { die "Error waiting for child process"; } # should never happen.
  if ($? != 0) { $numfail++; $ret = 1; } # The child process failed.
}

if ($ret != 0) {
  $njobs = @line;
  if ($njobs == 1) { 
    print STDERR "slurm.pl: job failed, log is in $logfile\n";
    if ($logfile =~ m/JOB/) {
      print STDERR "slurm.pl: probably you forgot to put JOB=1:\$nj in your script.\n";
    }
  }
  else {
    if (defined $jobname) {
      $logfile =~ s/$jobname/*/g;
    }
    print STDERR "slurm.pl: $numfail / $njobs failed, log is in $logfile\n";
  }
}
exit ($ret);
