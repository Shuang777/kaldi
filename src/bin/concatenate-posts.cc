// bin/concatenate-posts.cc

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
#include "hmm/posterior.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    typedef kaldi::int32 int32;  

    const char *usage =
        "Concatenate utterance posts into channel posts\n"
        "\n"
        "Usage: concatenate-posts <post-rspecifier> <vad-rspecifier> <post-wspecifier>\n";

    ParseOptions po(usage);
    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }
      
    std::string post_rspecifier = po.GetArg(1),
        vad_rspecifier = po.GetArg(2),
        post_wspecifier = po.GetArg(3);

    kaldi::SequentialPosteriorReader posterior_reader(post_rspecifier);
    kaldi::RandomAccessBaseFloatVectorReader vad_reader(vad_rspecifier);
    kaldi::PosteriorWriter posterior_writer(post_wspecifier);
    
    int32 num_done = 0, num_err = 0;

    std::string last_recording = "";
    kaldi::Posterior post_recording;
    
    std::pair<int32, BaseFloat> empty_pair (1, 0);
    std::vector<std::pair<int32, BaseFloat> > empty_post;
    empty_post.push_back(empty_pair);
    Vector<BaseFloat> vad_recording;

    for (; !posterior_reader.Done(); posterior_reader.Next()) {
      std::string key = posterior_reader.Key();
      std::vector<std::string> split_line;
      SplitStringToVector(key, "_", false, &split_line);


      if (split_line.size() < 3) {
        KALDI_WARN << "Invalid key in post file: " << key;
        continue;
      }

      std::string end_str = split_line.back();  split_line.pop_back();
      std::string start_str = split_line.back(); split_line.pop_back();

      string recording;
      JoinVectorToString(split_line, "_", false, &recording);

      if (recording != last_recording) {
        if (last_recording != "") {
          while (post_recording.size() < vad_recording.Dim()) {
            post_recording.push_back(empty_post);
          }
          posterior_writer.Write(last_recording, post_recording);
          post_recording.clear();
        }
        if (!vad_reader.HasKey(recording)) {
          KALDI_ERR << "Recording " << recording << " in post not found in vad.scp";
          continue;
        }
        vad_recording = vad_reader.Value(recording);
      }

      // Convert the start time and endtime to real from string. Segment is
      // ignored if start or end time cannot be converted to real.
      int32 start, end;
      if (!ConvertStringToInteger(start_str, &start)) {
        KALDI_WARN << "Invalid utt in post file: " << key;
        num_err++;
        continue;
      }
      if (!ConvertStringToInteger(end_str, &end)) {
        KALDI_WARN << "Invalid utt in post file: " << key;
        num_err++;
        continue;
      }
      // start time must not be negative; start time must not be greater than
      // end time, except if end time is -1
      if (start < 0 || (end != -1 && end <= 0) || ((start >= end) && (end > 0))) {
        KALDI_WARN << "Invalid utt in post file: " << key;
        num_err++;
        continue;
      }

      while(post_recording.size() <= start) {
        post_recording.push_back(empty_post);
      }
      
      kaldi::Posterior posterior = posterior_reader.Value();
      
      post_recording.insert(post_recording.end(), posterior.begin(), posterior.end());

      last_recording = recording;

      num_done++;
    }
    
    if (last_recording != "") {   // write last one
      while (post_recording.size() < vad_recording.Dim()) {
        post_recording.push_back(empty_post);
      }
      posterior_writer.Write(last_recording, post_recording);
      post_recording.clear();
    }

    KALDI_LOG << "Done concatenating " << num_done << " posteriors.";

    return (num_done != 0 ? 0 : 1);

  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}

