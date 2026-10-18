/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <CoreData/CoreData.h>
#import <ODataService/ODataService.h>

/* Reference data (docs/EXPRESSIONS.md, step 5): facts every store of an
 * app starts with, marked in the model, seeded from the tables, and
 * conversion as steps to them and arithmetic. */
@interface ORMReferenceDataTests : ORMTestCase
@end

@implementation ORMReferenceDataTests

- (ORMEditor *)units
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Factor is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Quantity is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"DistanceUnit is an entity type.\n"
	                 @"Reference Mode: .code\n"
	                 @"DistanceUnit is worth Factor km\n"
	                 @"Each DistanceUnit is worth exactly one Factor km.\n"
	                 @"Reference data: km, 1\n"
	                 @"Reference data: mi, 1.609344\n"
	                 @"Reference data: 'nm (sea)', 1.852\n"
	                 @"Distance has Quantity\n"
	                 @"Each Distance has exactly one Quantity.\n"
	                 @"Distance is in DistanceUnit\n"
	                 @"Each Distance is in exactly one DistanceUnit.\n"
	                 @"For each Quantity and DistanceUnit, at most one Distance has that Quantity and is in that DistanceUnit.\n"
	                 @"This association with Quantity and DistanceUnit provides the preferred identification scheme for Distance.\n"
	                 @"Trip(.id) covered Distance\n"
	                 @"Each Trip covered exactly one Distance.\n"
	                 @"\n"
	                 @"Query Kilometres:\n"
	                 @"✓Trip\n"
	                 @"  + covered Distance\n"
	                 @"    + has Quantity\n"
	                 @"    + is in DistanceUnit\n"
	                 @"      + is worth Factor km\n"
	                 @"  ✓Km = Quantity * Factor\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	return editor;
}

- (ORMFactType *)fact:(NSString *)reading in:(ORMModel *)model
{
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		if ([[[fact primaryReading] expandedText] isEqualToString:reading]) {
			return fact;
		}
	}
	return nil;
}

/* Marked as ORMKit's in the file, its facts in the population; read back
 * the same; said; refused for what cannot be; undone. */
- (void)testAFactTypeIsReferenceData
{
	ORMEditor *editor = [self units];
	ORMFactType *worth = [self fact:@"DistanceUnit is worth Factor km" in:editor.model];
	XCTAssertTrue(worth.isReferenceData);
	XCTAssertFalse([self fact:@"Trip covered Distance" in:editor.model].isReferenceData);
	XCTAssertEqual([[worth instances] count], 3u);
	XCTAssertEqualObjects([[[editor.model objectTypeNamed:@"DistanceUnit"] instances] valueForKey:@"displayText"],
	                      (@[ @"'km'", @"'mi'", @"'nm (sea)'" ]));
	NSString *saved = [[NSString alloc] initWithData:[editor dataForSaving] encoding:NSUTF8StringEncoding];
	XCTAssertTrue([saved rangeOfString:@"<ormv:ReferenceData>true</ormv:ReferenceData>"].location != NSNotFound, @"%@", saved);
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:[editor dataForSaving] options:NSXMLNodePreserveAll error:NULL];
	ORMEditor *again = [self newEditorWithDocument:document];
	XCTAssertTrue([self fact:@"DistanceUnit is worth Factor km" in:again.model].isReferenceData);
	NSArray *said = [[[ORMVerbalizer alloc] initWithModel:editor.model] sentencesForElement:worth.identifier];
	XCTAssertTrue([[said valueForKey:@"text"] containsObject:@"Its facts are reference data: every store starts with them."],
	              @"%@", [said valueForKey:@"text"]);
	NSString *reason = nil;
	ORMFactType *subtyping = nil;
	for (ORMFactType *fact in editor.model.factTypes) {
		subtyping = fact.kind != ORMFactTypeOrdinary ? fact : subtyping;
	}
	XCTAssertFalse([editor.factTypeEditor setReferenceData:YES of:subtyping.identifier reason:&reason]);
	XCTAssertTrue([reason length] > 0);
	/* Undone, in the file read again, where it is the one change. */
	ORMFactType *readWorth = [self fact:@"DistanceUnit is worth Factor km" in:again.model];
	XCTAssertTrue([again.factTypeEditor setReferenceData:NO of:readWorth.identifier reason:&reason], @"%@", reason);
	XCTAssertFalse([self fact:@"DistanceUnit is worth Factor km" in:again.model].isReferenceData);
	[self.undoManager undo];
	XCTAssertTrue([self fact:@"DistanceUnit is worth Factor km" in:again.model].isReferenceData);
	/* A line of reference data needs its fact type above it, and a player
	 * for each role. */
	NSArray *failures = nil;
	XCTAssertFalse([[[ORMSentenceEditor alloc] initWithEditor:[self newEditor]] addFromText:@"Reference data: km, 1\n"
	                                                                                failures:&failures]);
	XCTAssertFalse([[[ORMSentenceEditor alloc] initWithEditor:editor]
		addFromText:@"DistanceUnit is worth Factor km\nReference data: km\n" failures:&failures]);
}

