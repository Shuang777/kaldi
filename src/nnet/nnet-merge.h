// nnet/nnet-merge.h

// Copyright 2015  International Computer Science Institute (author: Hang Su)

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


#ifndef KALDI_NNET_NNET_MERGE_H_
#define KALDI_NNET_NNET_MERGE_H_

#include "nnet/nnet-component.h"
#include "cudamatrix/cu-math.h"
#include "cudamatrix/cu-rand.h"
#include "util/text-utils.h"

namespace kaldi {
namespace nnet1 {

class BlockAddComponent : public Component {
 public:
  BlockAddComponent (int32 dim_in, int32 dim_out) 
    : Component(dim_in, dim_out)
  { }
  ~BlockAddComponent()
  { }

  Component* Copy() const { return new BlockAddComponent(*this); }
  ComponentType GetType() const { return kBlockAddComponent; }

  void PropagateFnc(const CuMatrixBase<BaseFloat> &in, CuMatrixBase<BaseFloat> *out) {
    out->CopyFromMat(in);
  }
  
  void PropagateFnc(const std::vector<std::vector<CuMatrix<BaseFloat> > > &in, CuMatrixBase<BaseFloat> *out) {
    for (int32 i=0; i<in.size(); i++) {
      out->AddMat(1.0, in[i].back());
    }
  }

  void BackpropagateFnc(const CuMatrixBase<BaseFloat> &in, const CuMatrixBase<BaseFloat> &out,
                        const CuMatrixBase<BaseFloat> &out_diff, CuMatrixBase<BaseFloat> *in_diff) {
    in_diff->CopyFromMat(out_diff);
  }

  void BackpropagateFnc(const std::vector<std::vector<CuMatrix<BaseFloat> > > &in,
                        const CuMatrixBase<BaseFloat> &out,
                        const CuMatrixBase<BaseFloat> &out_diff,
                        std::vector<std::vector<CuMatrix<BaseFloat> > > &in_diff) {
    for (int32 i=0; i<in.size(); i++) {
      in_diff[i].back().AddMat(1.0, out_diff);
    }
  }
};


} // namespace nnet1
} // namespace kaldi

#endif
