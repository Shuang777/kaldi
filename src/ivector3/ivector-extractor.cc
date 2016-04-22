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
#include "thread/kaldi-task-sequence.h"
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

  Vector<double> ivector(ivector_dim);
  Matrix<double> normalized_gammasup(num_gauss, feat_dim);
  SpMatrix<double> ivector_var(ivector_dim);

  extractor.GetIvectorDistribution(utt_stats, &ivector, &ivector_var, &normalized_gammasup);
  
  gamma_iV_lock_.Lock();
  gamma_.AddVec(1.0, utt_stats.gamma_);

  SpMatrix<double> ivec_scatter(ivector_var);
  ivec_scatter.AddVec2(1.0, ivector);       // ivector^2 + ivec_var
  SubVector<double> ivec_scatter_vec(ivec_scatter.Data(),
                                     ivector_dim * (ivector_dim + 1) / 2);
  gamma_iV_iV_.AddVecVec(1.0, utt_stats.gamma_, ivec_scatter_vec);
  sum_iV_.AddVec(1.0, ivector);
  iV_iV_.AddSp(1.0, ivec_scatter);
  num_ivectors_++;
  gamma_iV_lock_.Unlock();

  gamm_supV_iV_lock_.Lock();
  for (int32 i = 0; i < extractor.NumGauss(); i++) {
    gamma_supV_iV_[i].AddVecVec(1.0, normalized_gammasup.Row(i), ivector);
  }
  gamm_supV_iV_lock_.Unlock();
  

  Matrix<double> XsupsupX (feat_dim, feat_dim);
  SpMatrix<double> XsupsupX_sp (feat_dim);
  gamma_supV_supV_lock_.Lock();
  for (int32 i = 0; i < extractor.NumGauss(); i++) {
    //gamma_supV_supV_[i].AddVec2(1.0 / utt_stats.gamma_(i), normalized_gammasup.Row(i));
    gamma_supV_supV_[i].AddSp(1.0, utt_stats.S_[i]);
    if (!extractor.PriorMode()) {
      XsupsupX.SetZero();
      XsupsupX.AddVecVec(1.0, extractor.mu_.Row(i), utt_stats.X_.Row(i));
      XsupsupX.AddVecVec(1.0, normalized_gammasup.Row(i), extractor.mu_.Row(i));
      XsupsupX_sp.CopyFromMat(XsupsupX);
      gamma_supV_supV_[i].AddSp(-1.0, XsupsupX_sp);
    }
  }
  gamma_supV_supV_lock_.Unlock();
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

void IvectorExtractorStats::GetOrthogonalIvectorTransform(
                              const SubMatrix<double> &T,
                              IvectorExtractor &extractor,
                              Matrix<double> *A) const {
  extractor.ComputeDerivedVariables(); // Update the extractor->U_ matrix.
  int32 ivector_dim = extractor.IvectorDim();
  int32 quad_dim = ivector_dim*(ivector_dim + 1)/2;

  // Each row of extractor->U_ is an SpMatrix. We can compute the weighted
  // avg of these rows in a SubVector that updates the data of the SpMatrix
  // Uavg.
  SpMatrix<double> Uavg(ivector_dim), Vavg(ivector_dim - 1);
  SubVector<double> uavg_vec(Uavg.Data(), quad_dim);
  uavg_vec.AddMatVec(1.0, extractor.AT_Psi_inv_A_, kTrans, extractor.w_vec_, 0.0);

  Matrix<double> Tinv(T);
  Tinv.Invert();
  Matrix<double> Vavg_temp(Vavg), Uavg_temp(Uavg);

  Vavg_temp.AddMatMatMat(1.0, Tinv, kTrans, SubMatrix<double>(Uavg_temp,
                           1, ivector_dim-1, 1, ivector_dim-1),
                         kNoTrans, Tinv, kNoTrans, 0.0);
  Vavg.CopyFromMat(Vavg_temp);

  Vector<double> s(ivector_dim-1);
  Matrix<double> P(ivector_dim-1, ivector_dim-1);
  Vavg.Eig(&s, &P);
  SortSvd(&s, &P);
  A->Resize(P.NumCols(), P.NumRows());
  A->SetZero();
  A->AddMat(1.0, P, kTrans);
  KALDI_LOG << "Eigenvalues of Vavg: " << s;
}

