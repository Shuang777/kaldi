// ivector2bin/gen-gmm-supervector.cc

// Copyright 2016  Hang Su

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

#include "util/common-utils.h"
#include "ivector2/ivector-extractor.h"


int main(int argc, char *argv[]) {
  try {
    typedef kaldi::int32 int32;
    using namespace kaldi;
    using namespace kaldi::ivector2;
    
    const char *usage =
        "Generate gmm supervector\n"
        "Usage: gen-gmm-supervector [options] <post-in> <feats-in> <num-gauss> <supvector-out>\n";

    bool binary = true;
    kaldi::ParseOptions po(usage);
    po.Register("binary", &binary, "Write output in binary mode");
    
    po.Read(argc, argv);

    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string posteriors_rspecifier = po.GetArg(1),
        feature_rspecifier = po.GetArg(2),
        supvector_wspecifier = po.GetArg(4);

    int32 num_gauss = atoi(po.GetArg(3).c_str());

    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader posteriors_reader(posteriors_rspecifier);
    DoubleVectorWriter supervector_writer(supvector_wspecifier);

    IvectorExtractorUtteranceStats stats;

    int32 num_done = 0, num_err = 0;

    Vector<double> supervector;
    for (; !feature_reader.Done(); feature_reader.Next()) {
      std::string key = feature_reader.Key();
      if (!posteriors_reader.HasKey(key)) {
        KALDI_WARN << "No posteriors for utterance " << key;
        num_err++;
        continue;
      }
      const Matrix<BaseFloat> &mat = feature_reader.Value();
      const Posterior &posterior = posteriors_reader.Value(key);

      int32 feat_dim = mat.NumCols();
      stats.Reset(num_gauss, feat_dim);
 
      if (static_cast<int32>(posterior.size()) != mat.NumRows()) {
        KALDI_WARN << "Size mismatch between posterior " << (posterior.size())
                   << " and features " << (mat.NumRows()) << " for utterance "
                   << key;
        num_err++;
        continue;
      }

      stats.AccStats(mat, posterior);

      stats.GetSupervector(supervector);
      
      supervector_writer.Write(key, supervector);

      num_done++;
     
    }

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}


