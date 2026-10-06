/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#include <dlfcn.h>

@implementation ORMTestCase

{
	NSUndoManager *_undoManager;
}

- (ORMQueryPlan *)archived:(ORMQueryPlan *)plan
{
	NSError *error = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:[plan propertyList]
	                                                          format:NSPropertyListXMLFormat_v1_0
	                                                         options:0
	                                                           error:&error];
	XCTAssertNotNil(data, @"%@\n%@", error, [plan text]);
	id list = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error] : nil;
	ORMQueryPlan *read = list != nil ? [ORMQueryPlan planWithPropertyList:list error:&error] : nil;
	XCTAssertNotNil(read, @"%@\n%@", error, [plan text]);
	XCTAssertEqualObjects([read propertyList], [plan propertyList], @"%@", [plan text]);
	return read ?: plan;
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

- (NSArray<NSString *> *)activeFactsFixtures
{
	NSMutableArray *names = [NSMutableArray array];
	NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[self fixturePath:@"ActiveFacts"] error:NULL];
	for (NSString *file in [files sortedArrayUsingSelector:@selector(compare:)]) {
		if ([[file pathExtension] isEqualToString:@"orm"]) {
			[names addObject:[@"ActiveFacts" stringByAppendingPathComponent:file]];
		}
	}
	if ([names count] == 0) {
		XCTFail(@"no ActiveFacts fixtures");
	}
	return names;
}

- (NSArray<NSString *> *)fixturesUnder:(NSString *)directory
{
	NSMutableArray *names = [NSMutableArray array];
	NSDirectoryEnumerator *files = [[NSFileManager defaultManager] enumeratorAtPath:[self fixturePath:directory]];
	for (NSString *file in files) {
		if ([[file pathExtension] isEqualToString:@"orm"]) {
			[names addObject:[directory stringByAppendingPathComponent:file]];
		}
	}
	if ([names count] == 0) {
		XCTFail(@"no fixtures in %@", directory);
	}
	return [names sortedArrayUsingSelector:@selector(compare:)];
}

/* NORMA's files that it would write the same way today: not
 * SampleModel.CoRef, an export whose PlayedRoles name roles it left out,
 * nor OIAL, whose binaries without uniqueness have multiplicities NORMA no
 * longer gives them. */
- (NSArray<NSString *> *)normaRepositoryFixtures
{
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *name in [[self fixturesUnder:@"NORMA/GenerationSamples"]
	                           arrayByAddingObjectsFromArray:[self fixturesUnder:@"NORMA/Documentation"]]) {
		NSString *file = [name lastPathComponent];
		if (![file isEqualToString:@"SampleModel.CoRef.orm"] && ![file isEqualToString:@"OIAL.orm"]) {
			[names addObject:name];
		}
	}
	return names;
}

- (NSArray<NSString *> *)normaFixtures
{
	NSMutableArray *names = [NSMutableArray arrayWithArray:@[ @"StockMate.orm", @"StockMate.CoRef.orm" ]];
	[names addObjectsFromArray:[self activeFactsFixtures]];
	[names addObjectsFromArray:[self normaRepositoryFixtures]];
	return names;
}

- (NSArray<NSString *> *)allNormaFiles
{
	NSMutableArray *names = [NSMutableArray arrayWithArray:[self normaFixtures]];
	[names addObjectsFromArray:@[ @"NORMA/GenerationSamples/SampleModel.CoRef.orm", @"NORMA/Documentation/OIAL.orm" ]];
	[names addObjectsFromArray:[self fixturesUnder:@"NORMA/TestSample"]];
	return names;
}

- (NSUndoManager *)undoManager
{
	return _undoManager;
}

/* XCTest keeps every test case to the end of the run: what one holds (an
 * undo manager's copies of the document, each change's) is let go of when
 * it is done. */
- (void)tearDown
{
	[_undoManager removeAllActions];
	_undoManager = nil;
	[super tearDown];
}

- (ORMEditor *)newEditor
{
	_undoManager = [[NSUndoManager alloc] init];
	[_undoManager setGroupsByEvent:NO];
	return [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:@"Test"] undoManager:_undoManager];
}

/* What Apple's model compiler says of the model, on a Mac; nil elsewhere
 * or when it accepts it. */
