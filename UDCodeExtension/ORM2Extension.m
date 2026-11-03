/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORM2Extension.h"
#import <UDCodeKit/UDCodeDocument.h>
#import <UDCodeKit/UDLanguageMode.h>
#import "ORM2EditorViewController.h"
#import "ORMModelViewController.h"

@implementation ORM2Extension

- (void)extensionDidLoad:(NSBundle *)bundle
{
	(void)bundle;
}

- (void)extensionWillUnload:(NSBundle *)bundle
{
	(void)bundle;
}

/* The mode's grammar is the XML mode's (LanguageInfo.plist's grammarOf). */
- (const void *)languageFuncForIdentifier:(NSString *)identifier
{
	(void)identifier;
	return NULL;
}

- (NSViewController *)workbench:(id<UDWorkbench>)workbench editorForDocument:(UDCodeDocument *)document
{
	if (![document.languageMode.identifier isEqualToString:@"orm"]) {
		return nil;
	}
	return [[ORM2EditorViewController alloc] initWithDocument:document workbench:workbench];
}

/* ORMDesignerKit's menus, as ORMDesigner's menu bar has them: their items
 * go to the first responder, which in an ORM2 tab is its editor; elsewhere
 * nothing takes them, and they are dimmed. */
- (NSArray<NSMenuItem *> *)editorMenuItemsForWorkbench:(id<UDWorkbench>)workbench
{
	(void)workbench;
	return [ORMModelViewController modelMenuItems];
}

@end
