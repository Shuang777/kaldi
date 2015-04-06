// nnetbin/nnet-train-frmshuff.cc

// Copyright 2013  Brno University of Technology (Author: Karel Vesely)

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

#include <mpi.h>
#include "nnet/nnet-trnopts.h"
#include "nnet/nnet-nnet.h"
#include "nnet/nnet-loss.h"
#include "nnet/nnet-randomizer.h"
#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "base/timer.h"
#include "cudamatrix/cu-device.h"


using namespace kaldi;
using namespace kaldi::nnet1;


void share_and_average(Nnet &nnet, const int rank_id, const int friend_id) {
  KALDI_ASSERT(rank_id != friend_id);
  int num_elements = nnet.NumElements();
  int num_elements_friend = 0;

  nnet.PrepSendBuffer();

  if (rank_id < friend_id) {
    MPI_Send(&num_elements, 1, MPI_INT, friend_id, 0, MPI_COMM_WORLD);
    MPI_Recv(&num_elements_friend, 1, MPI_INT, friend_id, 1, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    KALDI_ASSERT(num_elements == num_elements_friend);

    MPI_Send(nnet.GetSendBuffer(), num_elements, MPI_FLOAT, friend_id, 0, MPI_COMM_WORLD);
    MPI_Recv(nnet.GetReceiveBuffer(), num_elements, MPI_FLOAT, friend_id, 1, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
  } else {
    MPI_Recv(&num_elements_friend, 1, MPI_INT, friend_id, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    MPI_Send(&num_elements, 1, MPI_INT, friend_id, 1, MPI_COMM_WORLD);
    KALDI_ASSERT(num_elements == num_elements_friend);

    MPI_Recv(nnet.GetReceiveBuffer(), num_elements, MPI_FLOAT, friend_id, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    MPI_Send(nnet.GetSendBuffer(), num_elements, MPI_FLOAT, friend_id, 1, MPI_COMM_WORLD);
  }
  nnet.AverageReceiveBuffer();
}

int main(int argc, char *argv[]) {
  typedef kaldi::int32 int32;  
  
  try {
    const char *usage =
        "Perform one iteration of Neural Network training by mini-batch Stochastic Gradient Descent.\n"
        "This version use pdf-posterior as targets, prepared typically by ali-to-post.\n"
        "Usage:  nnet-train-frmshuff [options] <feature-rspecifier-str> <targets-rspecifier-str> <model-in> [<model-out>]\n"
        "e.g.: \n"
        " nnet-train-frmshuff scp:feature.scp ark:posterior.ark nnet.init nnet.iter1\n";

    ParseOptions po(usage);

    NnetTrainOptions trn_opts;
    trn_opts.Register(&po);
    NnetDataRandomizerOptions rnd_opts;
    rnd_opts.Register(&po);

    bool binary = true, 
         crossvalidate = false,
         randomize = true;
    po.Register("binary", &binary, "Write output in binary mode");
    po.Register("cross-validate", &crossvalidate, "Perform cross-validation (don't backpropagate)");
    po.Register("randomize", &randomize, "Perform the frame-level shuffling within the Cache::");

    std::string feature_transform;
    po.Register("feature-transform", &feature_transform, "Feature transform in Nnet format");
    std::string objective_function = "xent";
    po.Register("objective-function", &objective_function, "Objective function : xent|mse");

    int32 length_tolerance = 5;
    po.Register("length-tolerance", &length_tolerance, "Allowed length difference of features/targets (frames)");

    int32 semi_layers = -1;
    po.Register("semi-layers", &semi_layers, "Layers to reweight for semi data (default is -1, means no semidata)");

    std::string updatable_layers = "";
    po.Register("updatable-layers", &updatable_layers, "Layers to update");
    
    std::string frame_weights;
    po.Register("frame-weights", &frame_weights, "Per-frame weights to scale gradients (frame selection/weighting).");

    std::string use_gpu="yes";
    po.Register("use-gpu", &use_gpu, "yes|no|optional, only has effect if compiled with CUDA");
    
    std::string ref_model_filename="None";
    po.Register("ref-nnet", &ref_model_filename, "Reference nnet for regularization (default None)");

    int32 frames_per_avg = 10000;
    po.Register("frames-per-avg", &frames_per_avg, "Number of frames per average operation on MPI (default = 10000)");
    
    double dropout_retention = 0.0;
    po.Register("dropout-retention", &dropout_retention, "number between 0..1, saying how many neurons to preserve (0.0 will keep original value");
     
    
    po.Read(argc, argv);

    if (po.NumArgs() != 4-(crossvalidate?1:0)) {
      po.PrintUsage();
      exit(1);
    }

    std::string feature_rspecifier = po.GetArg(1),
      targets_rspecifier = po.GetArg(2),
      model_filename = po.GetArg(3);

    MPI::Init();
    int32 mpi_rank = MPI::COMM_WORLD.Get_rank();
    int32 mpi_jobs = MPI::COMM_WORLD.Get_size();
    std::string rank_str;

    KALDI_ASSERT(mpi_jobs > 1);
    {
      std::stringstream ss;
      ss << mpi_rank;
      rank_str = ss.str();
      ReplaceStr(feature_rspecifier, "MPI_RANK", rank_str);
    }
        
    std::string target_model_filename;
    if (!crossvalidate) {
      target_model_filename = po.GetArg(4) + rank_str;
    }

    using namespace kaldi;
    using namespace kaldi::nnet1;
    typedef kaldi::int32 int32;

    //Select the GPU
#if HAVE_CUDA==1
    CuDevice::Instantiate().SelectGpuId(use_gpu);
    CuDevice::Instantiate().DisableCaching();
#endif

    Nnet nnet_transf;
    if(feature_transform != "") {
      nnet_transf.Read(feature_transform);
    }

    Nnet nnet;
    nnet.Read(model_filename);
    nnet.SetTrainOptions(trn_opts);
    if (updatable_layers != "") {
      std::vector<bool> updatable;
      SplitStringToBoolVector(updatable_layers, ":", updatable);
      nnet.SetUpdatables(updatable);
    }

    nnet.AllocBuffer();
    int32 average_count = 0;

    Nnet ref_nnet;
    if (ref_model_filename != "None") {
      ref_nnet.Read(ref_model_filename);
      nnet.SetRefNnet(ref_nnet);
    }

    if (dropout_retention > 0.0) {
      nnet_transf.SetDropoutRetention(dropout_retention);
      nnet.SetDropoutRetention(dropout_retention);
    }
    if (crossvalidate) {
      nnet_transf.SetDropoutRetention(1.0);
      nnet.SetDropoutRetention(1.0);
    }

    kaldi::int64 total_frames = 0;

    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader targets_reader(targets_rspecifier);
    RandomAccessBaseFloatVectorReader weights_reader;
    if (frame_weights != "") {
      weights_reader.Open(frame_weights);
    }

    RandomizerMask randomizer_mask(rnd_opts);
    MatrixRandomizer feature_randomizer(rnd_opts);
    PosteriorRandomizer targets_randomizer(rnd_opts);
    VectorRandomizer weights_randomizer(rnd_opts);

    Xent xent;
    Mse mse;
    
    CuMatrix<BaseFloat> feats_transf, nnet_out, obj_diff;

    Timer time;
    if (mpi_rank == 0)
      KALDI_LOG << (crossvalidate?"CROSS-VALIDATION":"TRAINING") << " STARTED";

    int32 num_done = 0, num_no_tgt_mat = 0, num_other_error = 0;
    while (!feature_reader.Done()) {
#if HAVE_CUDA==1
      // check the GPU is not overheated
      CuDevice::Instantiate().CheckGpuHealth();
#endif
      // fill the randomizer
      for ( ; !feature_reader.Done(); feature_reader.Next()) {
        if (feature_randomizer.IsFull()) break; // suspend, keep utt for next loop
        std::string utt = feature_reader.Key();
        KALDI_VLOG(3) << "Reading " << utt;
        // check that we have targets
        if (!targets_reader.HasKey(utt)) {
          KALDI_WARN << utt << ", missing targets";
          num_no_tgt_mat++;
          continue;
        }
        // check we have per-frame weights
        if (frame_weights != "" && !weights_reader.HasKey(utt)) {
          KALDI_WARN << utt << ", missing per-frame weights";
          num_other_error++;
          continue;
        }
        // get feature / target pair
        Matrix<BaseFloat> mat = feature_reader.Value();
        Posterior targets = targets_reader.Value(utt);
        // get per-frame weights
        Vector<BaseFloat> weights;
        if (frame_weights != "") {
          weights = weights_reader.Value(utt);
        } else { // all per-frame weights are 1.0
          weights.Resize(mat.NumRows());
          weights.Set(1.0);
        }
        // correct small length mismatch ... or drop sentence
        {
          // add lengths to vector
          std::vector<int32> lenght;
          lenght.push_back(mat.NumRows());
          lenght.push_back(targets.size());
          lenght.push_back(weights.Dim());
          // find min, max
          int32 min = *std::min_element(lenght.begin(),lenght.end());
          int32 max = *std::max_element(lenght.begin(),lenght.end());
          // fix or drop ?
          if (max - min < length_tolerance) {
            if(mat.NumRows() != min) mat.Resize(min, mat.NumCols(), kCopyData);
            if(targets.size() != min) targets.resize(min);
            if(weights.Dim() != min) weights.Resize(min, kCopyData);
          } else {
            KALDI_WARN << utt << ", length mismatch of targets " << targets.size()
                       << " and features " << mat.NumRows();
            num_other_error++;
            continue;
          }
        }
        // apply optional feature transform
        nnet_transf.Feedforward(CuMatrix<BaseFloat>(mat), &feats_transf);

        // pass data to randomizers
        KALDI_ASSERT(feats_transf.NumRows() == targets.size());
        feature_randomizer.AddData(feats_transf);
        targets_randomizer.AddData(targets);
        weights_randomizer.AddData(weights);
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
      if (!crossvalidate && randomize) {
        const std::vector<int32>& mask = randomizer_mask.Generate(feature_randomizer.NumFrames());
        feature_randomizer.Randomize(mask);
        targets_randomizer.Randomize(mask);
        weights_randomizer.Randomize(mask);
      }

      // train with data from randomizers (using mini-batches)
      for ( ; !feature_randomizer.Done(); feature_randomizer.Next(),
                                          targets_randomizer.Next(),
                                          weights_randomizer.Next()) {
        // get block of feature/target pairs
        const CuMatrixBase<BaseFloat>& nnet_in = feature_randomizer.Value();
        const Posterior& nnet_tgt = targets_randomizer.Value();
        const Vector<BaseFloat>& frm_weights = weights_randomizer.Value();

        // forward pass
        nnet.Propagate(nnet_in, &nnet_out);

        // evaluate objective function we've chosen
        if (objective_function == "xent") {
          xent.Eval(nnet_out, nnet_tgt, &obj_diff);
        } else if (objective_function == "mse") {
          mse.Eval(nnet_out, nnet_tgt, &obj_diff);
        } else {
          KALDI_ERR << "Unknown objective function code : " << objective_function;
        }

        // backward pass
        if (!crossvalidate) {
          if (semi_layers == -1) {
            // re-scale the gradients
            obj_diff.MulRowsVec(CuVector<BaseFloat>(frm_weights));
            // backpropagate
            nnet.Backpropagate(obj_diff, NULL);
          } else {  // gradient cutoff for semidata, use weights to indicate semi or not
            if (frame_weights == "") {
              CuVector<BaseFloat> empty_weights;
              nnet.Backpropagate(obj_diff, NULL, empty_weights, semi_layers);
            } else {
              nnet.Backpropagate(obj_diff, NULL, CuVector<BaseFloat>(frm_weights), semi_layers);
            }
          }
        }

        // 1st minibatch : show what happens in network 
        if (kaldi::g_kaldi_verbose_level >= 1 && total_frames == 0 && mpi_rank == 0) { // vlog-1
          KALDI_VLOG(1) << "### After " << total_frames << " frames,";
          KALDI_VLOG(1) << nnet.InfoPropagate();
          if (!crossvalidate) {
            KALDI_VLOG(1) << nnet.InfoBackPropagate();
            KALDI_VLOG(1) << nnet.InfoGradient();
          }
          if (semi_layers != -1) {
            KALDI_VLOG(1) << "Gradient cutoff for semidata layers = " << semi_layers << ".";
          }
        }
        
        // monitor the NN training
        if (kaldi::g_kaldi_verbose_level >= 2) { // vlog-2
          if ((total_frames/25000) != ((total_frames+nnet_in.NumRows())/25000) && mpi_rank == 0) { // print every 25k frames
            KALDI_VLOG(2) << "### After " << total_frames << " frames,";
            KALDI_VLOG(2) << nnet.InfoPropagate();
            if (!crossvalidate) {
              KALDI_VLOG(2) << nnet.InfoGradient();
            }
          }
        }

        if (total_frames/frames_per_avg != ((total_frames+nnet_in.NumRows())/frames_per_avg)) { // average every frames_per_avg frames
          int32 friend_id = 1 - mpi_rank;
          if (mpi_rank == 0)
            KALDI_VLOG(2) << "### MPI averaging after " << total_frames << " frames."
                          << " Count " << average_count << " friend id " << friend_id;
          share_and_average(nnet, mpi_rank, friend_id);
          average_count++;
        }
        
        total_frames += nnet_in.NumRows();
      }
    }
    
    // after last minibatch : show what happens in network 
    if (kaldi::g_kaldi_verbose_level >= 1 && mpi_rank == 0) { // vlog-1
      KALDI_VLOG(1) << "### After " << total_frames << " frames,";
      KALDI_VLOG(1) << nnet.InfoPropagate();
      if (!crossvalidate) {
        KALDI_VLOG(1) << nnet.InfoBackPropagate();
        KALDI_VLOG(1) << nnet.InfoGradient();
      }
    }

    if (!crossvalidate) {
      nnet.Write(target_model_filename, binary);
    }

    KALDI_LOG << "MPI job " << mpi_rank << " done " << num_done << " files, " << num_no_tgt_mat
              << " with no tgt_mats, " << num_other_error
              << " with other errors. "
              << "[" << (crossvalidate?"CROSS-VALIDATION":"TRAINING")
              << ", " << (randomize?"RANDOMIZED":"NOT-RANDOMIZED") 
              << ", " << time.Elapsed()/60 << " min, fps" << total_frames/time.Elapsed()
              << "]";  

    if (objective_function == "xent") {
      KALDI_LOG << "MPI job " << mpi_rank << " " << xent.Report() << std::endl;
    } else if (objective_function == "mse") {
      KALDI_LOG << "MPI job " << mpi_rank << " " << mse.Report() << std::endl;
    } else {
      KALDI_ERR << "Unknown objective function code : " << objective_function;
    }

#if HAVE_CUDA==1
    CuDevice::Instantiate().PrintProfile();
#endif

    MPI::Finalize();

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
