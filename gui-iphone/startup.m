
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>

#include <pthread.h>

typedef unsigned short	Rune;
int chartorune(Rune *rune, const char *str);

NSPort *updateport = nil;
UIView *uiview = nil;
static CLLocationManager *locMgr;
static UIImagePickerController *bitpicker;
static UIWindow *window;

void screen_keystroke(const char *s);
void screen_touch_moved(void *touchid, float x, float y);
void screen_touch_ended(void *touchid, float x, float y);
void screen_touch_cancelled(void* touchid, float x, float y);
void screen_touch_began(void* touchid, float x, float y);

void sendaccel(float x, float y, float z);
void sendlocation(float x, float y, float altitude, float haccuracy, float vaccuracy, int failed); // Coordinates in WGS84
void sendheading(float magheading, float trueheading, float accuracy, int failed);

extern const char *userpass;

void dt_updatescreen(UIView *me);
int dt_main(int argc, char *argv[]);

@interface TermViewController : UIViewController
{
}
@end

@interface TermViewDelegate : NSObject <UITextFieldDelegate>
{
}
- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
- (void)textFieldDidBeginEditing:(UITextField *)textField;
- (void)textFieldDidEndEditing:(UITextField *)textField;
-  (BOOL)textFieldShouldBeginEditing:(UITextField *)textField;
- (BOOL)textFieldShouldClear:(UITextField *)textField;
- (BOOL)textFieldShouldEndEditing:(UITextField *)textField;
- (BOOL)textFieldShouldReturn:(UITextField *)textField;
- (void)keyboardInputChanged:(id)sender;	
@end



@interface TermView : UITextField <UITextFieldDelegate>
{
}
- (void) pleaseRedraw;
//- (BOOL)canBecomeFirstResponder;

@end

@interface EditableDetailCell : UITableViewCell
{
    UITextField *_textField;
}

@property (nonatomic, retain) UITextField *textField;

@end

@interface ConViewController : UITableViewController
{
	NSMutableArray *_displayedObjects;
}
@property (nonatomic, retain) NSMutableArray *displayedObjects;
- (void)addObject:(id)anObject;
- (void)save;


@end


@implementation TermViewController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return YES;
}
@end

@implementation TermView

/*
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return YES;
}
 */

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	NSLog(@"rot rot...\n");
	return NO;
}

- (id)initWithFrame:(CGRect)r
{
	self = [super initWithFrame:r];
	[self setDelegate: [[TermViewDelegate alloc] init]];
	self.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.multipleTouchEnabled = YES;
	//self.exclusiveTouch = YES;
	
	//self.delegate = self;
//	NSLog(@"old delegate: %@\n", self.delegate);
	return self;
}

- (void)drawRect:(CGRect)rect {	
	//NSLog(@"got a redraw call\n");
	dt_updatescreen(self);
	//[super drawRect: rect];

}

- (void) toggleKey
{
	if([self isFirstResponder])
		[self resignFirstResponder];
	else
		[self becomeFirstResponder];

}

- (void) pleaseRedraw
{
	//NSLog(@"pleaseRedraw\n");
	[self setNeedsDisplay];
}

@end

@implementation TermViewDelegate

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{	
	//NSLog(@"changed\n");
	// kbdputc should really be called: kbdputr

	screen_keystroke([string UTF8String]);
	
	//NSLog(@"Input: %@\n", string);
	return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
	//NSLog(@"did begin editing\n");
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
	//NSLog(@"did end editing\n");
}

