/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <CoreData/CoreData.h>

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

@end
