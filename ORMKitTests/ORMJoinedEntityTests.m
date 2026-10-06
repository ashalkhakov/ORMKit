/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <CoreData/CoreData.h>
#import <ODataKit/ODataTransport.h>
#import <ODataService/ODataService.h>

/* An entity type kept in several entities (docs/JOINED-ENTITIES.md): a
 * Customer, identified by its user id and also by a GUID, whose name is the
 * CRM's (the hub), whose balance is billing's (by user id, not every
 * customer has an account), and whose e-mail and topics are the
 * newsletter's (by GUID, through the CRM, which keeps both). */
@interface ORMJoinedEntityTests : ORMTestCase
@end

@implementation ORMJoinedEntityTests
{
	ORMEditor *_editor;
	NSString *_diagram;
	NSMutableDictionary<NSString *, NSArray<NSString *> *> *_facts;
	NSString *_mapping;
	NSDictionary<NSString *, NSString *> *_members;
}

- (void)setUp
{
	[super setUp];
	_editor = [self newEditor];
	_diagram = [[_editor.model.diagrams firstObject] identifier];
	_facts = [NSMutableDictionary dictionary];
}

/* A fact type; "1" makes the first role unique, "11" both, "*" spans them;
 * "!" makes the first role mandatory. */
- (NSArray<NSString *> *)fact:(NSString *)name
                      players:(NSArray *)players
                      reading:(NSString *)reading
                   uniqueness:(NSString *)uniqueness
{
	NSString *reason = nil;
	NSString *fact = [_editor.factTypeEditor addFactTypeWithPlayers:players reading:reading onDiagram:_diagram
	                                                             at:ORMAutomaticPlacement reason:&reason];
	XCTAssertNotNil(fact, @"%@: %@", reading, reason);
	NSArray *roles = [[[_editor.model elementWithId:fact] roles] valueForKey:@"identifier"];
	if ([uniqueness hasPrefix:@"1"]) {
		[_editor.constraintEditor setUnique:YES role:[roles firstObject] reason:NULL];
	}
	if ([uniqueness hasPrefix:@"11"]) {
		[_editor.constraintEditor setUnique:YES role:[roles lastObject] reason:NULL];
	}
	if ([uniqueness hasPrefix:@"*"]) {
		[_editor.constraintEditor addUniquenessConstraintOverRoles:roles reason:NULL];
	}
	if ([uniqueness hasSuffix:@"!"]) {
		[_editor.constraintEditor setMandatory:YES role:[roles firstObject] reason:NULL];
	}
	[_facts setObject:roles forKey:name];
	return roles;
}

- (NSString *)far:(NSString *)fact
{
	return [[_facts objectForKey:fact] lastObject];
}

/* The single-role uniqueness constraint on the role. */
- (NSString *)uniquenessOn:(NSString *)roleId
{
	for (ORMConstraint *constraint in [(ORMRole *)[_editor.model elementWithId:roleId] constraints]) {
		if (constraint.kind == ORMUniquenessConstraint && [[constraint allRoles] count] == 1) {
			return constraint.identifier;
		}
	}
	return nil;
}