-  (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	//NSLog(@"should begin editing?\n");
	return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField
{
	NSLog(@"should clear?\n");
	return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
	//NSLog(@"should end editing?\n");
	return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	screen_keystroke("\n");
	return NO;
}


// XXX: NOT SURE IF THAT BITES US IN THE ASS -- REGARDING APP STORE CRAZINESS!
- (void)keyboardInputChanged:(id)sender
{
	// This is a workaround for a bug either in this code or in the official 3.0
	// SDK.  Without this overridden method, we get in an infinite loop when
	// this text field becomes the first responder.
}

// XXX: same problem as above
- (void) keyboardInputShouldDelete:(id)input {
	screen_keystroke("\b");
}

@end

@implementation EditableDetailCell

@synthesize textField = _textField;

- (void)dealloc
{
    [_textField performSelector:@selector(release)
                     withObject:nil
                     afterDelay:1.0];
    
    [super dealloc];
}

- (id)initWithStyle:(UITableViewCellStyle)style
    reuseIdentifier:(NSString *)identifier
{
    self = [super initWithStyle:style reuseIdentifier:identifier];
    
    if (self == nil)
        return nil;
    
    CGRect bounds = [[self contentView] bounds];
    CGRect rect = CGRectInset(bounds, 20.0, 10.0);
    UITextField *textField = [[UITextField alloc] initWithFrame:rect];
    
    [textField setReturnKeyType:UIReturnKeyNext];
    [textField setClearButtonMode:UITextFieldViewModeWhileEditing];
    [textField setBackgroundColor:[UIColor whiteColor]];
    [textField setOpaque:YES];

    [[self contentView] addSubview:textField];
    [self setTextField:textField];
    
    [textField release];
    return self;
}

//  Disable highlighting of currently selected cell.
//
- (void)setSelected:(BOOL)selected
           animated:(BOOL)animated 
{
    [super setSelected:selected animated:NO];
    
    [self setSelectionStyle:UITableViewCellSelectionStyleNone];
}

@end


@interface Connection : NSObject
{
	NSString *_title;
	NSString *_auth;
	NSString *_cpu;
	NSString *_user;
	NSString *_pass;
}

@property (nonatomic, retain) NSString *title;
@property (nonatomic, retain) NSString *auth;
@property (nonatomic, retain) NSString *cpu;
@property (nonatomic, retain) NSString *user;
@property (nonatomic, retain) NSString *pass;

+ (id)connectionWithTitle:(NSString *)title
					 auth:(NSString *)auth
					  cpu:(NSString *)cpu
					 user:(NSString *)user
					 pass:(NSString *)pass;
- (id) init;
- (id) initWithTitle:(NSString *)title
				auth:(NSString *)auth
				 cpu:(NSString *)cpu
				user:(NSString *)user
				pass:(NSString *)pass;
- (id)proplst;

@end

@implementation Connection

@synthesize title = _title;
@synthesize auth = _auth;
@synthesize cpu = _cpu;
@synthesize user = _user;
@synthesize pass = _pass;

- (void)dealloc
{
	[_title release];
	[_auth release];
	[_cpu release];
	[_user release];
	[_pass release];
	[super dealloc];
}

- (id)init
{
	self = [super init];
	_title = @"";
	_auth = @"";
	_cpu = @"";
	_user = @"";
	_pass = @"";
	return self;
}

+ (id)connectionWithTitle:(NSString *)title
					 auth:(NSString *)auth
					  cpu:(NSString *)cpu
					 user:(NSString *)user
					 pass:(NSString *)pass
{
	Connection *con = [[self alloc] initWithTitle: title
											 auth:auth
											  cpu:cpu
											 user:user
											 pass:pass];
	return [con autorelease];
}

- (id) initWithTitle:(NSString *)title
				auth:(NSString *)auth
				 cpu:(NSString *)cpu
				user:(NSString *)user
				pass:(NSString *)pass
{
	self = [super init];
	[self setTitle: title];
	[self setAuth: auth];
	[self setCpu: cpu];
	[self setUser: user];
	[self setPass: pass];
	
	return self;
}

- (id)proplst
{
    NSArray *keys = [NSArray arrayWithObjects:
                     @"title",
                     @"auth",
                     @"cpu",
                     @"user",
                     @"pass",
                     nil];
    return [self dictionaryWithValuesForKeys:keys];
}


@end

enum {
	ConTitle,
	ConAuth,
	ConCpu,
	ConUser,
	ConPass,
};

@interface DetailController : UITableViewController <UITextFieldDelegate>
{
	Connection *_con;
	ConViewController *_list;
	EditableDetailCell *_titleCell;
	EditableDetailCell *_authCell;
	EditableDetailCell *_cpuCell;
	EditableDetailCell *_userCell;
	EditableDetailCell *_passCell;
}

@property (nonatomic, retain) Connection *con;
@property (nonatomic, retain) ConViewController *list;
@property (nonatomic, retain) EditableDetailCell *titleCell;
@property (nonatomic, retain) EditableDetailCell *authCell;
@property (nonatomic, retain) EditableDetailCell *cpuCell;
@property (nonatomic, retain) EditableDetailCell *userCell;
@property (nonatomic, retain) EditableDetailCell *passCell;


@end

@implementation DetailController

@synthesize con = _con;
@synthesize list = _list;
@synthesize titleCell = _titleCell;
@synthesize authCell = _authCell;
@synthesize cpuCell = _cpuCell;
@synthesize userCell = _userCell;
@synthesize passCell = _passCell;

- (void)dealloc
{
	[_con release];
	[_list release];
	[_titleCell release];
	[_authCell release];
	[_cpuCell release];
	[_userCell release];
	[_passCell release];

	[super dealloc];
}

- (BOOL)isModal
{
    NSArray *viewControllers = [[self navigationController] viewControllers];
    UIViewController *rootViewController = [viewControllers objectAtIndex:0];
    
    return rootViewController == self;
}

- (EditableDetailCell *)newDetailCellWithTag:(NSInteger)tag
								   leftLabel:(NSString*)lbltxt
{
    EditableDetailCell *cell = [[EditableDetailCell alloc] initWithFrame:CGRectZero 
                                                         reuseIdentifier:nil];
    [[cell textField] setDelegate:self];
    [[cell textField] setTag:tag];
    
	UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 50, 40)];
	lbl.text = lbltxt;

	cell.textField.leftView = lbl;
	cell.textField.leftViewMode = UITextFieldViewModeAlways;
	if(![lbltxt compare: @"pass"])
		cell.textField.secureTextEntry = YES;
	[lbl release];
	
    return cell;
}

