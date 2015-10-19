#!/usr/bin/perl -w
# Korbinian Riedhammer, Hang Su
# There are two modes to run parallel jobs.888888
# In the first mode 'cmdline', you can do (e.g.)
#  slurm.pl JOB=1:4 some.JOB.log a b c JOB
#  slurm.pl some.log a b c JOB
# this is like running the command 'a b c JOB'
# and putting it in some.JOB.log, for each one. 
# [Note: JOB can be any identifier, and it will be substituted by 1:4].
# If any of the jobs fails, this script will fail.
# Another example is:
#  slurm.pl JOB=1 some.log my-prog "--opt=foo bar" foo \|  other-prog baz
# and slurm.pl will run something like:
# ( my-prog '--opt=foo bar' foo |  other-prog baz ) >& some.log
# 
# The second mode 'script' run parallel jobs in a script, e.g.
#  slurm.pl some.log -f scriptfile
# this will take scriptfile and read each line in it as a separate cmdline,
# run them in parallel and write log to some.log.xx
# note that current script restrict jobs perbatch to be less than or equal to 64

use POSIX ":sys_wait_h";

@ARGV < 2 && die "usage: slurm.pl log-file command-line arguments...";

$SIG{INT}  = \&signal_handler;

$totaljobstart=1;
$totaljobend=1;
$threadsperjob=1;
$jobsperbatch=0;
$gpuarg = '';
$memfreearg = '';
$mode = 'cmdline';	# 'cmdline' is the default mode
%childpids = ();
$killmode = "strict";

sub roundup {
  my $n = shift;
  return(($n == int($n)) ? $n: int($n+1))
}

sub signal_handler {
  print "Here it caught signal $!\n";
  for my $childpid (values %childpids) {
    print "Killing child $childpid\n";
    kill('TERM', $childpid);
  }
}

if (@ARGV > 0) {
  while (@ARGV >= 2 && $ARGV[0] =~ m:^-:){ # parse any options
    $switch = shift @ARGV;
    if ($switch eq '-tc'){
      $jobsperbatch = shift @ARGV;
    } elsif ($switch eq '--max-jobs-run') {
      $jobsperbatch = shift @ARGV;
    } elsif ($switch eq '-pe'){
      $indicator = shift @ARGV;
      if($indicator ne 'smp'){
        print STDERR "argument -pe must be followed by smp!\n";
        exit(1);
      } else {
        $threadsperjob = shift @ARGV;
      }
    } elsif ($switch eq '--num-threads'){
      $threadsperjob = shift @ARGV;
    } elsif ($switch eq '-l'){
      $specifications = shift @ARGV;
      @specifics = split(/,/, $specifications);
      while (@specifics > 0) {
        $thisspec = shift @specifics;
        @argdetail = split(/=/, $thisspec);
        if ($argdetail[0] eq 'gpu') {
          $gpuarg = "--gres=gpu:$argdetail[1] -x kajiki[1-4]";
        } elsif ($argdetail[0] eq 'mem_free') {
          $memnumber = $argdetail[1];
          if ($memnumber =~ /^(\d+)\.?(\d*)G$/){
            $memnumber =~ s/G//;
            $memnumber = roundup($memnumber * 1024);
            $memfreearg = "--mem=$memnumber";
          } elsif ($memnumber =~ /^(\d+)\.(\d*)MB$/){
            $memnumber =~ s/MB//;
            $memnumber = roundup($memnumber);
            $memfreearg = "--mem=$memnumber";
          } else {
            print STDERR "argument $thisspec not correctly parsed!\n";
            exit(1);
          }
        } elsif ($argdetail[0] eq 'ram_free') {
          # we don't do anything
        } else {
          print STDERR "argument $thisspec not correctly parsed!\n";
          exit(1);
        }
      }
    } elsif ($switch eq '--loose') {
      $killmode = "loose";
    }
  }

  if ($ARGV[0] =~ m/^([\w_][\w\d_]*)+=(\d+):(\d+)$/) { # e.g. JOB=1:10
    $jobname = $1;
    $totaljobstart = $2;
    $totaljobend = $3;
    shift;
    if ($totaljobstart > $totaljobend) {
      die "slurm.pl: invalid job range $ARGV[0]";
    }
  } elsif ($ARGV[0] =~ m/^([\w_][\w\d_]*)+=(\d+)$/) { # e.g. JOB=1
    $jobname = $1;
    $totaljobstart = $2;
    $totaljobend = $2;
    shift;
  } elsif ($ARGV[0] =~ m/.+\=.*\:.*$/) {
    print STDERR "Warning: suspicious first argument to slurm.pl: $ARGV[0]\n";
  } elsif ($ARGV[1] eq '-f' ) {
    $mode = 'script';
    print STDERR "script mode on\n";
    $logfile = shift @ARGV;
    shift @ARGV;	# that '-f' argument
    my $scriptfile = shift @ARGV;
    open (FH, $scriptfile) || die "Could not open $scriptfile: $!\n";
    @cmds = <FH>;
    $totaljobend = @cmds;
  }
  if ($jobsperbatch == 0){
    $jobsperbatch = $totaljobend - $totaljobstart + 1;
  }
}   # parse argument done

