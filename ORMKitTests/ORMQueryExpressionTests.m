/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <ODataService/ODataService.h>
#import <ODataIncrementalStore/ODataIncrementalStore.h>

/* Value nodes (docs/EXPRESSIONS.md): what a query computes from the nodes
 * it reaches, as the file keeps it and the outline says it; said in words,
 * planned and run. */
@interface ORMQueryExpressionTests : ORMTestCase
@end

/* A service that refuses $apply, as one without Data Aggregation does; the
 * rest it answers. */
@interface ORMTestNoApplyTransport : NSObject <ODataTransport>
@property (nonatomic, strong) id<ODataTransport> service;
@property (nonatomic) NSUInteger refused;
@end

@implementation ORMTestNoApplyTransport
- (void)startExchange:(ODataExchange *)exchange
{
	if ([[[exchange.request.URL query] stringByRemovingPercentEncoding] rangeOfString:@"$apply="].location != NSNotFound) {
		self.refused++;
		exchange.URLResponse = [[NSHTTPURLResponse alloc] initWithURL:exchange.request.URL statusCode:501 HTTPVersion:@"HTTP/1.1"
		                                                 headerFields:@{ @"Content-Type": @"application/json" }];
		exchange.data = [@"{\"error\":{\"code\":\"501\",\"message\":\"No $apply here.\"}}" dataUsingEncoding:NSUTF8StringEncoding];
		[exchange finish];
		return;
	}
	[self.service startExchange:exchange];
}
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
	/* A type that is not what it would be taken to be is written. */
	NSString *typed = @"✓Trip\n  + started at Kilometres\n  + has Note\n  Count: Kilometres = count(Note) for Trip\n";
	made = [reader addQueryNamed:@"Typed" outline:typed reason:&reason];
	XCTAssertNotNil(made, @"%@", reason);
	XCTAssertEqualObjects([[ORMQuery queryWithId:made inModel:editor.model] outlineText], typed);
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
	/* The length computed by the service, listed from its answer. */
	XCTAssertTrue([[odata queryText] rangeOfString:@"$compute=EndedAtKilometres sub Kilometres as Computed2"].location
	                  != NSNotFound, @"%@", [odata queryText]);
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
	for (NSUInteger guard = 0; guard < 1000 && ![cursor atEnd]; guard++) {
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

#pragma mark Aggregates

- (ORMEditor *)fillUps
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Odometer is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Litres is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Number is a value type.\n"
	                 @"Portable data type: Numeric: Signed Integer\n"
	                 @"Vehicle(.id) is an entity type.\n"
	                 @"FillUp(.id) is of Vehicle\n"
	                 @"Each FillUp is of exactly one Vehicle.\n"
	                 @"FillUp was at Odometer\n"
	                 @"Each FillUp was at exactly one Odometer.\n"
	                 @"FillUp took Litres\n"
	                 @"Each FillUp took exactly one Litres.\n"
	                 @"\n"
	                 @"Query Before:\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + FillUp2 is of that Vehicle\n"
	                 @"      + was at Odometer2 < Odometer1\n"
	                 @"    + ✓FillUp3 is of that Vehicle\n"
	                 @"      + was at Odometer3 = Previous\n"
	                 @"  Previous = max(Odometer2) for FillUp1\n"
	                 @"\n"
	                 @"Query Consumption:\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + took Litres1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + FillUp2 is of that Vehicle\n"
	                 @"      + was at Odometer2 < Odometer1\n"
	                 @"  Previous = max(Odometer2) for FillUp1\n"
	                 @"  ✓Consumption = Litres1 / (Odometer1 - Previous) * 100\n"
	                 @"\n"
	                 @"Query Since:\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + FillUp2 is of that Vehicle\n"
	                 @"      + was at Odometer2 < Odometer1\n"
	                 @"    + FillUp3 is of that Vehicle\n"
	                 @"      + was at Odometer3 > Previous\n"
	                 @"      + was at Odometer3 <= Odometer1\n"
	                 @"      + took Litres3\n"
	                 @"  Previous = max(Odometer2) for FillUp1\n"
	                 @"  ✓Since = total(Litres3) for FillUp1\n"
	                 @"\n"
	                 @"Query Shifted:\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + FillUp2 is of that Vehicle\n"
	                 @"      + was at Odometer2\n"
	                 @"      + took Litres2\n"
	                 @"      Later: Odometer = Odometer2 + 500 < Odometer1\n"
	                 @"  ✓Most = max(Litres2) for FillUp1\n"
	                 @"\n"
	                 @"Query Among:\n"
	                 @"✓FillUp\n"
	                 @"  + took Litres in (30, 36)\n"
	                 @"\n"
	                 @"Query SameLitres:\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + took Litres1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + FillUp2 is of that Vehicle\n"
	                 @"      + took Litres2 = Litres1\n"
	                 @"      + was at Odometer2 < Odometer1\n"
	                 @"  ✓Prior = max(Odometer2) for FillUp1\n"
	                 @"\n"
	                 @"Query First:\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + not FillUp2 is of that Vehicle\n"
	                 @"      + was at Odometer2 < Odometer1\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	return editor;
}

/* An aggregate is a value node's whole expression: "max(X) for Y". */
- (void)testAggregatesAreReadAndWritten
{
	NSDictionary *ids = @{ @"A": @"_a", @"B": @"_b", @"C": @"_c" };
	NSDictionary *names = @{ @"_a": @"A", @"_b": @"B", @"_c": @"C" };
	NSString *reason = nil;
	ORMQueryExpression *e = [ORMQueryExpression expressionWithText:@"max(A) for B" designations:ids reason:&reason];
	XCTAssertEqual(e.kind, ORMQueryExpressionAggregate, @"%@", reason);
	XCTAssertEqualObjects([e canonicalText], @"max(#_a) for #_b");
	XCTAssertEqualObjects([e textWithDesignations:names], @"max(A) for B");
	XCTAssertEqualObjects([ORMQueryExpression expressionWithCanonicalText:@"max(#_a) for #_b" reason:NULL], e);
	XCTAssertEqualObjects([e nodeIds], (@[ @"_a", @"_b" ]));
	XCTAssertEqualObjects([[e expressionRenaming:@"_b" to:@"_d"] canonicalText], @"max(#_a) for #_d");
	e = [ORMQueryExpression expressionWithText:@"count(A) for B, C" designations:ids reason:NULL];
	XCTAssertEqualObjects([e canonicalText], @"count(#_a) for #_b, #_c");
	/* max of two is a function still. */
	e = [ORMQueryExpression expressionWithText:@"max(A, B)" designations:ids reason:NULL];
	XCTAssertEqual(e.kind, ORMQueryExpressionFunction);
	for (NSString *wrong in @[ @"max(A) for B + 1", @"1 + max(A) for B", @"total(A)", @"max(A) for D", @"max(A + 1) for B" ]) {
		reason = nil;
		XCTAssertNil([ORMQueryExpression expressionWithText:wrong designations:ids reason:&reason], @"%@", wrong);
		XCTAssertTrue([reason length] > 0, @"%@", wrong);
	}
}

/* The one before: the greatest earlier reading, a value node for each
 * fill-up, which another node is compared with; used in arithmetic. */
