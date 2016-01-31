// bin/select-posts.cc

// Copyright   2016   Hang Su

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
    using kaldi::int32;

    const char *usage =
        "Select a subset of posts of the input files, based on the output of\n"
        "compute-vad or a similar program (a vector of length num-frames,\n"
        "containing 1.0 for voiced, 0.0 for unvoiced).\n"
        "Usage: select-posts [options] <post-rspecifier> "
        " <vad-rspecifier> <post-wspecifier>\n"
        "E.g.: select-posts [options] scp:post.1.scp scp:vad.scp ark:-\n";
    
    ParseOptions po(usage);
    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }
    
    std::string post_rspecifier = po.GetArg(1),
        vad_rspecifier = po.GetArg(2),
        post_wspecifier = po.GetArg(3);
    
    SequentialPosteriorReader post_reader(post_rspecifier);
    RandomAccessBaseFloatVectorReader vad_reader(vad_rspecifier);
    PosteriorWriter post_writer(post_wspecifier);

    int32 num_done = 0, num_err = 0;
    
    for (;!post_reader.Done(); post_reader.Next()) {
      std::string utt = post_reader.Key();
      const Posterior &post = post_reader.Value();
      if (post.size() == 0) {
        KALDI_WARN << "Empty post for utterance " << utt;
        num_err++;
        continue;
      }
      if (!vad_reader.HasKey(utt)) {
        KALDI_WARN << "No VAD input found for utterance " << utt;
        num_err++;
        continue;
      }
      const Vector<BaseFloat> &voiced = vad_reader.Value(utt);

      if (post.size() != voiced.Dim()) {
        KALDI_WARN << "Mismatch in number for frames " << post.size() 
                   << " for post and VAD " << voiced.Dim() 
                   << ", for utterance " << utt;
        num_err++;
        continue;
      }
      if (voiced.Sum() == 0.0) {
        KALDI_WARN << "No posteriors were judged as voiced for utterance "
                   << utt;
        num_err++;
        continue;
      }
      int32 dim = 0;
      for (int32 i = 0; i < voiced.Dim(); i++)
        if (voiced(i) != 0.0)
          dim++;
      Posterior voiced_post;
      int32 index = 0;
      for (int32 i = 0; i < post.size(); i++) {
        if (voiced(i) != 0.0) {
          KALDI_ASSERT(voiced(i) == 1.0); // should be zero or one.
          voiced_post.push_back(post[i]);
          index++;
        }
      }
      KALDI_ASSERT(index == dim);
      post_writer.Write(utt, voiced_post);
      num_done++;
    }

    KALDI_LOG << "Done selecting voiced frames; processed "
              << num_done << " utterances, "
              << num_err << " had errors.";
    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


