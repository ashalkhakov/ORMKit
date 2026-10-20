/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <CoreData/CoreData.h>

/* Subtypes a rule derives: the rule as NORMA keeps it, a query that runs
 * it, no entity of their own in Core Data, and queries through them. */
@interface ORMSubtypeDerivationTests : ORMTestCase
@end

@implementation ORMSubtypeDerivationTests

- (ORMEditor *)costs
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Amount is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Record(.id) cost Amount\n"
	                 @"Each Record cost at most one Amount.\n"
	                 @"Each Cost is by definition a Record that cost some Amount.\n"
	                 @"Cost was charged Amount\n"
	                 @"Each Cost was charged at most one Amount.\n"
	                 @"Each Event is a Record.\n"
	                 @"Each FillUp is an Event.\n"
	                 @"Each FillUp is a Cost.\n"
	                 @"Each ServiceKind is by definition a Record that is not costly.\n"
	                 @"\n"
	                 @"Query CostRule:\n"
	                 @"Derivation of Cost:\n"
	                 @"✓Record\n"
	                 @"  + cost Amount\n"
	                 @"\n"
	                 @"Query Expensive:\n"
	                 @"✓Record\n"
	                 @"  + is Cost\n"
	                 @"    + was charged Amount > 100\n"
	                 @"\n"
	                 @"Query Charged:\n"
	                 @"✓Cost\n"
	                 @"  + was charged ✓Amount\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	return editor;
}

- (ORMQuery *)query:(NSString *)name in:(ORMModel *)model
{
	for (ORMQuery *query in [ORMQuery queriesInModel:model]) {
		if ([query.name isEqualToString:name]) {
			return query;
		}
	}
	return nil;
}

/* As NORMA keeps a subtype's rule: after its played roles, its words in
 * the path's informal rule; read back the same, and undone in one step. */
- (void)testTheRuleIsKeptAsNormaKeepsIt
{
	ORMEditor *editor = [self costs];
	ORMObjectType *cost = [editor.model objectTypeNamed:@"Cost"];
	XCTAssertEqualObjects([cost derivationRule].informalText, @"a Record that cost some Amount");
	NSString *saved = [[NSString alloc] initWithData:[editor dataForSaving] encoding:NSUTF8StringEncoding];
	NSRange type = [saved rangeOfString:@"Name=\"Cost\""];
	NSString *element = [saved substringFromIndex:type.location];
	element = [element substringToIndex:[element rangeOfString:@"</orm:EntityType>"].location];
	XCTAssertTrue([element rangeOfString:@"</orm:PlayedRoles>"].location < [element rangeOfString:@"<orm:SubtypeDerivationRule>"].location,
	              @"%@", element);
	XCTAssertTrue([element rangeOfString:@"<orm:Body>a Record that cost some Amount</orm:Body>"].location != NSNotFound);
	/* Stored and partly derived, as NORMA says them. */
	XCTAssertTrue([editor.objectTypeEditor setDerivationPartial:NO stored:YES ofSubtype:cost.identifier reason:NULL]);
	saved = [[NSString alloc] initWithData:[editor dataForSaving] encoding:NSUTF8StringEncoding];
	XCTAssertTrue([saved rangeOfString:@"DerivationStorage=\"Stored\""].location != NSNotFound);
	[self.undoManager undo];
	XCTAssertFalse([[editor.model objectTypeNamed:@"Cost"] derivationRule].isStored);
	/* Taken away. */
	XCTAssertTrue([editor.objectTypeEditor setDerivationNote:@"" ofSubtype:cost.identifier reason:NULL]);
	XCTAssertNil([[editor.model objectTypeNamed:@"Cost"] derivationRule]);
	NSString *reason = nil;
	XCTAssertFalse([editor.objectTypeEditor setDerivationNote:@"anything" ofSubtype:[[editor.model objectTypeNamed:@"Record"] identifier]
	                                                   reason:&reason]);
	XCTAssertTrue([reason length] > 0);
}

/* The query that runs it: its outline names the subtype, it says the
 * rule, and the subtype keeps its own words. */
