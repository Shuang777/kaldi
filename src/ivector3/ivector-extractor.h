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

#ifndef KALDI_IVECTOR3_IVECTOR_EXTRACTOR_H_
#define KALDI_IVECTOR3_IVECTOR_EXTRACTOR_H_

#include "base/kaldi-common.h"
#include "gmm/model-common.h"
#include "gmm/diag-gmm.h"
#include "gmm/full-gmm.h"
#include "matrix/matrix-lib.h"
#include "itf/options-itf.h"
#include "util/common-utils.h"
#include "hmm/posterior.h"

namespace kaldi {
namespace ivector3{

class IvectorExtractorUtteranceStats {
  friend class IvectorExtractor;
  friend class IvectorExtractorStats;
 public:
  IvectorExtractorUtteranceStats() {}
  IvectorExtractorUtteranceStats(int32 num_gauss, int32 feat_dim, bool need_2nd_order_stats);

  void AccStats(const MatrixBase<BaseFloat> &feats,
                const Posterior &post, 
                const std::vector<bool> selected_parts = std::vector<bool>());
  
  void Reset(int32 num_gauss, int32 feat_dim, bool need_2nd_order_stats);

 protected:
  Vector<double> gamma_; // zeroth-order stats (summed posteriors), dimension [I]
  Matrix<double> X_; // first-order stats, dimension [I][D]
  std::vector< SpMatrix< double > >   S_; // second order statistics [I][D][D]
};

struct IvectorExtractorOptions {
  int ivector_dim;
  bool diagonal_variance;
  bool prior_mode;
  IvectorExtractorOptions(): ivector_dim(400), diagonal_variance(false), prior_mode(true) { }
  void Register(OptionsItf *po) {
    po->Register("ivector-dim", &ivector_dim, "Dimension of iVector");
    po->Register("diagonal-variance", &diagonal_variance, "Restrict variance to be diagonal");
    po->Register("prior-mode", &prior_mode, "Use baked-in prior as Kaldi or not");
  }
  void Write(std::ostream &os, bool binary) const {
    WriteToken(os, binary, "<DiagonalVariance>");
    WriteBasicType(os, binary, diagonal_variance);
    WriteToken(os, binary, "<PriorMode>");
    WriteBasicType(os, binary, prior_mode);
  }
  void Read(std::istream &is, bool binary) {
    ExpectToken(is, binary, "<DiagonalVariance>");
    ReadBasicType(is, binary, &diagonal_variance);
    ExpectToken(is, binary, "<PriorMode>");
    ReadBasicType(is, binary, &prior_mode);
  }
};

struct IvectorExtractorEstimationOptions {
  bool update_variance;
  double variance_floor_factor;
  bool floor_iv2;
  bool update_prior;
  double gaussian_min_count; 
  bool diagonalize;
  int32 num_threads;
  IvectorExtractorEstimationOptions(): update_variance(true), variance_floor_factor(0.1), 
         floor_iv2(false), update_prior(false), gaussian_min_count(100.0), diagonalize(true) { }
  void Register(OptionsItf *po) {
    po->Register("update-variance", &update_variance, "Update variance of noise term");
    po->Register("diagonalize", &diagonalize, "diagonalizes the quadratic term.");
    po->Register("variance-floor-factor", &variance_floor_factor, "Factor that determines variance flooring (we floor each covar to this times global average covariance");
    po->Register("floor-iv2", &floor_iv2, "Floor the matrix for transformation estimation");
    po->Register("update-prior", & update_prior, "Update transformation matrix like is done in Kaldi default update prior function");
    po->Register("gaussian-min-count", &gaussian_min_count,
                   "Minimum total count per Gaussian, below which we refuse to "
                   "update any associated parameters.");
  }
};

class IvectorExtractor;

class IvectorExtractorStats {
 public:
  friend class IvectorExtractor;

  IvectorExtractorStats() {};

  IvectorExtractorStats(const IvectorExtractor& extractor);
  
  void AccStatsForUtterance(const IvectorExtractor &extractor, const MatrixBase<BaseFloat> &feats, 
                            const Posterior &post);
  
  void Write(std::ostream &os, bool binary) const;

  void Read(std::istream &is, bool binary, bool add = false) ;

  void Update(IvectorExtractor &extractor, const IvectorExtractorEstimationOptions &update_opts);

  double GetAuxfValue(const IvectorExtractor &extractor) const;

  double GetAuxfValueIvectorPrior(const IvectorExtractor &extractor) const;

  double GetAuxfValueLikelihood(const IvectorExtractor &extractor) const;
  
  void GetOrthogonalIvectorTransform(const SubMatrix<double> &T, IvectorExtractor &extractor, Matrix<double> *A) const;

  void UpdateProjection(const IvectorExtractorEstimationOptions &update_opts, 
                        int32 i, IvectorExtractor *extractor) const;

  void UpdateProjections(const IvectorExtractorEstimationOptions &opts, IvectorExtractor &extractor) const;

 private:
  std::vector<Matrix<double> > gamma_supV_iV_;
  Matrix<double> gamma_iV_iV_;
  std::vector<SpMatrix<double> > gamma_supV_supV_;
  Vector<double> sum_iV_;
  SpMatrix<double> iV_iV_;
  Vector<double> gamma_;
  double num_ivectors_;
};

class IvectorExtractor {
 public:
  friend class IvectorExtractorStats;

  IvectorExtractor() :  prior_offset_(0.0) { }

  IvectorExtractor(const IvectorExtractorOptions &opts, const IvectorExtractorUtteranceStats &stats);

  IvectorExtractor(const IvectorExtractorOptions &opts, const FullGmm &fgmm);

  int32 FeatDim() const {  return A_.front().NumRows(); }

  int32 IvectorDim() const {  return A_.front().NumCols(); }

  int32 NumGauss() const {  return A_.size(); }

  int32 SupervectorDim() const { return mu_.NumCols() * mu_.NumRows(); }

  void Write(std::ostream &os, bool binary, const bool write_derived = false) const;

  void Read(std::istream &is, bool binary, const bool read_derived = false) ;

  void GetIvectorDistribution(const IvectorExtractorUtteranceStats &stats, VectorBase<double> *mean,
                              SpMatrix< double > *var = NULL, MatrixBase<double> * normalized_gammasup = NULL, 
                              double *auxf = NULL, bool for_scoring = false) const;

  double ComputeAuxf(const IvectorExtractorUtteranceStats &stats, const VectorBase<double> &mean,
                     const SpMatrix<double> &quadratic, const MatrixBase<double> &normalized_gammasup) const;

  void TransformIvectors(const MatrixBase< double > & T);

  void ComputeDerivedVariables();

  void SetPriorOffset(double new_prior_offset) { prior_offset_ = new_prior_offset; }

  std::string Info() const;

  int32 NumParams() const;

  bool PriorMode() const { return opts_.prior_mode; }

  double PriorOffset() const { return prior_offset_; }

  double GetPsiLogDet(int32 k) const { return -Psi_inv_[k].LogDet(); }

private:
  IvectorExtractorOptions opts_;

  Vector< double >  w_vec_;   // Gaussian mixture weights from the UBM.
  Matrix<double> mu_;
  double prior_offset_;

  Vector<double>  gconsts_;

  std::vector<Matrix<double> > A_;
  std::vector<SpMatrix<double> > Psi_inv_;

  // derived values
  std::vector<Matrix<double> > Psi_inv_A_;
  Matrix<double> AT_Psi_inv_A_;     // each row is the covariance mat of a component
};


}  // namespace ivector3
}  // namespace kaldi

#endif