- (void)save
{
	[[self list] addObject:[self con]];
	[[self list] save];
	[self dismissModalViewControllerAnimated:YES];
}

- (void)cancel
{
	[self dismissModalViewControllerAnimated:YES];
}

static char *nargv[] = {"drawterm","-c","127.0.0.1","-a","127.0.0.1","-u","glenda",NULL};
static int nargc = 7;

static void *dt_thread(void *a)
{
	dt_main(nargc, nargv);
	printf("ending dt_thread\n");
	pthread_exit(NULL);
}

- (void)connect
{
	pthread_t t;

	nargv[2] = strdup([self.con.auth UTF8String]);
	nargv[4] = strdup([self.con.cpu UTF8String]);
	nargv[6] = strdup([self.con.user UTF8String]);
	userpass = strdup([self.con.pass UTF8String]);

	[[UIApplication sharedApplication] setStatusBarHidden:YES];
	[[UIApplication sharedApplication] setStatusBarOrientation: UIInterfaceOrientationLandscapeRight animated:YES];
	[self.view removeFromSuperview];
	[self.navigationController setNavigationBarHidden: YES];
	//[uiview becomeFirstResponder];



	pthread_create(&t, NULL, dt_thread, NULL);
}

- (void)viewDidLoad
{
    if ([self isModal]) // pressed '+' rather than modifying
    {
        UIBarButtonItem *saveButton = [[UIBarButtonItem alloc] 
                                       initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                       target:self
                                       action:@selector(save)];
        [[self navigationItem] setRightBarButtonItem:saveButton];
        [saveButton release];
        
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] 
                                         initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                         target:self
                                         action:@selector(cancel)];
        [[self navigationItem] setLeftBarButtonItem:cancelButton];
        [cancelButton release];
    } else {
        UIBarButtonItem *connectButton = [[UIBarButtonItem alloc]
                                       initWithBarButtonSystemItem:UIBarButtonSystemItemPlay
                                       target:self
                                       action:@selector(connect)];
        [[self navigationItem] setRightBarButtonItem:connectButton];
        [connectButton release];
	}
    
    [self setTitleCell:    [self newDetailCellWithTag:ConTitle leftLabel:@"title"]];
    [self setAuthCell:   [self newDetailCellWithTag:ConAuth leftLabel:@"auth"]];
    [self setCpuCell:   [self newDetailCellWithTag:ConCpu leftLabel:@"cpu"]];
    [self setUserCell:     [self newDetailCellWithTag:ConUser leftLabel:@"user"]];
    [self setPassCell:[self newDetailCellWithTag:ConPass leftLabel:@"pass"]];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    NSUInteger indexes[] = { 0, 0 };
    NSIndexPath *indexPath = [NSIndexPath indexPathWithIndexes:indexes
                                                        length:2];
    
    EditableDetailCell *cell = (EditableDetailCell *)[[self tableView]
                                                      cellForRowAtIndexPath:indexPath];
    
    [[cell textField] becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    for (NSUInteger section = 0; section < [[self tableView] numberOfSections]; section++)
    {
        NSUInteger indexes[] = { section, 0 };
        NSIndexPath *indexPath = [NSIndexPath indexPathWithIndexes:indexes
                                                            length:2];
        
        EditableDetailCell *cell = (EditableDetailCell *)[[self tableView]
                                                          cellForRowAtIndexPath:indexPath];
        if ([[cell textField] isFirstResponder])
        {
            [[cell textField] resignFirstResponder];
        }
    }
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    if ([textField tag] == ConPass)
		[textField setReturnKeyType:UIReturnKeyDone];
    
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{    
    NSString *text = [textField text];
    NSUInteger tag = [textField tag];
	//NSUInteger row = [indexPath row];

    switch (tag)
    {
        case ConTitle:  [_con setTitle:text];   break;
        case ConAuth:	[_con setAuth:text];	break;
		case ConCpu:	[_con setCpu:text];		break;
        case ConUser:	[_con setUser:text];	break;
        case ConPass:	[_con setPass:text];	break;
    }
	
	[[self list] save];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
	[[self list] save];
	
    if ([textField returnKeyType] == UIReturnKeyNext) {
		NSInteger nextTag = [textField tag] + 1;
        UIView *nextTextField = [[self tableView] viewWithTag:nextTag];
        [nextTextField becomeFirstResponder];
    } else if ([self isModal]) {
        [self save];
    } else {
        [[self navigationController] popViewControllerAnimated:YES];
    }
    
    return YES;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView 
{
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section
{
	if (section == 0)
		return 1;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView
titleForHeaderInSection:(NSInteger)section
{
    switch (section)
    {
        case 0:  return @"Title";
        case 1:  return @"Hosts";
        case 2:  return @"Login";
    }
    
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    EditableDetailCell *cell = nil;
    NSString *text = nil;
	NSUInteger row = [indexPath row];
    NSUInteger section = [indexPath section];

    switch (section) {
        case 0:
            cell = [self titleCell];
            text = [_con title];
            break;
        case 1:
			if (row == 0) {
				cell = [self authCell];
				text = [_con auth];
			} else {
				cell = [self cpuCell];
				text = [_con cpu];
			}
            break;
        case 2:
			if (row == 0) {
				cell = [self userCell];
				text = [_con user];
			} else {
				cell = [self passCell];
				text = [_con pass];
			}
            break;
    }
    
    UITextField *textField = [cell textField];
    [textField setText:text];
    
    return cell;
}


@end
	
@implementation ConViewController

@synthesize displayedObjects = _displayedObjects;

- (void) dealloc
{
	[_displayedObjects release];
	[super dealloc];
}

+ (NSString *)pathForDocumentWithName:(NSString *)documentName
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, 
                                                         YES);
    NSString *path = [paths objectAtIndex:0];
    
    return [path stringByAppendingPathComponent:documentName];
}

- (NSMutableArray *)displayedObjects
{
	if (_displayedObjects == nil) {
		_displayedObjects = [[NSMutableArray alloc] initWithCapacity: 0];
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		NSArray *data = [ud objectForKey:@"connections"];
		for (NSDictionary *condesc in data) {
			Connection *con = [[Connection alloc] init];
			for (NSString *key in condesc) {
				NSString *val = [condesc objectForKey:key];
				if (![key compare: @"title"]) con.title = val;
				else if (![key compare: @"auth"]) con.auth = val;
				else if (![key compare: @"cpu"]) con.cpu = val;
				else if (![key compare: @"user"]) con.user = val;
				else if (![key compare: @"pass"]) con.pass = val;
			}
			[_displayedObjects addObject:con];
		}
		
	}

	return _displayedObjects;
}

- (void)save
{
//	NSLog(@"saving prefs\n");
	
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	NSMutableArray *ma = [[NSMutableArray alloc] init];
	for (Connection *c in _displayedObjects) {
		[ma addObject: [c proplst]];
	}
	NSArray *uarr = [NSArray arrayWithArray:ma];
	[ud setObject: uarr forKey: @"connections"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)addObject:(id)anObject
{
	if (anObject != nil)
		[[self displayedObjects] addObject:anObject];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[[self tableView] reloadData];
}

- (void)viewDidLoad
{
	[self setTitle:[NSString stringWithFormat:@"Drawterm (%s)\tServers", DRAWTERM_VERSION]];
	[[self tableView] setRowHeight: 54.0]; // XXX check
	[[self navigationItem] setLeftBarButtonItem:[self editButtonItem]];
	UIBarButtonItem *addButton = [[UIBarButtonItem alloc]
								  initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
								  target:self 
								  action:@selector(add)];
	[[self navigationItem] setRightBarButtonItem:addButton];
	[addButton release];
}

- (void)setEditing:(BOOL)editing
		  animated:(BOOL)animated
{
	[super setEditing:editing
			 animated:animated];
	UIBarButtonItem *editButton = [[self navigationItem] rightBarButtonItem];
	[editButton setEnabled:!editing];
}


- (void)add
{

    DetailController *controller = [[DetailController alloc]
                                      initWithStyle:UITableViewStyleGrouped];
    
    id con = [[Connection alloc] init];
    [controller setCon:con];
    [controller setList:self];
    
    UINavigationController *newNavController = [[UINavigationController alloc]
                                                initWithRootViewController:controller];
    
    [[self navigationController] presentModalViewController:newNavController
                                                   animated:YES];
    
    [con release];
    [controller release];

//	printf("wanting to add...\n");
}

- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    DetailController *controller = [[DetailController alloc]
                                      initWithStyle:UITableViewStyleGrouped];
    NSUInteger index = [indexPath row];
    id con = [[self displayedObjects] objectAtIndex:index];
	
	[controller setCon: con];
	[controller setTitle: [con title]];
    [controller setList:self];

    
    [[self navigationController] pushViewController:controller
                                           animated:YES];
	[controller release];
}

- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section
{
    return [[self displayedObjects] count];
}

- (BOOL)tableView:(UITableView *)tableView
canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void) tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toIndexPath:(NSIndexPath *)targetIndexPath
{
    NSUInteger sourceIndex = [sourceIndexPath row];
    NSUInteger targetIndex = [targetIndexPath row];
    
    if (sourceIndex != targetIndex)
    {
        [[self displayedObjects] exchangeObjectAtIndex:sourceIndex
                                     withObjectAtIndex:targetIndex];
    }
}

- (void) tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle 
 forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete)
    {
        [[self displayedObjects] removeObjectAtIndex:[indexPath row]];
        
        //  Animate deletion
        NSArray *indexPaths = [NSArray arrayWithObject:indexPath];
        [[self tableView] deleteRowsAtIndexPaths:indexPaths
                                withRowAnimation:UITableViewRowAnimationFade];
    }
}
- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath 
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"connectionCell"];
    
    if (cell == nil)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:@"connectionCell"];
        
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        
       // UIFont *titleFont = [UIFont fontWithName:@"Georgia-BoldItalic" size:18.0];
        //[[cell textLabel] setFont:titleFont];
        
    //    UIFont *detailFont = [UIFont fontWithName:@"Georgia" size:16.0];
      //  [[cell detailTextLabel] setFont:detailFont];
        
        [cell autorelease];
    }
    
    NSUInteger index = [indexPath row];
    id con = [[self displayedObjects] objectAtIndex:index];
    
    NSString *title = [con title];
    [[cell textLabel] setText:(title == nil || [title length] < 1 ? @"?" : title)];
    
	/*
    NSString *detailText = [NSString stringWithFormat:
                            @"%@    %@",
                            [book publicationYear],
                            [book author]];
    
    [[cell detailTextLabel] setText:detailText];
    
	 
    NSString *path = [book imageFilePath];
    if (path != nil)
    {
        UIImage *image = [UIImage imageNamed:path];
        image = [image imageScaledToSize:CGSizeMake(36.0, 42.0)];
        [[cell imageView] setImage:image];
    }
    */
	 
    return cell;
}