- (void)testTheOneBefore
{
	ORMEditor *editor = [self fillUps];
	ORMQuery *before = [self query:@"Before" in:editor.model];
	XCTAssertEqualObjects([before outlineText], @"✓FillUp1\n"
	                                            @"  + was at Odometer1\n"
	                                            @"  + is of Vehicle\n"
	                                            @"    + FillUp2 is of that Vehicle\n"
	                                            @"      + was at Odometer2 < Odometer1\n"
	                                            @"    + ✓FillUp3 is of that Vehicle\n"
	                                            @"      + was at Odometer3 = Previous\n"
	                                            @"  Previous = max(Odometer2) for FillUp1\n");
	ORMQueryNode *previous = [self node:@"Previous" of:before];
	XCTAssertEqualObjects(previous.objectType, [editor.model objectTypeNamed:@"Odometer"]);
	XCTAssertEqual([self node:@"Odometer3" of:before].comparedNode, previous);
	NSArray *said = [[[[ORMVerbalizer alloc] initWithModel:editor.model] sentencesForQuery:before] valueForKey:@"text"];
	XCTAssertTrue([[said firstObject] rangeOfString:@"Previous is the maximum of Odometer2 for FillUp1."].location
	                  != NSNotFound, @"%@", said);
	/* What the editor refuses. */
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	NSString *root = before.root.identifier;
	NSString *vehicle = [self node:@"Vehicle" of:before].identifier;
	NSString *reason = nil;
	XCTAssertNil([queries addValueNamed:@"Many" to:root expression:@"count(Odometer2) for FillUp1" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"value type"].location != NSNotFound, @"%@", reason);
	XCTAssertNotNil([queries addValueNamed:@"Many" to:root expression:@"count(Odometer2) for FillUp1"
	                                  type:[[editor.model objectTypeNamed:@"Number"] identifier] reason:&reason], @"%@", reason);
	XCTAssertNil([queries addValueNamed:@"Odd" to:root expression:@"max(Odometer1) for Vehicle" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"or one above"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([queries addValueNamed:@"Odd" to:vehicle expression:@"max(Odometer1) for Vehicle" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"below it"].location != NSNotFound, @"%@", reason);

	/* Run: vehicle 1 filled up at 1000, 1500 and 2100 km, with 40, 30 and
	 * 36 litres; vehicle 2 once, at 500. */
	ORMModel *model = editor.model;
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	NSArray *given = @[ @[ @"1", @"1", @"1000", @"40" ], @[ @"2", @"1", @"1500", @"30" ], @[ @"3", @"1", @"2100", @"36" ],
		                @[ @"4", @"2", @"500", @"20" ] ];
	for (NSArray *each in given) {
		for (NSArray *fact in @[ @[ @"FillUp is of Vehicle", each[1] ], @[ @"FillUp was at Odometer", each[2] ],
		                         @[ @"FillUp took Litres", each[3] ] ]) {
			NSArray *roles = [[facts objectForKey:fact[0]] visibleRoles];
			XCTAssertNotNil(([editor.populationEditor addFactOf:[[facts objectForKey:fact[0]] identifier]
			                                              named:@{ [roles[0] identifier]: each[0], [roles[1] identifier]: fact[1] }
			                                             reason:&reason]), @"%@", reason);
		}
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"Before" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	XCTAssertEqualObjects([[self archived:plan] text], [plan text]);
	/* Decorrelated: the vehicle's fill-ups, once, by odometer. */
	XCTAssertTrue([[plan text] rangeOfString:@"let bag1 = read FillUp list vehicle (id), self (id), odometer"].location != NSNotFound,
	              @"%@", [plan text]);
	XCTAssertTrue([[plan text] rangeOfString:@"where Vehicle is vehicle.id, Odometer2 < odometer"].location != NSNotFound,
	              @"%@", [plan text]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	ORMQueryResult *result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects([self sorted:result.rows], (@[ @"2 1", @"3 2" ]), @"%@", [plan text]);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], (@[ @"2 1", @"3 2" ]), @"%@", [odata requestText]);
	/* Litres per hundred kilometres since the fill-up before. */
	plan = [planner planForQuery:[self query:@"Consumption" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects([self sorted:result.rows], (@[ @"2 6", @"3 6" ]), @"%@", [plan text]);
	odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], (@[ @"2 6", @"3 6" ]), @"%@", [odata requestText]);
	/* The litres since the fill-up before: an aggregate of fill-ups after
	 * another aggregate, whose bag computes that one. */
	plan = [planner planForQuery:[self query:@"Since" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	/* A window between two bounds, the lower itself a window. */
	XCTAssertTrue([[plan text] rangeOfString:@"Odometer3 > max of Odometer2 in bag1 where Vehicle is vehicle.id, Odometer2 < odometer, Odometer3 <= odometer"].location
	                  != NSNotFound, @"%@", [plan text]);
	result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects([self sorted:result.rows], (@[ @"2 30", @"3 36" ]), @"%@", [plan text]);
	odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], (@[ @"2 30", @"3 36" ]), @"%@", [odata requestText]);
	/* The most litres of a fill-up 500 km or more before: a window over a
	 * key computed of each fill-up, its existence the window's count. */
	plan = [planner planForQuery:[self query:@"Shifted" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	XCTAssertTrue([[plan text] rangeOfString:@"max of Litres2 in bag"].location != NSNotFound, @"%@", [plan text]);
	XCTAssertTrue([[plan text] rangeOfString:@"Later < odometer"].location != NSNotFound, @"%@", [plan text]);
	result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertEqualObjects([self sorted:result.rows], (@[ @"3 40" ]), @"%@", [plan text]);
	odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], (@[ @"3 40" ]), @"%@", [odata requestText]);
	/* One of a list: any of its values. */
	ORMQuery *among = [self query:@"Among" in:model];
	XCTAssertEqualObjects([among outlineText], @"✓FillUp\n  + took Litres in (30, 36)\n");
	XCTAssertEqualObjects([[self node:@"Litres" of:among] comparedValues], (@[ @"30", @"36" ]));
	said = [[[[ORMVerbalizer alloc] initWithModel:model] sentencesForQuery:among] valueForKey:@"text"];
	XCTAssertTrue([[said firstObject] rangeOfString:@" or "].location != NSNotFound, @"%@", said);
	plan = [planner planForQuery:among];
	XCTAssertEqualObjects(plan.notes, @[]);
	XCTAssertTrue([[plan text] rangeOfString:@"litres = 30 or litres = 36"].location != NSNotFound, @"%@", [plan text]);
	result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertEqualObjects([self sorted:result.rows], (@[ @"2", @"3" ]), @"%@", [plan text]);
	odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], (@[ @"2", @"3" ]), @"%@", [odata requestText]);
	/* No list, no condition. */
	ORMQueryEditor *editing = [[ORMQueryEditor alloc] initWithEditor:editor];
	NSString *refused = nil;
	XCTAssertFalse([editing setCondition:@"in" value:@"" ofNode:[self node:@"Litres" of:among].identifier reason:&refused]);
	XCTAssertTrue([refused rangeOfString:@"list"].location != NSNotFound, @"%@", refused);
	/* Each vehicle's first: none of its fill-ups below, a window's count. */
	plan = [planner planForQuery:[self query:@"First" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	XCTAssertTrue([[plan text] rangeOfString:@"count of FillUp2 in bag1 where Vehicle is vehicle.id, Odometer2 < odometer = 0"].location
	                  != NSNotFound, @"%@", [plan text]);
	result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertEqualObjects([self sorted:result.rows], (@[ @"1", @"4" ]), @"%@", [plan text]);
	odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], (@[ @"1", @"4" ]), @"%@", [odata requestText]);
}

/* A store of one vehicle's fill-ups, each 10 km after the one before;
 * the rows "the one before" gives of them. */
- (NSManagedObjectContext *)storeOf:(NSUInteger)count fillUpsOf:(ORMModel *)model planner:(ORMQueryPlanner *)planner
                           expected:(NSMutableArray *)expected
{
	return [self storeOf:count fillUpsOf:model planner:planner expected:expected alternating:NO];
}

/* The same, the litres 30 and 40 by turns where they alternate. */
- (NSManagedObjectContext *)storeOf:(NSUInteger)count
                          fillUpsOf:(ORMModel *)model
                            planner:(ORMQueryPlanner *)planner
                           expected:(NSMutableArray *)expected
                        alternating:(BOOL)alternating
{
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	[context performBlockAndWait:^{
		NSManagedObject *vehicle = [NSEntityDescription insertNewObjectForEntityForName:@"Vehicle" inManagedObjectContext:context];
		[vehicle setValue:@1 forKey:@"id"];
		for (NSUInteger i = 1; i <= count; i++) {
			NSManagedObject *fillUp = [NSEntityDescription insertNewObjectForEntityForName:@"FillUp" inManagedObjectContext:context];
			[fillUp setValue:@(i) forKey:@"id"];
			[fillUp setValue:vehicle forKey:@"vehicle"];
			[fillUp setValue:[NSDecimalNumber numberWithUnsignedInteger:1000 + 10 * i] forKey:@"odometer"];
			[fillUp setValue:[NSDecimalNumber numberWithUnsignedInteger:alternating && i % 2 == 0 ? 40 : 30] forKey:@"litres"];
			if (i > 1) {
				[expected addObject:@[ @(i), @(i - 1) ]];
			}
		}
		NSError *saved = nil;
		XCTAssertTrue([context save:&saved], @"%@", saved);
	}];
	return context;
}

/* A window within each value equal to the object's: the greatest odometer
 * below this one's among the vehicle's fill-ups of the same litres, the
 * one two before. */
- (void)testAWindowWithinEqualValues
{
	ORMEditor *editor = [self fillUps];
	ORMModel *model = editor.model;
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"SameLitres" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	XCTAssertTrue([[plan text] rangeOfString:@"where Vehicle is vehicle.id, Litres2 is litres, Odometer2 < odometer"].location
	                  != NSNotFound, @"%@", [plan text]);
	NSManagedObjectContext *context = [self storeOf:8 fillUpsOf:model planner:planner expected:[NSMutableArray array]
	                                    alternating:YES];
	NSMutableArray *expected = [NSMutableArray array];
	for (NSUInteger i = 3; i <= 8; i++) {
		[expected addObject:@[ @(i), @(1000 + 10 * (i - 2)) ]];
	}
	NSError *error = nil;
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	ORMQueryResult *result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects([self sorted:result.rows], [self sorted:expected], @"%@", [plan text]);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], [self sorted:expected], @"%@", [odata requestText]);
}

/* A window whose partition is read over many batches (and pages): made
 * once, each fill-up's the one before it. The service's in pages of ten,
 * the vehicle's fill-ups read once for its owner (a graft), not with each
 * fill-up read. */
- (void)testAWindowOverManyBatches
{
	ORMEditor *editor = [self fillUps];
	ORMModel *model = editor.model;
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"Before" in:model]];
	NSMutableArray *expected = [NSMutableArray array];
	NSManagedObjectContext *context = [self storeOf:600 fillUpsOf:model planner:planner expected:expected];
	NSError *error = nil;
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	ORMQueryResult *result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects([self sorted:result.rows], [self sorted:expected]);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertTrue([[odata requestText] rangeOfString:@"FillUps of each page's Vehicle, once each"].location != NSNotFound,
	              @"%@", [odata requestText]);
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], [self sorted:expected], @"%@", [odata requestText]);
}

/* The one before among a supertype's records: the bag lists a
 * subtype's property, which the service gives with each such record. */
