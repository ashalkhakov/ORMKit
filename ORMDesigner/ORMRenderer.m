/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMRenderer.h"

/* Whether the view being drawn is in a dark appearance. */
static BOOL
ORMIsDark(void)
{
#if defined(__APPLE__)
	if (@available(macOS 10.14, *)) {
		NSAppearanceName name = [[NSAppearance currentAppearance]
			bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
		return [name isEqualToString:NSAppearanceNameDarkAqua];
	}
#endif
	return NO;
}

NSColor *
ORMInkColor(void)
{
	return DKNSColor(ORMDiagramInk(ORMIsDark()));
}

NSColor *
ORMPaperColor(void)
{
	return DKNSColor(ORMDiagramPaper(ORMIsDark()));
}

NSColor *
ORMConstraintColor(ORMModality modality)
{
	return DKNSColor(ORMDiagramConstraint(modality, ORMIsDark()));
}

NSSize
ORMReadingSizeFor(NSString *text, ORMDiagram *diagram)
{
	return ORMReadingSizeOn([DKAppKitSurface surface], text, diagram);
}

NSRect
ORMDrawingBounds(ORMDiagram *diagram)
{
	return ORMPaintedBounds(diagram, [DKAppKitSurface surface]);
}
