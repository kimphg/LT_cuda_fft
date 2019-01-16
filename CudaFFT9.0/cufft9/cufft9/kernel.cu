//setx -m OPENCV_DIR D:\OpenCV\OpenCV331\opencv\build
//setx path "%path%;D:\OpenCV\OpenCV331\opencv\build\bin\Release\"
#include "device_launch_parameters.h"
//#include <opencv2/opencv.hpp>
#include <stdio.h>
#include <winsock2.h>
#include <windows.h>
#include <conio.h>
#include <tchar.h>
#define HAVE_REMOTE// for pcap
#include "pcap.h"
#define HR2D_PK//
#define FRAME_LEN 2048
#define OUTPUT_FRAME_SIZE FRAME_LEN*2+FRAME_HEADER_SIZE
#define FFT_SIZE_MAX 256
#define BANG_KHONG 0
int mFFTSize = 32;
#define FFT_STEP (mFFTSize / 4)

#define MAX_IREC 2400
#pragma comment(lib, "user32.lib")
#pragma comment (lib, "Ws2_32.lib")
//file mapping
#define FRAME_HEADER_SIZE 34
using namespace std;
bool isPaused = false;
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <cufft.h>
#include <cufftXt.h>
#include <stdio.h>
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
	int mMemSizeNen;
	int mMemSizeImage;
	int mTichLuySize;//16
	int mFrameLen;
	coreFFT(int frameLen, int ntichluy)
	{
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

u_char outputFrame[OUTPUT_FRAME_SIZE];

int iProcessing = 0, iReady = 50;
void packet_handler(u_char *param, const struct pcap_pkthdr *header, const u_char *pkt_data);
void pcapRun();


int mSocket;
struct sockaddr_in si_peter;
struct sockaddr_in si_capin;
void socketInit()
{
	WSADATA wsa;
	//Initialise winsock
	printf("\nInitialising Winsock...");
	if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0)
	{
		printf("Failed. Error Code : %d", WSAGetLastError());
		exit(EXIT_FAILURE);
	}
	printf("Initialised.\n");
	//init socket for UDP connect to Peter
	mSocket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);

	if (mSocket == SOCKET_ERROR)
	{
		printf("socket() failed with error code : %d", WSAGetLastError());
		exit(EXIT_FAILURE);
	}

	memset((char *)&si_capin, 0, sizeof(si_capin));
	si_capin.sin_family = AF_INET;
	si_capin.sin_port = htons(34566);//port "127.0.0.1"
	si_capin.sin_addr.S_un.S_addr = inet_addr("127.0.0.1");
	int ret = bind(mSocket, (struct sockaddr *)&si_capin, sizeof(struct sockaddr));
	if (ret == -1)
	{
		printf("Port busy");
		exit(EXIT_FAILURE);
	}
	//setup address structure
	memset((char *)&si_peter, 0, sizeof(si_peter));
	si_peter.sin_family = AF_INET;
	si_peter.sin_port = htons(31000);//port "127.0.0.1"
	si_peter.sin_addr.S_un.S_addr = inet_addr("127.0.0.1");

}
void socketDelete()
{
	closesocket(mSocket);
	WSACleanup();
}
void ProcessFrame(unsigned char*data, int len);

DWORD WINAPI ProcessDataBuffer(LPVOID lpParam);
DWORD WINAPI ProcessCommandBuffer(LPVOID lpParam);
void StartProcessing()
{
	CreateThread(
		NULL,                   // default security attributes
		0,                      // use default stack size  
		ProcessDataBuffer,       // thread function name
		NULL,          // argument to thread function 
		0,                      // use default creation flags 
		NULL);   // returns the thread identifier 
	CreateThread(
		NULL,                   // default security attributes
		0,                      // use default stack size  
		ProcessCommandBuffer,       // thread function name
		NULL,          // argument to thread function 
		0,                      // use default creation flags 
		NULL);   // returns the thread identifier 

}
coreFFT *mFFT;
FILE* pFile;
unsigned char buff[3000];

void ReplayData(const char* fileName)
{
	//char* mfileName = "C:\\Users\\Phuong-T1600\\Documents\\GitHub\\Peter\\VS\\x64\\Release\\raw_data_record_1538999224.dat";
	pFile = fopen(fileName, "rb");
	if (!pFile)
	{
		printf("\nfopen failed");
		return;
	}
	unsigned char len1, len2;
	unsigned long long dataSize = 0;
	while (!feof(pFile))
	{

		fread(&len1, 1, 1, pFile);
		fread(&len2, 1, 1, pFile);
		int len = (len1 << 8) | len2;
		printf("\ndatalen:%d", len);
		if (len > 3000)
		{
			printf("\nwrong datalen");
			break;
		}
		else if (len < 200)continue;
		fread(buff, 1, len, pFile);
		dataSize += len;
		ProcessFrame(buff, len);
		Sleep(5);
	}
	printf("\ntotal data sent:%d", dataSize);
}

int main(int argc, char **argv)
{

	/* start the capture */
	socketInit();
	mFFT = new coreFFT(FRAME_LEN, mFFTSize);
	StartProcessing();
	if (argc > 1)
	{
		char *fileName = argv[0];
		printf("\nreplay data file:");
		printf(fileName);
		ReplayData(fileName);
	}
	else pcapRun();

	return 0;
}
//precompiling code for FFT

// Complex data type