- (void)testTheOneBeforeThroughASubtype
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Odometer is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Vehicle(.id) is an entity type.\n"
	                 @"Record(.id) is of Vehicle\n"
	                 @"Each Record is of exactly one Vehicle.\n"
	                 @"Each FillUp is a Record.\n"
	                 @"Each Repair is a Record.\n"
	                 @"FillUp was at Odometer\n"
	                 @"Each FillUp was at exactly one Odometer.\n"
	                 @"\n"
	                 @"Query Before:\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + Record is of that Vehicle\n"
	                 @"      + is FillUp2\n"
	                 @"        + was at Odometer2 < Odometer1\n"
	                 @"  ✓Previous = max(Odometer2) for FillUp1\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model factTypes]) {
		if ([fact primaryReading] != nil) {
			[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
		}
	}
	NSString *reason = nil;
	for (NSArray *each in @[ @[ @"1", @"1", @"1000" ], @[ @"2", @"1", @"" ], @[ @"3", @"1", @"1500" ], @[ @"4", @"2", @"500" ] ]) {
		ORMObjectType *kind = [model objectTypeNamed:[each[2] length] > 0 ? @"FillUp" : @"Repair"];
		XCTAssertNotNil([editor.populationEditor addInstanceOf:kind.identifier named:each[0] reason:&reason], @"%@", reason);
		if ([each[2] length] > 0) {
			NSArray *roles = [[facts objectForKey:@"FillUp was at Odometer"] visibleRoles];
			XCTAssertNotNil(([editor.populationEditor addFactOf:[[facts objectForKey:@"FillUp was at Odometer"] identifier]
			                                              named:@{ [roles[0] identifier]: each[0], [roles[1] identifier]: each[2] }
			                                             reason:&reason]), @"%@", reason);
		}
		NSArray *roles = [[facts objectForKey:@"Record is of Vehicle"] visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:[[facts objectForKey:@"Record is of Vehicle"] identifier]
		                                              named:@{ [roles[0] identifier]: each[0], [roles[1] identifier]: each[1] }
		                                             reason:&reason]), @"%@", reason);
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"Before" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	ORMQueryResult *result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects([self sorted:result.rows], (@[ @"3 1000" ]), @"%@", [plan text]);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], (@[ @"3 1000" ]), @"%@", [odata requestText]);
}

/* The one before down a chain of subtypes, at a distance absorbed into
 * the record (its quantity and unit), of full tanks only, in the same
 * unit: a window, partitioned by vehicle and unit. A trip is an event but
 * no fill-up; a repair no event. And the one there, of any unit: looked
 * up by its quantity among the vehicle's fill-ups, the trip at the same
 * quantity not one. */
- (void)testTheOneBeforeDownSubtypesAndParts
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Quantity is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Vehicle(.id) is an entity type.\n"
	                 @"DistanceUnit(.code) is an entity type.\n"
	                 @"Record(.id) is of Vehicle\n"
	                 @"Each Record is of exactly one Vehicle.\n"
	                 @"Each Event is a Record.\n"
	                 @"Each Repair is a Record.\n"
	                 @"Each FillUp is an Event.\n"
	                 @"Each Trip is an Event.\n"
	                 @"Distance has Quantity\n"
	                 @"Each Distance has exactly one Quantity.\n"
	                 @"Distance is in DistanceUnit\n"
	                 @"Each Distance is in exactly one DistanceUnit.\n"
	                 @"For each Quantity and DistanceUnit, at most one Distance has that Quantity and is in that DistanceUnit.\n"
	                 @"This association with Quantity and DistanceUnit provides the preferred identification scheme for Distance.\n"
	                 @"Event was at Distance\n"
	                 @"Each Event was at exactly one Distance.\n"
	                 @"FillUp filled the tank\n"
	                 @"\n"
	                 @"Query Before:\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Distance1\n"
	                 @"    + has Quantity1\n"
	                 @"    + is in ✓DistanceUnit1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + Record is of that Vehicle\n"
	                 @"      + is Event\n"
	                 @"        + is FillUp2\n"
	                 @"          + filled the tank\n"
	                 @"          + was at Distance2\n"
	                 @"            + has Quantity2 < Quantity1\n"
	                 @"            + is in DistanceUnit1\n"
	                 @"  ✓Previous = max(Quantity2) for FillUp1\n"
	                 @"\n"
	                 @"Query Prior:\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Distance1\n"
	                 @"    + has Quantity1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + Record is of that Vehicle\n"
	                 @"      + is Event\n"
	                 @"        + is FillUp2\n"
	                 @"          + was at Distance2\n"
	                 @"            + has Quantity2 < Quantity1\n"
	                 @"    + Record is of that Vehicle\n"
	                 @"      + is Event\n"
	                 @"        + is ✓FillUp3\n"
	                 @"          + was at Distance3\n"
	                 @"            + has Quantity3 = Previous\n"
	                 @"  Previous = max(Quantity2) for FillUp1\n"
	                 @"\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"Before" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	XCTAssertTrue([[plan text] rangeOfString:@"max of Quantity2 in bag1 where Vehicle is vehicle.id, DistanceUnit1 is "].location
	                  != NSNotFound, @"%@", [plan text]);
	XCTAssertTrue([[plan text] rangeOfString:@"SUBQUERY"].location == NSNotFound, @"%@", [plan text]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	/* Id, vehicle, kind, quantity, unit, full. */
	NSArray *records = @[ @[ @1, @1, @"FillUp", @1000, @"km", @YES ], @[ @2, @1, @"Repair" ], @[ @3, @1, @"FillUp", @1300, @"mi", @YES ],
		                  @[ @4, @1, @"FillUp", @1500, @"km", @YES ], @[ @5, @1, @"FillUp", @1200, @"km", @NO ],
		                  @[ @6, @1, @"FillUp", @2000, @"km", @YES ], @[ @7, @2, @"FillUp", @500, @"km", @YES ],
		                  @[ @8, @1, @"Trip", @1500, @"km" ], @[ @9, @1, @"FillUp", @1400, @"mi", @YES ] ];
	ORMCDEntity *event = [planner.coreData entityNamed:@"Event"];
	NSString *quantity = nil;
	NSString *unit = nil;
	for (ORMCDProperty *property in event.properties) {
		quantity = [property.name hasSuffix:@"Quantity"] ? property.name : quantity;
		unit = [property.name hasSuffix:@"DistanceUnit"] ? property.name : unit;
	}
	XCTAssertNotNil(quantity);
	XCTAssertNotNil(unit);
	[context performBlockAndWait:^{
		NSMutableDictionary *made = [NSMutableDictionary dictionary];
		for (NSArray *each in @[ @[ @"Vehicle", @"id", @1 ], @[ @"Vehicle", @"id", @2 ], @[ @"DistanceUnit", @"code", @"km" ],
		                         @[ @"DistanceUnit", @"code", @"mi" ] ]) {
			NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:each[0] inManagedObjectContext:context];
			[object setValue:each[2] forKey:each[1]];
			[made setObject:object forKey:each[2]];
		}
		for (NSArray *each in records) {
			NSManagedObject *record = [NSEntityDescription insertNewObjectForEntityForName:each[2] inManagedObjectContext:context];
			[record setValue:each[0] forKey:@"id"];
			[record setValue:[made objectForKey:each[1]] forKey:@"vehicle"];
			if ([each count] > 3) {
				[record setValue:[NSDecimalNumber numberWithInteger:[each[3] integerValue]] forKey:quantity];
				[record setValue:[made objectForKey:each[4]] forKey:unit];
			}
			if ([each count] > 5) {
				[record setValue:each[5] forKey:@"filledTheTank"];
			}
		}
		NSError *saved = nil;
		XCTAssertTrue([context save:&saved], @"%@", saved);
	}];
	NSArray *expected = @[ @"4 km 1000", @"5 km 1000", @"6 km 1500", @"9 mi 1300" ];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	ORMQueryResult *result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects([self sorted:result.rows], expected, @"%@", [plan text]);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], expected, @"%@", [odata requestText]);
	plan = [planner planForQuery:[self query:@"Prior" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	expected = @[ @"3 5", @"4 9", @"5 1", @"6 4", @"9 3" ];
	result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects([self sorted:result.rows], expected, @"%@", [plan text]);
	odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], expected, @"%@", [odata requestText]);
}

/* A derivation stored, of the one before: worked out at save over a
 * window of the vehicle's fill-ups, read from the context with what it
 * has not saved; a fill-up moved changes those of every fill-up of its
 * vehicle, which a change to one reaches by its vehicle. */
