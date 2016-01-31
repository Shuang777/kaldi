// featbin/filter-transform.cc

// Copyright 2009-2012  Microsoft Corporation
//                      Johns Hopkins University (author: Daniel Povey)

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
#include "matrix/kaldi-matrix.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;

    const char *usage =
        "Filter transforms for certain speakers and save the result\n"
        "Usage: filter-transform [options] <transform-rspecifier> <spk2utt-rspecifier> <transform-wspecifier>\n";
        
    ParseOptions po(usage);
    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string transform_rspecifier = po.GetArg(1);
    std::string spk2utt_rspecifier = po.GetArg(2);
    std::string transform_wspecifier = po.GetArg(3);

    BaseFloatMatrixWriter transform_writer(transform_wspecifier);
    RandomAccessBaseFloatMatrixReaderMapped transform_reader;

    // an rspecifier -> not a global transform.
    if (!transform_reader.Open(transform_rspecifier,"")) {
      KALDI_ERR << "Problem opening transforms with rspecifier "
                << '"' << transform_rspecifier << '"';
    }

    int32 num_done = 0, num_error = 0;
    
    SequentialTokenVectorReader spk2utt_reader(spk2utt_rspecifier);

    for (; !spk2utt_reader.Done(); spk2utt_reader.Next()) {
      std::string spk = spk2utt_reader.Key();

      if (!transform_reader.HasKey(spk)) {
        KALDI_WARN << "No fMLLR transform available for speaker "
                   << spk << ", producing no output for this utterance";
        num_error++;
        continue;
      }
      const Matrix<BaseFloat> &trans = transform_reader.Value(spk);

      transform_writer.Write(spk, trans);

      num_done++;
    }
    KALDI_LOG << "Filtered transform to " << num_done << " utterances; " << num_error
              << " had errors.";

    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
