// gmmbin/amgmm-gselect-post.cc

// Copyright   2016       Hang Su

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


#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "gmm/am-diag-gmm.h"
#include "hmm/posterior.h"
#include "gmm/gmm-pdf-prior.h"

using std::vector;
using namespace kaldi;

double ApplySoftMax(std::vector<std::pair<BaseFloat, int> > & pairs) {
  KALDI_ASSERT(pairs.size() > 0);
  BaseFloat max = pairs.front().first;
  for (int i = 1; i < pairs.size(); i++) {
    if (max < pairs[i].first) {
      max = pairs[i].first;
    }
  }
  BaseFloat sum = 0;
  for (int i = 0; i < pairs.size(); i++) {
    sum += (pairs[i].first = Exp(pairs[i].first - max));
  }
  for (int i = 0; i < pairs.size(); i++) {
    pairs[i].first /= sum;
  }
  return max + Log(sum);
}

int main(int argc, char *argv[]) {
  try {
    const char *usage =
        "Precompute Gaussian indices and convert immediately to top-n\n"
        "posteriors (useful in iVector extraction with diagonal UBMs)\n"
        "See also: gmm-gselect, fgmm-gselect, fgmm-global-gselect-to-post\n"
        " (e.g. in training UBMs, SGMMs, tied-mixture systems)\n"
        " For each frame, gives a list of the n best Gaussian indices,\n"
        " sorted from best to worst.\n"
        "Usage: \n"
        " amgmm-gselect-post [options] <model-in> <feature-rspecifier> <post-wspecifier>\n"
        "e.g.: amgmm-gselect-post --n=20 final.mdl \"ark:feature-command |\" \"ark,t:|gzip -c >post.1.gz\"\n";
    
    typedef kaldi::int32 int32;
    ParseOptions po(usage);

    PdfPriorOptions prior_opts;
    prior_opts.Register(&po);

    int32 num_post = 50;
    BaseFloat min_post = 0.0;
    po.Register("n", &num_post, "Number of Gaussians to keep per frame\n");
    po.Register("min-post", &min_post, "Minimum posterior we will output "
                "before pruning and renormalizing (e.g. 0.01)");
    std::string post_rspecifier = "";
    po.Register("post-rspecifier", &post_rspecifier, "Given posterior to restrict search space\n");

    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_filename = po.GetArg(1),
        feature_rspecifier = po.GetArg(2),
        post_wspecifier = po.GetArg(3);
   

    AmDiagGmm am_gmm;
    TransitionModel trans_model;
    {
      bool binary;
      Input ki(model_filename, &binary);
      trans_model.Read(ki.Stream(), binary);
      am_gmm.Read(ki.Stream(), binary);
    }
 
    Vector<BaseFloat> log_priors;
    if (prior_opts.class_frame_counts != "") {
      PdfPrior pdf_prior(prior_opts);
      pdf_prior.GetLogPriors(&log_priors);
    } else {
      log_priors.Resize(am_gmm.Dim());
    }

    KALDI_ASSERT(num_post > 0);
    KALDI_ASSERT(min_post < 1.0);
    int32 num_states = am_gmm.NumPdfs();
    if (num_post > num_states) {
      KALDI_WARN << "You asked for " << num_post << " states but AmGMM "
                 << "only has " << num_states << ", returning this many. ";
      num_post = num_states;
    }
    
    double tot_like = 0.0;
    kaldi::int64 tot_t = 0;
    
    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader post_reader;
    if (post_rspecifier != "") {
      post_reader.Open(post_rspecifier);
    }
    PosteriorWriter post_writer(post_wspecifier);
    
    int32 num_done = 0, num_err = 0;
    for (; !feature_reader.Done(); feature_reader.Next()) {
      std::string utt = feature_reader.Key();
      const Matrix<BaseFloat> &feats = feature_reader.Value();
      int32 T = feats.NumRows();
      if (T == 0) {
        KALDI_WARN << "Empty features for utterance " << utt;
        num_err++;
        continue;
      }
      if (feats.NumCols() != am_gmm.Dim()) {
        KALDI_WARN << "Dimension mismatch for utterance " << utt
                   << ": got " << feats.NumCols() << ", expected " << am_gmm.Dim();
        num_err++;
        continue;
      }
      
      if (post_rspecifier != "" && !post_reader.HasKey(utt)) {
        KALDI_WARN << "Utterance " << utt << " not found in input posterior file";
        num_err++;
        continue;
      }
      const Posterior &old_post = (post_rspecifier != "") ? post_reader.Value(utt) : Posterior();
      if (post_rspecifier != "" && feats.NumRows() != old_post.size()) {
        KALDI_WARN << "Feature and posterior has differen number of frames for utterance " << utt;
        num_err++;
        continue;
      }

      Posterior post(T);
      double log_like_this_file = 0;

      for (int32 i = 0; i < feats.NumRows(); i++) {
        std::vector<std::pair<BaseFloat, int32> > pairs;
        if (post_rspecifier != "") {
          for (int32 j = 0; j < old_post[i].size(); j++) {
            int32 s = old_post[i][j].first;
            double logll = am_gmm.LogLikelihood(s, feats.Row(i));
            pairs.push_back(std::make_pair(logll+log_priors(s), s));
          }
        } else {
          for (int32 s = 0 ; s < num_states; s++) {
            double logll = am_gmm.LogLikelihood(s, feats.Row(i));
            pairs.push_back(std::make_pair(logll+log_priors(s), s));
          }
          sort(pairs.rbegin(), pairs.rend());
          pairs.erase(pairs.begin()+num_post, pairs.end());
        }
        log_like_this_file += ApplySoftMax(pairs);
        // now pairs contain posts
        for (int32 j = 0; j < pairs.size(); j++) {
          if (pairs[j].first > min_post)
            post[i].push_back(std::make_pair(pairs[j].second, pairs[j].first));
        }
      }

      KALDI_VLOG(1) << "Processed utterance " << utt << ", average likelihood "
                    << (log_like_this_file / T) << " over " << T << " frames";
      tot_like += log_like_this_file;
      tot_t += T;

      post_writer.Write(utt, post);
      num_done++;
    }

    KALDI_LOG << "Done " << num_done << " files, " << num_err
              << " with errors, average UBM log-likelihood is "
              << (tot_like/tot_t) << " over " << tot_t << " frames.";
    
    if (num_done != 0) return 0;
    else return 1;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


