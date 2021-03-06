// ivectorbin/ivector-extractor-init.cc

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
#include "gmm/full-gmm.h"
#include "ivector/ivector-extractor.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::ivector;
    using kaldi::int32;

    const char *usage =
        "Initialize ivector-extractor\n"
        "Usage:  ivector-extractor-init [options] <ivector-extractor-out> <ivector-extractor-out>\n"
        "e.g.:\n"
        " ivector-extractor-init 4.fgmm 0.ie\n";

    bool binary = true;
    bool derived_in = false;
    bool derived_out = false;
    IvectorExtractorOptions ivector_opts;
    ParseOptions po(usage);
    po.Register("binary", &binary, "Write output in binary mode");
    po.Register("derived-in", &derived_in, "Read extractor with derived vars (default = false)");
    po.Register("derived-out", &derived_out, "Write extractor with derived vars (default = false)");
    ivector_opts.Register(&po);



    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }


    std::string ivector_extractor_rxfilename = po.GetArg(1),
                ivector_extractor_wxfilename = po.GetArg(2);
        
    IvectorExtractor extractor;
    {
      bool binary_in;
      Input ki(ivector_extractor_rxfilename, &binary_in);
      extractor.Read(ki.Stream(), binary_in, derived_in);
    }
    {
      Output ko(ivector_extractor_wxfilename, binary);
      extractor.Write(ko.Stream(), binary, derived_out);
    }

    KALDI_LOG << "Initialized iVector extractor with iVector dimension "
              << extractor.IvectorDim() << " and wrote it to "
              << ivector_extractor_wxfilename;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

