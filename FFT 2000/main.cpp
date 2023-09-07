
#include <string>
#include <stdio.h>
#include <winsock2.h>
#include <windows.h>
#include <conio.h>
#include <tchar.h>
#include <math.h>
#include "fftw3.h"
#define HAVE_REMOTE// for pcap
#include "pcap.h"
#define HR2D_PK//
#define FRAME_LEN 2048
#define OUTPUT_FRAME_SIZE FRAME_LEN*2+FRAME_HEADER_SIZE
#define FFT_SIZE_MAX 256
#define BANG_KHONG 0
int mFFTSize = 8;
int mFFTDegree = 5;
int packetCount=0;
#define FFT_STEP (mFFTSize / 4)

#define MAX_IREC 2400
#pragma comment(lib, "user32.lib")
#pragma comment (lib, "Ws2_32.lib")
//file mapping
#define FRAME_HEADER_SIZE 34
fftwf_plan plan_forward ;
bool isPaused = false;
int changeCount = 0;
//#include "cuda_runtime.h"
//#include "device_launch_parameters.h"
//#include <cufft.h>
//#include <cufftXt.h>
#include <stdio.h>
//double *ramSignalTL;
double rawSignalx[MAX_IREC][FRAME_LEN];
double rawSignaly[MAX_IREC][FRAME_LEN];
//double ramImage[FRAME_LEN];
fftwf_complex *rawSignalFFT = 0;
fftwf_complex *rawSignalFFTout = 0;
using namespace std;
inline void FFT(double *x, double *y)//short int dir,long m,
{

}
//__global__ void complexMulKernel(cufftComplex *res, const cufftComplex *v1, const cufftComplex *v2)
//{
//	int i = threadIdx.x;
//	res[i].x = (v1[i].x * v2[i].x + v1[i].y * (v2[i].y));
//	res[i].y = (v1[i].x * (-v2[i].y) + v1[i].y * v2[i].x);
//}

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

int iProcessing = 0, iReady = 0;
void packet_handler(u_char *param, const struct pcap_pkthdr *header, const u_char *pkt_data);
void pcapRun();


int mSocket;
struct sockaddr_in si_peter;
struct sockaddr_in si_cabin;
struct sockaddr_in si_capin;
void socketInit()
{
    printf("socketInit\n");

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
    printf("Output port 31000");
    si_peter.sin_addr.S_un.S_addr = inet_addr("127.0.0.1");
    if (ret == -1)
    {
        printf("Port busy");
        Sleep(3000);
        exit(EXIT_FAILURE);
    }
    //forwarding socket
    memset((char *)&si_cabin, 0, sizeof(si_cabin));
    si_cabin.sin_family = AF_INET;
    si_cabin.sin_port = htons(1989);//port "127.0.0.1"
    si_cabin.sin_addr.S_un.S_addr = inet_addr("192.168.1.40");
    //    int ret = bind(mSocket, (struct sockaddr *)&si_capin, sizeof(struct sockaddr));
    printf("\nSocket initialized");_flushall();
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
    //    CreateThread(
    //                NULL,                   // default security attributes
    //                0,                      // use default stack size
    //                ProcessCommandBuffer,       // thread function name
    //                NULL,          // argument to thread function
    //                0,                      // use default creation flags
    //                NULL);   // returns the thread identifier
    printf("StartProcessing\n");_flushall();
}
FILE* pFile;
unsigned char buff[3000];
/*
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
*/
void HideConsole()
{
    ::ShowWindow(::GetConsoleWindow(), SW_HIDE);
}

void ShowConsole()
{
    ::ShowWindow(::GetConsoleWindow(), SW_SHOW);
}
int main(int argc, char** argv)
{

    /* start the capture */
    fftwf_init_threads();
    fftwf_plan_with_nthreads(6);
    socketInit();
    StartProcessing();

    printf("\nThreads started");
    pcapRun();
    getchar();
    _flushall();
    return 0;
}
//precompiling code for FFT

// Complex data type


