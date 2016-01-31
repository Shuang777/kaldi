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
#include "nnet/nnet-various.h"

namespace kaldi {

namespace ivector2{

using namespace kaldi::nnet1;

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

void IvectorExtractorUtteranceStats::GetSupervector(Vector<double> & supervector){
  int32 num_gauss = X_.NumRows(),
        feat_dim = X_.NumCols();
  supervector.Resize(num_gauss * feat_dim);
  for (int32 i = 0; i < num_gauss; i++) {
    SubVector<double> subSupervector(supervector, i*feat_dim, feat_dim);
    SubVector<double> subSuperMatrix(X_, i);
    if (gamma_(i) != 0)
      subSupervector.AddVec(1 / gamma_(i), subSuperMatrix);
  }
}

void IvectorExtractorInitStats::AccStats(const VectorBase<double> &supervector) {
  sum_acc.AddVec(1.0, supervector);
  int32 num_gauss = scatter.size();
  int32 feat_dim = scatter.front().NumRows();
  for (int32 i = 0; i < num_gauss; i++) {
    SubVector<double> gaussVec(supervector, i*feat_dim, feat_dim);
    scatter[i].AddVec2 (1.0, gaussVec);
  }
  num_samples++;
}

IvectorExtractorStats::IvectorExtractorStats(const IvectorExtractor& extractor,
                                             const IvectorExtractorStatsOptions& stats_opts):
                                             config_(stats_opts) {
  supV_iV_.resize(extractor.NumGauss());
  supV_supV_.resize(extractor.NumGauss());
  iV_iV_.Resize(extractor.IvectorDim());
  for (int32 i = 0; i < extractor.NumGauss(); i++) {
    supV_iV_[i].Resize(extractor.FeatDim(), extractor.IvectorDim());
    supV_supV_[i].Resize(extractor.FeatDim());
  }
}


void IvectorExtractorStats::AccStatsForUtterance(const IvectorExtractor &extractor, 
                                                 const VectorBase<double> &supervector) {
  Vector<double> ivector(extractor.IvectorDim());
  Vector<double> normalized_supervector(supervector.Dim());
  if (!config_.random_ivector)
    extractor.GetIvectorDistribution(supervector, &ivector, &normalized_supervector);
  else
    ivector.SetRandn();
  iV_iV_.AddVec2(1.0, ivector);
  for (int32 i = 0; i < extractor.NumGauss(); i++) {
    SubVector<double> gaussvector(normalized_supervector, i*extractor.FeatDim(), extractor.FeatDim());
    supV_iV_[i].AddVecVec(1.0, gaussvector, ivector);
    supV_supV_[i].AddVec2(1.0, gaussvector);
  }
  num_ivectors_++;
}

void IvectorExtractorStats::Write(std::ostream &os, bool binary) const {
  WriteToken(os, binary, "<IvectorExtractorStats2>");
  WriteToken(os, binary, "<supViV>");
  int32 size = supV_iV_.size();
  WriteBasicType(os, binary, size);
  for (int32 i = 0; i < size; i++)
    supV_iV_[i].Write(os, binary);
  WriteToken(os, binary, "<iViV>");
  iV_iV_.Write(os, binary);
  WriteToken(os, binary, "<supVsupV>");
  size = supV_supV_.size();
  WriteBasicType(os, binary, size);
  for (int32 i = 0; i < size; i++)
    supV_supV_[i].Write(os, binary);
  WriteToken(os, binary, "<NumIvectors>");
  WriteBasicType(os, binary, num_ivectors_);
  WriteToken(os, binary, "</IvectorExtractorStats2>");
}

void IvectorExtractorStats::Read(std::istream &is, bool binary, bool add) {
  ExpectToken(is, binary, "<IvectorExtractorStats2>");
  ExpectToken(is, binary, "<supViV>");
  int32 size;
  ReadBasicType(is, binary, &size);
  supV_iV_.resize(size);
  for (int32 i = 0; i < size; i++)
    supV_iV_[i].Read(is, binary, add);
  ExpectToken(is, binary, "<iViV>");
  iV_iV_.Read(is, binary, add);
  ExpectToken(is, binary, "<supVsupV>");
  ReadBasicType(is, binary, &size);
  supV_supV_.resize(size);
  for (int32 i = 0; i < size; i++)
    supV_supV_[i].Read(is, binary, add);
  ExpectToken(is, binary, "<NumIvectors>");
  ReadBasicType(is, binary, &num_ivectors_, add);
  ExpectToken(is, binary, "</IvectorExtractorStats2>");

}

void IvectorExtractorStats::Update(IvectorExtractor &extractor, const IvectorExtractorEstimationOptions &update_opts) {
  SpMatrix<double> iV2;
  iV2.Resize(extractor.IvectorDim());
  iV2.AddSp(num_ivectors_, extractor.Var_);
  iV2.AddSp(1.0, iV_iV_);

  if (!update_opts.floor_iv2) {
    // straight forward way of solving for A
    SpMatrix<double> iV2_inv(iV2);
    iV2_inv.Invert();
    // Update transform matrix
    for (int32 i = 0; i < extractor.NumGauss(); i++) {
      extractor.A_[i].AddMatSp(1.0, supV_iV_[i], kNoTrans, iV2_inv, 0.0);
    }
  } else {
    SolverOptions solver_opts;
    solver_opts.name = "M";
    solver_opts.diagonal_precondition = true;
    for (int32 i = 0; i < extractor.NumGauss(); i++) {
      SolveQuadraticMatrixProblem(iV2, supV_iV_[i], extractor.Psi_inv_[i], solver_opts, &extractor.A_[i]);
    }
  }

  // Update variance
  if (update_opts.update_variance) {
    Matrix<double> tmp_Psi(extractor.FeatDim(), extractor.FeatDim());

    SpMatrix<double> tot_Psi(extractor.FeatDim());

    bool floor_psi = (update_opts.variance_floor_factor != 0) ;

    for (int32 i = 0; i < extractor.NumGauss(); i++) {
      tmp_Psi.AddMatMat(-1.0, extractor.A_[i], kNoTrans, supV_iV_[i], kTrans, 0.0);
      extractor.Psi_inv_[i].CopyFromMat(tmp_Psi);
      extractor.Psi_inv_[i].AddSp(1.0, supV_supV_[i]);
      extractor.Psi_inv_[i].Scale(1.0 / num_ivectors_);
      if (floor_psi) {
        tot_Psi.AddSp(1.0, extractor.Psi_inv_[i]);
      }
    }
    tot_Psi.Scale(update_opts.variance_floor_factor / extractor.NumGauss());
    int32 tot_num_floored = 0;
    for (int32 i = 0; i < extractor.NumGauss(); i++) {
      if (floor_psi) {
        int32 num_floored = extractor.Psi_inv_[i].ApplyFloor(tot_Psi);
        tot_num_floored += num_floored;
        if (num_floored > 0)
          KALDI_LOG << "For Gaussian index " << i << ", floored "
                    << num_floored << " eigenvalues of variance.";
      }
      if (extractor.opts_.diagonal_variance) {
        extractor.Psi_inv_[i].SetDiag();
      }
      extractor.Psi_inv_[i].Invert();
    }
    double floored_percent = tot_num_floored * 100.0 / (extractor.NumGauss() * extractor.FeatDim());
    KALDI_LOG << "Floored " << floored_percent << "% of all Gaussian eigenvalues";
  }

  extractor.ComputeDerivedValues();
}

double IvectorExtractorStats::GetAuxfValue(const IvectorExtractor &extractor) const {
  double logDetPsi = 0;
  double trace2nd = 0;
  Matrix<double> tmp_mat;
  tmp_mat.Resize(extractor.FeatDim(), extractor.FeatDim());
  Matrix<double> tmp_mat_Psi_inv(tmp_mat);
  for (int32 i = 0; i < extractor.NumGauss(); i++) {
    logDetPsi -= extractor.Psi_inv_[i].LogDet();
    tmp_mat.CopyFromSp(supV_supV_[i]);
    tmp_mat.AddMatMat(-1.0, supV_iV_[i], kNoTrans, extractor.A_[i], kTrans, 1.0);
    tmp_mat_Psi_inv.AddMatSp(1.0, tmp_mat, kNoTrans, extractor.Psi_inv_[i], 0.0);
    trace2nd += tmp_mat_Psi_inv.Trace();
  }
  double auxf = - num_ivectors_ / 2 * logDetPsi - trace2nd / 2;
  return auxf;
}

IvectorExtractor::IvectorExtractor(const IvectorExtractorOptions &opts, int32 feat_dim, int32 num_gauss):
                                   opts_(opts) {
  mu_.Resize(num_gauss * feat_dim);
  A_.resize(num_gauss);
  Psi_inv_.resize(num_gauss);
  for (int32 i = 0; i < num_gauss; i++) {
    A_[i].Resize(feat_dim, opts.ivector_dim);
    Psi_inv_[i].Resize(feat_dim);
  }
}

IvectorExtractor::IvectorExtractor(const IvectorExtractorOptions &opts, const IvectorExtractorInitStats &stats):
                                   opts_(opts) {
  int32 num_gauss = stats.scatter.size();
  int32 feat_dim = stats.sum_acc.Dim() / num_gauss;

  mu_.Resize(num_gauss * feat_dim);
  mu_.AddVec(1.0 / stats.num_samples, stats.sum_acc);

  A_.resize(num_gauss);
  Psi_inv_.resize(num_gauss);
  for (int32 i = 0; i < num_gauss; i++) {
    A_[i].Resize(feat_dim, opts.ivector_dim);
    A_[i].SetRandn();
    Psi_inv_[i].Resize(feat_dim);
    Psi_inv_[i].AddSp(1.0 / stats.num_samples, stats.scatter[i]);
    SubVector<double> gaussVec(mu_, i * feat_dim, feat_dim);
    Psi_inv_[i].AddVec2(-1.0, gaussVec);
    if (opts_.diagonal_variance == true) {
      Psi_inv_[i].SetDiag();
    }
    Psi_inv_[i].Invert();
  }
}

void IvectorExtractor::GetIvectorDistribution(const VectorBase<double> &supervector, VectorBase<double> *mean,
                                              VectorBase<double> *normalized_supvervector, double *auxf) const {
  if (normalized_supvervector == NULL)
    normalized_supvervector = new Vector<double> (supervector);
  else
    normalized_supvervector->CopyFromVec(supervector);
  normalized_supvervector->AddVec(-1.0, mu_);
  Vector<double> linear(IvectorDim());
  int32 feat_dim = FeatDim();
  for (int32 i = 0; i < NumGauss(); i++) {
    SubVector<double> x(*normalized_supvervector, i*feat_dim, feat_dim);
    linear.AddMatVec(1.0, Psi_inv_A_[i], kTrans, x, 1.0);
  }
  mean->AddSpVec(1.0, Var_, linear, 0.0);
}
  
void IvectorExtractor::ComputeDerivedValues() {
  Var_.Resize(IvectorDim());
  Psi_inv_A_.resize(NumGauss());
  for (int32 i = 0; i < NumGauss(); i++) {
    Psi_inv_A_[i].Resize(FeatDim(), IvectorDim());
    Psi_inv_A_[i].AddSpMat(1.0, Psi_inv_[i], A_[i], kNoTrans, 1.0);
    Var_.AddMat2Sp(1.0, A_[i], kTrans, Psi_inv_[i], 1.0);
  }
  Var_.AddToDiag(1.0);
  Var_.Invert();
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
  WriteToken(os, binary, "</IvectorExtractor2>");
}

void IvectorExtractor::Read(std::istream &is, bool binary, const bool read_derived /* = false */) {
  ExpectToken(is, binary, "<IvectorExtractor2>");
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
  ExpectToken(is, binary, "</IvectorExtractor2>");

  ComputeDerivedValues();
}

int32 IvectorExtractor::NumParams() {
  int32 num_params = SupervectorDim() + NumGauss() * FeatDim() * IvectorDim();
  if (opts_.diagonal_variance) {
    num_params += SupervectorDim();
  } else {    // block diagonal
    num_params += NumGauss() * FeatDim() * FeatDim();
  }
  return num_params;
}

std::string IvectorExtractor::Info() {
  std::ostringstream ostr;
  ostr << "num-gauss " << NumGauss() << std::endl;
  ostr << "feat-dim " << FeatDim() << std::endl;
  ostr << "supervec-dim " << SupervectorDim() << std::endl;
  ostr << "ivector-dim " << IvectorDim() << std::endl;
  ostr << "number-of-parameters " << static_cast<float>(NumParams())/1e6
       << " millions" << std::endl;
  // topology & weight stats
  Matrix<double> A_mat(SupervectorDim(), IvectorDim());
  Vector<double> Psi_vec(SupervectorDim());
  for (int32 i = 0; i < NumGauss(); i++) {
    SubMatrix<double> A_mat_sub(A_mat, i * FeatDim(), FeatDim(), 0, IvectorDim());
    A_mat_sub.CopyFromMat(A_[i]);
    SubVector<double> Psi_vec_sub(Psi_vec, i * FeatDim(), FeatDim());
    Psi_vec_sub.CopyDiagFromSp(Psi_inv_[i]);
  }
  ostr << "Ivector Loading Matrix \n  " << MomentStatistics(A_mat) << std::endl;
  Psi_vec.InvertElements();
  ostr << "Diagonal of Psi \n  " << MomentStatistics(Psi_vec) << std::endl;

  return ostr.str();
}

} // namespace ivector2

} // namespace kaldi