@end

@interface TermWindow : UIWindow {
}

@end

@implementation TermWindow

-(void)sendEvent:(UIEvent *)event {
	//loop over touches for this event
	for(UITouch *touch in [event allTouches]) {
		//BOOL touchEnded = (touch.phase == UITouchPhaseEnded);
		//BOOL isSingleTap = (touch.tapCount == 1);
		//if (touch.view.class == [TermView class])
		CGPoint v = [touch locationInView: uiview];
		CGPoint p;
		
		p.x = v.y;
		p.y = [uiview bounds].size.width - v.x;
		
		if (touch.phase == UITouchPhaseBegan)
			screen_touch_began((void*)touch, p.x, p.y);
		else if (touch.phase == UITouchPhaseMoved)
			screen_touch_moved((void*)touch, p.x, p.y);
		else if (touch.phase == UITouchPhaseEnded)
			screen_touch_ended((void*)touch, p.x, p.y);
		else if (touch.phase == UITouchPhaseCancelled)
			screen_touch_cancelled((void*)touch, p.x, p.y);
	}
	[super sendEvent:event];
}

@end
void
loglocation()
{
	[locMgr startUpdatingLocation];
}

void
logheading()
{
	[locMgr startUpdatingHeading];
	// XXX: some devices don't have a compass. we should fail here right away
}

