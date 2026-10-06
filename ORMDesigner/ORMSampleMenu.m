/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMSampleMenu.h"

@implementation ORMSampleMenu

/* The bundle's resource folder of the name, if it has it. */
+ (NSURL *)folderNamed:(NSString *)name inBundle:(NSBundle *)bundle
{
	NSString *path = [[bundle resourcePath] stringByAppendingPathComponent:name];
	BOOL directory = NO;
	if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] || !directory) {
		return nil;
	}
	return [NSURL fileURLWithPath:path isDirectory:YES];
}

+ (NSArray<NSURL *> *)sorted:(NSArray<NSURL *> *)models
{
	return [models sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
		return [[a lastPathComponent] caseInsensitiveCompare:[b lastPathComponent]];
	}];
}

+ (NSArray<NSURL *> *)modelsInBundle:(NSBundle *)bundle
{
	NSMutableArray *models = [NSMutableArray array];
	NSURL *samples = [self folderNamed:@"Samples" inBundle:bundle];
	if (samples != nil) {
		[models addObjectsFromArray:[self modelsIn:samples]];
	}
	if ([bundle resourcePath] != nil) {
		[models addObjectsFromArray:[self modelsIn:[NSURL fileURLWithPath:[bundle resourcePath] isDirectory:YES]]];
	}
	return [self sorted:models];
}

+ (NSArray<NSURL *> *)foldersInBundle:(NSBundle *)bundle
{
	NSURL *activeFacts = [self folderNamed:@"ActiveFacts" inBundle:bundle];
	return activeFacts != nil ? @[ activeFacts ] : @[];
}

+ (NSArray<NSURL *> *)modelsIn:(NSURL *)folder
{
	NSMutableArray *models = [NSMutableArray array];
	for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[folder path] error:NULL]) {
		if ([[name pathExtension] isEqualToString:@"orm"]) {
			[models addObject:[folder URLByAppendingPathComponent:name]];
		}
	}
	return [self sorted:models];
}

+ (void)addModels:(NSArray<NSURL *> *)models to:(NSMenu *)menu
{
	for (NSURL *model in models) {
		NSMenuItem *item = [menu addItemWithTitle:[[model lastPathComponent] stringByDeletingPathExtension]
		                                   action:@selector(openSample:)
		                            keyEquivalent:@""];
		[item setRepresentedObject:model];
	}
}

+ (void)fillMenu:(NSMenu *)menu withModels:(NSArray<NSURL *> *)models folders:(NSArray<NSURL *> *)folders
{
	[menu removeAllItems];
	[self addModels:models to:menu];
	for (NSURL *folder in folders) {
		NSString *name = [folder lastPathComponent];
		NSMenu *submenu = [[NSMenu alloc] initWithTitle:name];
		[self addModels:[self modelsIn:folder] to:submenu];
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
