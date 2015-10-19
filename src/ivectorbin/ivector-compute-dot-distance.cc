// ivectorbin/ivector-compute-dot-products.cc

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


int main(int argc, char *argv[]) {
  using namespace kaldi;
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "See also: ivector-plda-scoring\n";
    
    ParseOptions po(usage);
    
    po.Read(argc, argv);
    
    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string feat_rspecifier = po.GetArg(1),
        scores_wxfilename = po.GetArg(2);

    int64 num_done = 0, num_err = 0;
    
    SequentialBaseFloatMatrixReader feature_reader(feat_rspecifier);
    
    bool binary = false;
    Output ko(scores_wxfilename, binary);

    for (; !feature_reader.Done(); feature_reader.Next()) {
      const Matrix<BaseFloat> &features = feature_reader.Value();
      int32 num_frames = features.NumRows();
      int32 ivector_dim = features.NumCols() / 2;
      ko.Stream() << feature_reader.Key();
      for (int32 i=0; i<num_frames; i++) {
        SubVector<BaseFloat> ivec_line(features, i);
        SubVector<BaseFloat> ivec1(ivec_line, 0, ivector_dim);
        SubVector<BaseFloat> ivec2(ivec_line, ivector_dim, ivector_dim);
        BaseFloat dot_prod = VecVec(ivec1, ivec2);
        ko.Stream() << "\t" << dot_prod;
      }
      ko.Stream() << endl;
      num_done++;
    }

    KALDI_LOG << "Processed " << num_done << " trials " << num_err
              << " had errors.";
    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