/* The customers' model, and a mapping joining them. */
- (void)makeCustomers
{
	ORMObjectTypeEditor *types = _editor.objectTypeEditor;
	NSString *customer = [types addEntityTypeNamed:@"Customer" referenceMode:@"UserId" kind:ORMReferenceModeGeneral
	                                     onDiagram:_diagram at:ORMAutomaticPlacement reason:NULL];
	ORMObjectType *userId = [[_editor.model elementWithId:customer] referenceModeValueType];
	[types setDataType:@"SignedIntegerNumericDataType" length:0 scale:0 of:userId.identifier reason:NULL];
	NSString *topic = [types addEntityTypeNamed:@"Topic" referenceMode:@"code" kind:ORMReferenceModePopular
	                                  onDiagram:_diagram at:ORMAutomaticPlacement reason:NULL];
	NSString *guid = [types addValueTypeNamed:@"Guid" dataType:@"VariableLengthTextDataType" onDiagram:_diagram
	                                       at:ORMAutomaticPlacement reason:NULL];
	NSString *name = [types addValueTypeNamed:@"Name" dataType:@"VariableLengthTextDataType" onDiagram:_diagram
	                                       at:ORMAutomaticPlacement reason:NULL];
	NSString *balance = [types addValueTypeNamed:@"Balance" dataType:@"SignedIntegerNumericDataType" onDiagram:_diagram
	                                          at:ORMAutomaticPlacement reason:NULL];
	NSString *email = [types addValueTypeNamed:@"Email" dataType:@"VariableLengthTextDataType" onDiagram:_diagram
	                                        at:ORMAutomaticPlacement reason:NULL];
	[self fact:@"guid" players:@[ customer, guid ] reading:@"{0} has {1}" uniqueness:@"11!"];
	[self fact:@"name" players:@[ customer, name ] reading:@"{0} is called {1}" uniqueness:@"1!"];
	[self fact:@"balance" players:@[ customer, balance ] reading:@"{0} owes {1}" uniqueness:@"1"];
	[self fact:@"email" players:@[ customer, email ] reading:@"{0} is mailed at {1}" uniqueness:@"1"];
	[self fact:@"topics" players:@[ customer, topic ] reading:@"{0} subscribes to {1}" uniqueness:@"*"];

	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:_editor];
	_mapping = [mappings addCoreDataMappingNamed:@"Customers" path:@"Customers.xcdatamodeld"];
	NSString *hub = [mappings addMemberNamed:@"CRMCustomer" by:nil via:nil outer:NO ofObjectType:customer
	                               inMapping:_mapping];
	NSString *billing = [mappings addMemberNamed:@"BillingAccount" by:nil via:nil outer:YES ofObjectType:customer
	                                   inMapping:_mapping];
	[mappings setHeld:YES role:[self far:@"balance"] byMember:billing inMapping:_mapping];
	NSString *subscriber = [mappings addMemberNamed:@"Subscriber" by:[self uniquenessOn:[self far:@"guid"]] via:hub
	                                          outer:YES ofObjectType:customer inMapping:_mapping];
	[mappings setHeld:YES role:[self far:@"email"] byMember:subscriber inMapping:_mapping];
	[mappings setHeld:YES role:[self far:@"topics"] byMember:subscriber inMapping:_mapping];
	_members = @{ @"hub": hub, @"billing": billing, @"subscriber": subscriber };
}

- (ORMCoreDataMapping *)mapping
{
	for (ORMCoreDataMapping *mapping in [ORMCoreDataMapping mappingsOfDocument:_editor.document]) {
		if ([mapping.identifier isEqualToString:_mapping]) {
			return mapping;
		}
	}
	return nil;
}

/* The members as the mapping reads them back: in order, the hub first,
 * each with what it correlates by, joins to and holds. */
