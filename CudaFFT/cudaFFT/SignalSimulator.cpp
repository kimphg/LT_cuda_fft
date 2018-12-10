// SignalSimulator.cpp : Defines the entry point for the console application.
//

#include "stdafx.h"
#include "c_target.h"

#include <winsock2.h>
#include <windows.h>
#include <random>
#pragma comment (lib, "Ws2_32.lib")
int mSocket;
unsigned char n_clk_adc = 0;
double rResolution = 0.015070644;
struct sockaddr_in si_peter;
struct sockaddr_in si_capin;
u_char outputFrame[MAX_AZI][OUTPUT_FRAME_SIZE];
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
	si_capin.sin_port = htons(12345);//port "127.0.0.1"
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
void regenerate(int azi)
{
	u_char* dataPointer = &outputFrame[azi][0] + FRAME_HEADER_SIZE;
	for (int i = 0; i < FRAME_LEN; i++)
	{
		int num = int(distribNoise(generator));
		if (num < 0)num = 0;
		dataPointer[i] = num;
	}
	for (int i = FRAME_LEN; i < FRAME_LEN * 2; i++)
	{
		dataPointer[i] = rand()%16;
	}
}
#define NUM_OF_TARG 10
target_t* target[NUM_OF_TARG];			

void initTargets()
{
	//target[0] = new target_t(250, -300, 4, 100,4);
	for (int i = 0; i < NUM_OF_TARG; i++)
	{
		target[i] = new target_t(
			(rand() % 400)/10.0 + 10,//x
			(rand() % 400)/10.0 - 20,//y
			((rand() % 20) +15),//speed
			rand() % 90,//heading
			i);
	}
	
	//target[2] = new target_t(200, -300, 4, 110,8);
	//target[3] = new target_t(200, -350, 4, 80,5);
}
void updateTargets()
{
	for (int i = 0; i < NUM_OF_TARG; i++)
	{
		target[i]->update();
	}
}
int _tmain(int argc, _TCHAR* argv[])
{ 
	socketInit();
	int azi = 200;
	for (int i = 0; i < MAX_AZI; i++)
	{
		regenerate(i);
		outputFrame[i][2] = i >> 8;
		outputFrame[i][3] = i;
	}
	initTargets();
	int dazi = 1;
	int nPeriod = 0;
	n_clk_adc = 1;
	rResolution = 0.015070644 * pow(2, n_clk_adc);
	while (true)
	{
		
		
		Sleep(8);
		azi += dazi;
		/*if (azi >= 2048)
		{
			nPeriod++;
			if (nPeriod > 50)
			{
				nPeriod = 0;
				//initTargets();
			}
			if (nPeriod == 20)
			{
				n_clk_adc = 2;
				rResolution = 0.015070644 * pow(2, n_clk_adc);
				
				
			}
			if (nPeriod == 50)
			{
				return 0;


			}
			azi = 0;
			updateTargets();
		}*/
		
		if (azi>= 1000)
		{
			nPeriod++;
			dazi = -1;
			updateTargets();
			Sleep(500);
		}
		else
		if (azi <= 2)
		{
			dazi = 1;
			updateTargets();
			Sleep(500);
		}
		//if (rand() % 10 == 0)regenerate(azi);
		/*if (rand() % 10 == 0)
		{
			memset((char*)(&outputFrame[azi][0]), 0, OUTPUT_FRAME_SIZE);
		}*/
		outputFrame[azi][0] = 0x55;
		outputFrame[azi][2] = azi >> 8;
		outputFrame[azi][3] = azi;
		outputFrame[azi][4] = n_clk_adc;
		
		sendto(mSocket, (char*)(&outputFrame[azi][0]), OUTPUT_FRAME_SIZE, 0, (struct sockaddr *) &si_peter, sizeof(si_peter));
		//outputFrame[azi][0] = 2;
		//sendto(mSocket, (char*)(&outputFrame[azi][0]), OUTPUT_FRAME_SIZE, 0, (struct sockaddr *) &si_peter, sizeof(si_peter));
		//regenerate(azi);
	}
	socketDelete();
	return 0;
}

