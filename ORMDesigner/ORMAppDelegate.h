/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

/* The application: its menu bar, built in code so both platforms have the
 * same one, and what happens when it starts with no document. */
@interface ORMAppDelegate : NSObject <NSApplicationDelegate>
/* The menu bar, as ORMDesigner has it: what the tests check items against. */
+ (NSMenu *)newMainMenu;
@end
