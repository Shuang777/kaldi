// bin/filter-posts.cc

// Copyright 2009-2012  Microsoft Corporation
//                      Johns Hopkins University (author: Daniel Povey)

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
#include "hmm/posterior.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    typedef kaldi::int32 int32;

    const char *usage =
        "Filter posts for certain speakers and save the result\n"
        "Usage: filter-posts [options] <posts-rspecifier> <utt2spk-rspecifier> <posts-wspecifier>\n";
        
    ParseOptions po(usage);
    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string post_rspecifier = po.GetArg(1);
    std::string utt2spk_rspecifier = po.GetArg(2);
    std::string post_wspecifier = po.GetArg(3);

    RandomAccessPosteriorReader post_reader(post_rspecifier);
    PosteriorWriter post_writer(post_wspecifier);

    int32 num_done = 0, num_error = 0;
    
    SequentialTokenVectorReader utt2spk_reader(utt2spk_rspecifier);

    for (; !utt2spk_reader.Done(); utt2spk_reader.Next()) {
      std::string utt = utt2spk_reader.Key();

      if (!post_reader.HasKey(utt)) {
        KALDI_WARN << "No posterior available for utterance "
                   << utt << ", producing no output for this utterance";
        num_error++;
        continue;
      }
      const Posterior &post = post_reader.Value(utt);

      post_writer.Write(utt, post);

      num_done++;
    }
    KALDI_LOG << "Filtered posterior to " << num_done << " utterances; " << num_error
              << " had errors.";

    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
