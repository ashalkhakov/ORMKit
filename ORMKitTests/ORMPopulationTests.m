/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <CoreData/CoreData.h>

/* Sample populations: written as NORMA writes them, read back, and put in
 * a Core Data store of the mapping. */
@interface ORMPopulationTests : ORMTestCase
@end

@implementation ORMPopulationTests
{
	ORMEditor *_editor;
	NSString *_person, *_country, *_born;
}

- (void)setUp
{
	[super setUp];
	_editor = [self newEditor];
	NSString *diagram = [[_editor.model.diagrams firstObject] identifier];
	_person = [_editor.objectTypeEditor addEntityTypeNamed:@"Person" referenceMode:@"id" kind:ORMReferenceModePopular
	                                            onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	_country = [_editor.objectTypeEditor addEntityTypeNamed:@"Country" referenceMode:@"code"
	                                                   kind:ORMReferenceModePopular onDiagram:diagram
	                                                     at:ORMAutomaticPlacement reason:NULL];
	_born = [_editor.factTypeEditor addFactTypeWithPlayers:@[ _person, _country ] reading:@"{0} was born in {1}"
	                                             onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	NSString *personRole = [[[[_editor.model elementWithId:_born] roles] firstObject] identifier];
	XCTAssertTrue([_editor.constraintEditor setUnique:YES role:personRole reason:NULL]);
}

/* An instance of the type by its reference mode's value. */
- (NSString *)instanceOf:(NSString *)typeId value:(NSString *)text in:(ORMSamplePopulation *)population
{
	ORMObjectType *type = [_editor.model elementWithId:typeId];
	ORMRole *role = [[type.preferredIdentifier allRoles] firstObject];
	return [population instanceOf:typeId identifiedBy:@{ role.identifier: [population value:text of:role.player.identifier] }];
}

- (NSDictionary *)born:(NSString *)person in:(NSString *)country
{
	NSArray *roles = [[_editor.model elementWithId:_born] roles];
	return @{ [[roles firstObject] identifier]: person, [[roles lastObject] identifier]: country };
}

- (void)addAnnAndBob
{
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	NSString *ann = [self instanceOf:_person value:@"1" in:population];
	NSString *bob = [self instanceOf:_person value:@"2" in:population];
	NSString *au = [self instanceOf:_country value:@"AU" in:population];
	XCTAssertEqualObjects([self instanceOf:_country value:@"AU" in:population], au, @"one instance for one identity");
	[population factOf:_born players:[self born:ann in:au]];
	[population factOf:_born players:[self born:bob in:au]];
	NSString *reason = nil;
	XCTAssertTrue([_editor.populationEditor addPopulation:population reason:&reason], @"%@", reason);
}

/* As NORMA keeps them: instances under their types, role instances under
 * the roles, a fact type's instances after all else it has. */
- (void)testAPopulationIsWrittenAsNormaWritesIt
{
	[self addAnnAndBob];
	ORMObjectType *person = [_editor.model elementWithId:_person];
	XCTAssertEqualObjects([[person instances] valueForKey:@"displayText"], (@[ @"1", @"2" ]));
	XCTAssertEqualObjects([[person.referenceModeValueType instances] valueForKey:@"value"], (@[ @"1", @"2" ]));
	ORMFactType *born = [_editor.model elementWithId:_born];
	XCTAssertEqual([[born instances] count], (NSUInteger)2);
	ORMFactInstance *first = [[born instances] firstObject];
	XCTAssertEqualObjects([[first.instancesByRole objectForKey:[[born.roles lastObject] identifier]] displayText], @"'AU'");
	XCTAssertEqualObjects([[[born.element children] lastObject] localName], @"Instances");
	ORMRole *role = [born.roles firstObject];
	XCTAssertEqualObjects([[[role.element children] lastObject] localName], @"RoleInstances");
	NSXMLElement *identified = [[[person instances] firstObject] element];
	XCTAssertEqualObjects([identified localName], @"EntityTypeInstance");
	NSArray *identifying = ORMChildren(ORMChild(identified, ORMCoreNamespace, @"RoleInstances"), ORMCoreNamespace,
	                                   @"EntityTypeRoleInstance");
	XCTAssertEqual([identifying count], (NSUInteger)1);

	/* What was written reads back as it was, and normalizes to itself. */
	NSData *data = [_editor dataForSaving];
	ORMEditor *reread = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
	[reread group:@"Nothing" with:^{
	}];
	XCTAssertEqualObjects(ORMDataOfDocument(reread.document), data);
	XCTAssertEqual([[[reread.model elementWithId:_born] instances] count], (NSUInteger)2);

	/* A value the model has already is that instance. */
	ORMSamplePopulation *more = [[ORMSamplePopulation alloc] init];
	NSString *cal = [self instanceOf:_person value:@"3" in:more];
	[more factOf:_born players:[self born:cal in:[self instanceOf:_country value:@"AU" in:more]]];
	XCTAssertTrue([_editor.populationEditor addPopulation:more reason:NULL]);
	ORMObjectType *countryCode = [[_editor.model elementWithId:_country] referenceModeValueType];
	XCTAssertEqual([[countryCode instances] count], (NSUInteger)1);

	[self.undoManager undo];
	[self.undoManager undo];
	XCTAssertEqual([[[_editor.model elementWithId:_born] instances] count], (NSUInteger)0);
	XCTAssertEqual([[[_editor.model elementWithId:_person] instances] count], (NSUInteger)0);
}

- (void)testAnInstanceOfTheWrongTypeIsRefused
{
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	NSString *ann = [self instanceOf:_person value:@"1" in:population];
	[population factOf:_born players:[self born:ann in:ann]];
	NSString *reason = nil;
	XCTAssertFalse([_editor.populationEditor addPopulation:population reason:&reason]);
	XCTAssertTrue([reason length] > 0);
	XCTAssertEqual([[[_editor.model elementWithId:_person] instances] count], (NSUInteger)0, @"nothing is added");
}

/* Each broken constraint said, of the instances that break it. */
- (void)testTheCheckerSaysWhatIsBroken
{
	[self addAnnAndBob];
	ORMPopulationChecker *checker = [[ORMPopulationChecker alloc] initWithModel:_editor.model];
	XCTAssertEqualObjects([[checker violations] valueForKey:@"text"], @[]);

	NSArray *roles = [[_editor.model elementWithId:_born] roles];
	XCTAssertTrue([_editor.constraintEditor setMandatory:YES role:[[roles firstObject] identifier] reason:NULL]);
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	NSString *ann = [self instanceOf:_person value:@"1" in:population];
	[population factOf:_born players:[self born:ann in:[self instanceOf:_country value:@"NZ" in:population]]];
	[self instanceOf:_person value:@"3" in:population];
	XCTAssertTrue([_editor.populationEditor addPopulation:population reason:NULL]);
	checker = [[ORMPopulationChecker alloc] initWithModel:_editor.model];
	NSArray *texts = [[checker violations] valueForKey:@"text"];
	XCTAssertTrue([texts containsObject:@"Person 1 occurs more than once in \"Person was born in Country\"."], @"%@", texts);
	XCTAssertTrue([texts containsObject:@"Person 3 plays no role in \"Person was born in Country\"."], @"%@", texts);
	XCTAssertEqual([texts count], (NSUInteger)2, @"%@", texts);
}

- (void)testRemovingThePopulationLeavesTheModel
{
	NSData *empty = [_editor dataForSaving];
	[self addAnnAndBob];
	[_editor.populationEditor removePopulation];
	XCTAssertEqualObjects([_editor dataForSaving], empty);
}

/* Each person an object with its id, born in the one country. */
- (void)testAPopulationGoesInTheStore
{
	[self addAnnAndBob];
	ORMCDModel *coreData = [[[ORMCoreDataMapper alloc] initWithModel:_editor.model mapping:nil] map];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:_editor.model coreData:coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	XCTAssertEqualObjects(store.notes, @[]);
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
	request.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES] ];
	NSArray *people = [context executeFetchRequest:request error:&error];
	XCTAssertEqualObjects([people valueForKey:@"id"], (@[ @1, @2 ]));
	NSString *bornIn = nil;
	for (NSRelationshipDescription *relationship in [[[store.managedObjectModel entitiesByName] objectForKey:@"Person"]
	                                                     relationshipsByName].allValues) {
		if ([relationship.destinationEntity.name isEqualToString:@"Country"]) {
			bornIn = relationship.name;
		}
	}
	XCTAssertEqualObjects([people valueForKeyPath:[bornIn stringByAppendingString:@".code"]], (@[ @"AU", @"AU" ]));
}

