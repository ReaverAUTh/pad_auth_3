<p align="center">
  <img width="600" height="257" src="https://i.imgur.com/DOgejso.png">
</p>

# Parallel-Exercise3

A Non-Local-Means algorithm implementation using NVIDIA CUDA.

**/results/** contains the results produced by using AUTh's High Performance Computing (HPC) infrastructure.

**/results/image_results/** contains the visual results produced by running the implementations. 

**/images/** contains the images used to produce the results.

## **1. Before using**
* Pull the directory and save it locally. Within that directory, add an image of strict sizing up to 256x256. The implementations work only for square images. 
* Open each .c and .cu file and edit the global variables (PIXELS, PATCH_SIZE, FILTER_SIGMA, PATCH_SIGMA) at the top of the script according to your needs. 
* PIXELS refers to the size of your image (PIXELSxPIXELS).

**nlm-serial.c:** Serial Implementation

**nlm-cuda.cu:** Implementation using NVIDIA CUDA

**nlm-cuda-shared.cu:** Implementation using NVIDIA CUDA and shared memory between threads

#
Repo for the third exercise of course 050 - Parallel and Distributed Systems, Aristotle University of Thessaloniki, Dpt. of Electrical & Computer Engineering.

