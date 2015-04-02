// bin/matrix-sum-rows.cc

// Copyright 2012  Johns Hopkins University (author: Daniel Povey)

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

    const char *usage =
        "Divide the elements by the sum of each column\n"
        "table of vectors\n"
        "\n"
        "Usage: matrix-div-cols-sum [options] <matrix-rspecifier> <matrix-wspecifier>\n"
        "e.g.: matrix-div-cols-sum ark:- ark:- \n"
        "See also: matrix-sum, vector-sum\n";


    ParseOptions po(usage);

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }
    std::string rspecifier = po.GetArg(1);
    std::string wspecifier = po.GetArg(2);
    
    SequentialBaseFloatMatrixReader mat_reader(rspecifier);
    BaseFloatMatrixWriter mat_writer(wspecifier);
    
    int32 num_done = 0;
    int64 num_rows_done = 0;
    
    for (; !mat_reader.Done(); mat_reader.Next()) {
      std::string key = mat_reader.Key();
      Matrix<double> mat(mat_reader.Value());
      mat.DivColSum();
      // Do the summation in double, to minimize roundoff.
      Matrix<BaseFloat> result_mat(mat);
      mat_writer.Write(key, result_mat);
      num_done++;
      num_rows_done += mat.NumRows();
    }
    
    KALDI_LOG << "Summed rows " << num_done << " matrices, "
              << num_rows_done << " rows in total.";
    
    return (num_done != 0 ? 0 : 1);
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}