/* The samples', and the models NORMA wrote: made up, a population each. */
- (NSArray<NSString *> *)generatedModels
{
	NSString *samples = [[[[self fixturePath:@"x"] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
		stringByDeletingLastPathComponent];
	NSMutableArray *paths = [NSMutableArray array];
	for (NSString *name in @[ @"Company.orm", @"University.orm", @"UMLandORM.orm" ]) {
		[paths addObject:[[samples stringByAppendingPathComponent:@"Samples"] stringByAppendingPathComponent:name]];
	}
	for (NSString *name in [@[ @"StockMate.orm", @"WorkMate.orm" ] arrayByAddingObjectsFromArray:[self activeFactsFixtures]]) {
		[paths addObject:[self fixturePath:name]];
	}
	return paths;
}

/* Every model gets a population that is written, read back and put in the
 * store of its default mapping. All but five break nothing (the samples,
 * StockMate, WorkMate, 24 of the 29 ActiveFacts models); for those five the
 * generator says why. */
- (void)testAGeneratedPopulationMeetsTheConstraints
{
	NSMutableSet *broken = [NSMutableSet set];
	for (NSString *path in [self generatedModels]) {
		/* Each model's let go of before the next: under the sanitizer, 34
		 * of them at once are more than the test's memory. */
		@autoreleasepool {
		NSString *name = [path lastPathComponent];
		NSData *data = [NSData dataWithContentsOfFile:path];
		ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
		[editor.populationEditor removePopulation];
		ORMPopulationGenerator *generator = [[ORMPopulationGenerator alloc] initWithModel:editor.model];
		NSString *reason = nil;
		XCTAssertTrue([editor.populationEditor addPopulation:[generator population] reason:&reason], @"%@: %@", name,
		              reason);
		ORMPopulationChecker *checker = [[ORMPopulationChecker alloc] initWithModel:editor.model];
		NSArray *violations = [[checker violations] valueForKey:@"text"];
		if ([violations count] > 0) {
			[broken addObject:name];
			XCTAssertTrue([generator.notes count] > 0, @"%@ says why it is not whole", name);
		}
		ORMCDModel *coreData = [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map];
		ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:editor.model coreData:coreData];
		NSError *error = nil;
		XCTAssertNotNil([store newContextWithError:&error], @"%@: %@", name, error);
		XCTAssertEqualObjects(store.notes, @[], @"%@", name);
		}
	}
	/* What the generator cannot yet make whole: docs/POPULATIONS.md. */
	XCTAssertEqualObjects(broken, ([NSSet setWithArray:@[ @"Blog.orm", @"Diplomacy.orm", @"Metamodel.orm",
	                                                      @"Monogamy.orm", @"Supervision.orm" ]]));
}

/* The samples' own populations: each query finds what its paper says, or
 * the sample's README. The first column's distinct values, sorted where the
 * query sorts nothing. */
- (void)testTheSamplesAnswerTheirQueries
{
	NSDictionary *expected = @{
		@"Company.orm": @{ @"Q1": @[ @1, @3 ], @"Q2": @[ @1, @3, @4 ], @"Q3": @[ @102 ], @"Q4": @[ @2 ],
		                   @"Q5": @[ @1, @4 ], @"Payroll": @[ @52, @7 ], @"Polyglots": @[ @1 ] },
		@"University.orm": @{ @"Q1": @[ @430, @715, @720 ], @"Q2": @[ @720 ], @"Q3": @[ @430, @503, @651, @715, @720 ] },
		@"UMLandORM.orm": @{ @"Rooms lacking a facility": @[], @"Coauthored papers": @[ @1 ] },
	};
	for (NSString *path in [self generatedModels]) {
		NSDictionary *answers = [expected objectForKey:[path lastPathComponent]];
		if (answers == nil) {
			continue;
		}
		ORMModel *model = [ORMModel modelOfDocument:ORMParseDocument([NSData dataWithContentsOfFile:path], NULL) reason:NULL];
		XCTAssertEqualObjects([[[[ORMPopulationChecker alloc] initWithModel:model] violations] valueForKey:@"text"], @[]);
		/* As the designer runs them: by the document's first mapping. */
		ORMCoreDataMapping *mapping = [[ORMCoreDataMapping mappingsOfDocument:model.document] firstObject];
		ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:mapping];
		ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
		NSError *error = nil;
		NSManagedObjectContext *context = [store newContextWithError:&error];
		XCTAssertNotNil(context, @"%@", error);
		XCTAssertEqualObjects(store.notes, @[]);
		ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:store.managedObjectModel];
		for (ORMQuery *query in [ORMQuery queriesInModel:model]) {
			ORMQueryPlan *plan = [planner planForQuery:query];
			ORMQueryResult *result = [interpreter executePlan:plan inContext:context error:&error];
			XCTAssertNotNil(result, @"%@: %@", query.name, error);
			NSMutableOrderedSet *firsts = [NSMutableOrderedSet orderedSet];
			for (NSArray *row in result.rows) {
				[firsts addObject:[row firstObject]];
			}
			NSArray *got = [plan.sorts count] > 0 ? [firsts array]
			                                      : [[firsts array] sortedArrayUsingSelector:@selector(compare:)];
			XCTAssertEqualObjects(got, [answers objectForKey:query.name], @"%@ %@", [path lastPathComponent], query.name);
			if ([[path lastPathComponent] isEqualToString:@"University.orm"] && [query.name isEqualToString:@"Q3"]) {
				/* Maybe a degree rated above 5: two academics with none have
				 * a row each, the degree empty; the rest a row a degree. */
				NSUInteger empty = 0;
				for (NSArray *row in result.rows) {
					empty += [row objectAtIndex:1] == [NSNull null] ? 1 : 0;
				}
				XCTAssertEqual([result.rows count], 7u, @"%@", result.rows);
				XCTAssertEqual(empty, 2u, @"%@", result.rows);
			}
		}
	}
}

