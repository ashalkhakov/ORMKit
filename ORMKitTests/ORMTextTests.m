/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* The small languages: readings and value lists. */
@interface ORMTextTests : ORMTestCase
@end

@implementation ORMTextTests

- (void)testAReadingTakesItsPlaceholdersApart
{
	ORMReadingText *reading = [ORMReadingText readingTextWithString:@"{0} includes first- {1}" arity:2 reason:NULL];
	XCTAssertEqual([reading.parts count], (NSUInteger)2);
	ORMReadingPart *first = reading.parts[0];
	ORMReadingPart *second = reading.parts[1];
	XCTAssertEqualObjects(first.followingText, @" includes ");
	XCTAssertEqualObjects(second.preBoundText, @"first ");
	NSString *text = [reading expandWithNames:^NSString *(NSUInteger index, NSString *pre, NSString *post) {
		return [NSString stringWithFormat:@"%@%@%@", pre ?: @"", index == 0 ? @"Street" : @"StreetLine", post ?: @""];
	}];
	XCTAssertEqualObjects(text, @"Street includes first StreetLine");
}

- (void)testPostBoundText
{
	ORMReadingText *reading = [ORMReadingText readingTextWithString:@"{0} is {1} -old" arity:2 reason:NULL];
	ORMReadingPart *second = reading.parts[1];
	XCTAssertEqualObjects(second.postBoundText, @" old");
	XCTAssertEqualObjects(second.followingText, @"");
}

- (void)testBadReadingsSayWhy
{
	NSString *reason = nil;
	XCTAssertNil([ORMReadingText readingTextWithString:@"{0} has" arity:2 reason:&reason]);
	XCTAssertTrue([reason length] > 0);
	XCTAssertNil([ORMReadingText readingTextWithString:@"{0} has {2}" arity:2 reason:&reason]);
	XCTAssertNil([ORMReadingText readingTextWithString:@"{1} has {1}" arity:2 reason:&reason]);
	XCTAssertNotNil([ORMReadingText readingTextWithString:@"{1} is had by {0}" arity:2 reason:&reason]);
}

- (void)testASentenceBecomesAReading
{
	NSString *reason = nil;
	XCTAssertEqualObjects(([ORMReadingText readingFromSentence:@"Person was born in Country."
	                                                withNames:@[ @"Person", @"Country" ] reason:&reason]),
	                      @"{0} was born in {1}");
	XCTAssertEqualObjects([ORMReadingText readingFromSentence:@"Person smokes" withNames:@[ @"Person" ] reason:&reason],
	                      @"{0} smokes");
	XCTAssertNil(([ORMReadingText readingFromSentence:@"Person Country" withNames:@[ @"Person", @"Country" ]
	                                          reason:&reason]), @"no predicate");
	XCTAssertNil([ORMReadingText readingFromSentence:@"Personnel smoke" withNames:@[ @"Person" ] reason:&reason],
	             @"names are whole words");
}

- (void)testValueLists
{
	NSString *reason = nil;
	NSArray *ranges = [ORMValueConstraintParser rangesFromString:@"{'M', 'F'}" reason:&reason];
	XCTAssertEqual([ranges count], (NSUInteger)2);
	XCTAssertEqualObjects(ranges[0][@"min"], @"M");
	XCTAssertEqualObjects(ranges[0][@"max"], @"M");
	ranges = [ORMValueConstraintParser rangesFromString:@"{1..10, 20, 'it''s'}" reason:&reason];
	XCTAssertEqualObjects(ranges[0][@"min"], @"1");
	XCTAssertEqualObjects(ranges[0][@"max"], @"10");
	XCTAssertEqualObjects(ranges[0][@"minInclusion"], @"NotSet");
	XCTAssertEqualObjects(ranges[2][@"min"], @"it's");
	ranges = [ORMValueConstraintParser rangesFromString:@"(0..100]" reason:&reason];
	XCTAssertEqualObjects(ranges[0][@"minInclusion"], @"Open");
	XCTAssertEqualObjects(ranges[0][@"maxInclusion"], @"Closed");
	ranges = [ORMValueConstraintParser rangesFromString:@"{18..}" reason:&reason];
	XCTAssertEqualObjects(ranges[0][@"max"], @"");
	XCTAssertNil([ORMValueConstraintParser rangesFromString:@"{'open}" reason:&reason]);
	XCTAssertNil([ORMValueConstraintParser rangesFromString:@"{1,,2}" reason:&reason]);
}

- (void)testFactEditorSentences
{
	ORMEditor *editor = [self newEditor];
	NSString *diagram = [[editor.model.diagrams firstObject] identifier];
	NSString *reason = nil;
	NSString *born = [editor addFactTypeFromSentence:@"Person(.id) was born in Country(.code)" onDiagram:diagram
	                                               at:ORMAutomaticPlacement reason:&reason];
	XCTAssertNotNil(born, @"%@", reason);
	XCTAssertEqualObjects([[editor.model objectTypeNamed:@"Person"] displayName], @"Person(.id)");
	XCTAssertEqualObjects([[[editor.model elementWithId:born] primaryReading] expandedText], @"Person was born in Country");
	/* Known names need no marks; Name() is a value type. */
	NSString *named = [editor addFactTypeFromSentence:@"Person has Name()" onDiagram:diagram at:ORMAutomaticPlacement
	                                           reason:&reason];
	XCTAssertNotNil(named, @"%@", reason);
	XCTAssertEqual([[editor.model objectTypeNamed:@"Name"] kind], ORMValueType);
	/* Several words in brackets, a unit, a second reading. */
	NSString *weighs = [editor addFactTypeFromSentence:@"[Order Line] weighs Mass(kg:) / Mass is weight of [Order Line]"
	                                         onDiagram:diagram at:ORMAutomaticPlacement reason:&reason];
	XCTAssertNotNil(weighs, @"%@", reason);
	XCTAssertEqualObjects([[editor.model objectTypeNamed:@"Mass"] displayName], @"Mass(kg:)");
	ORMFactType *fact = [editor.model elementWithId:weighs];
	XCTAssertEqual([fact.readingOrders count], (NSUInteger)2);
	XCTAssertEqualObjects([[[fact.readingOrders lastObject] readings].firstObject expandedText],
	                      @"Mass is weight of Order Line");
	/* A ring and a unary. */
	NSString *ring = [editor addFactTypeFromSentence:@"Person is parent of Person" onDiagram:diagram
	                                              at:ORMAutomaticPlacement reason:&reason];
	XCTAssertEqual([[editor.model elementWithId:ring] arity], (NSUInteger)2);
	NSString *smokes = [editor addFactTypeFromSentence:@"Person smokes." onDiagram:diagram at:ORMAutomaticPlacement
	                                            reason:&reason];
	XCTAssertTrue([[editor.model elementWithId:smokes] isUnary]);
	XCTAssertNil([editor addFactTypeFromSentence:@"is lonely" onDiagram:diagram at:ORMAutomaticPlacement
	                                      reason:&reason]);
	XCTAssertNotNil([[editor.model.diagrams firstObject] shapeForSubject:weighs]);
}

@end