void IvectorExtractorStats::UpdateProjection(
    const IvectorExtractorEstimationOptions &update_opts,
    int32 i,
    IvectorExtractor *extractor) const {

  // Update transform matrix
  int32 ivector_dim = extractor->IvectorDim();
  int32 num_gauss = extractor->NumGauss();
  KALDI_ASSERT(i >= 0 && i < num_gauss);

  SpMatrix<double> gamma_iV_iV_sp(ivector_dim, kUndefined);
  SubVector<double> gamma_iV_iV_sub(gamma_iV_iV_sp.Data(), ivector_dim * (ivector_dim+1) / 2);

  // prepare for Kaldi's solver
  SolverOptions solver_opts;
  solver_opts.name = "M";
  solver_opts.diagonal_precondition = true;

  if (gamma_(i) < update_opts.gaussian_min_count) {
    KALDI_WARN << "Skipping Gaussian index " << i << " because count "
               << gamma_(i) << " is below min-count.";
    return;
  }
  SubVector<double> gamma_iV_iV_vec(gamma_iV_iV_, i); // i'th row of R; vectorized form of SpMatrix.
  gamma_iV_iV_sub.CopyFromVec(gamma_iV_iV_vec);       // copy to SpMatrix's memory.
  if (!update_opts.floor_iv2) {     // straight forward way of solving for A
    gamma_iV_iV_sp.Invert();
    extractor->A_[i].AddMatSp(1.0, gamma_supV_iV_[i], kNoTrans, gamma_iV_iV_sp, 0.0);
  } else {                          // Kaldi's solver
    SolveQuadraticMatrixProblem(gamma_iV_iV_sp, gamma_supV_iV_[i], extractor->Psi_inv_[i], solver_opts, &(extractor->A_[i]));
  }
}

class IvectorExtractorUpdateProjectionClass {
 public:
  IvectorExtractorUpdateProjectionClass(const IvectorExtractorStats &stats,
                        const IvectorExtractorEstimationOptions &opts,
                        int32 i,
                        IvectorExtractor *extractor):
      stats_(stats), opts_(opts), i_(i), extractor_(extractor) { }
  void operator () () {
    stats_.UpdateProjection(opts_, i_, extractor_);
  }
 private:
  const IvectorExtractorStats &stats_;
  const IvectorExtractorEstimationOptions &opts_;
  int32 i_;
  IvectorExtractor *extractor_;
};

void IvectorExtractorStats::UpdateProjections(
    const IvectorExtractorEstimationOptions &opts,
    IvectorExtractor &extractor) const {

  int32 num_gauss = extractor.NumGauss();
  {
    TaskSequencerConfig sequencer_opts;
    sequencer_opts.num_threads = g_num_threads;
    TaskSequencer<IvectorExtractorUpdateProjectionClass> sequencer(
        sequencer_opts);
    for (int32 i = 0; i < num_gauss; i++)
      sequencer.Run(new IvectorExtractorUpdateProjectionClass(
          *this, opts, i, &extractor));
  }
}