/* The same model, the same population. */
- (void)testGeneratingIsRepeatable
{
	NSData *data = [NSData dataWithContentsOfFile:[[self generatedModels] firstObject]];
	NSMutableArray *texts = [NSMutableArray array];
	for (NSUInteger i = 0; i < 2; i++) {
		ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
		ORMPopulationGenerator *generator = [[ORMPopulationGenerator alloc] initWithModel:editor.model];
		XCTAssertTrue([editor.populationEditor addPopulation:[generator population] reason:NULL]);
		NSMutableArray *facts = [NSMutableArray array];
		for (ORMFactType *fact in editor.model.factTypes) {
			for (ORMFactInstance *instance in [fact instances]) {
				NSMutableArray *players = [NSMutableArray array];
				for (ORMRole *role in fact.roles) {
					[players addObject:[[instance.instancesByRole objectForKey:role.identifier] displayText] ?: @"-"];
				}
				[facts addObject:[NSString stringWithFormat:@"%@ %@", fact.name, [players componentsJoinedByString:@" "]]];
			}
		}
		[texts addObject:facts];
	}
	XCTAssertEqualObjects([texts firstObject], [texts lastObject]);
	XCTAssertTrue([[texts firstObject] count] > 50);
}

/* NORMA's own: the sample population an ActiveFacts model has. */
- (void)testNormasPopulationGoesInTheStore
{
	ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:@"ActiveFacts/Insurance.orm"] reason:NULL];
	ORMCDModel *coreData = [[[ORMCoreDataMapper alloc] initWithModel:model mapping:nil] map];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	/* Its facts of an alias and a state's name name no product or state:
	 * NORMA reports them incomplete, and they are left out. */
	XCTAssertEqualObjects(store.notes, (@[ @"A fact of \"State Name is of State\" lacks a role's player: it is left out.",
	                                       @"A fact of \"Alias is of Product\" lacks a role's player: it is left out." ]));
	ORMPopulationChecker *checker = [[ORMPopulationChecker alloc] initWithModel:model];
	NSArray *texts = [[checker violations] valueForKey:@"text"];
	XCTAssertTrue([texts containsObject:@"A fact of \"Alias is of Product\" lacks a role's player."], @"%@", texts);
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"CoverType"];
	request.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"code" ascending:YES] ];
	NSArray *covers = [context executeFetchRequest:request error:&error];
	XCTAssertEqualObjects([covers valueForKey:@"code"], (@[ @"TTP", @"TTPFT" ]));
	XCTAssertEqualObjects([covers valueForKey:@"coverTypeName"],
	                      (@[ @"Third Party Property", @"Third Party Property Fire and Theft" ]));
}

@end
