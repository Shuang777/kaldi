// nnetbin/rbm-train-cd1-frmshuff.cc

// Copyright 2012-2013  Brno University of Technology (Author: Karel Vesely)

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.

#include "nnet/nnet-trnopts.h"
#include "nnet/nnet-rbm.h"
#include "nnet/nnet-nnet.h"
#include "nnet/nnet-loss.h"
#include "nnet/nnet-randomizer.h"
#include "nnet/nnet-mixing.h"
#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "base/timer.h"
#include "cudamatrix/cu-device.h"
#include "cudamatrix/cu-rand.h"


int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::nnet1;
  typedef kaldi::int32 int32;
  try {
    const char *usage =
        "Train RBM by Contrastive Divergence alg. with 1 step of "
        "Markov Chain Monte-Carlo.\n"
        "The tool can perform several iterations (--num-iters) "
        "or it can subsample the training dataset (--drop-data)\n"
        "Usage:  rbm-train-cd1-frmshuff [options] <model-in> <feature-rspecifier> <model-out>\n"
        "e.g.: \n"
        " rbm-train-cd1-frmshuff 1.rbm.init scp:train.scp 1.rbm\n";

    ParseOptions po(usage);

    RbmTrainOptions trn_opts, trn_opts_rbm;
    trn_opts.Register(&po);

    bool binary = false; 
    po.Register("binary", &binary, "Write output in binary mode");

    bool with_bug = true; 
    po.Register("with-bug", &with_bug, "Apply bug which led to better results (set-initial-momentum-to-max)");
    
    int32 num_iters = 1; 
    po.Register("num-iters", &num_iters, 
                "Number of iterations (smaller datasets should have more iterations, "
                "iterating within tool becase of linear momentum scheduling)");

    std::string feature_transform;
    po.Register("feature-transform", &feature_transform, "Feature transform in Nnet format");

    NnetDataRandomizerOptions rnd_opts;
    rnd_opts.minibatch_size = 100;
    rnd_opts.Register(&po);

    kaldi::int32 max_frames = 6000; // Allow segments maximum of 30 seconds by default
    po.Register("max-frames",&max_frames, "Maximum number of frames a segment can have to be processed");
    
    std::string use_gpu="yes";
    po.Register("use-gpu", &use_gpu, "yes|no|optional, only has effect if compiled with CUDA"); 

    std::string reduce_type = "allreduce";
    po.Register("reduce-type", &reduce_type, "Reduce strategy for MPI jobs (butterfly|allreduce|ring|hoppingring, default = allreduce)");
     
    int32 frames_per_reduce = 10000;
    po.Register("frames-per-reduce", &frames_per_reduce, "Number of frames per average operation on MPI (default = 10000)");
    
    int32 max_reduce_count = INT_MAX;
    po.Register("max-reduce-count", &max_reduce_count, "Maximum number of average operation. (default = 10000)");
    
    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_filename = po.GetArg(1),
        feature_rspecifier = po.GetArg(2);
        
    std::string target_model_filename;
    target_model_filename = po.GetArg(3);

    MPI::Init();
    int32 mpi_rank = MPI::COMM_WORLD.Get_rank();
    int32 mpi_jobs = MPI::COMM_WORLD.Get_size();

    if (mpi_rank != 0) {
      kaldi::g_kaldi_verbose_level = 0;
    }

    KALDI_ASSERT(mpi_jobs > 1);
    if (reduce_type == "butterfly") {
      // we only support 2^N jobs for butterfly mixing
      KALDI_ASSERT(is_power_of_two(mpi_jobs));
    }

    std::string rank_str;
    {
      std::stringstream ss;
      ss << mpi_rank+1;
      rank_str = ss.str();
      ReplaceStr(feature_rspecifier, "MPI_RANK", rank_str);
    }

#if HAVE_CUDA==1
    CuDevice::Instantiate().SelectGpuId(use_gpu);
    CuDevice::Instantiate().DisableCaching();
#endif

    Nnet rbm_transf;
    if(feature_transform != "") {
      rbm_transf.Read(feature_transform);
    }

    // Read nnet, extract the RBM
    Nnet nnet;
    nnet.Read(model_filename);
    KALDI_ASSERT(nnet.NumComponents()==1);
    KALDI_ASSERT(nnet.GetComponent(0).GetType() == kaldi::nnet1::Component::kRbm);
    RbmBase &rbm = dynamic_cast<RbmBase&>(nnet.GetComponent(0));

    // Configure the RBM,
    // make some constants accessible, will use them later:
    const BaseFloat& learn_rate = trn_opts.learn_rate;
    const BaseFloat& momentum = trn_opts.momentum;
    const BaseFloat& momentum_max = trn_opts.momentum_max;
    const int32& momentum_steps = trn_opts.momentum_steps;
    const int32& momentum_step_period = trn_opts.momentum_step_period;
    // trn_opts_rbm is for RBM, copy the opts
    trn_opts_rbm = trn_opts;
    trn_opts_rbm.learn_rate = learn_rate*(1-momentum); // keep `effective' learning rate constant
    // pass options to RBM
    rbm.SetRbmTrainOptions(trn_opts_rbm);

    kaldi::int64 total_frames = 0;

    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomizerMask randomizer_mask(rnd_opts);
    MatrixRandomizer feature_randomizer(rnd_opts);

    CuRand<BaseFloat> cu_rand; // parallel random number generator
    Mse mse;
    
    CuMatrix<BaseFloat> feats, feats_transf, 
                        pos_hid, pos_hid_aux, 
                        neg_vis, neg_hid;
    CuMatrix<BaseFloat> dummy_mse_mat;

    Timer time;
    
    Timer mpi_timer;
    double mpi_time = 0;
    int32 reduce_count = 0;
    int32 reduce_shift = 1;

    if (mpi_rank == 0)
      KALDI_LOG << "RBM TRAINING STARTED";

    int32 iter = 1;
    if (mpi_rank == 0)
      KALDI_LOG << "Iteration " << iter << "/" << num_iters;

    int32 num_done = 0, num_other_error = 0;
    while (!feature_reader.Done() && reduce_count < max_reduce_count) {
#if HAVE_CUDA==1      
      // check the GPU is not overheated
      CuDevice::Instantiate().CheckGpuHealth();
#endif
      // fill the randomizer
      for ( ; !feature_reader.Done(); feature_reader.Next()) {
        if (feature_randomizer.IsFull()) break; // suspend, keep utt for next loop
        std::string utt = feature_reader.Key();
        KALDI_VLOG(3) << utt;
        // get feature matrix
        const Matrix<BaseFloat> &mat = feature_reader.Value();
        // skip too long segments (avoid runinning out of memory)
        if (mat.NumRows() > max_frames) {
          KALDI_WARN << "Utterance " << utt << ": Skipped because it has " << mat.NumRows() << 
            " frames, which is more than " << max_frames << ".";
          num_other_error++;
          continue;
        }
        // push features to GPU
        feats.Resize(mat.NumRows(),mat.NumCols());
        feats.CopyFromMat(mat);
        // apply optional feature transform
        rbm_transf.Feedforward(feats, &feats_transf);
        // add to randomizer
        feature_randomizer.AddData(feats_transf);
        num_done++;

        // report the speed
        if (num_done % 5000 == 0 && mpi_rank == 0) {
          double time_now = time.Elapsed();
          KALDI_VLOG(1) << "After " << num_done << " utterances: time elapsed = "
                        << time_now/60 << " min; processed " << total_frames/time_now
                        << " frames per second.";
        }
      }

      // randomize
      feature_randomizer.Randomize(randomizer_mask.Generate(feature_randomizer.NumFrames()));

      // train with data from randomizer (using mini-batches)
      for( ; !feature_randomizer.Done() && reduce_count < max_reduce_count; feature_randomizer.Next()) {
        // get block of feature/target pairs
        const CuMatrixBase<BaseFloat>& pos_vis = feature_randomizer.Value();
        // get the dims 
        int32 num_frames = pos_vis.NumRows(),
              dim_hid = rbm.OutputDim();
       
        // TRAIN with CD1
        // forward pass
        rbm.Propagate(pos_vis, &pos_hid);

        // alter the hidden values, so we can generate negative example
        if (rbm.HidType() == Rbm::Bernoulli) {
          pos_hid_aux.Resize(num_frames, dim_hid);
          cu_rand.BinarizeProbs(pos_hid, &pos_hid_aux);
        } else {
          // assume HidType Rbm::GAUSSIAN
          pos_hid_aux.Resize(num_frames, dim_hid);
          pos_hid_aux.CopyFromMat(pos_hid);
          cu_rand.AddGaussNoise(&pos_hid_aux);
        }

        // reconstruct pass
        rbm.Reconstruct(pos_hid_aux, &neg_vis);
        // propagate negative examples
        rbm.Propagate(neg_vis, &neg_hid);
        // update step
        rbm.RbmUpdate(pos_vis, pos_hid, neg_vis, neg_hid);
        // evaluate mean square error
        mse.Eval(neg_vis, pos_vis, &dummy_mse_mat);

        if (total_frames/frames_per_reduce != ((total_frames+num_frames)/frames_per_reduce)) { // reduce every frames_per_reduce frames
          mpi_timer.Reset();
          if (mpi_rank == 0)
            KALDI_LOG << "### MPI " << reduce_type << " reducing after " << total_frames+num_frames << " frames.";
          
          if (reduce_type == "butterfly") {
            int32 friend_id = get_butterfly_friend_id(mpi_rank, mpi_jobs, reduce_count);
            share_nnet_buffer(nnet, mpi_rank, friend_id, friend_id);
          } else if (reduce_type == "allreduce") {
            all_reduce_nnet_buffer(nnet, mpi_jobs);
          } else if (reduce_type == "ring") {
            share_nnet_buffer(nnet, mpi_rank, (mpi_rank + 1) % mpi_jobs, (mpi_rank + mpi_jobs - 1) % mpi_jobs);
          } else if (reduce_type == "hoppingring") {
            share_nnet_buffer(nnet, mpi_rank, (mpi_rank + reduce_shift) % mpi_jobs, (mpi_rank + mpi_jobs - reduce_shift) % mpi_jobs);
          }
          reduce_shift = (reduce_shift + 1) % mpi_jobs;
          if (reduce_shift == 0) {    // avoid averaging with itself
            reduce_shift = 1;
          }
          reduce_count++;
          mpi_time += mpi_timer.Elapsed();
        }

        total_frames += num_frames;

        // change the momentum progressively per 0.5million samples of the data
        {
          static int32 n_prev = -1;
          BaseFloat step = (momentum_max - momentum) / momentum_steps;
          int32 n = total_frames / momentum_step_period; //change every momentum_step_period data
          BaseFloat momentum_actual;
          if(n > momentum_steps) {
            momentum_actual = momentum_max;
          } else {
            momentum_actual = momentum + n*step;
          }
          if(n - n_prev > 0) {
            n_prev = n;
            BaseFloat learning_rate_actual = learn_rate*(1-momentum_actual);
            if (mpi_rank == 0)
              KALDI_VLOG(1) << "Setting momentum " << (with_bug ? momentum_max : momentum_actual)
                            << " and learning rate " << learning_rate_actual
                            << " after processing " 
                            << static_cast<double>(total_frames)/360000 << "h";
            // pass values to rbm
            trn_opts_rbm.momentum = (with_bug ? momentum_max : momentum_actual);
            trn_opts_rbm.learn_rate = learning_rate_actual;
            rbm.SetRbmTrainOptions(trn_opts_rbm);
          }
        }
      }

      // reopen the feature stream if we will run another iteration
      if (feature_reader.Done() && (iter < num_iters)) {
        iter++;
        if (mpi_rank == 0)
          KALDI_LOG << "Iteration " << iter << "/" << num_iters;
        feature_reader.Close();
        feature_reader.Open(feature_rspecifier);
      }
    }

    if (mpi_rank == 0)
      nnet.Write(target_model_filename, binary);
    
    KALDI_LOG << "MPI job " << mpi_rank << " done " << iter << " iterations, " << num_done << " files, "
              << "skipped " << num_other_error << " files. "
              << "[" << time.Elapsed()/60 << " min, fps" << total_frames/time.Elapsed() 
              << ", MPI time " << mpi_time/60 << " min"
              << "]";

    double loss = mse.GetLoss();
    int32 num_frames = mse.GetFrames();
    
    double global_loss;
    int32 global_num_frames;
    MPI_Reduce(&loss, &global_loss, 1, MPI_DOUBLE, MPI_SUM, 0, MPI_COMM_WORLD);
    MPI_Reduce(&num_frames, &global_num_frames, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);

    if (mpi_rank == 0)
      KALDI_LOG << "AvgLoss: " << global_loss/global_num_frames;

#if HAVE_CUDA==1
    if (mpi_rank == 0) {
      CuDevice::Instantiate().PrintProfile();
    }
#endif

    MPI::Finalize();

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
