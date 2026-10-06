/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <CoreData/CoreData.h>

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
	NSString *fact = [editor.factTypeEditor addFactTypeWithPlayers:players reading:reading onDiagram:[self diagramOf:editor]
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
	NSString *person = [editor.objectTypeEditor addEntityTypeNamed:@"Person" referenceMode:@"id" kind:ORMReferenceModePopular
	                                    onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	NSString *nickname = [editor.objectTypeEditor addValueTypeNamed:@"Nickname" dataType:@"VariableLengthTextDataType"
	                                     onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	NSString *legalName = [editor.objectTypeEditor addValueTypeNamed:@"LegalName" dataType:@"VariableLengthTextDataType"
	                                      onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	NSString *date = [editor.objectTypeEditor addValueTypeNamed:@"Date" dataType:@"DateAndTimeTemporalDataType" onDiagram:diagram
	                                        at:ORMAutomaticPlacement reason:NULL];
	NSString *age = [editor.objectTypeEditor addValueTypeNamed:@"Age" dataType:@"SignedIntegerNumericDataType" onDiagram:diagram
	                                       at:ORMAutomaticPlacement reason:NULL];

	NSString *employed = [[self rolesOf:[self fact:@[ person ] reading:@"{0} is employed" in:editor] in:editor]
		firstObject];
	NSString *retired = [[self rolesOf:[self fact:@[ person ] reading:@"{0} is retired" in:editor] in:editor]
		firstObject];
	XCTAssertNotNil(([editor.constraintEditor addSetComparisonConstraint:ORMExclusionConstraint sequences:@[ @[ employed ], @[ retired ] ]
	                                            reason:NULL]));

	NSArray *hasNickname = [self rolesOf:[self fact:@[ person, nickname ] reading:@"{0} has {1}" in:editor] in:editor];
	NSArray *hasLegalName = [self rolesOf:[self fact:@[ person, legalName ] reading:@"{0} has {1}" in:editor]
	                                   in:editor];
	[editor.constraintEditor setUnique:YES role:[hasNickname firstObject] reason:NULL];
	[editor.constraintEditor setUnique:YES role:[hasLegalName firstObject] reason:NULL];
	XCTAssertNotNil(([editor.constraintEditor addMandatoryConstraintOverRoles:@[ [hasNickname firstObject], [hasLegalName firstObject] ]
	                                                 reason:NULL]));

	NSArray *parent = [self rolesOf:[self fact:@[ person, person ] reading:@"{0} is parent of {1}" in:editor] in:editor];
	[editor.constraintEditor addUniquenessConstraintOverRoles:parent reason:NULL];
	XCTAssertNotNil(([editor.constraintEditor addRingConstraint:ORMRingAcyclic overRoles:parent reason:NULL]));

	NSArray *born = [self rolesOf:[self fact:@[ person, date ] reading:@"{0} was born on {1}" in:editor] in:editor];
	NSArray *died = [self rolesOf:[self fact:@[ person, date ] reading:@"{0} died on {1}" in:editor] in:editor];
	[editor.constraintEditor setUnique:YES role:[born firstObject] reason:NULL];
	[editor.constraintEditor setUnique:YES role:[died firstObject] reason:NULL];
	XCTAssertNotNil(([editor.constraintEditor addValueComparisonConstraint:@"GreaterThanOrEqual"
	                                           overRoles:@[ [died lastObject], [born lastObject] ]
	                                              reason:NULL]));
	XCTAssertNotNil(([editor.constraintEditor addSetComparisonConstraint:ORMSubsetConstraint
	                                         sequences:@[ @[ [died firstObject] ], @[ [born firstObject] ] ]
	                                            reason:NULL]));

	NSArray *hasAge = [self rolesOf:[self fact:@[ person, age ] reading:@"{0} has {1}" in:editor] in:editor];
	[editor.constraintEditor setUnique:YES role:[hasAge firstObject] reason:NULL];
	XCTAssertTrue(([editor.objectTypeEditor setValueConstraint:@"{0..17, 65..120}" of:age reason:NULL]));

	NSString *obligation = [editor.constraintEditor addSetComparisonConstraint:ORMSubsetConstraint
	                                                sequences:@[ @[ employed ], @[ [hasLegalName firstObject] ] ]
	                                                   reason:NULL];
	XCTAssertTrue(([editor.constraintEditor setModality:ORMDeontic of:obligation reason:NULL]));
	return editor;
}

- (ORMValidationGenerator *)generatorFor:(ORMEditor *)editor
{
	return [[ORMValidationGenerator alloc] initWithModel:editor.model mapping:nil name:@"Staff"];
}

/* A context over a store of the model the generator's mapping makes, in
 * memory. */
- (NSManagedObjectContext *)contextFor:(ORMEditor *)editor
{
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map];
	NSPersistentStoreCoordinator *coordinator =
		[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[mapped managedObjectModel]];
	NSError *error = nil;
	XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil
	                                                  error:&error],
	                @"%@", error);
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
	context.persistentStoreCoordinator = coordinator;
	return context;
}