void pcapRun()
{
	pcap_if_t *alldevs;
	pcap_if_t *d;
	pcap_t *adhandle;
	char errbuf[PCAP_ERRBUF_SIZE];
	//
	/* Retrieve the device list on the local machine */
	if (pcap_findalldevs_ex((char*)PCAP_SRC_IF_STRING, NULL, &alldevs, errbuf) == -1)
	{
		//isRunning = false;
		printf(errbuf); return;
	}
	//isRunning = true;
	int i = 0;
	/* Print the list */
	for (d = alldevs; d; d = d->next)
	{
		printf("\n%d. %s", ++i, d->name);
		if (d->description)
			printf(" (%s)", d->description);
		else
			printf(" (No description available)");
	}
	d = alldevs;
	if ((adhandle = pcap_open(d->name,          // name of the device
		65536,            // portion of the packet to capture
		// 65536 guarantees that the whole packet will be captured on all the link layers
		PCAP_OPENFLAG_PROMISCUOUS,    // promiscuous mode
		1000,             // read timeout
		NULL,             // authentication on the remote machine
		errbuf            // error buffer
		)) == NULL)
	{
		/* Free the device list */
		pcap_freealldevs(alldevs);
		return;
	}
	printf("\nlistening on %s...\n", d->description);
	pcap_loop(adhandle, 0, packet_handler, NULL);
}
u_char dataOut[FRAME_LEN];
long int nFrames = 0;


char recvDatagram[1000];
DWORD WINAPI ProcessCommandBuffer(LPVOID lpParam)
{
	while (false)
	{
		int PeterAddrSize = sizeof (si_peter);
		int iResult = recvfrom(mSocket, recvDatagram, 1000, 0, (struct sockaddr *) &si_peter, &PeterAddrSize);
		if (iResult == SOCKET_ERROR) {
			wprintf(L"recvfrom failed with error %d\n", WSAGetLastError());
		}
	}
	return 0;
}
/*
int datatestI[MAX_IREC];
int datatestQ[MAX_IREC];
int datatestA[MAX_IREC];*/

DWORD WINAPI ProcessDataBuffer(LPVOID lpParam)
{


	while (true)
	{
		Sleep(1);
		while (iProcessing != iReady)
		{


			for (int ir = 0; ir < FRAME_LEN; ir++)
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
			int ia;
			for (int ir = 0; ir < FRAME_LEN; ir++)
			{
				ia = iProcessing;
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

			for (int i = 0; i < FRAME_LEN; i++)
			{
				float maxAmp = 0;
				int indexMaxFFT = 0;
				//for (int j = 0; j<FFT_SIZE_MAX; j++)
				int fftSkip = BANG_KHONG*mFFTSize / 16;
				for (int j = fftSkip; j < mFFTSize - fftSkip; j++)
				{
					float ampl = (ramSignalTL[i*mFFTSize + j].x * ramSignalTL[i*mFFTSize + j].x) + (ramSignalTL[i*mFFTSize + j].y * ramSignalTL[i*mFFTSize + j].y);
					if (ampl>maxAmp)
					{
						maxAmp = ampl;
						indexMaxFFT = j;
					}
				}
				float res = sqrt(double(maxAmp) / double(mFFTSize));
				if (res > 255)res = 255;
				outputFrame[i + FRAME_HEADER_SIZE] = res;// u_char(sqrt(float(maxAmp)) / float(FFT_SIZE_MAX));
				outputFrame[i + FRAME_LEN + FRAME_HEADER_SIZE] = u_char(indexMaxFFT*16.0 / (mFFTSize));
			}
			sendto(mSocket, (char*)outputFrame, OUTPUT_FRAME_SIZE, 0, (struct sockaddr *) &si_peter, sizeof(si_peter));
		}
		//jump to next period
		iProcessing++;
		if (iProcessing >= MAX_IREC)iProcessing = 0;


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

	if (pkt_header->len<200)return;
	int port = ((*(pkt_data + 36) << 8) | (*(pkt_data + 37)));
	if (port == 5000)
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
		fftID = newfftID;
		mFFTSize = pow(2.0, fftID + 2);
		if (mFFTSize > 512 || mFFTSize < 4)mFFTSize = 32;
		isPaused = true;
		Sleep(20);
		//if (mFFT)delete mFFT;
		mFFT = new coreFFT(FRAME_LEN, mFFTSize);
		Sleep(5);
		isPaused = false;
	}
	memcpy(dataBuff[iNext].header, data, FRAME_HEADER_SIZE);
	
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
		
		sendto(mSocket, (char*)data, len, 0, (struct sockaddr *) &si_peter, sizeof(si_peter));
		//isLastFrame = true;

	}
	else if (data[0] == 5) //5: 1024 byte tín hiệu giả L/tục (512 byte đầu là I, 512 byte sau là Q) 
	{
		memcpy(dataBuff[iNext].dataPM_I, data + FRAME_HEADER_SIZE, 512);
		memcpy(dataBuff[iNext].dataPM_Q, data + FRAME_HEADER_SIZE + 512, 512);
		dataBuff[iNext].dataLen = 512;
		isLastFrame = true;
	}
	else if (data[0] == 6) //6: 1024 byte sau kênh I tín hiệu xung đơn 
	{
		memcpy(dataBuff[iNext].dataPM_I, data + FRAME_HEADER_SIZE, 1024);
		dataBuff[iNext].dataLen = 1024;

	}
	else if (data[0] == 7) //7: 1024 byte sau kênh Q tín hiệu xung đơn 
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