/* The tables carry the reference data as seeds, which put it in a store:
 * found by key the next time, and put right where a user changed it. */
- (void)testTheTablesSeedAStore
{
	ORMEditor *editor = [self units];
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:editor.model mapping:nil name:@"Units"];
	ORMTables *tables = [generator tables];
	XCTAssertEqual([tables.seeds count], 3u, @"%@", generator.notes);
	NSDictionary *mi = nil;
	for (NSDictionary *seed in tables.seeds) {
		mi = [[[seed objectForKey:@"values"] objectForKey:@"code"] isEqualToString:@"mi"] ? seed : mi;
	}
	XCTAssertEqualObjects([mi objectForKey:@"entity"], @"DistanceUnit");
	XCTAssertEqualObjects([mi objectForKey:@"key"], @[ @"code" ]);
	XCTAssertEqual([[[mi objectForKey:@"values"] allKeys] count], 2u);
	/* Through a property list and back, as an app reads them. */
	ORMTables *read = [ORMTables tablesWithPropertyList:[tables propertyList] error:NULL];
	XCTAssertEqualObjects(read.seeds, tables.seeds);
	XCTAssertTrue([[generator files][@"UnitsValidation.h"] rangeOfString:@"@interface UnitsReferenceData"].location != NSNotFound);

	NSManagedObjectModel *model = [[[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map] managedObjectModel];
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	NSError *error = nil;
	XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:&error],
	                @"%@", error);
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	context.persistentStoreCoordinator = coordinator;
	[context performBlockAndWait:^{
		NSError *failed = nil;
		XCTAssertTrue([read seedContext:context error:&failed], @"%@", failed);
		XCTAssertTrue([context save:&failed], @"%@", failed);
		NSFetchRequest *units = [NSFetchRequest fetchRequestWithEntityName:@"DistanceUnit"];
		units.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"code" ascending:YES] ];
		NSArray *found = [context executeFetchRequest:units error:NULL];
		XCTAssertEqualObjects([found valueForKey:@"code"], (@[ @"km", @"mi", @"nm (sea)" ]));
		XCTAssertEqualObjects([[found objectAtIndex:1] valueForKey:@"factor"], [NSDecimalNumber decimalNumberWithString:@"1.609344"]);
		/* A user's change put right; nothing made twice. */
		[[found objectAtIndex:1] setValue:[NSDecimalNumber decimalNumberWithString:@"2"] forKey:@"factor"];
		XCTAssertTrue([read seedContext:context error:&failed], @"%@", failed);
		found = [context executeFetchRequest:units error:NULL];
		XCTAssertEqual([found count], 3u);
		XCTAssertEqualObjects([[found objectAtIndex:1] valueForKey:@"factor"], [NSDecimalNumber decimalNumberWithString:@"1.609344"]);
	}];
}

/* Conversion is a step to the factor and a product: each trip in
 * kilometres, whatever unit it was entered in. */
