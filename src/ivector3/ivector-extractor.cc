// ivector3/ivector-extractor.cc

// Copyright 2013     Daniel Povey
//           2016     Hang Su

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

#include "ivector3/ivector-extractor.h"
#include "nnet/nnet-various.h"

namespace kaldi {

namespace ivector3{

using namespace kaldi::nnet1;

IvectorExtractorUtteranceStats::IvectorExtractorUtteranceStats(int32 num_gauss, int32 feat_dim,
                                                               bool need_2nd_order_stats) {
  Reset(num_gauss, feat_dim, need_2nd_order_stats);
}

void IvectorExtractorUtteranceStats::Reset(int32 num_gauss, int32 feat_dim, bool need_2nd_order_stats) {
  gamma_.Resize(num_gauss, kSetZero);
  X_.Resize(num_gauss, feat_dim, kSetZero);
  if (need_2nd_order_stats) {
     S_.resize(num_gauss);
     for (int32 i = 0; i < num_gauss; i++)
       S_[i].Resize(feat_dim);
  }
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
  SpMatrix<double> outer_prod(feat_dim);

  for (int32 t = 0; t < num_frames; t++) {
    SubVector<BaseFloat> frame(feats, t);
    const VecType &this_post(post[t]);
    if (S_.size() != 0) {
      outer_prod.SetZero();
      outer_prod.AddVec2(1.0, frame);
    }
    for (VecType::const_iterator iter = this_post.begin();
        iter != this_post.end(); ++iter) {
      int32 i = iter->first; // Gaussian index.
      KALDI_ASSERT(i >= 0 && i < num_gauss &&
                   "Out-of-range Gaussian (mismatched posteriors?)");
      double weight = iter->second;
      gamma_(i) += weight;
      X_.Row(i).AddVec(weight, frame);
      if (S_.size() != 0) {
        S_[i].AddSp(weight, outer_prod);
      }
    }
  } 
}


IvectorExtractorStats::IvectorExtractorStats(const IvectorExtractor& extractor) {
  const int32 num_gauss = extractor.NumGauss();
  const int32 ivector_dim = extractor.IvectorDim();
  const int32 feat_dim = extractor.FeatDim();

  gamma_supV_iV_.resize(num_gauss);
  gamma_supV_supV_.resize(num_gauss);
  gamma_iV_iV_.Resize(num_gauss, ivector_dim * (ivector_dim + 1) / 2);
  for (int32 i = 0; i < num_gauss; i++) {
    gamma_supV_iV_[i].Resize(feat_dim, ivector_dim);
    gamma_supV_supV_[i].Resize(feat_dim);
  }
  sum_iV_.Resize(ivector_dim);
  iV_iV_.Resize(ivector_dim);
  gamma_.Resize(num_gauss);
  num_ivectors_ = 0.0;
}


void IvectorExtractorStats::AccStatsForUtterance(const IvectorExtractor &extractor,
                                                 const MatrixBase<BaseFloat> &feats,
                                                 const Posterior &post) {
  const bool need_2nd_order_stats = true;
  const int32 feat_dim = extractor.FeatDim();
  const int32 num_gauss = extractor.NumGauss();
  const int32 ivector_dim = extractor.IvectorDim();

  IvectorExtractorUtteranceStats utt_stats(num_gauss, feat_dim, need_2nd_order_stats);
  utt_stats.AccStats(feats, post);

  gamma_.AddVec(1.0, utt_stats.gamma_);

  Vector<double> ivector(ivector_dim);
  Matrix<double> normalized_gammasup(num_gauss, feat_dim);
  SpMatrix<double> ivector_var(ivector_dim);

  extractor.GetIvectorDistribution(utt_stats, &ivector, &ivector_var, &normalized_gammasup);
  
  SpMatrix<double> ivec_scatter(ivector_var);
  ivec_scatter.AddVec2(1.0, ivector);       // ivector^2 + ivec_var

  SubVector<double> ivec_scatter_vec(ivec_scatter.Data(),
                                     ivector_dim * (ivector_dim + 1) / 2);
  gamma_iV_iV_.AddVecVec(1.0, utt_stats.gamma_, ivec_scatter_vec);

  Matrix<double> XsupsupX (feat_dim, feat_dim);
  SpMatrix<double> XsupsupX_sp (feat_dim);
  for (int32 i = 0; i < extractor.NumGauss(); i++) {
    if (utt_stats.gamma_(i) == 0)
      continue;
    gamma_supV_iV_[i].AddVecVec(1.0, normalized_gammasup.Row(i), ivector);
    //gamma_supV_supV_[i].AddVec2(1.0 / utt_stats.gamma_(i), normalized_gammasup.Row(i));
    XsupsupX.SetZero();
    XsupsupX.AddVecVec(1.0, utt_stats.X_.Row(i), extractor.mu_.Row(i));
    XsupsupX.AddVecVec(1.0, extractor.mu_.Row(i), utt_stats.X_.Row(i));
    XsupsupX_sp.CopyFromMat(XsupsupX);
    gamma_supV_supV_[i].AddSp(1.0, utt_stats.S_[i]);
    gamma_supV_supV_[i].AddSp(-1.0, XsupsupX_sp);
    gamma_supV_supV_[i].AddVec2(utt_stats.gamma_(i), extractor.mu_.Row(i));
  }
  sum_iV_.AddVec(1.0, ivector);
  iV_iV_.AddSp(1.0, ivec_scatter);
  num_ivectors_++;
}

void IvectorExtractorStats::Write(std::ostream &os, bool binary) const {
  WriteToken(os, binary, "<IvectorExtractorStats3>");
  WriteToken(os, binary, "<gammaSupViV>");
  int32 size = gamma_supV_iV_.size();
  WriteBasicType(os, binary, size);
  for (int32 i = 0; i < size; i++)
    gamma_supV_iV_[i].Write(os, binary);
  WriteToken(os, binary, "<gammaiViV>");
  gamma_iV_iV_.Write(os, binary);
  WriteToken(os, binary, "<gammaSupVsupV>");
  size = gamma_supV_supV_.size();
  WriteBasicType(os, binary, size);
  for (int32 i = 0; i < size; i++)
    gamma_supV_supV_[i].Write(os, binary);
  WriteToken(os, binary, "<sumiV>");
  sum_iV_.Write(os, binary);
  WriteToken(os, binary, "<iViV>");
  iV_iV_.Write(os, binary);
  WriteToken(os, binary, "<Gamma>");
  gamma_.Write(os, binary);
  WriteToken(os, binary, "<NumIvectors>");
  WriteBasicType(os, binary, num_ivectors_);
  WriteToken(os, binary, "</IvectorExtractorStats3>");
}

void IvectorExtractorStats::Read(std::istream &is, bool binary, bool add) {
  ExpectToken(is, binary, "<IvectorExtractorStats3>");
  ExpectToken(is, binary, "<gammaSupViV>");
  int32 size;
  ReadBasicType(is, binary, &size);
  gamma_supV_iV_.resize(size);
  for (int32 i = 0; i < size; i++)
    gamma_supV_iV_[i].Read(is, binary, add);
  ExpectToken(is, binary, "<gammaiViV>");
  gamma_iV_iV_.Read(is, binary, add);
  ExpectToken(is, binary, "<gammaSupVsupV>");
  ReadBasicType(is, binary, &size);
  gamma_supV_supV_.resize(size);
  for (int32 i = 0; i < size; i++)
    gamma_supV_supV_[i].Read(is, binary, add);
  ExpectToken(is, binary, "<sumiV>");
  sum_iV_.Read(is, binary, add);
  ExpectToken(is, binary, "<iViV>");
  iV_iV_.Read(is, binary, add);
  ExpectToken(is, binary, "<Gamma>");
  gamma_.Read(is, binary, add);
  ExpectToken(is, binary, "<NumIvectors>");
  ReadBasicType(is, binary, &num_ivectors_, add);
  ExpectToken(is, binary, "</IvectorExtractorStats3>");

}

void IvectorExtractorStats::Update(IvectorExtractor &extractor, const IvectorExtractorEstimationOptions &update_opts) {
  // Update transform matrix
  int32 ivector_dim = extractor.IvectorDim();
  SpMatrix<double> gamma_iV_iV_sp(ivector_dim, kUndefined);
  SubVector<double> gamma_iV_iV_sub(gamma_iV_iV_sp.Data(), ivector_dim * (ivector_dim+1) / 2);

  // prepare for Kaldi's solver
  SolverOptions solver_opts;
  solver_opts.name = "M";
  solver_opts.diagonal_precondition = true;

  for (int32 i = 0; i < extractor.NumGauss(); i++) {
    if (gamma_(i) < update_opts.gaussian_min_count) {
      KALDI_WARN << "Skipping Gaussian index " << i << " because count "
                 << gamma_(i) << " is below min-count.";
      continue;
    }
    SubVector<double> gamma_iV_iV_vec(gamma_iV_iV_, i); // i'th row of R; vectorized form of SpMatrix.
    gamma_iV_iV_sub.CopyFromVec(gamma_iV_iV_vec);       // copy to SpMatrix's memory.
    if (!update_opts.floor_iv2) {     // straight forward way of solving for A
      gamma_iV_iV_sp.Invert();
      extractor.A_[i].AddMatSp(1.0, gamma_supV_iV_[i], kNoTrans, gamma_iV_iV_sp, 0.0);
    } else {                          // Kaldi's solver
      SolveQuadraticMatrixProblem(gamma_iV_iV_sp, gamma_supV_iV_[i], extractor.Psi_inv_[i], solver_opts, &extractor.A_[i]);
    }
  }

  // Update variance
  if (update_opts.update_variance) {
    Matrix<double> tmp_Psi(extractor.FeatDim(), extractor.FeatDim());

    SpMatrix<double> tot_Psi(extractor.FeatDim());

    bool floor_psi = (update_opts.variance_floor_factor != 0) ;

    for (int32 i = 0; i < extractor.NumGauss(); i++) {
      if (gamma_(i) < update_opts.gaussian_min_count) continue; // warned in UpdateProjections

      tmp_Psi.AddMatMat(-2.0, extractor.A_[i], kNoTrans, gamma_supV_iV_[i], kTrans, 0.0);
      extractor.Psi_inv_[i].CopyFromMat(tmp_Psi);
      extractor.Psi_inv_[i].AddSp(1.0, gamma_supV_supV_[i]);
     
      SubVector<double> gamma_iV_iV_vec(gamma_iV_iV_, i); // i'th row of R; vectorized form of SpMatrix.
      gamma_iV_iV_sub.CopyFromVec(gamma_iV_iV_vec);       // copy to SpMatrix's memory.
     
      extractor.Psi_inv_[i].AddMat2Sp(1.0, extractor.A_[i], kNoTrans, gamma_iV_iV_sp, 0.0);
      extractor.Psi_inv_[i].Scale(1.0 / gamma_(i));
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

  // Update "Prior", it's not prior here, but does something similar to Kaldi
  if (update_opts.update_prior) {
    Vector<double> sum(sum_iV_);
    sum.Scale(1.0 / num_ivectors_);
    SpMatrix<double> covar(iV_iV_);
    covar.Scale(1.0 / num_ivectors_);
    covar.AddVec2(-1.0, sum); // Get the centered covariance.
    int32 ivector_dim = extractor.IvectorDim();
    Vector<double> s(ivector_dim);
    Matrix<double> P(ivector_dim, ivector_dim);
    // decompose covar = P diag(s) P^T:
    covar.Eig(&s, &P);
    KALDI_LOG << "Eigenvalues of iVector covariance range from "
              << s.Min() << " to " << s.Max();
    int32 num_floored = s.ApplyFloor(1.0e-07);
    if (num_floored > 0)
    KALDI_WARN << "Floored " << num_floored << " eigenvalues of covar "
               << "of iVectors.";
    Matrix<double> T(P, kTrans);
    { // set T to a transformation that makes covar unit
      // (modulo floored eigenvalues).
      Vector<double> scales(s);
      scales.ApplyPow(-0.5);
      T.MulRowsVec(scales);
      if (num_floored == 0) { // a check..
        SpMatrix<double> Tproj(ivector_dim);
        Tproj.AddMat2Sp(1.0, T, kNoTrans, covar, 0.0);
        KALDI_ASSERT(Tproj.IsUnit(1.0e-06));
      }
    }
    extractor.TransformIvectors(T);
  }

  extractor.ComputeDerivedValues();
}

double IvectorExtractorStats::GetAuxfValue(const IvectorExtractor &extractor) const {
  KALDI_ERR << "Not working here";
  int32 feat_dim = extractor.FeatDim();
  int32 ivector_dim = extractor.IvectorDim();

  Matrix<double> tmp_mat(feat_dim, feat_dim);
  SpMatrix<double> tmp_sp_mat(feat_dim);
  Matrix<double> tmp_mat_Psi_inv(feat_dim, feat_dim);
  
  SpMatrix<double> gamma_iV_iV_sp(ivector_dim, kUndefined);
  SubVector<double> gamma_iV_iV_sub(gamma_iV_iV_sp.Data(), ivector_dim * (ivector_dim+1) / 2);

  double logDetPsi = 0;
  double trace2nd = 0;
  double normivec = 0;

  for (int32 i = 0; i < extractor.NumGauss(); i++) {
    if (gamma_(i) != 0) {
      logDetPsi += log(gamma_(i));
    }
    logDetPsi += extractor.Psi_inv_[i].LogDet();
    tmp_mat.CopyFromSp(gamma_supV_supV_[i]);
    tmp_mat.AddMatMat(-2.0, gamma_supV_iV_[i], kNoTrans, extractor.A_[i], kTrans, 1.0);
    tmp_sp_mat.CopyFromMat(tmp_mat);

    SubVector<double> gamma_iV_iV_vec(gamma_iV_iV_, i); // i'th row of R; vectorized form of SpMatrix.
    gamma_iV_iV_sub.CopyFromVec(gamma_iV_iV_vec);       // copy to gamma_iV_iV_sp's memory.
    tmp_sp_mat.AddMat2Sp(1.0, extractor.A_[i], kNoTrans, gamma_iV_iV_sp, 0.0);

    tmp_mat_Psi_inv.AddSpSp(1.0, tmp_sp_mat, extractor.Psi_inv_[i], 0.0);
    trace2nd += tmp_mat_Psi_inv.Trace();

    normivec = 0;
  }
  double auxf = - gamma_.Sum() / 2 * logDetPsi - trace2nd / 2 - normivec / 2;
  return auxf;
}

IvectorExtractor::IvectorExtractor(const IvectorExtractorOptions &opts, int32 feat_dim, int32 num_gauss):
                                   opts_(opts) {
  mu_.Resize(num_gauss, feat_dim);
  A_.resize(num_gauss);
  Psi_inv_.resize(num_gauss);
  for (int32 i = 0; i < num_gauss; i++) {
    A_[i].Resize(feat_dim, opts.ivector_dim);
    Psi_inv_[i].Resize(feat_dim);
  }
}

IvectorExtractor::IvectorExtractor(const IvectorExtractorOptions &opts, const IvectorExtractorUtteranceStats &stats):
                                   opts_(opts) {
  int32 num_gauss = stats.X_.NumRows();
  int32 feat_dim = stats.X_.NumCols();

  mu_.Resize(num_gauss, feat_dim);

  A_.resize(num_gauss);
  Psi_inv_.resize(num_gauss);
  for (int32 i = 0; i < num_gauss; i++) {
    if (stats.gamma_(i) != 0) {
      mu_.Row(i).AddVec(1.0 / stats.gamma_(i), stats.X_.Row(i));
      A_[i].Resize(feat_dim, opts.ivector_dim);
      A_[i].SetRandn();
      Psi_inv_[i].Resize(feat_dim);
      Psi_inv_[i].AddSp(1.0 / stats.gamma_(i), stats.S_[i]);
      Psi_inv_[i].AddVec2(-1.0, mu_.Row(i));
      Psi_inv_[i].Invert();
    } else {
      KALDI_ERR << "gamma(i) == 0 for compnent" << i;
    }
  }
  ComputeDerivedValues();
}

IvectorExtractor::IvectorExtractor(const IvectorExtractorOptions &opts,
                                   const FullGmm &fgmm) : opts_(opts) {
  KALDI_ASSERT(opts.ivector_dim > 0);
  const int32 num_gauss = fgmm.NumGauss();
  const int32 feat_dim = fgmm.Dim();
  Psi_inv_.resize(num_gauss);
  for (int32 i = 0; i < num_gauss; i++) {
    const SpMatrix<BaseFloat> &inv_var = fgmm.inv_covars()[i];
    Psi_inv_[i].Resize(inv_var.NumRows());
    Psi_inv_[i].CopyFromSp(inv_var);
  }
  
  mu_.Resize(num_gauss, feat_dim);
  fgmm.GetMeans(&mu_);
 
  A_.resize(num_gauss);
  for (int32 i = 0; i < num_gauss; i++) {
    A_[i].Resize(feat_dim, opts.ivector_dim);
    A_[i].SetRandn();
  }

  ComputeDerivedValues();
}

void IvectorExtractor::GetIvectorDistribution(const IvectorExtractorUtteranceStats &stats,
                                              VectorBase<double> *mean,
                                              SpMatrix< double > *var,
                                              MatrixBase<double> *normalized_gammasup, 
                                              double *auxf) const {
  Vector<double> linear(IvectorDim());
  SpMatrix<double> quadratic(IvectorDim());
  Matrix<double> x(stats.X_);
  for (int32 i = 0; i < NumGauss(); i++) {
    if (stats.gamma_(i) != 0) {
      x.Row(i).AddVec(-stats.gamma_(i), mu_.Row(i));
      linear.AddMatVec(1.0, Psi_inv_A_[i], kTrans, x.Row(i), 1.0);   // becomes A^T * Psi_inv * gamma * (\mu_sd - \mu)
    }
  }
  if (normalized_gammasup != NULL) {
    normalized_gammasup->CopyFromMat(x);
  }
  SubVector<double> q_vec(quadratic.Data(), IvectorDim()*(IvectorDim()+1)/2);
  q_vec.AddMatVec(1.0, AT_Psi_inv_A_, kTrans, stats.gamma_, 0.0);   // A^T * Psi_inv * gamma * A
  quadratic.AddToDiag(1.0);
  quadratic.Invert();
  if (var != NULL) {
    var->CopyFromSp(quadratic);
  }
  KALDI_ASSERT(mean != NULL);
  mean->AddSpVec(1.0, quadratic, linear, 0.0);
  if (auxf != NULL) {
    *auxf = ComputeAuxf(stats, *mean, quadratic, x);
  }
}
  
double IvectorExtractor::ComputeAuxf(const IvectorExtractorUtteranceStats &stats,
                                     const VectorBase<double> &ivector,
                                     const SpMatrix<double> &ivec_var,
                                     const MatrixBase<double> &normalized_gammasup) const {
  double log_det = 0;
  const int32 ivector_dim = IvectorDim();
  const int32 feat_dim = FeatDim();

  SpMatrix<double> ivec_scatter(ivec_var);
  ivec_scatter.AddVec2(1.0, ivector);       // ivector^2 + ivec_var

  Matrix<double> final_mat(feat_dim, feat_dim);
  Matrix<double> gammasup_iV(feat_dim, ivector_dim);
  Matrix<double> tmp_acc_mat(feat_dim, feat_dim);
  SpMatrix<double> tmp_acc_mat_sp(tmp_acc_mat);

  double trace = 0;
  for (int32 i = 0; i < NumGauss(); i++) {
    if (stats.gamma_(i) == 0)
      continue;
    log_det -= Psi_inv_[i].LogDet();
    log_det -= FeatDim() * log(stats.gamma_(i));

    gammasup_iV.SetZero();
    gammasup_iV.AddVecVec(1.0, normalized_gammasup.Row(i), ivector);                // gamma * (x-mu) * ivec^T
    tmp_acc_mat.AddMatMat(-2.0, gammasup_iV, kNoTrans, A_[i], kTrans, 0.0);         // -2 * gamma * (x-mu) * ivec^T * A^T
    tmp_acc_mat_sp.CopyFromMat(tmp_acc_mat);
    tmp_acc_mat_sp.AddVec2(1 / stats.gamma_(i), normalized_gammasup.Row(i));      // -2 * gamma * (x-mu) * ivec^T * A^T + gamma * (x-mu) * (x-mu)^T
    tmp_acc_mat_sp.AddMat2Sp(stats.gamma_(i), A_[i], kNoTrans, ivec_scatter, 1.0);  // -2 * gamma * (x-mu) * ivec^T * A^T + gamma * (x-mu) * (x-mu)^T + gamma * A * E(ivec*ivec^T) * A^T
    final_mat.AddSpSp(1.0, tmp_acc_mat_sp, Psi_inv_[i], 0.0);       // ((x-mu) * (x-mu)^T - 2 * (x-mu) * ivec^T * A^T + A * E(ivec*ivec^T) * A^T) * gamma * Psi^{-1}
    trace += final_mat.Trace();
  }
  double auxf = -1/2 * (log_det + trace + ivec_scatter.Trace());
  return auxf;
}

void IvectorExtractor::ComputeDerivedValues() {
  AT_Psi_inv_A_.Resize(NumGauss(), IvectorDim() * (IvectorDim() + 1) / 2);
  Psi_inv_A_.resize(NumGauss());
  SpMatrix<double> temp_Var(IvectorDim());      // temp_Var = A_i^T Psi_i^{-1} A_i
  for (int32 i = 0; i < NumGauss(); i++) {
    Psi_inv_A_[i].Resize(FeatDim(), IvectorDim());
    Psi_inv_A_[i].AddSpMat(1.0, Psi_inv_[i], A_[i], kNoTrans, 1.0);
    temp_Var.AddMat2Sp(1.0, A_[i], kTrans, Psi_inv_[i], 0.0);
    SubVector<double> temp_Var_vec(temp_Var.Data(),
                                   IvectorDim() * (IvectorDim() + 1) / 2);
    AT_Psi_inv_A_.Row(i).CopyFromVec(temp_Var_vec);
  }
}

void IvectorExtractor::TransformIvectors(const MatrixBase< double > & T) {
  Matrix<double> Tinv(T);
  Tinv.Invert();
  for (int32 i = 0; i < NumGauss(); i++)
    A_[i].AddMatMat(1.0, Matrix<double>(A_[i]), kNoTrans, Tinv, kNoTrans, 0.0);
}

void IvectorExtractor::Write(std::ostream &os, bool binary, const bool write_derived /* = false */) const {
  WriteToken(os, binary, "<IvectorExtractor3>");
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
  WriteToken(os, binary, "</IvectorExtractor3>");
}

void IvectorExtractor::Read(std::istream &is, bool binary, const bool read_derived /* = false */) {
  ExpectToken(is, binary, "<IvectorExtractor3>");
  ExpectToken(is, binary, "<mu>");
  mu_.Read(is, binary);
  int32 num_gauss = mu_.NumRows();
  int32 feat_dim = mu_.NumCols();
  ExpectToken(is, binary, "<A>");  
  int32 size;
  ReadBasicType(is, binary, &size);
  if(size != num_gauss)
    KALDI_ERR << "Dimension mismatch: transformation matrix A_.size() : " << size << " vs mu_.NumRows() " << num_gauss;
  A_.resize(size);
  for (int32 i = 0; i < size; i++) {
    A_[i].Read(is, binary);
    if (A_[i].NumRows() != feat_dim) {
      KALDI_ERR << "Dimension mismatch: transformation matrix A_[" << i << "].NumRows() : " << A_[i].NumRows() << " vs mu_.NumCols() " << feat_dim;
    }
  }
  ExpectToken(is, binary, "<PsiInv>");
  Psi_inv_.resize(size);
  for (int32 i = 0; i < size; i++)
    Psi_inv_[i].Read(is, binary);
  ExpectToken(is, binary, "</IvectorExtractor3>");

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
