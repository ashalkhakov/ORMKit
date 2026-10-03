/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* Reading and writing NORMA's files: what NORMA wrote comes back as NORMA
 * wrote it. */
@interface ORMFileTests : ORMTestCase
@end

@implementation ORMFileTests

- (void)testANormaFileIsWrittenBackByteForByte
{
	for (NSString *name in [self allNormaFiles]) {
		NSData *data = [self fixtureData:name];
		NSXMLDocument *document = ORMParseDocument(data, NULL);
		XCTAssertEqualObjects(ORMDataOfDocument(document), data, @"%@ changed on the way through", name);
	}
}

- (void)testAnUndoSnapshotWritesAsTheFileDid
{
	NSData *data = [self fixtureData:@"StockMate.orm"];
	NSXMLDocument *copy = ORMCopyDocument(ORMParseDocument(data, NULL));
	XCTAssertEqualObjects(ORMDataOfDocument(copy), data);
}

- (void)testAnUnchangedModelIsSavedAsItWasRead
{
	for (NSString *name in [self allNormaFiles]) {
		NSData *data = [self fixtureData:name];
		ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
		XCTAssertFalse(editor.hasChanges);
		XCTAssertEqualObjects([editor dataForSaving], data, @"%@", name);
	}
}

- (void)testAFileThatIsNotXMLSaysWhy
{
	NSString *reason = nil;
	XCTAssertNil((ORMParseDocument([@"not xml" dataUsingEncoding:NSUTF8StringEncoding], &reason)));
	XCTAssertTrue([reason length] > 0);
}

- (void)testANewModelIsLaidOutAsNormaLaysItOut
{
	NSData *data = ORMDataOfDocument([ORMEditor newDocumentNamed:@"Fresh"]);
	const unsigned char *bytes = [data bytes];
	XCTAssertTrue([data length] > 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF, @"no BOM");
	NSString *text = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(3, [data length] - 3)]
	                                       encoding:NSUTF8StringEncoding];
	XCTAssertTrue([text hasPrefix:@"<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n<ormRoot:ORM2 "]);
	XCTAssertTrue([text rangeOfString:@"\r\n\t<orm:ORMModel "].location != NSNotFound);
	XCTAssertTrue([text rangeOfString:@" />"].location != NSNotFound, @"empty elements as NORMA writes them");
}

- (void)testBoundsAreInchesInTheFileAndPointsInTheModel
{
	NSRect bounds = ORMParseBounds(@"1, 0.5, 0.25, 2");
	XCTAssertEqualWithAccuracy(NSMinX(bounds), 72.0, 0.0001);
	XCTAssertEqualWithAccuracy(NSMinY(bounds), 36.0, 0.0001);
	XCTAssertEqualWithAccuracy(NSWidth(bounds), 18.0, 0.0001);
	XCTAssertEqualObjects(ORMFormatBounds(bounds), @"1, 0.5, 0.25, 2");
	NSString *odd = @"3.4083334654569626, 1.5833333702757955, 0.54499908804893493, 0.35900605320930479";
	XCTAssertEqualWithAccuracy(NSMinX(ORMParseBounds(ORMFormatBounds(ORMParseBounds(odd)))), NSMinX(ORMParseBounds(odd)),
	                           0.000001);
}

- (void)testAnEditedModelDropsWhatNormaGenerates
{
	NSXMLDocument *document = [self fixtureDocument:@"StockMate.orm"];
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:document undoManager:nil];
	ORMObjectType *product = [editor.model objectTypeNamed:@"Product"];
	XCTAssertTrue([editor.elementEditor rename:product.identifier to:@"Article" reason:NULL]);
	NSXMLDocument *saved = [editor documentForSaving];
	NSXMLElement *root = [saved rootElement];
	for (NSXMLNode *child in [root children]) {
		XCTAssertFalse([ORMGeneratedNamespaces() containsObject:[child URI]], @"%@ kept", [child name]);
	}
	XCTAssertNil((ORMChild(ORMChild(root, ORMCoreNamespace, @"ORMModel"), ORMCoreNamespace, @"ModelErrors")));
	/* What the user made stays: diagrams and their positions. */
	XCTAssertEqual(([ORMChildren(root, ORMDiagramNamespace, @"ORMDiagram") count]), (NSUInteger)4);
	XCTAssertNotNil((ORMChild(root, ORMDiagramDisplayNamespace, @"DiagramDisplay")));
}

@end
