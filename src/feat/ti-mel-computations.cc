// feat/mel-computations.cc

// Copyright 2009-2011  Phonexia s.r.o.;  Karel Vesely;  Microsoft Corporation

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

#include <stdio.h>
#include <stdlib.h>
#include <float.h>
#include <algorithm>
#include <iostream>

#include "feat/ti-mel-computations.h"
#include "feat/feature-functions.h"

namespace kaldi {

TiMelBanks::TiMelBanks() {
  InitGivenBins();
}

TiMelBanks::TiMelBanks(const TiMelBanksOptions &opts,
                       const FrameExtractionOptions &frame_opts,
                       BaseFloat vtln_warp_factor):
                       htk_mode_(opts.htk_mode) {

  InitGivenBins();
  BaseFloat sample_freq = frame_opts.samp_freq;
  int32 window_length = static_cast<int32>(frame_opts.samp_freq*0.001*frame_opts.frame_length_ms);
  int32 window_length_padded =
      (frame_opts.round_to_power_of_two ?
       RoundUpToNearestPowerOfTwo(window_length) :
       window_length);
  KALDI_ASSERT(window_length_padded % 2 == 0);
  int32 num_fft_bins = window_length_padded/2;
  BaseFloat nyquist = 0.5 * sample_freq;

  BaseFloat low_freq = opts.low_freq, high_freq;
  if (opts.high_freq > 0.0)
    high_freq = opts.high_freq;
  else
    high_freq = nyquist + opts.high_freq;

  if (low_freq < 0.0 || low_freq >= nyquist
      || high_freq <= 0.0 || high_freq > nyquist
      || high_freq <= low_freq)
    KALDI_ERR << "Bad values in options: low-freq " << low_freq
              << " and high-freq " << high_freq << " vs. nyquist "
              << nyquist;
  
  BaseFloat fft_bin_width = sample_freq / window_length_padded;
  // fft-bin width [think of it as Nyquist-freq / half-window-length]

  for (int32 bin = 0; bin < given_bins_.size(); bin++) {
    BaseFloat left_freq = given_bins_[bin].first,
        right_freq = given_bins_[bin].second;

    BaseFloat center_freq = (left_freq + right_freq) / 2;

    if (left_freq < low_freq || left_freq > high_freq) {
      continue;
    }
    if (right_freq > high_freq) {
      right_freq = high_freq;
    }

    center_freqs_.push_back(center_freq);

    // this_bin will be a vector of coefficients that is only
    // nonzero where this mel bin is active.
    Vector<BaseFloat> this_bin(num_fft_bins);
    int32 first_index = -1, last_index = -1;
    for (int32 i = 0; i < num_fft_bins; i++) {
      BaseFloat freq = (fft_bin_width * i);  // center freq of this fft bin.
      if (freq > left_freq && freq < right_freq) {
        BaseFloat weight;
        if (freq <= center_freq)
          weight = (freq - left_freq) / (center_freq - left_freq);
        else
         weight = (right_freq - freq) / (right_freq-center_freq);
        this_bin(i) = weight;
        if (first_index == -1)
          first_index = i;
        last_index = i;
      }
    }
    KALDI_ASSERT(first_index != -1 && last_index >= first_index
                 && "You may have set --num-mel-bins too large.");
    
    std::pair<int32, Vector<BaseFloat> > copy_bin;
    copy_bin.first = first_index;    
    bins_.push_back(copy_bin);
    int32 size = last_index + 1 - first_index;
    bins_.back().second.Resize(size);
    bins_.back().second.CopyFromVec(this_bin.Range(first_index, size));
  }
}

void TiMelBanks::InitGivenBins() {
  given_bins_.push_back(FloatPair(0,12000));    // energy term placed at 0
  given_bins_.push_back(FloatPair(0,200));
  given_bins_.push_back(FloatPair(200,400));
  given_bins_.push_back(FloatPair(400,600));
  given_bins_.push_back(FloatPair(600,800));
  given_bins_.push_back(FloatPair(800,1000));
  given_bins_.push_back(FloatPair(1000,1200));
  given_bins_.push_back(FloatPair(1200,1500));
  given_bins_.push_back(FloatPair(1500,2250));
  given_bins_.push_back(FloatPair(2250,3000));
  given_bins_.push_back(FloatPair(3000,6000));
  given_bins_.push_back(FloatPair(6000,12000));
}

int32 TiMelBanks::NumBins(const FrameExtractionOptions &frame_opts,
                          const TiMelBanksOptions &opts) {
  BaseFloat sample_freq = frame_opts.samp_freq;
  BaseFloat nyquist = 0.5 * sample_freq;
  BaseFloat low_freq = opts.low_freq, high_freq;
  if (opts.high_freq > 0.0)
    high_freq = opts.high_freq;
  else
    high_freq = nyquist + opts.high_freq;

  int32 num_bins = 0;
  for (int32 bin = 0; bin < given_bins_.size(); bin++) {
    BaseFloat left_freq = given_bins_[bin].first;

    if (left_freq < low_freq || left_freq > high_freq) {
      continue;
    }
    num_bins++;
  }
  return num_bins;
}

// "power_spectrum" contains fft energies.
void TiMelBanks::Compute(const VectorBase<BaseFloat> &power_spectrum,
                       Vector<BaseFloat> *mel_energies_out) const {
  int32 num_bins = bins_.size();
  if (mel_energies_out->Dim() != num_bins)
    mel_energies_out->Resize(num_bins);

  for (int32 i = 0; i < num_bins; i++) {
    int32 offset = bins_[i].first;
    const Vector<BaseFloat> &v(bins_[i].second);
    BaseFloat energy = VecVec(v, power_spectrum.Range(offset, v.Dim()));
    // HTK-like flooring- for testing purposes (we prefer dither)
    if (htk_mode_ && energy < 1.0) energy = 1.0; 
    (*mel_energies_out)(i) = energy;
    
    // The following assert was added due to a problem with OpenBlas that
    // we had at one point (it was a bug in that library).  Just to detect
    // it early.
    KALDI_ASSERT(!KALDI_ISNAN((*mel_energies_out)(i)));
  }

}

}  // namespace kaldi
