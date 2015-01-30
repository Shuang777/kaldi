// nnet/nnet-loss.cc

// Copyright 2011-2015  Brno University of Technology (author: Karel Vesely)

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

#include "nnet/nnet-loss.h"
#include "nnet/nnet-utils.h"
#include "cudamatrix/cu-math.h"
#include "hmm/posterior.h"

#include <sstream>
#include <iterator>

namespace kaldi {
namespace nnet1 {


/* Xent */

/**
 * Helper function of Xent::Eval,
 * calculates number of matching elemente in 'v1', 'v2' weighted by 'weights'.
 */
template <typename T>
inline void CountCorrectFramesWeighted(const CuArray<T> &v1, 
                                       const CuArray<T> &v2, 
                                       const VectorBase<BaseFloat> &weights, 
                                       double *correct) {
  KALDI_ASSERT(v1.Dim() == v2.Dim());
  KALDI_ASSERT(v1.Dim() == weights.Dim());
  int32 dim = v1.Dim();
  // Get GPU data to host,
  std::vector<T> v1_h(dim), v2_h(dim);
  v1.CopyToVec(&v1_h);
  v2.CopyToVec(&v2_h);
  // Get correct frame count (weighted),
  double corr = 0.0;
  for (int32 i=0; i<dim; i++) {
   corr += weights(i) * (v1_h[i] == v2_h[i] ? 1.0 : 0.0);
  }
  // Return,
  (*correct) = corr;
}


void Xent::Eval(const VectorBase<BaseFloat> &frame_weights,
                const CuMatrixBase<BaseFloat> &net_out, 
                const CuMatrixBase<BaseFloat> &target, 
                CuMatrix<BaseFloat> *diff) {
  // check inputs,
  KALDI_ASSERT(net_out.NumCols() == target.NumCols());
  KALDI_ASSERT(net_out.NumRows() == target.NumRows());
  KALDI_ASSERT(net_out.NumRows() == frame_weights.Dim());
  diff->Resize(net_out.NumRows(), net_out.NumCols());
  double num_frames = frame_weights.Sum();

  // get frame_weights to GPU,
  frame_weights_ = frame_weights;

  // compute derivative wrt. activations of last layer of neurons,
  *diff = net_out;
  diff->AddMat(-1.0, target);
  diff->MulRowsVec(frame_weights_); // weighting,

  // evaluate the frame-level classification,
  double correct; 
  net_out.FindRowMaxId(&max_id_out_); // find max in nn-output
  target.FindRowMaxId(&max_id_tgt_); // find max in targets
  CountCorrectFramesWeighted(max_id_out_, max_id_tgt_, frame_weights, &correct);

  // calculate cross_entropy (in GPU),
  xentropy_aux_ = net_out; // y
  xentropy_aux_.ApplyLog(); // log(y)
  xentropy_aux_.MulElements(target); // t*log(y)
  xentropy_aux_.MulRowsVec(frame_weights_); // w*t*log(y) 
  double cross_entropy = -xentropy_aux_.Sum();
  
  // caluculate entropy (in GPU),
  entropy_aux_ = target; // t
  entropy_aux_.Add(1e-20); // avoid log(0)
  entropy_aux_.ApplyLog(); // log(t)
  entropy_aux_.MulElements(target); // t*log(t)
  entropy_aux_.MulRowsVec(frame_weights_); // w*t*log(t) 
  double entropy = -entropy_aux_.Sum();

  loss_ += cross_entropy;
  entropy_ += entropy;
  correct_ += correct;
  frames_ += num_frames;

  // progressive loss reporting
  {
    static const int32 progress_step = 3600*100; // 1h
    frames_progress_ += num_frames;
    loss_progress_ += cross_entropy;
    entropy_progress_ += entropy;
    if (frames_progress_ > progress_step) {
      KALDI_VLOG(1) << "ProgressLoss[" << frames_progress_/100/3600 << "h/" << frames_/100/3600 << "h]: " 
                    << (loss_progress_-entropy_progress_)/frames_progress_ << " (Xent)";
      // store
      loss_vec_.push_back((loss_progress_-entropy_progress_)/frames_progress_);
      // reset
      frames_progress_ = 0;
      loss_progress_ = 0.0;
      entropy_progress_ = 0.0;
    }
  }
}


void Xent::Eval(const VectorBase<BaseFloat> &frame_weights,
                const CuMatrixBase<BaseFloat> &net_out, 
                const Posterior &post, 
                CuMatrix<BaseFloat> *diff) {
  int32 num_frames = net_out.NumRows(),
    num_pdf = net_out.NumCols();
  KALDI_ASSERT(num_frames == post.size());

  // convert posterior to matrix,
  PosteriorToMatrix(post, num_pdf, &tgt_mat_);

  // call the other eval function,
  Eval(frame_weights, net_out, tgt_mat_, diff);
}

void Xent::Eval(const std::vector<CuMatrixBase<BaseFloat> *> &net_outs, const Posterior& post, 
                const std::vector<int32> &subnnet_ids, std::vector<CuMatrix<BaseFloat>* > &diffs) {
  const int32 num_frames = net_outs.front()->NumRows(),
              num_subnnets = net_outs.size();
  KALDI_ASSERT(num_frames == post.size());

  // convert posterior to matrix
  std::vector<Matrix<BaseFloat> > tgt_mats_host(num_subnnets);
  std::vector<Vector<BaseFloat> > subnnet_mask_host(num_subnnets);
  for (int32 i = 0; i < num_subnnets; i++) {
    tgt_mats_host[i].Resize(num_frames, net_outs[i]->NumCols(), kSetZero);
    subnnet_mask_host[i].Resize(num_frames, kSetZero);
  }
  for (int32 t = 0; t < post.size(); t++) {
    int32 subnnet_id = subnnet_ids[t];
    int32 num_pdf = net_outs[subnnet_id]->NumCols();
    subnnet_mask_host[subnnet_id](t) = 1.0;
    for (int32 i = 0; i < post[t].size(); i++) {
      int32 pdf = post[t][i].first;
      if (pdf >= num_pdf) {
        KALDI_ERR << "Posterior pdf-id out of NN-output dimension, please check number of pdfs by 'hmm-info'."
                  << " nn-outputs : " << num_pdf << ", posterior pdf-id : " << pdf;
      }
      tgt_mats_host[subnnet_id](t, pdf) += post[t][i].second;
    }
  }
  tgt_mats_device_.resize(num_subnnets);
  subnnet_mask_device_.resize(num_subnnets);
  for (int32 i = 0; i < num_subnnets; i++) {
    tgt_mats_device_[i] = tgt_mats_host[i]; // -> GPU
    subnnet_mask_device_[i] = subnnet_mask_host[i];
  }

  // compute derivaitve w.r.t. pre-softmax activation (net_out - tgt)
  KALDI_ASSERT(num_subnnets == diffs.size());
  for (int32 i = 0; i < num_subnnets; i++) {
    *diffs[i] = *net_outs[i];
    diffs[i]->AddMat(-1.0, tgt_mats_device_[i]);
    diffs[i]->MulRowsVec(subnnet_mask_device_[i]);
  }

  // evaluate the frame-level classification
  int32 correct=0;
  double cross_entropy = 0;
  for (int i = 0; i < num_subnnets; i++) {
    net_outs[i]->FindRowMaxId(&max_id_out_); // find max in nn-output
    tgt_mats_device_[i].FindRowMaxId(&max_id_tgt_); // find max in targets
    max_id_out_host_.resize(num_frames);
    max_id_tgt_host_.resize(num_frames);
    max_id_out_.CopyToVec(&max_id_out_host_);
    max_id_tgt_.CopyToVec(&max_id_tgt_host_);
    // count frames where maxima match
    for(int32 t=0; t<num_frames; t++) {
      if (subnnet_ids[t] == i && max_id_tgt_host_[t] == max_id_out_host_[t]) correct++;
    }

   // calculate cross_entropy (in GPU)
    xentropy_aux_ = *net_outs[i]; // y
    xentropy_aux_.Add(1e-20); // avoid -inf
    xentropy_aux_.ApplyLog(); // log(y)
    xentropy_aux_.MulElements(tgt_mats_device_[i]); // t*log(y)
    xentropy_aux_.MulRowsVec(subnnet_mask_device_[i]); // mask it;
    cross_entropy -= xentropy_aux_.Sum(); // sum the matrix
  }

   // calculate entropy (from Posterior)
  double entropy = 0.0;
  for (int32 t = 0; t < post.size(); t++) {
    for (int32 i = 0; i < post[t].size(); i++) {
      BaseFloat p = post[t][i].second;
      entropy += -p*log(p);
    }
  }
  
  // accumulate
  loss_ += cross_entropy;
  entropy_ += entropy;
  correct_ += correct;
  frames_ += num_frames;

  // progressive loss reporting
  {
    static const int32 progress_step = 3600*100; // 1h
    frames_progress_ += num_frames;
    loss_progress_ += cross_entropy;
    entropy_progress_ += entropy;
    if (frames_progress_ > progress_step) {
      KALDI_VLOG(1) << "ProgressLoss[" << frames_progress_/100/3600 << "h/" << frames_/100/3600 << "h]: " 
                    << (loss_progress_-entropy_progress_)/frames_progress_ << " (Xent)";
      // store
      loss_vec_.push_back((loss_progress_-entropy_progress_)/frames_progress_);
      // reset
      frames_progress_ = 0;
      loss_progress_ = 0.0;
      entropy_progress_ = 0.0;
    }
  }
}

std::string Xent::Report() {
  std::ostringstream oss;
  oss << "AvgLoss: " << (loss_-entropy_)/frames_ << " (Xent), "
      << "[AvgXent: " << loss_/frames_ 
      << ", AvgTargetEnt: " << entropy_/frames_ << "]" << std::endl;
  if (loss_vec_.size() > 0) {
     oss << "progress: [";
     std::copy(loss_vec_.begin(),loss_vec_.end(),std::ostream_iterator<float>(oss," "));
     oss << "]" << std::endl;
  }
  if (correct_ >= 0.0) {
    oss << "\nFRAME_ACCURACY >> " << 100.0*correct_/frames_ << "% <<";
  }
  return oss.str(); 
}


/* Mse */

void Mse::Eval(const VectorBase<BaseFloat> &frame_weights,
               const CuMatrixBase<BaseFloat>& net_out, 
               const CuMatrixBase<BaseFloat>& target, 
               CuMatrix<BaseFloat>* diff) {
  KALDI_ASSERT(net_out.NumCols() == target.NumCols());
  KALDI_ASSERT(net_out.NumRows() == target.NumRows());
  int32 num_frames = frame_weights.Sum();

  // get frame_weights to GPU,
  frame_weights_ = frame_weights;

  //compute derivative w.r.t. neural nerwork outputs
  *diff = net_out; // y
  diff->AddMat(-1.0,target); // (y - t)
  diff->MulRowsVec(frame_weights_); // weighting,

  // Compute MeanSquareError loss of mini-batch
  diff_pow_2_ = *diff;
  diff_pow_2_.MulElements(diff_pow_2_); // (y - t)^2
  diff_pow_2_.MulRowsVec(frame_weights_); // w*(y - t)^2
  double mean_square_error = 0.5 * diff_pow_2_.Sum(); // sum the matrix,

  // accumulate
  loss_ += mean_square_error;
  frames_ += num_frames;

  // progressive loss reporting
  {
    static const int32 progress_step = 1e6; // 2.77h
    frames_progress_ += num_frames;
    loss_progress_ += mean_square_error;
    if (frames_progress_ > progress_step) {
      KALDI_VLOG(1) << "ProgressLoss[" << frames_progress_/100/3600 << "h/" << frames_/100/3600 << "h]: " 
                    << loss_progress_/frames_progress_ << " (Mse)";
      // store
      loss_vec_.push_back(loss_progress_/frames_progress_);
      // reset
      frames_progress_ = 0;
      loss_progress_ = 0.0;
    }
  }
}


void Mse::Eval(const VectorBase<BaseFloat> &frame_weights,
               const CuMatrixBase<BaseFloat>& net_out, 
               const Posterior& post, 
               CuMatrix<BaseFloat>* diff) {
  int32 num_frames = net_out.NumRows(),
    num_nn_outputs = net_out.NumCols();
  KALDI_ASSERT(num_frames == post.size());

  // convert posterior to matrix,
  PosteriorToMatrix(post, num_nn_outputs, &tgt_mat_);

  // call the other eval function,
  Eval(frame_weights, net_out, tgt_mat_, diff);
}
 

std::string Mse::Report() {
  // compute root mean square,
  int32 num_tgt = diff_pow_2_.NumCols();
  BaseFloat root_mean_square = sqrt(loss_/frames_/num_tgt);
  // build the message,
  std::ostringstream oss;
  oss << "AvgLoss: " << loss_/frames_ << " (Mse), " << "[RMS " << root_mean_square << "]" << std::endl;
  oss << "progress: [";
  std::copy(loss_vec_.begin(),loss_vec_.end(),std::ostream_iterator<float>(oss," "));
  oss << "]" << std::endl;
  return oss.str();
}


} // namespace nnet1
} // namespace kaldi
