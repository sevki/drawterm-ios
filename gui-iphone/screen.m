#undef Point
#define Point _Point
#undef Rect
#define Rect _Rect

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Foundation/NSRunLoop.h>

#undef Rect
#undef Point

#undef nil

#include "u.h"
#include "lib.h"
#include "kern/dat.h"
#include "kern/fns.h"
#include "error.h"
#include "user.h"
#include <draw.h>
#include <memdraw.h>
#include "screen.h"
#include "keyboard.h"

#define UNIMPL {printf("UNIMPL CALL: %s\n",__PRETTY_FUNCTION__);}

extern Cursorinfo cursor;

typedef struct touch touch;
typedef struct button button;
typedef struct pt pt;


struct pt
{
	float x,y;
};

struct touch
{
	float x,y;
	int inview;
	void *tid;
};

struct button
{
	pt min, max, dim;
};

Memimage *gscreen;
Screeninfo screen;
static CGRect devRect;
static float dx, dy;
static CGDataProviderRef dataProviderRef;
static CGImageRef fullScreenImage;

static int isready = 0;
static int gesturestate;
static float zoom = 1.0;
static float pinchdist;
static float pinchzoom;
static int magnify;

static float lastwheel;


pt cursoroff;

static uchar cursorbit[16*16*4];
static CGDataProviderRef cursorProvider;
static CGImageRef cursorImg;


static Cursorinfo	arrow = {
	.clr = { 0xFF, 0xFF, 0x80, 0x01, 0x80, 0x02, 0x80, 0x0C, 
		0x80, 0x10, 0x80, 0x10, 0x80, 0x08, 0x80, 0x04, 
		0x80, 0x02, 0x80, 0x01, 0x80, 0x02, 0x8C, 0x04, 
		0x92, 0x08, 0x91, 0x10, 0xA0, 0xA0, 0xC0, 0x40, 
	},
	.set = { 0x00, 0x00, 0x7F, 0xFE, 0x7F, 0xFC, 0x7F, 0xF0, 
		0x7F, 0xE0, 0x7F, 0xE0, 0x7F, 0xF0, 0x7F, 0xF8, 
		0x7F, 0xFC, 0x7F, 0xFE, 0x7F, 0xFC, 0x73, 0xF8, 
		0x61, 0xF0, 0x60, 0xE0, 0x40, 0x40, 0x00, 0x00, 
	},
	.offset = {0,-16},
};


static int mmod = 0;

static button btns[4];

extern UIView *uiview;


enum {
	GestureNone,
	GesturePinch,
	GestureToggleKeyboard,
	GestureChord,
	GestureWheel,
};

static float origx, origy;
static float offx, offy;

static int lastmx = 0, lastmy = 0;

static pt PT(float x, float y)
{
	pt p = {x,y};
	return p;
}


touch touches[20]; // 20..just a ridiculous number XXX: should make checks anyways..
int ntouches = 0;

void sendbuttons(int b, int x, int y);


static void screen_invalidate()
{
	if(!uiview) {
		printf("screenload dismissed -- uiview not initialized XXX: can this even happen?\n");
		return;
	}
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[[NSRunLoop mainRunLoop] performSelector: @selector(pleaseRedraw)
									  target: uiview
									argument: nil
									   order:0
									   modes:[NSArray arrayWithObject: NSRunLoopCommonModes]]; //NSDefaultRunLoopMode]];
	[pool release];
}

static float
touchdist(touch *a, touch *b)
{
	return sqrtf((a->x - b->x)*(a->x - b->x) + (a->y - b->y)*(a->y - b->y));
}

static int
inbutton(touch *t, int num)
{
	if (t->x >= btns[num].min.x && t->x <= btns[num].max.x &&
		t->y >= btns[num].min.y && t->y <= btns[num].max.y)
		return 1;
	
	return 0;
}

void
screen_keystroke(const char *s)
{
	Rune r;
	chartorune(&r, (char*)s);
	kbdputc(kbdq, r);
}

