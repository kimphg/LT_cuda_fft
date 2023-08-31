
// buffers for receiving and sending data
#define ARRAY_SIZE 1058
//unsigned char packetBuffer[UDP_TX_PACKET_MAX_SIZE];  // buffer to hold incoming packet,
unsigned char outBuffer1[ARRAY_SIZE] ;        // HR data packets
unsigned char outBuffer2[ARRAY_SIZE] ;  
unsigned char outBuffer3[ARRAY_SIZE] ;  
unsigned char outBuffer4[ARRAY_SIZE] ; 
unsigned char header[34];


#include <SPI.h>
#include <NativeEthernet.h>         // for Teensy 4.1
#include <NativeEthernetUdp.h>

//#define ARRAY_SIZE 32       // max 700 with Arduino UNO
//#define ARRAY_SIZE 318        // real Audio Data
//uint8_t data1[ARRAY_SIZE];    // write vector

//byte mac[] = { 0x04, 0xE9, 0xE5, 0x0B, 0xFC, 0xCD };      // com 9  (the other board)
byte mac[] = { 0x04, 0xE9, 0xE5, 0x0B, 0xFC, 0xD1 };    // com 6      Teensy
//IPAddress myIP(111, 111, 111, 111);
//IPAddress myIP(192, 168, 1, 105);                       // for use in my Ethernet
IPAddress myIP(192,  168, 0, 16);                        // BCP21 = (160,  48, 199, 16);                    
//IPAddress myDns(160, 48, 199, 1);                         // trial with webClient
//EthernetClient client;                                    // trial with webClient

//IPAddress destinationIP(111, 111, 111, 222);
//IPAddress destinationIP(192, 168, 1, 102);
IPAddress destinationIP(192,  168, 0, 4);                   // This is now the receiver board Address

//unsigned int          myPort = 8000;
//unsigned int destinationPort = 8002;
unsigned int destinationPort = 31000;                         // Inova receiver Address
unsigned int myPort          = 32501;                         // BCP21 orig. Port

EthernetUDP Udp;                             // create an instance 'Udp'
unsigned short angleradar = 0;
void send_Data() { 
  angleradar++;
  if(angleradar>=2048)angleradar=0;
  unsigned char byte11 = angleradar>>3;
  unsigned char byte12 = angleradar<<5;
  outBuffer1[11]=byte11;
  outBuffer2[11]=byte11;
  outBuffer3[11]=byte11;
  outBuffer4[11]=byte11;
  outBuffer1[12]=byte12;
  outBuffer2[12]=byte12;
  outBuffer3[12]=byte12;
  outBuffer4[12]=byte12;
    for(int i=34;i<1058;i++){
  outBuffer1[i]=rand();
  outBuffer2[i]=rand();
  outBuffer3[i]=rand();
  outBuffer4[i]=rand();
  outBuffer1[i]>>=4;
  outBuffer2[i]>>=4;
  outBuffer3[i]>>=4;
  outBuffer4[i]>>=4;
  }
Udp.beginPacket(destinationIP, destinationPort);
Udp.write(outBuffer1, ARRAY_SIZE);
Udp.endPacket();
Udp.beginPacket(destinationIP, destinationPort);
Udp.write(outBuffer2, ARRAY_SIZE);
Udp.endPacket();
Udp.beginPacket(destinationIP, destinationPort);
Udp.write(outBuffer3, ARRAY_SIZE);
Udp.endPacket();
Udp.beginPacket(destinationIP, destinationPort);
Udp.write(outBuffer4, ARRAY_SIZE);
Udp.endPacket();
}

void setup() {
  header[4]=1; //phan giai
  header[22]=5;
  
  memcpy(outBuffer1,header,34);outBuffer1[0]=0;
  memcpy(outBuffer2,header,34);outBuffer2[0]=1;
  memcpy(outBuffer3,header,34);outBuffer3[0]=2;
  memcpy(outBuffer4,header,34);outBuffer4[0]=3;
  for(int i=34;i<1058;i++){
  outBuffer1[i]=rand();
  outBuffer2[i]=rand();
  outBuffer3[i]=rand();
  outBuffer4[i]=rand();
  }
  Serial.begin(115200);
  //  Serial.println("ready");
  Ethernet.begin(mac, myIP);
  Udp.begin(myPort);
  Serial.print("WebClient Sender with IP address: ");
  Serial.println(Ethernet.localIP());


}

void loop() {

send_Data();
  delayMicroseconds(100);

}
