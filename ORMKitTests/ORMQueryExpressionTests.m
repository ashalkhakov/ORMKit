/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <ODataService/ODataService.h>

/* Value nodes (docs/EXPRESSIONS.md): what a query computes from the nodes
 * it reaches, as the file keeps it and the outline says it; said in words,
 * planned and run. */
@interface ORMQueryExpressionTests : ORMTestCase
@end

@implementation ORMQueryExpressionTests

- (ORMEditor *)trips
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Kilometres is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Trip(.id) started at Kilometres\n"
	                 @"Each Trip started at at most one Kilometres.\n"
	                 @"Trip ended at Kilometres\n"
	                 @"Each Trip ended at at most one Kilometres.\n"
	                 @"Note is a value type.\n"
	                 @"Trip has Note\n"
	                 @"Each Trip has at most one Note.\n"
	                 @"\n"
	                 @"Query Long:\n"
	                 @"✓Trip\n"
	                 @"  + started at Kilometres1\n"
	                 @"  + ended at Kilometres2\n"
	                 @"  ✓Length = Kilometres2 - Kilometres1 > 100\n";
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

- (ORMQueryNode *)node:(NSString *)designation of:(ORMQuery *)query
{
	for (ORMQueryNode *node in [query nodes]) {
		if ([[node designation] isEqualToString:designation]) {
			return node;
		}
	}
	return nil;
}

/* Read and written both ways: by node ids as the file keeps it, by
 * designations as the outline says it, brackets only where they are
 * needed. */
- (void)testExpressionsAreReadAndWritten
{
	NSDictionary *ids = @{ @"A": @"_a", @"B": @"_b", @"C": @"_c" };
	NSDictionary *names = @{ @"_a": @"A", @"_b": @"B", @"_c": @"C" };
	NSString *reason = nil;
	ORMQueryExpression *e = [ORMQueryExpression expressionWithText:@"(A - B) * 2 + -C / 1.5" designations:ids reason:&reason];
	XCTAssertNotNil(e, @"%@", reason);
	XCTAssertEqualObjects([e canonicalText], @"add(multiply(subtract(#_a, #_b), 2), divide(negate(#_c), 1.5))");
	XCTAssertEqualObjects([e textWithDesignations:names], @"(A - B) * 2 + -C / 1.5");
	XCTAssertEqualObjects([ORMQueryExpression expressionWithCanonicalText:[e canonicalText] reason:NULL], e);
	XCTAssertEqualObjects([e nodeIds], (@[ @"_a", @"_b", @"_c" ]));
	XCTAssertEqualObjects([[e expressionRenaming:@"_b" to:@"_d"] canonicalText],
	                      @"add(multiply(subtract(#_a, #_d), 2), divide(negate(#_c), 1.5))");
	/* Not associative: the right side bracketed. */
	e = [ORMQueryExpression expressionWithText:@"A - (B - C)" designations:ids reason:NULL];
	XCTAssertEqualObjects([e textWithDesignations:names], @"A - (B - C)");
	e = [ORMQueryExpression expressionWithText:@"A − B × C ÷ 2" designations:ids reason:NULL];
	XCTAssertEqualObjects([e textWithDesignations:names], @"A - B * C / 2");
	e = [ORMQueryExpression expressionWithText:@"round(abs(A), 2) + coalesce(B, 'none''s')" designations:ids reason:NULL];
	XCTAssertEqualObjects([e canonicalText], @"add(round(abs(#_a), 2), coalesce(#_b, 'none''s'))");
	XCTAssertEqualObjects([e textWithDesignations:names], @"round(abs(A), 2) + coalesce(B, 'none''s')");
	/* What is none. */
	for (NSString *wrong in @[ @"A -", @"(A", @"D + 1", @"sqrt(A)", @"round(A)", @"A B", @"'open" ]) {
		reason = nil;
		XCTAssertNil([ORMQueryExpression expressionWithText:wrong designations:ids reason:&reason], @"%@", wrong);
		XCTAssertTrue([reason length] > 0, @"%@", wrong);
	}
}

/* In the outline, a line under the node it is computed for; in the file,
 * an ormq:Value with its expression by node ids; read back the same. */
