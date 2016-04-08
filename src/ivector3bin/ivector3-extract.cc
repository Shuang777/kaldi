// ivector2bin/ivector2-extract.cc

// Copyright 2013  Daniel Povey
//           2016  Hang Su

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
#include "ivector3/ivector-extractor.h"
#include <algorithm>

int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::ivector3;
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "Extract iVectors for utterances, using a trained iVector extractor,\n"
        "and supvectors and Gaussian-level posteriors\n"
        "Usage:  ivector-extract [options] <model-in> <posteriors-rspecifier>"
        "<feat-rspecifier> <ivector-wspecifier>\n"
        "e.g.: \n"
        "  ivector-extract final.ie 'ark:1.post' 'ark:1.feat' ark,t:ivectors.1.ark\n";

    ParseOptions po(usage);
    bool compute_objf = false;
    po.Register("compute-objf", &compute_objf, "If true, compute the objective function");

    po.Read(argc, argv);
    
    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string ivector_extractor_rxfilename = po.GetArg(1),
        posterior_rspecifier = po.GetArg(2),
        feature_rspecifier = po.GetArg(3),
        ivectors_wspecifier = po.GetArg(4);

    IvectorExtractor extractor;
    {
      bool binary_in;
      Input ki(ivector_extractor_rxfilename, &binary_in);
      extractor.Read(ki.Stream(), binary_in);
    }

    double tot_auxf = 0.0;
    
    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader posteriors_reader(posterior_rspecifier);
    DoubleVectorWriter ivector_writer(ivectors_wspecifier);

    Vector<double> ivector(extractor.IvectorDim());

    IvectorExtractorUtteranceStats stats;

    int32 num_done = 0, num_err = 0;
    double this_auxf = 0;
    int32 feat_dim = extractor.FeatDim();
    int32 num_gauss = extractor.NumGauss();
    bool need_2nd_order_stats = false;
    if (compute_objf) 
      need_2nd_order_stats = true;

    for (; !feature_reader.Done(); feature_reader.Next()) {
      std::string key = feature_reader.Key();
      if (!posteriors_reader.HasKey(key)) {
        KALDI_WARN << "No posteriors for utterance " << key;
        num_err++;
        continue;
      }
      const Matrix<BaseFloat> &mat = feature_reader.Value();
      const Posterior &posterior = posteriors_reader.Value(key);

      stats.Reset(num_gauss, feat_dim, need_2nd_order_stats);
      stats.AccStats(mat, posterior);
     
      if (static_cast<int32>(posterior.size()) != mat.NumRows()) {
        KALDI_WARN << "Size mismatch between posterior " << (posterior.size())
                   << " and features " << (mat.NumRows()) << " for utterance "
                   << key;
        num_err++;
        continue;
      }

      double *auxf_ptr = NULL;
      if (compute_objf)
        auxf_ptr = &this_auxf;

      bool for_scoring = true;
      extractor.GetIvectorDistribution(stats, &ivector, NULL, NULL, auxf_ptr, for_scoring);
      
      tot_auxf += this_auxf;

      ivector_writer.Write(key, ivector);

      num_done++;
    }

    KALDI_LOG << "Done " << num_done << " files.";

    if (compute_objf)
      KALDI_LOG << "Overall average objective-function estimating "
                << "ivector was " << (tot_auxf / num_done) << " per vector "
                << " over " << num_done << " vectors.";

    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