@interface App : UIApplication <UIAccelerometerDelegate, CLLocationManagerDelegate, UIImagePickerControllerDelegate> {
}
@end

@implementation App
// startUpdatingHeading

- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)loc
           fromLocation:(CLLocation *)oldLocation
{
	sendlocation(loc.coordinate.longitude, loc.coordinate.latitude, loc.altitude, loc.horizontalAccuracy, loc.verticalAccuracy, 0);
}

- (void)locationManager:(CLLocationManager *)manager didUpdateHeading:(CLHeading *)newHeading
{
	sendheading(	newHeading.magneticHeading,
					newHeading.trueHeading,
					newHeading.headingAccuracy,
					0); // did not fail
}

- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error
{
	sendlocation(0,0,0,0,0, 1);
	NSLog(@"fail!\n");
}

- (void)accelerometer:(UIAccelerometer *)accelerometer didAccelerate:(UIAcceleration *)acceleration
{
	sendaccel(acceleration.x, acceleration.y, acceleration.z);
}

#define deg2rad(__ANGLE__) ((__ANGLE__) / 180.0 * M_PI)

- (void)simulatedAccel
{
	static float rot = 0.0;
	rot += 0.1;
	if (rot > 360.0)
		rot -= 360.0;
	sendaccel(sinf(deg2rad(rot)), cosf(deg2rad(rot)), 0.0);
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
	NSLog(@"didFinish picking with info\n");
}