void pcapRun()
{
    pcap_if_t *alldevs;
    pcap_if_t *d;
    pcap_if_t *adapter;
    pcap_t		*adhandle;
    char errbuf[PCAP_ERRBUF_SIZE];
    printf("\npcap_findalldevs_ex\n");
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
        std::string des(d->description);
        if (des.find(std::string("GbE")) != std::string::npos)
        {
            printf(" (Found GbE)");
            adapter=d;
        }
        if (des.find(std::string("Controller")) != std::string::npos)
        {
            printf(" (Found Controller)");
            adapter=d;
        }
    }_flushall();
    //    d = alldevs;
    if ((adhandle = pcap_open(adapter->name,          // name of the device
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
        _flushall();
        return;
    }
    printf("\nFFT listening on %s...\n", adapter->description);
    printf("FFT size = %d",mFFTSize);

    Sleep(1000);
    printf("\nAuto close in 3s");
    Sleep(1000);
    printf("\nAuto close in 2s");
    Sleep(1000);
    printf("\nAuto close in 1s");
    Sleep(1000);
    _flushall();
    //    HideConsole();
    pcap_loop(adhandle, 0, packet_handler, NULL);
}
u_char dataOut[FRAME_LEN];
long int nFrames = 0;


char recvDatagram[1000];
DWORD WINAPI ProcessCommandBuffer(LPVOID lpParam)
{
    unsigned char watchDog[] = { 0xAA, 0xAA, 0xAA, 0xAA, 0xAA };
    while (true)
    {
        Sleep(1000);
        sendto(mSocket, (char*)watchDog, 4, 0, (struct sockaddr *) &si_peter, sizeof(si_peter));

        /*int PeterAddrSize = sizeof (si_peter);
        int iResult = recvfrom(mSocket, recvDatagram, 1000, 0, (struct sockaddr *) &si_peter, &PeterAddrSize);
        if (iResult == SOCKET_ERROR) {
        //wprintf(L"recvfrom failed with error %d\n", WSAGetLastError());
        }*/
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

        while(rawSignalFFT==NULL);
        while (iProcessing != iReady)
        {

            int dataLen = dataBuff[iProcessing].dataLen;
            for (int ir = 0; ir < dataLen; ir++)
            {
                rawSignalx[iProcessing][ir] = (dataBuff[iProcessing].dataPM_I[ir]);
                rawSignaly[iProcessing][ir] = (dataBuff[iProcessing].dataPM_Q[ir]);
            }
            if (!dataBuff[iProcessing].isToFFT || isPaused)
            {
                //skip to next data frame
                iProcessing++;
                if (iProcessing >= MAX_IREC)iProcessing = 0;
                continue;
            }
            for (int ir = 0; ir < dataLen; ir++)
            {
                int ia = iProcessing;
                for (int i = 0; i < mFFTSize; i++)
                {
                    rawSignalFFT[ir*mFFTSize + i][0] = rawSignalx[ia][ir];
                    rawSignalFFT[ir*mFFTSize + i][1] = rawSignaly[ia][ir];
                    ia--;
                    if (ia < 0)ia += MAX_IREC;
                }
            }
            if(packetCount>100){
                fftwf_execute(plan_forward);

                //generate output data frame
                memcpy(outputFrame, dataBuff[iProcessing].header, FRAME_HEADER_SIZE);
                int fftSkip = BANG_KHONG*mFFTSize / 16;
                for (int i = 0; i < dataLen; i++)
                {
                    double maxAmp = 0;
                    int indexMaxFFT = 0;
                    for (int j = fftSkip; j < mFFTSize - fftSkip; j++)
                    {
                        int pt = i*mFFTSize + j;
                        float ax = rawSignalFFTout[pt][0];
                        float ay = rawSignalFFTout[pt][1];
                        double ampl = (ax*ax) + (ay*ay);
                        if (ampl>maxAmp)
                        {
                            maxAmp = ampl;
                            indexMaxFFT = j;
                        }
                    }
                    double res = sqrt(maxAmp / float(mFFTSize));
                    if (res > 255)res = 255;
                    outputFrame[i + FRAME_HEADER_SIZE] = u_char(res);// u_char(sqrt(float(maxAmp)) / float(FFT_SIZE_MAX));
                    outputFrame[i + FRAME_LEN + FRAME_HEADER_SIZE] = u_char(indexMaxFFT*16.0 / (mFFTSize));
                }
                for (int i = dataLen; i < FRAME_LEN; i++)
                {
                    outputFrame[i + FRAME_HEADER_SIZE] = 0;
                    outputFrame[i + FRAME_LEN + FRAME_HEADER_SIZE] = 0;
                }
                sendto(mSocket, (char*)outputFrame, OUTPUT_FRAME_SIZE, 0, (struct sockaddr *) &si_peter, sizeof(si_peter));
            }
            iProcessing++;
            if (iProcessing >= MAX_IREC)iProcessing = 0;

            packetCount++;
            if(packetCount<100)printf(".");
            //jump to next period
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
    int port = ((*(pkt_data + 36) << 8) | (*(pkt_data + 37)));
    //    if(port!=31000)return;
    //    if(port!=1989)sendto(mSocket, (char*)pkt_data, pkt_header->len, 0, (struct sockaddr *) &si_cabin, sizeof(si_cabin));
    //    if (
    //            ((*(pkt_data + 6)) == 0) &&
    //            ((*(pkt_data + 7)) == 0x12) &&
    //            ((*(pkt_data + 8)) == 0x34)

    //            )
    //    {
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

    //    }



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
void fftInit()
{

    if (changeCount>0){
        fftwf_free(rawSignalFFT);
        fftwf_free(rawSignalFFTout);
        fftwf_destroy_plan(plan_forward);
        Sleep(500);
    }
    changeCount++;
    rawSignalFFT = (fftwf_complex*)fftwf_malloc(sizeof(fftwf_complex) * mFFTSize * FRAME_LEN);//new fftwf_complex[mFFTSize*FRAME_LEN];

    rawSignalFFTout = (fftwf_complex*)fftwf_malloc(sizeof(fftwf_complex) * mFFTSize * FRAME_LEN);//new fftwf_complex[mFFTSize*FRAME_LEN];
    plan_forward = fftwf_plan_many_dft(1,&mFFTSize,FRAME_LEN,rawSignalFFT,\
                                       &mFFTSize,1,mFFTSize,rawSignalFFTout,&mFFTSize,1,mFFTSize,FFTW_FORWARD,FFTW_ESTIMATE);
    packetCount=0;
}
static int fftID = -1;

void ProcessFrame(unsigned char*data, int len)
{
    //    printf("frame input\n");
    int iNext = iReady + 1;
    if (iNext >= MAX_IREC)iNext = 0;
    int newfftID = data[22];
    if (fftID != newfftID)
    {

        if (newfftID > 10 || newfftID < 0)
        {
            printf("\nWrong fftID:%d",newfftID);
            return;
        }
        fftID = newfftID;
        mFFTDegree = fftID ;
        mFFTSize = pow(2.0, mFFTDegree);

        if (mFFTSize > 512 || mFFTSize < 4)mFFTSize = 4;
        isPaused = true;
        printf("FFT size = %d",mFFTSize);
        Sleep(200);
        fftInit();
        Sleep(200);
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