- (void)testAValueNodeInTheOutlineAndTheFile
{
	ORMEditor *editor = [self trips];
	ORMQuery *query = [self query:@"Long" in:editor.model];
	NSString *outline = @"✓Trip\n  + started at Kilometres1\n  + ended at Kilometres2\n  ✓Length = Kilometres2 - Kilometres1 > 100\n";
	XCTAssertEqualObjects([query outlineText], outline);
	ORMQueryNode *length = [self node:@"Length" of:query];
	XCTAssertTrue(length.isValue);
	XCTAssertEqualObjects(length.objectType, [editor.model objectTypeNamed:@"Kilometres"]);
	XCTAssertEqual(length.valueOf, query.root);
	XCTAssertEqualObjects([query.projectedNodes valueForKey:@"designation"], (@[ @"Trip", @"Length" ]));
	NSString *saved = [[NSString alloc] initWithData:[editor dataForSaving] encoding:NSUTF8StringEncoding];
	NSString *expression = [NSString stringWithFormat:@"Expression=\"subtract(#%@, #%@)\"",
	                                                  [self node:@"Kilometres2" of:query].identifier,
	                                                  [self node:@"Kilometres1" of:query].identifier];
	XCTAssertTrue([saved rangeOfString:@"<ormq:Value "].location != NSNotFound, @"%@", saved);
	XCTAssertTrue([saved rangeOfString:expression].location != NSNotFound, @"%@", saved);
	XCTAssertTrue([saved rangeOfString:@"Name=\"Length\""].location != NSNotFound);
	/* Read again from what was saved. */
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:[editor dataForSaving] options:NSXMLNodePreserveAll error:NULL];
	ORMEditor *again = [self newEditorWithDocument:document];
	XCTAssertEqualObjects([[self query:@"Long" in:again.model] outlineText], outline);
	/* A value under a step's node, written under it; read back the same. */
	NSString *halves = @"✓Trip\n  + started at Kilometres\n    Half = Kilometres / 2 ↓\n";
	NSString *reason = nil;
	ORMOutlineReader *reader = [[ORMOutlineReader alloc] initWithEditor:editor];
	NSString *made = [reader addQueryNamed:@"Halves" outline:halves reason:&reason];
	XCTAssertNotNil(made, @"%@", reason);
	XCTAssertEqualObjects([[ORMQuery queryWithId:made inModel:editor.model] outlineText], halves);
	/* One value used by another, and compared with a node. */
	NSString *more = @"✓Trip\n  + started at Kilometres1\n  + ended at Kilometres2\n"
	                 @"  Length = Kilometres2 - Kilometres1\n  ✓Double: Kilometres = Length * 2 < Kilometres2\n";
	made = [reader addQueryNamed:@"More" outline:more reason:&reason];
	XCTAssertNotNil(made, @"%@", reason);
	XCTAssertEqualObjects([[ORMQuery queryWithId:made inModel:editor.model] outlineText],
	                      [more stringByReplacingOccurrencesOfString:@"Double: Kilometres" withString:@"Double"]);
}