static int
checkmouse()
{
	int i,j;
	int mod = 0;
	

	for (i = 0; i < ntouches; i++) {
		touches[i].inview = 1;
		for (j = 0; j < 3; j++)
			if (inbutton(&touches[i], (j+1))) {
				mod |= 1 << j;
				touches[i].inview = 0;
			}
	}

	if (mod != mmod) {
		mmod = mod;
		return 1;
	}
	mmod = mod;
	return 0;
}

void
screen_touch_began(void* touchid, float x, float y)
{
	touch *t;
	
	touches[ntouches].tid = touchid;
	touches[ntouches].x = x;
	touches[ntouches].y = y;
	t = &(touches[ntouches]);
	ntouches++;
	
	if(!isready)
		return;
	
	switch (gesturestate) {
		case GestureNone:
			if (checkmouse()) {
				//printf("activating GestureChord\n");
				gesturestate = GestureChord;
				//printf("sending chord 1\n");
				sendbuttons(mmod, lastmx, lastmy);
				screen_invalidate();
			} else if (ntouches == 3) {
				gesturestate = GestureWheel;
				// origy is used for wheeldelta
				//origy = ((touches[0].y + touches[1].y + touches[2].y) * (1.0/3.0) - offy) / zoom;
				lastwheel = (touches[0].y + touches[1].y + touches[2].y) * (1.0/3.0);
				//printf("WHEEL activated\n");
			} else if (ntouches == 2) {
				gesturestate = GesturePinch;
				// orig in SCREEN coordinates --> point under the pinch
				origx = ((touches[0].x + touches[1].x) * 0.5 - offx) / zoom;
				origy = ((touches[0].y + touches[1].y) * 0.5 - offy) / zoom;
				pinchdist = touchdist(&touches[0], &touches[1]);
				pinchzoom = zoom;
				magnify = 0;
			} else if (ntouches == 1) {
				if (inbutton(&touches[0], 0)) {
					gesturestate = GestureToggleKeyboard;
					magnify = 0;
				} else {
					//printf("send null A\n");
					lastmx = (t->x - offx) / zoom;
					lastmy = (t->y - offy) / zoom;
					sendbuttons(0, lastmx, lastmy);
					magnify = 1;
					screen_invalidate();
				}

			}
			break;
		case GesturePinch:
			if (ntouches == 3) {
				lastwheel = (touches[0].y + touches[1].y + touches[2].y) * (1.0/3.0);
				//printf("WHEEL activated\n");
				gesturestate = GestureWheel;
			}
			break;
		case GestureChord:
			checkmouse();
			if(ntouches == 3) {
			} else if (t->inview) {
				//NSLog(@"send buttons!\n");
				lastmx = (t->x - offx) / zoom;
				lastmy = (t->y - offy) / zoom;
				magnify = 1;
				sendbuttons(mmod, lastmx, lastmy);
			}
			screen_invalidate();
			break;
	}	
}

#define Wheelstep 5

void
screen_touch_moved(void *touchid, float x, float y)
{
	int i;
	touch *t = nil;
	for (i = 0; i < ntouches; i++)
		if (touches[i].tid == touchid) {
			t = &(touches[i]);
			break;
		}
	if (!t) {
		printf("Warning...moved a touch that never started\n");
		return;
	}
	t->x = x;
	t->y = y;

	if (!isready)
		return;

	switch (gesturestate) {
		case GestureWheel: {
			float wheel = (touches[0].y + touches[1].y + touches[2].y) * (1.0/3.0);

			while (lastwheel - wheel > Wheelstep) {
				sendbuttons(16,
							(touches[0].x + touches[1].x + touches[2].x) * (1.0/3.0),
							(touches[0].y + touches[1].y + touches[2].y) * (1.0/3.0)
							);
				lastwheel = lastwheel - Wheelstep;
			} 
			while (wheel - lastwheel > Wheelstep) {
				sendbuttons(8,
							(touches[0].x + touches[1].x + touches[2].x) * (1.0/3.0),
							(touches[0].y + touches[1].y + touches[2].y) * (1.0/3.0)
							);
				lastwheel = lastwheel + Wheelstep;
			}
			break;
		}
		case GestureNone:
			lastmx = (t->x - offx) / zoom;
			lastmy = (t->y - offy) / zoom;
			sendbuttons(0, lastmx, lastmy);
			screen_invalidate();			
			break;
		case GesturePinch: {
			float curpinch = touchdist(&touches[0], &touches[1]);
			zoom = (curpinch / pinchdist) * pinchzoom;
			offx = (touches[0].x + touches[1].x) * 0.5 - origx * zoom;
			offy = (touches[0].y + touches[1].y) * 0.5 - origy * zoom;
			//zoom = (curpinch / pinchdist) * pinchzoom;
			screen_invalidate();
			break;
		case GestureChord:
			if (checkmouse() || t->inview) {
				if (t->inview) {
					lastmx = (t->x - offx) / zoom;
					lastmy = (t->y - offy) / zoom;
					magnify = 1;
				}
				sendbuttons(mmod, lastmx, lastmy);
				screen_invalidate();
			}
			break;
			
		}
	}
}

