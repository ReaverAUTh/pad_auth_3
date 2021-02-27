SHELL := /bin/bash # Use bash syntax

CC = sm_30
CFLAGS = -O3
NVCC	= nvcc -o
ARGS	= -ptx

default: all

nlm-serial:
	gcc $(CFLAGS) -o nlm-serial nlm-serial.c -lm

nlm-cuda:
	$(NVCC) nlm-cuda nlm-cuda.cu

nlm-cuda-shared:
	$(NVCC) nlm-cuda-shared nlm-cuda-shared.cu


.PHONY: clean

all: nlm-serial nlm-cuda nlm-cuda-shared


clean:
	rm -f nlm-serial nlm-cuda nlm-cuda-shared