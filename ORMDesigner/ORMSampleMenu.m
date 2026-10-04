/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMSampleMenu.h"

@implementation ORMSampleMenu

+ (NSArray<NSURL *> *)foldersInBundle:(NSBundle *)bundle
{
	NSMutableArray *folders = [NSMutableArray array];
	for (NSString *name in @[ @"Samples", @"ActiveFacts" ]) {
		NSString *path = [[bundle resourcePath] stringByAppendingPathComponent:name];
		BOOL directory = NO;
		if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory) {
			[folders addObject:[NSURL fileURLWithPath:path isDirectory:YES]];
		}
	}
	return folders;
}

/* The folder's models, by name. */
+ (NSArray<NSURL *> *)modelsIn:(NSURL *)folder
{
	NSMutableArray *models = [NSMutableArray array];
	for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[folder path] error:NULL]) {
		if ([[name pathExtension] isEqualToString:@"orm"]) {
			[models addObject:[folder URLByAppendingPathComponent:name]];
		}
	}
	return [models sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
		return [[a lastPathComponent] caseInsensitiveCompare:[b lastPathComponent]];
	}];
}

+ (void)addModelsIn:(NSURL *)folder to:(NSMenu *)menu
{
	for (NSURL *model in [self modelsIn:folder]) {
		NSMenuItem *item = [menu addItemWithTitle:[[model lastPathComponent] stringByDeletingPathExtension]
		                                   action:@selector(openSample:)
		                            keyEquivalent:@""];
		[item setRepresentedObject:model];
	}
}

+ (void)fillMenu:(NSMenu *)menu fromFolders:(NSArray<NSURL *> *)folders
{
	[menu removeAllItems];
	for (NSURL *folder in folders) {
		if (folder == [folders firstObject]) {
			[self addModelsIn:folder to:menu];
			continue;
		}
		NSString *name = [folder lastPathComponent];
		NSMenu *submenu = [[NSMenu alloc] initWithTitle:name];
		[self addModelsIn:folder to:submenu];
		if ([submenu numberOfItems] == 0) {
			continue;
		}
		if ([menu numberOfItems] > 0) {
			[menu addItem:[NSMenuItem separatorItem]];
		}
		[[menu addItemWithTitle:name action:NULL keyEquivalent:@""] setSubmenu:submenu];
	}
}

@end