void
screen_touch_ended(void *touchid, float x, float y)
{
	int i;
	touch *t = nil;
	
	for (i = 0; i < ntouches; i++)
		if (touches[i].tid == touchid) {
			t = &(touches[i]);
			memmove(t, t+1, ((ntouches-- - i) - 1) * sizeof(touch));
			break;
		}
	if (!t) {
		printf("Warning...ended a touch that never started\n");
		return;
	}
	
	if (!isready)
		return;

	switch (gesturestate) {
		case GestureWheel:
			printf("WHEEL end!\n");
			if (ntouches < 3)
				gesturestate = GestureNone;
			break;
		case GestureNone:
			magnify = 0;
			screen_invalidate();
			break;
		case GesturePinch:
			if (ntouches < 2)
				gesturestate = GestureNone;
			break;
		case GestureToggleKeyboard:
			if (inbutton(&touches[0], 0)) {
				[uiview toggleKey];
				//printf("toggle keyboard!\n");
				gesturestate = GestureNone;
			}
			break;
		case GestureChord:
			if (checkmouse()) {
				sendbuttons(mmod, lastmx, lastmy);
				if (!mmod) {
					//printf("deactivating GestureChord\n");
					gesturestate = GestureNone;
					magnify = 0;
				}
				screen_invalidate();
			}
			break;
	}
	//if (ntouches == 0)
	//	printf("NO TOUCHES\n");
}

void
screen_touch_cancelled(void* touchid, float x, float y)
{
	// XXX: for now screen_touch_cancelled just means ended...obviously that's not it exactly. but close enough for now
	screen_touch_ended(touchid, x, y);
}
							

void
screenload(Rectangle r, int depth, uchar *p, Point pt, int step)
{
	screen_invalidate();
}

// PAL - no palette handling.  Don't intend to either.
void
getcolor(ulong i, ulong *r, ulong *g, ulong *b)
{
	
	// PAL: Certainly wrong to return a grayscale.
	*r = i;
	*g = i;
	*b = i;
}

int
clipwrite(char *snarf)
{
	UNIMPL
	
	return 0; // failure
}

uchar*
attachscreen(Rectangle *r, ulong *chan, int *depth, int *width, int *softscreen, void **X)
{
	/* XXX: what is this??*/
	*r = gscreen->r;
	*chan = gscreen->chan;
	*depth = gscreen->depth;
	*width = gscreen->width;
	*softscreen = 1;
	
	return gscreen->data->bdata;
}
void
flushmemscreen(Rectangle r)
{
	// sanity check.  Trips from the initial "terminal"
    if (r.max.x < r.min.x || r.max.y < r.min.y) return;
    
	screenload(r, gscreen->depth, byteaddr(gscreen, ZP), ZP,
			   gscreen->width*sizeof(ulong));
}

char*
clipread(void)
{
	UNIMPL
	
	return 0;
}

