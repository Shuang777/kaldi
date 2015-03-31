// nnet/nnet-multi-nnet.cc

// Copyright 2015  International Computer Science Institute (Author: Hang Su)

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

#include "nnet/nnet-multi-nnet.h"
#include "nnet/nnet-component.h"
//#include "nnet/nnet-parallel-component.h"
#include "nnet/nnet-activation.h"
#include "nnet/nnet-affine-transform.h"
#include "nnet/nnet-various.h"


namespace kaldi {
namespace nnet1 {


MultiNnet::MultiNnet(const MultiNnet& other) {
  Copy(other);
}

void MultiNnet::Copy (const MultiNnet& other) {
  // copy the in_subnnet components
  for(int32 i=0; i<other.NumInSubNnets(); i++) {
    std::vector<Component*> in_sub_nnet_components_;
    for(int32 j=0; j<other.NumInSubNnetComponents(); j++) {
      in_sub_nnet_components_.push_back(other.GetInSubNnetComponent(i,j).Copy());
    }
    in_sub_nnets_components_.push_back(in_sub_nnet_components_);
  }

  merge_component_ = other.GetMergeComponent().Copy();
  
  // create empty buffers for subnnet
  for(int32 i=0; i<other.NumInSubNnets(); i++) {
    std::vector<CuMatrix<BaseFloat> > in_sub_nnet_propagate_buf_;
    in_sub_nnet_propagate_buf_.resize(NumInSubNnetComponents()+1);
    in_sub_nnets_propagate_buf_.push_back(in_sub_nnet_propagate_buf_);
    
    std::vector<CuMatrix<BaseFloat> > in_sub_nnet_backpropagate_buf_;
    in_sub_nnet_backpropagate_buf_.resize(NumInSubNnetComponents()+1);
    in_sub_nnets_backpropagate_buf_.push_back(in_sub_nnet_backpropagate_buf_);
  }

  // copy the shared components
  for(int32 i=0; i<other.NumSharedComponents(); i++) {
    shared_components_.push_back(other.GetSharedComponent(i).Copy());
  }
  // create empty buffers
  shared_propagate_buf_.resize(NumSharedComponents()+1);
  shared_backpropagate_buf_.resize(NumSharedComponents()+1);
  // copy train opts
  SetTrainOptions(other.opts_);

  // copy the subnnet components
  for(int32 i=0; i<other.NumSubNnets(); i++) {
    std::vector<Component*> sub_nnet_components_;
    for(int32 j=0; j<other.NumSubNnetComponents(); j++) {
      sub_nnet_components_.push_back(other.GetSubNnetComponent(i,j).Copy());
    }
    sub_nnets_components_.push_back(sub_nnet_components_);
  }

  // create empty buffers for subnnet
  for(int32 i=0; i<other.NumSubNnets(); i++) {
    std::vector<CuMatrix<BaseFloat> > sub_nnet_propagate_buf_;
    sub_nnet_propagate_buf_.resize(NumSubNnetComponents()+1);
    sub_nnets_propagate_buf_.push_back(sub_nnet_propagate_buf_);
    
    std::vector<CuMatrix<BaseFloat> > sub_nnet_backpropagate_buf_;
    sub_nnet_backpropagate_buf_.resize(NumSubNnetComponents()+1);
    sub_nnets_backpropagate_buf_.push_back(sub_nnet_backpropagate_buf_);
  }

  Check();
}

MultiNnet & MultiNnet::operator = (const MultiNnet& other) {
  Destroy();
  Copy(other);
  return *this;
}


MultiNnet::~MultiNnet() {
  Destroy();
}

void MultiNnet::Propagate(const CuMatrixBase<BaseFloat> &in, std::vector<CuMatrix<BaseFloat> *> &out) {
  for (int32 i=0; i<out.size(); i++) {
    KALDI_ASSERT(NULL != out[i]);
  }

  // we need at least L+1 input buffers
  KALDI_ASSERT((int32)shared_propagate_buf_.size() >= NumSharedComponents()+1);
  
  KALDI_ASSERT (NumInSubNnets() == 0);
  shared_propagate_buf_[0].Resize(in.NumRows(), in.NumCols());
  shared_propagate_buf_[0].CopyFromMat(in);

  for(int32 i=0; i<NumSharedComponents(); i++) {
    shared_components_[i]->Propagate(shared_propagate_buf_[i], &shared_propagate_buf_[i+1]);
  }
  if (NumSubNnets() == 0) {
    out.resize(1);
    out[0] = &shared_propagate_buf_.back();
  } else {
    out.resize(NumSubNnets());
    for(int32 i=0; i<NumSubNnets(); i++) {
      sub_nnets_propagate_buf_[i][0] = shared_propagate_buf_[NumSharedComponents()];
      for(int32 j=0; j<NumSubNnetComponents();j++) {
        sub_nnets_components_[i][j]->Propagate(sub_nnets_propagate_buf_[i][j], &sub_nnets_propagate_buf_[i][j+1]);
      }
      out[i] = &sub_nnets_propagate_buf_[i][NumSubNnetComponents()];
    }
  }
}

void MultiNnet::Propagate(const std::vector<const CuMatrixBase<BaseFloat> *> &in, std::vector<CuMatrix<BaseFloat> *> &out) {
  for (int32 i=0; i<out.size(); i++) {
    KALDI_ASSERT(NULL != out[i]);
  }
  KALDI_ASSERT(in.size() > 0);
  if (NumInSubNnets() != 0) {
    KALDI_ASSERT(in.size() == NumInSubNnets());
  } else {
    KALDI_ASSERT(in.size() == 1);
  }

  // we need at least L+1 input buffers
  KALDI_ASSERT((int32)shared_propagate_buf_.size() >= NumSharedComponents()+1);
  
  KALDI_ASSERT (NumInSubNnets() == in.size());
  if (NumInSubNnets() > 0) {
    shared_propagate_buf_[0].Resize(in[0]->NumRows(), in_sub_nnets_components_[0].back()->OutputDim());
    for(int32 i=0; i<NumInSubNnets(); i++) {
      in_sub_nnets_propagate_buf_[i][0] = *in[i];
      for(int32 j=0; j<NumInSubNnetComponents(); j++) {
        in_sub_nnets_components_[i][j]->Propagate(in_sub_nnets_propagate_buf_[i][j], &in_sub_nnets_propagate_buf_[i][j+1]);
      }
    }
    merge_component_->Propagate(in_sub_nnets_propagate_buf_, &shared_propagate_buf_[0]);
  } else {
    shared_propagate_buf_[0] = *in[0];
  }

  if (NumSharedComponents() > 0) {
    for(int32 i=0; i<NumSharedComponents(); i++) {
      shared_components_[i]->Propagate(shared_propagate_buf_[i], &shared_propagate_buf_[i+1]);
    }
  }

  if (NumSubNnets() == 0) {
    out.resize(1);
    out[0] = &shared_propagate_buf_.back();
  } else {
    out.resize(NumSubNnets());
    for(int32 i=0; i<NumSubNnets(); i++) {
      sub_nnets_propagate_buf_[i][0] = shared_propagate_buf_[NumSharedComponents()];
      for(int32 j=0; j<NumSubNnetComponents();j++) {
        sub_nnets_components_[i][j]->Propagate(sub_nnets_propagate_buf_[i][j], &sub_nnets_propagate_buf_[i][j+1]);
      }
      out[i] = &sub_nnets_propagate_buf_[i][NumSubNnetComponents()];
    }
  }
}

void MultiNnet::Backpropagate(const std::vector<CuMatrix<BaseFloat> *> &out_diff, CuMatrix<BaseFloat> *in_diff) {
  //////////////////////////////////////
  // Backpropagation
  //
  KALDI_ASSERT((int32)shared_propagate_buf_.size() == NumSharedComponents()+1);
  KALDI_ASSERT((int32)shared_backpropagate_buf_.size() == NumSharedComponents()+1);
  KALDI_ASSERT(out_diff.size() > 0);
  shared_backpropagate_buf_.back().Resize(out_diff[0]->NumRows(), SharedOutputDims(), kSetZero);
  for(int32 i=0; i<NumSubNnets(); i++) {
    // copy out_diff to last buffer
    sub_nnets_backpropagate_buf_[i][NumSubNnetComponents()] = (*out_diff[i]);
    // backpropagate using buffers
    for(int32 j=NumSubNnetComponents()-1; j>=0; j--) {
      sub_nnets_components_[i][j]->Backpropagate(sub_nnets_propagate_buf_[i][j], sub_nnets_propagate_buf_[i][j+1],
      sub_nnets_backpropagate_buf_[i][j+1], &sub_nnets_backpropagate_buf_[i][j]);
      if (sub_nnets_components_[i][j]->IsUpdatable()) {
        UpdatableComponent *uc = dynamic_cast<UpdatableComponent*>(sub_nnets_components_[i][j]);
        uc->Update(sub_nnets_propagate_buf_[i][j], sub_nnets_backpropagate_buf_[i][j+1]);
      }
    }
    shared_backpropagate_buf_.back().AddMat(1.0, sub_nnets_backpropagate_buf_[i].front(), kNoTrans);
  }
  // backpropagate through shared layers
  for (int32 i = NumSharedComponents()-1; i >= 0; i--) {
    shared_components_[i]->Backpropagate(shared_propagate_buf_[i], shared_propagate_buf_[i+1],
    shared_backpropagate_buf_[i+1], &shared_backpropagate_buf_[i]);
    if (shared_components_[i]->IsUpdatable()) {
      UpdatableComponent *uc = dynamic_cast<UpdatableComponent*>(shared_components_[i]);
      uc->Update(shared_propagate_buf_[i], shared_backpropagate_buf_[i+1]);
    }
  }
  // eventually export the derivative
  if (NULL != in_diff) (*in_diff) = shared_backpropagate_buf_[0];
  //
  // End of Backpropagation
  //////////////////////////////////////
}

void MultiNnet::Backpropagate(const std::vector<CuMatrix<BaseFloat> *> &out_diff, std::vector<CuMatrix<BaseFloat> *> &in_diff) {

  //////////////////////////////////////
  // Backpropagation
  //

  KALDI_ASSERT((int32)shared_propagate_buf_.size() == NumSharedComponents()+1);
  KALDI_ASSERT((int32)shared_backpropagate_buf_.size() == NumSharedComponents()+1);

  KALDI_ASSERT(out_diff.size() > 0);

  shared_backpropagate_buf_.back().Resize(out_diff[0]->NumRows(), SharedOutputDims(), kSetZero);

  for(int32 i=0; i<NumSubNnets(); i++) {
    // copy out_diff to last buffer
    sub_nnets_backpropagate_buf_[i][NumSubNnetComponents()] = (*out_diff[i]);
    // backpropagate using buffers
    for(int32 j=NumSubNnetComponents()-1; j>=0; j--) {
      sub_nnets_components_[i][j]->Backpropagate(sub_nnets_propagate_buf_[i][j], sub_nnets_propagate_buf_[i][j+1],
                                    sub_nnets_backpropagate_buf_[i][j+1], &sub_nnets_backpropagate_buf_[i][j]);
      if (sub_nnets_components_[i][j]->IsUpdatable()) {
        UpdatableComponent *uc = dynamic_cast<UpdatableComponent*>(sub_nnets_components_[i][j]);
        uc->Update(sub_nnets_propagate_buf_[i][j], sub_nnets_backpropagate_buf_[i][j+1]);
      }
    }
    shared_backpropagate_buf_.back().AddMat(1.0, sub_nnets_backpropagate_buf_[i].front(), kNoTrans);
  }
  if (NumSubNnets() == 0) {
    shared_backpropagate_buf_.back() = *out_diff[0];
  }
  // backpropagate through shared layers
  for (int32 i = NumSharedComponents()-1; i >= 0; i--) {
    shared_components_[i]->Backpropagate(shared_propagate_buf_[i], shared_propagate_buf_[i+1],
                            shared_backpropagate_buf_[i+1], &shared_backpropagate_buf_[i]);
    if (shared_components_[i]->IsUpdatable()) {
      UpdatableComponent *uc = dynamic_cast<UpdatableComponent*>(shared_components_[i]);
      uc->Update(shared_propagate_buf_[i], shared_backpropagate_buf_[i+1]);
    }
  }
  
  if (merge_component_ != NULL) {
    merge_component_->Backpropagate(in_sub_nnets_propagate_buf_, shared_propagate_buf_[0],
                                    shared_backpropagate_buf_[0], in_sub_nnets_backpropagate_buf_);
  }

  for(int32 i=0; i<NumInSubNnets(); i++) {
    // backpropagate using buffers
    for(int32 j=NumInSubNnetComponents()-1; j>=0; j--) {
      in_sub_nnets_components_[i][j]->Backpropagate(in_sub_nnets_propagate_buf_[i][j], in_sub_nnets_propagate_buf_[i][j+1],
                                    in_sub_nnets_backpropagate_buf_[i][j+1], &in_sub_nnets_backpropagate_buf_[i][j]);
      if (in_sub_nnets_components_[i][j]->IsUpdatable()) {
        UpdatableComponent *uc = dynamic_cast<UpdatableComponent*>(in_sub_nnets_components_[i][j]);
        uc->Update(in_sub_nnets_propagate_buf_[i][j], in_sub_nnets_backpropagate_buf_[i][j+1]);
      }
    }
  }

  if (in_diff.size() != 0) {
    for (int32 i=0; i<NumInSubNnetComponents(); i++){
      if (NULL != in_diff[i]) {
        (*in_diff[i]) = in_sub_nnets_backpropagate_buf_[i][0];
      }
    }
  }

  //
  // End of Backpropagation
  //////////////////////////////////////
}

void MultiNnet::Feedforward(const CuMatrixBase<BaseFloat> &in, const int32 subnnet_id, CuMatrix<BaseFloat> *out) {
  KALDI_ASSERT(NULL != out);

  if (NumSharedComponents() == 0 && NumSubNnetComponents() == 0) { 
    out->Resize(in.NumRows(), in.NumCols());
    out->CopyFromMat(in); 
    return; 
  }

  // we need at least 2 input buffers
  KALDI_ASSERT(shared_propagate_buf_.size() >= 2);

  // propagate by using exactly 2 auxiliary buffers
  int32 L = 0;
  shared_components_[L]->Propagate(in, &shared_propagate_buf_[L%2]);
  for(L++; L<=NumSharedComponents()-2; L++) {
    shared_components_[L]->Propagate(shared_propagate_buf_[(L-1)%2], &shared_propagate_buf_[L%2]);
  }
  if (NumSubNnetComponents() == 0) {
    shared_components_[L]->Propagate(shared_propagate_buf_[(L-1)%2], out);
  } else {
    KALDI_ASSERT(subnnet_id < NumSubNnets());
    shared_components_[L]->Propagate(shared_propagate_buf_[(L-1)%2], &shared_propagate_buf_[L%2]);
    for(L++; L<=NumSharedComponents()+NumSubNnetComponents()-2; L++) {
      sub_nnets_components_[subnnet_id][L-NumSharedComponents()]->Propagate(shared_propagate_buf_[(L-1)%2], &shared_propagate_buf_[L%2]);
    }
    sub_nnets_components_[subnnet_id][L-NumSharedComponents()]->Propagate(shared_propagate_buf_[(L-1)%2], out);
  }

  // release the buffers we don't need anymore
  shared_propagate_buf_[0].Resize(0,0);
  shared_propagate_buf_[1].Resize(0,0);

}

void MultiNnet::Feedforward(const std::vector<CuMatrix<BaseFloat> *> &in, const int32 subnnet_id, 
                            CuMatrix<BaseFloat> *out) {
  KALDI_ASSERT(NULL != out);
  KALDI_ASSERT(in.size() > 0);
  if (NumInSubNnets() != 0) {
    KALDI_ASSERT(in.size() == NumInSubNnets());
  } else {
    KALDI_ASSERT(in.size() == 1);
  }

  // we need 2 input buffers for shared components
  shared_propagate_buf_.resize(2);

  // propagate by using exactly 2 auxiliary buffers and in_sub_nnets_propagate_buf_ for in subnnet layers
  if (NumInSubNnets() > 0) {
    // we need at least 2 input buffers for subnnets
    for(int32 i=0; i<NumInSubNnets(); i++) {
      shared_propagate_buf_[0] = *in[i];
      int32 j = 0;
      for(; j<NumInSubNnetComponents()-1; j++) {
        in_sub_nnets_components_[i][j]->Propagate(shared_propagate_buf_[j%2], &shared_propagate_buf_[(j+1)%2]);
      }
      in_sub_nnets_components_[i][j]->Propagate(shared_propagate_buf_[j%2], &in_sub_nnets_propagate_buf_[i].back());
    }
    merge_component_->Propagate(in_sub_nnets_propagate_buf_, &shared_propagate_buf_[0]);
  } else {
    shared_propagate_buf_[0] = *in[0];
  }
  
  // propagate by using exactly 2 auxiliary buffers for shared layers
  if (NumSharedComponents() > 0) {
    int32 L = 0;
    for(; L<NumSharedComponents(); L++) {
      shared_components_[L]->Propagate(shared_propagate_buf_[L%2], &shared_propagate_buf_[(L+1)%2]);
    }
    shared_propagate_buf_[0] = shared_propagate_buf_[L%2];
  }
  
  // finally, for sub nnet components
  if (NumSubNnetComponents() > 0) {
    KALDI_ASSERT(subnnet_id < NumSubNnets());
    int32 L = 0;
    for(; L<NumSubNnetComponents()-1; L++) {
      sub_nnets_components_[subnnet_id][L]->Propagate(shared_propagate_buf_[L%2], &shared_propagate_buf_[(L+1)%2]);
    }
    sub_nnets_components_[subnnet_id][L]->Propagate(shared_propagate_buf_[L%2], out);
  } else {
    out->Resize(shared_propagate_buf_[0].NumRows(), shared_propagate_buf_[0].NumCols());
    out->CopyFromMat(shared_propagate_buf_[0]);
  }

  // release the buffers we don't need anymore
  shared_propagate_buf_[0].Resize(0,0);
  shared_propagate_buf_[1].Resize(0,0);
  shared_propagate_buf_.resize(shared_components_.size()+1);
}

int32 MultiNnet::SharedInputDims() const {
  KALDI_ASSERT(!shared_components_.empty());
  return shared_components_.front()->InputDim();
}

int32 MultiNnet::SharedOutputDims() const {
  KALDI_ASSERT(!shared_components_.empty());
  return shared_components_.back()->OutputDim();
}

std::vector<int32> MultiNnet::InputDims() const {
  std::vector<int32> inputs;
  KALDI_ASSERT(!in_sub_nnets_components_.empty());
  for(int32 i=0; i<NumInSubNnets(); i++) {
    inputs.push_back(in_sub_nnets_components_[i].front()->InputDim());
  }
  return inputs;
}

std::vector<int32> MultiNnet::OutputDims() const {
  std::vector<int32> outputs;
  KALDI_ASSERT(!sub_nnets_components_.empty());
  for(int32 i=0; i<NumSubNnets(); i++) {
    outputs.push_back(sub_nnets_components_[i].back()->OutputDim());
  }
  return outputs;
}

const Component& MultiNnet::GetSharedComponent(int32 shared_component) const {
  KALDI_ASSERT(static_cast<size_t>(shared_component) < shared_components_.size());
  return *(shared_components_[shared_component]);
}

Component& MultiNnet::GetSharedComponent(int32 shared_component) {
  KALDI_ASSERT(static_cast<size_t>(shared_component) < shared_components_.size());
  return *(shared_components_[shared_component]);
}

const Component& MultiNnet::GetInSubNnetComponent(int32 in_sub_nnet, int32 component) const {
  KALDI_ASSERT(static_cast<size_t>(in_sub_nnet) < in_sub_nnets_components_.size());
  KALDI_ASSERT(static_cast<size_t>(component) < in_sub_nnets_components_[0].size());
  return *(in_sub_nnets_components_[in_sub_nnet][component]);
}

Component& MultiNnet::GetInSubNnetComponent(int32 in_sub_nnet, int32 component) {
  KALDI_ASSERT(static_cast<size_t>(in_sub_nnet) < in_sub_nnets_components_.size());
  KALDI_ASSERT(static_cast<size_t>(component) < in_sub_nnets_components_[0].size());
  return *(in_sub_nnets_components_[in_sub_nnet][component]);
}

const Component& MultiNnet::GetSubNnetComponent(int32 sub_nnet, int32 component) const {
  KALDI_ASSERT(static_cast<size_t>(sub_nnet) < sub_nnets_components_.size());
  KALDI_ASSERT(static_cast<size_t>(component) < sub_nnets_components_[0].size());
  return *(sub_nnets_components_[sub_nnet][component]);
}

Component& MultiNnet::GetSubNnetComponent(int32 sub_nnet, int32 component) {
  KALDI_ASSERT(static_cast<size_t>(sub_nnet) < sub_nnets_components_.size());
  KALDI_ASSERT(static_cast<size_t>(component) < sub_nnets_components_[0].size());
  return *(sub_nnets_components_[sub_nnet][component]);
}

const Component& MultiNnet::GetLastComponent() const {
  if (NumSubNnets() != 0) {
    return *(sub_nnets_components_.back().back());
  } else if (NumSharedComponents() != 0) {
    return *(shared_components_.back());
  } else if (merge_component_ != NULL) {
    return *merge_component_;
  } else {
    return *(in_sub_nnets_components_.back().back());
  }
}

Component& MultiNnet::GetLastComponent() {
  if (NumSubNnets() != 0) {
    return *(sub_nnets_components_.back().back());
  } else if (NumSharedComponents() != 0) {
    return *(shared_components_.back());
  } else if (merge_component_ != NULL) {
    return *merge_component_;
  } else {
    return *(in_sub_nnets_components_.back().back());
  }
}

const Component& MultiNnet::GetMergeComponent() const {
  KALDI_ASSERT(merge_component_ != NULL);
  return *merge_component_;
}

Component& MultiNnet::GetMergeComponent() {
  KALDI_ASSERT(merge_component_ != NULL);
  return *merge_component_;
}

bool MultiNnet::HasMergeComponent() const {
  return merge_component_ != NULL;
}

void MultiNnet::GetParams(Vector<BaseFloat>* wei_copy) const {
  wei_copy->Resize(NumParams());
  int32 pos = 0;
  // copy the params
  for(int32 i=0; i<NumInSubNnets(); i++) {
    for(int32 j=0; j<NumInSubNnetComponents(); j++) {
      if (in_sub_nnets_components_[i][j]->IsUpdatable()) {
        UpdatableComponent& c = dynamic_cast<UpdatableComponent&>(*in_sub_nnets_components_[i][j]);
        Vector<BaseFloat> c_params;
        c.GetParams(&c_params);
        wei_copy->Range(pos,c_params.Dim()).CopyFromVec(c_params);
        pos += c_params.Dim();
      }
    }
  }
  for(int32 i=0; i<NumSharedComponents(); i++) {
    if(shared_components_[i]->IsUpdatable()) {
      UpdatableComponent& c = dynamic_cast<UpdatableComponent&>(*shared_components_[i]);
      Vector<BaseFloat> c_params; 
      c.GetParams(&c_params);
      wei_copy->Range(pos,c_params.Dim()).CopyFromVec(c_params);
      pos += c_params.Dim();
    }
  }
  for(int32 i=0; i<NumSubNnets(); i++) {
    for(int32 j=0; j<NumSubNnetComponents(); j++) {
      if (sub_nnets_components_[i][j]->IsUpdatable()) {
        UpdatableComponent& c = dynamic_cast<UpdatableComponent&>(*sub_nnets_components_[i][j]);
        Vector<BaseFloat> c_params;
        c.GetParams(&c_params);
        wei_copy->Range(pos,c_params.Dim()).CopyFromVec(c_params);
        pos += c_params.Dim();
      }
    }
  }
  KALDI_ASSERT(pos == NumParams());
}

int32 MultiNnet::NumParams() const {
  int32 n_params = 0;
  for(int32 i=0; i<NumInSubNnets(); i++) {
    for(int32 j=0; j<NumInSubNnetComponents(); j++) {
      if(in_sub_nnets_components_[i][j]->IsUpdatable()) {
        n_params += dynamic_cast<UpdatableComponent*>(in_sub_nnets_components_[i][j])->NumParams();
      }
    }
  }
  for(int32 i=0; i<NumSharedComponents(); i++) {
    if(shared_components_[i]->IsUpdatable()) {
      n_params += dynamic_cast<UpdatableComponent*>(shared_components_[i])->NumParams();
    }
  }
  for(int32 i=0; i<NumSubNnets(); i++) {
    for(int32 j=0; j<NumSubNnetComponents(); j++) {
      if(sub_nnets_components_[i][j]->IsUpdatable()) {
        n_params += dynamic_cast<UpdatableComponent*>(sub_nnets_components_[i][j])->NumParams();
      }
    }
  }
  return n_params;
}

void MultiNnet::AppendSharedComponent(Component* dynamically_allocated_comp) {
  // append,
  shared_components_.push_back(dynamically_allocated_comp);
  // create training buffers,
  shared_propagate_buf_.resize(NumSharedComponents()+1);
  shared_backpropagate_buf_.resize(NumSharedComponents()+1);
  //
  Check();
}

void MultiNnet::RemoveSharedComponent(int32 component) {
  KALDI_ASSERT(component < NumSharedComponents());
  // remove,
  Component* ptr = shared_components_[component];
  shared_components_.erase(shared_components_.begin()+component);
  delete ptr;
  // create training buffers,
  shared_propagate_buf_.resize(NumSharedComponents()+1);
  shared_backpropagate_buf_.resize(NumSharedComponents()+1);
  // 
  Check();
}

void MultiNnet::RemoveSubNnetComponent(int32 component) {
  KALDI_ASSERT(component < NumSubNnetComponents());
  // remove,
  for(int32 i=0; i<NumSubNnets(); i++) {
    Component* ptr = sub_nnets_components_[i][component];
    sub_nnets_components_.erase(sub_nnets_components_.begin()+component);
    delete ptr;
    // create training buffers,
    sub_nnets_propagate_buf_.resize(NumSubNnetComponents()+1);
    sub_nnets_backpropagate_buf_.resize(NumSubNnetComponents()+1);
  }
  // 
  Check();
}

void MultiNnet::RemoveLastSoftmax() {
  if (NumSubNnets() != 0) {
    for (int32 i=0; i<NumSubNnets(); i++) {
      KALDI_ASSERT(sub_nnets_components_[i].back()->GetType() == kaldi::nnet1::Component::kSoftmax);
    }
    RemoveSubNnetComponent(NumSubNnetComponents()-1);
  } else if (NumSharedComponents() != 0) {
    KALDI_ASSERT(shared_components_.back()->GetType() == kaldi::nnet1::Component::kSoftmax);
    RemoveSharedComponent(NumSharedComponents()-1);
  } else {
    KALDI_ERR << "Please check if the top layer is softmax before removing last softmax";
  }
}

void MultiNnet::AddInSubNnet(const Nnet& nnet_to_add) {
  std::vector<Component*> in_sub_nnet_components_;
  for(int32 i=0; i<nnet_to_add.NumComponents(); i++) {
    in_sub_nnet_components_.push_back(nnet_to_add.GetComponent(i).Copy());
  }
  in_sub_nnets_components_.push_back(in_sub_nnet_components_);
  // create training buffers,
  std::vector<CuMatrix<BaseFloat> > in_sub_nnet_propagate_buf_;
  in_sub_nnet_propagate_buf_.resize(in_sub_nnet_components_.size()+1);
  in_sub_nnets_propagate_buf_.push_back(in_sub_nnet_propagate_buf_);

  std::vector<CuMatrix<BaseFloat> > in_sub_nnet_backpropagate_buf_;
  in_sub_nnet_backpropagate_buf_.resize(in_sub_nnet_components_.size()+1);
  in_sub_nnets_backpropagate_buf_.push_back(in_sub_nnet_backpropagate_buf_);
  
  Check();
}

void MultiNnet::AddSubNnet(const Nnet& nnet_to_add) {
  std::vector<Component*> sub_nnet_components_;
  for(int32 i=0; i<nnet_to_add.NumComponents(); i++) {
    sub_nnet_components_.push_back(nnet_to_add.GetComponent(i).Copy());
  }
  sub_nnets_components_.push_back(sub_nnet_components_);
  // create training buffers,
  std::vector<CuMatrix<BaseFloat> > sub_nnet_propagate_buf_;
  sub_nnet_propagate_buf_.resize(sub_nnet_components_.size()+1);
  sub_nnets_propagate_buf_.push_back(sub_nnet_propagate_buf_);

  std::vector<CuMatrix<BaseFloat> > sub_nnet_backpropagate_buf_;
  sub_nnet_backpropagate_buf_.resize(sub_nnet_components_.size()+1);
  sub_nnets_backpropagate_buf_.push_back(sub_nnet_backpropagate_buf_);
  
  Check();
}

void MultiNnet::Split(int32 c) {
  int32 num_shared_components = NumSharedComponents();
  int32 num_subnnets = NumSubNnets();

  KALDI_ASSERT(c <= num_shared_components);

  for (int32 i=0; i<c; i++) {
    for (int32 j=0; j<num_subnnets-1; j++) {
      sub_nnets_components_[j].insert(sub_nnets_components_[j].begin(), shared_components_[num_shared_components-1-i]->Copy());
    }
    if (num_subnnets >= 1) {
      sub_nnets_components_[num_subnnets-1].insert(sub_nnets_components_[num_subnnets-1].begin(), shared_components_[num_shared_components-1-i]);
    } else {
      sub_nnets_components_.resize(1);
      sub_nnets_components_[0].insert(sub_nnets_components_[0].begin(), shared_components_[num_shared_components-1-i]);
    }
  }
  shared_components_.resize(num_shared_components-c);
  shared_propagate_buf_.resize(shared_components_.size()+1);
  shared_backpropagate_buf_.resize(shared_components_.size()+1);
  
  for (int32 i=0; i<sub_nnets_components_.size(); i++){
    sub_nnets_propagate_buf_[i].resize(sub_nnets_components_[i].size()+1);
    sub_nnets_backpropagate_buf_[i].resize(sub_nnets_components_[i].size()+1);
  }
  Check();
}

void MultiNnet::SplitFront(int32 c) {
  int32 num_shared_components = NumSharedComponents();
  int32 num_in_subnnets = NumInSubNnets();

  KALDI_ASSERT(c <= num_shared_components);

  for (int32 i=0; i<c; i++) {
    for (int32 j=0; j<num_in_subnnets-1; j++) {
      in_sub_nnets_components_[j].push_back(shared_components_[i]->Copy());
    }
    if (num_in_subnnets >= 1) {
      in_sub_nnets_components_[num_in_subnnets-1].push_back(shared_components_[i]);
    } else {
      in_sub_nnets_components_.resize(1);
      in_sub_nnets_components_[0].push_back(shared_components_[i]);
    }
  }
  shared_components_.erase(shared_components_.begin(), shared_components_.begin()+c);
  shared_propagate_buf_.resize(shared_components_.size()+1);
  shared_backpropagate_buf_.resize(shared_components_.size()+1);
  
  for (int32 i=0; i<in_sub_nnets_components_.size(); i++){
    in_sub_nnets_propagate_buf_[i].resize(in_sub_nnets_components_[i].size()+1);
    in_sub_nnets_backpropagate_buf_[i].resize(in_sub_nnets_components_[i].size()+1);
  }
  Check();
}

void MultiNnet::SetDropoutRetention(BaseFloat r)  {
  for (int32 i=0; i<NumInSubNnets(); i++) {
    for (int32 c=0; c<NumInSubNnetComponents(); c++) {
      if (GetInSubNnetComponent(i,c).GetType() == Component::kDropout) {
        Dropout& comp = dynamic_cast<Dropout&>(GetInSubNnetComponent(i,c));
        BaseFloat r_old = comp.GetDropoutRetention();
        comp.SetDropoutRetention(r);
        KALDI_LOG << "Setting dropout-retention in subnnet " << i << " component " << c
                  << " from " << r_old << " to " << r;
      }
    }
  }
  for (int32 c=0; c < NumSharedComponents(); c++) {
    if (GetSharedComponent(c).GetType() == Component::kDropout) {
      Dropout& comp = dynamic_cast<Dropout&>(GetSharedComponent(c));
      BaseFloat r_old = comp.GetDropoutRetention();
      comp.SetDropoutRetention(r);
      KALDI_LOG << "Setting dropout-retention in shared component " << c 
                << " from " << r_old << " to " << r;
    }
  }
  for (int32 i=0; i<NumSubNnets(); i++) {
    for (int32 c=0; c<NumSubNnetComponents(); c++) {
      if (GetSubNnetComponent(i,c).GetType() == Component::kDropout) {
        Dropout& comp = dynamic_cast<Dropout&>(GetSubNnetComponent(i,c));
        BaseFloat r_old = comp.GetDropoutRetention();
        comp.SetDropoutRetention(r);
        KALDI_LOG << "Setting dropout-retention in subnnet " << i << " component " << c
                  << " from " << r_old << " to " << r;
      }
    }
  }
}

void MultiNnet::Init(const std::string &file) {
  Input in(file);
  std::istream &is = in.Stream();
  ExpectToken(is, false, "<MultiNnetProto>");
  // do the initialization with config lines
  std::string conf_line;
  std::string conf_line_detail;
  const bool binary = false;
  ReadToken(is, binary, &conf_line);
  if (conf_line == "<InSubNnetComponents>") {
    while (conf_line != "</MultiNnetProto>" && conf_line != "<SharedComponents>" && conf_line != "<SubNnetComponents>") {
      ReadToken(is, binary, &conf_line);
      std::vector<Component*> in_sub_nnet_components_;
      while (conf_line != "</InSubNnetComponents>") {
        KALDI_VLOG(1) << conf_line; 
        std::getline(is, conf_line_detail); // get the line in config file
        in_sub_nnet_components_.push_back(Component::Init(conf_line+" "+conf_line_detail+"\n"));
        ReadToken(is, binary, &conf_line);
      }
      in_sub_nnets_components_.push_back(in_sub_nnet_components_);

      std::vector<CuMatrix<BaseFloat> > in_sub_nnet_propagate_buf_;
      in_sub_nnet_propagate_buf_.resize(in_sub_nnet_components_.size()+1);
      in_sub_nnets_propagate_buf_.push_back(in_sub_nnet_propagate_buf_);
    
      std::vector<CuMatrix<BaseFloat> > in_sub_nnet_backpropagate_buf_;
      in_sub_nnet_backpropagate_buf_.resize(in_sub_nnet_components_.size()+1);
      in_sub_nnets_backpropagate_buf_.push_back(in_sub_nnet_backpropagate_buf_);

      ReadToken(is, binary, &conf_line);
    }
  }
  if (conf_line == "<MergeComponent>") {
    ReadToken(is, binary, &conf_line);
    KALDI_VLOG(1) << conf_line;
    std::getline(is, conf_line_detail);
    merge_component_ = Component::Init(conf_line+" "+conf_line_detail+"\n");
    ReadToken(is, binary, &conf_line);
    KALDI_ASSERT(conf_line == "</MergeComponent>");
  }
  if (conf_line == "<SharedComponents>") {
    ReadToken(is, binary, &conf_line);
    while (conf_line != "</SharedComponents>") {
      KALDI_VLOG(1) << conf_line;
      std::getline(is, conf_line_detail); // get the line in config file
      AppendSharedComponent(Component::Init(conf_line+" "+conf_line_detail+"\n"));
      ReadToken(is, binary, &conf_line);
    }
    ReadToken(is, binary, &conf_line);
  }
  // just to ensure those are resized when there is no shared components
  shared_propagate_buf_.resize(NumSharedComponents()+1);
  shared_backpropagate_buf_.resize(NumSharedComponents()+1);
  if (conf_line == "<SubNnetComponents>") {
    while (conf_line != "</MultiNnetProto>") {
      ReadToken(is, binary, &conf_line);
      std::vector<Component*> sub_nnet_components_;
      while (conf_line != "</SubNnetComponents>") {
        KALDI_VLOG(1) << conf_line; 
        std::getline(is, conf_line_detail); // get the line in config file
        sub_nnet_components_.push_back(Component::Init(conf_line+" "+conf_line_detail+"\n"));
        ReadToken(is, binary, &conf_line);
      }
      sub_nnets_components_.push_back(sub_nnet_components_);

      std::vector<CuMatrix<BaseFloat> > sub_nnet_propagate_buf_;
      sub_nnet_propagate_buf_.resize(sub_nnet_components_.size()+1);
      sub_nnets_propagate_buf_.push_back(sub_nnet_propagate_buf_);
    
      std::vector<CuMatrix<BaseFloat> > sub_nnet_backpropagate_buf_;
      sub_nnet_backpropagate_buf_.resize(sub_nnet_components_.size()+1);
      sub_nnets_backpropagate_buf_.push_back(sub_nnet_backpropagate_buf_);

      ReadToken(is, binary, &conf_line);
    }
  }
  if (conf_line != "</MultiNnetProto>") {
    KALDI_ERR << "Missing </MultiNnetProto> at the end.";
  }
  KALDI_ASSERT(is.good());
  // cleanup
  in.Close();
  Check();
}

void MultiNnet::Read(const std::string &file) {
  bool binary;
  Input in(file, &binary);
  const bool is_nnet = false;   // false because it is multi_nnet here
  Read(in.Stream(), binary, is_nnet);
  in.Close();
  // Warn if the NN is empty
  if(NumInSubNnetComponents() == 0) {
    KALDI_WARN << "The network '" << file << "' has empty in-subnnet components.";
  }
  if(NumSharedComponents() == 0) {
    KALDI_WARN << "The network '" << file << "' has empty shared components.";
  }
  if(NumSubNnetComponents() == 0) {
    KALDI_WARN << "The network '" << file << "' has empty subnnet components.";
  }
}

void MultiNnet::Read(std::istream &is, bool binary, const bool is_nnet /*= false*/) {
  // get the network layers from a factory
  std::string token;
  ReadToken(is, binary, &token);
  std::string str2match = is_nnet ? "<Nnet>" : "<MultiNnet>";   // we also support reading nnet as shared nnet directly
  if(token != str2match) {
    ExpectToken(is, false, str2match);
    return;
  }
  Component *comp;
  if (!is_nnet) {
    ReadToken(is, binary, &token);
    while (!is.eof() && token != "</MultiNnet>" && token != "<SharedComponents>" && token != "<SubNnetComponents>"
        && token != "<MergeComponent>") {
      // token is InSubNnetComponents
      std::vector<Component*> in_sub_nnet_components_;
      while (NULL != (comp = Component::Read(is, binary))) {
        in_sub_nnet_components_.push_back(comp);
      }
      in_sub_nnets_components_.push_back(in_sub_nnet_components_);

      // create empty in subnnet buffers
      std::vector<CuMatrix<BaseFloat> > in_sub_nnet_propagate_buf_;
      in_sub_nnet_propagate_buf_.resize(NumInSubNnetComponents()+1);
      in_sub_nnets_propagate_buf_.push_back(in_sub_nnet_propagate_buf_);
      
      std::vector<CuMatrix<BaseFloat> > in_sub_nnet_backpropagate_buf_;
      in_sub_nnet_backpropagate_buf_.resize(NumInSubNnetComponents()+1);
      in_sub_nnets_backpropagate_buf_.push_back(in_sub_nnet_backpropagate_buf_);

      ReadToken(is, binary, &token);
    }
    if (token == "<MergeComponent>") {
      merge_component_ = Component::Read(is, binary);
      ReadToken(is, binary, &token);
      KALDI_ASSERT(token == "</MergeComponent>");
      ReadToken(is, binary, &token);
    }
  }
  if (is_nnet || token == "<SharedComponents>" ) {
    while (NULL != (comp = Component::Read(is, binary))) {
      shared_components_.push_back(comp);
    }
  }
  // create empty shared buffers
  shared_propagate_buf_.resize(NumSharedComponents()+1);
  shared_backpropagate_buf_.resize(NumSharedComponents()+1);

  if (!is_nnet && !is.eof()) {   // for multi-nnet part
    int first_char = Peek(is, binary);
    if (first_char != EOF) {
      ReadToken(is, binary, &token);
      while (!is.eof() && token != "</MultiNnet>") {
        // token is SubNnetComponents
        std::vector<Component*> sub_nnet_components_;
        while (NULL != (comp = Component::Read(is, binary))) {
          sub_nnet_components_.push_back(comp);
        }
        sub_nnets_components_.push_back(sub_nnet_components_);

        // create empty subnnet buffers
        std::vector<CuMatrix<BaseFloat> > sub_nnet_propagate_buf_;
        sub_nnet_propagate_buf_.resize(NumSubNnetComponents()+1);
        sub_nnets_propagate_buf_.push_back(sub_nnet_propagate_buf_);
        
        std::vector<CuMatrix<BaseFloat> > sub_nnet_backpropagate_buf_;
        sub_nnet_backpropagate_buf_.resize(NumSubNnetComponents()+1);
        sub_nnets_backpropagate_buf_.push_back(sub_nnet_backpropagate_buf_);

        ReadToken(is, binary, &token);
      }
      if (token != "</MultiNnet>") {
        KALDI_ERR << "Missing </MultiNnet> at the end.";
      }
    }
  }
  // reset learn rate
  opts_.learn_rate = 0.0;

  Check(); //check consistency (dims...)
}

void MultiNnet::ReadSharedNnet(const std::string &file) {
  bool binary;
  Input in(file, &binary);
  const bool is_nnet = true;
  Read(in.Stream(), binary, is_nnet);
  in.Close();
  // Warn if the NN is empty
  if(NumSharedComponents() == 0) {
    KALDI_WARN << "The network '" << file << "' is empty.";
  }
}

void MultiNnet::ReadSharedNnet(std::istream &is, bool binary) {
  const bool is_nnet = true;
  Read(is, binary, is_nnet);
}

void MultiNnet::Write(const std::string &file, bool binary) const {
  Output out(file, binary, true);
  Write(out.Stream(), binary);
  out.Close();
}

void MultiNnet::Write(std::ostream &os, bool binary) const {
  Check();
  WriteToken(os, binary, "<MultiNnet>");
  if(binary == false) os << std::endl;

  for(int32 i=0; i<NumInSubNnets(); i++) {
    WriteToken(os, binary, "<InSubNnetComponents>");
    if(binary == false) os << std::endl;
    for(int32 j=0; j<NumInSubNnetComponents(); j++) {
      in_sub_nnets_components_[i][j]->Write(os, binary);
    }
    WriteToken(os, binary, "</InSubNnetComponents>");
    if(binary == false) os << std::endl;
  }
  if (merge_component_ != NULL) {
    WriteToken(os, binary, "<MergeComponent>");
    if(binary == false) os << std::endl;
    merge_component_->Write(os, binary);
    WriteToken(os, binary, "</MergeComponent>");
    if(binary == false) os << std::endl;
  }

  WriteToken(os, binary, "<SharedComponents>");
  if(binary == false) os << std::endl;
  for(int32 i=0; i<NumSharedComponents(); i++) {
    shared_components_[i]->Write(os, binary);
  }
  WriteToken(os, binary, "</SharedComponents>");
  if(binary == false) os << std::endl;

  for(int32 i=0; i<NumSubNnets(); i++) {
    WriteToken(os, binary, "<SubNnetComponents>");
    if(binary == false) os << std::endl;
    for(int32 j=0; j<NumSubNnetComponents(); j++) {
      sub_nnets_components_[i][j]->Write(os, binary);
    }
    WriteToken(os, binary, "</SubNnetComponents>");
    if(binary == false) os << std::endl;
  }

  WriteToken(os, binary, "</MultiNnet>");  
  if(binary == false) os << std::endl;
}

void MultiNnet::WriteNnet(const std::string &file, bool binary, const int32 in_subnnet /* = -1 */, 
                          const int32 subnnet /* = -1 */) const {
  Output out(file, binary, true);
  WriteNnet(out.Stream(), binary, in_subnnet, subnnet);
  out.Close();
}

void MultiNnet::WriteNnet(std::ostream &os, bool binary, const int32 in_subnnet /* = -1 */, 
                          const int32 subnnet /* = -1 */) const {
  Check();
  KALDI_ASSERT(subnnet >= 0 && subnnet < NumSubNnets());
  WriteToken(os, binary, "<Nnet>");
  if(binary == false) os << std::endl;
  if (in_subnnet != -1) {
    for(int32 j=0; j<NumSubNnetComponents(); j++){
      in_sub_nnets_components_[in_subnnet][j]->Write(os, binary);
    }
    KALDI_ERR << "Think about how to handle MergeComponent!" ;
  }
  for(int32 i=0; i<NumSharedComponents(); i++) {
    shared_components_[i]->Write(os, binary);
  }
  if (subnnet != -1) {
    for(int32 j=0; j<NumSubNnetComponents(); j++) {
      sub_nnets_components_[subnnet][j]->Write(os, binary);
    }
  }
  WriteToken(os, binary, "</Nnet>");  
  if(binary == false) os << std::endl;
}

void MultiNnet::WriteInSubNnet(const std::string &file, bool binary, const int32 in_subnnet) const {
  Output out(file, binary, true);
  WriteNnet(out.Stream(), binary, in_subnnet);
  out.Close();
}

void MultiNnet::WriteInSubNnet(std::ostream &os, bool binary, const int32 in_subnnet) const {
  WriteNnet(os, binary, in_subnnet);
}

void MultiNnet::WriteSubNnet(const std::string &file, bool binary, const int32 subnnet) const {
  Output out(file, binary, true);
  WriteNnet(out.Stream(), binary, -1 /*no in subnnet*/, subnnet);
  out.Close();
}

void MultiNnet::WriteSubNnet(std::ostream &os, bool binary, const int32 subnnet) const {
  WriteNnet(os, binary, -1 /*no in subnnet*/, subnnet);
}

std::string MultiNnet::Info() const {
  // global info
  std::ostringstream ostr;
  ostr << "num-in-subnnets " << NumInSubNnets() << std::endl;
  if (NumInSubNnets() != 0) {
    std::vector<int32> input_dims = InputDims();
    for(int32 i=0; i<input_dims.size(); i++) {
      ostr << "in subnnet " << i+1 << " input-dim " << input_dims[i] << std::endl;
    }
  }

  ostr << "num-shared-components " << NumSharedComponents() << std::endl;
  if (NumSharedComponents() != 0) {
    ostr << "input-dim " << SharedInputDims() << std::endl;
    ostr << "output-dim " << SharedOutputDims() << std::endl;
  }
  
  ostr << "num-subnnets " << NumSubNnets() << std::endl;
  if (NumSubNnets() != 0) {
    std::vector<int32> output_dims = OutputDims();
    for(int32 i=0; i<output_dims.size(); i++) {
      ostr << "subnnet " << i+1 << " output-dim " << output_dims[i] << std::endl;
    }
  }
  ostr << "number-of-parameters " << static_cast<float>(NumParams())/1e6 
       << " millions" << std::endl;
  
  // topology & weight stats
  for (int32 i=0; i<NumInSubNnets(); i++) {
    ostr << "in subnnet " << i+1 << " : " << std::endl;
    for (int32 j=0; j<NumInSubNnetComponents(); j++) {
      ostr << "in subnnet component " << j+1 << " : "
           << Component::TypeToMarker(in_sub_nnets_components_[i][j]->GetType())
           << ", input-dim " << in_sub_nnets_components_[i][j]->InputDim()
           << ", output-dim " << in_sub_nnets_components_[i][j]->OutputDim()
           << ", " << in_sub_nnets_components_[i][j]->Info() << std::endl;
    }
  }
  for (int32 i=0; i<NumSharedComponents(); i++) {
    ostr << "shared component " << i+1 << " : " 
         << Component::TypeToMarker(shared_components_[i]->GetType()) 
         << ", input-dim " << shared_components_[i]->InputDim()
         << ", output-dim " << shared_components_[i]->OutputDim()
         << ", " << shared_components_[i]->Info() << std::endl;
  }
  for (int32 i=0; i<NumSubNnets(); i++) {
    ostr << "subnnet " << i+1 << " : " << std::endl;
    for (int32 j=0; j<NumSubNnetComponents(); j++) {
      ostr << "subnnet component " << j+1 << " : "
           << Component::TypeToMarker(sub_nnets_components_[i][j]->GetType())
           << ", input-dim " << sub_nnets_components_[i][j]->InputDim()
           << ", output-dim " << sub_nnets_components_[i][j]->OutputDim()
           << ", " << sub_nnets_components_[i][j]->Info() << std::endl;
    }
  }

  return ostr.str();
}

std::string MultiNnet::InfoGradient() const {
  std::ostringstream ostr;
  // gradient stats
  ostr << "### Gradient stats :\n";
  for (int32 i=0; i<NumInSubNnets(); i++) {
    ostr << "in subnnet " << i+1 << " : " << std::endl;
    for (int32 j=0; j<NumInSubNnetComponents(); j++) {
      ostr << "in sub component " << j+1 << " : "
           << Component::TypeToMarker(in_sub_nnets_components_[i][j]->GetType())
           << ", " << in_sub_nnets_components_[i][j]->InfoGradient() << std::endl;
    }
  }
  for (int32 i=0; i<NumSharedComponents(); i++) {
    ostr << "shared component " << i+1 << " : " 
         << Component::TypeToMarker(shared_components_[i]->GetType()) 
         << ", " << shared_components_[i]->InfoGradient() << std::endl;
  }
  for (int32 i=0; i<NumSubNnets(); i++) {
    ostr << "subnnet " << i+1 << " : " << std::endl;
    for (int32 j=0; j<NumSubNnetComponents(); j++) {
      ostr << "sub component " << j+1 << " : "
           << Component::TypeToMarker(sub_nnets_components_[i][j]->GetType())
           << ", " << sub_nnets_components_[i][j]->InfoGradient() << std::endl;
    }
  }

  return ostr.str();
}

std::string MultiNnet::InfoPropagate() const {
  std::ostringstream ostr;
  // forward-pass buffer stats
  ostr << "### Forward propagation buffer content :\n";
  for (int32 i=0; i<NumInSubNnets(); i++) {
    ostr << "in subnnet " << i+1 << " : " << std::endl;
    for (int32 j=0; j<NumInSubNnetComponents(); j++) {
      ostr << "["<<1+j<< "] output of " 
           << Component::TypeToMarker(in_sub_nnets_components_[i][j]->GetType())
           << MomentStatistics(in_sub_nnets_propagate_buf_[i][j+1]) << std::endl;
    }
  }
  ostr << "[0] output of <Input> " << MomentStatistics(shared_propagate_buf_[0]) << std::endl;
  for (int32 i=0; i<NumSharedComponents(); i++) {
    ostr << "["<<1+i<< "] output of " 
         << Component::TypeToMarker(shared_components_[i]->GetType())
         << MomentStatistics(shared_propagate_buf_[i+1]) << std::endl;
  }
  for (int32 i=0; i<NumSubNnets(); i++) {
    ostr << "subnnet " << i+1 << " : " << std::endl;
    for (int32 j=0; j<NumSubNnetComponents(); j++) {
      ostr << "["<<1+j<< "] output of " 
           << Component::TypeToMarker(sub_nnets_components_[i][j]->GetType())
           << MomentStatistics(sub_nnets_propagate_buf_[i][j+1]) << std::endl;
    }
  }
  
  return ostr.str();
}

std::string MultiNnet::InfoBackPropagate() const {
  std::ostringstream ostr;
  // forward-pass buffer stats
  ostr << "### Backward propagation buffer content :\n";
  for (int32 i=0; i<NumInSubNnets(); i++) {
    ostr << "in subnnet " << i+1 << " : " << std::endl;
    for (int32 j=0; j<NumInSubNnetComponents(); j++) {
      ostr << "["<<1+j<< "] diff-output of " 
           << Component::TypeToMarker(in_sub_nnets_components_[i][j]->GetType())
           << MomentStatistics(in_sub_nnets_backpropagate_buf_[i][j+1]) << std::endl;
    }
  }
  ostr << "[0] diff of <Input> " << MomentStatistics(shared_backpropagate_buf_[0]) << std::endl;
  for (int32 i=0; i<NumSharedComponents(); i++) {
    ostr << "["<<1+i<< "] diff-output of " 
         << Component::TypeToMarker(shared_components_[i]->GetType())
         << MomentStatistics(shared_backpropagate_buf_[i+1]) << std::endl;
  }
  for (int32 i=0; i<NumSubNnets(); i++) {
    ostr << "subnnet " << i+1 << " : " << std::endl;
    for (int32 j=0; j<NumSubNnetComponents(); j++) {
      ostr << "["<<1+j<< "] diff-output of " 
           << Component::TypeToMarker(sub_nnets_components_[i][j]->GetType())
           << MomentStatistics(sub_nnets_backpropagate_buf_[i][j+1]) << std::endl;
    }
  }

  return ostr.str();
}

void MultiNnet::Check() const {
  // check we have correct number of buffers,
  KALDI_ASSERT(in_sub_nnets_propagate_buf_.size() == NumInSubNnets());
  for(int32 i=0; i<NumInSubNnets(); i++) {
    KALDI_ASSERT(in_sub_nnets_propagate_buf_[i].size() == NumInSubNnetComponents()+1);
  }
  KALDI_ASSERT(in_sub_nnets_backpropagate_buf_.size() == NumInSubNnets());
  for(int32 i=0; i<NumInSubNnets(); i++) {
    KALDI_ASSERT(in_sub_nnets_backpropagate_buf_[i].size() == NumInSubNnetComponents()+1);
  }
  KALDI_ASSERT(shared_propagate_buf_.size() == NumSharedComponents()+1);
  KALDI_ASSERT(shared_backpropagate_buf_.size() == NumSharedComponents()+1);
  
  KALDI_ASSERT(sub_nnets_propagate_buf_.size() == NumSubNnets());
  for(int32 i=0; i<NumSubNnets(); i++) {
    KALDI_ASSERT(sub_nnets_propagate_buf_[i].size() == NumSubNnetComponents()+1);
  }
  KALDI_ASSERT(sub_nnets_backpropagate_buf_.size() == NumSubNnets());
  for(int32 i=0; i<NumSubNnets(); i++) {
    KALDI_ASSERT(sub_nnets_backpropagate_buf_[i].size() == NumSubNnetComponents()+1);
  }
  KALDI_ASSERT((NumInSubNnets() == 0) == (merge_component_ == NULL));    // if there is in_sub_nnet, we need a merge component.

  // check dims,
  int32 sum_in_sub_nnets_output_dim = 0;
  for(int32 i=0; i<NumInSubNnets(); i++) {
    for(int32 j=0; j+1<NumInSubNnetComponents(); j++) {
      KALDI_ASSERT(in_sub_nnets_components_[i][j] != NULL);
      int32 output_dim = in_sub_nnets_components_[i][j]->OutputDim();
      int32 next_input_dim = in_sub_nnets_components_[i][j+1]->InputDim();
      KALDI_ASSERT(output_dim == next_input_dim);
    }  
    // ensure all outdim are of same dim
    if (i != 0){
      int32 output_dim = in_sub_nnets_components_[i].back()->OutputDim();
      int32 first_output_dim = in_sub_nnets_components_[0].back()->OutputDim();
      KALDI_ASSERT(output_dim == first_output_dim);
    }
    sum_in_sub_nnets_output_dim += in_sub_nnets_components_[i].back()->OutputDim();
  }
  if (NumInSubNnets() > 0) {
    int32 input_dim = merge_component_->InputDim();
    KALDI_ASSERT(input_dim == sum_in_sub_nnets_output_dim);

    int32 output_dim = merge_component_->OutputDim();
    if (NumSharedComponents() > 0) {
      int32 next_input_dim = shared_components_.front()->InputDim();
      KALDI_ASSERT(output_dim == next_input_dim);
    } else if (NumSubNnets() > 0) {
      int32 next_input_dim = sub_nnets_components_[0].front()->InputDim();
      KALDI_ASSERT(output_dim == next_input_dim);
    }
  }

  for(int32 i=0; i+1<NumSharedComponents(); i++) {
    KALDI_ASSERT(shared_components_[i] != NULL);
    int32 output_dim = shared_components_[i]->OutputDim();
    int32 next_input_dim = shared_components_[i+1]->InputDim();
    KALDI_ASSERT(output_dim == next_input_dim);
  }

  for(int32 i=0; i<NumSubNnets(); i++) {
    for(int32 j=0; j+1<NumSubNnetComponents(); j++) {
      KALDI_ASSERT(sub_nnets_components_[i][j] != NULL);
      if (j == 0 && NumSharedComponents() > 0) {
        int32 input_dim = sub_nnets_components_[i][j]->InputDim();
        int32 prev_output_dim = shared_components_.back()->OutputDim();
        KALDI_ASSERT(prev_output_dim == input_dim);
      }
      int32 output_dim = sub_nnets_components_[i][j]->OutputDim();
      int32 next_input_dim = sub_nnets_components_[i][j+1]->InputDim();
      KALDI_ASSERT(output_dim == next_input_dim);
    }
    if (i != 0) {
      int32 input_dim = sub_nnets_components_[i].front()->InputDim();
      int32 first_input_dim = sub_nnets_components_[0].front()->InputDim();
      KALDI_ASSERT(input_dim == first_input_dim);
    }
  }

  // check for nan/inf in network weights,
  Vector<BaseFloat> weights;
  GetParams(&weights);
  BaseFloat sum = weights.Sum();
  if(KALDI_ISINF(sum)) {
    KALDI_ERR << "'inf' in network parameters (weight explosion, try lower learning rate?)";
  }
  if(KALDI_ISNAN(sum)) {
    KALDI_ERR << "'nan' in network parameters (try lower learning rate?)";
  }
}

void MultiNnet::Destroy() {
  // delete in subnnets
  int num_in_subnnets = NumInSubNnets();
  int num_in_subnnet_components = NumInSubNnetComponents();
  for(int32 i=0; i<num_in_subnnets; i++) {
    for(int32 j=0; j<num_in_subnnet_components; j++) {
      delete in_sub_nnets_components_[i][j];
    }
    in_sub_nnets_components_[i].resize(0);
    in_sub_nnets_propagate_buf_[i].resize(0);
    in_sub_nnets_backpropagate_buf_[i].resize(0);
  }
  in_sub_nnets_components_.resize(0);
  in_sub_nnets_propagate_buf_.resize(0);
  in_sub_nnets_backpropagate_buf_.resize(0);

  if (merge_component_ != NULL) {
    delete merge_component_;
  }

  // delete shared components
  for(int32 i=0; i<NumSharedComponents(); i++) {
    delete shared_components_[i];
  }
  shared_components_.resize(0);
  shared_propagate_buf_.resize(0);
  shared_backpropagate_buf_.resize(0);

  // delete subnnets
  int num_subnnets = NumSubNnets();
  int num_subnnet_components = NumSubNnetComponents();
  for(int32 i=0; i<num_subnnets; i++) {
    for(int32 j=0; j<num_subnnet_components; j++) {
      delete sub_nnets_components_[i][j];
    }
    sub_nnets_components_[i].resize(0);
    sub_nnets_propagate_buf_[i].resize(0);
    sub_nnets_backpropagate_buf_[i].resize(0);
  }
  sub_nnets_components_.resize(0);
  sub_nnets_propagate_buf_.resize(0);
  sub_nnets_backpropagate_buf_.resize(0);
}

void MultiNnet::SetTrainOptions(const NnetTrainOptions& opts) {
  opts_ = opts;
  //set values to individual components
  // in subnnets
  for(int32 i=0; i<NumInSubNnets(); i++) {
    for(int32 j=0; j<NumInSubNnetComponents(); j++) {
      if(GetInSubNnetComponent(i,j).IsUpdatable()) {
        dynamic_cast<UpdatableComponent&>(GetInSubNnetComponent(i,j)).SetTrainOptions(opts_);
      }
    }
  }
  // shared components
  for(int32 l=0; l<NumSharedComponents(); l++) {
    if(GetSharedComponent(l).IsUpdatable()) {
      dynamic_cast<UpdatableComponent&>(GetSharedComponent(l)).SetTrainOptions(opts_);
    }
  }
  // subnnets
  for(int32 i=0; i<NumSubNnets(); i++) {
    for(int32 j=0; j<NumSubNnetComponents(); j++) {
      if(GetSubNnetComponent(i,j).IsUpdatable()) {
        dynamic_cast<UpdatableComponent&>(GetSubNnetComponent(i,j)).SetTrainOptions(opts_);
      }
    }
  }
}

void MultiNnet::SetUpdatables(std::vector<bool> updatables) {
  KALDI_ASSERT(NumInSubNnetComponents() + NumSharedComponents() + NumSubNnetComponents()  == updatables.size());
  for (int i=0; i<NumInSubNnetComponents(); i++) {
    for (int j=0; j<NumInSubNnets(); j++) {
      if (in_sub_nnets_components_[j][i]->IsUpdatableLayer()) {
        UpdatableComponent *uc = dynamic_cast<UpdatableComponent*>(in_sub_nnets_components_[j][i]);
        uc->SetUpdatable(updatables[i]);
      }
    }
  }
  for (int i=0; i<NumSharedComponents(); i++) {
    if (shared_components_[i]->IsUpdatableLayer()) {
      UpdatableComponent *uc = dynamic_cast<UpdatableComponent*>(shared_components_[i]);
      uc->SetUpdatable(updatables[i+NumInSubNnetComponents()]);
    }
  }
  for (int i=0; i<NumSubNnetComponents(); i++) {
    for (int j=0; j<NumSubNnets(); j++) {
      if (sub_nnets_components_[j][i]->IsUpdatableLayer()) {
        UpdatableComponent *uc = dynamic_cast<UpdatableComponent*>(sub_nnets_components_[j][i]);
        uc->SetUpdatable(updatables[i+NumInSubNnetComponents()+NumSharedComponents()]);
      }
    }
  }
}

} // namespace nnet1
} // namespace kaldi
