// nnet-multi-nnet.h
//
// Copyright 2015  International Computer Science Institute (Author: Hang Su)
//
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

#ifndef KALDI_NNET_NNET_MULTI_NNET_H_
#define KALDI_NNET_NNET_MULTI_NNET_H_

#include <iostream>
#include <sstream>
#include <vector>

#include "base/kaldi-common.h"
#include "util/kaldi-io.h"
#include "matrix/matrix-lib.h"
#include "nnet/nnet-trnopts.h"
#include "nnet/nnet-component.h"
#include "nnet/nnet-nnet.h"

namespace kaldi {
namespace nnet1 {

class MultiNnet {
 public:
  MultiNnet() {}
  MultiNnet(const MultiNnet& other);
  MultiNnet &operator = (const MultiNnet& other); // Assignment operator.

  ~MultiNnet();

 public:
  void Copy(const MultiNnet& other);
  /// Perform forward pass through the network
  void Propagate(const CuMatrixBase<BaseFloat> &in, std::vector<CuMatrix<BaseFloat> *> &out); 
  /// Perform forward pass through the network with mutliple input
  void Propagate(const std::vector<CuMatrixBase<BaseFloat> *> &in, std::vector<CuMatrix<BaseFloat> *> &out); 
  /// Perform backward pass through the network
  void Backpropagate(const std::vector<CuMatrixBase<BaseFloat> *> &out_diff, CuMatrix<BaseFloat> *in_diff);
  /// Perform forward pass through the network, don't keep buffers (use it when not training)
  void Feedforward(const CuMatrixBase<BaseFloat> &in, const int32 subnnet_id, CuMatrix<BaseFloat> *out); 
  /// Perform forward pass through the network, don't keep buffers (use it when not training)
  void Feedforward(const std::vector<CuMatrix<BaseFloat> *> &in, const int32 subnnet_id, CuMatrix<BaseFloat> *out); 

  /// Dimensionality on network input (input feature dim.)
  int32 SharedInputDims() const;
  int32 SharedOutputDims() const;
  /// Dimensionality of network outputs (posteriors | bn-features | etc.)
  std::vector<int32> InputDims() const; 
  /// Dimensionality of network outputs (posteriors | bn-features | etc.)
  std::vector<int32> OutputDims() const; 
  
  /// Returns number of components-- think of this as similar to # of layers, but
  /// e.g. the nonlinearity and the linear part count as separate components,
  /// so the number of components will be more than the number of layers.
  int32 NumSharedComponents() const { return shared_components_.size(); }

  int32 NumSubNnets() const { return sub_nnets_components_.size(); }
  int32 NumSubNnetComponents() const { return NumSubNnets() > 0 ? sub_nnets_components_[0].size() : 0; }
  int32 NumInSubNnets() const { return in_sub_nnets_components_.size(); }
  int32 NumInSubNnetComponents() const { return NumInSubNnets() > 0 ? in_sub_nnets_components_[0].size() : 0; }

  const Component& GetSharedComponent(int32 c) const;
  Component& GetSharedComponent(int32 c);

  const Component& GetInSubNnetComponent(int32 in_sub_nnet, int32 component) const;
  Component& GetInSubNnetComponent(int32 in_sub_nnet, int32 component);

  const Component& GetSubNnetComponent(int32 sub_nnet, int32 component) const;
  Component& GetSubNnetComponent(int32 sub_nnet, int32 component);

  /// Appends this component to the components already in the neural net.
  /// Takes ownership of the pointer
  void AppendSharedComponent(Component *dynamically_allocated_comp);

  /// Remove component
  void RemoveSharedComponent(int32 c);
  /// Remove subnnet component for all subnnets
  void RemoveSubNnetComponent(int32 c);
  /// Remove in_subnnet component
  void RemoveInSubNnetComponent(int32 c);
  /// Add sub nnet
  void AddSubNnet(const Nnet& nnet_to_add);
  /// Add in_sub nnet
  void AddInSubNnet(const Nnet& nnet_to_add);
  /// Split shared nnet and assign to sub nnets
  void Split(int32 c);
  /// Split shared nnet at the front and assign to in_sub_nnets
  void SplitFront(int32 c);
 
