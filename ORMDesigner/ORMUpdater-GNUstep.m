/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMUpdater.h"
#import <GSUpdater/GSUpdater.h>

/* GNUstep: the stack's GSUpdater (ORMUpdater.h) -- WinSparkle on Windows;
 * on Linux nothing, the AppImage being updated from outside it. */
@implementation ORMUpdater {
	GSUpdater *_updater;
}

- (instancetype)initStarting:(BOOL)start
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	_updater = [[GSUpdater alloc] initStarting:start];
	return self;
}

- (BOOL)available
{
	return [_updater available];
}

- (BOOL)canCheckForUpdates
{
	return [_updater canCheckForUpdates];
}

- (IBAction)checkForUpdates:(id)sender
{
	[_updater checkForUpdates:sender];
}

@end
