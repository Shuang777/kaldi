#!/bin/bash

export train_cmd="myutils/slurm.pl"
export decode_cmd="myutils/slurm.pl"
export cuda_cmd="myutils/slurm.pl -l gpu=1,mem_free=6G"
