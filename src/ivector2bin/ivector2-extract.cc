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
#include "ivector2/ivector-extractor.h"
#include <algorithm>

int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::ivector2;
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "Extract iVectors for utterances, using a trained iVector extractor,\n"
        "and features and Gaussian-level posteriors\n"
        "Usage:  ivector-extract [options] <model-in> <feature-rspecifier>"
        "<posteriors-rspecifier> <ivector-wspecifier>\n"
        "e.g.: \n"
        "  ivector-extract final.ie '$supervectors' ark,t:ivectors.1.ark\n";

    ParseOptions po(usage);
    bool compute_objf = false;
    po.Register("compute-objf", &compute_objf, "If true, compute the objective function");

    po.Read(argc, argv);
    
    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string ivector_extractor_rxfilename = po.GetArg(1),
        feature_rspecifier = po.GetArg(2),
        ivectors_wspecifier = po.GetArg(3);

    IvectorExtractor extractor;
    {
      bool binary_in;
      Input ki(ivector_extractor_rxfilename, &binary_in);
      extractor.Read(ki.Stream(), binary_in);
    }

    double tot_auxf = 0.0;
    int32 num_done = 0;
    
    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    BaseFloatVectorWriter ivector_writer(ivectors_wspecifier);

    Vector<double> ivector;
    for (; !feature_reader.Done(); feature_reader.Next()) {
      std::string key = feature_reader.Key();
      const Matrix<BaseFloat> &supervector = feature_reader.Value();

      ivector.Resize(extractor.IvectorDim());
      extractor.GetIvectorDistribution(supervector, &ivector);
      ivector_writer.Write(key, Vector<BaseFloat>(ivector));

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
