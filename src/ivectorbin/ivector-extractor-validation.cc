// ivectorbin/ivector-extractor-acc-stats.cc

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

// this class is used to run the command
//  stats.AccStatsForUtterance(extractor, mat, posterior);
// in parallel.
class IvectorValidTask {
 public:
  IvectorValidTask(const IvectorExtractor &extractor,
              const Matrix<BaseFloat> &features,
              const Posterior &posterior,
              IvectorExtractorCVStats *stats,
              double lambda): extractor_(extractor),
                                    features_(features),
                                    posterior_(posterior),
                                    stats_(stats),
                                    lambda_(lambda) {}

  void operator () () {
    stats_->AccValidStatsForUtterance(extractor_, features_, posterior_, lambda_);
  }
  ~IvectorValidTask() { }  // the destructor doesn't have to do anything.
 private:
  const IvectorExtractor &extractor_;
  Matrix<BaseFloat> features_; // not a reference, since features come from a
                               // Table and the reference we get from that is
                               // not valid long-term.
  Posterior posterior_;  // as above.
  IvectorExtractorCVStats *stats_;
  double lambda_;
};



}



int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::ivector;
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "Perform cross validation on lambda for iVector extractor training\n"
        "Reads in features and Gaussian-level posteriors (typically from a full GMM)\n"
        "Supports multiple threads, but won't be able to make use of too many at a time\n"
        "(e.g. more than about 4)\n"
        "Usage:  ivector-extractor-cross-validation [options] <model-in> <feature-rspecifier>"
        "<posteriors-rspecifier>\n"
        "e.g.: \n"
        " fgmm-global-gselect-to-post 1.fgmm '$feats' 'ark:gunzip -c gselect.1.gz|' ark:- | \\\n"
        "  ivector-extractor-cross-validation 2.ie '$feats' ark,s,cs:-\n";

    ParseOptions po(usage);
    bool binary = true;
    IvectorExtractorStatsOptions stats_opts;
    TaskSequencerConfig sequencer_opts;
    po.Register("binary", &binary, "Write output in binary mode");
    stats_opts.Register(&po);
    sequencer_opts.Register(&po);

    double lambda = -1.0;   
    po.Register("lambda", &lambda, "Prior parameter for ivectors");

    po.Read(argc, argv);
    
    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string ivector_extractor_rxfilename = po.GetArg(1),
        feature_rspecifier = po.GetArg(2),
        posteriors_rspecifier = po.GetArg(3);


    // Initialize these Reader objects before reading the IvectorExtractor,
    // because it uses up a lot of memory and any fork() after that will
    // be in danger of causing an allocation failure.
    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader posteriors_reader(posteriors_rspecifier);


    // This is a bit of a mess... the code that reads in the extractor calls
    // ComputeDerivedVars, and it can do this multi-threaded, controlled by
    // g_num_threads.  So if the user specified the --num-threads option, which
    // goes to sequencer_opts in this case, copy it to g_num_threads.
    g_num_threads = sequencer_opts.num_threads;
    
    IvectorExtractor extractor;
    ReadKaldiObject(ivector_extractor_rxfilename, &extractor);
    
    if (lambda == -1) {   // This means it is not set by input argument
      lambda = extractor.GetLambda();
    }

    IvectorExtractorCVStats stats;
    
    int64 tot_t = 0;
    int32 num_done = 0, num_err = 0;
    
    {
      TaskSequencer<IvectorValidTask> sequencer(sequencer_opts);
      
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
          KALDI_WARN << "Size mismatch between posterior " << (posterior.size())
                     << " and features " << (mat.NumRows()) << " for utterance "
                     << key;
          num_err++;
          continue;
        }

        sequencer.Run(new IvectorValidTask(extractor, mat, posterior, &stats, lambda));

        tot_t += posterior.size();
        num_done++;
      }
      // destructor of "sequencer" will wait for any remaining tasks that
      // have not yet completed.
    }
    
    KALDI_LOG << "Done " << num_done << " files, " << num_err
              << " with errors.  Total frames " << tot_t;
    
    KALDI_LOG << "Log residue is " << stats.LogResidue()
              << " , residue is " << stats.Residue()
              << " , Log avg residue is " << stats.LogAvgResidue()
              << " , Avg residue is " << stats.AvgResidue()
              << " , Total Auxf per frame is " << stats.TotalAuxfPerFrame();
    
    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
