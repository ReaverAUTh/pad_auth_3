#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <math.h>
#include "supplementary.h"

//!------------------------------------------------------------------
//! EDIT THESE VALUES ACCORDING TO THE IMAGE SIZE AND SPECIFICATIONS

#define PIXELS 64 // PIXELS x PIXELS
#define PATCH_SIZE 3
#define FILTER_SIGMA 0.0185
#define PATCH_SIGMA 3.1550

//!------------------------------------------------------------------

// Device global variables
__device__ const int DEV_PIXELS = PIXELS;
__device__ const int DEV_PATCH_SIZE = PATCH_SIZE;
__device__ const float DEV_FILTER_SIGMA = (float)FILTER_SIGMA;
__device__ const int DEV_PADDING = PATCH_SIZE/2;

// Host global variables
const int HOST_PADDING = PATCH_SIZE/2;

// Functions
__global__ void denoise_image(float *filtered_image, float *image, int padded_size, float *G);
__device__ void compare_patches(float *comp_value, float *patch_i, int j, float *G, float *shared_memory);
__host__ float *nonLocalMeans(float *host_image);
__host__ float *gaussian_filter();



__host__ int main(){
	//read image from txt
    float *host_image = image_from_txt(PIXELS, HOST_PADDING);
	
	float *filtered_image;
	cudaMallocManaged(&filtered_image,0*sizeof(float));
    struct timespec tic, toc;
	
    clock_gettime(CLOCK_MONOTONIC, &tic);
    filtered_image = nonLocalMeans(host_image);
    clock_gettime(CLOCK_MONOTONIC, &toc);
	
    FILE *f = fopen("filtered_image.txt", "w");
	if(f == NULL){
		printf("Cannot open filtered_image.txt\n");
		exit(1);
	}
	
    int pixels_counter = 0;
	int padded_size = PIXELS*PIXELS + 4*HOST_PADDING*PIXELS + 4*HOST_PADDING*HOST_PADDING;
	int start = PIXELS*HOST_PADDING + 2*HOST_PADDING*HOST_PADDING + HOST_PADDING; //skip first padding rows
    
	for(int i=start; i<(padded_size-start); i++){
        fprintf(f, "%f ", filtered_image[i]);
        pixels_counter++;
        if(pixels_counter == PIXELS){
            pixels_counter = 0;
			i += 2*HOST_PADDING;
            fprintf(f, "\n");
        }
    }
    fclose(f);
    free(host_image);
	cudaFree(filtered_image);
	
	printf("*NLM-CUDA-SHARED Duration = %f second(s)* || (Pixels, Patch) = (%d, %d)\n", elapsed_time(tic,toc), PIXELS, PATCH_SIZE);
    return 0;
}

__host__ float *nonLocalMeans(float *host_image){
	int padded_size = PIXELS*PIXELS + 4*HOST_PADDING*PIXELS + 4*HOST_PADDING*HOST_PADDING;

    float *G;
	cudaMallocManaged(&G, PATCH_SIZE*PATCH_SIZE*sizeof(float));
	if(G == NULL){
        exit(1);
    }
	float *temp = gaussian_filter();
	memcpy(G, temp, PATCH_SIZE*PATCH_SIZE*sizeof(float));
	
	//host_image is not know to both the host and device, hence the memcpy
	float *image;
	cudaMallocManaged(&image, padded_size*sizeof(float));
	if(image == NULL){
        exit(1);
    }
	memcpy(image, host_image, padded_size*sizeof(float));

	float *filtered_image;
	cudaMallocManaged(&filtered_image, padded_size*sizeof(float));
	if(filtered_image == NULL){
        exit(1);
    }
	// Fill array with -1, so after adding the image's values
	// the padding will have -1 values
	for(int i=0; i<padded_size; i++){
		filtered_image[i]=(float)-1;
	}
	
    //! KERNEL
	int shared_memory_size = PATCH_SIZE*(PIXELS + 2*HOST_PADDING);
    denoise_image<<<PIXELS, PIXELS, shared_memory_size*sizeof(float)>>>(filtered_image, image, padded_size, G);
	cudaDeviceSynchronize();
	//! KERNEL
	
	cudaFree(G);
	cudaFree(image);
    return filtered_image;
}

