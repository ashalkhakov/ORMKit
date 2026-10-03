/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* FORML, sentence by sentence. */
@interface ORMVerbalizerTests : ORMTestCase
@end

@implementation ORMVerbalizerTests

- (NSArray<NSString *> *)sentencesOf:(NSString *)elementId in:(ORMModel *)model
{
	NSMutableArray *texts = [NSMutableArray array];
	for (ORMVerbalSentence *sentence in [[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:elementId]) {
		[texts addObject:[sentence text]];
	}
	return texts;
}

- (ORMModel *)stockMate
{
	return [ORMModel modelOfDocument:[self fixtureDocument:@"StockMate.orm"] reason:NULL];
}

- (ORMFactType *)fact:(NSString *)reading in:(ORMModel *)model
{
	for (ORMFactType *fact in model.factTypes) {
		if ([[[fact primaryReading] expandedText] isEqualToString:reading]) {
			return fact;
		}
	}
	XCTFail(@"no fact type reads '%@'", reading);
	return nil;
}

- (void)testAnEntityType
{
	ORMModel *model = [self stockMate];
	NSArray *sentences = [self sentencesOf:[[model objectTypeNamed:@"Product"] identifier] in:model];
	XCTAssertEqualObjects(sentences[0], @"Product is an entity type.");
	XCTAssertTrue([sentences containsObject:@"Reference Scheme: Product has Product_Id."]);
	XCTAssertTrue([sentences containsObject:@"Reference Mode: .Id."]);
	XCTAssertTrue([sentences containsObject:@"Portable data type: Numeric: Auto Counter."]);
}

- (void)testANameIsNotCapitalized
{
	ORMModel *model = [self stockMate];
	NSArray *sentences = [self sentencesOf:[[model objectTypeNamed:@"kgValue"] identifier] in:model];
	XCTAssertEqualObjects(sentences[0], @"kgValue is a value type.");
}

- (void)testABinarysConstraints
{
	ORMModel *model = [self stockMate];
	NSArray *sentences = [self sentencesOf:[[self fact:@"Product has Name" in:model] identifier] in:model];
	XCTAssertEqualObjects(sentences, (@[ @"Product has Name.", @"Each Product has exactly one Name.",
	                                     @"It is possible that more than one Product has some Name." ]));
	sentences = [self sentencesOf:[[self fact:@"Product is identified by SKU" in:model] identifier] in:model];
	XCTAssertTrue([sentences containsObject:@"For each SKU, at most one Product is identified by that SKU."]);
}

- (void)testAnExternalUniquenessConstraintWithHyphenBinding
{
	ORMModel *model = [self stockMate];
	ORMConstraint *identifier = [[model objectTypeNamed:@"Street"] preferredIdentifier];
	NSArray *sentences = [self sentencesOf:identifier.identifier in:model];
	XCTAssertEqualObjects(sentences[0], @"For each StreetLine1, StreetLine2 and StreetLine3, at most one Street "
	                                    @"includes that first StreetLine1 and includes that second StreetLine2 and "
	                                    @"includes that third StreetLine3.");
	XCTAssertEqualObjects(sentences[1], @"This association with StreetLine provides the preferred identification "
	                                    @"scheme for Street.");
}

- (void)testARingConstraint
{
	ORMModel *model = [self stockMate];
	ORMFactType *fact = [self fact:@"ItemCategory is child of ItemCategory" in:model];
	NSArray *sentences = [self sentencesOf:fact.identifier in:model];
	XCTAssertTrue([sentences containsObject:@"No ItemCategory may cycle back to itself via one or more traversals "
	                                        @"through ItemCategory is child of ItemCategory."], @"%@", sentences);
}

- (void)testSetComparisons
{
	ORMModel *model = [self stockMate];
	NSMutableArray *all = [NSMutableArray array];
	for (ORMVerbalSentence *sentence in [[[ORMVerbalizer alloc] initWithModel:model] sentencesForModel]) {
		[all addObject:[sentence text]];
	}
	XCTAssertTrue([all containsObject:@"Some Address is in some Region if and only if that Address is in some Country."]);
	XCTAssertTrue([all containsObject:@"If some Lot has some LotNumber then that Lot is of some LotType."]);
	XCTAssertTrue([all containsObject:@"If some Street includes some third StreetLine then that Street includes some "
	                                  @"second StreetLine."]);
}

- (void)testAModelBuiltHere
{
	ORMEditor *editor = [self newEditor];
	NSString *diagram = [[editor.model.diagrams firstObject] identifier];
	NSString *person = [editor addEntityTypeNamed:@"Person" referenceMode:@"id" kind:ORMReferenceModePopular
	                                    onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	NSString *smokes = [editor addFactTypeWithPlayers:@[ person ] reading:@"{0} smokes" onDiagram:diagram
	                                               at:ORMAutomaticPlacement reason:NULL];
	NSString *drinks = [editor addFactTypeWithPlayers:@[ person ] reading:@"{0} drinks" onDiagram:diagram
	                                               at:ORMAutomaticPlacement reason:NULL];
	NSString *exclusion = [editor addSetComparisonConstraint:ORMExclusionConstraint
	                                               sequences:@[ @[ [[[editor.model elementWithId:smokes] roles][0] identifier] ],
	                                                            @[ [[[editor.model elementWithId:drinks] roles][0] identifier] ] ]
	                                                  reason:NULL];
	XCTAssertEqualObjects([self sentencesOf:exclusion in:editor.model], (@[ @"No Person smokes and drinks." ]));
	NSString *mandatory = [editor addMandatoryConstraintOverRoles:@[ [[[editor.model elementWithId:smokes] roles][0] identifier],
	                                                                 [[[editor.model elementWithId:drinks] roles][0] identifier] ]
	                                                       reason:NULL];
	XCTAssertEqualObjects([self sentencesOf:mandatory in:editor.model], (@[ @"Each Person smokes or drinks." ]));
	XCTAssertTrue([editor setModality:ORMDeontic of:mandatory reason:NULL]);
	XCTAssertEqualObjects([self sentencesOf:mandatory in:editor.model],
	                      (@[ @"It is obligatory that each Person smokes or drinks." ]));
}

- (void)testHTMLColoursAsNormaDoes
{
	ORMModel *model = [self stockMate];
	NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:model]
		sentencesForElement:[[model objectTypeNamed:@"Product"] identifier]];
	NSString *html = [ORMVerbalizer HTMLOfSentences:sentences title:@"Product"];
	XCTAssertTrue([html rangeOfString:@"<span class=\"objectType\">Product</span>"].location != NSNotFound);
	XCTAssertTrue([html rangeOfString:@"class=\"keyword\""].location != NSNotFound);
}

@end
