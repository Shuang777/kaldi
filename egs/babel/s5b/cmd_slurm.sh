#!/bin/bash

export train_cmd="myutils/slurm.pl"
export decode_cmd="myutils/slurm.pl"
export cuda_cmd="myutils/slurm.pl -l gpu=1,mem_free=6G"
export cudall_cmd="myutils/slurm_gpu.pl -l gpu=1,mem_free=6G"
