// TestFFTx86.cpp : Defines the entry point for the console application.
//

#include "stdafx.h"
#include "fftw3.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <random>
#include <iostream>
#include <fstream>
#include <Windows.h>
#include <string>
#include <cstring>
#include <algorithm>
#include <chrono>
#include <vector>
using namespace std;

void testFFT(int experi);

int main()
{
	fftwf_init_threads();
	fftwf_plan_with_nthreads(4);
	for (int i = 0; i < 100000; i++)
		testFFT(i);
	fftwf_cleanup_threads();
	getchar();
    return 0;
}

void testFFT(int experi)
{
	int rank = 1; /* not 2: we are computing 1d transforms */
	fftwf_complex *in;
	int nx = 2048;
	int ny = 512;
	int nyh;
	fftwf_complex *out;
	fftwf_plan plan_forward;
	unsigned int seed = 123456789;

	LARGE_INTEGER frequency;
	LARGE_INTEGER start;
	LARGE_INTEGER end;
	double interval;

	int n[] = { ny }; /* 1d transforms of length ny */
	int howmany = nx;
	int idist = ny, odist = ny;
	int istride = 1, ostride = 1; /* distance between two elements in
								  the same column */
	int *inembed = n, *onembed = n;

	in = (fftwf_complex*)fftwf_malloc(sizeof(fftwf_complex) * nx * ny);

	srand(time(NULL));

	float* freq = (float*) malloc(sizeof(float) * nx);
	float Fs = 50000;
	float pi = 3.1416;
	default_random_engine generator;
	normal_distribution<float> distribution(0, 1);
	
	for (int i = 0; i < nx; i++) {
		freq[i] = 100.0 + i * (Fs-200) / nx;
		for (int j = 0; j < ny; j++) {
			int idx = i*ny + j;
			srand(time(NULL));
			in[idx][0] = cosf(2 * pi* freq[i] * j / Fs)*rand()/RAND_MAX;//+ distribution(generator);
			in[idx][1] = sinf(2 * pi* freq[i] * j / Fs)*rand() / RAND_MAX;//+ distribution(generator);
		}
		
	}
	
	nyh = ny;


	out = (fftwf_complex*)fftwf_malloc(sizeof(fftwf_complex) * nx * nyh);

	
	//for (int i = 0; i < 20; i++) {
		QueryPerformanceFrequency(&frequency);
		QueryPerformanceCounter(&start);
		plan_forward = fftwf_plan_many_dft(rank, n, howmany, in, inembed, istride, idist, out, onembed, ostride, odist, FFTW_FORWARD, FFTW_ESTIMATE);
		fftwf_execute(plan_forward);

		QueryPerformanceCounter(&end);
		interval = (double)(end.QuadPart - start.QuadPart) / frequency.QuadPart;
		cout << "[" << experi << "] " << interval * 1000.0 << " [ms]\n";
	//}
	// Save results for checking
	double amplitude;

	FILE *fp;
	char fn[100];
	sprintf(fn,"data_%d.bin",experi);
	fp = fopen(fn, "wb");
	if (fp) {
		// Write input real
		for (int i = 0; i < nx; i++) {
			for (int j = 0; j < ny; j++) {
				int idx = i*ny + j;
				fwrite(&in[idx][0], sizeof(double), 1, fp);
			}

		}
		// Write input imag
		for (int i = 0; i < nx; i++) {
			for (int j = 0; j < ny; j++) {
				int idx = i*ny + j;
				fwrite(&in[idx][1], sizeof(double), 1, fp);
			}

		}
		// Write output
		for (int i = 0; i < nx; i++) {
			for (int j = 0; j < ny; j++) {
				int idx = i*ny + j;
				amplitude = sqrt(out[idx][0] * out[idx][0] + out[idx][1] * out[idx][1]) / ny;
				fwrite(&amplitude, sizeof(double), 1, fp);
				//printf("%f\n", amplitude);
			}
		}
	}
	fclose(fp);
	free(freq);
	fftwf_destroy_plan(plan_forward);
	fftwf_free(in);
	fftwf_free(out);
}