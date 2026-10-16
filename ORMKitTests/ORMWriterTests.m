/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* The model written as NORMA keeps it (ORMNormaWriter, docs/MODEL.md). */
@interface ORMWriterTests : ORMTestCase
@end

/* Where two texts first differ: the line, each side's. */
static NSString *
ORMFirstDifference(NSData *a, NSData *b)
{
	NSArray *left = [[[NSString alloc] initWithData:a encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
	NSArray *right = [[[NSString alloc] initWithData:b encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"];
	for (NSUInteger i = 0; i < MAX([left count], [right count]); i++) {
		NSString *l = i < [left count] ? [left objectAtIndex:i] : @"(none)";
		NSString *r = i < [right count] ? [right objectAtIndex:i] : @"(none)";
		if (![l isEqualToString:r]) {
			return [NSString stringWithFormat:@"line %lu:\n  was %@\n  now %@", (unsigned long)i + 1, l, r];
		}
	}
	return @"the same";
}

@implementation ORMWriterTests

/* Every NORMA file, every element written from the model read of it, is
 * the same bytes: the writer says all the model holds as NORMA does. */
- (void)testEveryElementWrittenFromTheModelIsWhatNormaWrote
{
	for (NSString *name in [self allNormaFiles]) @autoreleasepool {
		NSData *data = [self fixtureData:name];
		NSXMLDocument *document = ORMParseDocument(data, NULL);
		ORMModel *model = [ORMModel modelOfDocument:document reason:NULL];
		XCTAssertNotNil(model, @"%@", name);
		[[[ORMNormaWriter alloc] initWithModel:model] writeModel];
		NSData *written = ORMDataOfDocument(document);
		XCTAssertEqualObjects(written, data, @"%@: %@", name, ORMFirstDifference(data, written));
	}
}

@end
