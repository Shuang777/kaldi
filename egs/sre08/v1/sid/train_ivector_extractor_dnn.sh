#!/bin/bash
{
set -e
set -o pipefail

# Copyright 2013  Daniel Povey
#      2014-2015  David Snyder
#           2015  Johns Hopkins University (Author: Daniel Garcia-Romero)
#           2015  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0.

# This script trains the i-vector extractor using a DNN-based UBM. It also requires
# an fGMM, usually created by the script sid/init_full_gmm_from_dnn.sh.
# Note: there are 3 separate levels of parallelization: num_threads, num_processes, 
# and num_jobs.  This may seem a bit excessive.  It has to do with minimizing 
# memory usage and disk I/O, subject to various constraints.  The "num_threads" 
# is how many threads a program uses; the "num_processes" is the number of separate
# processes a single  job spawns, and then sums the accumulators in memory.
# Our recommendation:
#  - Set num_threads to the minimum of (4, or how many virtual cores your machine has).
#    (because of needing to lock various global quantities, the program can't
#    use many more than 4 threads with good CPU utilization).
#  - Set num_processes to the number of virtual cores on each machine you have, divided by 
#    num_threads.  E.g. 4, if you have 16 virtual cores.   If you're on a shared queue
#    that's busy with other people's jobs, it may be wise to set it to rather less
#    than this maximum though, or your jobs won't get scheduled.  And if memory is
#    tight you need to be careful; in our normal setup, each process uses about 5G.
#  - Set num_jobs to as many of the jobs (each using $num_threads * $num_processes CPUs)
#    your queue will let you run at one time, but don't go much more than 10 or 20, or
#    summing the accumulators will possibly get slow.  If you have a lot of data, you
#    may want more jobs, though.

# Begin configuration section.
nj=10   # this is the number of separate queue jobs we run, but each one 
        # contains num_processes sub-jobs.. the real number of threads we 
        # run is nj * num_processes * num_threads, and the number of
        # separate pieces of data is nj * num_processes.
num_threads=4
num_processes=1 # each job runs this many processes, each with --num-threads threads
cmd="run.pl"
post_cmd=
stage=-4
num_gselect=20 # Gaussian-selection using diagonal model: number of Gaussians to select
ivector_dim=400 # dimension of the extracted i-vector
use_weights=false # set to true to turn on the regression of log-weights on the ivector.
num_iters=10
min_post=0.025 # Minimum posterior to use (posteriors below this are pruned out)
num_samples_for_weights=3 # smaller than the default for speed (relates to a sampling method)
cleanup=true
posterior_scale=1.0 # This scale helps to control for successve features being highly
                    # correlated.  E.g. try 0.1 or 0.3
compute_post=true     # posts are copied from else-where
dnnfeats2feats=none
sum_accs_opt=
subsample=1

nnet=
feat_type=traps
transform_dir=
feature_transform=
use_gpu=no

add_delta=true
cmvn=true
cmvn_opts="--norm-vars=false"
vad=true
# End configuration section.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;


if [ $# != 5 ]; then
  echo "Usage: $0 <fgmm-model> <dnn-model> <data-speaker-id> <data-dnn> <extractor-dir>"
  echo " e.g.: $0 exp/sup_ubm/final.ubm exp/dnn/final.mdl data/train data/train_dnn exp/extractor_male"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --num-iters <#iters|10>                          # Number of iterations of E-M"
  echo "  --nj <n|10>                                      # Number of jobs (also see num-processes and num-threads)"
  echo "  --num-processes <n|4>                            # Number of processes for each queue job (relates"
  echo "                                                   # to summing accs in memory)"
  echo "  --num-threads <n|4>                              # Number of threads for each process (can't be usefully"
  echo "                                                   # increased much above 4)"
  echo "  --stage <stage|-4>                               # To control partial reruns"
  echo "  --num-gselect <n|20>                             # Number of Gaussians to select using"
  echo "                                                   # diagonal model."
  echo "  --sum-accs-opt <option|''>                       # Option e.g. '-l hostname=a15' to localize"
  echo "                                                   # sum-accs process to nfs server."
  exit 1;
fi

fgmm_model=$1
dnndir=$2
data=$3
data_dnn=$4
dir=$5

srcdir=$(dirname $fgmm_model)

for f in $fgmm_model $data/feats.scp ; do
  [ ! -f $f ] && echo "No such file $f" && exit 1;
done

[ -z "$post_cmd" ] && post_cmd="$cmd"

# Set various variables.
mkdir -p $dir/log
nj_full=$[$nj*$num_processes]
sdata=$data/split$nj_full;
utils/split_data.sh $data $nj_full || exit 1;

sdata_dnn=$data_dnn/split$nj_full;
utils/split_data.sh $data_dnn $nj_full || exit 1;

delta_opts=`cat $srcdir/delta_opts 2>/dev/null`
if [ -f $srcdir/delta_opts ]; then
  cp $srcdir/delta_opts $dir/ 2>/dev/null
fi

[ -f $dnndir/splice_opts ] && splice_opts=`cat $dnndir/splice_opts 2>/dev/null` # frame-splicing options           

parallel_opts="-pe smp $[$num_threads*$num_processes]"
## Set up features.
feats="ark,s,cs:copy-feats scp:$sdata/JOB/feats.scp ark:- |"
if [ $add_delta == true ]; then
  feats=$feats" add-deltas $delta_opts ark:- ark:- |"
fi
if [ $cmvn == true ]; then
  feats=$feats" apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- |"
fi
if [ $vad == true ]; then
  feats=$feats" select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"
fi
feats=$feats" subsample-feats --n=$subsample ark:- ark:- |"

# Set up nnet feature
if [ -z "$nnet" ]; then nnet=$dnndir/final.nnet; fi
if [ -z "$feature_transform" ]; then feature_transform=$dnndir/final.feature_transform; fi
case $feat_type in
  raw) nnet_feats="scp:$sdata_dnn/JOB/feats.scp";;
  traps) nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- |";;
  delta) nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- | add-deltas ark:- ark:- |";;
  lda|fmllr) nnet_feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata_dnn/JOB/utt2spk scp:$sdata_dnn/JOB/cmvn.scp scp:$sdata_dnn/JOB/feats.scp ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $dnndir/final.mat ark:- ark:- |" ;;
  *) echo "$0: invalid feature type $feat_type" && exit 1;
