
#include "device_launch_parameters.h"
//#include <opencv2/opencv.hpp>
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
#define HAVE_REMOTE// for pcap
#include <pcap.h> /* if this gives you an error try pcap/pcap.h */
#define HR2D_PK//
#define FRAME_LEN 2048
#define OUTPUT_FRAME_SIZE FRAME_LEN*2+FRAME_HEADER_SIZE
#define FFT_SIZE_MAX 256
#define BANG_KHONG 0
int mFFTSize = 32;
#define FFT_STEP (mFFTSize / 4)

#define MAX_IREC 2400
//file mapping
#define FRAME_HEADER_SIZE 34
using namespace std;
bool isPaused = false;
// includes, system
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "udpclient.h"
// includes, project
#include <cuda_runtime.h>
#include <cufft.h>
#include <cufftXt.h>

cufftComplex *ramSignalTL;
cufftComplex ramSignalNen[MAX_IREC][FRAME_LEN];
cufftComplex ramImage[FRAME_LEN];
__global__ void complexMulKernel(cufftComplex *res, const cufftComplex *v1, const cufftComplex *v2)
{
	int i = threadIdx.x;
	res[i].x = (v1[i].x * v2[i].x + v1[i].y * (v2[i].y));
	res[i].y = (v1[i].x * (-v2[i].y) + v1[i].y * v2[i].x);
}
class coreFFT
{
public:

	bool isActive;
	cufftHandle planTL;
	//cufftHandle planNenTH;
	//cufftHandle planImageFFT;
	cufftComplex *dSignalTL;
	//cufftComplex *dSignalNenRes;
	//cufftComplex *dSignalNen;
	//cufftComplex *dImageNen;
	int mMemSizeTL;
	//int mMemSizeImage;
	int mTichLuySize;//16
	int mFrameLen;
	coreFFT(int frameLen, int ntichluy)
	{
		isActive = false;
		cudaError_t cudaStatus;

		// Choose which GPU to run on, change this on a multi-GPU system.
		cudaStatus = cudaSetDevice(0);
		if (cudaStatus != cudaSuccess) {
			fprintf(stderr, "cudaSetDevice failed!  Do you have a CUDA-capable GPU installed?");
			isActive = false;
			return;
		}
		else
		{
			printf("\ncudaSetDevice on ");
			printf("\ncuda fft size:%d", ntichluy);
			printf("\nFFT ratio:1/%d", FFT_STEP);
		}
		mFrameLen = frameLen;
		mTichLuySize = ntichluy;
		mMemSizeTL = sizeof(cufftComplex)* mTichLuySize*frameLen;
		if (cufftPlan1d(&planTL, mTichLuySize, CUFFT_C2C, frameLen) != CUFFT_SUCCESS)
		{
			printf("\nFFT planTL failed to init");
			isActive = false;
			return;
		}
		ramSignalTL = new cufftComplex[FRAME_LEN*mTichLuySize];
		// Allocate device memory for signal tich luy
		cudaMalloc((void **)&dSignalTL, mMemSizeTL);
		isActive = true;
	}
	void exeFFTTL(cufftComplex *h_signal)
	{
		cudaMemcpy(dSignalTL, h_signal, mMemSizeTL, cudaMemcpyHostToDevice);
		cufftExecC2C(planTL, dSignalTL, dSignalTL, CUFFT_FORWARD);

		if (cudaGetLastError() != cudaSuccess) {
			fprintf(stderr, "FFT kernel launch failed: %s\n", cudaGetErrorString(cudaGetLastError()));
			return;
		}
		cudaMemcpy(h_signal, dSignalTL, mMemSizeTL, cudaMemcpyDeviceToHost);
	}
	/*void exeFFTNen(cufftComplex *h_signal, cufftComplex* h_image)
	{
	//move signal to gpu and process fft forward
	cudaMemcpy(dSignalNen, h_signal, mMemSizeNen, cudaMemcpyHostToDevice);
	cufftExecC2C(planNenTH, dSignalNen, dSignalNen, CUFFT_FORWARD);
	//move image to gpu and process fft forward
	cudaMemcpy(dImageNen, h_image, mMemSizeNen, cudaMemcpyHostToDevice);
	cufftExecC2C(planNenTH, dImageNen, dImageNen, CUFFT_FORWARD);
	// Element wise complext multiplication
	for (int i = 0; i < mFrameLen; i += 1024)
	{
	complexMulKernel << <1, 1024 >> >(dSignalNenRes+i, dSignalNen+i, dImageNen+i);
	}

	cufftExecC2C(planNenTH, dSignalNenRes, dSignalNenRes, CUFFT_FORWARD);

	cudaMemcpy(h_signal, dSignalNenRes, mMemSizeNen, cudaMemcpyDeviceToHost);
	}*/
	~coreFFT()
	{
		delete[] ramSignalTL;
		cufftDestroy(planTL);
		//cufftDestroy(planNenTH);
		// cleanup memory
		cudaFree(dSignalTL);
		printf("\nmemory clear");
		//cudaFree(dSignalNen);
		//cudaFree(dImageNen);
	}
};
//_______________________________________________________________________