- (void)testTheRuleIsAQuery
{
	ORMEditor *editor = [self costs];
	ORMQuery *rule = [self query:@"CostRule" in:editor.model];
	XCTAssertEqualObjects(rule.derivedSubtype, [editor.model objectTypeNamed:@"Cost"]);
	XCTAssertEqualObjects([ORMQuery derivationOfSubtype:rule.derivedSubtype inModel:editor.model].identifier, rule.identifier);
	XCTAssertEqualObjects([rule outlineText], @"Derivation of Cost:\n✓Record\n  + cost Amount\n");
	NSArray *said = [[[[ORMVerbalizer alloc] initWithModel:editor.model] sentencesForQuery:rule] valueForKey:@"text"];
	XCTAssertTrue([said containsObject:@"Each Cost is by definition a Record that cost some Amount."], @"%@", said);
	XCTAssertEqualObjects([rule.derivedSubtype derivationRule].informalText, @"a Record that cost some Amount");
	NSString *reason = nil;
	XCTAssertFalse([[[ORMQueryEditor alloc] initWithEditor:editor] setDerivedSubtype:[[editor.model objectTypeNamed:@"Amount"] identifier]
	                                                                         ofQuery:rule.identifier reason:&reason]);
	XCTAssertTrue([reason length] > 0);
}

/* A step to the subtype is its rule, and what is said of the subtype is
 * said of the supertype, the same object; a query of it reads the
 * supertype. A subtype whose rule is words alone cannot be gone through. */
- (void)testQueriesGoThroughTheRule
{
	ORMEditor *editor = [self costs];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:editor.model mapping:nil];
	ORMQueryPlan *expensive = [planner planForQuery:[self query:@"Expensive" in:editor.model]];
	XCTAssertEqualObjects(expensive.notes, @[]);
	XCTAssertEqualObjects([expensive text], @"read Record\nwhere wasChargedAmount > 100 and amount is set\nlist self (id)");
	ORMQueryPlan *charged = [planner planForQuery:[self query:@"Charged" in:editor.model]];
	XCTAssertEqualObjects([charged text],
	                      @"read Record\nwhere wasChargedAmount is set and amount is set\nlist self (id), wasChargedAmount");
	NSString *outline = @"✓Record\n  + is ServiceKind\n";
	NSString *reason = nil;
	NSString *made = [[[ORMOutlineReader alloc] initWithEditor:editor] addQueryNamed:@"Kinds" outline:outline reason:&reason];
	XCTAssertNotNil(made, @"%@", reason);
	ORMQueryPlan *kinds = [planner planForQuery:[ORMQuery queryWithId:made inModel:editor.model]];
	XCTAssertEqualObjects(kinds.notes, @[ @"ServiceKind is derived by its rule's words alone, which queries cannot run." ]);
}

/* No entity of its own: its properties are its supertype's, and a subtype
 * of it and of another inherits from the other. */
- (void)testCoreDataHasNoEntityForIt
{
	ORMEditor *editor = [self costs];
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map];
	XCTAssertNil([self momcRejects:mapped]);
	XCTAssertNil([mapped entityNamed:@"Cost"]);
	XCTAssertTrue([[[[mapped entityNamed:@"Record"] attributes] valueForKey:@"name"] containsObject:@"wasChargedAmount"]);
	XCTAssertEqualObjects([mapped entityNamed:@"FillUp"].parentName, @"Event");
}

/* Run against a sample population: the records with a cost over 100
 * charged. */
- (void)testItRunsAgainstAPopulation
{
	ORMEditor *editor = [self costs];
	ORMModel *model = editor.model;
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	NSString *reason = nil;
	for (NSArray *each in @[ @[ @"Record cost Amount", @"1", @"50" ], @[ @"Record cost Amount", @"2", @"70" ],
	                         @[ @"Record cost Amount", @"3", @"" ] ]) {
		if ([each[2] length] == 0) {
			XCTAssertNotNil([editor.populationEditor addInstanceOf:[[model objectTypeNamed:@"Record"] identifier] named:each[1]
			                                                reason:&reason], @"%@", reason);
			continue;
		}
		ORMFactType *fact = [facts objectForKey:each[0]];
		NSArray *roles = [fact visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:fact.identifier
		                                              named:@{ [roles[0] identifier]: each[1], [roles[1] identifier]: each[2] }
		                                             reason:&reason]), @"%@", reason);
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"CostRule" in:model]];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMQueryResult *result = [[[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]]
		executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	NSMutableArray *ids = [NSMutableArray array];
	for (NSArray *row in result.rows) {
		[ids addObject:[[row firstObject] description]];
	}
	XCTAssertEqualObjects([ids sortedArrayUsingSelector:@selector(compare:)], (@[ @"1", @"2" ]));
}