- (void)imagePickerController:(UIImagePickerController *)picker
        didFinishPickingImage:(UIImage *)image
				  editingInfo:(NSDictionary *)editingInfo
{
	NSLog(@"didFinish picking\n");
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
	NSLog(@"didCancel picking\n");
	
	
	[picker.view removeFromSuperview];
}

- (void)applicationDidFinishLaunching:(UIApplication *)application {  
    window = [[TermWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

#if TARGET_IPHONE_SIMULATOR
	[NSTimer scheduledTimerWithTimeInterval:1.0/10.0 target:self selector:@selector(simulatedAccel) userInfo:nil repeats:YES];
#else
	UIAccelerometer *a = [UIAccelerometer sharedAccelerometer];
	a.updateInterval = 1.0 / 100.0;
	a.delegate = self;
#endif
	
	locMgr = [[CLLocationManager alloc] init];
	locMgr.delegate = self;


	
	CGRect r = [[UIScreen mainScreen] bounds];
	//r.origin.y = 25;
	//r.size.height -= 25;
	//r.size.height = 200;
	uiview = [[TermView alloc] initWithFrame:r];
	[window addSubview: uiview];

	UITextField *uitext = [[UITextField alloc] initWithFrame:r];
	[window addSubview:uitext];

	TermViewController *tvc = [[TermViewController alloc] init];
	tvc.view = uitext;

	ConViewController *rootViewController = [[ConViewController alloc] initWithStyle:UITableViewStylePlain];
	UINavigationController *navcont = [[UINavigationController alloc] initWithRootViewController:rootViewController];
	[window addSubview:[navcont view]];


	//bitpicker = [[UIImagePickerController alloc] init];
	//bitpicker.delegate = self;
//    bitpicker.sourceType = UIImagePickerControllerSourceTypeCamera; //UIImagePickerControllerSourceTypePhotoLibrary;
    //bitpicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;

//	[window addSubview:bitpicker.view];
	//[window presentModalViewController:bitpicker animated:YES];

    [window makeKeyAndVisible];
}

@end

int
main(int argc, char **argv)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	UIApplicationMain(argc, argv, @"App", nil);
    [pool release];	
}