struct DataFrame// buffer for data frame
{
	char header[FRAME_HEADER_SIZE];
	char dataPM_I[FRAME_LEN];
	char dataPM_Q[FRAME_LEN];
	short dataLen;
	bool isToFFT;
} dataBuff[MAX_IREC];
//unsigned int gyroValue = 0;
udp_client_server::udp_client mUdp("127.0.0.1",31000);
u_char outputFrame[OUTPUT_FRAME_SIZE];

int iProcessing = 0, iReady = 50;
void packet_handler(u_char *param, const struct pcap_pkthdr *header, const u_char *pkt_data);
void pcapRun();

int mSocket;
void ProcessFrame(unsigned char*data, int len);

void *ProcessDataBuffer(void*);
void *ProcessCommandBuffer(void*);
pthread_t thread1,thread2;
void StartProcessing()
{
	pthread_create(&thread1,NULL,ProcessDataBuffer,NULL);
	pthread_create(&thread2,NULL,ProcessCommandBuffer,NULL);
}
coreFFT *mFFT;
FILE* pFile;
unsigned char buff[3000];


int main(int argc, char **argv)
{

	/* start the capture */
	mFFT = new coreFFT(FRAME_LEN, mFFTSize);

	StartProcessing();
	pcapRun();
	printf("\nNo interface available");
	getchar();

	return 0;
}

// Complex data type

void pcapRun()
{
	char error_buffer[PCAP_ERRBUF_SIZE];
	pcap_t *handle;
	int timeout_limit = 10000; /* In milliseconds */

	pcap_if_t *interfaces,*temp;
	int i=0;
	if(pcap_findalldevs(&interfaces,error_buffer)==-1)
	{
		printf("\nerror in pcap findall devs");
		return ;
	}

	printf("\n the interfaces present:");
	for(temp=interfaces;temp;temp=temp->next)
	{
		printf("\n%d  :  %s",i++,temp->name);

	}
	printf("\nOpen device to read:");
	if(pcap_findalldevs(&interfaces,error_buffer)==-1)
	{
		printf("\nerror in pcap findall devs");
		return ;
	}
	printf(" %s",interfaces->name);
	/* Open device for live capture */
	handle = pcap_open_live(
			interfaces->name,
			BUFSIZ,
			0,
			timeout_limit,
			error_buffer
		);
	if (handle == NULL) {
		 fprintf(stderr, "Could not open device: %s\n", error_buffer);
		 return ;
	 }

	pcap_loop(handle,NULL, packet_handler, NULL);
	    return ;
}
u_char dataOut[FRAME_LEN];
long int nFrames = 0;


char recvDatagram[1000];
void *ProcessCommandBuffer(void*)
{
	unsigned char watchDog[] = { 0xAA, 0xAA, 0xAA, 0xAA, 0xAA };
	while (true)
	{
		usleep(1000000);
		mUdp.send((char*)watchDog,4);
		//sendto(mSocket, (char*)watchDog, 4, 0, (struct sockaddr *) &si_peter, sizeof(si_peter));

		/*int PeterAddrSize = sizeof (si_peter);
		int iResult = recvfrom(mSocket, recvDatagram, 1000, 0, (struct sockaddr *) &si_peter, &PeterAddrSize);
		if (iResult == SOCKET_ERROR) {
			//wprintf(L"recvfrom failed with error %d\n", WSAGetLastError());
		}*/
	}

}
/*
int datatestI[MAX_IREC];
int datatestQ[MAX_IREC];
int datatestA[MAX_IREC];*/