//! Compute the gaussian filter
__host__ float *gaussian_filter(){
    float *G = (float *)malloc(PATCH_SIZE*PATCH_SIZE*sizeof(float));
    if(G == NULL){
        exit(1);
	}
	// bound for the 2D Gaussian filter
    int bound = PATCH_SIZE/2;
    for(int x=-bound; x<=bound; x++){
        for(int y=-bound; y<=bound; y++){
			int index = (x+bound)*PATCH_SIZE + (y+bound);
            G[index] = exp( -(float)(x*x+y*y)/(float)(2*PATCH_SIGMA*PATCH_SIGMA) ) / (float)(2*M_PI*PATCH_SIGMA*PATCH_SIGMA);
        }
    }
    return G;
}

__global__ void denoise_image(float *filtered_image, float *image, int padded_size, float *G){
	int index = blockIdx.x*(blockDim.x+2*DEV_PADDING) + (threadIdx.x+DEV_PADDING) + DEV_PADDING*DEV_PIXELS + 2*DEV_PADDING*DEV_PADDING;
	int row_size = DEV_PIXELS + 2*DEV_PADDING;
	//safety-check if
	if(index < padded_size){
		//shared memory
		extern __shared__ float shared_memory[];
		//each thread handles its column
		for(int i=0; i<DEV_PATCH_SIZE; i++){
			shared_memory[(threadIdx.x + DEV_PADDING) + i*row_size] = image[(threadIdx.x+DEV_PADDING) + i*row_size];
		}
		//thread #0 also handles the side paddings
		if(threadIdx.x == 0){
			for(int row=0; row<DEV_PADDING; row++){
				for(int col=0; col<DEV_PATCH_SIZE; col++){
					shared_memory[row + col*row_size] = -1;
				}
			}
			for(int row=(DEV_PADDING+DEV_PIXELS); row<row_size; row++){
				for(int col=0; col<DEV_PATCH_SIZE; col++){
					shared_memory[row + col*row_size] = -1;
				}
			}
		}
		__syncthreads();
		//creating i's patch
		float patch_i[DEV_PATCH_SIZE*DEV_PATCH_SIZE];
		for(int it1=0; it1<DEV_PATCH_SIZE; it1++){
			for(int it2=0; it2<DEV_PATCH_SIZE; it2++){
				patch_i[it1*DEV_PATCH_SIZE + it2] = image[index + (it1-DEV_PADDING)*row_size + it2 - DEV_PADDING];
			}
		}
		filtered_image[index] = 0;
		float weight;
		float Z = 0;
		for(int it1=DEV_PADDING; it1<(DEV_PIXELS+DEV_PADDING); it1++){
			for(int it2=DEV_PADDING; it2<(DEV_PIXELS+DEV_PADDING); it2++){	
				float comp_value = 0;
				compare_patches(&comp_value, patch_i, it2, G, shared_memory);
				weight = (float)(exp(-comp_value/(DEV_FILTER_SIGMA*DEV_FILTER_SIGMA)));
				filtered_image[index] += weight * shared_memory[DEV_PADDING*row_size + it2];
				Z += weight;
			}
			__syncthreads();
			//alter the shared memory, slide everything one row up
			for(int i=0; i<DEV_PATCH_SIZE-1; i++){
				shared_memory[(threadIdx.x+DEV_PADDING) + i*row_size] = shared_memory[(threadIdx.x+DEV_PADDING) + (i+1)*row_size];
			}
			int row_offset = (it1+1-DEV_PADDING)*row_size;
			//insert the new row in the shared_memory
			shared_memory[(threadIdx.x+DEV_PADDING) + (DEV_PATCH_SIZE-1)*row_size] = image[row_offset + (threadIdx.x+DEV_PADDING) + (DEV_PATCH_SIZE-1)*row_size];
			__syncthreads();
		}
		filtered_image[index] = filtered_image[index] / Z; 
	}
}

//! Compares patch_i with the patch of pixel j
__device__ void compare_patches(float *comp_value, float *patch_i, int j, float *G, float *shared_memory){
	int offset = DEV_PADDING*(DEV_PIXELS + 2*DEV_PADDING);
	j += offset;
    for(int it1=0; it1<DEV_PATCH_SIZE; it1++){
        for(int it2=0; it2<DEV_PATCH_SIZE; it2++){
			int first_index = it1*DEV_PATCH_SIZE+it2;
			int second_index = j+(it1-DEV_PADDING)*(DEV_PIXELS+2*DEV_PADDING) + it2 - DEV_PADDING;
            // patch/shared_memory[x] == -1 means it's the added padding
			if(patch_i[first_index] != (float)-1 && shared_memory[second_index] != (float)-1){
                float diff = patch_i[first_index] - shared_memory[second_index];
                *comp_value += G[first_index]*(diff*diff);
            }
        }
    }
}
