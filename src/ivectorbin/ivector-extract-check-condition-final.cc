// ivectorbin/ivector-extract.cc

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
#include "ivector/ivector-extractor.h"
#include "thread/kaldi-task-sequence.h"

#include <utility>
#include <vector>
#include "gmm/model-common.h"
#include "matrix/matrix-lib.h"
#include "util/common-utils.h"
#include "gmm/full-gmm.h"

#include "gmm/am-diag-gmm.h"

namespace kaldi {
class TestClass:public IvectorExtractor {
public:
  TestClass(string name) {
    name_ = name;
  }
  Matrix<double> getMInfor() {
    Matrix<double> T(NumGauss() * FeatDim(), IvectorDim());
    int index = 0;
    for(int i = 0; i < M_.size();i++)
    {
      //Matrix<double> mi = M_[i];
      for(int j = 0; j < M_[i].NumRows(); j++)
      {
        T.Row(index).CopyFromVec(M_[i].Row(j));
        index++;
      }
    }
    cout << "Finish extracting T matrix " << endl;
    return T;        
  }
private:
  string name_;
};



Vector<double> getStats(const MatrixBase<kaldi::BaseFloat> &feats, const Posterior &post) 
{
  typedef std::vector<std::pair<int32, BaseFloat> > VecType;  
  int32 num_frames = feats.NumRows(),
        num_gauss = 2048;
      //feat_dim = feats.NumCols();
  cout << "Num-of-frame = " << num_frames << endl;
  Vector<double> gamma_(num_gauss);
  //KALDI_ASSERT(X_.NumCols() == feat_dim);
  KALDI_ASSERT(feats.NumRows() == static_cast<int32>(post.size()));
  for (int32 t = 0; t < num_frames; t++) {
    SubVector<BaseFloat> frame(feats, t);
    const VecType &this_post(post[t]);
    for (VecType::const_iterator iter = this_post.begin();
         iter != this_post.end(); ++iter) {
      int32 i = iter->first; // Gaussian index.
      KALDI_ASSERT(i >= 0 && i < num_gauss &&
                   "Out-of-range Gaussian (mismatched posteriors?)");
      double weight = iter->second;
      gamma_(i) += weight;
    }
  }
    return gamma_;
}


void getW(Matrix<double> &T, Vector<double> &zero_order, std::vector<SpMatrix<BaseFloat> > &inver_cova, kaldi::int32 numGauss, kaldi::int32 featSize) 
{
  KALDI_ASSERT(numGauss == static_cast<int32>(inver_cova.size()));
  KALDI_ASSERT(numGauss == static_cast<int32>(zero_order.Dim()));
  cout << "Pass condition here " << endl;
  kaldi::int32 cf = featSize * numGauss;
  
  T.Transpose();
  kaldi::int32 r = T.NumRows();
  cout << "Transpose T, number of rows = " << T.NumRows() << ", num of column = " << T.NumCols() << endl;
  Matrix<double> TW(r, cf, kaldi::kSetZero);
  cout << "Initialization finished. " << endl;
  for(int i = 0; i < r; i++)
  {
      SubVector<double> rowI = T.Row(i);
      for(int j = 0; j < cf ;j++)
      {
          int indexGauss = j/featSize;
          int residual = j % featSize;
          int startConsider = indexGauss * featSize;
          int endConsider = startConsider + featSize - 1;
          SpMatrix<BaseFloat> &inv_sigmaC = inver_cova[indexGauss];
          double weightC = zero_order(indexGauss);
          for(int k = startConsider ; k <= endConsider;k++) 
          {
              TW(i,j) += rowI(k) * weightC * inv_sigmaC(k- startConsider, residual);
          }
      }
  }
  //cout << "Finish V^T * W" << endl;
  T.Transpose();
  Matrix<double> TWT(r, r, kaldi::kSetZero);
  TWT.AddMatMat(1.0, TW, kaldi::kNoTrans, T, kaldi::kNoTrans, 1.0);
  SpMatrix<double> temp(TWT.NumRows(), kaldi::kSetZero);
  for(int i = 0; i < TWT.NumRows();i++)
    for(int j = 0; j < TWT.NumRows();j++)
      temp(i,j) = TWT(i,j);
  //cout << "Finish V^T * W * V, now estimating condition number " << endl;
  Vector<double> s(temp.NumRows());
  Matrix<double> p(temp.NumRows(), temp.NumRows());
  temp.Eig(&s, &p);
  double min_abs = std::abs(s(0)), max_abs = std::abs(s(0)), min = s(0);  // both absolute values...
  for (MatrixIndexT i = 1;i < s.Dim();i++) {
    min_abs = std::min((double)std::abs(s(i)), min_abs); 
    max_abs = std::max((double)std::abs(s(i)), max_abs);
    min = std::min(s(i), min); 
  }
  if (min_abs > 0) 
    cout << "Max_abs = " << max_abs << " Min_abs = " << min_abs << ", cond num = " << max_abs/min_abs << endl;
  else 
    cout << "Max_abs = " << max_abs << " Min_abs = " << min_abs << ", bad condition number = 1.0e+100 " << endl;
}



}
int main(int argc, char *argv[]) {
  using namespace kaldi;
  typedef kaldi::int32 int32;
  typedef kaldi::int64 int64;
  try {
    const char *usage =
        "Extract iVectors for utterances, using a trained iVector extractor,\n"
        "and features and Gaussian-level posteriors\n"
        "Usage:  ivector-extract [options] <model-in> <feature-rspecifier>"
        "<posteriors-rspecifier> <ivector-wspecifier>\n"
        "e.g.: \n"
        " fgmm-global-gselect-to-post 1.fgmm '$feats' 'ark:gunzip -c gselect.1.gz|' ark:- | \\\n"
        "  ivector-extract final.ie '$feats' ark,s,cs:- ark,t:ivectors.1.ark\n";

    ParseOptions po(usage);
    IvectorExtractorStatsOptions stats_opts;
    
    stats_opts.Register(&po);
    
    po.Read(argc, argv);
    
    if (po.NumArgs() != 4) {
      po.PrintUsage();
      exit(1);
    }

    std::string ivector_extractor_rxfilename = po.GetArg(1),
        fgmm_rxfilename = po.GetArg(2),
        feature_rspecifier = po.GetArg(3),
        posteriors_rspecifier = po.GetArg(4);


    IvectorExtractor extractor;
    TestClass test(ivector_extractor_rxfilename);
    //ReadKaldiObject(ivector_extractor_rxfilename, &extractor);
    ReadKaldiObject(ivector_extractor_rxfilename, &test);
    Matrix<double> T = test.getMInfor();
    

    FullGmm fgmm;
    ReadKaldiObject(fgmm_rxfilename, &fgmm);

    // Initialize these Reader objects before reading the IvectorExtractor,
    // because it uses up a lot of memory and any fork() after that will
    // be in danger of causing an allocation failure.

    SequentialBaseFloatMatrixReader feature_reader(feature_rspecifier);
    RandomAccessPosteriorReader posteriors_reader(posteriors_rspecifier);
    std::vector<SpMatrix<BaseFloat> > inver_cova = fgmm.inv_covars();
    //KALDI_LOG << "The SI model:"
    //          << "Number of Gaussian = " << fgmm.NumGauss() << endl;
    //KALDI_LOG << "Size of the vector inver_covariance = " << inver_cova.size() << endl;
    int dim_size = 0;
    for(int i = 0; i < inver_cova.size();i++)
    {
        SpMatrix<BaseFloat> &aComponent = inver_cova[i];
        dim_size = aComponent.NumRows();
    }
    //KALDI_LOG << "Feat size= " << dim_size << endl;


    kaldi::int32 num_done = 0, num_err = 0;
    
    {
      
      for (; !feature_reader.Done(); feature_reader.Next()) {
        std::string key = feature_reader.Key();
        if (!posteriors_reader.HasKey(key)) {
          KALDI_WARN << "No posteriors for utterance " << key;
          num_err++;
          continue;
        }
        const Matrix<BaseFloat> &mat = feature_reader.Value();
        const Posterior &posterior = posteriors_reader.Value(key);
        Vector<double> zero_order = getStats(mat, posterior) ;
        //KALDI_LOG << "Size of zero-order = " << zero_order.Dim() << endl;
        //for(int i = 0; i < 10;i++)
        //    cout << zero_order(i) << "  ";
        cout << endl;
        getW(T, zero_order, inver_cova, fgmm.NumGauss(), dim_size);
        if (static_cast<int32>(posterior.size()) != mat.NumRows()) {
          KALDI_WARN << "Size mismatch between posterior " << (posterior.size())
                     << " and features " << (mat.NumRows()) << " for utterance "
                     << key;
          num_err++;
          continue;
        }

        num_done++;
      }
      // destructor of "sequencer" will wait for any remaining tasks that
      // have not yet completed.
    }
    return 0;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