- (void)testTheMappingKeepsTheMembers
{
	[self makeCustomers];
	ORMObjectType *customer = [_editor.model objectTypeNamed:@"Customer"];
	ORMCoreDataMapping *mapping = [self mapping];
	XCTAssertEqual([mapping mappingOfObjectType:customer.identifier], ORMMapJoined);
	NSArray<ORMJoinMember *> *members = [mapping.joins objectForKey:customer.identifier];
	XCTAssertEqualObjects([members valueForKey:@"name"], (@[ @"CRMCustomer", @"BillingAccount", @"Subscriber" ]));
	XCTAssertNil(members[0].viaId);
	XCTAssertFalse(members[0].isOuter);
	XCTAssertEqualObjects(members[1].viaId, members[0].identifier, @"the hub, where it says none");
	XCTAssertTrue(members[1].isOuter);
	XCTAssertNil(members[1].correlationId, @"the preferred identifier");
	XCTAssertEqualObjects(members[2].correlationId, [self uniquenessOn:[self far:@"guid"]]);
	XCTAssertEqualObjects(members[2].heldRoleIds, (@[ [self far:@"email"], [self far:@"topics"] ]));

	/* A role is held by one member: holding it elsewhere moves it. */
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:_editor];
	[mappings setHeld:YES role:[self far:@"email"] byMember:[_members objectForKey:@"billing"] inMapping:_mapping];
	members = [[self mapping].joins objectForKey:customer.identifier];
	XCTAssertEqualObjects(members[1].heldRoleIds, (@[ [self far:@"balance"], [self far:@"email"] ]));
	XCTAssertEqualObjects(members[2].heldRoleIds, @[ [self far:@"topics"] ]);
	[self.undoManager undo];
	members = [[self mapping].joins objectForKey:customer.identifier];
	XCTAssertEqualObjects(members[2].heldRoleIds, (@[ [self far:@"email"], [self far:@"topics"] ]));
}

/* Each member an entity: the hub the type's, with what no member holds;
 * the others with their correlating values and what they hold, and what
 * joins them in their userInfo. Topic's customers are the subscribers. */
- (void)testEachMemberIsAnEntity
{
	[self makeCustomers];
	ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMCDModel *model = [mapper map];
	for (ORMMappingNote *note in mapper.notes) {
		XCTAssertNotEqual(note.kind, ORMMappingWarning, @"%@", note.text);
	}
	ORMCDEntity *hub = [model entityNamed:@"CRMCustomer"];
	ORMCDEntity *billing = [model entityNamed:@"BillingAccount"];
	ORMCDEntity *subscriber = [model entityNamed:@"Subscriber"];
	XCTAssertNil([model entityNamed:@"Customer"]);
	NSArray *(^names)(ORMCDEntity *) = ^NSArray *(ORMCDEntity *entity) {
		return [[[entity properties] valueForKey:@"name"] sortedArrayUsingSelector:@selector(compare:)];
	};
	XCTAssertEqualObjects(names(hub), (@[ @"guid", @"name", @"userId" ]));
	XCTAssertEqualObjects(names(billing), (@[ @"balance", @"userId" ]));
	XCTAssertEqualObjects(names(subscriber), (@[ @"email", @"guid", @"topics" ]));
	XCTAssertEqualObjects([[model entityNamed:@"Topic"] relationshipNamed:@"customers"].destination, @"Subscriber");

	XCTAssertEqualObjects(hub.source, [[_editor.model objectTypeNamed:@"Customer"] identifier]);
	XCTAssertEqualObjects(billing.source, [_members objectForKey:@"billing"]);
	XCTAssertEqualObjects([billing attributeNamed:@"userId"].source,
	                      ([NSString stringWithFormat:@"%@/%@", [_members objectForKey:@"billing"],
	                                                  [[_editor.model objectTypeNamed:@"Customer"] preferredIdentifier]
	                                                      .allRoles.firstObject.identifier]));
	XCTAssertEqualObjects([billing.userInfo objectForKey:@"ormkit.via"], @"CRMCustomer");
	XCTAssertEqualObjects([billing.userInfo objectForKey:@"ormkit.on"], @"userId userId");
	XCTAssertEqualObjects([billing.userInfo objectForKey:@"ormkit.outer"], @"YES");
	XCTAssertEqualObjects([subscriber.userInfo objectForKey:@"ormkit.on"], @"guid guid");
	XCTAssertEqualObjects(billing.uniquenessConstraints, @[ @[ @"userId" ] ]);
	XCTAssertTrue([[hub attributeNamed:@"name"] optional] == NO);
	XCTAssertNil([self momcRejects:model]);
}