void IvectorExtractorStats::Update(IvectorExtractor &extractor, const IvectorExtractorEstimationOptions &update_opts) {
  
  UpdateProjections(update_opts, extractor);

  // Update variance
  if (update_opts.update_variance) {
    int32 feat_dim = extractor.FeatDim();
    Matrix<double> AY(feat_dim, feat_dim);
    Matrix<double> AYYA(feat_dim, feat_dim);

    SpMatrix<double> tot_Psi(feat_dim);

    bool floor_psi = (update_opts.variance_floor_factor != 0) ;

    int32 ivector_dim = extractor.IvectorDim();
    SpMatrix<double> gamma_iV_iV_sp(ivector_dim, kUndefined);
    SubVector<double> gamma_iV_iV_sub(gamma_iV_iV_sp.Data(), ivector_dim * (ivector_dim+1) / 2);

    for (int32 i = 0; i < extractor.NumGauss(); i++) {
      if (gamma_(i) < update_opts.gaussian_min_count) continue; // warned in UpdateProjections

      AY.AddMatMat(-1.0, extractor.A_[i], kNoTrans, gamma_supV_iV_[i], kTrans, 0.0);   // = - A*Y^T
      AYYA.CopyFromMat(AY, kTrans);   // = - Y^T*A
      AYYA.AddMat(1.0, AY);           // = - (A*Y^T + Y^T*A)

      extractor.Psi_inv_[i].CopyFromMat(AYYA);
      extractor.Psi_inv_[i].AddSp(1.0, gamma_supV_supV_[i]);
     
      SubVector<double> gamma_iV_iV_vec(gamma_iV_iV_, i); // i'th row of R; vectorized form of SpMatrix.
      gamma_iV_iV_sub.CopyFromVec(gamma_iV_iV_vec);       // copy to SpMatrix's memory.
     
      extractor.Psi_inv_[i].AddMat2Sp(1.0, extractor.A_[i], kNoTrans, gamma_iV_iV_sp, 1.0);
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
    if (extractor.PriorMode()) {
      Vector<double> sum_proj(ivector_dim);
      sum_proj.AddMatVec(1.0, T, kNoTrans, sum, 0.0);

      Matrix<double> U(ivector_dim, ivector_dim);
      U.SetUnit();
      Vector<double> x(sum_proj);
      x.Scale(1.0 / x.Norm(2.0));
      double x0 = x(0), alpha, beta;
      alpha = 1.0 / (M_SQRT2 * sqrt(1.0 - x0));
      beta = -alpha;
      Vector<double> a(x);
      a.Scale(alpha);
      a(0) += beta;
      U.AddVecVec(-2.0, a, a);
      Matrix<double> V(ivector_dim, ivector_dim);
      V.AddMatMat(1.0, U, kNoTrans, T, kNoTrans, 0.0);

      if (update_opts.diagonalize) {
        SubMatrix<double> Vsub(V, 1, V.NumRows()-1, 0, V.NumCols());
        Matrix<double> Vtemp(SubMatrix<double>(V, 1, V.NumRows()-1, 0, V.NumCols())),
                       A;
        GetOrthogonalIvectorTransform(SubMatrix<double>(Vtemp, 0,
                                      Vtemp.NumRows(), 1, Vtemp.NumCols()-1),
                                      extractor, &A);
        Vsub.AddMatMat(1.0, A, kNoTrans, Vtemp, kNoTrans, 0.0);

      }

      Vector<double> sum_vproj(ivector_dim);
      sum_vproj.AddMatVec(1.0, V, kNoTrans, sum, 0.0);
      // Make sure sum_vproj is of the form [ x 0 0 0 .. ] with x > 0.
      // (the x > 0 part isn't really necessary, it's just nice to know.)
      KALDI_ASSERT(ApproxEqual(sum_vproj(0), sum_vproj.Norm(2.0)));
      extractor.TransformIvectors(V);
      extractor.SetPriorOffset(sum_vproj(0));
    } else {
      extractor.TransformIvectors(T);
    }
  }
  if (update_opts.update_weights) {
    extractor.w_vec_.CopyFromVec(gamma_);
    extractor.w_vec_.Scale(1.0/gamma_.Sum());
  }
  extractor.ComputeDerivedVariables();
}


double IvectorExtractorStats::GetAuxfValueIvectorPrior(const IvectorExtractor &extractor) const {
  int32 ivector_dim = extractor.IvectorDim();
  double const_part = -ivector_dim / 2 * num_ivectors_ * (M_LOG_2PI + log(extractor.lambda_));
  double exp_part = - iV_iV_.Trace() / (2*extractor.lambda_);
  return (const_part + exp_part);
}

double IvectorExtractorStats::GetAuxfValueLikelihood(const IvectorExtractor &extractor) const {
  int32 num_gauss = extractor.NumGauss();
  int32 feat_dim = extractor.FeatDim();
  int32 ivector_dim = extractor.IvectorDim();

  double sum_gamma_logDet = 0;
  double sum_exponent_part = 0;
  Matrix<double> AY(feat_dim, feat_dim);
  Matrix<double> AYYA(feat_dim, feat_dim);
  SpMatrix<double> tmp_mat(feat_dim);
  Matrix<double> tmp_prod(feat_dim, feat_dim);
  SpMatrix<double> gamma_iV_iV_sp(ivector_dim, kUndefined);
  SubVector<double> gamma_iV_iV_sub(gamma_iV_iV_sp.Data(), ivector_dim * (ivector_dim+1) / 2);
     
  for (int32 i = 0; i < num_gauss; i++) {
    sum_gamma_logDet += gamma_(i) * extractor.GetPsiLogDet(i);
      
    AY.AddMatMat(-1.0, extractor.A_[i], kNoTrans, gamma_supV_iV_[i], kTrans, 0.0);   // = - A*Y^T
    AYYA.CopyFromMat(AY, kTrans);   // = - Y^T*A
    AYYA.AddMat(1.0, AY);           // = - (A*Y^T + Y^T*A)

    tmp_mat.CopyFromMat(AYYA);
    tmp_mat.AddSp(1.0, gamma_supV_supV_[i]);

    SubVector<double> gamma_iV_iV_vec(gamma_iV_iV_, i); // i'th row of R; vectorized form of SpMatrix.
    gamma_iV_iV_sub.CopyFromVec(gamma_iV_iV_vec);       // copy to SpMatrix's memory.

    tmp_mat.AddMat2Sp(1.0, extractor.A_[i], kNoTrans, gamma_iV_iV_sp, 1.0);

    tmp_prod.AddSpSp(1.0, tmp_mat, extractor.Psi_inv_[i], 0.0);
    sum_exponent_part += tmp_prod.Trace();
  }

  double auxf_llk = - gamma_.Sum() / 2 * M_LOG_2PI - sum_gamma_logDet / 2 - sum_exponent_part / 2;
  return auxf_llk;
}

double IvectorExtractorStats::GetAuxfValue(const IvectorExtractor &extractor) const {
  
  double auxf1 = GetAuxfValueIvectorPrior(extractor);
  double auxf2 = GetAuxfValueLikelihood(extractor);

  return auxf1 + auxf2;
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
  ComputeDerivedVariables();
}

IvectorExtractor::IvectorExtractor(const IvectorExtractorOptions &opts,
                                   const FullGmm &fgmm, const double lambda, 
                                   const bool compute_derived) : opts_(opts) {
  KALDI_ASSERT(opts.ivector_dim > 0);
  const int32 num_gauss = fgmm.NumGauss();
  const int32 feat_dim = fgmm.Dim();
  Psi_inv_.resize(num_gauss);
  for (int32 i = 0; i < num_gauss; i++) {
    const SpMatrix<BaseFloat> &inv_var = fgmm.inv_covars()[i];
    Psi_inv_[i].Resize(inv_var.NumRows());
    Psi_inv_[i].CopyFromSp(inv_var);
  }
  
  lambda_ = lambda;
  mu_.Resize(num_gauss, feat_dim);
  fgmm.GetMeans(&mu_);

  prior_offset_ = 100.0; // hardwired for now.  Must be nonzero.
  if (opts_.prior_mode)
    mu_.Scale(1.0 / prior_offset_);;
 
  A_.resize(num_gauss);
  for (int32 i = 0; i < num_gauss; i++) {
    A_[i].Resize(feat_dim, opts.ivector_dim);
    A_[i].SetRandn();
    if (opts_.prior_mode) {
      A_[i].CopyColFromVec(mu_.Row(i), 0);
    }
  }
  w_vec_.Resize(fgmm.NumGauss());
  w_vec_.CopyFromVec(fgmm.weights());

  if (compute_derived)
    ComputeDerivedVariables();
}

class IvectorExtractorComputeDerivedVarsClass {
 public:
  IvectorExtractorComputeDerivedVarsClass(IvectorExtractor *extractor,
                                          int32 i):
      extractor_(extractor), i_(i) { }
  void operator () () { extractor_->ComputeDerivedVars(i_); }
 private:
  IvectorExtractor *extractor_;
  int32 i_;
};

void IvectorExtractor::ComputeDerivedVariables() {
  KALDI_LOG << "Computing derived variables for iVector extractor";
  const int32 num_gauss = NumGauss();
  const int32 ivector_dim = IvectorDim();

  AT_Psi_inv_A_.Resize(num_gauss, ivector_dim * (ivector_dim + 1) / 2);
  Psi_inv_A_.resize(num_gauss);
  gconsts_.Resize(num_gauss);

  {
    TaskSequencerConfig sequencer_opts;
    sequencer_opts.num_threads = g_num_threads;
    TaskSequencer<IvectorExtractorComputeDerivedVarsClass> sequencer(
        sequencer_opts);
    for (int32 i = 0; i < NumGauss(); i++)
      sequencer.Run(new IvectorExtractorComputeDerivedVarsClass(this, i));
  }
  KALDI_LOG << "Done.";
}

void IvectorExtractor::ComputeDerivedVars(int32 i) {

  double var_logdet = -Psi_inv_[i].LogPosDefDet();
  gconsts_(i) = -0.5 * (var_logdet + FeatDim() * M_LOG_2PI);

  SpMatrix<double> temp_Var(IvectorDim());
  // temp_U = M_i^T Sigma_i^{-1} M_i
  temp_Var.AddMat2Sp(1.0, A_[i], kTrans, Psi_inv_[i], 0.0);
  SubVector<double> temp_Var_vec(temp_Var.Data(),
                               IvectorDim() * (IvectorDim() + 1) / 2);
  AT_Psi_inv_A_.Row(i).CopyFromVec(temp_Var_vec);

  Psi_inv_A_[i].Resize(FeatDim(), IvectorDim());
  Psi_inv_A_[i].AddSpMat(1.0, Psi_inv_[i], A_[i], kNoTrans, 0.0);
}


void IvectorExtractor::GetIvectorDistribution(const IvectorExtractorUtteranceStats &stats,
                                              VectorBase<double> *mean,
                                              SpMatrix< double > *var,
                                              MatrixBase<double> *normalized_gammasup, 
                                              double *auxf, bool for_scoring) const {
  const int32 ivector_dim = IvectorDim();
  const int32 num_gauss = NumGauss();
  Vector<double> linear(ivector_dim);
  SpMatrix<double> quadratic(ivector_dim);
  Matrix<double> x(stats.X_);
  for (int32 i = 0; i < num_gauss; i++) {
    if (stats.gamma_(i) != 0) {
      if (!opts_.prior_mode) {
        x.Row(i).AddVec(-stats.gamma_(i), mu_.Row(i));
      }
      SubVector<double> x_i(x, i);
      linear.AddMatVec(1.0, Psi_inv_A_[i], kTrans, x_i, 1.0);   // becomes A^T * Psi_inv * gamma * (\mu_sd - \mu)
    }
  }
  if (normalized_gammasup != NULL) {
    normalized_gammasup->CopyFromMat(x);
  }
  SubVector<double> q_vec(quadratic.Data(), IvectorDim()*(IvectorDim()+1)/2);
  q_vec.AddMatVec(1.0, AT_Psi_inv_A_, kTrans, stats.gamma_, 0.0);   // A^T * Psi_inv * gamma * A
  if (opts_.prior_mode) {
    linear(0) += prior_offset_;
  }
  quadratic.AddToDiag(1.0/lambda_);
  quadratic.Invert();

  if (var != NULL) {
    var->CopyFromSp(quadratic);
  }
  
  KALDI_ASSERT(mean != NULL);
  mean->AddSpVec(1.0, quadratic, linear, 0.0);
  if (auxf != NULL) {
    *auxf = ComputeAuxf(stats, *mean, quadratic, x);
  }
  if (for_scoring && PriorMode()) {
    (*mean)(0) -= PriorOffset();
  }
}

BaseFloat IvectorExtractor::LogLikelihood(const VectorBase<BaseFloat> & data, 
                                          const int32 idx, const VectorBase<double> &ivector) const {
  Vector<double> x(data);
  x.AddMatVec(-1.0, A_[idx], kNoTrans, ivector, 1.0);
  if (!PriorMode()) {
    SubVector<double> bias(mu_, idx);
    x.AddVec(-1.0, bias);
  }
  return gconsts_(idx) - 0.5 * VecSpVec(x, Psi_inv_[idx], x);
}

void IvectorExtractor::PostPreselect(const MatrixBase<BaseFloat> &feats, 
                                     const Posterior &post, 
                                     Posterior &new_post) const {

  KALDI_ASSERT(new_post.size() == post.size());

  int32 feat_dim = FeatDim();
  int32 num_gauss = NumGauss();
  int32 ivector_dim = IvectorDim();

  bool need_2nd_order_stats = false;
  IvectorExtractorUtteranceStats utt_stats(num_gauss, feat_dim, need_2nd_order_stats);
  utt_stats.AccStats(feats, post);

  Vector<double> ivector(ivector_dim);
  GetIvectorDistribution(utt_stats, &ivector);
  
  Vector<BaseFloat> loglikes;
  for (int32 t = 0; t < post.size(); t++) {
    loglikes.Resize(post[t].size());
    SubVector<BaseFloat> feat(feats, t);
    for (int32 i = 0; i < post[t].size(); i++) {
      int32 index = post[t][i].first;
      loglikes(i) = LogLikelihood(feat, index, ivector);  
    }
    loglikes.ApplySoftMax();
    int32 max_index;
    loglikes.Max(&max_index);
    BaseFloat sum = loglikes.Sum();
    if (sum == 0.0) {
      loglikes(max_index) = 1.0;
    } else {
      loglikes.Scale(1.0 / sum);
    }
    for (int32 i = 0; i < loglikes.Dim(); i++) {
      if (loglikes(i) != 0.0) {
        new_post[t].push_back(std::make_pair(post[t][i].first, loglikes(i)));
      }
    }
  }
}

double IvectorExtractor::ComputeAuxfPrior(const SpMatrix<double> & ivec_scatter) const {
  int32 ivector_dim = IvectorDim();
  double const_part = -ivector_dim / 2 * (M_LOG_2PI + log(lambda_));
  double exp_part = - ivec_scatter.Trace() / (2*lambda_);
  return (const_part + exp_part);
}

double IvectorExtractor::ComputeAuxfLikelihood(const IvectorExtractorUtteranceStats &utt_stats,
                                               const VectorBase<double> &ivector,
                                               const SpMatrix<double> & ivec_scatter,
                                               const MatrixBase<double> &normalized_gammasup) const {

  int32 num_gauss = NumGauss();
  int32 ivector_dim = IvectorDim();
  int32 feat_dim = FeatDim();

  double sum_gamma_logDet = 0;
  double sum_exponent_part = 0;
  Matrix<double> AY(feat_dim, feat_dim);
  Matrix<double> AYYA(feat_dim, feat_dim);
  Matrix<double> tmp_AY_mat(feat_dim, ivector_dim);
  SpMatrix<double> tmp_mat(feat_dim);
  Matrix<double> tmp_prod(feat_dim, feat_dim);
     
  for (int32 i = 0; i < num_gauss; i++) {
    sum_gamma_logDet += utt_stats.gamma_(i) * GetPsiLogDet(i);
    
    tmp_AY_mat.SetZero();
    tmp_AY_mat.AddVecVec(1.0, normalized_gammasup.Row(i), ivector);   // gamma * (x_{it}-\mu_k) * z_i^T
    AY.AddMatMat(-1.0, A_[i], kNoTrans, tmp_AY_mat, kTrans, 0.0);   // = - gamma * A * z_i * (x_{it}-\mu_k)^T
    AYYA.CopyFromMat(AY, kTrans);   // = - gamma * (x_{it}-\mu_k) * (A * z_i) ^ T
    AYYA.AddMat(1.0, AY);           // = - gamma * (x_{it}-\mu_k) * (A * z_i) ^ T - gamma * A * z_i * (x_{it}-\mu_k)^T

    AYYA.AddSp(1.0, utt_stats.S_[i]);   // = + gamma * (x_{it}-\mu_k) * (x_{it}-\mu_k) ^ T
    if (!PriorMode()) {
      AYYA.AddVecVec(-1.0, mu_.Row(i), utt_stats.X_.Row(i));
      AYYA.AddVecVec(-1.0, normalized_gammasup.Row(i), mu_.Row(i));
    }

    tmp_mat.CopyFromMat(AYYA);
    tmp_mat.AddMat2Sp(utt_stats.gamma_(i), A_[i], kNoTrans, ivec_scatter, 1.0);

    tmp_prod.AddSpSp(1.0, tmp_mat, Psi_inv_[i], 0.0);
    sum_exponent_part += tmp_prod.Trace();
  }

  double auxf_llk = - utt_stats.gamma_.Sum() / 2 * M_LOG_2PI - sum_gamma_logDet / 2 - sum_exponent_part / 2;
  return auxf_llk;
}

double IvectorExtractor::ComputeAuxf(const IvectorExtractorUtteranceStats &stats,
                                     const VectorBase<double> &ivector,
                                     const SpMatrix<double> &ivec_var,
                                     const MatrixBase<double> &normalized_gammasup) const {

  SpMatrix<double> ivec_scatter(ivec_var);
  ivec_scatter.AddVec2(1.0, ivector);       // ivector^2 + ivec_var

  double auxf1 = ComputeAuxfPrior(ivec_scatter);
  double auxf2 = ComputeAuxfLikelihood(stats, ivector, ivec_scatter, normalized_gammasup);

  return auxf1 + auxf2;
}

void IvectorExtractor::TransformIvectors(const MatrixBase< double > & T) {
  Matrix<double> Tinv(T);
  Tinv.Invert();
  for (int32 i = 0; i < NumGauss(); i++)
    A_[i].AddMatMat(1.0, Matrix<double>(A_[i]), kNoTrans, Tinv, kNoTrans, 0.0);
}

void IvectorExtractor::Write(std::ostream &os, bool binary, const bool write_derived /* = false */) const {
  WriteToken(os, binary, "<IvectorExtractor3>");
  opts_.Write(os, binary);
  WriteToken(os, binary, "<lambda>");
  WriteBasicType(os, binary, lambda_);
  WriteToken(os, binary, "<mu>");
  mu_.Write(os, binary);
  WriteToken(os, binary, "<w_vec>");
  w_vec_.Write(os, binary);
  WriteToken(os, binary, "<A>");  
  int32 size = A_.size();
  WriteBasicType(os, binary, size);
  for (int32 i = 0; i < size; i++)
    A_[i].Write(os, binary);
  WriteToken(os, binary, "<PsiInv>");  
  KALDI_ASSERT(size == static_cast<int32>(Psi_inv_.size()));
  for (int32 i = 0; i < size; i++)
    Psi_inv_[i].Write(os, binary);
  WriteToken(os, binary, "<IvectorOffset>");
  WriteBasicType(os, binary, prior_offset_);
  WriteToken(os, binary, "</IvectorExtractor3>");
}

void IvectorExtractor::Read(std::istream &is, bool binary, const bool read_derived /* = false */) {
  ExpectToken(is, binary, "<IvectorExtractor3>");
  opts_.Read(is, binary);
  int token = PeekToken(is, binary);
  if (token == 'l') {
    ExpectToken(is, binary, "<lambda>");
    ReadBasicType(is, binary, &lambda_);
  } else {
    lambda_ = 1.0;
  }
  ExpectToken(is, binary, "<mu>");
  mu_.Read(is, binary);
  int32 num_gauss = mu_.NumRows();
  int32 feat_dim = mu_.NumCols();
  ExpectToken(is, binary, "<w_vec>");
  w_vec_.Read(is, binary);
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
  ExpectToken(is, binary, "<IvectorOffset>");
  ReadBasicType(is, binary, &prior_offset_);
  ExpectToken(is, binary, "</IvectorExtractor3>");

  ComputeDerivedVariables();
}

int32 IvectorExtractor::NumParams() const {
  int32 num_params = SupervectorDim() + NumGauss() * FeatDim() * IvectorDim();
  if (opts_.diagonal_variance) {
    num_params += SupervectorDim();
  } else {    // block diagonal
    num_params += NumGauss() * FeatDim() * FeatDim();
  }
  return num_params;
}

std::string IvectorExtractor::Info() const {
  std::ostringstream ostr;
  ostr << "num-gauss " << NumGauss() << std::endl;
  ostr << "feat-dim " << FeatDim() << std::endl;
  ostr << "supervec-dim " << SupervectorDim() << std::endl;
  ostr << "ivector-dim " << IvectorDim() << std::endl;
  ostr << "number-of-parameters " << static_cast<float>(NumParams())/1e6
       << " millions" << std::endl;
  ostr << "prior mode? " << PriorMode() << std::endl;
  if (PriorMode())
    ostr << "prior-offset " << prior_offset_ << std::endl;
  else
    ostr << "mu_" << MomentStatistics(mu_) << std::endl;

  ostr << "lambda " << lambda_ << std::endl;

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
