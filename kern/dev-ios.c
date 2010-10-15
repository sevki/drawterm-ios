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
typedef struct Touchesinfo Touchesinfo;
typedef struct Touch Touch;
typedef struct Caminfo Caminfo;

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

struct Touchesinfo
{
	Lock  lk;
	Touch *lst;
	int n, idx;
	int open;
	
	// buffered touch infos
	char **buffered;
	int pending, pendinglen;

	char *str;
};

struct Caminfo
{
	Lock lk;
	Rendez r;
	int open, changed;
	char *failstr;
	
	char *dat, *p;
	int len;
};

struct Touch // shared with the ios device driver
{
	float x,y;
	int used;
	void *tid;
};

static Accelinfo accel;
static Locationinfo location;
static Headinginfo heading;
static Touchesinfo touches;
static Caminfo cam;

enum{
	Qdir,
	Qaccel,
	Qlocation,
	Qheading,
	Qtouches,
	Qcam,
};

Dirtab iosdir[]={
	".",		{Qdir, 0, QTDIR},	0,	DMDIR|0555,	
	"accel",	{Qaccel},	0,			0444,
	"location",	{Qlocation},0,			0444,
	"heading",  {Qheading}, 0,			0444,
	"touches",  {Qtouches}, 0,			0444,
	"cam",		{Qcam},		0,			0444,
};

#define	NIOS	(sizeof(iosdir)/sizeof(Dirtab))
#define IOSCHAR 'z'


void loglocation(); // startup.m
void logheading(); // startup.m
void startcam(); // startup.m

static int accelchanged(void *a);
static int locationchanged(void *a);
static int headingchanged(void *a);
static int camchanged(void *a);

Touch *touchset(int *n); // retrieve current set of touches

static char*
nexttouch()
{
	Touch *lst;
	int n, i, j;
	char *buf;
	
	lock(&touches.lk);

	if (touches.pending) {
		buf = touches.buffered[--touches.pending];
		unlock(&touches.lk);
		return buf;
	}
	
	lst = touchset(&n);
	if (touches.pendinglen < n) {
		int start = touches.pendinglen;
		touches.pendinglen = n + touches.n; // new + possible old release
		touches.buffered = realloc(touches.buffered, touches.pendinglen *sizeof(void*));
		for (i = start; i < touches.pendinglen; i++)
			touches.buffered[i] = malloc(1 + 2*12 + 6);
	}
	touches.pending = n;
	for (i = 0; i < touches.pending; i++) // U == used, A == available
		sprint(touches.buffered[i], "%c %11f %11f %x\n", lst[i].used ? 'U' : 'A', lst[i].x, lst[i].y, lst[i].tid); 

	if (touches.lst) {
		for (i = 0; i < touches.n; i++) {
			for (j = 0; i < n; j++)
				if (touches.lst[i].tid == lst[j].tid)
					break;
			if (touches.lst[i].tid != lst[j].tid) {
				// delete this touch
				sprint(touches.buffered[touches.pending++], "D %11f %11f %x\n", touches.lst[i].x, touches.lst[i].y, touches.lst[i].tid);
			}
		}
		free(touches.lst);
	}
	touches.lst = lst;
	touches.n = n;

	if (touches.pending == 0)
		buf = nil;
	else
		buf = touches.buffered[--touches.pending];
	
	unlock(&touches.lk);
	return buf;
}
		 

void starttouches()
{
	lock(&touches.lk);
}

void endtouches()
{
	unlock(&touches.lk);
}



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
	case Qcam:
			if (omode != OREAD)
				error(Eperm);
			lock(&cam.lk);
			if (cam.open) {
				unlock(&cam.lk);
				error(Einuse);
			}
			cam.open = 1;
			unlock(&cam.lk);
			// open blocks until we got the image...or not
			startcam();
			while (!camchanged(0))
				sleep(&cam.r, camchanged, 0);
			lock(&cam.lk);
			cam.changed = 0;
			if (cam.failstr) {
				cam.open = 0;
				unlock(&cam.lk);
				printf("failstr: %s\n", cam.failstr);
				error(cam.failstr);
			}
			unlock(&cam.lk);

			break;
	case Qtouches:
			if (omode != OREAD)
				error(Eperm);
			lock(&touches.lk);
			if (touches.open) {
				unlock(&touches.lk);
				error(Einuse);
			}
			touches.open = 1;
			unlock(&touches.lk);
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
	int i;
	
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
		case Qcam:
			lock(&cam.lk);
			cam.open = 0;
			unlock(&cam.lk);
			break;
		case Qtouches:
			lock(&touches.lk);
			touches.open = 0;
			if (touches.lst) {
				free(touches.lst);
				touches.n = 0;
			}
			if (touches.pendinglen) {
				for (i = 0; i < touches.pendinglen; i++)
					free(touches.buffered[i]);
				free(touches.buffered);
				touches.pendinglen = 0;
			}
			touches.pending = 0;
			unlock(&touches.lk);
			break;
	}
}


long
iosread(Chan *c, void *va, long n, vlong offset)
{
	char buf[10001];
	// XXX: why not write directly into va?
	uchar *p;
	int len;
	char *s;
	
	p = va;
	switch((long)c->qid.path){
		case Qdir:
			return devdirread(c, va, n, iosdir, NIOS, devgen);
		case Qtouches:
			while ((s = nexttouch()) == nil); // XXX: this is a pretty hot loop...
			if (n > strlen(s))
				n = strlen(s);
			memmove(va, s, n);
			return n;
		case Qcam:
			lock(&cam.lk);
			if (n > cam.len)
				n = cam.len;
			if (n > 10000)
				n = 10000;
			memmove(va, cam.p, n);
			cam.p += n;
			cam.len -= n;
			unlock(&cam.lk);
			return n;
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
	case Qtouches:
		panic("shouldn't be able to write on Qtouches");
		break;
	case Qcam:
		panic("shouldn't be able to write on Qcam");
		break;
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

static int
camchanged(void *a)
{
	USED(a);
	return cam.changed;
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
sendcam(void *dat, int len, char *failed)
{
	lock(&cam.lk);
	if (cam.dat)
		free(cam.dat);
	cam.dat = dat;
	cam.p = dat;
	cam.len = len;
	cam.failstr = failed;
	cam.changed = 1;
	unlock(&cam.lk);
	wakeup(&cam.r);
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