- (void)testConversionIsAStepAndArithmetic
{
	ORMEditor *editor = [self units];
	ORMModel *model = editor.model;
	ORMFactType *covered = [self fact:@"Trip covered Distance" in:model];
	NSString *reason = nil;
	for (NSArray *each in @[ @[ @"1", @"10, km" ], @[ @"2", @"10, mi" ] ]) {
		NSArray *roles = [covered visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:covered.identifier
		                                              named:@{ [roles[0] identifier]: each[0], [roles[1] identifier]: each[1] }
		                                             reason:&reason]), @"%@", reason);
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQuery *query = nil;
	for (ORMQuery *each in [ORMQuery queriesInModel:model]) {
		query = [each.name isEqualToString:@"Kilometres"] ? each : query;
	}
	ORMQueryPlan *plan = [planner planForQuery:query];
	XCTAssertEqualObjects(plan.notes, @[]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMQueryResult *result = [[[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]]
		executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	NSMutableArray *rows = [NSMutableArray array];
	for (NSArray *row in result.rows) {
		[rows addObject:[row componentsJoinedByString:@" "]];
	}
	XCTAssertEqualObjects([rows sortedArrayUsingSelector:@selector(compare:)], (@[ @"1 10", @"2 16.09344" ]), @"%@", [plan text]);
}

/* A comparison across units: another trip of the vehicle that went
 * fewer kilometres, its value compared with one the root computes, which
 * is planned as soon as what it uses is reached. */
- (void)testAComparisonAcrossUnits
{
	ORMEditor *editor = [self units];
	NSString *text = @"Vehicle(.id) is an entity type.\n"
	                 @"Trip is of Vehicle\n"
	                 @"Each Trip is of exactly one Vehicle.\n"
	                 @"\n"
	                 @"Query Longer:\n"
	                 @"✓Trip1\n"
	                 @"  + covered Distance1\n"
	                 @"    + has Quantity1\n"
	                 @"    + is in DistanceUnit1\n"
	                 @"      + is worth Factor1 km\n"
	                 @"  + is of Vehicle\n"
	                 @"    + Trip2 is of that Vehicle\n"
	                 @"      + covered Distance2\n"
	                 @"        + has Quantity2\n"
	                 @"        + is in DistanceUnit2\n"
	                 @"          + is worth Factor2 km\n"
	                 @"      Km2 = Quantity2 * Factor2 < Km1\n"
	                 @"  Km1 = Quantity1 * Factor1\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	NSString *reason = nil;
	for (NSArray *each in @[ @[ @"Trip covered Distance", @"1", @"10, km" ], @[ @"Trip covered Distance", @"2", @"10, mi" ],
	                         @[ @"Trip is of Vehicle", @"1", @"7" ], @[ @"Trip is of Vehicle", @"2", @"7" ] ]) {
		ORMFactType *fact = [self fact:each[0] in:model];
		NSArray *roles = [fact visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:fact.identifier
		                                              named:@{ [roles[0] identifier]: each[1], [roles[1] identifier]: each[2] }
		                                             reason:&reason]), @"%@", reason);
	}
	ORMQuery *query = nil;
	for (ORMQuery *each in [ORMQuery queriesInModel:model]) {
		query = [each.name isEqualToString:@"Longer"] ? each : query;
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:query];
	XCTAssertEqualObjects(plan.notes, @[]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	ORMQueryResult *result = [[[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]]
		executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	/* Trip 2 went 16 km; trip 1, 10, fewer. */
	XCTAssertEqualObjects(result.rows, (@[ @[ @2 ] ]), @"%@", [plan text]);
}

/* Money in the owner's currency: each cost at the latest rate on or
 * before its day ("the one before" over rates users enter), one already
 * in that currency as it is; then totalled by month. */
- (void)testCurrencyConversion
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Amount is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Factor is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"Date is a value type.\n"
	                 @"Portable data type: Temporal: Date\n"
	                 @"Moment is a value type.\n"
	                 @"Portable data type: Temporal: Date & Time\n"
	                 @"Currency is an entity type.\n"
	                 @"Reference Mode: .code\n"
	                 @"User(.id) prefers Currency\n"
	                 @"Each User prefers at most one Currency.\n"
	                 @"Vehicle(.id) is owned by User\n"
	                 @"Each Vehicle is owned by exactly one User.\n"
	                 @"Money has Amount\n"
	                 @"Each Money has exactly one Amount.\n"
	                 @"Money is in Currency\n"
	                 @"Each Money is in exactly one Currency.\n"
	                 @"For each Amount and Currency, at most one Money has that Amount and is in that Currency.\n"
	                 @"This association with Amount and Currency provides the preferred identification scheme for Money.\n"
	                 @"Cost(.id) is of Vehicle\n"
	                 @"Each Cost is of exactly one Vehicle.\n"
	                 @"Cost cost Money\n"
	                 @"Each Cost cost exactly one Money.\n"
	                 @"Cost was at Moment\n"
	                 @"Each Cost was at exactly one Moment.\n"
	                 @"Currency (as BaseCurrency) was worth Factor in Currency (as QuoteCurrency) on Date\n"
	                 @"For each Currency1, Currency2 and Date, that Currency1 was worth at most one Factor in that Currency2 on that Date.\n"
	                 @"\n"
	                 @"Query ByMonth:\n"
	                 @"✓Vehicle\n"
	                 @"  + is owned by User\n"
	                 @"    + prefers ✓Currency2\n"
	                 @"  + Cost is of that Vehicle\n"
	                 @"    + was at Moment\n"
	                 @"    + cost Money\n"
	                 @"      + has Amount\n"
	                 @"      + is in Currency1\n"
	                 @"        + maybe was worth Factor1 in Currency2 on Date1 <= Day\n"
	                 @"        + maybe was worth Factor2 in Currency2 on Date2 = RateDay\n"
	                 @"    Day: Date = date(Moment)\n"
	                 @"    RateDay = max(Date1) for Cost\n"
	                 @"    Rate = max(Factor2) for Cost\n"
	                 @"    ✓Month = month(Moment) ↓\n"
	                 @"    Converted = Amount * coalesce(Rate, 1)\n"
	                 @"    ✓Total = total(Converted) for Vehicle, Month\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMModel *model = editor.model;
	NSString *reason = nil;
	ORMFactType *rate = nil;
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		rate = [[fact visibleRoles] count] == 4 ? fact : rate;
	}
	for (NSArray *each in @[ @[ @"User prefers Currency", @"1", @"EUR" ], @[ @"Vehicle is owned by User", @"1", @"1" ],
	                         @[ @"Cost is of Vehicle", @"1", @"1" ], @[ @"Cost cost Money", @"1", @"10, USD" ],
	                         @[ @"Cost was at Moment", @"1", @"2026-01-15T10:00:00" ],
	                         @[ @"Cost is of Vehicle", @"2", @"1" ], @[ @"Cost cost Money", @"2", @"20, EUR" ],
	                         @[ @"Cost was at Moment", @"2", @"2026-01-20T10:00:00" ],
	                         @[ @"Cost is of Vehicle", @"3", @"1" ], @[ @"Cost cost Money", @"3", @"10, USD" ],
	                         @[ @"Cost was at Moment", @"3", @"2026-02-10T10:00:00" ] ]) {
		ORMFactType *fact = [self fact:each[0] in:model];
		NSArray *roles = [fact visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:fact.identifier
		                                              named:@{ [roles[0] identifier]: each[1], [roles[1] identifier]: each[2] }
		                                             reason:&reason]), @"%@: %@", each, reason);
	}
	/* USD in EUR: 0.9 from January, 0.8 from February. */
	NSArray *roles = [(ORMReadingOrder *)[rate.readingOrders firstObject] roles];
	for (NSArray *each in @[ @[ @"USD", @"0.9", @"EUR", @"2026-01-01" ], @[ @"USD", @"0.8", @"EUR", @"2026-02-01" ] ]) {
		NSMutableDictionary *named = [NSMutableDictionary dictionary];
		for (NSUInteger i = 0; i < 4; i++) {
			[named setObject:each[i] forKey:[roles[i] identifier]];
		}
		XCTAssertNotNil([editor.populationEditor addFactOf:rate.identifier named:named reason:&reason], @"%@", reason);
	}
	ORMQuery *query = nil;
	for (ORMQuery *each in [ORMQuery queriesInModel:model]) {
		query = [each.name isEqualToString:@"ByMonth"] ? each : query;
	}
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:query];
	XCTAssertEqualObjects(plan.notes, @[]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMQueryResult *result = [[[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]]
		executePlan:plan inContext:context error:&error];
	XCTAssertNotNil(result, @"%@", error);
	/* The same from the service. */
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	NSURL *root = [NSURL URLWithString:@"http://example.test/odata/"];
	ORMQueryODataCursor *cursor = [odata cursorWithTransport:[[ODataService alloc] initWithPersistentStoreCoordinator:
		                                                          context.persistentStoreCoordinator serviceRoot:root]
	                                             serviceRoot:root];
	NSMutableArray *served = [NSMutableArray array];
	for (NSUInteger guard = 0; guard < 10 && ![cursor atEnd]; guard++) {
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		[cursor nextPage:10 completion:^(ORMQueryResult *page, NSError *failed) {
			XCTAssertNotNil(page, @"%@", failed);
			[served addObjectsFromArray:page.rows ?: @[]];
			dispatch_semaphore_signal(done);
		}];
		XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC))), 0);
	}
	NSMutableArray *servedRows = [NSMutableArray array];
	for (NSArray *row in served) {
		[servedRows addObject:[NSString stringWithFormat:@"%@ %@ %@ %@", row[0], row[1], [row[2] description].length >= 7
			                                                                               ? [[row[2] description] substringToIndex:7] : row[2],
			                                             row[3]]];
	}
	XCTAssertEqualObjects(servedRows, (@[ @"1 EUR 2026-02 8", @"1 EUR 2026-01 29" ]), @"%@", [odata requestText]);
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
	formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
	formatter.dateFormat = @"yyyy-MM";
	NSMutableArray *rows = [NSMutableArray array];
	for (NSArray *row in result.rows) {
		NSMutableArray *values = [NSMutableArray array];
		for (id value in row) {
			[values addObject:[value isKindOfClass:[NSDate class]] ? [formatter stringFromDate:value] : [value description]];
		}
		[rows addObject:[values componentsJoinedByString:@" "]];
	}
	/* January: 10 USD at 0.9 and 20 EUR; February: 10 USD at 0.8. */
	XCTAssertEqualObjects(rows, (@[ @"1 EUR 2026-02 8", @"1 EUR 2026-01 29" ]), @"%@", [plan text]);

	/* A currency absorbed as its code, as an app's mapping may have it:
	 * from it to its rates, a join on the code. */
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:editor];
	NSString *mappingId = [mappings addCoreDataMappingNamed:@"Codes" path:@"Codes.xcdatamodeld"];
	[mappings setAbsorbsIdentifierTypes:YES ofMapping:mappingId];
	ORMCoreDataMapping *mapping = [model elementWithId:mappingId];
	planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:mapping];
	XCTAssertNil([planner.coreData entityNamed:@"Currency"]);
	plan = [planner planForQuery:query];
	XCTAssertEqualObjects(plan.notes, @[]);
	store = [[ORMPopulationStore alloc] initWithModel:model coreData:planner.coreData];
	context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	result = [[[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]] executePlan:plan inContext:context
	                                                                                                   error:&error];
	XCTAssertNotNil(result, @"%@", error);
	rows = [NSMutableArray array];
	for (NSArray *row in result.rows) {
		NSMutableArray *values = [NSMutableArray array];
		for (id value in row) {
			[values addObject:[value isKindOfClass:[NSDate class]] ? [formatter stringFromDate:value] : [value description]];
		}
		[rows addObject:[values componentsJoinedByString:@" "]];
	}
	XCTAssertEqualObjects(rows, (@[ @"1 EUR 2026-02 8", @"1 EUR 2026-01 29" ]), @"%@", [plan text]);
}

@end
