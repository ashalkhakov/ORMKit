/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

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

@end
