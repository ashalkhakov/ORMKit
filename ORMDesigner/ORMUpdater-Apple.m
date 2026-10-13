/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMUpdater.h"
#import <Sparkle/Sparkle.h>

/* macOS: Sparkle's standard updater (ORMUpdater.h). */
@implementation ORMUpdater
{
	SPUStandardUpdaterController *_controller;
}

- (instancetype)initStarting:(BOOL)start
{
	if ((self = [super init])) {
		_controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:start
		                                                            updaterDelegate:nil
		                                                         userDriverDelegate:nil];
	}
	return self;
}

- (BOOL)available
{
	return YES;
}

- (BOOL)canCheckForUpdates
{
	return _controller.updater.canCheckForUpdates;
}

- (IBAction)checkForUpdates:(id)sender
{
	[_controller checkForUpdates:sender];
}

@end
