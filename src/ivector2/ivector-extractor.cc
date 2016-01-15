// ivector2/ivector-extractor.cc

// Copyright 2013     Daniel Povey

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

#include "ivector2/ivector-extractor.h"

namespace kaldi {

namespace ivector2{

void IvectorExtractorUtteranceStats::Reset(int32 num_gauss, int32 feat_dim) {
  gamma_.Resize(num_gauss, kSetZero);
  X_.Resize(num_gauss, feat_dim, kSetZero);
}

void IvectorExtractorUtteranceStats::AccStats(
    const MatrixBase<BaseFloat> &feats, 
    const Posterior &post, 
    const std::vector<bool> selected_parts) {
  typedef std::vector<std::pair<int32, BaseFloat> > VecType;
  int32 num_frames = feats.NumRows(),
        num_gauss = X_.NumRows(),
        feat_dim = feats.NumCols();
  KALDI_ASSERT(X_.NumCols() == feat_dim);
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
      X_.Row(i).AddVec(weight, frame);
    }
  } 
}

void IvectorExtractorUtteranceStats::GetSupervector(Vector<BaseFloat> & supervector){
  int32 num_gauss = X_.NumRows(),
        feat_dim = X_.NumCols();
  supervector.Resize(num_gauss * feat_dim);
  for (int32 i = 0; i < num_gauss; i++) {
    SubVector<BaseFloat> subSupervector(supervector, i*feat_dim, feat_dim);
    SubVector<double> subSuperMatrix(X_, i);
    if (gamma_(i) != 0)
      subSupervector.AddVec(1 / gamma_(i), subSuperMatrix);
  }
}

void IvectorExtractorInitStats::AccStats(const MatrixBase<BaseFloat> &feats) {
  KALDI_ASSERT(feats.NumRows() == 1);
  SubVector<BaseFloat> superVec(feats, 0);
  sum_acc.AddVec(1.0, superVec);
  int32 num_gauss = scatter.size();
  int32 feat_dim = scatter.front().NumRows();
  for (int32 i = 0; i < num_gauss; i++) {
    SubVector<BaseFloat> gaussVec(superVec, i*feat_dim, feat_dim);
    scatter[i].AddVec2 (1.0, gaussVec);
  }
  num_samples++;
}

void IvectorExtractor::Write(std::ostream &os, bool binary, const bool write_derived /* = false */) const {
  WriteToken(os, binary, "<IvectorExtractor2>");
  WriteToken(os, binary, "<mu>");
  mu_.Write(os, binary);
  WriteToken(os, binary, "<A>");  
  int32 size = A_.size();
  WriteBasicType(os, binary, size);
  for (int32 i = 0; i < size; i++)
    A_[i].Write(os, binary);
  WriteToken(os, binary, "<PsiInv>");  
  KALDI_ASSERT(size == static_cast<int32>(Psi_inv_.size()));
  for (int32 i = 0; i < size; i++)
    Psi_inv_[i].Write(os, binary);
  WriteToken(os, binary, "</IvectorExtractor>");
}

void IvectorExtractor::Read(std::istream &is, bool binary, const bool read_derived /* = false */) {
  ExpectToken(is, binary, "<IvectorExtractor>");
  ExpectToken(is, binary, "<mu>");
  mu_.Read(is, binary);
  ExpectToken(is, binary, "<A>");  
  int32 size;
  ReadBasicType(is, binary, &size);
  KALDI_ASSERT(size > 0);
  A_.resize(size);
  for (int32 i = 0; i < size; i++)
    A_[i].Read(is, binary);
  ExpectToken(is, binary, "<PsiInv>");
  Psi_inv_.resize(size);
  for (int32 i = 0; i < size; i++)
    Psi_inv_[i].Read(is, binary);
  ExpectToken(is, binary, "</IvectorExtractor>");
}



} // namespace ivector2

} // namespace kaldi