- (void)testTheOneBeforeIsStoredAtSave
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Odometer is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Litres is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Vehicle(.id) is an entity type.\n"
	                 @"FillUp(.id) is of Vehicle\n"
	                 @"Each FillUp is of exactly one Vehicle.\n"
	                 @"FillUp was at Odometer\n"
	                 @"Each FillUp was at exactly one Odometer.\n"
	                 @"FillUp took Litres\n"
	                 @"Each FillUp took exactly one Litres.\n"
	                 @"FillUp followed Litres\n"
	                 @"** The litres of the vehicle's fill-up before.\n"
	                 @"Each FillUp followed at most one Litres.\n"
	                 @"\n"
	                 @"Query Followed:\n"
	                 @"Derivation of \"FillUp followed Litres\":\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + FillUp2 is of that Vehicle\n"
	                 @"      + was at Odometer2 < Odometer1\n"
	                 @"    + FillUp3 is of that Vehicle\n"
	                 @"      + was at Odometer3 = Previous\n"
	                 @"      + took ✓Litres\n"
	                 @"  Previous = max(Odometer2) for FillUp1\n"
	                 @"\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:editor.model mapping:nil name:@"Fuel"];
	NSDictionary *files = [generator files];
	NSData *data = [[files objectForKey:@"Fuel.ormplans"] dataUsingEncoding:NSUTF8StringEncoding];
	id list = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
	NSError *error = nil;
	ORMTables *tables = [ORMTables tablesWithPropertyList:list error:&error];
	XCTAssertNotNil(tables, @"%@", error);
	XCTAssertEqual([tables.derivations count], 1u, @"%@", generator.notes);
	ORMStoredDerivation *derivation = [tables.derivations firstObject];
	XCTAssertTrue([[derivation.plan text] rangeOfString:@"Odometer2 < odometer"].location != NSNotFound, @"%@", [derivation.plan text]);
	XCTAssertTrue([derivation.backs containsObject:(@[ @"FillUp", @[ @"vehicle", @"fillUps" ] ])], @"%@", derivation.backs);
	NSString *target = derivation.target;
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:editor.model mapping:nil];
	NSManagedObjectContext *context = [[[ORMPopulationStore alloc] initWithModel:editor.model coreData:planner.coreData]
		newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMSaveHook *hook = [[ORMSaveHook alloc] initWithTables:tables];
	[context performBlockAndWait:^{
		NSManagedObject *vehicle = [NSEntityDescription insertNewObjectForEntityForName:@"Vehicle" inManagedObjectContext:context];
		[vehicle setValue:@1 forKey:@"id"];
		NSMutableArray *fillUps = [NSMutableArray array];
		for (NSArray *each in @[ @[ @1, @1000, @40 ], @[ @2, @1500, @30 ], @[ @3, @2100, @36 ] ]) {
			NSManagedObject *fillUp = [NSEntityDescription insertNewObjectForEntityForName:@"FillUp" inManagedObjectContext:context];
			[fillUp setValue:each[0] forKey:@"id"];
			[fillUp setValue:vehicle forKey:@"vehicle"];
			[fillUp setValue:[NSDecimalNumber numberWithInteger:[each[1] integerValue]] forKey:@"odometer"];
			[fillUp setValue:[NSDecimalNumber numberWithInteger:[each[2] integerValue]] forKey:@"litres"];
			[fillUps addObject:fillUp];
		}
		NSError *derived = nil;
		XCTAssertTrue([hook deriveInContext:context changed:[NSMutableSet setWithSet:[context insertedObjects]] error:&derived],
		              @"%@", derived);
		XCTAssertNil([fillUps[0] valueForKey:target]);
		XCTAssertEqualObjects([[fillUps[1] valueForKey:target] description], @"40");
		XCTAssertEqualObjects([[fillUps[2] valueForKey:target] description], @"30");
		XCTAssertTrue([context save:&derived], @"%@", derived);
		/* The second moved past the third: each one's before is another. */
		[fillUps[1] setValue:[NSDecimalNumber numberWithInteger:2200] forKey:@"odometer"];
		XCTAssertTrue([hook deriveInContext:context changed:[NSMutableSet setWithSet:[context updatedObjects]] error:&derived],
		              @"%@", derived);
		XCTAssertEqualObjects([[fillUps[1] valueForKey:target] description], @"36");
		XCTAssertEqualObjects([[fillUps[2] valueForKey:target] description], @"40");
		XCTAssertTrue([context save:&derived], @"%@", derived);
	}];
}

/* The one before stored on a subtype of the vehicle's records: a change
 * reaches the vehicle's records, a repair among them, which is no root of
 * it (nor has the property). A way back on through a fill-up's own
 * relationship (its station) passes the repair by. */
- (void)testTheOneBeforeIsStoredOnASubtype
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Odometer is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Vehicle(.id) is an entity type.\n"
	                 @"Record(.id) is of Vehicle\n"
	                 @"Each Record is of exactly one Vehicle.\n"
	                 @"Each FillUp is a Record.\n"
	                 @"Each Repair is a Record.\n"
	                 @"FillUp was at Odometer\n"
	                 @"Each FillUp was at exactly one Odometer.\n"
	                 @"FillUp followed Odometer\n"
	                 @"** The odometer of the vehicle's fill-up before.\n"
	                 @"Each FillUp followed at most one Odometer.\n"
	                 @"FillUp was at Station(.name)\n"
	                 @"Each FillUp was at at most one Station.\n"
	                 @"\n"
	                 @"Query Followed:\n"
	                 @"Derivation of \"FillUp followed Odometer\":\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + Record is of that Vehicle\n"
	                 @"      + is FillUp2\n"
	                 @"        + was at Odometer2 < Odometer1\n"
	                 @"  ✓Previous = max(Odometer2) for FillUp1\n"
	                 @"\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:editor.model mapping:nil name:@"Fuel"];
	NSData *data = [[[generator files] objectForKey:@"Fuel.ormplans"] dataUsingEncoding:NSUTF8StringEncoding];
	id list = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
	NSError *error = nil;
	ORMTables *tables = [ORMTables tablesWithPropertyList:list error:&error];
	XCTAssertEqual([tables.derivations count], 1u, @"%@", generator.notes);
	NSString *target = tables.derivations.firstObject.target;
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:editor.model mapping:nil];
	NSManagedObjectContext *context = [[[ORMPopulationStore alloc] initWithModel:editor.model coreData:planner.coreData]
		newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMSaveHook *hook = [[ORMSaveHook alloc] initWithTables:tables];
	[context performBlockAndWait:^{
		NSManagedObject *vehicle = [NSEntityDescription insertNewObjectForEntityForName:@"Vehicle" inManagedObjectContext:context];
		[vehicle setValue:@1 forKey:@"id"];
		NSManagedObject *repair = [NSEntityDescription insertNewObjectForEntityForName:@"Repair" inManagedObjectContext:context];
		[repair setValue:@1 forKey:@"id"];
		[repair setValue:vehicle forKey:@"vehicle"];
		NSMutableArray *fillUps = [NSMutableArray array];
		for (NSArray *each in @[ @[ @2, @1000 ], @[ @3, @1500 ] ]) {
			NSManagedObject *fillUp = [NSEntityDescription insertNewObjectForEntityForName:@"FillUp" inManagedObjectContext:context];
			[fillUp setValue:each[0] forKey:@"id"];
			[fillUp setValue:vehicle forKey:@"vehicle"];
			[fillUp setValue:[NSDecimalNumber numberWithInteger:[each[1] integerValue]] forKey:@"odometer"];
			[fillUps addObject:fillUp];
		}
		NSError *derived = nil;
		XCTAssertTrue([hook prepareForSaveInContext:context error:&derived], @"%@", derived);
		XCTAssertNil([fillUps[0] valueForKey:target]);
		XCTAssertEqualObjects([[fillUps[1] valueForKey:target] description], @"1000");
		NSManagedObject *station = [NSEntityDescription insertNewObjectForEntityForName:@"Station" inManagedObjectContext:context];
		[station setValue:@"Shell" forKey:@"name"];
		[fillUps[1] setValue:station forKey:@"station"];
		NSSet *reached = [ORMSaveHook rootsOf:@"Station" backs:@[ @[ @"Vehicle", @[ @"records", @"station" ] ] ]
		                              changed:[NSSet setWithObject:vehicle] inContext:context];
		XCTAssertEqualObjects(reached, [NSSet setWithObject:station]);
	}];
}

/* The same in a service (docs/RULES.md): a client's save is one change
 * set, and the service, before it saves it, works out what is derived and
 * checks the rules for what the change reaches (-[ODataService willSave],
 * -[ORMSaveHook prepareForSaveInContext:error:]). A fill-up after one of
 * more than 50 litres breaks a rule over the derived value: the change set
 * is refused, and the service has none of it. */