/* What a join cannot be is said, and the type is mapped as it can be. */
- (void)testAJoinThatCannotBeIsNoted
{
	[self makeCustomers];
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:_editor];
	ORMObjectType *customer = [_editor.model objectTypeNamed:@"Customer"];
	/* By a role that identifies nothing. */
	NSString *odd = [mappings addMemberNamed:@"Odd" by:[self far:@"name"] via:nil outer:YES
	                             ofObjectType:customer.identifier inMapping:_mapping];
	XCTAssertNotNil(odd);
	ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:_editor.model mapping:[self mapping]];
	[mapper map];
	NSArray *texts = [mapper.notes valueForKey:@"text"];
	XCTAssertTrue([texts containsObject:@"Odd is not joined to Customer: what it correlates by is no identifier of it."],
	              @"%@", texts);
	[mappings removeMember:odd inMapping:_mapping];

	/* A mandatory role held by an outer member: a row for each. */
	[mappings setHeld:YES role:[self far:@"name"] byMember:[_members objectForKey:@"billing"] inMapping:_mapping];
	mapper = [[ORMCoreDataMapper alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMCDModel *model = [mapper map];
	XCTAssertEqualObjects([[model entityNamed:@"BillingAccount"].userInfo objectForKey:@"ormkit.outer"], @"NO");
	XCTAssertTrue([[mapper.notes valueForKey:@"text"]
		containsObject:@"BillingAccount has a row for each Customer: it holds a mandatory role of it, so it is joined as "
	                   @"inner."]);
}

#pragma mark Queries

/* The node a new step from the node reaches. */
- (NSString *)step:(ORMQueryEditor *)queries from:(NSString *)nodeId through:(NSString *)roleId in:(NSString *)queryId
{
	NSString *reason = nil;
	NSString *step = [queries addStepTo:nodeId through:roleId reason:&reason];
	XCTAssertNotNil(step, @"%@", reason);
	for (ORMQueryNode *node in [[ORMQuery queryWithId:queryId inModel:_editor.model] nodes]) {
		if ([node.step.identifier isEqualToString:step]) {
			return node.identifier;
		}
	}
	return nil;
}

- (NSString *)stepOf:(NSString *)nodeId in:(NSString *)queryId
{
	for (ORMQueryNode *node in [[ORMQuery queryWithId:queryId inModel:_editor.model] nodes]) {
		if ([node.identifier isEqualToString:nodeId]) {
			return node.step.identifier;
		}
	}
	return nil;
}

/* The customers in their three stores: Ann (1) owes 50 and reads the news,
 * Bob (2) has no account and does not subscribe, Cy (3) owes 500 and reads
 * the news and the deals. */
- (NSManagedObjectContext *)storeIn:(NSString *)directory model:(NSManagedObjectModel *)model
{
	NSError *error = nil;
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	XCTAssertNotNil([coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
	                                                    URL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"Customers.sqlite"]]
	                                                options:nil error:&error], @"%@", error);
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	context.persistentStoreCoordinator = coordinator;
	[context performBlockAndWait:^{
		NSManagedObject *(^make)(NSString *, NSDictionary *) = ^NSManagedObject *(NSString *entity, NSDictionary *values) {
			NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:context];
			[object setValuesForKeysWithDictionary:values];
			return object;
		};
		NSManagedObject *news = make(@"Topic", @{ @"code": @"news" });
		NSManagedObject *deals = make(@"Topic", @{ @"code": @"deals" });
		make(@"CRMCustomer", @{ @"userId": @1, @"name": @"Ann", @"guid": @"g1" });
		make(@"CRMCustomer", @{ @"userId": @2, @"name": @"Bob", @"guid": @"g2" });
		make(@"CRMCustomer", @{ @"userId": @3, @"name": @"Cy", @"guid": @"g3" });
		make(@"BillingAccount", @{ @"userId": @1, @"balance": @50 });
		make(@"BillingAccount", @{ @"userId": @3, @"balance": @500 });
		make(@"Subscriber", @{ @"guid": @"g1", @"email": @"ann@example.test", @"topics": [NSSet setWithObject:news] });
		make(@"Subscriber", @{ @"guid": @"g3", @"email": @"cy@example.test",
		                       @"topics": [NSSet setWithObjects:news, deals, nil] });
		NSError *saved = nil;
		XCTAssertTrue([context save:&saved], @"%@", saved);
	}];
	return context;
}