void *ProcessDataBuffer(void*)
{
	while (true)
	{
		usleep(1000);
		while (iProcessing != iReady)
		{

			int dataLen = dataBuff[iProcessing].dataLen;
			for (int ir = 0; ir < dataLen; ir++)
			{

				//ramSignalNen[iProcessing][ir].x = sqrt(double(dataBuff[iProcessing].dataPM_I[ir] * dataBuff[iProcessing].dataPM_I[ir] + dataBuff[iProcessing].dataPM_Q[ir] * dataBuff[iProcessing].dataPM_Q[ir]));//int(dataBuff[iProcessing].dataPM_I[ir]);
				ramSignalNen[iProcessing][ir].x = float(dataBuff[iProcessing].dataPM_I[ir]);
				ramSignalNen[iProcessing][ir].y = float(dataBuff[iProcessing].dataPM_Q[ir]);//0;//
				//ramSignalNen[iProcessing][ir].y = 0;
			}
			if (!dataBuff[iProcessing].isToFFT || isPaused)
			{
				//jump to next period
				iProcessing++;
				if (iProcessing >= MAX_IREC)iProcessing = 0;
				continue;
			}
			for (int ir = 0; ir < dataLen; ir++)
			{
				int ia = iProcessing;
				for (int i = 0; i < mFFTSize; i++)
				{
					ramSignalTL[ir*mFFTSize + i] = ramSignalNen[ia][ir];
					ia--;
					if (ia < 0)ia += MAX_IREC;
				}
			}
			// perform fft
			if (mFFT->isActive)mFFT->exeFFTTL((cufftComplex*)ramSignalTL);
			//dataBuff[iProcessing].header[32] = gyroValue >> 8;
			//dataBuff[iProcessing].header[33] = gyroValue;

			memcpy(outputFrame, dataBuff[iProcessing].header, FRAME_HEADER_SIZE);
			int fftSkip = BANG_KHONG*mFFTSize / 16;
			for (int i = 0; i < dataLen; i++)
			{
				double maxAmp = 0;
				int indexMaxFFT = 0;
				//for (int j = 0; j<FFT_SIZE_MAX; j++)

				for (int j = fftSkip; j < mFFTSize - fftSkip; j++)
				{
					double ampl = (ramSignalTL[i*mFFTSize + j].x * ramSignalTL[i*mFFTSize + j].x) + (ramSignalTL[i*mFFTSize + j].y * ramSignalTL[i*mFFTSize + j].y);
					if (ampl>maxAmp)
					{
						maxAmp = ampl;
						indexMaxFFT = j;
					}
				}
				double res = sqrt(double(maxAmp) / double(mFFTSize));
				if (res > 255)res = 255;
				outputFrame[i + FRAME_HEADER_SIZE] = u_char(res);// u_char(sqrt(float(maxAmp)) / float(FFT_SIZE_MAX));
				outputFrame[i + FRAME_LEN + FRAME_HEADER_SIZE] = u_char(indexMaxFFT*16.0 / (mFFTSize));
			}
			for (int i = dataLen; i < FRAME_LEN; i++)
			{
				outputFrame[i + FRAME_HEADER_SIZE] = 0;
				outputFrame[i + FRAME_LEN + FRAME_HEADER_SIZE] = 0;
			}
			mUdp.send( (char*)outputFrame, OUTPUT_FRAME_SIZE);
			//jump to next period
			iProcessing++;
			if (iProcessing >= MAX_IREC)iProcessing = 0;
		}



	}



}

