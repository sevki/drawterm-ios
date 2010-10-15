#include	"u.h"
#include	"lib.h"
#include	"dat.h"
#include	"fns.h"
#include	"error.h"

#include	"draw.h"
#include	"memdraw.h"
#include	"screen.h"

typedef struct Accelinfo Accelinfo;
typedef struct Locationinfo Locationinfo;
typedef struct Headinginfo Headinginfo;

struct Accelinfo
{
	Lock lk;
	int open;
	int changed;
	float x,y,z;
	Rendez r;
};

struct Locationinfo
{
	Lock lk;
	Rendez r;
	int open, changed, logging, failed;
	float x, y, altitude, haccur, vaccur;	
};

struct Headinginfo
{
	Lock lk;
	Rendez r;
	int open, changed, logging, failed;
	float mag, tru, accuracy;
};

static Accelinfo accel;
static Locationinfo location;
static Headinginfo heading;

enum{
	Qdir,
	Qaccel,
	Qlocation,
	Qheading,
};

Dirtab iosdir[]={
	".",		{Qdir, 0, QTDIR},	0,	DMDIR|0555,	
	"accel",	{Qaccel},	0,			0444,
	"location",	{Qlocation},0,			0444,
	"heading",  {Qheading}, 0,			0444,
	
};

#define	NIOS	(sizeof(iosdir)/sizeof(Dirtab))
#define IOSCHAR 'z'


void loglocation(); // startup.m
void logheading(); // startup.m

static int accelchanged(void *a);
static int locationchanged(void *a);
static int headingchanged(void *a);

static Chan*
iosattach(char *spec)
{
	return devattach(IOSCHAR, spec);
}

static Walkqid*
ioswalk(Chan *c, Chan *nc, char **name, int nname)
{
	return devwalk(c, nc, name, nname, iosdir, NIOS, devgen);
}

static int
iosstat(Chan *c, uchar *db, int n)
{
	return devstat(c, db, n, iosdir, NIOS, devgen);
}

static Chan*
iosopen(Chan *c, int omode)
{
	switch((long)c->qid.path){
	case Qdir:
		if(omode != OREAD)
			error(Eperm);
		break;
	case Qaccel:
			if (omode != OREAD)
				error(Eperm);
			lock(&accel.lk);
			if (accel.open) {
				unlock(&accel.lk);
				error(Einuse);
			}
			accel.open = 1;
			unlock(&accel.lk);
			break;
	case Qheading:
			if (omode != OREAD)
				error(Eperm);
			lock(&heading.lk);
			if (heading.open) {
				unlock(&heading.lk);
				error(Einuse);
			}
			if (!heading.logging) {
				logheading();
				heading.logging = 1;
			} else {
				heading.changed = 1;
			}
			heading.open = 1;
			unlock(&heading.lk);
			break;
	case Qlocation:
			if (omode != OREAD)
				error(Eperm);
			lock(&location.lk);
			if (location.open) {
				unlock(&location.lk);
				error(Einuse);
			}
			if (!location.logging) {
				loglocation();
				location.logging = 1;
			} else {
				// updates coming so rarely
				// just send the last one again when reopening the device
				location.changed = 1;
			}
			location.open = 1;
			unlock(&location.lk);
			break;
	}
	
	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

void
iosclose(Chan *c)
{
	if(!(c->flag&COPEN))
		return;

	switch((long)c->qid.path) {
		case Qaccel:
			lock(&accel.lk);
			accel.open = 0;
			unlock(&accel.lk);
			break;
		case Qlocation:
			lock(&location.lk);
			location.open = 0;
			unlock(&location.lk);
			break;
		case Qheading:
			lock(&heading.lk);
			heading.open = 0;
			unlock(&heading.lk);
			break;
	}
}


long
iosread(Chan *c, void *va, long n, vlong offset)
{
	char buf[5*12+1];
	// XXX: why not write directly into va?
	uchar *p;
	int len;
	
	p = va;
	switch((long)c->qid.path){
		case Qdir:
			return devdirread(c, va, n, iosdir, NIOS, devgen);
		case Qaccel:
			while (!accelchanged(0))
				sleep(&accel.r, accelchanged, 0);
			lock(&accel.lk);
			sprint(buf, "a%11f %11f %11f", accel.x, accel.y, accel.z);
			accel.changed = 0;
			unlock(&accel.lk);
			if (n > nelem(buf))
				n = nelem(buf);
			memmove(va, buf, n);
			return n;
		break;
		case Qheading:
			while (!headingchanged(0))
				sleep(&heading.r, headingchanged, 0);
			lock(&heading.lk);
			if (heading.failed) {
				error("cannot read from heading service");
				unlock(&heading.lk);
				return -1;
			}
			len = sprint(buf, "%11f %11f %11f\n", heading.mag, heading.tru, heading.accuracy);
			heading.changed = 0;
			unlock(&heading.lk);
			if (n > len)
				n = len;
			memmove(va, buf, n);
			return n;
		case Qlocation:
			while(!locationchanged(0))
				sleep(&location.r, locationchanged, 0);
			lock(&location.lk);
			if (location.failed) {
				error("cannot read from location service");
				unlock(&location.lk);
				return -1;
			}
			len = sprint(buf, "%11f %11f %11f %11f %11f\n", location.x, location.y, location.altitude, location.haccur, location.vaccur);
			location.changed = 0;
			unlock(&location.lk);
			if (n > len)
				n = len;
			memmove(va, buf, n);
			return n;
	}
	return 0;
}

long
ioswrite(Chan *c, void *va, long n, vlong offset)
{
	char *p;

	USED(offset);

	p = va;
	switch((long)c->qid.path){
	case Qdir:
		error(Eisdir);
	case Qaccel:
		panic("shouldn't be able to write on Qaccel");
		break;
	case Qlocation:
		panic("shouldn't be able to write on Qlocation");
		break;
	case Qheading:
		panic("shouldn't be able to write on Qheading");	
		break;
	}

	error(Egreg);
	return -1;
}


static int
accelchanged(void *a)
{
	USED(a);
	
	return accel.changed;
}

static int
locationchanged(void *a)
{
	USED(a);
	return location.changed;
}

static int
headingchanged(void *a)
{
	USED(a);
	return heading.changed;
}

void
sendaccel(float x, float y, float z)
{
	lock(&accel.lk);
	accel.x = x;
	accel.y = y;
	accel.z = z;
	accel.changed = 1;
	unlock(&accel.lk);
	wakeup(&accel.r);
}

void
sendlocation(float x, float y, float altitude, float haccuracy, float vaccuracy, int failed) // Coordinates in WGS84
{
	lock(&location.lk);
	location.x = x;
	location.y = y;
	location.altitude = altitude;
	location.haccur = haccuracy;
	location.vaccur = vaccuracy;
	location.failed = failed;
	location.changed = 1;
	unlock(&location.lk);
	wakeup(&location.r);
}

void
sendheading(float magheading, float trueheading, float accuracy, int failed)
{
	lock(&heading.lk);
	heading.mag = magheading;
	heading.tru = trueheading;
	heading.accuracy = accuracy;
	heading.failed = failed;
	heading.changed = 1;
	unlock(&heading.lk);
	wakeup(&heading.r);
}


Dev iosdevtab = {
	IOSCHAR,
	"ios",

	devreset,
	devinit,
	devshutdown,
	iosattach,
	ioswalk,
	iosstat,
	iosopen,
	devcreate,
	iosclose,
	iosread,
	devbread,
	ioswrite,
	devbwrite,
	devremove,
	devwstat,
};
