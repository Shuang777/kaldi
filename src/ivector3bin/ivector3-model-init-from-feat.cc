// ivector3bin/ivector3-model-init-from-feat.cc

// Copyright 2016 Hang Su

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
#include "ivector3/ivector-extractor.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::ivector3;
    using kaldi::int32;

    const char *usage =
        "Initialize ivector-model\n"
        "Usage:  ivector3-model-init-from-feat [options] <posterior-rspecifier> <feat-rspecifier> <num-gauss> <ivector-model-out>\n"
        "e.g.:\n"
        " ivector3-model-init ark:1.post scp:feat.1.scp 8848 0.ie\n";

    bool binary = true;
    IvectorExtractorOptions ivector_opts;
    ParseOptions po(usage);
    po.Register("binary", &binary, "Write output in binary mode");
    ivector_opts.Register(&po);

    po.Read(argc, argv);

    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string posteriors_rspecifier = po.GetArg(1),
        feature_rspecifier = po.GetArg(2);
    
    int32 num_gauss = atoi(po.GetArg(3).c_str());
    std::string ivector_model_wxfilename = po.GetArg(4);

    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader posteriors_reader(posteriors_rspecifier);
    
    IvectorExtractorUtteranceStats stats;

    int32 num_done = 0, num_err = 0;

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
      bool need_2nd_order_stats = true;
      stats.Reset(num_gauss, feat_dim, need_2nd_order_stats);
 
      if (static_cast<int32>(posterior.size()) != mat.NumRows()) {
        KALDI_WARN << "Size mismatch between posterior " << (posterior.size())
                   << " and features " << (mat.NumRows()) << " for utterance "
                   << key;
        num_err++;
        continue;
      }

      stats.AccStats(mat, posterior);

      num_done++;
    }

    IvectorExtractor extractor(ivector_opts, stats);
    
    WriteKaldiObject(extractor, ivector_model_wxfilename, binary);

    KALDI_LOG << "Initialized iVector extractor with iVector dimension "
              << extractor.IvectorDim() << " and wrote it to "
              << ivector_model_wxfilename;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

