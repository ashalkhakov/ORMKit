/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* What Core Data cannot enforce, as code (ORMCoreDataValidation.h). */
@interface ORMCoreDataValidationTests : ORMTestCase
@end

@implementation ORMCoreDataValidationTests

- (NSString *)diagramOf:(ORMEditor *)editor
{
	return [[editor.model.diagrams firstObject] identifier];
}

- (NSArray<NSString *> *)rolesOf:(NSString *)fact in:(ORMEditor *)editor
{
	return [[[editor.model elementWithId:fact] roles] valueForKey:@"identifier"];
}

- (NSString *)fact:(NSArray *)players reading:(NSString *)reading in:(ORMEditor *)editor
{
	NSString *fact = [editor addFactTypeWithPlayers:players reading:reading onDiagram:[self diagramOf:editor]
	                                             at:ORMAutomaticPlacement reason:NULL];
	XCTAssertNotNil(fact, @"%@", reading);
	return fact;
}

/* Staff: a person employed or retired, not both; known by a nickname or a
 * legal name; parents without cycles; dying no earlier than being born, and
 * only when born; of an age a child's or a pensioner's; and, as an
 * obligation, the employed with a legal name. */
- (ORMEditor *)staff
{
	ORMEditor *editor = [self newEditor];
	NSString *diagram = [self diagramOf:editor];
	NSString *person = [editor addEntityTypeNamed:@"Person" referenceMode:@"id" kind:ORMReferenceModePopular
	                                    onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	NSString *nickname = [editor addValueTypeNamed:@"Nickname" dataType:@"VariableLengthTextDataType"
	                                     onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	NSString *legalName = [editor addValueTypeNamed:@"LegalName" dataType:@"VariableLengthTextDataType"
	                                      onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	NSString *date = [editor addValueTypeNamed:@"Date" dataType:@"DateAndTimeTemporalDataType" onDiagram:diagram
	                                        at:ORMAutomaticPlacement reason:NULL];
	NSString *age = [editor addValueTypeNamed:@"Age" dataType:@"SignedIntegerNumericDataType" onDiagram:diagram
	                                       at:ORMAutomaticPlacement reason:NULL];

	NSString *employed = [[self rolesOf:[self fact:@[ person ] reading:@"{0} is employed" in:editor] in:editor]
		firstObject];
	NSString *retired = [[self rolesOf:[self fact:@[ person ] reading:@"{0} is retired" in:editor] in:editor]
		firstObject];
	XCTAssertNotNil(([editor addSetComparisonConstraint:ORMExclusionConstraint sequences:@[ @[ employed ], @[ retired ] ]
	                                            reason:NULL]));

	NSArray *hasNickname = [self rolesOf:[self fact:@[ person, nickname ] reading:@"{0} has {1}" in:editor] in:editor];
	NSArray *hasLegalName = [self rolesOf:[self fact:@[ person, legalName ] reading:@"{0} has {1}" in:editor]
	                                   in:editor];
	[editor setUnique:YES role:[hasNickname firstObject] reason:NULL];
	[editor setUnique:YES role:[hasLegalName firstObject] reason:NULL];
	XCTAssertNotNil(([editor addMandatoryConstraintOverRoles:@[ [hasNickname firstObject], [hasLegalName firstObject] ]
	                                                 reason:NULL]));

	NSArray *parent = [self rolesOf:[self fact:@[ person, person ] reading:@"{0} is parent of {1}" in:editor] in:editor];
	[editor addUniquenessConstraintOverRoles:parent reason:NULL];
	XCTAssertNotNil(([editor addRingConstraint:ORMRingAcyclic overRoles:parent reason:NULL]));

	NSArray *born = [self rolesOf:[self fact:@[ person, date ] reading:@"{0} was born on {1}" in:editor] in:editor];
	NSArray *died = [self rolesOf:[self fact:@[ person, date ] reading:@"{0} died on {1}" in:editor] in:editor];
	[editor setUnique:YES role:[born firstObject] reason:NULL];
	[editor setUnique:YES role:[died firstObject] reason:NULL];
	XCTAssertNotNil(([editor addValueComparisonConstraint:@"GreaterThanOrEqual"
	                                           overRoles:@[ [died lastObject], [born lastObject] ]
	                                              reason:NULL]));
	XCTAssertNotNil(([editor addSetComparisonConstraint:ORMSubsetConstraint
	                                         sequences:@[ @[ [died firstObject] ], @[ [born firstObject] ] ]
	                                            reason:NULL]));

	NSArray *hasAge = [self rolesOf:[self fact:@[ person, age ] reading:@"{0} has {1}" in:editor] in:editor];
	[editor setUnique:YES role:[hasAge firstObject] reason:NULL];
	XCTAssertTrue(([editor setValueConstraint:@"{0..17, 65..120}" of:age reason:NULL]));

	NSString *obligation = [editor addSetComparisonConstraint:ORMSubsetConstraint
	                                                sequences:@[ @[ employed ], @[ [hasLegalName firstObject] ] ]
	                                                   reason:NULL];
	XCTAssertTrue(([editor setModality:ORMDeontic of:obligation reason:NULL]));
	return editor;
}

- (ORMValidationGenerator *)generatorFor:(ORMEditor *)editor
{
	return [[ORMValidationGenerator alloc] initWithModel:editor.model mapping:nil name:@"Staff"];
}

- (void)testEachKindOfConstraintIsChecked
{
	ORMValidationGenerator *generator = [self generatorFor:[self staff]];
	XCTAssertEqual([generator.notes count], 0u, @"%@", generator.notes);
	XCTAssertEqual(generator.ruleCount, 7u);
	NSDictionary *files = [generator files];
	XCTAssertEqualObjects([[files allKeys] sortedArrayUsingSelector:@selector(compare:)],
	                      (@[ @"StaffValidation.h", @"StaffValidation.m" ]));
	NSString *code = [files objectForKey:@"StaffValidation.m"];
	NSArray *expected = @[
		/* Exclusion of two unaries. */
		@"(StaffTrue(self, @\"isEmployed\") + StaffTrue(self, @\"isRetired\")) <= 1",
		/* Inclusive-or. */
		@"StaffPresent(self, @\"nickname\") || StaffPresent(self, @\"legalName\")",
		/* Ring. */
		@"StaffAcyclic(self, @\"persons\")",
		/* Value comparison. */
		@"StaffCompare(self, @\"diedOnDate\", @\"date\", @\">=\")",
		/* Subset. */
		@"(!StaffPresent(self, @\"diedOnDate\") || StaffPresent(self, @\"date\"))",
		/* Value constraint of two ranges. */
		@"StaffWithin(self, @\"age\", ^BOOL(double v) { return (v >= 0.0 && v <= 17.0) || (v >= 65.0 && v <= 120.0); })",
	];
	for (NSString *condition in expected) {
		XCTAssertTrue([code rangeOfString:condition].location != NSNotFound, @"%@ in\n%@", condition, code);
	}
	/* The obligation is told of, not enforced. */
	NSRange deontic = [code rangeOfString:@"\tif (deontic) {"];
	XCTAssertTrue(deontic.location != NSNotFound);
	XCTAssertTrue([[code substringFromIndex:deontic.location]
	                  rangeOfString:@"(!StaffTrue(self, @\"isEmployed\") || StaffPresent(self, @\"legalName\"))"]
	                  .location
	              != NSNotFound);

	NSString *header = [files objectForKey:@"StaffValidation.h"];
	XCTAssertTrue([header rangeOfString:@"#import \"Person+CoreDataClass.h\""].location != NSNotFound, @"%@", header);
	XCTAssertTrue([header rangeOfString:@"@interface Person (ORMValidation)"].location != NSNotFound);
	XCTAssertTrue([header rangeOfString:@"- (BOOL)orm_validateConstraints:(NSError **)error;"].location != NSNotFound);
}

/* A subentity with rules of its own calls its parent's, and does not
 * declare the entry points again. */
- (void)testSubentitiesCallTheirParents
{
	ORMEditor *editor = [self staff];
	NSString *diagram = [self diagramOf:editor];
	NSString *person = [[editor.model objectTypeNamed:@"Person"] identifier];
	NSString *employee = [editor addEntityTypeNamed:@"Employee" referenceMode:nil kind:ORMReferenceModeNone
	                                      onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	XCTAssertNotNil(([editor addSubtype:employee of:person reason:NULL]));
	NSString *full = [[self rolesOf:[self fact:@[ employee ] reading:@"{0} is full time" in:editor] in:editor]
		firstObject];
	NSString *part = [[self rolesOf:[self fact:@[ employee ] reading:@"{0} is part time" in:editor] in:editor]
		firstObject];
	XCTAssertNotNil(([editor addExclusiveOrConstraintOverRoles:@[ full, part ] reason:NULL]));

	NSString *code = [[[self generatorFor:editor] files] objectForKey:@"StaffValidation.m"];
	NSRange at = [code rangeOfString:@"@implementation Employee (ORMValidation)"];
	XCTAssertTrue(at.location != NSNotFound, @"%@", code);
	NSString *employeeCode = [code substringFromIndex:at.location];
	XCTAssertTrue([employeeCode rangeOfString:@"[super orm_collectViolations:violations deontic:deontic];"].location
	              != NSNotFound);
	XCTAssertTrue([employeeCode rangeOfString:@"- (BOOL)orm_validateConstraints:"].location == NSNotFound);
	/* Exclusive-or: exactly one. */
	XCTAssertTrue([employeeCode rangeOfString:@"(StaffTrue(self, @\"isFullTime\") + StaffTrue(self, @\"isPartTime\")) == 1"]
	                  .location
	              != NSNotFound,
	              @"%@", employeeCode);
	/* Person's come first, so Employee's super call has a declaration. */
	XCTAssertLessThan([code rangeOfString:@"@implementation Person (ORMValidation)"].location, at.location);
}

/* Every example: code for what Core Data cannot enforce, and a note for
 * each constraint it cannot check. */
- (void)testFixturesGenerate
{
	NSMutableArray *files = [NSMutableArray arrayWithObject:@"StockMate.orm"];
	[files addObjectsFromArray:[self activeFactsFixtures]];
	NSUInteger rules = 0;
	for (NSString *file in files) {
		@autoreleasepool {
			ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:file] reason:NULL];
			ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:model mapping:nil
			                                                                             name:@"Model"];
			NSString *code = [[generator files] objectForKey:@"ModelValidation.m"];
			XCTAssertNotNil(code, @"%@", file);
			rules += generator.ruleCount;
		}
	}
	XCTAssertGreaterThan(rules, 100u);
}

- (void)testWritesOnlyWhatChanged
{
	ORMValidationGenerator *generator = [self generatorFor:[self staff]];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	NSError *error = nil;
	XCTAssertTrue([generator writeToDirectory:directory error:&error], @"%@", error);
	NSString *path = [directory stringByAppendingPathComponent:@"StaffValidation.m"];
	NSDate *written = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileModificationDate];
	XCTAssertNotNil(written);
	[[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate: [NSDate dateWithTimeIntervalSinceReferenceDate:0] } ofItemAtPath:path
	                                        error:NULL];
	XCTAssertTrue([generator writeToDirectory:directory error:&error], @"%@", error);
	XCTAssertEqualObjects([[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileModificationDate],
	                      [NSDate dateWithTimeIntervalSinceReferenceDate:0]);
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

@end
