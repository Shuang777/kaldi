// bin/copy-vector.cc

// Copyright 2009-2011  Microsoft Corporation

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
#include "matrix/kaldi-vector.h"
#include "transform/transform-common.h"
#include "nnet/nnet-randomizer.h"
#include "ivector/ivector-randomizer.h"

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;

    const char *usage =
        "Copy matrices, or archives of matrices (e.g. features or transforms)\n"
        "Also see copy-feats which has other format options\n"
        "\n"
        "Usage: randomize-int-vector [options] <vector-in-rspecifier> <vector-out-wspecifier>\n"
        "  or: copy-vector [options] <vector-in-rxfilename> <vector-out-wxfilename>\n"
        " e.g.: copy-vector --binary=false 1.mat -\n"
        "   copy-vector ark:2.trans ark,t:-\n"
        "See also: copy-feats\n";
    
    bool binary = true;
    ParseOptions po(usage);

    NnetDataRandomizerOptions rnd_opts;
    rnd_opts.Register(&po);

    po.Register("binary", &binary, "Write in binary mode (only relevant if output is a wxfilename)");

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    Int32VectorRandomizer feature_randomizer(rnd_opts);    

    std::string vector_in_fn = po.GetArg(1),
        vector_out_fn = po.GetArg(2);

    // all these "fn"'s are either rspecifiers or filenames.

    bool in_is_rspecifier =
        (ClassifyRspecifier(vector_in_fn, NULL, NULL)
         != kNoRspecifier),
        out_is_wspecifier =
        (ClassifyWspecifier(vector_out_fn, NULL, NULL, NULL)
         != kNoWspecifier);

    if (in_is_rspecifier != out_is_wspecifier)
      KALDI_ERR << "Cannot mix archives with regular files (copying matrices)";
    
    if (!in_is_rspecifier) {
      std::vector<int32> vec;
      bool binary_in;
      Input ki(vector_in_fn, &binary_in);
      ReadIntegerVector(ki.Stream(), binary_in, &vec);
      
      feature_randomizer.AddData(vec);
      RandomizerMask randomizer_mask(rnd_opts);
      const std::vector<int32>& mask = randomizer_mask.Generate(feature_randomizer.NumFrames());
      feature_randomizer.Randomize(mask);

      for ( ; !feature_randomizer.Done(); feature_randomizer.Next()) {
        const std::vector<int32> vec_cv = feature_randomizer.Value();
        const std::vector<int32> vec_left = feature_randomizer.LeftOverValue();

        Output ko(vector_out_fn, binary);
        WriteIntegerVector(ko.Stream(), binary, vec_cv);
        WriteIntegerVector(ko.Stream(), binary, vec_left);
      }
      
      KALDI_LOG << "Copied vector to " << vector_out_fn;
      return 0;
    } else {
      KALDI_LOG << "Not supported!";
      return 1;
    }
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


