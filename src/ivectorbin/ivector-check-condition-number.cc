// ivectorbin/ivector-extract.cc

// Copyright 2013  Daniel Povey

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
#include "ivector/ivector-extractor.h"
#include "thread/kaldi-task-sequence.h"

namespace kaldi {
using namespace kaldi::ivector;

// This class will be used to parallelize over multiple threads the job
// that this program does.  The work happens in the operator (), the
// output happens in the destructor.
class IvectorGetMinMaxEigTask {
 public:
  IvectorGetMinMaxEigTask(const IvectorExtractor &extractor,
                     std::string utt,
                     const Matrix<BaseFloat> &feats,
                     const Posterior &posterior) :
                     extractor_(extractor), utt_(utt), feats_(feats), posterior_(posterior) { }

  void operator () () {
    bool need_2nd_order_stats = false;
    
    IvectorExtractorUtteranceStats utt_stats(extractor_.NumGauss(),
                                             extractor_.FeatDim(),
                                             need_2nd_order_stats);
      
    utt_stats.AccStats(feats_, posterior_);
    
    extractor_.GetIvectorMinMaxEigenvalue(utt_stats, min_eig_, max_eig_);
  }
  ~IvectorGetMinMaxEigTask() {
    KALDI_LOG << "Ivector matrix V^T*W*V for utt "<< utt_ << " min eig value " << min_eig_ << " , max eig value "
              << max_eig_ << " , condition number " << max_eig_/min_eig_ << ".";
  }
 private:
  const IvectorExtractor &extractor_;
  std::string utt_;
  Matrix<BaseFloat> feats_;
  Posterior posterior_;
  double min_eig_;
  double max_eig_;
};



}


int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::ivector;
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "Extract iVectors for utterances, using a trained iVector extractor,\n"
        "and features and Gaussian-level posteriors\n"
        "Usage:  ivector-check-condition-number [options] <model-in> <feature-rspecifier>"
        "<posteriors-rspecifier>\n"
        "e.g.: \n"
        " fgmm-global-gselect-to-post 1.ubm '$feats' 'ark:gunzip -c gselect.1.gz|' ark:- | \\\n"
        "   ivector-check-condition-number final.ie '$feats' ark,s,cs:- \n";

    ParseOptions po(usage);
    bool derived_in = false;
    IvectorExtractorStatsOptions stats_opts;
    TaskSequencerConfig sequencer_config;
    po.Register("derived-in", &derived_in, "Read extractor with derived vars (default = false)");

    stats_opts.Register(&po);
    sequencer_config.Register(&po);
    
    po.Read(argc, argv);
    
    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string ivector_extractor_rxfilename = po.GetArg(1),
        feature_rspecifier = po.GetArg(2),
        posteriors_rspecifier = po.GetArg(3);

    // g_num_threads affects how ComputeDerivedVars is called when we read the
    // extractor.
    g_num_threads = sequencer_config.num_threads; 
    IvectorExtractor extractor;
    {
      bool binary_in;
      Input ki(ivector_extractor_rxfilename, &binary_in);
      extractor.Read(ki.Stream(), binary_in, derived_in);
    }

    int64 tot_t = 0;
    int32 num_done = 0, num_err = 0;
    
    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader posteriors_reader(posteriors_rspecifier);

    {
      TaskSequencer<IvectorGetMinMaxEigTask> sequencer(sequencer_config);
      for (; !feature_reader.Done(); feature_reader.Next()) {
        std::string key = feature_reader.Key();
        if (!posteriors_reader.HasKey(key)) {
          KALDI_WARN << "No posteriors for utterance " << key;
          num_err++;
          continue;
        }
        const Matrix<BaseFloat> &mat = feature_reader.Value();
        const Posterior &posterior = posteriors_reader.Value(key);

        if (static_cast<int32>(posterior.size()) != mat.NumRows()) {
          KALDI_WARN << "Size mismatch between posterior " << posterior.size()
                     << " and features " << mat.NumRows() << " for utterance "
                     << key;
          num_err++;
          continue;
        }

        sequencer.Run(new IvectorGetMinMaxEigTask(extractor, key, mat, posterior));
                      
        tot_t += posterior.size();
        num_done++;
      }
      // Destructor of "sequencer" will wait for any remaining tasks.
    }

    KALDI_LOG << "Done " << num_done << " files, " << num_err
              << " with errors.  Total frames " << tot_t;

    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
