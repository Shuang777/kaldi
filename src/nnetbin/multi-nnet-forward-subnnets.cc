// nnetbin/multi-nnet-forward.cc

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
  try {
    using namespace kaldi;
    using namespace kaldi::nnet1;
    typedef kaldi::int32 int32;
    const char *usage =
        "Perform forward pass through Multi Neural Network.\n"
        "\n"
        "Usage:  multi-nnet-forward-subnnets [options] <model-in> <feature-rspecifier-list> <feature-wspecifier>\n"
        "e.g.: \n"
        " multi-nnet-forward --subnnet-id=0 multi_nnet feats.list ark:mlpoutput.ark\n";

    ParseOptions po(usage);

    PdfPriorOptions prior_opts;
    prior_opts.Register(&po);

    std::string feature_transform_list;
    po.Register("feature-transform-list", &feature_transform_list, "Feature transform in front of main network (in nnet format)");

    bool no_softmax = false;
    po.Register("no-softmax", &no_softmax, "No softmax on MLP output (or remove it if found), the pre-softmax activations will be used as log-likelihoods, log-priors will be subtracted");
    bool apply_log = false;
    po.Register("apply-log", &apply_log, "Transform MLP output to logscale");

    std::string use_gpu="no";
    po.Register("use-gpu", &use_gpu, "yes|no|optional, only has effect if compiled with CUDA"); 
    
    int32 subnnet_id = 0;
    po.Register("subnnet-id", &subnnet_id, "subnnet id for output layer selection");

    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_filename = po.GetArg(1);
    std::string feature_list = po.GetArg(2);
    std::string feature_wspecifier = po.GetArg(3);

    std::vector<std::string> feature_rspecifiers;

    {
      bool featlist_binary = false;
      Input ki(feature_list, &featlist_binary);
      std::istream &is = ki.Stream();
      string feature_rspecifier;
      while (getline(is, feature_rspecifier)) {
        feature_rspecifiers.push_back(feature_rspecifier);
      }
    }

    const int32 num_features = feature_rspecifiers.size();

    //Select the GPU
#if HAVE_CUDA==1
    CuDevice::Instantiate().SelectGpuId(use_gpu);
    CuDevice::Instantiate().DisableCaching();
#endif

    std::vector<Nnet> nnet_transfs(num_features);
    if (feature_transform_list != "") {
      bool transform_list_binary = false;
      Input ki(feature_transform_list, &transform_list_binary);
      std::istream &is = ki.Stream();
      string feature_transform;
      int32 i = 0;
      while (getline(is, feature_transform)) {
        nnet_transfs[i].Read(feature_transform);
        i++;
      }
    }

    MultiNnet multi_nnet;
    multi_nnet.Read(model_filename);
    //optionally remove softmax
    if (no_softmax && multi_nnet.GetLastComponent().GetType() == kaldi::nnet1::Component::kSoftmax) {
      KALDI_LOG << "Removing softmax from the nnet " << model_filename;
      multi_nnet.RemoveLastSoftmax();
    }
    //check for some non-sense option combinations
    if (apply_log && no_softmax) {
      KALDI_ERR << "Nonsense option combination : --apply-log=true and --no-softmax=true";
    }
    
    PdfPrior pdf_prior(prior_opts);
    if (prior_opts.class_frame_counts != "" && (!no_softmax && !apply_log)) {
      KALDI_ERR << "Option --class-frame-counts has to be used together with "
                << "--no-softmax or --apply-log";
    }

    // disable dropout
    for (int32 i=0; i<num_features; i++) {
      nnet_transfs[i].SetDropoutRetention(1.0);
    }
    multi_nnet.SetDropoutRetention(1.0);

    kaldi::int64 tot_t = 0;

    std::vector<SequentialBaseFloatMatrixReader> feature_readers(num_features);
    for (int32 i=0; i<num_features; i++) {
      feature_readers[i].Open(feature_rspecifiers[i]);
    }
    BaseFloatMatrixWriter feature_writer(feature_wspecifier);

    std::vector<CuMatrix<BaseFloat> > feats(num_features);
    std::vector<CuMatrix<BaseFloat> *> feats_transfs(num_features);
    for (int32 i=0; i<num_features; i++) {
      feats_transfs[i] = new CuMatrix<BaseFloat>();
    }

    CuMatrix<BaseFloat> nnet_out;
    Matrix<BaseFloat> nnet_out_host;

    Timer time;
    double time_now = 0;
    int32 num_done = 0;
    // iterate over all feature files
    while (!feature_readers[0].Done()) {
      std::string feat_key = feature_readers[0].Key();
      for (int32 i=0; i<num_features; i++) {
        const Matrix<BaseFloat> &mat = feature_readers[i].Value();

        if (feature_readers[i].Key() != feat_key) {
          KALDI_ERR << "Utterance key " << feature_readers[i].Key() << " does not match that in feature-rspecifier=1 " << feat_key;
        }
        if (i == 0) {
          KALDI_VLOG(2) << "Processing utterance " << num_done+1 
                        << ", " << feature_readers[i].Key() 
                        << ", " << mat.NumRows() << "frm";
        }

        //check for NaN/inf
        BaseFloat sum = mat.Sum();
        if (!KALDI_ISFINITE(sum)) {
          KALDI_ERR << "NaN or inf found in features of " << feature_readers[i].Key();
        }
      
        // push it to gpu
        feats[i] = mat;
        // fwd-pass
        nnet_transfs[i].Feedforward(feats[i], feats_transfs[i]);
      }
 
      // fwd-pass
      multi_nnet.Feedforward(feats_transfs, subnnet_id, &nnet_out);
      
      // convert posteriors to log-posteriors
      if (apply_log) {
        nnet_out.ApplyLog();
      }
     
      // subtract log-priors from log-posteriors to get quasi-likelihoods
      if (prior_opts.class_frame_counts != "" && (no_softmax || apply_log)) {
        pdf_prior.SubtractOnLogpost(&nnet_out);
      }
     
      //download from GPU
      nnet_out_host.Resize(nnet_out.NumRows(), nnet_out.NumCols());
      nnet_out.CopyToMat(&nnet_out_host);

      //check for NaN/inf
      for (int32 r = 0; r < nnet_out_host.NumRows(); r++) {
        for (int32 c = 0; c < nnet_out_host.NumCols(); c++) {
          BaseFloat val = nnet_out_host(r,c);
          if (val != val) KALDI_ERR << "NaN in NNet output of : " << feature_readers[0].Key();
          if (val == std::numeric_limits<BaseFloat>::infinity())
            KALDI_ERR << "inf in NNet coutput of : " << feature_readers[0].Key();
        }
      }

      // write
      feature_writer.Write(feature_readers[0].Key(), nnet_out_host);

      // progress log
      if (num_done % 100 == 0) {
        time_now = time.Elapsed();
        KALDI_VLOG(1) << "After " << num_done << " utterances: time elapsed = "
                      << time_now/60 << " min; processed " << tot_t/time_now
                      << " frames per second.";
      }
      num_done++;
      tot_t += nnet_out_host.NumRows();

      for (int32 i=0; i<num_features; i++) {
        feature_readers[i].Next();
      }
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
