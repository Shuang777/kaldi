// fgmmbin/fgmm-global-acc-stats-print.cc

// Copyright 2016   Hang Su

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
#include "gmm/model-common.h"
#include "gmm/full-gmm.h"
#include "gmm/diag-gmm.h"
#include "gmm/mle-full-gmm.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;

    const char *usage =
        "Copy stats for diagnosis.\n"
        "Usage:  fgmm-global-acc-stats-print [options] <acc-in> <acc-out>\n"
        "e.g.: fgmm-global-acc-stats 1.acc 1.acc.txt\n";

    ParseOptions po(usage);
    bool binary = true;
    po.Register("binary", &binary, "Write output in binary mode");
    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string accs_rxfilename = po.GetArg(1),
      accs_wxfilename = po.GetArg(2);

    AccumFullGmm fgmm_accs;
    {
      bool binary_read;
      Input ki(accs_rxfilename, &binary_read);
      fgmm_accs.Read(ki.Stream(), binary_read, false /*not add read values*/);
    }

    WriteKaldiObject(fgmm_accs, accs_wxfilename, binary);
    KALDI_LOG << "Written accs to " << accs_wxfilename;
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
