// ivectorbin/ivector-mean.cc

// Copyright 2013-2014  Daniel Povey

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

int main(int argc, char *argv[]) {
  using namespace kaldi;
  typedef kaldi::int32 int32;
  try {
    const char *usage =
        "Generate ivector pairs and group them as utterances.\n"
        "\n"
        "Usage: ivector-prep-pairs [options] <utt-pairs> <ivector-rspecifier> <feat-wspecifier> <ali-wspecifier>\n"
        " e.g.: ivector-prep-pairs data/utt-pairs scp:exp/ivectors.scp scp,ark:exp/ivector-pairs.scp,exp/ivector-pairs.ark scp,ark:exp/ivector-pairs-ali.scp,exp/ivector-pairs-ali.ark\n";
    
    ParseOptions po(usage);
    bool binary_write = false;
    po.Register("binary", &binary_write, "If true, write output in binary "
                "(only applicable when writing files, not archives/tables.");
    int32 frames_per_utt = 1000;
    po.Register("frames-per-utt", &frames_per_utt, "Number of pairs per utterance for nnet training (default is 1000)");
    std::string utt_prefix = "";
    po.Register("utt-prefix", &utt_prefix, "Prefix for utterance id (default is none)");
    
    po.Read(argc, argv);
    
    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string utt_pairs_file = po.GetArg(1),
          ivector_rspecifier = po.GetArg(2),
          feat_wspecifier = po.GetArg(3),
          alignment_wspecifier = po.GetArg(4);
   
    RandomAccessBaseFloatVectorReader ivector_reader(ivector_rspecifier);
    BaseFloatMatrixWriter kaldi_writer(feat_wspecifier);
    Int32VectorWriter alignment_writer(alignment_wspecifier);

    Input ki(utt_pairs_file);

    std::string line;
    Matrix<BaseFloat> features;
    std::vector<int32> alignments(frames_per_utt);

    int32 num_done = 0, num_frames = 0, num_utts = 0, num_err = 0;
    while (std::getline(ki.Stream(), line)) {
      std::vector<std::string> fields;
      SplitStringToVector(line, " \t\n\r", true, &fields);
      if (fields.size() != 3) {
        KALDI_ERR << "Bad line in input "
                  << "(expected three fields: key1 key2 alignment): " << line;
      }
      std::string key1 = fields[0], key2 = fields[1];
      int32 alignment = atoi(fields[2].c_str());

      if (!ivector_reader.HasKey(key1)) {
        KALDI_WARN << "Key " << key1 << " not present in 1st table of ivectors.";
        num_err++;
        continue;
      }
      if (!ivector_reader.HasKey(key2)) {
        KALDI_WARN << "Key " << key2 << " not present in 2nd table of ivectors.";
        num_err++;
        continue;
      }

      alignments[num_frames] = alignment;
 
      const Vector<BaseFloat> &ivector1 = ivector_reader.Value(key1);
      if (num_done == 0) {
        features.Resize(frames_per_utt, 2*ivector1.Dim());
      }
      SubVector<BaseFloat> ivec_line(features, num_frames);
      SubVector<BaseFloat> ivec1(ivec_line, 0, ivector1.Dim());
      ivec1.CopyFromVec(ivector1);
      const Vector<BaseFloat> &ivector2 = ivector_reader.Value(key2);
      SubVector<BaseFloat> ivec2(ivec_line, ivector1.Dim(), ivector2.Dim());
      ivec2.CopyFromVec(ivector2);

      num_frames++;
      num_done++;
      if (num_frames == frames_per_utt) {
        std::stringstream ss;  ss << num_utts;
        kaldi_writer.Write(utt_prefix + "utt_" + ss.str(), features);
        alignment_writer.Write(utt_prefix + "utt_" + ss.str(), alignments);
        num_frames = 0;
        num_utts++;
      }
    }
    
    if (num_utts != 0) {
      KALDI_LOG << num_utts << " fake sentences generated, "
                << num_err << " pairs not found in ivector scp";
    }
    return (num_utts != 0 ? 0 : 1);

  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