if ($jobsperbatch > 64) {
  print STDERR "Warning: jobs per batch restricted to 64\n";
  $jobsperbatch = 64;
}
if ($mode eq 'cmdline') {
  $logfile = shift @ARGV;

  if (defined $jobname && $logfile !~ m/$jobname/ &&
      $totaljobend > $totaljobstart) {
    print STDERR "slurm.pl: you are trying to run a parallel job but "
      . "you are putting the output into just one log file ($logfile)\n";
    exit(1);
  }

  $cmd = "";

  foreach $x (@ARGV) { 
      if ($x =~ m/^\S+$/) { $cmd .=  $x . " "; }
      elsif ($x =~ m:\":) { $cmd .= "'$x' "; }
      else { $cmd .= "\"$x\" "; } 
  }
}

$numjobs = ($totaljobend - $totaljobstart + 1);

for ($batchi = 0; $batchi < roundup($numjobs / $jobsperbatch); $batchi++) {
  $jobstart = $totaljobstart + $jobsperbatch * $batchi;
  $jobend = $totaljobstart + $jobsperbatch * ($batchi + 1) - 1;
  if ($jobend > $totaljobend){
    $jobend = $totaljobend;
  }
  for ($jobid = $jobstart; $jobid <= $jobend; $jobid++) {
    $childpid = fork();
    if (!defined $childpid) { die "Error forking in slurm.pl (writing to $logfile)"; }
    if ($childpid == 0) { # We're in the child... this branch
      # executes the job and returns (possibly with an error status).
      if ($mode eq "script") {
        $cmd = $cmds[$jobid-1];
        $logfile = $logfile . '.' . $jobid;
      } elsif (defined $jobname) { 
        $cmd =~ s/$jobname/$jobid/g;
        $logfile =~ s/$jobname/$jobid/g;
      }
      $cmd="set -e; set -o pipefail; $cmd";
      $precmd = "srun -q -N 1 -n 1 --msg-timeout=60 -c $threadsperjob $gpuarg $memfreearg bash";
      system("echo $logfile");
      system("mkdir -p `dirname $logfile` 2>/dev/null");
      open(F, ">$logfile") || die "Error opening log file $logfile";
      print F "# " . $precmd . "\n";
      print F "# " . $cmd . "\n";
      print F "# Started at " . `date`;
      $starttime = `date +'%s'`;
      print F "#\n";
      close(F);

      # Pipe into bash.. make sure we're not using any other shell.
      open(B, "|-", "$precmd") || die "Error opening shell command"; 
      print B "( " . $cmd . ") 2>>$logfile >> $logfile";
      close(B);                   # If there was an error, exit status is in $?
      $ret = $?;

      $endtime = `date +'%s'`;
      open(F, ">>$logfile") || die "Error opening log file $logfile (again)";
      $enddate = `date`;
      chop $enddate;
      print F "# Ended (code $ret) at " . $enddate . ", elapsed time " . ($endtime-$starttime) . " seconds\n";
      close(F);
      exit($ret);
    } else {
      $childpids{$jobid} = $childpid;
    }
  }

  $ret = 0;
  $numfail = 0;

  if ($killmode eq "strict") {
    while (1) {
      foreach my $jobid (keys %childpids) {
        my $res = waitpid($childpids{$jobid}, WNOHANG);
        if ($res == $childpids{$jobid}){
          # this job done
          delete $childpids{$jobid};    # At least this job is done
          $numfail++;
          $thislogfile = $logfile;
          if ($mode eq "script") {
            $thislogfile = $logfile . '.' . $jobid;
          } elsif (defined $jobname) {
            $thislogfile =~ s/$jobname/$jobid/g;
          }
          # Check if done properly (I don't have other methods to do this yet)
          $ret = system("tail -1 $thislogfile | grep 'Ended (code 0)' &> /dev/null");
          if ($ret != 0) {
            print "Job $jobid exit unexpectedly, killing all others\n";
            foreach my $thisjobid (keys %childpids) {
              kill('TERM', $childpids{$thisjobid});
              delete $childpids{$thisjobid};
              $numfail++;
            }
            last;
          }
        }
      }
      if (! %childpids) {
        last;
      }
      sleep 1;
    }
    if ($ret != 0) {
      last;
    }
  } else {    # loose mode; keep going when some jobs are wrong
    for ($jobid = $jobstart; $jobid <= $jobend; $jobid++) {
      $r = wait();
      if ($r == -1) { die "Error waiting for child process"; } # should never happen.
      if ($? != 0) { $numfail++; $ret = 1; } # The child process failed.
    }
  }
}

if ($ret != 0) {
  $njobs = $jobend - $jobstart + 1;
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
} else {
  print "slurm.pl: Done successfully.\n";
}

exit ($ret);
