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

  void GetSupervector(Vector<double> & supervector);

 protected:
  Vector<double> gamma_; // zeroth-order stats (summed posteriors), dimension [I]
  Matrix<double> X_; // first-order stats, dimension [I][D]
};

struct IvectorExtractorOptions {
  int ivector_dim;
  bool diagonal_variance;
  IvectorExtractorOptions(): ivector_dim(400), diagonal_variance(true) { }
  void Register(OptionsItf *po) {
    po->Register("ivector-dim", &ivector_dim, "Dimension of iVector");
    po->Register("diagonal-variance", &diagonal_variance, "Restrict variance to be diagonal");
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
  
  void AccStats(const VectorBase<double> &feats);

 private: 
  Vector<double> sum_acc;
  std::vector<SpMatrix<double> > scatter;
  int32 num_samples;
};

class IvectorExtractor {
 public:
  friend class IvectorExtractorInitStats;
  friend class IvectorExtractorStats;

  IvectorExtractor() {}

  IvectorExtractor(const IvectorExtractorOptions &opts, int32 feat_dim, int32 num_gauss);
  
  IvectorExtractor(const IvectorExtractorOptions &opts, const IvectorExtractorInitStats &stats);

  int32 FeatDim() const {  return A_.front().NumRows(); }

  int32 IvectorDim() const {  return A_.front().NumCols(); }

  int32 NumGauss() const {  return A_.size(); }

  int32 SupervectorDim() const { return mu_.Dim(); }

  void Write(std::ostream &os, bool binary, const bool write_derived = false) const;

  void Read(std::istream &is, bool binary, const bool read_derived = false) ;

  void GetIvectorDistribution(const VectorBase<double> &supervector, VectorBase<double> *mean, 
                              VectorBase<double> *normalized_supvervector = NULL, double *auxf = NULL) const;

  void TransformIvectors(const MatrixBase< double > & T);

  void ComputeDerivedValues();

  std::string Info();

  int32 NumParams();

private:
  IvectorExtractorOptions opts_;

  Vector<double> mu_;
  double prior_offset_;

  std::vector<Matrix<double> > A_;
  std::vector<SpMatrix<double> > Psi_inv_;

  // derived values
  std::vector<Matrix<double> > Psi_inv_A_;
  SpMatrix<double> Var_;
};

struct IvectorExtractorEstimationOptions {
  bool update_variance;
  double variance_floor_factor;
  bool floor_iv2;
  bool update_prior;
  IvectorExtractorEstimationOptions(): update_variance(true), variance_floor_factor(0), 
         floor_iv2(false), update_prior(false) { }
  void Register(OptionsItf *po) {
    po->Register("update-variance", &update_variance, "Update variance of noise term");
    po->Register("variance-floor-factor", &variance_floor_factor, "Factor that determines variance flooring (we floor each covar to this times global average covariance");
    po->Register("floor-iv2", &floor_iv2, "Floor the matrix for transformation estimation");
    po->Register("update-prior", & update_prior, "Update transformation matrix like is done in Kaldi default update prior function");
  }
};

class IvectorExtractorStats {
 public:
  friend class IvectorExtractor;

  IvectorExtractorStats() {};

  IvectorExtractorStats(const IvectorExtractor& extractor);
  
  void AccStatsForUtterance(const IvectorExtractor &extractor, const VectorBase<double> &supervector);
  
  void Write(std::ostream &os, bool binary) const;

  void Read(std::istream &is, bool binary, bool add = false) ;

  void Update(IvectorExtractor &extractor, const IvectorExtractorEstimationOptions &update_opts);

  double GetAuxfValue(const IvectorExtractor &extractor) const;

 private:
  std::vector<Matrix<double> > supV_iV_;
  SpMatrix<double> iV_iV_;
  std::vector<SpMatrix<double> > supV_supV_;
  Vector<double> sum_iV_;
  double num_ivectors_;
};


}  // namespace ivector2
}  // namespace kaldi

#endif
