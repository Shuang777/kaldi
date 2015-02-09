// nnetbin/multi-nnet-split.cc

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
        "Split shared layers and assign them to each of the subnnets\n"
        "Usage:  multi-nnet-split [options] <multi-nnet-in> <num-shared-layers-to-split-front> <num-shared-layers-to-split> <multi-nnet-out>\n"
        "e.g.:\n"
        " multi-nnet-split --binary=false multi_nnet.mdl 0 2 multi_nnet_new.mdl\n";


    bool binary_write = true;
    
    ParseOptions po(usage);
    po.Register("binary", &binary_write, "Write output in binary mode");

    po.Read(argc, argv);

    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string multi_nnet_in_filename = po.GetArg(1);
    int32 num_layers_to_split_front = atoi(po.GetArg(2).c_str());
    int32 num_layers_to_split = atoi(po.GetArg(3).c_str());
    std::string multi_nnet_out_filename = po.GetArg(4);

    MultiNnet multi_nnet;
    {
      bool binary_read;
      Input ki(multi_nnet_in_filename, &binary_read);
      multi_nnet.Read(ki.Stream(), binary_read);
    }
    
    multi_nnet.SplitFront(num_layers_to_split_front);
    multi_nnet.Split(num_layers_to_split);

    {
      Output ko(multi_nnet_out_filename, binary_write);
      multi_nnet.Write(ko.Stream(), binary_write);
    }

    KALDI_LOG << "Written model to " << multi_nnet_out_filename;
    return 0;
  } catch(const std::exception& e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}


