// ivector3bin/ivector3-model-post-to-post.cc

// Copyright   2013       Johns Hopkins University (author: Daniel Povey)

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
#include "ivector3/ivector-extractor.h"
#include "hmm/posterior.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::ivector3;
    typedef kaldi::int32 int32;
    typedef kaldi::int64 int64;

    const char *usage =
        "Given features and Posterior information for ivector model \n"
        "output per-frame posteriors for the selected indices\n"
        "See also: gmm-gselect, fgmm-gselect, gmm-global-get-post,\n"
        " gmm-global-gselect-to-post\n"
        "\n"
        "Usage:  ivector3-model-post-to-post [options] <model-in> <feature-rspecifier> "
        "<post-rspecifier> <post-wspecifier>\n"
        "e.g.: ivector3-model-post-to-post 1.ie ark:feats.ark ark:1.post ark:-\n";
        
    ParseOptions po(usage);

    po.Read(argc, argv);

    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_rxfilename = po.GetArg(1),
        feature_rspecifier = po.GetArg(2),
        post_rspecifier = po.GetArg(3),
        post_wspecifier = po.GetArg(4);
    
    IvectorExtractor ivector_extractor;
    ReadKaldiObject(model_rxfilename, &ivector_extractor);
    
    int64 tot_frames = 0;

    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader post_reader(post_rspecifier);
    PosteriorWriter post_writer(post_wspecifier);

    int32 num_done = 0, num_err = 0;

    for (; !feature_reader.Done(); feature_reader.Next()) {
      std::string utt = feature_reader.Key();
      const Matrix<BaseFloat> &mat = feature_reader.Value();

      int32 num_frames = mat.NumRows();
      // typedef std::vector<std::vector<std::pair<int32, BaseFloat> > > Posterior;
      Posterior new_post(num_frames);
      
      if (!post_reader.HasKey(utt)) {
        KALDI_WARN << "No gselect information for utterance " << utt;
        num_err++;
        continue;
      }
      const Posterior &post(post_reader.Value(utt));
      if (static_cast<int32>(post.size()) != num_frames) {
        KALDI_WARN << "posterior information for utterance " << utt
                   << " has wrong size " << post.size() << " vs. "
                   << num_frames;
        num_err++;
        continue;
      }

      ivector_extractor.PostPreselect(mat, post, new_post);

      post_writer.Write(utt, new_post);
      num_done++;
      tot_frames += num_frames;
    }

    KALDI_LOG << "Done " << num_done << " files; " << num_err << " had errors.";
    KALDI_LOG << "Overall " << tot_frames << " frames";
    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
