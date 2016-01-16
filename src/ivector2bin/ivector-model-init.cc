// ivector2bin/ivector-model-init.cc

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
#include "ivector2/ivector-extractor.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::ivector2;
    using kaldi::int32;

    const char *usage =
        "Initialize ivector-model\n"
        "Usage:  ivector-model-init [options] <supervector-in> <ivector-model-out>\n"
        "e.g.:\n"
        " ivector-extractor-init scp:ivector.1.scp 0.ie\n";

    bool binary = true;
    int32 num_gauss = 1;
    IvectorExtractorOptions ivector_opts;
    ParseOptions po(usage);
    po.Register("binary", &binary, "Write output in binary mode");
    po.Register("num-gauss", &num_gauss, "Number of Gaussians in supervector");
    ivector_opts.Register(&po);

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string supvector_rspecifier = po.GetArg(1),
        ivector_model_wxfilename = po.GetArg(2);

    SequentialDoubleVectorReader supvector_reader(supvector_rspecifier);
    const Vector<double> &sample_feat = supvector_reader.Value();
    int32 feat_dim = sample_feat.Dim() / num_gauss;
        
    IvectorExtractorInitStats stats(feat_dim, num_gauss);

    for (; !supvector_reader.Done(); supvector_reader.Next()) {
      const Vector<double>  &this_feat = supvector_reader.Value();
      stats.AccStats(this_feat);
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

