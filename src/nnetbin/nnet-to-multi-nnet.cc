// nnetbin/nnet-to-multi-nnet.cc

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
        "Convert Nnet to MultiNnet (only shared layers)\n"
        "Usage:  nnet-to-multi-nnet [options] <nnet-shared-in> <nnet-subnnet-1> <...> <nnet-subnnet-N> <multi-nnet-out>\n"
        "e.g.:\n"
        " nnet-to-multi-nnet --binary=false nnet.mdl multi_nnet.mdl\n";


    bool binary_write = true;
    
    ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");

    po.Read(argc, argv);

    if (po.NumArgs() < 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_in_filename = po.GetArg(1);

    MultiNnet multi_nnet; 
    {
      bool binary_read;
      Input ki(model_in_filename, &binary_read);
      multi_nnet.ReadSharedNnet(ki.Stream(), binary_read);
    }

    for (int32 i=2; i<po.NumArgs(); i++) {
      std::string nnet_subnnet_filename = po.GetArg(i);
      Nnet nnet;
      bool binary_read;
      Input ki(nnet_subnnet_filename, &binary_read);
      nnet.Read(ki.Stream(), binary_read);
      multi_nnet.AddSubNnet(nnet);
    }
    
    std::string model_out_filename = po.GetArg(po.NumArgs());
    {
      Output ko(model_out_filename, binary_write);
      multi_nnet.Write(ko.Stream(), binary_write);
    }

    KALDI_LOG << "Written model to " << model_out_filename;
    return 0;
  } catch(const std::exception& e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}


