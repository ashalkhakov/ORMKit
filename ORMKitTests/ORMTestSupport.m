/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

@implementation ORMTestCase
{
	NSUndoManager *_undoManager;
}

- (NSString *)fixturePath:(NSString *)name
{
	NSString *here = [[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent];
	/* gnustep-make compiles from the bundle's directory, and __FILE__ is
	 * then relative to it. */
	if (![here isAbsolutePath]) {
		here = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:here];
	}
	return [[here stringByAppendingPathComponent:@"Fixtures"] stringByAppendingPathComponent:name];
}

- (NSData *)fixtureData:(NSString *)name
{
	NSData *data = [NSData dataWithContentsOfFile:[self fixturePath:name]];
	if (data == nil) {
		XCTFail(@"no fixture %@", name);
	}
	return data;
}

- (NSXMLDocument *)fixtureDocument:(NSString *)name
{
	NSString *reason = nil;
	NSXMLDocument *document = ORMParseDocument([self fixtureData:name], &reason);
	if (document == nil) {
		XCTFail(@"%@ does not parse: %@", name, reason);
	}
	return document;
}

- (NSUndoManager *)undoManager
{
	return _undoManager;
}

- (ORMEditor *)newEditor
{
	_undoManager = [[NSUndoManager alloc] init];
	[_undoManager setGroupsByEvent:NO];
	return [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:@"Test"] undoManager:_undoManager];
}

@end
