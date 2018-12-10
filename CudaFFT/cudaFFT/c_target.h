#include <random>
#include <time.h>
#define FRAME_HEADER_SIZE 34
#define FRAME_LEN 2048
#define OUTPUT_FRAME_SIZE FRAME_LEN*2+FRAME_HEADER_SIZE
#define PI_NHAN2                    6.2831853072
#define PI_CHIA2                    1.5707963268
#define PI                       3.14159265358979323846
#define DEG_RAD 57.295779513
#define MAX_AZI 2048
std::default_random_engine generator;
std::normal_distribution<double> distribNoise(30, 8);
std::normal_distribution<double> distribAzi(0, 1);//scale of 2048
std::normal_distribution<double> distribRot(180, 0.5 );//deg per sec
using namespace std;
double ConvXYToRange(double x, double y)
{
	double range;
	if (!y)
	{
		range = abs(x);
	}
	else
	{
		//*azi = atanf(x / y);
		//if (y<0)*azi += PI;
		//if (*azi<0)*azi += PI_NHAN2;
		range = sqrt(x*x + y*y);
		//*azi = *azi*DEG_RAD;
	}
	return range;

}
double ConvXYToAziRad(double x, double y)
{
	double azi;
	if (!y)
	{
		azi = x>0 ? PI_CHIA2 : (PI_NHAN2 - PI_CHIA2);

	}
	else
	{
		azi = atanf(x / y);
		if (y<0)azi += PI;
		if (azi<0)azi += PI_NHAN2;
	}
	return azi;
}
extern unsigned char outputFrame[MAX_AZI][OUTPUT_FRAME_SIZE];
extern double rResolution;
class target_t
{
public:
	double speed, x, y, azi, range;
	double bearing,rot;
	int dopler;
	int targetSize;
	unsigned char nUpdates;
	time_t  timeLast;
	target_t(double tx, double ty, double tspeed, double tbearing, int dople)
	{
		speed = tspeed;
		x = tx;
		y = ty;
		bearing = tbearing / 180.0*3.14159265359;
		azi = ConvXYToAziRad(x, y) / 3.141592653589*1024.0;
		range = ConvXYToRange(x, y);
		dopler = dople;
		targetSize = 5;
		nUpdates = 0;
		timeLast = time(0);
		rot = 0;
	}
	void generateSignal()
	{
		if (range >= FRAME_LEN - 1)return;
		//if (rand() % 5)return;
		int azimin = azi - targetSize; if (azimin < 0)azimin += 2048;
		int azimax = azi + targetSize; if (azimax >= 2048)azimax -= 2048;
		int k = 0;
		for (int a = azimin; ; a++)
		{
			if (a < 0)a += 2048;
			if (a >= 2048) a -= 2048;
			if (a == azimax)break;
			int value = 150 * (1.0 - abs(k - targetSize) / (targetSize + 1.0));
			outputFrame[a][(int)range + FRAME_LEN + FRAME_HEADER_SIZE] = dopler;
			outputFrame[a][(int)range + FRAME_LEN + 1 + FRAME_HEADER_SIZE] = dopler;
			outputFrame[a][(int)range + FRAME_HEADER_SIZE] = value + int(distribNoise(generator));
			outputFrame[a][(int)range + 1 + FRAME_HEADER_SIZE] = value + int(distribNoise(generator));
			
			k++;
		}
	}
	void eraseSIgnal()
	{
		if (range >= FRAME_LEN - 1)return;
		int azimax = azi + targetSize; if (azimax >= 2048)azimax -= 2048;
		int azimin = azi - targetSize; if (azimin < 0)azimin += 2048;
		for (int a = azimin; ; a++)
		{
			if (a < 0)a += 2048;
			if (a>=2048) a -= 2048;
			if (a == azimax)break;
			int num = int(distribNoise(generator));
			if (num < 0)num = 0;
			outputFrame[a][(int)range + FRAME_HEADER_SIZE] = num;
			outputFrame[a][(int)range + FRAME_LEN + FRAME_HEADER_SIZE] =  rand() % 16;
			num = int(distribNoise(generator));
			if (num < 0)num = 0;
			outputFrame[a][(int)range + 1 + FRAME_HEADER_SIZE] = num;
			outputFrame[a][(int)range + FRAME_LEN + 1 + FRAME_HEADER_SIZE] = rand() % 16;
		}
	}
	void update()
	{
		eraseSIgnal();
		//recalculate coodinates
		time_t timenow = time(0);
		double elapsed_secs = difftime(timenow, timeLast);
		timeLast = timenow;
		nUpdates++;
		if (nUpdates>5)
		{
			nUpdates = 0;
			rot = distribRot(generator) / DEG_RAD - PI;

		}
		bearing += rot*elapsed_secs;
		printf("\nbearing:%f", bearing);
		double distance = elapsed_secs / 3600.0*speed;
		x += distance*sin(bearing);
		y += distance*cos(bearing);
		//
		azi = ConvXYToAziRad(x, y) / 3.141592653589*1024.0;// +(distribAzi(generator));
		range	= ConvXYToRange(x, y) / rResolution;
		
		
		generateSignal();
	}
	~target_t();
};