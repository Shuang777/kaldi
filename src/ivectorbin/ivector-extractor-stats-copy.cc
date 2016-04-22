// ivectorbin/ivector-extractor-stats-copy.cc

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

#include "util/common-utils.h"
#include "ivector/ivector-extractor.h"


int main(int argc, char *argv[]) {
  try {
    typedef kaldi::int32 int32;
    using namespace kaldi;
    using namespace kaldi::ivector;
    
    const char *usage =
        "Copy accumulators for training of iVector extractor\n"
        "Usage: ivector-extractor-stats-copy [options] <stats-in> <stats-out>\n";

    ParseOptions po(usage);
    bool binary = true;
    po.Register("binary", &binary, "Write output in binary mode");
    
    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string stats_rxfilename = po.GetArg(1),
                stats_wxfilename = po.GetArg(2);

    IvectorExtractorStats stats;

    {
      bool binary_in;
      Input ki(stats_rxfilename, &binary_in);
      stats.Read(ki.Stream(), binary_in);
    }    

    WriteKaldiObject(stats, stats_wxfilename, binary);
    
    KALDI_LOG << "Wrote stats to " << stats_wxfilename;

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}


