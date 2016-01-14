// feat/zero-crossing-functions.cc
//
// Copyright    2015  Hang Su
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
// limitations under the License

namespace kaldi {

void ComputeZeroCrossing(const VectorBase<BaseFloat> &wave,
                         Matrix<BaseFloat> *output) {

  int32 rows_out = NumFrames(wave.Dim(), opts_.frame_opts),
        cols_out = 1;

  output->Resize(rows_out, cols_out);
  if (wave_remainder != NULL)
    ExtractWaveformRemainder(wave, opts_.frame_opts, wave_remainder);
  Vector<BaseFloat> window;  // windowed waveform.
  for (int32 r = 0; r < rows_out; r++) {  // r is frame index..
    ExtractWindow(wave, r, opts_.frame_opts, feature_window_function_, &window,
                  (opts_.use_energy && opts_.raw_energy ? &log_energy : NULL));

  }


}

}
