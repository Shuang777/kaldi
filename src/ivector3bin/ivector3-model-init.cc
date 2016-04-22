// ivector3bin/ivector3-model-init.cc

// Copyright 2013  Hang Su

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
#include "ivector3/ivector-extractor.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::ivector3;
    using kaldi::int32;

    const char *usage =
        "Initialize ivector3-model\n"
        "Usage:  ivector3-model-init [options] <fgmm-in> <ivector-extractor-out>\n"
        "e.g.:\n"
        " ivector3-model-init 4.fgmm 0.ie\n";

    bool binary = true;
    IvectorExtractorOptions ivector_opts;
    ParseOptions po(usage);
    po.Register("binary", &binary, "Write output in binary mode");
    double lambda = 1.0;
    po.Register("lambda", &lambda, "lambda for ivector regularization");
    ivector_opts.Register(&po);

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string fgmm_rxfilename = po.GetArg(1),
        ivector_model_wxfilename = po.GetArg(2);
        
    FullGmm fgmm;
    ReadKaldiObject(fgmm_rxfilename, &fgmm);

    bool compute_derived = false;
    IvectorExtractor extractor(ivector_opts, fgmm, lambda, compute_derived);

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

