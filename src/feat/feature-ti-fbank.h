// feat/feature-fbank.h

// Copyright 2009-2012  Karel Vesely

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

#ifndef KALDI_FEAT_FEATURE_TI_FBANK_H_
#define KALDI_FEAT_FEATURE_TI_FBANK_H_

#include<map>
#include <string>

#include "feat/feature-functions.h"

namespace kaldi {
/// @addtogroup  feat FeatureExtraction
/// @{


/// TiFbankOptions contains basic options for computing FBANK features
/// It only includes things that can be done in a "stateless" way, i.e.
/// it does not include energy max-normalization.
/// It does not include delta computation.
struct TiFbankOptions {
  FrameExtractionOptions frame_opts;
  TiMelBanksOptions mel_opts;
  bool use_energy;  // append an extra dimension with energy to the filter banks
  BaseFloat energy_floor;
  bool raw_energy;  // If true, compute energy before preemphasis and windowing
  bool htk_compat;  // If true, put energy last (if using energy)
  bool use_log_fbank;  // if true (default), produce log-filterbank, else linear
  bool use_zc1;
  bool use_zc2;
  int32 num_bins;
  
  TiFbankOptions(): use_energy(false),
                 energy_floor(0.0),  // not in log scale: a small value e.g. 1.0e-10
                 raw_energy(true),
                 htk_compat(false),
                 use_log_fbank(true),
                 use_zc1(false),
                 use_zc2(false) {}

  TiFbankOptions(const TiFbankOptions& other):
                      frame_opts(other.frame_opts),
                      mel_opts(other.mel_opts),
                      use_energy(other.use_energy),
                      energy_floor(other.energy_floor),
                      raw_energy(other.raw_energy),
                      htk_compat(other.htk_compat),
                      use_log_fbank(other.use_log_fbank),
                      use_zc1(other.use_zc1),
                      use_zc2(other.use_zc2) {
    
    TiMelBanks tmpTiMelBanks;
    num_bins = tmpTiMelBanks.NumBins(frame_opts, mel_opts);
  }

  void Register(OptionsItf *po) {
    frame_opts.Register(po);
    mel_opts.Register(po);
    po->Register("use-zc1", &use_zc1,
                 "First Zero crossing rate.");
    po->Register("use-zc2", &use_zc2,
                 "Second zero crossing rate across 0 to 12000");
    po->Register("use-energy", &use_energy,
                 "Add an extra dimension with energy to the FBANK output.");
    po->Register("raw-energy", &raw_energy,
                 "If true, compute energy before preemphasis and windowing");
    po->Register("htk-compat", &htk_compat, "If true, put energy last.  "
                 "Warning: not sufficient to get HTK compatible features (need "
                 "to change other parameters).");
    po->Register("use-log-fbank", &use_log_fbank,
                 "If true, produce log-filterbank, else produce linear.");
  }
};


class TiMelBanks;

/// Class for computing ti-mel-filterbank features; see \ref feat_mfcc for more
/// information.
class TiFbank {
 public:
  explicit TiFbank(const TiFbankOptions &opts);
  ~TiFbank();

  int32 Dim() const { return opts_.num_bins; }

  /// Will throw exception on failure (e.g. if file too short for even one
  /// frame).  The output "wave_remainder" is the last frame or two of the
  /// waveform that it would be necessary to include in the next call to Compute
  /// for the same utterance.  It is not exactly the un-processed part (it may
  /// have been partly processed), it's the start of the next window that we
  /// have not already processed.
  void Compute(const VectorBase<BaseFloat> &wave,
               BaseFloat vtln_warp,
               Matrix<BaseFloat> *output,
               Vector<BaseFloat> *wave_remainder = NULL);
  
  /// Const version of Compute()
  void Compute(const VectorBase<BaseFloat> &wave,
               BaseFloat vtln_warp,
               Matrix<BaseFloat> *output,
               Vector<BaseFloat> *wave_remainder = NULL) const;
  typedef TiFbankOptions Options;
 private:
  void ComputeInternal(const VectorBase<BaseFloat> &wave,
                       const TiMelBanks &mel_banks,
                       Matrix<BaseFloat> *output,
                       Vector<BaseFloat> *wave_remainder = NULL) const;
  
  const TiMelBanks *GetTiMelBanks(BaseFloat vtln_warp);

  const TiMelBanks *GetTiMelBanks(BaseFloat vtln_warp,
                              bool *must_delete) const;

  TiFbankOptions opts_;
  BaseFloat log_energy_floor_;
  std::map<BaseFloat, TiMelBanks*> mel_banks_;  // BaseFloat is VTLN coefficient.
  FeatureWindowFunction feature_window_function_;
  SplitRadixRealFft<BaseFloat> *srfft_;
  KALDI_DISALLOW_COPY_AND_ASSIGN(TiFbank);
};


/// @} End of "addtogroup feat"
}  // namespace kaldi


#endif  // KALDI_FEAT_FEATURE_TI_FBANK_H_
