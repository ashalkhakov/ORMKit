/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* The designer's updates.  On macOS, Sparkle (ORMUpdater-Apple.m): the
 * newest release's appcast (SUFeedURL in ORMDesigner-Info.plist, its
 * updates signed with the key SUPublicEDKey names) is checked once a day if
 * the user allows it, and ORMDesigner > Check for Updates... checks now.  On
 * GNUstep (ORMUpdater-GNUstep.m), the stack's GSUpdater: on Windows
 * WinSparkle, its feed the newest release's appcast-windows.xml
 * (SUWindowsFeedURL, which the installer's build writes into
 * Info-gnustep.plist with SUPublicEDKey, the same key's); on Linux nothing,
 * the AppImage carrying its own update information, for AppImageUpdate,
 * Gear Lever and the like.  In the test bundles (ORMUpdater.m), nothing. */
@interface ORMUpdater : NSObject

/* Started at once unless told not to: a test reaches no network. */
- (instancetype)initStarting:(BOOL)start;
/* Whether this system has an updater at all (Check for Updates... shown). */
@property (nonatomic, readonly) BOOL available;
@property (nonatomic, readonly) BOOL canCheckForUpdates;
- (IBAction)checkForUpdates:(id)sender;

@end
