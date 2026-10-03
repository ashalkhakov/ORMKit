/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "ORMAppDelegate.h"

int
main(int argc, const char *argv[])
{
	(void)argc;
	(void)argv;
	@autoreleasepool {
		[NSApplication sharedApplication];
		/* Before anything opens: the shared controller puts itself in the
		 * responder chain ahead of the app delegate, so File > Open, Save
		 * and Close reach the document. */
		(void)[NSDocumentController sharedDocumentController];
		ORMAppDelegate *delegate = [[ORMAppDelegate alloc] init];
		[NSApp setDelegate:delegate];
#if !defined(GNUSTEP)
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		[NSApp activateIgnoringOtherApps:YES];
#endif
		[NSApp run];
	}
	return 0;
}
