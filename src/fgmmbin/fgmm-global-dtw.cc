// ivectorbin/ivector-compute-distance.cc

// Copyright 2013  Daniel Povey

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
#include "gmm/am-diag-gmm.h"
#include "hmm/posterior.h"
#include "base/kaldi-math.h"

using std::pair;
using std::vector;
using namespace kaldi;

double post_distance(const vector<pair<int,float> > &post1, const vector<pair<int,float> > &post2) {
  double score = 0;
  for (int i = 0; i < post1.size(); i++) {
    for (int j = 0; j < post2.size(); j++) {
      if (post1[i].first == post2[j].first)
        score += post1[i].second * post2[j].second;
    }
  }
  if (score == 0)
    return kMinLogDiffDouble;
  else
    return std::log(score);
}


double posts_distance(const Posterior & post1, const Posterior & post2) {
  double mismatchPenalty = 0;
  int numFrames1 = post1.size();
  int numFrames2 = post2.size();
  Matrix<double> bestPath (numFrames1, numFrames2);
  bestPath(0,0) = post_distance(post1[0], post2[0]);
  for (int i = 1; i < numFrames1; i++) {
    bestPath(i,0) = post_distance(post1[i], post2[0]) + bestPath(i-1,0) + mismatchPenalty;
  }
  for (int j = 1; j < numFrames2; j++) {
    bestPath(0,j) = post_distance(post1[0], post2[j]) + bestPath(0, j-1) + mismatchPenalty;
  }
  for (int i = 1; i < numFrames1; i++) {
    for (int j = 1; j < numFrames2; j++) {
      double path1Score = bestPath(i,j-1) + mismatchPenalty; // horizontal path
      double path2Score = bestPath(i-1,j) + mismatchPenalty; // vertical path
      double path3Score = bestPath(i-1,j-1); // diagnoal path
      double bestScore = LogAdd(LogAdd(path1Score, path2Score), path3Score);
      bestPath(i,j) = bestScore + post_distance(post1[i],post2[j]);
    }
  }
  return bestPath(numFrames1-1, numFrames2-1);
}


int main(int argc, char *argv[]) {
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "Computes distance between two sentences; useful in application of an\n"
        "pass-phrase id system.  The 'trials-file' has lines of the form\n"
        "<key1> <key2>\n"
        "and the output will have the form\n"
        "<key1> <key2> [<distance>]\n"
        "(if either key could not be found, the distance field in the output\n"
        "will be absent, and this program will print a warning)\n"
        "\n"
        "Usage:  fgmm-global-dtw [options] <trials-in> "
        "<post-rspecifier> <post2-rspecifier> <scores-out>\n"
        "e.g.: \n"
        " fgmm-global-dtw trials ark:post.ark ark:post2.ark trials.scored\n";
    
    ParseOptions po(usage);
    
    po.Read(argc, argv);
    
    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string trials_rxfilename = po.GetArg(1),
        post1_rspecifier = po.GetArg(2),
        post2_rspecifier = po.GetArg(3),
        scores_wxfilename = po.GetArg(4);


    int64 num_done = 0, num_err = 0;
    
    RandomAccessPosteriorReader post1_reader(post1_rspecifier);
    RandomAccessPosteriorReader post2_reader(post2_rspecifier);
    
    Input ki(trials_rxfilename);

    bool binary = false;
    Output ko(scores_wxfilename, binary);
    double sum = 0.0;

    std::string line;
    while (std::getline(ki.Stream(), line)) {
      std::vector<std::string> fields;
      SplitStringToVector(line, " \t\n\r", true, &fields);
      if (fields.size() != 2) {
        KALDI_ERR << "Bad line " << (num_done + num_err) << " in input "
                  << "(expected two fields: key1 key2): " << line;
      }
      std::string key1 = fields[0], key2 = fields[1];
      if (!post1_reader.HasKey(key1)) {
        KALDI_WARN << "Key " << key1 << " not present in 1st table of posts.";
        num_err++;
        continue;
      }
      if (!post2_reader.HasKey(key2)) {
        KALDI_WARN << "Key " << key2 << " not present in 2nd table of posts.";
        num_err++;
        continue;
      }
      const Posterior &post1 = post1_reader.Value(key1),
          &post2 = post2_reader.Value(key2);
      // The following will crash if the dimensions differ, but
      // they would likely also differ for all the posts so it's probably
      // best to just crash.
      BaseFloat score = posts_distance(post1, post2);
      sum += score;
      num_done++;
      ko.Stream() << key1 << ' ' << key2 << ' ' << score << std::endl;
    }
    
    if (num_done != 0) {
      BaseFloat mean = sum / num_done;
      KALDI_LOG << "Mean distance was " << mean ;
    }
    KALDI_LOG << "Processed " << num_done << " trials " << num_err
              << " had errors.";
    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