- (void)testAServiceKeepsTheRulesOfAChangeSet
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Odometer is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Litres is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Vehicle(.id) is an entity type.\n"
	                 @"FillUp(.id) is of Vehicle\n"
	                 @"Each FillUp is of exactly one Vehicle.\n"
	                 @"FillUp was at Odometer\n"
	                 @"Each FillUp was at exactly one Odometer.\n"
	                 @"FillUp took Litres\n"
	                 @"Each FillUp took exactly one Litres.\n"
	                 @"FillUp followed Litres\n"
	                 @"** The litres of the vehicle's fill-up before.\n"
	                 @"Each FillUp followed at most one Litres.\n"
	                 @"\n"
	                 @"Query Followed:\n"
	                 @"Derivation of \"FillUp followed Litres\":\n"
	                 @"✓FillUp1\n"
	                 @"  + was at Odometer1\n"
	                 @"  + is of Vehicle\n"
	                 @"    + FillUp2 is of that Vehicle\n"
	                 @"      + was at Odometer2 < Odometer1\n"
	                 @"    + FillUp3 is of that Vehicle\n"
	                 @"      + was at Odometer3 = Previous\n"
	                 @"      + took ✓Litres\n"
	                 @"  Previous = max(Odometer2) for FillUp1\n"
	                 @"\n"
	                 @"Query Spilled:\n"
	                 @"It is impossible that:\n"
	                 @"✓FillUp\n"
	                 @"  + followed Litres > 50\n"
	                 @"\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:editor.model mapping:nil name:@"Fuel"];
	NSDictionary *files = [generator files];
	NSData *data = [[files objectForKey:@"Fuel.ormplans"] dataUsingEncoding:NSUTF8StringEncoding];
	id list = data != nil ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
	NSError *error = nil;
	ORMTables *tables = [ORMTables tablesWithPropertyList:list error:&error];
	XCTAssertNotNil(tables, @"%@", error);
	XCTAssertEqual([tables.derivations count], 1u, @"%@", generator.notes);
	XCTAssertEqual([tables.rules count], 1u, @"%@", generator.notes);
	NSString *target = tables.derivations.firstObject.target;

	/* The service's store, and what it asks before it saves. */
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:editor.model mapping:nil];
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	NSManagedObjectContext *served = [[[ORMPopulationStore alloc] initWithModel:editor.model coreData:planner.coreData]
		newContextWithError:&error];
	XCTAssertNotNil(served, @"%@", error);
	NSURL *root = [NSURL URLWithString:@"http://example.test/odata/"];
	ODataService *service = [[ODataService alloc] initWithPersistentStoreCoordinator:served.persistentStoreCoordinator serviceRoot:root];
	ORMSaveHook *hook = [[ORMSaveHook alloc] initWithTables:tables];
	__block NSUInteger asked = 0;
	service.willSave = ^BOOL(NSManagedObjectContext *context, NSError **refused) {
		asked++;
		return [hook prepareForSaveInContext:context error:refused];
	};

	/* A client of it, which gives the keys: what it saves is one change
	 * set, its inserts in it. */
	[ODataIncrementalStore registerStore];
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	NSDictionary *options = @{ ODataIncrementalStoreTransportOption: service, ODataIncrementalStorePostOnObtainPermanentIDsOption: @NO };
	XCTAssertNotNil([coordinator addPersistentStoreWithType:[ODataIncrementalStore storeType] configuration:nil URL:root
	                                                options:options error:&error], @"%@", error);
	NSManagedObjectContext *client = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	client.persistentStoreCoordinator = coordinator;
	[client performBlockAndWait:^{
		NSManagedObject *vehicle = [NSEntityDescription insertNewObjectForEntityForName:@"Vehicle" inManagedObjectContext:client];
		[vehicle setValue:@1 forKey:@"id"];
		for (NSArray *each in @[ @[ @1, @1000, @40 ], @[ @2, @1500, @60 ] ]) {
			NSManagedObject *fillUp = [NSEntityDescription insertNewObjectForEntityForName:@"FillUp" inManagedObjectContext:client];
			[fillUp setValue:each[0] forKey:@"id"];
			[fillUp setValue:vehicle forKey:@"vehicle"];
			[fillUp setValue:[NSDecimalNumber numberWithInteger:[each[1] integerValue]] forKey:@"odometer"];
			[fillUp setValue:[NSDecimalNumber numberWithInteger:[each[2] integerValue]] forKey:@"litres"];
		}
		NSError *saved = nil;
		XCTAssertTrue([client save:&saved], @"%@", saved);
		/* After the one of 60 litres. */
		NSManagedObject *third = [NSEntityDescription insertNewObjectForEntityForName:@"FillUp" inManagedObjectContext:client];
		[third setValue:@3 forKey:@"id"];
		[third setValue:vehicle forKey:@"vehicle"];
		[third setValue:[NSDecimalNumber numberWithInteger:2100] forKey:@"odometer"];
		[third setValue:[NSDecimalNumber numberWithInteger:36] forKey:@"litres"];
		saved = nil;
		XCTAssertFalse([client save:&saved]);
		XCTAssertNotNil(saved);
	}];
	XCTAssertEqual(asked, 2u, @"once for each change set");

	/* What the service has: the first two, the second's derived. */
	[served performBlockAndWait:^{
		NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"FillUp"];
		fetch.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES] ];
		NSArray *fillUps = [served executeFetchRequest:fetch error:NULL];
		XCTAssertEqualObjects([fillUps valueForKey:@"id"], (@[ @1, @2 ]));
		XCTAssertEqual([fillUps[0] valueForKey:target], nil);
		XCTAssertEqualObjects([[fillUps[1] valueForKey:target] description], @"40");
	}];
}

#pragma mark Dates

/* Durations and dates, in UTC: across midnight, at a month's end; a
 * computed date compared; from the store and from the service. */
