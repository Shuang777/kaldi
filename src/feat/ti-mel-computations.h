// feat/ti-mel-computations.h

// Copyright 2009-2011  Phonexia s.r.o.;  Microsoft Corporation

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

#ifndef KALDI_FEAT_TI_MEL_COMPUTATIONS_H_
#define KALDI_FEAT_TI_MEL_COMPUTATIONS_H_

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <complex>
#include <utility>
#include <vector>

#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "matrix/matrix-lib.h"


namespace kaldi {
/// @addtogroup  feat FeatureExtraction
/// @{

struct FrameExtractionOptions;  // defined in feature-function.h

struct TiMelBanksOptions;  // defined in feature-function.h

class TiMelBanks {
 public:
  TiMelBanks();
  TiMelBanks(const TiMelBanksOptions &opts,
           const FrameExtractionOptions &frame_opts,
           BaseFloat vtln_warp_factor);

  void InitGivenBins();
  int32 NumBins (const FrameExtractionOptions &frame_opts, const TiMelBanksOptions &opts);
  /// Compute Mel energies (note: not log enerties).
  /// At input, "fft_energies" contains the FFT energies (not log).
  void Compute(const VectorBase<BaseFloat> &fft_energies,
               Vector<BaseFloat> *ti_mel_energies_out) const;

  int32 NumBins() const { return bins_.size(); }

 private:
  // center frequencies of bins, numbered from 0 ... num_bins-1.
  // Needed by GetCenterFreqs().
  std::vector<BaseFloat> center_freqs_;

  // the "bins_" vector is a vector, one for each bin, of a pair:
  // (the first nonzero fft-bin), (the vector of weights).
  std::vector<std::pair<int32, Vector<BaseFloat> > > bins_;
  
  typedef std::pair<BaseFloat, BaseFloat> FloatPair;
  std::vector<FloatPair> given_bins_;

  bool htk_mode_;
};


/// @} End of "addtogroup feat"
}  // namespace kaldi

#endif  // KALDI_FEAT_TI_MEL_COMPUTATIONS_H_