esac
if [ $dnnfeats2feats == lda ]; then
  feats=$nnet_feats
  if [ $vad == true ]; then
    feats=$feats" select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"
  fi
  feats=$feats" subsample-feats --n=$subsample ark:- ark:- |"
fi
if [ ! -z "$transform_dir" ]; then
  echo "$0: using transforms from $transform_dir"
  if [ "$feat_type" == "fmllr" ]; then
    [ ! -f $transform_dir/trans.1 ] && echo "$0: no such file $transform_dir/trans.1" && exit 1;
    [ "$nj" -ne "`cat $transform_dir/num_jobs`" ] \
      && echo "$0: #jobs mismatch with transform-dir." && exit 1;
    nnet_feats="$nnet_feats transform-feats --utt2spk=ark:$sdata_dnn/JOB/utt2spk ark,s,cs:$transform_dir/trans.JOB ark:- ark:- |"
  elif [[ "$feat_type" == "raw" || "$feat_type" == "fmllr" ]]; then
    [ ! -f $transform_dir/raw_trans.1 ] && echo "$0: no such file $transform_dir/raw_trans.1" && exit 1;
    [ "$nj" -ne "`cat $transform_dir/num_jobs`" ] \
      && echo "$0: #jobs mismatch with transform-dir." && exit 1;
    nnet_feats="$nnet_feats transform-feats --utt2spk=ark:$sdata_dnn/JOB/utt2spk ark,s,cs:$transform_dir/raw_trans.JOB ark:- ark:- |"
  fi
elif grep 'transform-feats --utt2spk' $dnndir/log/train.1.log >&/dev/null; then
  echo "$0: **WARNING**: you seem to be using a neural net system trained with transforms,"
  echo "  but you are not providing the --transform-dir option in test time."
fi

if [ $dnnfeats2feats == fmllr ]; then
  feats=$nnet_feats
  if [ $vad == true ]; then
    feats=$feats" select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- |"
  fi
  feats=$feats" subsample-feats --n=$subsample ark:- ark:- |"
fi