/* What the editor refuses, and undoes. */
- (void)testTheEditorRefusesWhatIsNoValue
{
	ORMEditor *editor = [self trips];
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	ORMQuery *query = [self query:@"Long" in:editor.model];
	NSString *root = query.root.identifier;
	NSString *noteType = [[editor.model objectTypeNamed:@"Note"] identifier];
	NSString *reason = nil;
	XCTAssertNil([queries addValueNamed:@"Length" to:root expression:@"Kilometres1 + 1" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"already"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([queries addValueNamed:@"round" to:root expression:@"Kilometres1" type:nil reason:&reason]);
	XCTAssertNil([queries addValueNamed:@"Odd" to:root expression:@"Kilometres3 + 1" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"Kilometres3"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([queries addValueNamed:@"Odd" to:root expression:@"1 + 2" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"value type"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([queries addValueNamed:@"Odd" to:root expression:@"Kilometres1 + 1" type:noteType reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"not one"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([queries addValueNamed:@"Odd" to:root expression:@"Kilometres1" type:[[editor.model objectTypeNamed:@"Trip"] identifier]
	                             reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"no value type"].location != NSNotFound, @"%@", reason);
	/* Arithmetic of what is not a number. */
	NSString *made = [[[ORMOutlineReader alloc] initWithEditor:editor]
		addQueryNamed:@"Notes" outline:@"✓Trip\n  + has Note\n  + started at Kilometres\n" reason:&reason];
	ORMQuery *notes = [ORMQuery queryWithId:made inModel:editor.model];
	XCTAssertNil([queries addValueNamed:@"Odd" to:notes.root.identifier expression:@"Note * 2" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"Note is not a number"].location != NSNotFound, @"%@", reason);
	XCTAssertNotNil([queries addValueNamed:@"Either" to:notes.root.identifier expression:@"coalesce(Note, 'none')" type:nil
	                                reason:&reason], @"%@", reason);
	/* Said again; taken away, not while another uses it; undone. */
	NSString *length = [self node:@"Length" of:query].identifier;
	NSString *twice = [queries addValueNamed:@"Twice" to:root expression:@"Length * 2" type:nil reason:&reason];
	XCTAssertNotNil(twice, @"%@", reason);
	XCTAssertFalse([queries removeValue:length reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"used"].location != NSNotFound, @"%@", reason);
	XCTAssertTrue([queries setExpression:@"Kilometres2 + Kilometres1" ofValue:length reason:&reason], @"%@", reason);
	XCTAssertFalse([queries setExpression:@"Twice + 1" ofValue:length reason:&reason]);
	XCTAssertTrue([[[self query:@"Long" in:editor.model] outlineText]
	                  rangeOfString:@"✓Length = Kilometres2 + Kilometres1 > 100"].location != NSNotFound);
	XCTAssertTrue([queries removeValue:twice reason:&reason], @"%@", reason);
	XCTAssertTrue([queries removeValue:length reason:&reason], @"%@", reason);
	XCTAssertNil([self node:@"Length" of:[self query:@"Long" in:editor.model]]);
	[self.undoManager undo];
	XCTAssertNotNil([self node:@"Length" of:[self query:@"Long" in:editor.model]]);
	/* A step taken away takes the values using what it reached. */
	ORMQueryStep *ended = [[self node:@"Kilometres2" of:[self query:@"Long" in:editor.model]] step];
	[queries removeStep:ended.identifier];
	XCTAssertEqualObjects([[self query:@"Long" in:editor.model] outlineText], @"✓Trip\n  + started at Kilometres1\n");
}

/* Said as Halpin says calculations: the value by its name, the arithmetic
 * in words. */
- (void)testItIsSaidInWords
{
	ORMEditor *editor = [self trips];
	ORMQuery *query = [self query:@"Long" in:editor.model];
	NSArray *said = [[[[ORMVerbalizer alloc] initWithModel:editor.model] sentencesForQuery:query] valueForKey:@"text"];
	NSString *text = [said firstObject];
	XCTAssertTrue([text hasPrefix:@"List each Trip and Length where "], @"%@", said);
	XCTAssertTrue([text rangeOfString:@"Length is Kilometres2 minus Kilometres1"].location != NSNotFound, @"%@", said);
	XCTAssertTrue([text rangeOfString:@"Length is greater than 100"].location != NSNotFound, @"%@", said);
}

/* Planned: the expression of the places its nodes are at, listed and
 * compared; one of a node out of scope is noted. The plan archives. */
- (void)testItIsPlanned
{
	ORMEditor *editor = [self trips];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:editor.model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"Long" in:editor.model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	XCTAssertEqualObjects([plan text], @"read Trip\n"
	                                   @"where kilometres is set and endedAtKilometres is set "
	                                   @"and subtract(endedAtKilometres, kilometres) > 100\n"
	                                   @"list self (id), subtract(endedAtKilometres, kilometres)");
	XCTAssertEqualObjects([[self archived:plan] text], [plan text]);
	ORMPlanColumn *length = [plan.columns lastObject];
	XCTAssertEqualObjects(length.title, @"Length");
	XCTAssertEqualObjects(length.value.function, @"subtract");
}

/* Run against a sample population, from the store and from the service:
 * trip 1 went 150 km, trip 2 50; trip 3 has not ended. */
- (void)testItRunsAgainstAPopulation
{
	ORMEditor *editor = [self trips];
	ORMModel *model = editor.model;
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	NSString *reason = nil;
	for (NSArray *each in @[ @[ @"Trip started at Kilometres", @"1", @"100" ], @[ @"Trip ended at Kilometres", @"1", @"250" ],
	                         @[ @"Trip started at Kilometres", @"2", @"300" ], @[ @"Trip ended at Kilometres", @"2", @"350" ],
	                         @[ @"Trip started at Kilometres", @"3", @"400" ] ]) {
		ORMFactType *fact = [facts objectForKey:each[0]];
		NSArray *roles = [fact visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:fact.identifier
		                                              named:@{ [roles[0] identifier]: each[1], [roles[1] identifier]: each[2] }
		                                             reason:&reason]), @"%@", reason);
	}
	NSString *all = [[[ORMOutlineReader alloc] initWithEditor:editor]
		addQueryNamed:@"All" outline:@"✓Trip\n  + started at Kilometres1\n  + maybe ended at Kilometres2\n"
		              @"  ✓Length = Kilometres2 - Kilometres1\n"
		       reason:&reason];
	XCTAssertNotNil(all, @"%@", reason);
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"Long" in:model]];
	ORMQueryResult *result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects(result.rows, (@[ @[ @1, @150 ] ]));
	/* Nothing is a value where an operand is none. */
	ORMQueryPlan *each = [planner planForQuery:[ORMQuery queryWithId:all inModel:model]];
	XCTAssertEqualObjects(each.notes, @[]);
	result = [interpreter executePlan:each inContext:context error:&error];
	NSMutableArray *rows = [NSMutableArray array];
	for (NSArray *row in result.rows) {
		[rows addObject:[row componentsJoinedByString:@" "]];
	}
	XCTAssertEqualObjects([rows sortedArrayUsingSelector:@selector(compare:)], (@[ @"1 150", @"2 50", @"3 <null>" ]));
	/* From the service: the arithmetic in its filter. */
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqualObjects(odata.notes, @[]);
	XCTAssertTrue([[odata queryText] rangeOfString:@"EndedAtKilometres sub Kilometres gt 100"].location != NSNotFound,
	              @"%@", [odata queryText]);
	XCTAssertEqualObjects([self rowsOf:odata over:context], (@[ @[ @1, @150 ] ]));
	ORMQueryOData *everyTrip = [ORMQueryOData requestForPlan:each coreData:planner.coreData error:&error];
	rows = [NSMutableArray array];
	for (NSArray *row in [self rowsOf:everyTrip over:context]) {
		[rows addObject:[row componentsJoinedByString:@" "]];
	}
	XCTAssertEqualObjects([rows sortedArrayUsingSelector:@selector(compare:)], (@[ @"1 150", @"2 50", @"3 <null>" ]));
}

/* The rows ODataKit's service over the store answers the request with. */
- (NSArray *)rowsOf:(ORMQueryOData *)odata over:(NSManagedObjectContext *)context
{
	NSURL *root = [NSURL URLWithString:@"http://example.test/odata/"];
	ODataService *service = [[ODataService alloc] initWithPersistentStoreCoordinator:context.persistentStoreCoordinator
	                                                                     serviceRoot:root];
	ORMQueryODataCursor *cursor = [odata cursorWithTransport:service serviceRoot:root];
	NSMutableArray *rows = [NSMutableArray array];
	for (NSUInteger guard = 0; guard < 10 && ![cursor atEnd]; guard++) {
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		[cursor nextPage:10 completion:^(ORMQueryResult *result, NSError *failed) {
			XCTAssertNotNil(result, @"%@", failed);
			[rows addObjectsFromArray:result.rows ?: @[]];
			dispatch_semaphore_signal(done);
		}];
		XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC))), 0);
	}
	return rows;
}

