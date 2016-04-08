// ivector2bin/ivector-model-est.cc

// Copyright 2013  Daniel Povey
//           2016  Hang Su

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
#include "ivector3/ivector-extractor.h"
#include "thread/kaldi-thread.h"

int main(int argc, char *argv[]) {
  try {
    typedef kaldi::int32 int32;
    using namespace kaldi;
    using namespace kaldi::ivector3;
    
    const char *usage =
        "Do model re-estimation / objective computation of iVector extractor (this is\n"
        "the update phase of a single pass of E-M)\n"
        "Usage: ivector-model-est [options] <model-in> <stats-in> <model-out>\n";

    bool binary = true;
    IvectorExtractorEstimationOptions update_opts;    
    kaldi::ParseOptions po(usage);
    po.Register("binary", &binary, "Write output in binary mode");
    bool check_change = false;
    po.Register("check-change", &check_change, "Check auxf value before model update");
    bool update_model = true;
    po.Register("update-model", &update_model, "Update the model by performing M-step");
    po.Register("num-threads", &g_num_threads,
                "Number of threads used in update");
    
    update_opts.Register(&po);
    
    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_rxfilename = po.GetArg(1),
        stats_rxfilename = po.GetArg(2),
        model_wxfilename = po.GetArg(3);

    KALDI_LOG << "Reading model";
    IvectorExtractor extractor;
    ReadKaldiObject(model_rxfilename, &extractor);

    KALDI_LOG << "Reading statistics";
    IvectorExtractorStats stats;
    ReadKaldiObject(stats_rxfilename, &stats);
    
    double auxf_old = 0;
    if (check_change == true) {
      auxf_old = stats.GetAuxfValue(extractor);
      KALDI_LOG << "Aux-function value before update is " << auxf_old;
    }

    if (update_model == true) {
      stats.Update(extractor, update_opts);
      WriteKaldiObject(extractor, model_wxfilename, binary);
      KALDI_LOG << "Updated model and wrote it to "
                << model_wxfilename;
    }

    double auxf = stats.GetAuxfValue(extractor);
    KALDI_LOG << "Aux-function value after update is " << auxf;

    if (check_change == true) {
      KALDI_LOG << "Aux-function value improvement (after - before) is " << auxf - auxf_old;
    }

    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what() << '\n';
    return -1;
  }
}


