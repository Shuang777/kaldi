// nnetbin/multi-nnet-to-nnet.cc

// Copyright 2015  International Computer Science Institute (Author: Hang Su)

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
#include "nnet/nnet-nnet.h"
#include "nnet/nnet-multi-nnet.h"

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::nnet1;
    typedef kaldi::int32 int32;

    const char *usage =
        "Extract Nnet from MultiNnet\n"
        "Usage:  multi-nnet-to-nnet [options] <multi-nnet-in> <subnnet-id> <nnet-out>\n"
        "e.g.:\n"
        " multi-nnet-to-nnet --binary=false multi_nnet.mdl 1 nnet.mdl\n";


    bool binary_write = true;
    
    ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");

    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_in_filename = po.GetArg(1);
    int32 subnnet = atoi(po.GetArg(2).c_str());
    std::string model_out_filename = po.GetArg(3);

    MultiNnet multi_nnet; 
    {
      bool binary_read;
      Input ki(model_in_filename, &binary_read);
      multi_nnet.Read(ki.Stream(), binary_read);
    }
    
    {
      Output ko(model_out_filename, binary_write);
      multi_nnet.WriteSubNnet(ko.Stream(), binary_write, subnnet);
    }

    KALDI_LOG << "Written model to " << model_out_filename;
    return 0;
  } catch(const std::exception& e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}