# Initialize the i-vector extractor using the FGMM input
if [ $stage -le -2 ]; then
  cp $fgmm_model $dir/final.ubm || exit 1;
  $cmd $dir/log/convert.log \
    fgmm-global-to-gmm $dir/final.ubm $dir/final.dubm || exit 1;
  $cmd $dir/log/init.log \
    ivector-extractor-init --ivector-dim=$ivector_dim --use-weights=$use_weights \
     $dir/final.ubm $dir/0.ie || exit 1;
fi 

# Do Gaussian selection and posterior extracion
if [ $compute_post == true ]; then   # if not available, compute it
  if [ $stage -le -1 ]; then
    echo $nj_full > $dir/num_jobs
    echo "$0: doing DNN posterior computation"
    $post_cmd JOB=1:$nj_full $dir/log/post.JOB.log \
    nnet-forward --frames-per-batch=4096 --feature-transform=$feature_transform \
      --use-gpu=$use_gpu $nnet "$nnet_feats" ark:- \
      \| select-voiced-frames ark:- scp,s,cs:$sdata/JOB/vad.scp ark:- \
      \| prob-to-post --min-post=$min_post ark,s,cs:- ark:- \| \
      scale-post ark:- $posterior_scale "ark:|gzip -c >$dir/post.JOB.gz"

  else
    if ! [ $nj_full -eq $(cat $dir/num_jobs) ]; then
      echo "Num-jobs mismatch $nj_full versus $(cat $dir/num_jobs)"
      exit 1
    fi
  fi
else      # copy from srcdir
  [ -f $dir/post.1.gz ] && rm $dir/post.*.gz
  (cd  $dir; for i in $(ls ../$(basename $srcdir)/post.*.gz); do ln -s $i; done)
fi

x=0
while [ $x -lt $num_iters ]; do
  if [ $stage -le $x ]; then
    [ -f $dir/.error ] && rm $dir/.error 2>/dev/null

    echo "Accumulating stats (pass $x)"
    if [ $num_processes == 1 ]; then
      $cmd $parallel_opts JOB=1:$nj $dir/log/acc.$x.JOB.log \
        ivector-extractor-acc-stats --num-threads=$num_threads --num-samples-for-weights=$num_samples_for_weights $dir/$x.ie "$feats" "ark,s,cs:gunzip -c $dir/post.JOB.gz|" "$dir/acc.$x.JOB"
    else
      echo "We do not support multiple processes now!"
      exit 1;
      Args=() # bash array of training commands for 1:nj, that put accs to stdout.
      for j in $(seq $nj_full); do
        Args[$j]=`echo "ivector-extractor-acc-stats --num-threads=$num_threads --num-samples-for-weights=$num_samples_for_weights $dir/$x.ie '$feats' 'ark,s,cs:gunzip -c $dir/post.JOB.gz|' -|" | sed s/JOB/$j/g`
      done

      for g in $(seq $nj); do
        start=$[$num_processes*($g-1)+1]
        $cmd $parallel_opts $dir/log/acc.$x.$g.log \
          ivector-extractor-sum-accs --parallel=true "${Args[@]:$start:$num_processes}" \
            $dir/acc.$x.$g || touch $dir/.error &
      done
      wait
    fi
    [ -f $dir/.error ] && echo "Error accumulating stats on iteration $x" && exit 1;
	
    accs=""
  	for j in $(seq $nj); do
  	  accs+="$dir/acc.$x.$j "
  	done
  	echo "Summing accs (pass $x)"
  	$cmd $sum_accs_opt $dir/log/sum_acc.$x.log \
  	  ivector-extractor-sum-accs $accs $dir/acc.$x || exit 1;
      echo "Updating model (pass $x)"
      nt=$[$num_threads*$num_processes] # use the same number of threads that
                                        # each accumulation process uses, since we
                                        # can be sure the queue will support this many.
	  $cmd -pe smp $nt $dir/log/update.$x.log \
  	  ivector-extractor-est --num-threads=$nt $dir/$x.ie $dir/acc.$x $dir/$[$x+1].ie || exit 1;
	  rm $dir/acc.$x.*
    if $cleanup; then
      rm $dir/acc.$x
      # rm $dir/$x.ie
    fi
  fi
  x=$[$x+1]
done

ln -s $x.ie $dir/final.ie

}