/* From a subtype of it ("Each FillUp is a Cost"), "is Cost" is its rule
 * too; with not, the rule's one step is negated: a fill-up with no cost is
 * no Cost. Where the query says more of it, not cannot be carried. */
- (void)testAStepFromASubtypeOfItIsItsRule
{
	ORMEditor *editor = [self costs];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:editor.model mapping:nil];
	NSArray *cases = @[ @[ @"✓FillUp\n  + is Cost\n", @"read FillUp\nwhere amount is set\nlist self (id)" ],
	                    @[ @"It is impossible that:\n✓FillUp\n  + not is Cost\n",
	                       @"read FillUp\nwhere not (amount is set)\nlist self (id)" ],
	                    @[ @"✓Record\n  + not is Cost\n", @"read Record\nwhere not (amount is set)\nlist self (id)" ] ];
	NSUInteger n = 0;
	for (NSArray *each in cases) {
		NSString *reason = nil;
		NSString *made = [[[ORMOutlineReader alloc] initWithEditor:editor]
			addQueryNamed:[NSString stringWithFormat:@"Q%lu", (unsigned long)++n] outline:each[0] reason:&reason];
		XCTAssertNotNil(made, @"%@", reason);
		ORMQueryPlan *plan = [planner planForQuery:[ORMQuery queryWithId:made inModel:editor.model]];
		XCTAssertEqualObjects(plan.notes, @[], @"%@", each[0]);
		XCTAssertEqualObjects([plan text], each[1]);
	}
	NSString *reason = nil;
	NSString *made = [[[ORMOutlineReader alloc] initWithEditor:editor]
		addQueryNamed:@"More" outline:@"✓FillUp\n  + not is Cost\n    + was charged Amount\n" reason:&reason];
	XCTAssertNotNil(made, @"%@", reason);
	ORMQueryPlan *more = [planner planForQuery:[ORMQuery queryWithId:made inModel:editor.model]];
	XCTAssertEqualObjects(more.notes, @[ @"\"is Cost\" is gone through with not, maybe or a count, and the query says "
	                                     @"more of it there." ]);
}

/* An asserted subtype of it is one by its rule, which Core Data cannot
 * say (its properties are the supertype's, optional there): a rule of the
 * subtype's entity, checked. */
- (void)testAnAssertedSubtypeOfItMeetsTheRule
{
	ORMEditor *editor = [self costs];
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:editor.model mapping:nil name:@"Costs"];
	NSData *data = [[[generator files] objectForKey:@"Costs.ormplans"] dataUsingEncoding:NSUTF8StringEncoding];
	id list = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
	NSError *error = nil;
	ORMTables *tables = [ORMTables tablesWithPropertyList:list error:&error];
	XCTAssertNotNil(tables, @"%@", error);
	NSArray *rules = [tables.rules objectForKey:@"FillUp"];
	XCTAssertEqualObjects([rules valueForKey:@"text"], @[ @"Each FillUp is a Cost." ]);
	XCTAssertEqualObjects([rules valueForKey:@"constraint"], @[ @"FillUpIsACost" ]);

	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map];
	NSPersistentStoreCoordinator *coordinator =
		[[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[mapped managedObjectModel]];
	XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil
	                                                  error:&error],
	                @"%@", error);
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
	context.persistentStoreCoordinator = coordinator;
	ORMValidator *validator = [[ORMValidator alloc] initWithTables:tables];
	NSManagedObject *fillUp = [NSEntityDescription insertNewObjectForEntityForName:@"FillUp" inManagedObjectContext:context];
	[fillUp setValue:@1 forKey:@"id"];
	NSManagedObject *record = [NSEntityDescription insertNewObjectForEntityForName:@"Record" inManagedObjectContext:context];
	[record setValue:@2 forKey:@"id"];
	XCTAssertTrue([validator validate:record error:&error], @"a record need not cost: %@", error);
	XCTAssertFalse([validator validate:fillUp error:&error]);
	XCTAssertTrue([[error localizedDescription] containsString:@"Each FillUp is a Cost."], @"%@", error);
	[fillUp setValue:[NSDecimalNumber decimalNumberWithString:@"40"] forKey:@"amount"];
	XCTAssertTrue([validator validate:fillUp error:&error], @"%@", error);
}

@end