/* The tables the generator writes, read back as the app reads them. */
- (ORMTables *)tablesOf:(ORMValidationGenerator *)generator
{
	NSData *data = [[[generator files] objectForKey:@"Staff.ormplans"] dataUsingEncoding:NSUTF8StringEncoding];
	id list = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
	NSError *error = nil;
	ORMTables *tables = [ORMTables tablesWithPropertyList:list error:&error];
	XCTAssertNotNil(tables, @"%@", error);
	return tables;
}

/* The constraints the alethic violations of the object are of. */
- (NSArray<NSString *> *)broken:(NSManagedObject *)object by:(ORMValidator *)validator
{
	NSMutableArray *names = [NSMutableArray array];
	for (NSError *violation in [validator violationsOf:object deontic:NO]) {
		[names addObject:[violation.userInfo objectForKey:NSValidationKeyErrorKey] ?: @"?"];
	}
	return names;
}

/* Each kind of constraint Core Data cannot enforce is a rule of the
 * tables, which the driver checks: a person who meets them all, and one
 * who breaks each. */
- (void)testEachKindOfConstraintIsChecked
{
	ORMEditor *editor = [self staff];
	ORMValidationGenerator *generator = [self generatorFor:editor];
	XCTAssertEqual([generator.notes count], 0u, @"%@", generator.notes);
	XCTAssertEqual(generator.ruleCount, 7u);
	NSDictionary *files = [generator files];
	XCTAssertEqualObjects([[files allKeys] sortedArrayUsingSelector:@selector(compare:)],
	                      (@[ @"Staff.ormplans", @"StaffValidation.h", @"StaffValidation.m" ]));
	ORMTables *tables = [self tablesOf:generator];
	NSArray *kinds = [[[tables.rules objectForKey:@"Person"] valueForKeyPath:@"check.kind"]
		sortedArrayUsingSelector:@selector(compare:)];
	XCTAssertEqualObjects(kinds, (@[ @"any", @"any", @"any", @"compare", @"count", @"ring", @"within" ]));
	NSString *header = [files objectForKey:@"StaffValidation.h"];
	XCTAssertTrue([header containsString:@"#import \"Person+CoreDataClass.h\""], @"%@", header);
	XCTAssertTrue([header containsString:@"@interface Person (ORMValidation)"]);
	XCTAssertTrue([header containsString:@"- (BOOL)orm_validateConstraints:(NSError **)error;"]);
	XCTAssertTrue([[files objectForKey:@"StaffValidation.m"] containsString:@"[ORMValidator validatorNamed:@\"Staff\""]);

	ORMValidator *validator = [[ORMValidator alloc] initWithTables:tables];
	NSManagedObjectContext *context = [self contextFor:editor];
	NSManagedObject *ann = [NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context];
	[ann setValuesForKeysWithDictionary:@{ @"nickname": @"Ann", @"age": @12, @"date": [NSDate dateWithTimeIntervalSince1970:0] }];
	NSError *error = nil;
	XCTAssertTrue([validator validate:ann error:&error], @"%@", error);
	/* Employed and retired: exclusion. */
	[ann setValuesForKeysWithDictionary:@{ @"isEmployed": @YES, @"isRetired": @YES }];
	XCTAssertEqualObjects([self broken:ann by:validator], @[ @"isEmployed" ]);
	[ann setValue:@NO forKey:@"isRetired"];
	/* Employed without a legal name: the obligation, told of, not enforced. */
	XCTAssertTrue([validator validate:ann error:NULL]);
	XCTAssertEqual([[validator violationsOf:ann deontic:YES] count], 1u);
	/* No name at all: inclusive-or. */
	[ann setValue:nil forKey:@"nickname"];
	XCTAssertEqualObjects([self broken:ann by:validator], @[ @"nickname" ]);
	[ann setValue:@"Ann" forKey:@"nickname"];
	/* Of an age neither a child's nor a pensioner's. */
	[ann setValue:@30 forKey:@"age"];
	XCTAssertEqualObjects([self broken:ann by:validator], @[ @"age" ]);
	[ann setValue:@70 forKey:@"age"];
	/* Dying before being born: value comparison. */
	[ann setValue:[NSDate dateWithTimeIntervalSince1970:-100] forKey:@"diedOnDate"];
	XCTAssertEqualObjects([self broken:ann by:validator], @[ @"diedOnDate" ]);
	/* Dying unborn: subset. */
	[ann setValue:nil forKey:@"date"];
	XCTAssertEqualObjects([self broken:ann by:validator], @[ @"diedOnDate" ]);
	[ann setValue:nil forKey:@"diedOnDate"];
	XCTAssertTrue([validator validate:ann error:NULL]);
	/* Her own grandparent: acyclic. */
	NSManagedObject *bob = [NSEntityDescription insertNewObjectForEntityForName:@"Person" inManagedObjectContext:context];
	[bob setValue:@"Bob" forKey:@"nickname"];
	[[ann mutableSetValueForKey:@"persons"] addObject:bob];
	XCTAssertTrue([validator validate:ann error:NULL]);
	[[bob mutableSetValueForKey:@"persons"] addObject:ann];
	XCTAssertEqualObjects([self broken:ann by:validator], @[ @"persons" ]);
}

