/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMUpdater.h"

/* GNUstep: the AppImage is updated from outside it (ORMUpdater.h). */
@implementation ORMUpdater

- (instancetype)initStarting:(BOOL)start
{
	(void)start;
	return [super init];
}

- (BOOL)available
{
	return NO;
}

- (BOOL)canCheckForUpdates
{
	return NO;
}

- (IBAction)checkForUpdates:(id)sender
{
	(void)sender;
}

@end
