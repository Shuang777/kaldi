// ivector2bin/ivector-model-acc-stats.cc

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

int main(int argc, char *argv[]) {
  using namespace kaldi;
  using namespace kaldi::ivector2;
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "Accumulate stats for iVector extractor training\n"
        "Reads in supvectors and Gaussian-level posteriors (typically from a full GMM)\n"
        "Supports multiple threads, but won't be able to make use of too many at a time\n"
        "(e.g. more than about 4)\n"
        "Usage:  ivector-model-acc-stats [options] <model-in> <supvector-rspecifier> <stats-out>\n"
        "e.g.: \n"
        "  ivector-extractor-acc-stats 2.ie '$supervector' 2.1.acc\n";

    ParseOptions po(usage);
    bool binary = true;
    po.Register("binary", &binary, "Write output in binary mode");

    po.Read(argc, argv);
    
    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string ivector_extractor_rxfilename = po.GetArg(1),
        supvector_rspecifier = po.GetArg(2),
        accs_wxfilename = po.GetArg(3);


    // Initialize these Reader objects before reading the IvectorExtractor,
    // because it uses up a lot of memory and any fork() after that will
    // be in danger of causing an allocation failure.
    SequentialDoubleVectorReader supvector_reader(supvector_rspecifier);

    IvectorExtractor extractor;
    ReadKaldiObject(ivector_extractor_rxfilename, &extractor);
    
    IvectorExtractorStats stats(extractor);
    
    int32 num_done = 0;
    
    for (; !supvector_reader.Done(); supvector_reader.Next()) {
      std::string key = supvector_reader.Key();
      const Vector<double> &mat = supvector_reader.Value();
      stats.AccStatsForUtterance(extractor, mat);
      num_done++;
    }
    
    KALDI_LOG << "Done " << num_done << " files.";
    
    {
      Output ko(accs_wxfilename, binary);
      stats.Write(ko.Stream(), binary);
    }
    
    KALDI_LOG << "Wrote stats to " << accs_wxfilename;

    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