/* A subentity's objects meet their ancestors' rules and their own; the
 * category is on the topmost class with rules only. */
- (void)testSubentitiesMeetTheirParentsRules
{
	ORMEditor *editor = [self staff];
	NSString *diagram = [self diagramOf:editor];
	NSString *person = [[editor.model objectTypeNamed:@"Person"] identifier];
	NSString *employee = [editor.objectTypeEditor addEntityTypeNamed:@"Employee" referenceMode:nil kind:ORMReferenceModeNone
	                                      onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	XCTAssertNotNil(([editor.objectTypeEditor addSubtype:employee of:person reason:NULL]));
	NSString *full = [[self rolesOf:[self fact:@[ employee ] reading:@"{0} is full time" in:editor] in:editor]
		firstObject];
	NSString *part = [[self rolesOf:[self fact:@[ employee ] reading:@"{0} is part time" in:editor] in:editor]
		firstObject];
	XCTAssertNotNil(([editor.constraintEditor addExclusiveOrConstraintOverRoles:@[ full, part ] reason:NULL]));

	ORMValidationGenerator *generator = [self generatorFor:editor];
	NSString *code = [[generator files] objectForKey:@"StaffValidation.m"];
	XCTAssertTrue([code containsString:@"@implementation Person (ORMValidation)"], @"%@", code);
	XCTAssertFalse([code containsString:@"@implementation Employee (ORMValidation)"], @"%@", code);
	ORMTables *tables = [self tablesOf:generator];
	ORMRuleCheck *exactlyOne = [[[tables.rules objectForKey:@"Employee"] firstObject] check];
	XCTAssertEqualObjects(exactlyOne.kind, @"count");
	XCTAssertTrue(exactlyOne.exactly);

	ORMValidator *validator = [[ORMValidator alloc] initWithTables:tables];
	NSManagedObjectContext *context = [self contextFor:editor];
	NSManagedObject *cy = [NSEntityDescription insertNewObjectForEntityForName:@"Employee" inManagedObjectContext:context];
	/* Neither named, nor full or part time: Person's rule, then Employee's. */
	XCTAssertEqualObjects([self broken:cy by:validator], (@[ @"nickname", @"isFullTime" ]));
	[cy setValuesForKeysWithDictionary:@{ @"nickname": @"Cy", @"isFullTime": @YES }];
	XCTAssertTrue([validator validate:cy error:NULL]);
	[cy setValue:@YES forKey:@"isPartTime"];
	XCTAssertEqualObjects([self broken:cy by:validator], @[ @"isFullTime" ]);
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
