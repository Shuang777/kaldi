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
        "Usage:  nnet-to-multi-merge-nnet [options] <nnet-in-subnnet-1> <...> <nnet-subnnet-N> <merge-layer> <multi-nnet-out>\n"
        "e.g.:\n"
        " nnet-to-multi-merge-nnet --binary=false nnet1.mdl nnet2.mdl InverseEntropy multi_nnet.mdl\n";


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
    multi_nnet.PushToInSubNnet();

    for (int32 i=2; i<po.NumArgs()-1; i++) {
      std::string nnet_subnnet_filename = po.GetArg(i);
      Nnet nnet;
      bool binary_read;
      Input ki(nnet_subnnet_filename, &binary_read);
      nnet.Read(ki.Stream(), binary_read);
      multi_nnet.AddInSubNnet(nnet);
    }

    std::string merge_layer = po.GetArg(po.NumArgs()-1);
    multi_nnet.AddMergeLayer(merge_layer);
    
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