  /// Access to forward pass buffers
  const std::vector<CuMatrix<BaseFloat> >& SharedPropagateBuffer() const { 
    return shared_propagate_buf_; 
  }
  /// Access to backward pass buffers
  const std::vector<CuMatrix<BaseFloat> >& SharedBackpropagateBuffer() const { 
    return shared_backpropagate_buf_; 
  }

  /// Get the number of parameters in the network
  int32 NumParams() const;
  /// Get the network weights in a supervector
  void GetParams(Vector<BaseFloat>* wei_copy) const;
  /// Set the dropout rate
  void SetDropoutRetention(kaldi::BaseFloat);
    
  /// Initialize MLP from config
  void Init(const std::string &config_file);
  /// Read the MLP from file (can add layers to exisiting instance of Nnet)
  void Read(const std::string &file);  
  /// Read the MLP from stream (can add layers to exisiting instance of Nnet)
  void Read(std::istream &in, bool binary, const bool is_nnet = false);
  /// Read shared MLP from file
  void ReadSharedNnet(const std::string &file);
  /// Read shared MLP from stream
  void ReadSharedNnet(std::istream &in, bool binary);
  /// Write MultiMLP to file
  void Write(const std::string &file, bool binary) const;
  /// Write MultiMLP to stream 
  void Write(std::ostream &out, bool binary) const;   
  /// Write MLP to file
  void WriteNnet(const std::string &file, bool binary, const int32 in_subnnet = -1, const int32 subnnet = -1) const;
  /// Write MLP to stream 
  void WriteNnet(std::ostream &out, bool binary, const int32 in_subnnet = -1, const int32 subnnet = -1) const;   
  /// Write MLP to file
  void WriteInSubNnet(const std::string &file, bool binary, const int32 in_subnnet) const;
  /// Write MLP to stream 
  void WriteInSubNnet(std::ostream &out, bool binary, const int32 in_subnnet) const;   
  /// Write MLP to file
  void WriteSubNnet(const std::string &file, bool binary, const int32 subnnet) const;
  /// Write MLP to stream 
  void WriteSubNnet(std::ostream &out, bool binary, const int32 subnnet) const;   
  
  /// Create string with human readable description of the nnet
  std::string Info() const;
  /// Create string with per-component gradient statistics
  std::string InfoGradient() const;
  /// Create string with propagation-buffer statistics
  std::string InfoPropagate() const;
  /// Create string with back-propagation-buffer statistics
  std::string InfoBackPropagate() const;
  
  /// Consistency check.
  void Check() const;
  /// Relese the memory
  void Destroy();

  /// Set training hyper-parameters to the network and its UpdatableComponent(s)
  void SetTrainOptions(const NnetTrainOptions& opts);
  /// Set Layers to update during training
  void SetUpdatables(std::vector<bool> updatables);
  /// Get training hyper-parameters from the network
  const NnetTrainOptions& GetTrainOptions() const {
    return opts_;
  }

 private:
  /// Vector which contains all the shared components composing the neural network,
  /// the components are for example: AffineTransform, Sigmoid, Softmax
  std::vector<Component*> shared_components_;

  std::vector<CuMatrix<BaseFloat> > shared_propagate_buf_; ///< buffers for forward pass
  std::vector<CuMatrix<BaseFloat> > shared_backpropagate_buf_; ///< buffers for backward pass

  /// Option class with hyper-parameters passed to UpdatableComponent(s)
  NnetTrainOptions opts_;

  /// Vector of sub_nnet_components_;
  std::vector<std::vector<Component*> > sub_nnets_components_;
  std::vector<std::vector<CuMatrix<BaseFloat> > > sub_nnets_propagate_buf_;
  std::vector<std::vector<CuMatrix<BaseFloat> > > sub_nnets_backpropagate_buf_;

  /// Vector of in_sub_nnet_components_;
  std::vector<std::vector<Component*> > in_sub_nnets_components_;
  std::vector<std::vector<CuMatrix<BaseFloat> > > in_sub_nnets_propagate_buf_;
  std::vector<std::vector<CuMatrix<BaseFloat> > > in_sub_nnets_backpropagate_buf_;
};


} // namespace nnet1
} // namespace kaldi

#endif  // KALDI_NNET_NNET_MULTI_NNET_H_
