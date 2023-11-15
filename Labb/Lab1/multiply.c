#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <arm_neon.h>
#include <pthread.h>

#define NUM_THREADS 2

typedef struct {
		int threadId;
		int start;
		int end;
		float* vectora;
		float* vectorb;
		float* vectorr;
} workInfo;

void mult_std(float* a, float* b, float* r, int num, int i)
{
	while ( i < num )
	{
		i++;
		r[i] = a[i] * b[i];
	}
	/*
	for (int i = 0; i < num; i++)
	{
		r[i] = a[i] * b[i];
	}*/
}

// delat på två för att beräkna nedre delen, i = num/2 till num för andra delen på halvan?
void mult_vect(float* a, float* b, float* r, int num)
{
	float32x4_t va, vb, vr;
	for (int i = 0; i < num; i +=4)
	{
		va = vld1q_f32(&a[i]);
		vb = vld1q_f32(&b[i]);
		vr = vmulq_f32(va, vb);
		vst1q_f32(&r[i], vr);
	}
}

// Thread function
void* calcVect(void* workStruct) {
	workInfo* work = (workInfo*)workStruct;
	mult_std(work->vectora, work->vectorb, work->vectorr, work->end, work->start);
	
	pthread_exit(NULL);
	return NULL; // This line is typically not reached due to pthread_exit above.
}

int main(int argc, char *argv[]) {

	int num = 100000000;

	float *a = (float*)aligned_alloc(16, num*sizeof(float));
	float *b = (float*)aligned_alloc(16, num*sizeof(float));
	float *r = (float*)aligned_alloc(16, num*sizeof(float));
	for (int i = 0; i < num; i++)
	{
		a[i] = (i % 127)*0.1457f;
		b[i] = (i % 331)*0.1231f;
	}

	// ADDED CODE #1 STARTS

	int rc;

	
	workInfo array[NUM_THREADS];

	array[0].start = 0;
	array[0].threadId = 0;
	array[0].end = num/2;
	array[0].vectora = a;
	array[0].vectorb = b;
	array[0].vectorr = r;

	array[1].start = num/2 + 1;
	array[1].threadId = 1;
	array[1].end = num;
	array[1].vectora = a;
	array[1].vectorb = b;
	array[1].vectorr = r;

	pthread_t threads[NUM_THREADS];

	struct timespec ts_start;
	struct timespec ts_end_1;
	struct timespec ts_end_2;
	clock_gettime(CLOCK_MONOTONIC, &ts_start);

	for(long t = 0; t < NUM_THREADS; t++) {
		printf("Creating thread %ld\n", t);
		rc = pthread_create(&threads[t], NULL, calcVect, (void*)&array[t]);
		if(rc) {
			printf("Error: Unable to create thread, %d\n", rc);
			exit(-1);
		}
	}

	// ADDED CODE #1 ENDS

	
	
	//Join threads before calculating time?

	// Join the threads
	for(long t = 0; t < NUM_THREADS; t++) {
		pthread_join(threads[t], NULL);
	}

	
	//mult_std(a, b, r, num);

	clock_gettime(CLOCK_MONOTONIC, &ts_end_1);
	//mult_vect(a, b, r, num);

	clock_gettime(CLOCK_MONOTONIC, &ts_end_2);

	double duration_std = (ts_end_1.tv_sec - ts_start.tv_sec) +
			      (ts_end_1.tv_nsec - ts_start.tv_nsec) * 1e-9;
	double duration_vec = (ts_end_2.tv_sec - ts_end_1.tv_sec) +
			      (ts_end_2.tv_nsec - ts_end_1.tv_nsec) * 1e-9;

	printf("Elapsed time std: %f\n", duration_std);
	printf("Elapsed time vec: %f\n", duration_vec);

	free(a);
	free(b);
	free(r);
	
	// ADDED CODE #2 STARTS

	// Join the threads 
/*
	for(long t = 0; t < NUM_THREADS; t++) {
		pthread_join(threads[t], NULL);
	}
*/
	printf("Main thread completing\n");

	// ADDED CODE #2 ENDS
	return 0;
}