static void 
loadcursor(Cursorinfo *c)
{
	int i, j;
	//UNIMPL
	int col, alpha;
	
	lock(&c->lk);
	
	cursoroff.x = c->offset.x;
	cursoroff.y = c->offset.y;

	
	for (i = 0; i < 16; i++) {
		for (j = 0; j < 8; j++) {
			col = ((c->clr[i * 2 + 0] >> (7 - j)) & 1) ? 255 : 0;
			alpha = ((c->set[i * 2 + 0] >> (7 - j)) & 1) ? 255 : 0;
			cursorbit[(16*4) * i + (j * 4) + 0] = col;
			cursorbit[(16*4) * i + (j * 4) + 1] = col;
			cursorbit[(16*4) * i + (j * 4) + 2] = col;
			cursorbit[(16*4) * i + (j * 4) + 3] = alpha;
		}
		for (j = 0; j < 8; j++) {
			col = ((c->clr[i * 2 + 1] >> (7 - j)) & 1) ? 255 : 0;
			alpha = ((c->set[i * 2 + 1] >> (7 - j)) & 1) ? 255 : 0;
			cursorbit[(16*4) * i + ((j+8) * 4) + 0] = col;
			cursorbit[(16*4) * i + ((j+8) * 4) + 1] = col;
			cursorbit[(16*4) * i + ((j+8) * 4) + 2] = col;
			cursorbit[(16*4) * i + ((j+8) * 4) + 3] = alpha;
		}		
	}
	
	unlock(&c->lk);
	
}

void
cursorarrow(void)
{
	loadcursor(&arrow);
}

void
setcursor()
{
	loadcursor(&cursor);
}

void
mouseset(Point xy)
{
	lastmx = xy.x;
	lastmy = xy.y;
	screen_invalidate();
}

void
setcolor(ulong index, ulong red, ulong green, ulong blue)
{
	// assert(0);
	UNIMPL
}

#define deg2rad(__ANGLE__) ((__ANGLE__) / 180.0 * M_PI)
#define rad2deg(__ANGLE__) ((__ANGLE__) / M_PI * 180.0)