- (NSString *)momcRejects:(ORMCDModel *)model
{
	/* Apple's through xcrun; elsewhere FreeCoreData's, wherever PATH has it. */
	NSString *launch = nil;
	NSArray *arguments = nil;
#if defined(__APPLE__)
	launch = @"/usr/bin/xcrun";
	arguments = @[ @"momc" ];
#else
	for (NSString *directory in [[[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"] componentsSeparatedByString:@":"]) {
		NSString *candidate = [directory stringByAppendingPathComponent:@"momc"];
		if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
			launch = candidate;
			arguments = @[];
			break;
		}
	}
#endif
	if (launch == nil) {
		return nil;
	}
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	NSString *package = [directory stringByAppendingPathComponent:@"Test.xcdatamodeld"];
	NSError *error = nil;
	if (![model writeToPackage:package error:&error]) {
		return [error localizedDescription];
	}
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = launch;
	task.arguments = [arguments arrayByAddingObjectsFromArray:@[ package, [directory stringByAppendingPathComponent:@"Test.momd"] ]];
	NSPipe *pipe = [NSPipe pipe];
	task.standardError = pipe;
	task.standardOutput = pipe;
	[task launch];
	NSData *output = [[pipe fileHandleForReading] readDataToEndOfFile];
	[task waitUntilExit];
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
	NSString *text = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
	return [task terminationStatus] == 0 ? nil : text;
}

#if defined(__APPLE__)
/* The generated validation code built as a library and loaded: the class
 * headers it imports stubbed. NO, with clang's word, where it does not
 * build. */
- (BOOL)load:(NSDictionary<NSString *, NSString *> *)files in:(NSString *)directory why:(NSString **)why
{
	NSMutableArray *sources = [NSMutableArray array];
	NSMutableString *stubs = [NSMutableString stringWithString:@"#import <CoreData/CoreData.h>\n"];
	for (NSString *name in files) {
		NSString *text = [files objectForKey:name];
		[text writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		if ([name hasSuffix:@".m"]) {
			[sources addObject:[directory stringByAppendingPathComponent:name]];
		}
		NSRegularExpression *imported = [NSRegularExpression regularExpressionWithPattern:@"#import \"([A-Za-z0-9_]+)\\+CoreDataClass\\.h\""
		                                                                          options:0 error:NULL];
		for (NSTextCheckingResult *match in [imported matchesInString:text options:0 range:NSMakeRange(0, [text length])]) {
			NSString *class = [text substringWithRange:[match rangeAtIndex:1]];
			NSString *header = [NSString stringWithFormat:@"#import <CoreData/CoreData.h>\n@interface %@ : NSManagedObject\n@end\n", class];
			[header writeToFile:[directory stringByAppendingPathComponent:[class stringByAppendingString:@"+CoreDataClass.h"]]
			         atomically:YES encoding:NSUTF8StringEncoding error:NULL];
			if ([stubs rangeOfString:[NSString stringWithFormat:@"@implementation %@\n", class]].location == NSNotFound) {
				[stubs appendFormat:@"@interface %@ : NSManagedObject\n@end\n@implementation %@\n@end\n", class, class];
			}
		}
	}
	NSString *stubFile = [directory stringByAppendingPathComponent:@"Stubs.m"];
	[stubs writeToFile:stubFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
	[sources addObject:stubFile];
	NSString *library = [directory stringByAppendingPathComponent:@"Generated.dylib"];
	NSTask *clang = [[NSTask alloc] init];
	clang.launchPath = @"/usr/bin/xcrun";
	/* The driver the save hook calls (docs/RUNTIME.md): the framework the
	 * tests run with. */
	NSString *frameworks = [[[NSBundle bundleForClass:[ORMTables class]] bundlePath] stringByDeletingLastPathComponent];
	clang.arguments = [@[ @"clang", @"-fobjc-arc", @"-dynamiclib", @"-framework", @"Foundation", @"-framework", @"CoreData",
	                      @"-F", frameworks, @"-framework", @"ORMRuntime", [@"-Wl,-rpath," stringByAppendingString:frameworks],
	                      @"-o", library ] arrayByAddingObjectsFromArray:sources];
	NSPipe *output = [NSPipe pipe];
	clang.standardError = output;
	clang.standardOutput = output;
	[clang launch];
	NSData *said = [[output fileHandleForReading] readDataToEndOfFile];
	[clang waitUntilExit];
	if (clang.terminationStatus != 0) {
		*why = [[NSString alloc] initWithData:said encoding:NSUTF8StringEncoding];
		return NO;
	}
	if (dlopen([library fileSystemRepresentation], RTLD_NOW) == NULL) {
		*why = [NSString stringWithUTF8String:dlerror()];
		return NO;
	}
	return YES;
}
#endif

@end
