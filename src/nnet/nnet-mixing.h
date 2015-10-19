#include <mpi.h>
#include "nnet/nnet-nnet.h"

using namespace kaldi;
using namespace kaldi::nnet1;

/// Butterfly mixing
int get_butterfly_friend_id(int mpi_rank, int mpi_jobs, int round_i) {
  int rounds = round(log2(mpi_jobs));
  return mpi_rank ^ (1 << (round_i % rounds));
}

bool is_power_of_two(int x) {
  return ((x != 0) && !(x & (x-1)));
}

void share_nnet_buffer(Nnet &nnet, const int rank_id, const int send_to_id, const int receive_from_id, const bool average_model = true) {
  KALDI_ASSERT(rank_id != send_to_id && rank_id != receive_from_id);
  int num_elements = nnet.NumElements();
  MPI_Sendrecv(nnet.GetSendBuffer(), num_elements, MPI_FLOAT, send_to_id, 0, nnet.GetReceiveBuffer(), num_elements, MPI_FLOAT, receive_from_id, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
  if (average_model) {
    nnet.AverageReceiveBuffer();
  }
}

void all_reduce_nnet_buffer(Nnet &nnet, const int mpi_jobs, const bool average_model = true) {
  int num_elements = nnet.NumElements();
  MPI_Allreduce(nnet.GetSendBuffer(), nnet.GetReceiveBuffer(), num_elements, MPI_FLOAT, MPI_SUM, MPI_COMM_WORLD);
  if (average_model) {
    float scale = 1.0/mpi_jobs;
    nnet.SetAndScaleBuffer(scale);
  }
}

void send_nnet_buffer(Nnet &nnet, const int src_rank_id) {
  int num_elements = nnet.NumElements();
  MPI_Bcast(nnet.GetSendBuffer(), num_elements, MPI_FLOAT, src_rank_id, MPI_COMM_WORLD);
  nnet.SetAndScaleBuffer(1.0);
}
