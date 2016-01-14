// feat/feature-mfcc.h

// Copyright 2009-2011  Karel Vesely;  Petr Motlicek;  Saarland University

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

#ifndef KALDI_FEAT_FEATURE_TI_MFCC_H_
#define KALDI_FEAT_FEATURE_TI_MFCC_H_

#include <map>
#include <string>

#include "feat/feature-functions.h"

namespace kaldi {
/// @addtogroup  feat FeatureExtraction
/// @{


/// MfccOptions contains basic options for computing MFCC features
/// It only includes things that can be done in a "stateless" way, i.e.
/// it does not include energy max-normalization.
/// It does not include delta computation.
struct TiMfccOptions {
  FrameExtractionOptions frame_opts;
  TiMelBanksOptions mel_opts;
  bool use_energy;  // use energy; else C0
  BaseFloat energy_floor;
  bool raw_energy;  // If true, compute energy before preemphasis and windowing
  BaseFloat cepstral_lifter;  // Scaling factor on cepstra for HTK compatibility.
                              // if 0.0, no liftering is done.
  bool htk_compat;  // if true, put energy/C0 last and introduce a factor of
                    // sqrt(2) on C0 to be the same as HTK.
  int32 num_ceps;
  bool use_zc1;
  bool use_zc2;
  
  typedef std::pair<BaseFloat, BaseFloat> FreqBand;

  std::vector<FreqBand> freq_bands;

  TiMfccOptions() : mel_opts(),
                  use_energy(true),
                  energy_floor(0.0),  // not in log scale: a small value e.g. 1.0e-10
                  raw_energy(true),
                  cepstral_lifter(22.0),
                  htk_compat(false),
                  use_zc1(false),
                  use_zc2(false) {
    
    freq_bands.push_back(FreqBand(0, 0));
  }

  TiMfccOptions(const TiMfccOptions & other) : 
                  frame_opts(other.frame_opts),
                  mel_opts(other.mel_opts),
                  use_energy(other.use_energy),
                  energy_floor(other.energy_floor),
                  raw_energy(other.raw_energy),
                  cepstral_lifter(other.cepstral_lifter),
                  htk_compat(other.htk_compat),
                  use_zc1(other.use_zc1),
                  use_zc2(other.use_zc2),
                  freq_bands(other.freq_bands) {

    TiMelBanks tmpTiMelBanks;
    num_ceps = tmpTiMelBanks.NumBins(frame_opts, mel_opts);
  }

  void Register(OptionsItf *po) {
    frame_opts.Register(po);
    mel_opts.Register(po);
    po->Register("use-zc1", &use_zc1,
                 "First Zero crossing rate.");
    po->Register("use-zc2", &use_zc2,
                 "Second zero crossing rate across 0 to 12000");
    po->Register("use-energy", &use_energy,
                 "Use energy (not C0) in MFCC computation");
    po->Register("energy-floor", &energy_floor,
                 "Floor on energy (absolute, not relative) in MFCC computation");
    po->Register("raw-energy", &raw_energy,
                 "If true, compute energy before preemphasis and windowing");
    po->Register("cepstral-lifter", &cepstral_lifter,
                 "Constant that controls scaling of MFCCs");
    po->Register("htk-compat", &htk_compat,
                 "If true, put energy or C0 last and use a factor of sqrt(2) on "
                 "C0.  Warning: not sufficient to get HTK compatible features "
                 "(need to change other parameters).");
  }

  int32 GetNumCeps() const {
    TiMelBanks tmpTiMelBanks;
    return tmpTiMelBanks.NumBins(frame_opts, mel_opts);
  }
};

class TiMelBanks;


/// Class for computing MFCC features; see \ref feat_mfcc for more information.
class TiMfcc {
 public:
  explicit TiMfcc(const TiMfccOptions &opts);
  ~TiMfcc();

  int32 Dim() const { return opts_.num_ceps; }

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
  
  typedef TiMfccOptions Options;
 private:
  
  BaseFloat CountCrossZero(const VectorBase<BaseFloat> &wave) const;
  
  typedef std::pair<BaseFloat, BaseFloat> FreqBand;

  void FilterBands(Vector<BaseFloat> &wave, const FreqBand & freq_band) const;

  void ComputeInternal(const VectorBase<BaseFloat> &wave,
                       const TiMelBanks &mel_banks,
                       Matrix<BaseFloat> *output,
                       Vector<BaseFloat> *wave_remainder = NULL) const;
  
  const TiMelBanks *GetTiMelBanks(BaseFloat vtln_warp);

  const TiMelBanks *GetTiMelBanks(BaseFloat vtln_warp,
                              bool *must_delete) const;
  
  TiMfccOptions opts_;
  Vector<BaseFloat> lifter_coeffs_;
  Matrix<BaseFloat> dct_matrix_;  // matrix we left-multiply by to perform DCT.
  BaseFloat log_energy_floor_;
  std::map<BaseFloat, TiMelBanks*> mel_banks_;  // BaseFloat is VTLN coefficient.
  FeatureWindowFunction feature_window_function_;
  SplitRadixRealFft<BaseFloat> *srfft_;
  KALDI_DISALLOW_COPY_AND_ASSIGN(TiMfcc);
};


/// @} End of "addtogroup feat"
}  // namespace kaldi


#endif  // KALDI_FEAT_FEATURE_TI_MFCC_H_
