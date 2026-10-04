/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMAppDelegate.h"
#import "ORMCanvasView.h"
#import "ORMDocument.h"
#import "ORMSampleMenu.h"

@interface ORMAppDelegate ()
@property (nonatomic, strong) IBOutlet NSMenu *mainMenu;
@property (nonatomic, strong) IBOutlet NSMenu *sampleMenu;
@end

@implementation ORMAppDelegate

/* MainMenu.xib, from the bundle the class is in: the application's, or a
 * test bundle's, with the samples that bundle has. GNUstep wants the
 * Window menu named. */
- (NSMenu *)loadMainMenu
{
	NSBundle *bundle = [NSBundle bundleForClass:[ORMAppDelegate class]];
	NSNib *nib = [[NSNib alloc] initWithNibNamed:@"MainMenu" bundle:bundle];
	if (![nib instantiateWithOwner:self topLevelObjects:NULL]) {
		return nil;
	}
	[ORMSampleMenu fillMenu:self.sampleMenu
	             withModels:[ORMSampleMenu modelsInBundle:bundle]
	                folders:[ORMSampleMenu foldersInBundle:bundle]];
	NSMutableArray *pending = [NSMutableArray arrayWithObject:self.mainMenu];
	while ([pending count] > 0) {
		NSMenu *menu = [pending lastObject];
		[pending removeLastObject];
		for (NSMenuItem *item in [menu itemArray]) {
			if ([item submenu] != nil) {
				[pending addObject:[item submenu]];
			} else if ([item action] == @selector(arrangeInFront:)) {
				[NSApp setWindowsMenu:[item menu]];
			}
		}
	}
	return self.mainMenu;
}

+ (NSMenu *)newMainMenu
{
	return [[[ORMAppDelegate alloc] init] loadMainMenu];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
	(void)notification;
	[NSApp setMainMenu:[self loadMainMenu]];
}

- (IBAction)openSample:(id)sender
{
	NSError *error = nil;
	ORMDocument *document = [ORMDocument sampleWithContentsOfURL:[sender representedObject] error:&error];
	if (document == nil) {
		[NSApp presentError:error];
		return;
	}
	[[NSDocumentController sharedDocumentController] addDocument:document];
	[document makeWindowControllers];
	[document showWindows];
}

/* A blank model when the app starts with nothing to open, as a
 * document-based app does. */
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	(void)sender;
	return YES;
}

/* GNUstep quits when the last window closes otherwise. */
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	(void)sender;
	return NO;
}

@end
