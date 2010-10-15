#include <u.h>
#include <libc.h>
#include <draw.h>
#include <event.h>

Rectangle win;
Image *image, *disk;


#define add addpt
#define sub subpt
#define inset insetrect

float bx, by;
float bsx, bsy;
float gravx, gravy;
int eaccel;

void 
eresized(int new){
	if(new && getwindow(display, Refnone) < 0) {
		sysfatal("can't reattach to window");
	}
	if(image) freeimage(image);
	image=allocimage(display, screen->r, screen->chan, 0, DNofill);
	draw(image, image->r, display->black, nil, ZP);
	win = screen->r;
}

int
doaccel(int key, Event *e, uchar *buf, int len)
{
	gravy = -atof((char*)buf+1);
	gravx = -atof((char*)buf+13);
	return 0;
}

void
update(void)
{
	Event e;
	if(ecanmouse())
		emouse();
	if(ecanread(eaccel))
		eread(eaccel, &e);

	// update data
	bsx = gravx * 3.0;
	bsy = gravy * 3.0;
	bx += bsx;
	if (bx > win.max.x) {
		bx = win.max.x;
		bsx = 0;
	}
	if (bx < win.min.x) {
		bx = win.min.x;
		bsx = 0;
	}
	by += bsy;
	if (by > win.max.y) {
		by = win.max.y;
		bsy = 0;
	}
	if (by < win.min.y) {
		by = win.min.y;
		bsy = 0;
	}
	// redraw screen
	draw(image, inset(image->r, 3), display->white, nil, ZP);
	fillellipse(image, Pt(bx,by),50,50, display->black, ZP);

	draw(screen, screen->r, image, nil, image->r.min);
	flushimage(display ,1);
	// wait
	sleep(20);
}

void
main(int argc, char *argv[]){
	int accelfd;

	accelfd = open("/dev/accel", OREAD);
	if (accelfd < 0)
		drawerror(display, "cannot open accelerometer\n");

	if(initdraw(nil, nil, "acceldemo") < 0)
		sysfatal("initdraw failed: %r");
	einit(Emouse);
	eaccel = estartfn(4, accelfd, 3*12+1, doaccel);
	disk = allocimage(display,Rect(0,0,1,1), CMAP8, 1, DDarkyellow);
	eresized(0);
	gravx = 0.0;
	gravy = 0.0;
	bsx = 0.0;
	bsy = 0.0;
	bx = win.min.x + 40;
	by = win.min.y + 40.0;

	for(;;){
		update();
	}
}