/* A query of customers reads the hub, and goes to each other member by
 * what correlates it: the billing account by user id, the subscriber by
 * GUID through the hub, which has both. A step there is some row; maybe,
 * the row or none; not, no row. */
- (void)testQueriesJoinTheMembers
{
	[self makeCustomers];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self storeIn:directory model:[planner.coreData managedObjectModel]];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:_editor];
	NSString *customer = [[_editor.model objectTypeNamed:@"Customer"] identifier];
	NSSet *(^rows)(NSString *) = ^NSSet *(NSString *queryId) {
		ORMQueryPlan *plan = [planner planForQuery:[ORMQuery queryWithId:queryId inModel:_editor.model]];
		XCTAssertEqualObjects(plan.notes, @[], @"%@", [plan text]);
		__block ORMQueryResult *result = nil;
		__block NSError *error = nil;
		[context performBlockAndWait:^{
			result = [interpreter executePlan:plan inContext:context error:&error];
		}];
		XCTAssertNotNil(result, @"%@\n%@", error, [plan text]);
		/* The same, from the service the model is served by. */
		ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
		XCTAssertNotNil(odata, @"%@", error);
		XCTAssertEqualObjects(odata.notes, @[], @"%@", [odata requestText]);
		ODataService *service = [[ODataService alloc] initWithPersistentStoreCoordinator:context.persistentStoreCoordinator
		                                                                     serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
		ORMQueryODataCursor *cursor = [odata cursorWithTransport:(id<ODataTransport>)service
		                                             serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
		NSMutableArray *served = [NSMutableArray array];
		for (NSUInteger guard = 0; cursor != nil && guard < 10 && ![cursor atEnd]; guard++) {
			dispatch_semaphore_t done = dispatch_semaphore_create(0);
			[cursor nextPage:2 completion:^(ORMQueryResult *page, NSError *failed) {
				XCTAssertNotNil(page, @"%@\n%@", failed, [odata requestText]);
				[served addObjectsFromArray:page.rows ?: @[]];
				dispatch_semaphore_signal(done);
			}];
			XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC))), 0);
		}
		XCTAssertEqualObjects([NSSet setWithArray:served], [NSSet setWithArray:result.rows ?: @[]], @"%@\n%@", [plan text],
		                      [odata requestText]);
		return [NSSet setWithArray:result.rows ?: @[]];
	};

	NSString *plain = [queries addQueryNamed:@"All" from:customer reason:NULL];
	XCTAssertEqual([rows(plain) count], 3u);
	/* What they owe: those with an account. */
	NSString *q = [queries addQueryNamed:@"Owing" from:customer reason:NULL];
	NSString *root = [ORMQuery queryWithId:q inModel:_editor.model].root.identifier;
	NSString *owes = [self step:queries from:root through:[[_facts objectForKey:@"balance"] firstObject] in:q];
	[queries setProjected:YES ofNode:owes];
	XCTAssertEqualObjects(rows(q), ([NSSet setWithObjects:@[ @1, @50 ], @[ @3, @500 ], nil]));
	ORMQueryPlan *plan = [planner planForQuery:[ORMQuery queryWithId:q inModel:_editor.model]];
	XCTAssertTrue([[plan text] containsString:@"some x1 in member1 with userId = userId has x1.balance is set"],
	              @"%@", [plan text]);
	NSError *read = nil;
	ORMQueryPlan *again = [ORMQueryPlan planWithPropertyList:[plan propertyList] error:&read];
	XCTAssertEqualObjects([again text], [plan text], @"%@", read);
	/* Maybe: everyone, with what they owe if they have an account. */
	[queries setOperator:ORMQueryMaybe ofStep:[self stepOf:owes in:q]];
	XCTAssertEqualObjects(rows(q), ([NSSet setWithObjects:@[ @1, @50 ], @[ @2, [NSNull null] ], @[ @3, @500 ], nil]));
	/* Not: those without. */
	[queries setOperator:ORMQueryNot ofStep:[self stepOf:owes in:q]];
	XCTAssertEqualObjects(rows(q), [NSSet setWithObject:@[ @2 ]]);
	/* Some, more than 100: Cy, by name. */
	[queries setOperator:ORMQueryAnd ofStep:[self stepOf:owes in:q]];
	[queries setProjected:NO ofNode:owes];
	XCTAssertTrue([queries setCondition:@">" value:@"100" ofNode:owes reason:NULL]);
	NSString *named = [self step:queries from:root through:[[_facts objectForKey:@"name"] firstObject] in:q];
	[queries setProjected:YES ofNode:named];
	XCTAssertEqualObjects(rows(q), ([NSSet setWithObject:@[ @3, @"Cy" ]]));

	/* Through the hub's GUID to the subscriber: e-mails, and topics. */
	NSString *m = [queries addQueryNamed:@"Mailing" from:customer reason:NULL];
	root = [ORMQuery queryWithId:m inModel:_editor.model].root.identifier;
	NSString *email = [self step:queries from:root through:[[_facts objectForKey:@"email"] firstObject] in:m];
	[queries setProjected:YES ofNode:email];
	XCTAssertEqualObjects(rows(m), ([NSSet setWithObjects:@[ @1, @"ann@example.test" ], @[ @3, @"cy@example.test" ], nil]));
	NSString *t = [queries addQueryNamed:@"Deals" from:customer reason:NULL];
	root = [ORMQuery queryWithId:t inModel:_editor.model].root.identifier;
	NSString *topic = [self step:queries from:root through:[[_facts objectForKey:@"topics"] firstObject] in:t];
	XCTAssertTrue([queries setCondition:@"=" value:@"deals" ofNode:topic reason:NULL]);
	XCTAssertEqualObjects(rows(t), [NSSet setWithObject:@[ @3 ]]);
	/* From a topic, its subscribers are customers: each the hub's row,
	 * listed by user id, with its name. */
	NSString *r = [queries addQueryNamed:@"Readers" from:[[_editor.model objectTypeNamed:@"Topic"] identifier]
	                              reason:NULL];
	root = [ORMQuery queryWithId:r inModel:_editor.model].root.identifier;
	NSString *reader = [self step:queries from:root through:[[_facts objectForKey:@"topics"] lastObject] in:r];
	[queries setProjected:YES ofNode:reader];
	NSString *readerName = [self step:queries from:reader through:[[_facts objectForKey:@"name"] firstObject] in:r];
	[queries setProjected:YES ofNode:readerName];
	XCTAssertEqualObjects(rows(r), ([NSSet setWithObjects:@[ @"news", @1, @"Ann" ], @[ @"news", @3, @"Cy" ],
	                                                      @[ @"deals", @3, @"Cy" ], nil]));
}