void dt_updatescreen(UIView *me)
{
	CGRect rbounds;
	CGRect vbounds;
	UIImage *baseImg;
	int i;
	//CGAffineTransform transnorm;
	rbounds.size.width = dx;
	rbounds.size.height = dy;
	rbounds.origin.x = 0;
	rbounds.origin.y = 0;
	vbounds = [me bounds];
	
	UIGraphicsBeginImageContext(vbounds.size);
	//UIGraphicsPushContext(context);
	CGContextRef context = UIGraphicsGetCurrentContext();

	CGAffineTransform transimg = {
		.a = zoom,
		.c = 0.0,
		.tx = floorf(offx),
		
		.b = 0.0,
		.d = -zoom,//-floorf(zoom),
		.ty = rbounds.size.height * zoom + floorf(offy),//dy
	};
	
	
	CGContextSaveGState(context);
	CGContextRotateCTM(context, deg2rad(90.0));
	CGContextTranslateCTM(context, 0.0,-vbounds.size.width);
	CGContextConcatCTM(context, transimg);
	CGContextDrawImage(context, rbounds, fullScreenImage);
	CGContextDrawImage(context, CGRectMake(lastmx+cursoroff.x,dy - (lastmy-cursoroff.y),16,16), cursorImg);
	CGContextRestoreGState(context);


	CGAffineTransform transbtns = {
		.a = 0.0,
		.c = -1.0,
		.tx = vbounds.size.width,
		
		.b = 1.0,
		.d = 0.0,
		.ty = 0.0,//dy
	};

	CGContextConcatCTM(context, transbtns);
	CGContextMoveToPoint(context, 0, 0);

	for (i = 0; i < nelem(btns); i++) {
		CGRect r = CGRectMake(btns[i].min.x,btns[i].min.y,btns[i].dim.x, btns[i].dim.y);

		if (mmod & (1 << (i-1)))
			CGContextSetRGBFillColor(context, 1.0, 0.0, 0.0, 1.0);
		else 
			CGContextSetRGBFillColor(context, 0.0, 0.0, 0.0, 1.0);
		//CGContextSetRGBFillColor(context, 0.0,0.0,0.0,1.0);
		CGContextFillRect(context, r);
		CGContextSetRGBStrokeColor(context, 0.0, 1.0, 0.0, 1.0);
		CGContextStrokeRect(context, r);
	}
	
	CGContextSetRGBFillColor(context, 0.0,0.0,1.0,1.0);
	//CGContextFillEllipseInRect(context, CGRectMake((lastmx*zoom+offx)-5,(lastmy*zoom+offy)-5,10,10));
	//CGContextDrawImage(context, CGRectMake((lastmx*zoom+offx)-40,(lastmy*zoom+offy)-40,80,80), cursorImg);
	
	CGContextFlush(context);

	baseImg = [UIGraphicsGetImageFromCurrentImageContext() retain];
	//UIGraphicsPopContext();
	UIGraphicsEndImageContext();
	context = UIGraphicsGetCurrentContext();

	//CGContext
	//CGContextTranslateCTM(context, 0.0,-vbounds.size.width);
	CGContextSaveGState(context);
	CGContextScaleCTM(context, 1.0, -1.0);
	CGContextTranslateCTM(context, 0, -vbounds.size.height);
	CGContextDrawImage(context, vbounds, [baseImg CGImage]);	
	CGContextRestoreGState(context);

	if (magnify) {
		float sx = lastmx * zoom + offx;
		float sy = lastmy * zoom + offy;
		CGRect elr = CGRectMake(vbounds.size.width-sy+50, sx-50, 100, 100);
		CGContextFillEllipseInRect(context, elr);
		CGContextAddEllipseInRect(context, CGRectMake(vbounds.size.width-sy+55, sx-45, 90, 90));
		CGContextClip(context);
		CGContextScaleCTM(context, 1.0, -1.0);
		CGContextTranslateCTM(context, 100, -vbounds.size.height);
		CGContextDrawImage(context, CGRectMake(vbounds.origin.x-(vbounds.size.width-sy), vbounds.origin.y-(vbounds.size.height-sx), vbounds.size.width*2.0, vbounds.size.height*2.0), [baseImg CGImage]);
	}
	
	CGContextFlush(context);
	
	[baseImg release];
}

void
btnsinit()
{
	int i;
	CGRect b = [uiview bounds];
	const float bsize = 80;

	for (i = 0; i < nelem(btns); i++) {
		btns[i].min.x = b.size.height - bsize; 
		btns[i].max.x = b.size.height;
		btns[i].min.y = bsize * i;
		btns[i].max.y = bsize * (i + 1);
		btns[i].dim.x = bsize;
		btns[i].dim.y = bsize;
	}
}

void screeninit(void)
{
	memimageinit();
	screen.depth = 32;

	devRect = CGRectMake(0,0,1024,768); // XXX: we have to pick something... maybe this should be a preference?
	
	dx = devRect.size.width;
	dy = devRect.size.height;

	gscreen = allocmemimage(Rect(0,0,dx,dy), XBGR32);
	
	dataProviderRef = CGDataProviderCreateWithData(0, gscreen->data->bdata,
												   dx * dy * 4, 0);
	fullScreenImage = CGImageCreate(dx, dy, 8, 32, dx * 4,
									CGColorSpaceCreateDeviceRGB(),
									kCGImageAlphaNoneSkipLast,
									dataProviderRef, 0, 0, kCGRenderingIntentDefault);
	cursorProvider = CGDataProviderCreateWithData(0, cursorbit, 16 * 16 * 4, 0);
	cursorImg = CGImageCreate(16, 16, 8, 32, 16 * 4,
									CGColorSpaceCreateDeviceRGB(),
									kCGImageAlphaPremultipliedLast,
									cursorProvider, 0, 0, kCGRenderingIntentDefault);
	

	loadcursor(&arrow);
	btnsinit();
	terminit();
	isready = 1;
}


