/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMAppDelegate.h"
#import "ORMCanvasView.h"
#import "ORMDocument.h"
#import "ORMWindowController.h"

@implementation ORMAppDelegate

static NSMenuItem *
ORMItem(NSMenu *menu, NSString *title, SEL action, NSString *key, NSUInteger modifiers)
{
	NSMenuItem *item = (NSMenuItem *)[menu addItemWithTitle:title action:action keyEquivalent:key ?: @""];
	if ([key length] > 0) {
		[item setKeyEquivalentModifierMask:modifiers];
	}
	return item;
}

static NSMenu *
ORMSubmenu(NSMenu *bar, NSString *title)
{
	NSMenuItem *item = (NSMenuItem *)[bar addItemWithTitle:title action:NULL keyEquivalent:@""];
	NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
	[bar setSubmenu:menu forItem:item];
	return menu;
}

static void
ORMToolItem(NSMenu *menu, NSString *title, ORMCanvasTool tool, NSString *key)
{
	NSMenuItem *item = ORMItem(menu, title, @selector(chooseTool:), key, 0);
	[item setTag:tool];
}

+ (NSMenu *)newMainMenu
{
	const NSUInteger command = NSEventModifierFlagCommand;
	const NSUInteger shift = NSEventModifierFlagShift;
	const NSUInteger option = NSEventModifierFlagOption;
	NSMenu *bar = [[NSMenu alloc] initWithTitle:@"ORMDesigner"];

	NSMenu *app = ORMSubmenu(bar, @"ORMDesigner");
	ORMItem(app, @"About ORMDesigner", @selector(orderFrontStandardAboutPanel:), nil, 0);
	[app addItem:[NSMenuItem separatorItem]];
	ORMItem(app, @"Hide ORMDesigner", @selector(hide:), @"h", command);
	ORMItem(app, @"Quit ORMDesigner", @selector(terminate:), @"q", command);

	NSMenu *file = ORMSubmenu(bar, @"File");
	ORMItem(file, @"New", @selector(newDocument:), @"n", command);
	ORMItem(file, @"Open…", @selector(openDocument:), @"o", command);
	[file addItem:[NSMenuItem separatorItem]];
	ORMItem(file, @"Close", @selector(performClose:), @"w", command);
	ORMItem(file, @"Save", @selector(saveDocument:), @"s", command);
	ORMItem(file, @"Save As…", @selector(saveDocumentAs:), @"s", command | shift);
	ORMItem(file, @"Save a Copy for NORMA…", @selector(saveCopyForNorma:), nil, 0);
	ORMItem(file, @"Revert to Saved", @selector(revertDocumentToSaved:), nil, 0);
	[file addItem:[NSMenuItem separatorItem]];
	ORMItem(file, @"Export Diagram as PDF…", @selector(exportDiagramAsPDF:), @"e", command | shift);
	ORMItem(file, @"Export Diagram as PNG…", @selector(exportDiagramAsPNG:), nil, 0);
	ORMItem(file, @"Export Verbalization…", @selector(exportVerbalization:), nil, 0);
	[file addItem:[NSMenuItem separatorItem]];
	ORMItem(file, @"Print…", @selector(printDocument:), @"p", command);

	NSMenu *edit = ORMSubmenu(bar, @"Edit");
	ORMItem(edit, @"Undo", NSSelectorFromString(@"undo:"), @"z", command);
	ORMItem(edit, @"Redo", NSSelectorFromString(@"redo:"), @"z", command | shift);
	[edit addItem:[NSMenuItem separatorItem]];
	ORMItem(edit, @"Cut", @selector(cut:), @"x", command);
	ORMItem(edit, @"Copy", @selector(copy:), @"c", command);
	ORMItem(edit, @"Paste", @selector(paste:), @"v", command);
	ORMItem(edit, @"Delete", @selector(delete:), nil, 0);
	ORMItem(edit, @"Remove from Diagram", @selector(removeFromDiagram:), @"\b", command | shift);
	ORMItem(edit, @"Select All", @selector(selectAll:), @"a", command);

	NSMenu *model = ORMSubmenu(bar, @"Model");
	ORMToolItem(model, @"Pointer", ORMToolPointer, @"");
	ORMToolItem(model, @"Entity Type", ORMToolEntityType, @"");
	ORMToolItem(model, @"Value Type", ORMToolValueType, @"");
	ORMToolItem(model, @"Fact Type", ORMToolFactType, @"");
	ORMItem(model, @"Fact Editor", @selector(focusFactEditor:), @"f", command | option);
	ORMToolItem(model, @"Subtype", ORMToolSubtype, @"");
	ORMToolItem(model, @"Connect Role", ORMToolConnectRole, @"");
	ORMToolItem(model, @"Note", ORMToolNote, @"");
	[model addItem:[NSMenuItem separatorItem]];
	ORMItem(model, @"Toggle Uniqueness", @selector(toggleUniqueness:), @"u", command | option);
	ORMItem(model, @"Toggle Mandatory", @selector(toggleMandatory:), @"m", command | option);
	NSMenuItem *constraints = (NSMenuItem *)[model addItemWithTitle:@"Add Constraint" action:NULL keyEquivalent:@""];
	NSMenu *constraintMenu = [[NSMenu alloc] initWithTitle:@"Add Constraint"];
	ORMToolItem(constraintMenu, @"Uniqueness", ORMToolUniqueness, @"");
	ORMToolItem(constraintMenu, @"Inclusive Or (Mandatory)", ORMToolInclusiveOr, @"");
	ORMToolItem(constraintMenu, @"Exclusion", ORMToolExclusion, @"");
	ORMToolItem(constraintMenu, @"Exclusive Or", ORMToolExclusiveOr, @"");
	ORMToolItem(constraintMenu, @"Subset", ORMToolSubset, @"");
	ORMToolItem(constraintMenu, @"Equality", ORMToolEquality, @"");
	ORMToolItem(constraintMenu, @"Frequency", ORMToolFrequency, @"");
	ORMToolItem(constraintMenu, @"Ring", ORMToolRing, @"");
	ORMToolItem(constraintMenu, @"Value Comparison", ORMToolValueComparison, @"");
	[model setSubmenu:constraintMenu forItem:constraints];
	ORMItem(model, @"Next Role Sequence", @selector(nextRoleSequence:), @"\t", option);
	ORMItem(model, @"Finish Constraint", @selector(commitPending:), @"\r", command);
	[model addItem:[NSMenuItem separatorItem]];
	ORMItem(model, @"Objectify Fact Type", @selector(objectifyFactType:), nil, 0);
	ORMItem(model, @"Unobjectify Fact Type", @selector(unobjectifyFactType:), nil, 0);
	ORMItem(model, @"Show Verbalization of Model", @selector(verbalizeModel:), @"v", command | option);

	NSMenu *diagram = ORMSubmenu(bar, @"Diagram");
	ORMItem(diagram, @"New Diagram", @selector(newDiagram:), @"n", command | option);
	ORMItem(diagram, @"Rename Diagram…", @selector(renameDiagram:), nil, 0);
	ORMItem(diagram, @"Delete Diagram", @selector(deleteDiagram:), nil, 0);
	[diagram addItem:[NSMenuItem separatorItem]];
	ORMItem(diagram, @"Show Selection on Diagram", @selector(showOnDiagram:), @"d", command | option);
	ORMItem(diagram, @"Show Related", @selector(showRelated:), @"r", command | option);
	ORMItem(diagram, @"Arrange", @selector(arrangeDiagram:), nil, 0);
	ORMItem(diagram, @"Rotate Fact Type", @selector(rotateFactType:), nil, 0);
	ORMItem(diagram, @"Reverse Role Order", @selector(reverseRoleOrder:), nil, 0);
	[diagram addItem:[NSMenuItem separatorItem]];
	ORMItem(diagram, @"Zoom In", @selector(zoomIn:), @"+", command);
	ORMItem(diagram, @"Zoom Out", @selector(zoomOut:), @"-", command);
	ORMItem(diagram, @"Actual Size", @selector(zoomToActualSize:), @"0", command);
	ORMItem(diagram, @"Zoom to Fit", @selector(zoomToFit:), @"9", command);

	NSMenu *coreData = ORMSubmenu(bar, @"Core Data");
	ORMItem(coreData, @"Mappings…", @selector(showCoreDataMappings:), @"k", command | option);
	ORMItem(coreData, @"Synchronize", @selector(synchronizeCoreData:), @"k", command | option | shift);

	NSMenu *window = ORMSubmenu(bar, @"Window");
	ORMItem(window, @"Minimize", @selector(performMiniaturize:), @"m", command);
	ORMItem(window, @"Bring All to Front", @selector(arrangeInFront:), nil, 0);
	[NSApp setWindowsMenu:window];
	return bar;
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
	(void)notification;
	[NSApp setMainMenu:[ORMAppDelegate newMainMenu]];
}

/* A blank model when the app starts with nothing to open, as a
 * document-based app does. */
- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	(void)sender;
	return YES;
}

/* GNUstep quits when the last window closes otherwise. */
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	(void)sender;
	return NO;
}

@end
