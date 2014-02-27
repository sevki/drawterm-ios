/*
	main.m
	drawterm
	
	Created by Jeff Sickel on 10/16/10.
*/

#import <UIKit/UIKit.h>

int
main(int argc, char **argv)
{
    int                 retVal;
    NSAutoreleasePool * pool;
    
    pool = [[NSAutoreleasePool alloc] init];
    assert(pool != nil);
    
    retVal = UIApplicationMain(argc, argv, @"App", nil);
    
    [pool drain];

    return retVal;
/*
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([DTAppDelegate class]));
    }
*/
}