/* Each function's value, none where an operand is none or it divides by
 * zero; whole numbers whole, decimals decimal. */
- (void)testFunctionsAreComputed
{
	XCTAssertEqualObjects(ORMPlanApply(@"subtract", @[ @250, @100 ]), @150);
	XCTAssertEqualObjects(ORMPlanApply(@"divide", @[ @3, @2 ]), @1.5);
	XCTAssertNil(ORMPlanApply(@"divide", @[ @3, @0 ]));
	XCTAssertNil(ORMPlanApply(@"add", @[ @3, [NSNull null] ]));
	XCTAssertNil(ORMPlanApply(@"add", @[ @3, @"x" ]));
	NSDecimalNumber *price = [NSDecimalNumber decimalNumberWithString:@"1.25"];
	XCTAssertEqualObjects(ORMPlanApply(@"multiply", @[ price, @4 ]), [NSDecimalNumber decimalNumberWithString:@"5"]);
	XCTAssertTrue([ORMPlanApply(@"multiply", @[ price, @4 ]) isKindOfClass:[NSDecimalNumber class]]);
	XCTAssertEqualObjects(ORMPlanApply(@"round", @[ [NSDecimalNumber decimalNumberWithString:@"2.345"], @2 ]),
	                      [NSDecimalNumber decimalNumberWithString:@"2.35"]);
	XCTAssertEqualObjects(ORMPlanApply(@"round", @[ @2.5, @0 ]), @3);
	XCTAssertEqualObjects(ORMPlanApply(@"negate", @[ @2 ]), @-2);
	XCTAssertEqualObjects(ORMPlanApply(@"abs", @[ @-2.5 ]), @2.5);
	XCTAssertEqualObjects(ORMPlanApply(@"max", @[ @2, @3.5 ]), @3.5);
	XCTAssertEqualObjects(ORMPlanApply(@"min", @[ @"b", @"a" ]), @"a");
	XCTAssertEqualObjects(ORMPlanApply(@"coalesce", @[ [NSNull null], @"none" ]), @"none");
}

@end