- (void)testDates
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Moment is a value type.\n"
	                 @"Portable data type: Temporal: Date & Time\n"
	                 @"Count is a value type.\n"
	                 @"Portable data type: Numeric: Signed Integer\n"
	                 @"Trip(.id) started at Moment\n"
	                 @"Each Trip started at exactly one Moment.\n"
	                 @"Trip ended at Moment\n"
	                 @"Each Trip ended at exactly one Moment.\n"
	                 @"\n"
	                 @"Query Durations:\n"
	                 @"✓Trip\n"
	                 @"  + started at Moment1\n"
	                 @"  + ended at Moment2\n"
	                 @"  ✓Duration: Count = minutes(Moment1, Moment2)\n"
	                 @"  ✓Days: Count = days(Moment1, Moment2)\n"
	                 @"  ✓Month = month(Moment1)\n"
	                 @"  ✓Due = addMonths(Moment1, 6) > '2026-08-01'\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	ORMQuery *query = [self query:@"Durations" in:model];
	XCTAssertTrue([[query outlineText] hasSuffix:@"  ✓Month = month(Moment1)\n  ✓Due = addMonths(Moment1, 6) > '2026-08-01'\n"],
	              @"%@", [query outlineText]);
	NSArray *said = [[[[ORMVerbalizer alloc] initWithModel:model] sentencesForQuery:query] valueForKey:@"text"];
	for (NSString *words in @[ @"Duration is the number of minutes from Moment1 to Moment2",
	                           @"Month is the first day of the month of Moment1", @"Due is Moment1 plus 6 months" ]) {
		XCTAssertTrue([[said firstObject] rangeOfString:words].location != NSNotFound, @"%@", said);
	}
	/* What is refused. */
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	NSString *root = query.root.identifier;
	NSString *count = [[model objectTypeNamed:@"Count"] identifier];
	NSString *reason = nil;
	XCTAssertNil([queries addValueNamed:@"Odd" to:root expression:@"minutes(Moment1, 3)" type:count reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"3 is not a moment or a date"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([queries addValueNamed:@"Odd" to:root expression:@"Moment1 + 1" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"Moment1 is not a number"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([queries addValueNamed:@"Odd" to:root expression:@"days(Moment1, Moment2)" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"name the value type"].location != NSNotFound, @"%@", reason);
	XCTAssertNil([queries addValueNamed:@"Odd" to:root expression:@"addDays(Moment1, 1)" type:count reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"computes a moment"].location != NSNotFound, @"%@", reason);
	XCTAssertNotNil([queries addValueNamed:@"Since" to:root expression:@"days('2026-01-01', today())" type:count reason:&reason],
	                @"%@", reason);

	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	for (NSArray *each in @[ @[ @"1", @"2026-01-31T22:00:00", @"2026-02-01T01:30:00" ],
	                         @[ @"2", @"2026-03-10T08:00:00", @"2026-03-10T09:15:00" ] ]) {
		for (NSArray *fact in @[ @[ @"Trip started at Moment", each[1] ], @[ @"Trip ended at Moment", each[2] ] ]) {
			NSArray *roles = [[facts objectForKey:fact[0]] visibleRoles];
			XCTAssertNotNil(([editor.populationEditor addFactOf:[[facts objectForKey:fact[0]] identifier]
			                                              named:@{ [roles[0] identifier]: each[0], [roles[1] identifier]: fact[1] }
			                                             reason:&reason]), @"%@", reason);
		}
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"Durations" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	XCTAssertEqualObjects([[self archived:plan] text], [plan text]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	ORMQueryResult *result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	NSArray *expected = @[ @"2 75 0 2026-03-01T00:00:00Z 2026-09-10T08:00:00Z" ];
	XCTAssertEqualObjects([self datedRows:result.rows], expected, @"%@", [plan text]);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqualObjects([self datedRows:[self rowsOf:odata over:context]], expected, @"%@", [odata requestText]);
	/* Across midnight, at a month's end, without the condition. */
	XCTAssertEqualObjects(ORMPlanApply(@"minutes", @[ @"2026-01-31T22:00:00Z", @"2026-02-01T01:30:00Z" ]), @210);
	XCTAssertEqualObjects(ORMPlanApply(@"days", @[ @"2026-01-31T22:00:00Z", @"2026-02-01T01:30:00Z" ]), @1);
	XCTAssertEqualObjects(ORMPlanApply(@"months", @[ @"2026-01-31", @"2026-03-30" ]), @1);
	NSArray *dates = @[ ORMPlanApply(@"addMonths", @[ @"2026-01-31T22:00:00Z", @1 ]),
		                ORMPlanApply(@"date", @[ @"2026-01-31T22:00:00Z" ]), ORMPlanApply(@"addDays", @[ @"2026-12-31", @1 ]) ];
	XCTAssertEqualObjects([self datedRows:@[ dates ]], (@[ @"2026-02-28T22:00:00Z 2026-01-31T00:00:00Z 2027-01-01T00:00:00Z" ]));
}

/* A rule with a computed value is no one predicate, but the generated
 * tables' validator asks its plan of each object in memory. */
- (void)testARuleWithAComputedValueIsValidated
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Moment is a value type.\n"
	                 @"Portable data type: Temporal: Date & Time\n"
	                 @"Count is a value type.\n"
	                 @"Portable data type: Numeric: Signed Integer\n"
	                 @"Trip(.id) started at Moment\n"
	                 @"Each Trip started at exactly one Moment.\n"
	                 @"Trip ended at Moment\n"
	                 @"Each Trip ended at exactly one Moment.\n"
	                 @"\n"
	                 @"Query Backwards:\n"
	                 @"It is impossible that:\n"
	                 @"✓Trip\n"
	                 @"  + started at Moment1\n"
	                 @"  + ended at Moment2\n"
	                 @"  Length: Count = minutes(Moment1, Moment2) < 0\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	NSString *reason = nil;
	for (NSArray *each in @[ @[ @"1", @"2026-03-10T08:00:00", @"2026-03-10T09:15:00" ],
	                         @[ @"2", @"2026-03-11T08:00:00", @"2026-03-11T07:00:00" ] ]) {
		for (NSArray *fact in @[ @[ @"Trip started at Moment", each[1] ], @[ @"Trip ended at Moment", each[2] ] ]) {
			NSArray *roles = [[facts objectForKey:fact[0]] visibleRoles];
			XCTAssertNotNil(([editor.populationEditor addFactOf:[[facts objectForKey:fact[0]] identifier]
			                                              named:@{ [roles[0] identifier]: each[0], [roles[1] identifier]: fact[1] }
			                                             reason:&reason]), @"%@", reason);
		}
	}
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:model mapping:nil name:@"Trips"];
	ORMTables *tables = [generator tables];
	NSString *notes = [generator.notes componentsJoinedByString:@"\n"];
	XCTAssertTrue([notes rangeOfString:@"Backwards"].location == NSNotFound, @"%@", notes);
	ORMRule *rule = [[tables.rules objectForKey:@"Trip"] lastObject];
	XCTAssertEqualObjects(rule.constraint, @"Backwards");
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMValidator *validator = [[ORMValidator alloc] initWithTables:tables];
	NSMutableArray *invalid = [NSMutableArray array];
	for (NSManagedObject *trip in [context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Trip"] error:NULL]) {
		if (![validator validate:trip error:NULL]) {
			[invalid addObject:[trip valueForKey:@"id"]];
		}
	}
	XCTAssertEqualObjects(invalid, @[ @2 ]);
}

#pragma mark Grouping

/* Costs by vehicle and month: an aggregate for a node and a value node,
 * the rows one for each, sorted by the total, which is computed. */
- (void)testGroupingByMonth
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Moment is a value type.\n"
	                 @"Portable data type: Temporal: Date & Time\n"
	                 @"Amount is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Vehicle(.id) is an entity type.\n"
	                 @"Cost(.id) is of Vehicle\n"
	                 @"Each Cost is of exactly one Vehicle.\n"
	                 @"Cost was at Moment\n"
	                 @"Each Cost was at exactly one Moment.\n"
	                 @"Cost cost Amount\n"
	                 @"Each Cost cost exactly one Amount.\n"
	                 @"\n"
	                 @"Query ByMonth:\n"
	                 @"✓Vehicle\n"
	                 @"  + Cost is of that Vehicle\n"
	                 @"    + was at Moment\n"
	                 @"    + cost Amount\n"
	                 @"    ✓Month = month(Moment)\n"
	                 @"    ✓Total = total(Amount) for Vehicle, Month ↓\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	ORMQuery *query = [self query:@"ByMonth" in:model];
	XCTAssertTrue([[query outlineText] hasSuffix:@"    ✓Total = total(Amount) for Vehicle, Month ↓\n"], @"%@", [query outlineText]);
	NSArray *said = [[[[ORMVerbalizer alloc] initWithModel:model] sentencesForQuery:query] valueForKey:@"text"];
	XCTAssertTrue([[said firstObject] rangeOfString:@"Total is the total of that Amount for that Vehicle and Month"].location != NSNotFound,
	              @"%@", said);
	/* A value node alone is nothing to group by. */
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	NSString *reason = nil;
	NSString *cost = [self node:@"Cost" of:query].identifier;
	XCTAssertNil([queries addValueNamed:@"Odd" to:cost expression:@"total(Amount) for Month" type:nil reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"besides any value nodes"].location != NSNotFound, @"%@", reason);

	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	for (NSArray *each in @[ @[ @"1", @"1", @"2026-01-05T10:00:00", @"10" ], @[ @"2", @"1", @"2026-01-20T10:00:00", @"15" ],
	                         @[ @"3", @"1", @"2026-02-03T10:00:00", @"7" ], @[ @"4", @"2", @"2026-01-10T10:00:00", @"100" ] ]) {
		for (NSArray *fact in @[ @[ @"Cost is of Vehicle", each[1] ], @[ @"Cost was at Moment", each[2] ],
		                         @[ @"Cost cost Amount", each[3] ] ]) {
			NSArray *roles = [[facts objectForKey:fact[0]] visibleRoles];
			XCTAssertNotNil(([editor.populationEditor addFactOf:[[facts objectForKey:fact[0]] identifier]
			                                              named:@{ [roles[0] identifier]: each[0], [roles[1] identifier]: fact[1] }
			                                             reason:&reason]), @"%@", reason);
		}
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:query];
	XCTAssertEqualObjects(plan.notes, @[]);
	XCTAssertEqualObjects(plan.sorts, @[]);
	XCTAssertTrue([[plan text] hasSuffix:@"rows sorted by Total descending"], @"%@", [plan text]);
	XCTAssertEqualObjects([[self archived:plan] text], [plan text]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	ORMQueryResult *result = [interpreter executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	NSArray *expected = @[ @"2 2026-01-01T00:00:00Z 100", @"1 2026-01-01T00:00:00Z 25", @"1 2026-02-01T00:00:00Z 7" ];
	XCTAssertEqualObjects([self datedRows:result.rows sorted:NO], expected, @"%@", [plan text]);
	/* A page at a time, in that order still. */
	ORMQueryCursor *cursor = [interpreter cursorForPlan:plan inContext:context error:&error];
	NSMutableArray *paged = [NSMutableArray array];
	while (![cursor atEnd]) {
		[paged addObjectsFromArray:[cursor nextPage:1 error:&error].rows];
	}
	XCTAssertEqualObjects([self datedRows:paged sorted:NO], expected);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqualObjects([self datedRows:[self rowsOf:odata over:context] sorted:NO], expected, @"%@", [odata requestText]);
}

#pragma mark Computed facts

/* A derivation lists a value node as a role's player: "Trip went
 * Kilometres" derived from where it started and ended; queried through,
 * the value node comes with it. Stored, "Trip covered Kilometres" is made
 * in the population, and worked out at save. */
- (void)testComputedFacts
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Kilometres is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Trip(.id) started at Kilometres\n"
	                 @"Each Trip started at exactly one Kilometres.\n"
	                 @"Trip ended at Kilometres\n"
	                 @"Each Trip ended at exactly one Kilometres.\n"
	                 @"Trip went Kilometres\n"
	                 @"Each Trip went at most one Kilometres.\n"
	                 @"Trip covered Kilometres\n"
	                 @"Each Trip covered at most one Kilometres.\n"
	                 @"\n"
	                 @"Query WentRule:\n"
	                 @"Derivation of \"Trip went Kilometres\":\n"
	                 @"✓Trip\n"
	                 @"  + started at Kilometres1\n"
	                 @"  + ended at Kilometres2\n"
	                 @"  ✓Length = Kilometres2 - Kilometres1\n"
	                 @"\n"
	                 @"Query CoveredRule:\n"
	                 @"Derivation of \"Trip covered Kilometres\":\n"
	                 @"✓Trip\n"
	                 @"  + started at Kilometres1\n"
	                 @"  + ended at Kilometres2\n"
	                 @"  ✓Length = Kilometres2 - Kilometres1\n"
	                 @"\n"
	                 @"Query Long:\n"
	                 @"✓Trip\n"
	                 @"  + went ✓Kilometres > 100\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	ORMQuery *rule = [self query:@"WentRule" in:model];
	XCTAssertEqualObjects([[rule derivedColumns] valueForKey:@"designation"], (@[ @"Trip", @"Length" ]));
	NSArray *said = [[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:rule.derivedFactType.identifier];
	NSString *words = [[said valueForKey:@"text"] componentsJoinedByString:@"\n"];
	XCTAssertTrue([words rangeOfString:@"Length is Kilometres2 minus Kilometres1"].location != NSNotFound, @"%@", words);

	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	NSString *reason = nil;
	for (NSArray *each in @[ @[ @"Trip started at Kilometres", @"1", @"100" ], @[ @"Trip ended at Kilometres", @"1", @"250" ],
	                         @[ @"Trip started at Kilometres", @"2", @"300" ], @[ @"Trip ended at Kilometres", @"2", @"350" ] ]) {
		ORMFactType *fact = [facts objectForKey:each[0]];
		NSArray *roles = [fact visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:fact.identifier
		                                              named:@{ [roles[0] identifier]: each[1], [roles[1] identifier]: each[2] }
		                                             reason:&reason]), @"%@", reason);
	}
	/* Through it: the value node in the query, compared and listed. */
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"Long" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMQueryResult *result = [[[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]]
		executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	XCTAssertEqualObjects([self sorted:result.rows], (@[ @"1 150" ]), @"%@", [plan text]);
	/* No step from a role its rule computes. */
	NSString *from = [[[ORMOutlineReader alloc] initWithEditor:editor]
		addQueryNamed:@"From" outline:@"✓Kilometres\n  + Trip went that Kilometres\n" reason:&reason];
	XCTAssertNotNil(from, @"%@", reason);
	XCTAssertTrue([[[planner planForQuery:[ORMQuery queryWithId:from inModel:model]].notes firstObject]
	                  rangeOfString:@"its rule computes"].location != NSNotFound);

	/* Stored: made in the population; worked out at save. */
	ORMFactType *covered = [facts objectForKey:@"Trip covered Kilometres"];
	XCTAssertTrue([editor.factTypeEditor setDerivationPartial:NO stored:YES of:covered.identifier reason:&reason], @"%@", reason);
	XCTAssertTrue([editor.populationEditor bringStoredDerivationsUpToDate:&reason], @"%@", reason);
	NSMutableArray *made = [NSMutableArray array];
	for (ORMFactInstance *each in [covered instances]) {
		NSMutableArray *players = [NSMutableArray array];
		for (ORMRole *role in [covered visibleRoles]) {
			[players addObject:[[each.instancesByRole objectForKey:role.identifier] displayText]];
		}
		[made addObject:[players componentsJoinedByString:@" "]];
	}
	XCTAssertEqualObjects([made sortedArrayUsingSelector:@selector(compare:)], (@[ @"1 150", @"2 50" ]));
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:model mapping:nil name:@"Trips"];
	ORMTables *tables = [generator tables];
	XCTAssertEqual([tables.derivations count], 1u, @"%@", generator.notes);
	ORMStoredDerivation *derivation = [tables.derivations firstObject];
	XCTAssertEqualObjects(derivation.kind, @"value");
	planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	context = [store newContextWithError:&error];
	ORMSaveHook *hook = [[ORMSaveHook alloc] initWithTables:tables];
	[context performBlockAndWait:^{
		NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Trip"];
		fetch.predicate = [NSPredicate predicateWithFormat:@"id == 1"];
		NSManagedObject *trip = [[context executeFetchRequest:fetch error:NULL] firstObject];
		XCTAssertEqualObjects([[trip valueForKey:derivation.target] description], @"150");
		[trip setValue:[NSDecimalNumber decimalNumberWithString:@"300"] forKey:@"endedAtKilometres"];
		NSMutableSet *changed = [NSMutableSet setWithSet:[context updatedObjects]];
		NSError *failed = nil;
		XCTAssertTrue([hook deriveInContext:context changed:changed error:&failed], @"%@", failed);
		XCTAssertEqualObjects([[trip valueForKey:derivation.target] description], @"200");
	}];
}

/* A computed fact whose player is identified by two values: a service's
 * cost, Money (an amount and a currency), from its items less its
 * discount. Partly derived and stored: a service with no items keeps the
 * cost entered for it. */
- (void)testAComputedFactOfTwoValues
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Amount is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Currency is an entity type.\n"
	                 @"Reference Mode: .code\n"
	                 @"Money has Amount\n"
	                 @"Each Money has exactly one Amount.\n"
	                 @"Money is in Currency\n"
	                 @"Each Money is in exactly one Currency.\n"
	                 @"For each Amount and Currency, at most one Money has that Amount and is in that Currency.\n"
	                 @"This association with Amount and Currency provides the preferred identification scheme for Money.\n"
	                 @"Service(.id) is paid in Currency\n"
	                 @"Each Service is paid in exactly one Currency.\n"
	                 @"Service had a discount of Money\n"
	                 @"Each Service had a discount of at most one Money.\n"
	                 @"Service cost Money\n"
	                 @"++ The sum of its items' costs, less its discount.\n"
	                 @"Each Service cost at most one Money.\n"
	                 @"ServiceItem(.id) is part of Service\n"
	                 @"Each ServiceItem is part of exactly one Service.\n"
	                 @"ServiceItem cost Money\n"
	                 @"Each ServiceItem cost exactly one Money.\n"
	                 @"\n"
	                 @"Query CostRule:\n"
	                 @"Derivation of \"Service cost Money\":\n"
	                 @"✓Service\n"
	                 @"  + is paid in ✓Currency1\n"
	                 @"  + ServiceItem is part of that Service\n"
	                 @"    + cost Money1\n"
	                 @"      + has Amount1\n"
	                 @"      + is in Currency1\n"
	                 @"  + maybe had a discount of Money2\n"
	                 @"    + has Amount2\n"
	                 @"  Items = total(Amount1) for Service\n"
	                 @"  ✓Amount = Items - coalesce(Amount2, 0)\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	ORMQuery *rule = [self query:@"CostRule" in:model];
	NSArray *groups = [rule derivedColumnGroups];
	XCTAssertEqual([groups count], 2u);
	XCTAssertEqualObjects([[groups lastObject] valueForKey:@"designation"], (@[ @"Amount", @"Currency1" ]));
	NSArray *said = [[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:rule.derivedFactType.identifier];
	NSString *words = [[said valueForKey:@"text"] componentsJoinedByString:@"\n"];
	XCTAssertTrue([words rangeOfString:@"that Service cost the Money of Amount and Currency if that Service"].location != NSNotFound,
	              @"%@", words);

	/* Its note gives way to the query's words; partly derived and stored
	 * it stays. */
	ORMFactType *cost = rule.derivedFactType;
	NSString *reason = nil;
	XCTAssertTrue([[cost derivationRule].informalText hasPrefix:@"For each Service, Amount and Currency"],
	              @"%@", [cost derivationRule].informalText);
	XCTAssertTrue([cost derivationRule].isPartial && [cost derivationRule].isStored);
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	for (NSArray *each in @[ @[ @"Service is paid in Currency", @"1", @"EUR" ], @[ @"Service is paid in Currency", @"2", @"EUR" ],
	                         @[ @"ServiceItem is part of Service", @"1", @"1" ], @[ @"ServiceItem cost Money", @"1", @"100, EUR" ],
	                         @[ @"ServiceItem is part of Service", @"2", @"1" ], @[ @"ServiceItem cost Money", @"2", @"50, EUR" ],
	                         @[ @"Service had a discount of Money", @"1", @"20, EUR" ],
	                         @[ @"Service cost Money", @"2", @"70, EUR" ],
	                         @[ @"Service is paid in Currency", @"3", @"EUR" ], @[ @"ServiceItem is part of Service", @"3", @"3" ],
	                         @[ @"ServiceItem cost Money", @"3", @"40, EUR" ] ]) {
		ORMFactType *fact = [facts objectForKey:each[0]];
		NSArray *roles = [fact visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:fact.identifier
		                                              named:@{ [roles[0] identifier]: each[1], [roles[1] identifier]: each[2] }
		                                             reason:&reason]), @"%@: %@", each, reason);
	}
	/* In the population: service 1's from its items; service 2 keeps its own. */
	XCTAssertTrue([editor.populationEditor bringStoredDerivationsUpToDate:&reason], @"%@", reason);
	NSMutableArray *made = [NSMutableArray array];
	for (ORMFactInstance *each in [cost instances]) {
		NSMutableArray *players = [NSMutableArray array];
		for (ORMRole *role in [cost visibleRoles]) {
			[players addObject:[[each.instancesByRole objectForKey:role.identifier] displayText]];
		}
		[made addObject:[players componentsJoinedByString:@" "]];
	}
	XCTAssertEqualObjects([made sortedArrayUsingSelector:@selector(compare:)], (@[ @"1 130, 'EUR'", @"2 70, 'EUR'", @"3 40, 'EUR'" ]));

	/* At save: the cost's parts, where the rule derives one. */
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:model mapping:nil name:@"Services"];
	ORMTables *tables = [ORMTables tablesWithPropertyList:[[generator tables] propertyList] error:NULL];
	XCTAssertEqual([tables.derivations count], 1u, @"%@", generator.notes);
	ORMStoredDerivation *derivation = [tables.derivations firstObject];
	XCTAssertEqualObjects(derivation.kind, @"values");
	XCTAssertEqual([derivation.targets count], 2u);
	XCTAssertTrue(derivation.partial);
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMSaveHook *hook = [[ORMSaveHook alloc] initWithTables:tables];
	NSString *amount = [derivation.targets firstObject];
	[context performBlockAndWait:^{
		NSFetchRequest *items = [NSFetchRequest fetchRequestWithEntityName:@"ServiceItem"];
		items.predicate = [NSPredicate predicateWithFormat:@"id == 1"];
		NSManagedObject *item = [[context executeFetchRequest:items error:NULL] firstObject];
		NSString *itemAmount = nil;
		for (NSString *key in [[item.entity attributesByName] allKeys]) {
			itemAmount = [key hasSuffix:@"Amount"] ? key : itemAmount;
		}
		[item setValue:[NSDecimalNumber decimalNumberWithString:@"200"] forKey:itemAmount];
		NSMutableSet *changed = [NSMutableSet setWithSet:[context updatedObjects]];
		/* The item alone changed: the hook walks back to its service. */
		NSFetchRequest *services = [NSFetchRequest fetchRequestWithEntityName:@"Service"];
		services.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES] ];
		NSError *failed = nil;
		XCTAssertTrue([hook deriveInContext:context changed:changed error:&failed], @"%@", failed);
		NSArray *found = [context executeFetchRequest:services error:NULL];
		XCTAssertEqualObjects([[found valueForKey:amount] valueForKey:@"description"], (@[ @"230", @"70", @"40" ]));
	}];
}