#pragma mark The sample population

/* A population stored through the join: each customer a hub row, a
 * billing account where it owes, a subscriber where it is mailed or
 * subscribes, each with the values it correlates by; queries of the store
 * find each fact. */
- (void)testThePopulationIsStoredInTheMembers
{
	[self makeCustomers];
	ORMPopulationGenerator *generator = [[ORMPopulationGenerator alloc] initWithModel:_editor.model];
	NSString *reason = nil;
	XCTAssertTrue([_editor.populationEditor addPopulation:[generator population] reason:&reason], @"%@", reason);
	ORMModel *model = _editor.model;
	ORMCDModel *coreData = [[[ORMCoreDataMapper alloc] initWithModel:model mapping:[self mapping]] map];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	XCTAssertEqualObjects(store.notes, @[]);
	NSArray *(^all)(NSString *) = ^NSArray *(NSString *entity) {
		__block NSArray *found = nil;
		[context performBlockAndWait:^{
			found = [context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:entity] error:NULL];
		}];
		return found;
	};
	NSUInteger (^factsOf)(NSString *) = ^NSUInteger(NSString *name) {
		ORMRole *role = [model elementWithId:[[_facts objectForKey:name] firstObject]];
		return [[role.factType instances] count];
	};
	NSUInteger customers = [[[model objectTypeNamed:@"Customer"] instances] count];
	XCTAssertGreaterThan(customers, 0u);
	XCTAssertEqual([all(@"CRMCustomer") count], customers);
	XCTAssertEqual([all(@"BillingAccount") count], factsOf(@"balance"));
	XCTAssertGreaterThan(factsOf(@"balance"), 0u);
	XCTAssertGreaterThan([all(@"Subscriber") count], 0u);
	NSUInteger subscriptions = 0;
	for (NSManagedObject *subscriber in all(@"Subscriber")) {
		subscriptions += [[subscriber valueForKey:@"topics"] count];
	}
	XCTAssertEqual(subscriptions, factsOf(@"topics"));
	NSMutableSet *hubIds = [NSMutableSet setWithArray:[all(@"CRMCustomer") valueForKey:@"userId"]];
	NSMutableSet *hubGuids = [NSMutableSet setWithArray:[all(@"CRMCustomer") valueForKey:@"guid"]];
	XCTAssertTrue([[NSSet setWithArray:[all(@"BillingAccount") valueForKey:@"userId"]] isSubsetOfSet:hubIds]);
	XCTAssertTrue([[NSSet setWithArray:[all(@"Subscriber") valueForKey:@"guid"]] isSubsetOfSet:hubGuids]);
	XCTAssertFalse([[all(@"Subscriber") valueForKey:@"guid"] containsObject:[NSNull null]]);

	/* What they owe, read back through the join: each balance fact. */
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:_editor];
	NSString *q = [queries addQueryNamed:@"Owing" from:[[model objectTypeNamed:@"Customer"] identifier] reason:NULL];
	NSString *root = [ORMQuery queryWithId:q inModel:_editor.model].root.identifier;
	NSString *owes = [self step:queries from:root through:[[_facts objectForKey:@"balance"] firstObject] in:q];
	[queries setProjected:YES ofNode:owes];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithCoreData:coreData];
	ORMQueryPlan *plan = [planner planForQuery:[ORMQuery queryWithId:q inModel:_editor.model]];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:store.managedObjectModel];
	__block ORMQueryResult *result = nil;
	[context performBlockAndWait:^{
		result = [interpreter executePlan:plan inContext:context error:NULL];
	}];
	XCTAssertEqual([result.rows count], factsOf(@"balance"), @"%@", [plan text]);
}

