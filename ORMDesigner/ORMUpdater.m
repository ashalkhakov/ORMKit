/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMUpdater.h"

/* In the test bundles: nothing, so that a test reaches no network
 * (ORMUpdater.h).  The application has ORMUpdater-Apple.m (Sparkle) and
 * ORMUpdater-GNUstep.m (the stack's GSUpdater). */
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
