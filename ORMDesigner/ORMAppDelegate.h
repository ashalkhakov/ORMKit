/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

/* The application: its menu bar (MainMenu.xib), and what happens when it
 * starts with no document. */
@interface ORMAppDelegate : NSObject <NSApplicationDelegate>
/* The menu bar, as ORMDesigner loads it: what the tests check items against. */
+ (NSMenu *)newMainMenu;
@end
