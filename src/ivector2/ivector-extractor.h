// ivector2/ivector-extractor.h

// Copyright 2013-2014    Daniel Povey


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

#ifndef KALDI_IVECTOR2_IVECTOR_EXTRACTOR_H_
#define KALDI_IVECTOR2_IVECTOR_EXTRACTOR_H_

#include "base/kaldi-common.h"
#include "matrix/matrix-lib.h"
#include "itf/options-itf.h"
#include "util/common-utils.h"
#include "hmm/posterior.h"

namespace kaldi {
namespace ivector2{

class IvectorExtractorUtteranceStats {
 public:
  IvectorExtractorUtteranceStats() {}

  void AccStats(const MatrixBase<BaseFloat> &feats,
                const Posterior &post, const std::vector<bool> selected_parts = std::vector<bool>());
  
  void Reset(int32 num_gauss, int32 feat_dim);

  void GetSupervector(Vector<BaseFloat> & supervector);

 protected:
  Vector<double> gamma_; // zeroth-order stats (summed posteriors), dimension [I]
  Matrix<double> X_; // first-order stats, dimension [I][D]
};

struct IvectorExtractorOptions {
  int ivector_dim;
  IvectorExtractorOptions(): ivector_dim(400) { }
  void Register(OptionsItf *po) {
    po->Register("ivector-dim", &ivector_dim, "Dimension of iVector");
  }
};

class IvectorExtractorInitStats {
 public:
  friend class IvectorExtractor;
  IvectorExtractorInitStats(int32 feat_dim, int32 num_gauss): sum_acc(feat_dim*num_gauss), scatter(num_gauss), 
                                                          num_samples(0) {
    for (int32 i = 0; i < num_gauss; i++) {
      scatter[i].Resize(feat_dim);
    }
  }
  
  void AccStats(const MatrixBase<BaseFloat> &feats);

private: 
  Vector<double> sum_acc;
  std::vector<SpMatrix<double> > scatter;
  int32 num_samples;
};

class IvectorExtractor {
 public:
  friend class IvectorExtractorInitStats;

  IvectorExtractor(const IvectorExtractorOptions &opts, int32 feat_dim, int32 num_gauss) {
    mu_.Resize(num_gauss * feat_dim);
    A_.resize(num_gauss);
    Psi_inv_.resize(num_gauss);
    for (int32 i = 0; i < num_gauss; i++) {
      A_[i].Resize(feat_dim, opts.ivector_dim);
      Psi_inv_[i].Resize(feat_dim);
    }
  }
  
  IvectorExtractor(const IvectorExtractorOptions &opts, const IvectorExtractorInitStats &stats) {
    int32 num_gauss = stats.scatter.size();
    int32 feat_dim = stats.sum_acc.Dim() / num_gauss;

    mu_.Resize(num_gauss * feat_dim);
    mu_.AddVec(1.0 / stats.num_samples, stats.sum_acc);

    A_.resize(num_gauss);
    Psi_inv_.resize(num_gauss);
    for (int32 i = 0; i < num_gauss; i++) {
      A_[i].Resize(feat_dim, opts.ivector_dim);
      Psi_inv_[i].Resize(feat_dim);
      Psi_inv_[i].AddSp(1.0 / stats.num_samples, stats.scatter[i]);
      SubVector<double> gaussVec(mu_, i * feat_dim, feat_dim);
      Psi_inv_[i].AddVec2(-1.0, gaussVec);
    }
  }

  int32 IvectorDim() {
    return A_.front().NumCols();
  }

  void Write(std::ostream &os, bool binary, const bool write_derived = false) const;
  void Read(std::istream &is, bool binary, const bool read_derived = false) ;

private:
  Vector<double> mu_;
  std::vector< Matrix< double > > A_;
  std::vector< SpMatrix< double > > Psi_inv_;

};

}  // namespace ivector2
}  // namespace kaldi

#endif
