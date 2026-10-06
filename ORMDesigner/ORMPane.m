/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1.
   ORMTabBadge is ported from RDLTabBadge (RDLKit, LGPL 2.1), itself from
   XFDBadge in the XForms Designer (XFormsKit, LGPL 2.1). */
#import "ORMPane.h"

void
ORMFillHost(NSView *host, NSView *view)
{
	if (host == nil || view == nil) {
		return;
	}
	[view setFrame:[host bounds]];
	[view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[host addSubview:view];
}

BOOL
ORMLoadPaneNib(NSView *pane, NSString *name)
{
	NSNib *nib = [[NSNib alloc] initWithNibNamed:name bundle:[NSBundle bundleForClass:[pane class]]];
	return nib != nil && [nib instantiateWithOwner:pane topLevelObjects:NULL];
}

NSImage *
ORMTabBadge(NSString *letters, double red, double green, double blue)
{
	static NSMutableDictionary *cache;
	if (cache == nil) {
		cache = [NSMutableDictionary dictionary];
	}
	NSString *key = [NSString stringWithFormat:@"%@|%.2f%.2f%.2f", letters, red, green, blue];
	NSImage *image = [cache objectForKey:key];
	if (image != nil) {
		return image;
	}
	NSSize size = NSMakeSize(15, 15);
	image = [[NSImage alloc] initWithSize:size];
	/* -lockFocus is deprecated on macOS and what GNUstep implements; its
	 * replacement has no counterpart there. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	[image lockFocus];
	[[NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0] set];
	[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0.5, 0.5, 14, 14)] fill];
	NSDictionary *attributes = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[letters length] > 1 ? 7.0 : 9.0],
		                          NSForegroundColorAttributeName: [NSColor whiteColor] };
	NSSize text = [letters sizeWithAttributes:attributes];
	[letters drawAtPoint:NSMakePoint((size.width - text.width) / 2, (size.height - text.height) / 2) withAttributes:attributes];
	[image unlockFocus];
#pragma clang diagnostic pop
	[cache setObject:image forKey:key];
	return image;
}
