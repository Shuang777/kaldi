// ivectorbin/compute-vad.cc

// Copyright  2015  Hang Su

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
#include "matrix/kaldi-matrix.h"


int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using kaldi::int32;

    const char *usage =
        "This program reads two input vad file and output their overlap stats.\n"
        "\n"
        "Usage: compare-vad [options] <vad-rspecifier1> <vad-rspecifier2> <vad-wspecifier>\n"
        "e.g.: compare-vad scp:vad1.scp scp:vad2.scp scp:vad_merge.scp\n";
    
    ParseOptions po(usage);
    po.Read(argc, argv);

    if (po.NumArgs() != 3) {
      po.PrintUsage();
      exit(1);
    }

    std::string vad_rspecifier1 = po.GetArg(1),
                vad_rspecifier2 = po.GetArg(2),
                vad_wspecifier = po.GetArg(3);

    SequentialBaseFloatVectorReader vad_reader1(vad_rspecifier1);
    RandomAccessBaseFloatVectorReader vad_reader2(vad_rspecifier2);
    BaseFloatVectorWriter vad_writer(vad_wspecifier);

    int32 num_done = 0, tot_len = 0, num_err = 0;
    int32 both_nonvoice = 0, both_voice = 0, only1_voice = 0, only2_voice = 0;
    
    for (;!vad_reader1.Done(); vad_reader1.Next()) {
      std::string utt = vad_reader1.Key();
      const Vector<BaseFloat> &voiced1 = vad_reader1.Value();

      if (!vad_reader2.HasKey(utt)) {
        KALDI_WARN << "No VAD input found in second vad file for utterance " << utt;
        num_err++;
        continue;
      }

      const Vector<BaseFloat> &voiced2 = vad_reader2.Value(utt);
      KALDI_ASSERT(voiced1.Dim() == voiced2.Dim());

      Vector<BaseFloat> vad_result(voiced1.Dim(), kSetZero);
      for (int32 i=0; i<voiced1.Dim(); i++){
        if (voiced1(i) == 0) {
          if (voiced2(i) == 0) {
            both_nonvoice++;
          } else {
            only2_voice++;
          }
        } else {
          if (voiced2(i) == 0) {
            only1_voice++;
          } else {
            both_voice++;
            vad_result(i) = 1;
          }
        }
      }
      vad_writer.Write(utt, vad_result);
      tot_len += voiced1.Dim();
      num_done++;
    }

    KALDI_LOG << "Counts:\nvad1\\vad2\t0\t1\n"
              << "0\t\t" << both_nonvoice << "\t" << only2_voice << "\n"
              << "1\t\t" << only1_voice << "\t" << both_voice;
    
    KALDI_LOG << "Portion:\nvad1\\vad2\t0\t1\n"
              << "0\t\t" << (both_nonvoice * 100.0) / tot_len << "\t" << (only2_voice * 100.0) / tot_len << "\n"
              << "1\t\t" << (only1_voice * 100.0) / tot_len << "\t" << (both_voice * 100.0) / tot_len;
    KALDI_LOG << "Done " << num_done << " utterances, " << num_err << " have error";
    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