/* The same kept on a supertype: a record's cost, derived for those that
 * are services; the rule reads Service, which has Record's properties. */
- (void)testAComputedFactOfASubtype
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Amount is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Currency is an entity type.\n"
	                 @"Reference Mode: .code\n"
	                 @"Money has Amount\n"
	                 @"Each Money has exactly one Amount.\n"
	                 @"Money is in Currency\n"
	                 @"Each Money is in exactly one Currency.\n"
	                 @"For each Amount and Currency, at most one Money has that Amount and is in that Currency.\n"
	                 @"This association with Amount and Currency provides the preferred identification scheme for Money.\n"
	                 @"Record(.id) cost Money\n"
	                 @"++ A service's: the sum of its items' costs.\n"
	                 @"Each Record cost at most one Money.\n"
	                 @"Each Service is a Record.\n"
	                 @"Each Expense is a Record.\n"
	                 @"Service is paid in Currency\n"
	                 @"Each Service is paid in exactly one Currency.\n"
	                 @"ServiceItem(.id) is part of Service\n"
	                 @"Each ServiceItem is part of exactly one Service.\n"
	                 @"ServiceItem cost Money\n"
	                 @"Each ServiceItem cost exactly one Money.\n"
	                 @"\n"
	                 @"Query ServiceCost:\n"
	                 @"Derivation of \"Record cost Money\":\n"
	                 @"✓Record\n"
	                 @"  + is Service\n"
	                 @"    + is paid in ✓Currency1\n"
	                 @"    + ServiceItem is part of that Service\n"
	                 @"      + cost Money1\n"
	                 @"        + has Amount1\n"
	                 @"        + is in Currency1\n"
	                 @"  ✓Amount = total(Amount1) for Record\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:model mapping:nil name:@"Records"];
	ORMTables *tables = [ORMTables tablesWithPropertyList:[[generator tables] propertyList] error:NULL];
	XCTAssertEqual([tables.derivations count], 1u, @"%@", generator.notes);
	ORMStoredDerivation *derivation = [tables.derivations firstObject];
	XCTAssertEqualObjects(derivation.root, @"Service");
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	NSString *reason = nil;
	XCTAssertNotNil([editor.populationEditor addInstanceOf:[[model objectTypeNamed:@"Service"] identifier] named:@"1" reason:&reason]);
	XCTAssertNotNil([editor.populationEditor addInstanceOf:[[model objectTypeNamed:@"Expense"] identifier] named:@"2" reason:&reason]);
	for (NSArray *each in @[ @[ @"Service is paid in Currency", @"1", @"EUR" ], @[ @"ServiceItem is part of Service", @"1", @"1" ],
	                         @[ @"ServiceItem cost Money", @"1", @"100, EUR" ], @[ @"Record cost Money", @"2", @"9, EUR" ] ]) {
		ORMFactType *fact = [facts objectForKey:each[0]];
		NSArray *roles = [fact visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:fact.identifier
		                                              named:@{ [roles[0] identifier]: each[1], [roles[1] identifier]: each[2] }
		                                             reason:&reason]), @"%@: %@", each, reason);
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMSaveHook *hook = [[ORMSaveHook alloc] initWithTables:tables];
	NSString *amount = [derivation.targets firstObject];
	[context performBlockAndWait:^{
		NSManagedObject *item = [[context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"ServiceItem"] error:NULL]
			firstObject];
		NSString *itemAmount = nil;
		for (NSString *key in [[item.entity attributesByName] allKeys]) {
			itemAmount = [key hasSuffix:@"Amount"] ? key : itemAmount;
		}
		[item setValue:[NSDecimalNumber decimalNumberWithString:@"120"] forKey:itemAmount];
		NSError *failed = nil;
		XCTAssertTrue([hook deriveInContext:context changed:[NSMutableSet setWithSet:[context updatedObjects]] error:&failed],
		              @"%@", failed);
		NSFetchRequest *records = [NSFetchRequest fetchRequestWithEntityName:@"Record"];
		records.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES] ];
		NSArray *found = [context executeFetchRequest:records error:NULL];
		XCTAssertEqualObjects([[found valueForKey:amount] valueForKey:@"description"], (@[ @"120", @"9" ]));
	}];
}

