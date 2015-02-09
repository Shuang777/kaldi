// nnetbin/multi-nnet-forwardback.cc

// Copyright 2015  International Computer Science Institute (Author: Hang Su)

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

#include <limits>

#include "nnet/nnet-multi-nnet.h"
#include "nnet/nnet-loss.h"
#include "nnet/nnet-pdf-prior.h"
#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "base/timer.h"


int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::nnet1;
  try {
    const char *usage =
        "Perform forwardback pass through Multi Neural Network.\n"
        "\n"
        "Usage:  multi-nnet-forwardback [options] <model-in> <feature-rspecifier> <targets-rspecifier> <subnnet-ids-rspecifier> <feature-wspecifier>\n"
        "e.g.: \n"
        " multi-nnet-forwardback nnet ark:features.ark ark:targets.ark ark:subnnet_ids.ark ark:mlpoutput.ark\n";

    ParseOptions po(usage);

    PdfPriorOptions prior_opts;
    prior_opts.Register(&po);

    std::string feature_transform;
    po.Register("feature-transform", &feature_transform, "Feature transform in front of main network (in nnet format)");

    bool no_softmax = false;
    po.Register("no-softmax", &no_softmax, "No softmax on MLP output (or remove it if found), the pre-softmax activations will be used as log-likelihoods, log-priors will be subtracted");
    bool apply_log = false;
    po.Register("apply-log", &apply_log, "Transform MLP output to logscale");

    std::string use_gpu="no";
    po.Register("use-gpu", &use_gpu, "yes|no|optional, only has effect if compiled with CUDA"); 

    po.Read(argc, argv);

    if (po.NumArgs() != 5) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_filename = po.GetArg(1),
        feature_rspecifier = po.GetArg(2),
        targets_rspecifier = po.GetArg(3),
        subnnet_ids_rspecifier = po.GetArg(4),
        feature_wspecifier = po.GetArg(5);
        
    using namespace kaldi;
    using namespace kaldi::nnet1;
    typedef kaldi::int32 int32;

    //Select the GPU
#if HAVE_CUDA==1
    CuDevice::Instantiate().SelectGpuId(use_gpu);
    CuDevice::Instantiate().DisableCaching();
#endif

    Nnet nnet_transf;
    if (feature_transform != "") {
      nnet_transf.Read(feature_transform);
    }

    MultiNnet multi_nnet;
    multi_nnet.Read(model_filename);
    //optionally remove softmax
    if (no_softmax && multi_nnet.GetSubNnetComponent(0, multi_nnet.NumSubNnetComponents()-1).GetType() ==
        kaldi::nnet1::Component::kSoftmax) {
      KALDI_LOG << "Removing softmax from the nnet " << model_filename;
      multi_nnet.RemoveSubNnetComponent(multi_nnet.NumSubNnetComponents()-1);
    }
    //check for some non-sense option combinations
    if (apply_log && no_softmax) {
      KALDI_ERR << "Nonsense option combination : --apply-log=true and --no-softmax=true";
    }
    if (apply_log && multi_nnet.GetSubNnetComponent(0,multi_nnet.NumSubNnetComponents()-1).GetType() !=
        kaldi::nnet1::Component::kSoftmax) {
      KALDI_ERR << "Used --apply-log=true, but nnet " << model_filename 
                << " does not have <softmax> as last component!";
    }
    
    PdfPrior pdf_prior(prior_opts);
    if (prior_opts.class_frame_counts != "" && (!no_softmax && !apply_log)) {
      KALDI_ERR << "Option --class-frame-counts has to be used together with "
                << "--no-softmax or --apply-log";
    }

    // disable dropout
    nnet_transf.SetDropoutRetention(1.0);
    multi_nnet.SetDropoutRetention(1.0);

    kaldi::int64 tot_t = 0;

    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    SequentialPosteriorReader targets_reader(targets_rspecifier);
    SequentialInt32VectorReader subnnet_ids_reader(subnnet_ids_rspecifier);
    BaseFloatMatrixWriter feature_writer(feature_wspecifier);

    CuMatrix<BaseFloat> feats, feats_transf, nnet_backout;
    Matrix<BaseFloat> nnet_backout_host;
    std::vector<CuMatrix<BaseFloat> *> nnet_out, obj_diff;
    std::vector<CuMatrixBase<BaseFloat> *> nnet_out_base, obj_diff_base;


    Timer time;
    double time_now = 0;
    int32 num_done = 0;
    // iterate over all feature files
    for (; !feature_reader.Done(); feature_reader.Next()) {
      // read
      const Matrix<BaseFloat> &mat = feature_reader.Value();
      KALDI_VLOG(2) << "Processing utterance " << num_done+1 
                    << ", " << feature_reader.Key() 
                    << ", " << mat.NumRows() << "frm";

      //check for NaN/inf
      BaseFloat sum = mat.Sum();
      if (!KALDI_ISFINITE(sum)) {
        KALDI_ERR << "NaN or inf found in features of " << feature_reader.Key();
      }
      
      // push it to gpu
      feats = mat;
      // fwd-pass
      nnet_transf.Feedforward(feats, &feats_transf);
      multi_nnet.Propagate(feats_transf, nnet_out);
      
      // convert posteriors to log-posteriors
      if (apply_log) {
        for (int32 i=0; i< nnet_out.size(); i++) {
          nnet_out[i]->ApplyLog();
        }
      }
     
      // subtract log-priors from log-posteriors to get quasi-likelihoods
      if (prior_opts.class_frame_counts != "" && (no_softmax || apply_log)) {
        for (int32 i=0; i< nnet_out.size(); i++) {
          pdf_prior.SubtractOnLogpost(nnet_out[i]);
        }
      }
     
      for (int32 i=0; i<nnet_out.size(); i++) {
        nnet_out_base.push_back(dynamic_cast<CuMatrixBase<BaseFloat> *>(nnet_out[i]));
      }
      
      Xent xent;
      std::string utt = feature_reader.Key();
      Posterior targets = targets_reader.Value();
      targets_reader.Next();

      std::vector<int32> frm_subnnet_ids = subnnet_ids_reader.Value();
      subnnet_ids_reader.Next();

      xent.Eval(nnet_out_base, targets, frm_subnnet_ids, obj_diff);
      
      for (int32 i=0; i<obj_diff.size(); i++) {
        obj_diff_base.push_back(dynamic_cast<CuMatrixBase<BaseFloat> *>(obj_diff[i]));
      }
      multi_nnet.Backpropagate(obj_diff_base, &nnet_backout);

      nnet_backout_host.Resize(nnet_backout.NumRows(), nnet_backout.NumCols());
      nnet_backout.CopyToMat(&nnet_backout_host);

      //check for NaN/inf
      for (int32 r = 0; r < nnet_backout_host.NumRows(); r++) {
        for (int32 c = 0; c < nnet_backout_host.NumCols(); c++) {
          BaseFloat val = nnet_backout_host(r,c);
          if (val != val) KALDI_ERR << "NaN in NNet output of : " << feature_reader.Key();
          if (val == std::numeric_limits<BaseFloat>::infinity())
            KALDI_ERR << "inf in NNet coutput of : " << feature_reader.Key();
        }
      }

      // write
      feature_writer.Write(feature_reader.Key(), nnet_backout_host);

      // progress log
      if (num_done % 100 == 0) {
        time_now = time.Elapsed();
        KALDI_VLOG(1) << "After " << num_done << " utterances: time elapsed = "
                      << time_now/60 << " min; processed " << tot_t/time_now
                      << " frames per second.";
      }
      num_done++;
      tot_t += mat.NumRows();
    }
    
    // final message
    KALDI_LOG << "Done " << num_done << " files" 
              << " in " << time.Elapsed()/60 << "min," 
              << " (fps " << tot_t/time.Elapsed() << ")"; 

#if HAVE_CUDA==1
    if (kaldi::g_kaldi_verbose_level >= 1) {
      CuDevice::Instantiate().PrintProfile();
    }
#endif

    if (num_done == 0) return -1;
    return 0;
  } catch(const std::exception &e) {
    KALDI_ERR << e.what();
    return -1;
  }
}
