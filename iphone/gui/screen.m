#if 0

#undef Point
#define Point _Point
#undef Rect
#define Rect _Rect

#import <UIKit/UIKit.h>

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

Memimage *gscreen;
Screeninfo screen;
static int depth;

static CGRect devRect;
static Rendez	rend;
static int readybit;

extern char **gArgv;
extern int gArgc;
	int dx, dy;
static CGDataProviderRef dataProviderRef;
static CGImageRef fullScreenImage;

void put_pass();
void do_stuff();

static UIWindow *window;
static UIButton *bb;
static UIView *gView;
NSPort *gUpdatePort;

void iphone_do_screen(CGContextRef context);


static NSAutoreleasePool * pool = 0;

@interface DTView : UIView {
}
@end

@implementation DTView

- (void)drawRect:(CGRect)rect {
	
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect    myFrame = self.bounds;
	
    CGContextSetLineWidth(context, 10);
	
    [[UIColor blueColor] set];
    UIRectFrame(myFrame);
	
	iphone_do_screen(context);
	
}

@end


@interface DTApp : UIApplication <UIAccelerometerDelegate> {
}
@end

@implementation DTApp

- (void)accelerometer:(UIAccelerometer *)accelerometer didAccelerate:(UIAcceleration *)acceleration
{
/*	float x,y,z;
	
	_accel[0] = acceleration.x;
	_accel[1] = acceleration.y;
	_accel[2] = acceleration.z;
	
	AppEvent(D_EVENT_ACCEL);
*/	
}

- (void)buttonAction:(id)sender {
	NSLog(@"Here");
	[gView setNeedsDisplay];
}

- (void)updateAction {
	NSLog(@"UPDATE");
	printf("HERE\n");
	[gView setNeedsDisplay];
}


- (void)passAction:(id)sender {
	NSLog(@"pass action");
	put_pass();
}

- (void)stuffAction:(id)sender {
	NSLog(@"stuff action");
	do_stuff();
}

- (void) handlePortMessage:(NSPortMessage *)portMessage
{
	[gView setNeedsDisplay];
}

- (void)applicationDidFinishLaunching:(UIApplication *)application {  
    window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	//window.backgroundColor = [UIColor redColor];
	
	CGRect dFrame = CGRectMake(0, 20, 320, 460);
	gView = [[DTView alloc] initWithFrame:dFrame];
	gView.backgroundColor = [UIColor greenColor];
	[window addSubview: gView];
	
	dFrame = CGRectMake(5, 445, 100, 30);
	bb = [[UIButton buttonWithType: UIButtonTypeRoundedRect] initWithFrame:dFrame];
	[bb addTarget:self action:@selector(buttonAction:) forControlEvents:UIControlEventTouchUpInside];
	[bb setTitle:@"Update" forState:UIControlStateNormal];
	[window addSubview: bb];
	
	dFrame = CGRectMake(110, 445, 100, 30);
	bb = [[UIButton buttonWithType: UIButtonTypeRoundedRect] initWithFrame:dFrame];
	[bb addTarget:self action:@selector(passAction:) forControlEvents:UIControlEventTouchUpInside];
	[bb setTitle:@"Pass" forState:UIControlStateNormal];
	[window addSubview: bb];	
	
	dFrame = CGRectMake(215, 445, 100, 30);
	bb = [[UIButton buttonWithType: UIButtonTypeRoundedRect] initWithFrame:dFrame];
	[bb addTarget:self action:@selector(stuffAction:) forControlEvents:UIControlEventTouchUpInside];
	[bb setTitle:@"Stuff" forState:UIControlStateNormal];
	[window addSubview: bb];	
	
    // Override point for customization after app launch    
    //[window addSubview:viewController.view];
    [window makeKeyAndVisible];
	[gView setNeedsDisplay];
	//gView.backgroundColor = [UIColor grayColor];
	
	gUpdatePort = [NSMachPort port];
	[gUpdatePort setDelegate:self];
	[[NSRunLoop currentRunLoop] addPort:gUpdatePort forMode:NSDefaultRunLoopMode];

	//gApp = self;	
}

@end

void iphone_do_screen(CGContextRef context)
{
	
	
	CGRect rbounds;
	rbounds.size.width = dx;
	rbounds.size.height = dy;
	rbounds.origin.x = 0;
	rbounds.origin.y = 0;


#if 0
	CGAffineTransform transimg = {
		.a = (320 / (float)dx),
		.c = 0.0,
		.tx = 0,
		
		.b = 0.0,
		.d = -(320.0 / (float)dx),
		.ty = ((float)dy / (float)dx) * 320.0
	};
#else
	CGAffineTransform transimg = {
		.a = 1.0,
		.c = 0.0,
		.tx = 0,
		
		.b = 0.0,
		.d = -1.0,
		.ty = dy
	};
#endif

	//CGContextTranslateCTM(context, 320,460);

	//CGContextRotateCTM(context, 3.141);
	CGContextConcatCTM(context, transimg);
	CGImageRef subimg = CGImageCreateWithImageInRect(fullScreenImage, rbounds);
	CGContextDrawImage(context, rbounds, subimg);
	CGContextFlush(context);
	CGImageRelease(subimg);
}
#endif