#pragma mark Aggregated by the service

/* A bag of a member's own attribute is aggregated by the service
 * ($apply), a value for each group, the page's groups only; the rows are
 * those the store gives. */
- (void)testTheServiceAggregates
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Amount is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Number is a value type.\n"
	                 @"Portable data type: Numeric: Signed Integer\n"
	                 @"Vehicle(.id) is an entity type.\n"
	                 @"Cost(.id) is of Vehicle\n"
	                 @"Each Cost is of exactly one Vehicle.\n"
	                 @"Cost cost Amount\n"
	                 @"Each Cost cost exactly one Amount.\n"
	                 @"\n"
	                 @"Query Totals:\n"
	                 @"✓Vehicle\n"
	                 @"  + Cost is of that Vehicle\n"
	                 @"    + cost Amount > 5\n"
	                 @"  ✓Total = total(Amount) for Vehicle\n"
	                 @"  ✓Most = max(Amount) for Vehicle\n"
	                 @"  ✓Costs: Number = count(Amount) for Vehicle\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	NSString *reason = nil;
	for (NSArray *each in @[ @[ @"1", @"1", @"10" ], @[ @"2", @"1", @"15" ], @[ @"3", @"1", @"2" ], @[ @"4", @"2", @"100" ],
	                         @[ @"5", @"3", @"7" ] ]) {
		for (NSArray *fact in @[ @[ @"Cost is of Vehicle", each[1] ], @[ @"Cost cost Amount", each[2] ] ]) {
			NSArray *roles = [[facts objectForKey:fact[0]] visibleRoles];
			XCTAssertNotNil(([editor.populationEditor addFactOf:[[facts objectForKey:fact[0]] identifier]
			                                              named:@{ [roles[0] identifier]: each[0], [roles[1] identifier]: fact[1] }
			                                             reason:&reason]), @"%@", reason);
		}
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:@"Totals" in:model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMQueryResult *result = [[[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]]
		executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	NSArray *expected = @[ @"1 25 15 2", @"2 100 100 1", @"3 7 7 1" ];
	XCTAssertEqualObjects([self sorted:result.rows], expected, @"%@", [plan text]);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	NSString *said = [odata requestText];
	XCTAssertTrue([said rangeOfString:@"aggregated by the service for each page's groups"].location != NSNotFound, @"%@", said);
	XCTAssertTrue([said rangeOfString:@"groupby((Vehicle/Id),aggregate(Amount with sum as Value))"].location != NSNotFound, @"%@", said);
	XCTAssertTrue([said rangeOfString:@"aggregate($count as Value)"].location != NSNotFound, @"%@", said);
	XCTAssertEqualObjects([self sorted:[self rowsOf:odata over:context]], expected, @"%@", said);
	/* A page at a time: each page's groups. */
	NSURL *root = [NSURL URLWithString:@"http://example.test/odata/"];
	ORMQueryODataCursor *cursor = [odata cursorWithTransport:[[ODataService alloc] initWithPersistentStoreCoordinator:
		                                                          context.persistentStoreCoordinator serviceRoot:root]
	                                             serviceRoot:root];
	NSMutableArray *paged = [NSMutableArray array];
	for (NSUInteger guard = 0; guard < 10 && ![cursor atEnd]; guard++) {
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		[cursor nextPage:1 completion:^(ORMQueryResult *page, NSError *failed) {
			XCTAssertNotNil(page, @"%@", failed);
			[paged addObjectsFromArray:page.rows ?: @[]];
			dispatch_semaphore_signal(done);
		}];
		XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC))), 0);
	}
	XCTAssertEqualObjects([self sorted:paged], expected);
	/* A service that refuses: the bag's rows read instead, the same rows. */
	ORMTestNoApplyTransport *refusing = [[ORMTestNoApplyTransport alloc] init];
	refusing.service = [[ODataService alloc] initWithPersistentStoreCoordinator:context.persistentStoreCoordinator serviceRoot:root];
	odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	cursor = [odata cursorWithTransport:refusing serviceRoot:root];
	NSMutableArray *read = [NSMutableArray array];
	for (NSUInteger guard = 0; guard < 10 && ![cursor atEnd]; guard++) {
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		[cursor nextPage:10 completion:^(ORMQueryResult *page, NSError *failed) {
			XCTAssertNotNil(page, @"%@", failed);
			[read addObjectsFromArray:page.rows ?: @[]];
			dispatch_semaphore_signal(done);
		}];
		XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC))), 0);
	}
	XCTAssertEqualObjects([self sorted:read], expected);
	XCTAssertGreaterThan(refusing.refused, 0u);
}

/* Rows as text, a moment as UTC ISO 8601 text, in order. */
- (NSArray *)datedRows:(NSArray *)rows
{
	return [self datedRows:rows sorted:YES];
}

- (NSArray *)datedRows:(NSArray *)rows sorted:(BOOL)sorted
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
	NSMutableArray *texts = [NSMutableArray array];
	for (NSArray *row in rows) {
		NSMutableArray *values = [NSMutableArray array];
		for (id value in row) {
			[values addObject:[value isKindOfClass:[NSDate class]] ? [formatter stringFromDate:value] : [value description]];
		}
		[texts addObject:[values componentsJoinedByString:@" "]];
	}
	return sorted ? [texts sortedArrayUsingSelector:@selector(compare:)] : texts;
}

/* Rows as text, each its values by spaces, in order. */
- (NSArray *)sorted:(NSArray *)rows
{
	NSMutableArray *texts = [NSMutableArray array];
	for (NSArray *row in rows) {
		[texts addObject:[row componentsJoinedByString:@" "]];
	}
	return [texts sortedArrayUsingSelector:@selector(compare:)];
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
