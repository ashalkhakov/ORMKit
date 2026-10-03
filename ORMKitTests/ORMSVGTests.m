/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* Diagrams as SVG: drawn by the painter the editor draws with, so what
 * is checked here is that the SVG is a document and says what the
 * diagram shows. */
@interface ORMSVGTests : ORMTestCase
@end

@implementation ORMSVGTests

- (NSXMLDocument *)parse:(NSString *)svg
{
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:svg options:0 error:&error];
	XCTAssertNotNil(document, @"%@", error);
	return document;
}

- (NSArray<NSString *> *)texts:(NSXMLDocument *)document
{
	NSMutableArray *texts = [NSMutableArray array];
	NSMutableArray *pending = [NSMutableArray arrayWithObject:[document rootElement]];
	while ([pending count] > 0) {
		NSXMLElement *element = [pending lastObject];
		[pending removeLastObject];
		if ([[element localName] isEqualToString:@"text"]) {
			[texts addObject:[element stringValue]];
		}
		for (NSXMLNode *child in [element children]) {
			if ([child kind] == NSXMLElementKind) {
				[pending addObject:child];
			}
		}
	}
	return texts;
}

- (void)testADiagramIsAnSVGDocumentOfWhatItShows
{
	ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:@"StockMate.orm"] reason:NULL];
	ORMDiagram *diagram = [model.diagrams firstObject];
	NSString *svg = ORMSVGOfDiagram(diagram, NO);
	NSXMLDocument *document = [self parse:svg];
	NSXMLElement *root = [document rootElement];
	XCTAssertEqualObjects([root localName], @"svg");
	XCTAssertEqualObjects([root URI], @"http://www.w3.org/2000/svg");
	XCTAssertNotNil([[root attributeForName:@"viewBox"] stringValue]);
	NSArray *texts = [self texts:document];
	/* Every object type it shows, by name, and its readings. */
	for (ORMShape *shape in diagram.shapes) {
		if (shape.kind == ORMShapeObjectType) {
			XCTAssertTrue([texts containsObject:shape.objectType.name], @"%@ missing", shape.objectType.name);
		}
	}
	XCTAssertTrue([texts containsObject:@"(.Id)"]);
	XCTAssertTrue([texts containsObject:@"is identified by"]);
	XCTAssertTrue([texts containsObject:@"ac"]);
	NSString *title = [NSString stringWithFormat:@"<title>%@</title>", diagram.name];
	XCTAssertTrue([svg rangeOfString:title].location != NSNotFound);
	/* NORMA's colours: object types navy, constraints violet. */
	XCTAssertTrue([svg rangeOfString:@"stroke=\"#00008c\""].location != NSNotFound);
	XCTAssertTrue([svg rangeOfString:@"#800080"].location != NSNotFound);
	XCTAssertTrue([svg rangeOfString:@"stroke-dasharray"].location != NSNotFound);
}

- (void)testDarkPaper
{
	ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:@"StockMate.orm"] reason:NULL];
	NSString *svg = ORMSVGOfDiagram([model.diagrams firstObject], YES);
	XCTAssertTrue([svg rangeOfString:@"fill=\"#1f1f21\""].location != NSNotFound);
}

/* Every diagram NORMA wrote draws: objectifications, subtyping, notes,
 * every kind of constraint shape. */
- (void)testEveryNormaDiagramDraws
{
	for (NSString *name in [self normaFixtures]) {
		ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:name] reason:NULL];
		for (ORMDiagram *diagram in model.diagrams) {
			NSXMLDocument *document = [self parse:ORMSVGOfDiagram(diagram, NO)];
			XCTAssertTrue(([[[document rootElement] children] count] > 2), @"%@: %@", name, diagram.name);
		}
	}
}

@end