#define UDP_HEADER_LEN 42
void packet_handler(u_char *param, const struct pcap_pkthdr *pkt_header, const u_char *pkt_data)
{
	//    struct tm ltime;
	//    char timestr[16];
	//    time_t local_tv_sec;

	/*
	* unused variables
	*/
	//    (VOID)(param);
	//    (VOID)(pkt_data);

	/* convert the timestamp to readable format */
	//    local_tv_sec = header->ts.tv_sec;
	//    localtime_s(&ltime, &local_tv_sec);
	//    strftime( timestr, sizeof timestr, "%H:%M:%S", &ltime);
	if (pkt_header->len<1000)return;
	//int port = ((*(pkt_data + 36) << 8) | (*(pkt_data + 37)));

	if (
		((*(pkt_data + 6)) == 0) &&
		((*(pkt_data + 7)) == 0x12) &&
		((*(pkt_data + 8)) == 0x34)

		)
	{
		/*
		+ 0: 1024 byte đầu kênh I
		+ 1: 1024 byte sau kênh I
		+ 2: 1024 byte đầu kênh Q
		+ 3: 1024 byte sau kênh Q
		+ 4: 256 byte máy hỏi
		+ 5: 1024 byte tín hiệu giả L/tục (512 byte đầu là I, 512 byte sau là Q)
		+ 6: 1024 byte sau kênh I tín hiệu xung đơn
		+ 7: 1024 byte sau kênh Q tín hiệu xung đơn

		*/
		u_char* data = (u_char*)pkt_data + UDP_HEADER_LEN;
		ProcessFrame(data, pkt_header->len);


	}

}
/*void packet_handler_compress(u_char *param, const struct pcap_pkthdr *pkt_header, const u_char *pkt_data)
{
if (pkt_header->len<1000)return;
if (((*(pkt_data + 36) << 8) | (*(pkt_data + 37))) != 5000)
{
return;
}
u_char* data = (u_char*)pkt_data + UDP_HEADER_LEN;
if (data[0] == 0)		//I chanel first part
{
iReady++;
if (iReady >= MAX_IREC)iReady = 0;
memcpy(dataBuff[iReady].header, data, FRAME_HEADER_SIZE);
memcpy(dataBuff[iReady].dataPM_I, data + FRAME_HEADER_SIZE, 1024);
}
else if (data[0] == 2) //Q chanel first part
{
memcpy(dataBuff[iReady].dataPM_Q, data + FRAME_HEADER_SIZE, 1024);
}
else if (data[0] == 1) //I chanel second part
{
memcpy(dataBuff[iReady].dataPM_I + 1024, data + FRAME_HEADER_SIZE, 1024);
}
else if (data[0] == 3) //Q chanel second part
{
memcpy(dataBuff[iReady].dataPM_Q + 1024, data + FRAME_HEADER_SIZE, 1024);
}
return;
}*/
/*
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   STT |   Byte    |   Chức                                              |
|       |           |   năng                                              |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   1   |   0       |   Id gói                                            |
|       |           |   tin:                                              |
|       |           |   0,1,2,3:                                          |
|       |           |   iq th mã pha (mỗi kênh 2048 byte)                 |
|       |           |   4: 256                                            |
|       |           |   byte máy hỏi, mỗi bít một o_cu_ly                 |
|       |           |   5: iq th                                          |
|       |           |   giả liên tục, 512 byte i, 512 byte q              |
|       |           |   6,7: iq                                           |
|       |           |   cho tín hiệu xung đơn, mỗi kênh 1024 byte         |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   2   |   1, 2, 3 |   Byte cho                                          |
|       |           |   báo hỏng:                                         |
|       |           |   1: loại                                           |
|       |           |   mô-đun, (0, 1, 2, 3)                              |
|       |           |   2: Loại                                           |
|       |           |   tham số (bb, cc, dd)                              |
|       |           |   3: Tham                                           |
|       |           |   số mô-đun                                         |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   3   |   4       |   Phân giải                                         |
|       |           |   ra đa: 0 (15m), 1 (30m)......                     |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   4   |   5,6     |   Loại tín                                          |
|       |           |   hiệu phát và tham số:                             |
|       |           |   5: loại                                           |
|       |           |   th phát (0: xung đơn; 1: mã pha; 2: giả ltuc)     |
|       |           |   6: tham                                           |
|       |           |   số cho loại th trên                               |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   5   |   7,8     |   Hai byte                                          |
|       |           |   trung bình tạp máy thu (ktra báo hỏng tuyến thu)  |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   6   |   9, 10,  |   4 byte                                            |
|       |   11, 12  |   quay an-ten                                       |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   7   |   13, 14  |   Hai byte                                          |
|       |           |   hướng tàu                                         |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   8   |   15, 16  |   Hai byte                                          |
|       |           |   hướng mũi tàu                                     |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   9   |   17, 18  |   Hai byte                                          |
|       |           |   tốc độ tàu                                        |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   10  |   19      |   Thông                                             |
|       |           |   báo chế độ chủ đông - bị động, tốc độ quay an-ten |
|       |           |   - bít thấp                                        |
|       |           |   thông báo cđ-bđ (1: chủ động)                     |
|       |           |   - 4 bít                                           |
|       |           |   cao là tốc độ an-ten                              |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   11  |   20      |   Thông                                             |
|       |           |   báo tần số phát và đặt mức tín hiệu:              |
|       |           |   - 4 bít                                           |
|       |           |   cuối là tần số phát                               |
|       |           |   - 4 bít                                           |
|       |           |   cao là đặt mức th                                 |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   12  |   21      |   Thông                                             |
|       |           |   báo chọn thang cự ly và bật/tắt AM2:              |
|       |           |   - 4 bít                                           |
|       |           |   cuối là thang cự ly (0: 2 lý; 1: 4 lý.....)       |
|       |           |   - 4 bít                                           |
|       |           |   cao là báo bật/tắt AM2: 0: tắt, 1: bật            |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
|       |           |                                                     |
|   13  |   22      |   Thông                                             |
|       |           |   báo số điểm FFT:                                  |
|       |           |   1(fft8);                                          |
|       |           |   2(fft16) ;...;32(fft256)                          |
|       |           |                                                     |
+-------+-----------+-----------------------------------------------------+
Id gói                                            |
|       |           |   tin:                                              |
|       |           |   0,1,2,3:                                          |
|       |           |   iq th mã pha (mỗi kênh 2048 byte)                 |
|       |           |   4: 256                                            |
|       |           |   byte máy hỏi, mỗi bít một o_cu_ly                 |
|       |           |   5: iq th                                          |
|       |           |   giả liên tục, 512 byte i, 512 byte q              |
|       |           |   6,7: iq                                           |
|       |           |   cho tín hiệu xung đơn, mỗi kênh 1024 byte
*/
static int fftID = -1;
void ProcessFrame(unsigned char*data, int len)
{
	int iNext = iReady + 1;
	if (iNext >= MAX_IREC)iNext = 0;
	int newfftID = data[22];
	if(fftID!=newfftID)
	{
		if (newfftID > 8 || newfftID < 0)
		{
			printf("\nWrong fftID");
			return;
		}
		fftID = newfftID;
		mFFTSize = pow(2.0, fftID + 2);
		if (mFFTSize > 512 || mFFTSize < 4)mFFTSize = 32;
		isPaused = true;

		usleep(100000);
		iProcessing = iReady;
		if (mFFT)
		{
			delete mFFT;
		}
		mFFT = new coreFFT(FRAME_LEN, mFFTSize);

		usleep(50000);
		isPaused = false;
	}
	memcpy(dataBuff[iNext].header, data, FRAME_HEADER_SIZE);

	//printf("data[0]=%d\n", data[0]);
	bool isLastFrame = false;
	if (data[0] == 0)		//0: 1024 byte đầu kênh I
	{
		//memcpy(dataBuff[iNext].header, data, FRAME_HEADER_SIZE);
		memcpy(dataBuff[iNext].dataPM_I, data + FRAME_HEADER_SIZE, 1024);
	}
	else if (data[0] == 1) //1: 1024 byte sau kênh I
	{
		memcpy(dataBuff[iNext].dataPM_I + 1024, data + FRAME_HEADER_SIZE, 1024);

	}
	else if (data[0] == 2) //2: 1024 byte đầu kênh Q
	{
		memcpy(dataBuff[iNext].dataPM_Q, data + FRAME_HEADER_SIZE, 1024);

	}
	else if (data[0] == 3) //3: 1024 byte sau kênh Q
	{
		memcpy(dataBuff[iNext].dataPM_Q + 1024, data + FRAME_HEADER_SIZE, 1024);
		dataBuff[iNext].dataLen = FRAME_LEN;
		isLastFrame = true;

	}
	else if (data[0] == 4) //4: máy hỏi
	{

		mUdp.send( (char*)data, len);

		//isLastFrame = true;

	}
	else if (data[0] == 5) //5: 1024 byte tín hiệu giả L/tục (512 byte đầu là I, 512 byte sau là Q)
	{
		memcpy(dataBuff[iNext].dataPM_I, data + FRAME_HEADER_SIZE, 512);
		memcpy(dataBuff[iNext].dataPM_Q, data + FRAME_HEADER_SIZE + 512, 512);
		dataBuff[iNext].dataLen = 512;
		isLastFrame = true;
	}
	else if (data[0] == 6) //6: 1024 byte kênh I tín hiệu xung đơn
	{
		memcpy(dataBuff[iNext].dataPM_I, data + FRAME_HEADER_SIZE, 1024);
		dataBuff[iNext].dataLen = 1024;

	}
	else if (data[0] == 7) //7: 1024 byte kênh Q tín hiệu xung đơn
	{
		memcpy(dataBuff[iNext].dataPM_Q, data + FRAME_HEADER_SIZE, 1024);
		dataBuff[iNext].dataLen = 1024;
		isLastFrame = true;

	}
	if (isLastFrame)
	{
		iReady++;
		dataBuff[iNext].isToFFT = ((iNext%FFT_STEP) == 0);
		if (iReady >= MAX_IREC)iReady = 0;
	}
	return;

}
