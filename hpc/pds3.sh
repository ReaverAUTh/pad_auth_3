#!/bin/bash
#SBATCH --job-name=nlm_gpu
#SBATCH --nodes=1
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=10:00
#SBATCH --output=durations.stdout 


module load gcc
module load cuda/10.1.243

#nvidia-smi
make clean
make all
./nlm-serial
./nlm-cuda
./nlm-cuda-shared
make clean