#pragma mark Generated code

/* Updates through the join, in generated code (docs/JOINED-ENTITIES.md):
 * a Customer class over the members' objects, each property read from and
 * written where it is kept; an outer member's row made with its first
 * value and let go of with its last; a value the members are joined by
 * set on theirs too; and, at save, a hub object deleted or re-keyed
 * without the class takes its rows with it. Built and run on macOS. */
- (void)testGeneratedCodeUpdatesThroughTheJoin
{
	[self makeCustomers];
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:_editor.model mapping:[self mapping]
	                                                                             name:@"Customers"];
	NSDictionary *files = [generator files];
	NSString *header = [files objectForKey:@"CustomersValidation.h"];
	XCTAssertTrue([header containsString:@"@interface Customer : CustomersJoined"], @"%@", header);
	XCTAssertTrue([header containsString:@"@property (nonatomic, strong) NSNumber *balance;"], @"%@", header);
	XCTAssertTrue([header containsString:@"@property (nonatomic, strong) NSSet *topics;"], @"%@", header);
	XCTAssertTrue([header containsString:@"- (BOOL)orm_prepareForSave:(NSError **)error;"], @"%@", header);
#if defined(__APPLE__)
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSString *why = nil;
	XCTAssertTrue([self load:files in:directory why:&why], @"%@", why);
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:_editor.model mapping:[self mapping]] map];
	NSManagedObjectContext *context = [self storeIn:directory model:[mapped managedObjectModel]];
	Class customers = NSClassFromString(@"Customer");
	XCTAssertNotNil(customers);
	SEL allIn = NSSelectorFromString(@"allInContext:");
	SEL prepare = NSSelectorFromString(@"orm_prepareForSave:");
	NSArray *(*all)(id, SEL, id) = (NSArray * (*)(id, SEL, id))[customers methodForSelector:allIn];
	BOOL (*prepared)(id, SEL, NSError **) = (BOOL (*)(id, SEL, NSError **))[context methodForSelector:prepare];
	[context performBlockAndWait:^{
		NSUInteger (^rows)(NSString *) = ^NSUInteger(NSString *entity) {
			return [[context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:entity] error:NULL] count];
		};
		id (^customer)(NSNumber *) = ^id(NSNumber *userId) {
			for (id each in all(customers, allIn, context)) {
				if ([[each valueForKey:@"userId"] isEqual:userId]) {
					return each;
				}
			}
			return nil;
		};
		id ann = customer(@1);
		id bob = customer(@2);
		XCTAssertEqualObjects([ann valueForKey:@"name"], @"Ann");
		XCTAssertEqualObjects([ann valueForKey:@"balance"], @50);
		XCTAssertEqualObjects([ann valueForKey:@"email"], @"ann@example.test");
		XCTAssertEqual([[ann valueForKey:@"topics"] count], 1u);
		XCTAssertNil([bob valueForKey:@"balance"]);

		/* Ann pays: her account goes. Bob owes: his is made, by his id. */
		[ann setValue:nil forKey:@"balance"];
		XCTAssertEqual(rows(@"BillingAccount"), 1u);
		[bob setValue:@70 forKey:@"balance"];
		XCTAssertEqual(rows(@"BillingAccount"), 2u);
		XCTAssertEqualObjects([[bob performSelector:NSSelectorFromString(@"rowIn:") withObject:@"BillingAccount"]
		                          valueForKey:@"userId"], @2);
		/* Bob subscribes, by his GUID through the hub; a new GUID moves his
		 * subscription with him. */
		[bob setValue:@"bob@example.test" forKey:@"email"];
		XCTAssertEqual(rows(@"Subscriber"), 3u);
		[bob setValue:@"g22" forKey:@"guid"];
		XCTAssertEqualObjects([bob valueForKey:@"email"], @"bob@example.test");
		XCTAssertEqualObjects([[bob performSelector:NSSelectorFromString(@"rowIn:") withObject:@"Subscriber"]
		                          valueForKey:@"guid"], @"g22");

		/* Without the class: Cy's hub object deleted, Bob's re-keyed. At
		 * save, Cy's rows go, and Bob's follow his id. */
		id cy = customer(@3);
		[context deleteObject:[cy valueForKey:@"object"]];
		[[bob valueForKey:@"object"] setValue:@22 forKey:@"userId"];
		NSError *error = nil;
		XCTAssertTrue(prepared(context, prepare, &error), @"%@", error);
		XCTAssertEqual(rows(@"Subscriber"), 2u);
		NSFetchRequest *accounts = [NSFetchRequest fetchRequestWithEntityName:@"BillingAccount"];
		XCTAssertEqualObjects([[context executeFetchRequest:accounts error:NULL] valueForKey:@"userId"], @[ @22 ]);
		XCTAssertTrue([context save:&error], @"%@", error);
	}];
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
#endif
}

@end
