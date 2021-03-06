// nnet/nnet-nnet.h

// Copyright 2011-2013  Brno University of Technology (Author: Karel Vesely)

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

#ifndef KALDI_NNET_NNET_NNET_H_
#define KALDI_NNET_NNET_NNET_H_

#include <iostream>
#include <sstream>
#include <vector>

#include "base/kaldi-common.h"
#include "util/kaldi-io.h"
#include "matrix/matrix-lib.h"
#include "nnet/nnet-trnopts.h"
#include "nnet/nnet-component.h"

namespace kaldi {
namespace nnet1 {

class Nnet {
 public:
  Nnet() : send_buffer_(NULL), receive_buffer_(NULL), reduce_content_ ("model") {}
  Nnet(const Nnet& other); // Copy constructor.
  Nnet &operator = (const Nnet& other); // Assignment operator.

  ~Nnet(); 

 public:
  /// Perform forward pass through the network
  void Propagate(const CuMatrixBase<BaseFloat> &in, CuMatrix<BaseFloat> *out); 
  /// Perform backward pass through the network
  void Backpropagate(const CuMatrixBase<BaseFloat> &out_diff, CuMatrix<BaseFloat> *in_diff);
  /// Perform backward pass through the network with semidata gradient cutoff
  void Backpropagate(const CuMatrixBase<BaseFloat> &out_diff, CuMatrix<BaseFloat> *in_diff, const CuVector<BaseFloat> &frm_weights, const int32 semi_layers);
  /// Perform forward pass through the network, don't keep buffers (use it when not training)
  void Feedforward(const CuMatrixBase<BaseFloat> &in, CuMatrix<BaseFloat> *out); 

  /// Dimensionality on network input (input feature dim.)
  int32 InputDim() const; 
  /// Dimensionality of network outputs (posteriors | bn-features | etc.)
  int32 OutputDim() const; 

  /// Number of frames dependent on neighbors
  int32 FramesDependent() const;

  /// Returns number of components-- think of this as similar to # of layers, but
  /// e.g. the nonlinearity and the linear part count as separate components,
  /// so the number of components will be more than the number of layers.
  int32 NumComponents() const { return components_.size(); }

  const Component& GetComponent(int32 c) const;
  Component& GetComponent(int32 c);

  std::string GetReduceContent() const { return reduce_content_; }

  /// Sets the c'th component to "component", taking ownership of the pointer
  /// and deleting the corresponding one that we own.
  void SetComponent(int32 c, Component *component);

  /// Set the components to be updatable or not
  void SetUpdatables(std::vector<bool> updatables);

  /// Set reference nnet for regularization
  void SetRefNnet(const Nnet& ref_nnet);

  /// Set content to reduce in MPI
  void SetReduceContent(std::string content);
 
  /// Appends this component to the components already in the neural net.
  /// Takes ownership of the pointer
  void AppendComponent(Component *dynamically_allocated_comp);
  /// Append another network to the current one (copy components).
  void AppendNnet(const Nnet& nnet_to_append);

  /// Remove component
  void RemoveComponent(int32 c);
  void RemoveLastComponent() { RemoveComponent(NumComponents()-1); }

  /// Access to forward pass buffers
  const std::vector<CuMatrix<BaseFloat> >& PropagateBuffer() const { 
    return propagate_buf_; 
  }
  /// Access to backward pass buffers
  const std::vector<CuMatrix<BaseFloat> >& BackpropagateBuffer() const { 
    return backpropagate_buf_; 
  }

  /// Get the number of parameters in the network
  int32 NumParams() const;
  /// Get the number of elements in the network (physically allocated Real numbers)
  int32 NumElements() const;
  /// Get the network weights in a supervector
  void GetParams(Vector<BaseFloat>* wei_copy) const;
  /// Get the network weights in a supervector
  void GetWeights(Vector<BaseFloat>* wei_copy) const;
  /// Set the network weights from a supervector
  void SetWeights(const Vector<BaseFloat>& wei_src);
  /// Get the gradient stored in the network
  void GetGradient(Vector<BaseFloat>* grad_copy) const;
  /// Set the dropout rate 
  void SetDropoutRetention(BaseFloat r);
  /// Allocate buffer for MPI
  void AllocBuffer();
  /// Prepare for MPI
  void PrepSendBuffer();

  BaseFloat *GetSendBuffer() { return send_buffer_;}
  BaseFloat *GetReceiveBuffer() { return receive_buffer_;}

  /// Average model with weights in receive buffer
  void AverageReceiveBuffer();

  /// Copy gradient from bufer and update
  void CopyBufferAndUpdate();

  /// Set the model with weights in the buffer and scale it
  void SetAndScaleBuffer(const BaseFloat scale);

  /// Initialize MLP from config
  void Init(const std::string &config_file);
  /// Read the MLP from file (can add layers to exisiting instance of Nnet)
  void Read(const std::string &file);  
  /// Read the MLP from stream (can add layers to exisiting instance of Nnet)
  void Read(std::istream &in, bool binary);  
  /// Write MLP to file
  void Write(const std::string &file, bool binary) const;
  /// Write MLP to stream 
  void Write(std::ostream &out, bool binary) const;   

  /// Change AffineTransform layers to AffineTransformPreconditioned
  void Affine2Preconditioned(BaseFloat max_norm, BaseFloat alpha);
  void Affine2PreconditionedOnline(int32 rank_in, int32 rank_out,
                                   int32 update_period, BaseFloat num_samples_history,
                                   BaseFloat alpha, BaseFloat max_change_per_sample);
  
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
  /// Check if of same structure
  void CheckSameStructure(const Nnet &other) const;
  /// Relese the memory
  void Destroy();

  /// Set training hyper-parameters to the network and its UpdatableComponent(s)
  void SetTrainOptions(const NnetTrainOptions& opts);
  /// Get training hyper-parameters from the network
  const NnetTrainOptions& GetTrainOptions() const {
    return opts_;
  }

 private:
  /// Vector which contains all the components composing the neural network,
  /// the components are for example: AffineTransform, Sigmoid, Softmax
  std::vector<Component*> components_; 

  std::vector<CuMatrix<BaseFloat> > propagate_buf_; ///< buffers for forward pass
  std::vector<CuMatrix<BaseFloat> > backpropagate_buf_; ///< buffers for backward pass

  BaseFloat* send_buffer_;    // buffer for MPI communication
  BaseFloat* receive_buffer_; // buffer for MPI communication
  CuVector<BaseFloat> cuda_receive_buffer_;
  std::string reduce_content_;    // model, momentum, all

  /// Option class with hyper-parameters passed to UpdatableComponent(s)
  NnetTrainOptions opts_;
};
  

} // namespace nnet1
} // namespace kaldi

#endif  // KALDI_NNET_NNET_NNET_H_


