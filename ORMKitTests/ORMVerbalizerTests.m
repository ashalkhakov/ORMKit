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
	/* Numbered variables are named bare the second time, as Halpin does. */
	XCTAssertEqualObjects(sentences[0], @"For each StreetLine1, StreetLine2 and StreetLine3, at most one Street "
	                                    @"includes first StreetLine1 and includes second StreetLine2 and "
	                                    @"includes third StreetLine3.");
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
	/* Join paths are followed, not guessed at. */
	XCTAssertTrue([all containsObject:@"For each Address and Region, that Address is in that Region if and only if "
	                                  @"that Address is in some Country and that Region is part of that Country."], @"%@", all);
	/* The superset names every instance it compares, though the subset
	 * says "Lot is of LotType" too: the sentence reads back as written. */
	XCTAssertTrue([all containsObject:@"If some Lot has some LotNumber and is of some LotType then that Lot is of that "
	                                  @"LotType that tracks lot numbers."], @"%@", all);
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

- (ORMConstraint *)constraint:(NSString *)name in:(ORMModel *)model
{
	for (ORMConstraint *constraint in model.constraints) {
		if ([constraint.name isEqualToString:name]) {
			return constraint;
		}
	}
	XCTFail(@"no constraint %@", name);
	return nil;
}

- (ORMModel *)activeFacts:(NSString *)name
{
	return [ORMModel modelOfDocument:[self fixtureDocument:[NSString stringWithFormat:@"ActiveFacts/%@.orm", name]]
	                          reason:NULL];
}

- (NSArray<NSString *> *)textsOf:(NSArray<ORMVerbalSentence *> *)sentences
{
	return [sentences valueForKey:@"text"];
}

/* Each statement carries what it rules out: the questionnaire's
 * counterexample. */
- (void)testConstraintsCarryTheirNegations
{
	ORMModel *model = [self stockMate];
	ORMFactType *fact = [self fact:@"Product has Name" in:model];
	ORMVerbalSentence *exactlyOne = nil;
	for (ORMVerbalSentence *sentence in [[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:fact.identifier]) {
		if ([[sentence text] isEqualToString:@"Each Product has exactly one Name."]) {
			exactlyOne = sentence;
		}
	}
	XCTAssertEqual(exactlyOne.kind, ORMVerbalStatement);
	XCTAssertEqualObjects([self textsOf:exactlyOne.negations],
	                      (@[ @"It is impossible that the same Product has more than one Name.",
	                          @"It is impossible that some Product has no Name." ]));
	/* Each negation names the constraint it is the counterexample of. */
	ORMRole *product = [[fact visibleRoles] firstObject];
	ORMConstraint *uniqueness = [model elementWithId:[exactlyOne.negations[0] sourceId]];
	ORMConstraint *mandatory = [model elementWithId:[exactlyOne.negations[1] sourceId]];
	XCTAssertEqual(uniqueness.kind, ORMUniquenessConstraint);
	XCTAssertEqual(mandatory.kind, ORMMandatoryConstraint);
	XCTAssertTrue([[mandatory allRoles] containsObject:product]);

	ORMConstraint *unique = [self constraint:@"ExternalUniquenessConstraint3" in:model];
	ORMVerbalSentence *statement = [[[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:unique.identifier]
		firstObject];
	XCTAssertEqualObjects([statement text], @"For each Country and RegionISOCode, at most one Region is part of that "
	                                        @"Country and has that RegionISOCode.");
	XCTAssertEqualObjects([self textsOf:statement.negations],
	                      (@[ @"It is impossible that more than one Region is part of the same Country and has the "
	                          @"same RegionISOCode." ]));
	/* Said too when asked. */
	ORMVerbalizer *verbalizer = [[ORMVerbalizer alloc] initWithModel:model];
	verbalizer.verbalizesNegations = YES;
	NSArray *sentences = [verbalizer sentencesForElement:unique.identifier];
	XCTAssertEqual([(ORMVerbalSentence *)sentences[1] kind], ORMVerbalNegation);
}

/* A possibility names the role a uniqueness constraint would go on. */
- (void)testPossibilitiesNameWhatWouldRuleThemOut
{
	ORMModel *model = [self stockMate];
	ORMFactType *fact = [self fact:@"Product has Name" in:model];
	for (ORMVerbalSentence *sentence in [[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:fact.identifier]) {
		if (sentence.kind == ORMVerbalPossibility) {
			XCTAssertEqualObjects(sentence.sourceId, [[[fact visibleRoles] lastObject] identifier]);
		}
	}
}

/* A join path through an objectification's link fact types, either way
 * NORMA records the step. */
- (void)testJoinPathsThroughLinkFactTypes
{
	ORMModel *model = [self activeFacts:@"WaiterTips"];
	ORMConstraint *equality = [self constraint:@"EqualityConstraint1" in:model];
	XCTAssertEqualObjects([self sentencesOf:equality.identifier in:model],
	                      (@[ @"For each Waiter, Meal and Amount, that Waiter served that Meal that is involved in some "
	                          @"Service that earned a tip of that Amount if and only if that Waiter for serving that Meal "
	                          @"reported a tip of that Amount." ]));
}

/* Halpin's mark, and the rule as relative clauses: Heath's CQL says it as
 * "Session (where Cinema shows Film on Session Time) has Seat where that
 * Cinema contains Row that contains that Seat". */
- (void)testADerivationRule
{
	ORMModel *model = [self activeFacts:@"CinemaTickets"];
	ORMFactType *fact = nil;
	for (ORMFactType *each in model.factTypes) {
		if ([each.name isEqualToString:@"SessionHasSeat"]) {
			fact = each;
		}
	}
	XCTAssertTrue([[self sentencesOf:fact.identifier in:model]
		containsObject:@"* For each Session and Seat, that Session has that Seat if and only if that Session is at "
		               @"some Cinema that contains some Row that contains that Seat."]);
}

- (void)testSamplePopulations
{
	ORMModel *model = [self activeFacts:@"Orienteering"];
	ORMObjectType *code = [model objectTypeNamed:@"Club Code"];
	XCTAssertTrue([[self sentencesOf:code.identifier in:model] containsObject:@"Examples: 'DROC', 'YV', 'BK'."]);
	ORMFactType *named = [self fact:@"Club Name is name of Club" in:model];
	NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:named.identifier];
	/* GNUstep's predicate parser takes no %ld. */
	NSPredicate *examples = [NSPredicate predicateWithBlock:^BOOL(ORMVerbalSentence *sentence, NSDictionary *bindings) {
		(void)bindings;
		return sentence.kind == ORMVerbalExample;
	}];
	XCTAssertTrue([[self textsOf:[sentences filteredArrayUsingPredicate:examples]]
		containsObject:@"Club Name 'Dandenong Ranges Orienteering Club' is name of Club 'DROC'."]);
}

/* Every model says something of everything, without failing. */
- (void)testEveryNormaModelVerbalizes
{
	for (NSString *name in [self allNormaFiles]) {
		ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:name] reason:NULL];
		ORMVerbalizer *verbalizer = [[ORMVerbalizer alloc] initWithModel:model];
		verbalizer.verbalizesNegations = YES;
		NSArray *sentences = [verbalizer sentencesForModel];
		XCTAssertTrue([sentences count] > [[model visibleObjectTypes] count], @"%@", name);
		for (ORMVerbalSentence *sentence in sentences) {
			XCTAssertTrue([[sentence text] length] > 1, @"%@", name);
			XCTAssertEqual([[sentence text] rangeOfString:@"  "].location, (NSUInteger)NSNotFound, @"%@: %@", name,
			               [sentence text]);
		}
	}
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
