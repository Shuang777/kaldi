// ivector2bin/ivector-model-copy.cc

// Copyright    2016  Hang Su

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
#include "thread/kaldi-thread.h"

int main(int argc, char *argv[]) {
  try {
    typedef kaldi::int32 int32;
    using namespace kaldi;
    using namespace kaldi::ivector2;
    
    const char *usage =
        "Copy ivector extractor\n"
        "Usage: ivector-model-copy [options] <model-in> <model-out>\n";

    ParseOptions po(usage);
    bool binary = true;
    po.Register("binary", &binary, "Write output in binary mode");
    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_rxfilename = po.GetArg(1),
                model_wxfilename = po.GetArg(2);


    KALDI_LOG << "Reading model";
    IvectorExtractor extractor;
    ReadKaldiObject(model_rxfilename, &extractor);

    {
      Output ko(model_wxfilename, binary);
      extractor.Write(ko.Stream(), binary);
    }
 
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}


