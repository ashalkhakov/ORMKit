/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* Changing models: each operation, what it keeps up, and its undo. */
@interface ORMEditorTests : ORMTestCase
@end

@implementation ORMEditorTests

- (NSString *)diagramOf:(ORMEditor *)editor
{
	return [[editor.model.diagrams firstObject] identifier];
}

- (NSString *)entity:(NSString *)name mode:(NSString *)mode in:(ORMEditor *)editor
{
	NSString *reason = nil;
	NSString *created = [editor.objectTypeEditor addEntityTypeNamed:name referenceMode:mode
	                                          kind:mode != nil ? ORMReferenceModePopular : ORMReferenceModeNone
	                                     onDiagram:[self diagramOf:editor] at:ORMAutomaticPlacement reason:&reason];
	XCTAssertNotNil(created, @"%@", reason);
	return created;
}

- (NSString *)fact:(NSArray *)players reading:(NSString *)reading in:(ORMEditor *)editor
{
	NSString *reason = nil;
	NSString *created = [editor.factTypeEditor addFactTypeWithPlayers:players reading:reading onDiagram:[self diagramOf:editor]
	                                                at:ORMAutomaticPlacement reason:&reason];
	XCTAssertNotNil(created, @"%@", reason);
	return created;
}

/* Keeping NORMA's derived data must not change what NORMA keeps itself:
 * an untouched file normalizes to itself, implied constraints and all. */
- (void)testNormalizingANormaModelChangesNothing
{
	for (NSString *name in [self normaFixtures]) {
		NSData *data = [self fixtureData:name];
		ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
		[editor group:@"Nothing" with:^{
		}];
		XCTAssertEqualObjects(ORMDataOfDocument(editor.document), data, @"%@", name);
	}
}

/* A file from an older NORMA keeps its own ways when edited: "Person
 * Name" rather than "Person_Name", no ExpandedData. */
- (void)testAnOlderNormaFileIsEditedInItsOwnStyle
{
	NSData *data = [self fixtureData:@"ActiveFacts/Death.orm"];
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
	NSString *person = [[editor.model objectTypeNamed:@"Person"] identifier];
	XCTAssertTrue([editor.elementEditor rename:person to:@"Human" reason:NULL]);
	XCTAssertNotNil([editor.model objectTypeNamed:@"Human Name"]);
	XCTAssertEqualObjects([[editor.model objectTypeNamed:@"Human"] referenceMode], @"Name");
	NSString *diagram = [[editor.model.diagrams firstObject] identifier];
	NSString *added = [editor.factTypeEditor addFactTypeWithPlayers:@[ person ] reading:@"{0} is famous" onDiagram:diagram
	                                              at:ORMAutomaticPlacement reason:NULL];
	ORMReading *reading = [[editor.model elementWithId:added] primaryReading];
	XCTAssertNil(ORMChild(reading.element, ORMCoreNamespace, @"ExpandedData"));
}

/* What ORMKit wrote reads back and normalizes to itself too. */
- (void)testORMKitsOwnFileIsStable
{
	NSData *data = [self fixtureData:@"WorkMate.orm"];
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
	[editor group:@"Nothing" with:^{
	}];
	XCTAssertEqualObjects(ORMDataOfDocument(editor.document), data);
	XCTAssertEqual([editor.model.diagrams count], (NSUInteger)3);
	XCTAssertEqual([[editor.model visibleObjectTypes] count], (NSUInteger)54);
}

- (void)testAReferenceModeIsBuiltAsNormaBuildsIt
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	ORMObjectType *type = [editor.model elementWithId:person];
	XCTAssertEqualObjects([type displayName], @"Person(.id)");
	XCTAssertEqualObjects(type.referenceModeValueType.name, @"Person_id");
	ORMFactType *fact = type.referenceModeFactType;
	XCTAssertEqualObjects([[fact primaryReading] text], @"{0} has {1}");
	XCTAssertEqual([fact.readingOrders count], (NSUInteger)2);
	ORMRole *own = [fact.roles firstObject];
	XCTAssertTrue(own.isMandatory && own.isUnique);
	XCTAssertEqual(type.preferredIdentifier.preferredIdentifierFor, type);
	XCTAssertEqualObjects((ORMAttribute(type.element, @"_ReferenceMode")), @"id");
	/* A value type's implied mandatory, as NORMA keeps it. */
	NSUInteger implied = 0;
	for (ORMConstraint *constraint in editor.model.constraints) {
		implied += constraint.isImplied ? 1 : 0;
	}
	XCTAssertEqual(implied, (NSUInteger)1);
}

/* An object type's flags: the same object changed, written as NORMA
 * writes them, the default left out; undone and done again. */
- (void)testAnObjectTypesFlags
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	ORMObjectType *type = [editor.model elementWithId:person];
	XCTAssertTrue([editor.objectTypeEditor setIndependent:YES of:person reason:NULL]);
	XCTAssertTrue([editor.objectTypeEditor setPersonal:YES of:person reason:NULL]);
	XCTAssertTrue([editor.objectTypeEditor setExternal:YES of:person reason:NULL]);
	XCTAssertEqual([editor.model elementWithId:person], type);
	XCTAssertTrue(type.isIndependent && type.isPersonal && type.isExternal);
	XCTAssertEqualObjects(ORMAttribute(type.element, @"IsIndependent"), @"true");
	XCTAssertEqualObjects(ORMAttribute(type.element, @"IsPersonal"), @"true");
	XCTAssertEqualObjects(ORMAttribute(type.element, @"IsExternal"), @"true");
	XCTAssertTrue([editor.objectTypeEditor setIndependent:NO of:person reason:NULL]);
	XCTAssertFalse(type.isIndependent);
	XCTAssertNil(ORMAttribute(type.element, @"IsIndependent"));
	[self.undoManager undo];
	XCTAssertTrue(type.isIndependent);
	XCTAssertEqualObjects(ORMAttribute(type.element, @"IsIndependent"), @"true");
	[self.undoManager undo];
	XCTAssertFalse(type.isExternal);
	[self.undoManager redo];
	XCTAssertTrue(type.isExternal);
	XCTAssertEqual([editor.model elementWithId:person], type);
}

/* A data type the model has not used yet is made, as NORMA makes one. */
- (void)testAValueTypesDataType
{
	ORMEditor *editor = [self newEditor];
	NSString *height = [editor.objectTypeEditor addValueTypeNamed:@"Height" dataType:nil onDiagram:nil at:NSZeroPoint
	                                                       reason:NULL];
	ORMObjectType *type = [editor.model elementWithId:height];
	NSUInteger before = [editor.model.dataTypes count];
	XCTAssertTrue([editor.objectTypeEditor setDataType:@"DecimalNumericDataType" length:10 scale:2 of:height reason:NULL]);
	XCTAssertEqualObjects(type.dataType.typeName, @"DecimalNumericDataType");
	XCTAssertEqual(type.dataTypeLength, 10);
	XCTAssertEqual(type.dataTypeScale, 2);
	XCTAssertEqual([editor.model.dataTypes count], before + 1);
	NSXMLElement *conceptual = ORMChild(type.element, ORMCoreNamespace, @"ConceptualDataType");
	XCTAssertEqualObjects(ORMRef(conceptual), type.dataType.identifier);
	XCTAssertEqualObjects(ORMAttribute(conceptual, @"Length"), @"10");
	XCTAssertEqualObjects([type.dataType.element localName], @"DecimalNumericDataType");
	/* Used again, not made again. */
	XCTAssertTrue([editor.objectTypeEditor setDataType:@"DecimalNumericDataType" length:0 scale:0 of:height reason:NULL]);
	XCTAssertEqual([editor.model.dataTypes count], before + 1);
	XCTAssertEqualObjects(ORMAttribute(conceptual, @"Length"), @"0");
	[self.undoManager undo];
	[self.undoManager undo];
	XCTAssertEqual([editor.model.dataTypes count], before);
	XCTAssertEqualObjects(type.dataType.typeName, @"UnspecifiedDataType");
}

/* An entity type made a value type and back: NORMA's element of each
 * kind, with what each kind has, the same object all along. */
- (void)testAnObjectTypeChangesKind
{
	ORMEditor *editor = [self newEditor];
	NSString *colour = [self entity:@"Colour" mode:nil in:editor];
	ORMObjectType *type = [editor.model elementWithId:colour];
	XCTAssertEqualObjects(ORMAttribute(type.element, @"_ReferenceMode"), @"");
	XCTAssertTrue([editor.objectTypeEditor setValueType:YES of:colour reason:NULL]);
	XCTAssertEqual([editor.model elementWithId:colour], type);
	XCTAssertEqual(type.kind, ORMValueType);
	XCTAssertEqualObjects([type.element localName], @"ValueType");
	XCTAssertEqualObjects(type.dataType.typeName, @"UnspecifiedDataType");
	XCTAssertNotNil(ORMChild(type.element, ORMCoreNamespace, @"ConceptualDataType"));
	XCTAssertNil(ORMAttribute(type.element, @"_ReferenceMode"));
	XCTAssertEqualObjects(ORMAttribute(type.element, @"id"), colour);
	XCTAssertTrue([editor.objectTypeEditor setValueConstraint:@"{'red', 'green'}" of:colour reason:NULL]);
	XCTAssertEqual([type.valueConstraint.ranges count], 2u);
	XCTAssertTrue([editor.objectTypeEditor setValueType:NO of:colour reason:NULL]);
	XCTAssertEqual(type.kind, ORMEntityType);
	XCTAssertEqualObjects([type.element localName], @"EntityType");
	XCTAssertNil(type.valueConstraint);
	XCTAssertNil(ORMChild(type.element, ORMCoreNamespace, @"ValueRestriction"));
	XCTAssertNil(ORMChild(type.element, ORMCoreNamespace, @"ConceptualDataType"));
	XCTAssertEqualObjects(ORMAttribute(type.element, @"_ReferenceMode"), @"");
	[self.undoManager undo];
	XCTAssertEqual(type.kind, ORMValueType);
	XCTAssertEqual([type.valueConstraint.ranges count], 2u);
	/* A value type with a value constraint, made a value type again. */
	[self.undoManager redo];
	XCTAssertTrue([editor.objectTypeEditor setValueType:YES of:colour reason:NULL]);
	XCTAssertNil(type.valueConstraint);
}

/* A role's value constraint: made, its ranges replaced, taken away, as
 * NORMA keeps one; undone. */
- (void)testARolesValueConstraint
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *age = [editor.objectTypeEditor addValueTypeNamed:@"Age" dataType:@"UnsignedIntegerNumericDataType" onDiagram:nil
	                                                     at:NSZeroPoint reason:NULL];
	NSString *fact = [self fact:@[ person, age ] reading:@"{0} has {1}" in:editor];
	ORMRole *role = [[[editor.model elementWithId:fact] roles] lastObject];
	XCTAssertTrue([editor.objectTypeEditor setValueConstraint:@"0..150" of:role.identifier reason:NULL]);
	ORMValueConstraint *values = role.valueConstraint;
	XCTAssertEqual([values.ranges count], 1u);
	XCTAssertEqualObjects([values.element localName], @"RoleValueConstraint");
	XCTAssertEqualObjects(ORMAttribute(values.element, @"Name"), @"RoleValueConstraint1");
	XCTAssertEqualObjects(values.valueType.name, @"Age");
	NSArray *ranges = ORMGrandchildren(values.element, ORMCoreNamespace, @"ValueRanges", ORMCoreNamespace, @"ValueRange");
	XCTAssertEqual([ranges count], 1u);
	XCTAssertEqualObjects(ORMAttribute([ranges firstObject], @"MaxValue"), @"150");
	XCTAssertTrue([editor.objectTypeEditor setValueConstraint:@"{1, 3..5}" of:role.identifier reason:NULL]);
	XCTAssertEqual(role.valueConstraint, values);
	XCTAssertEqual([values.ranges count], 2u);
	ranges = ORMGrandchildren(values.element, ORMCoreNamespace, @"ValueRanges", ORMCoreNamespace, @"ValueRange");
	XCTAssertEqual([ranges count], 2u);
	XCTAssertEqualObjects([values displayText], @"{1, 3..5}");
	XCTAssertTrue([editor.objectTypeEditor setValueConstraint:@"" of:role.identifier reason:NULL]);
	XCTAssertNil(role.valueConstraint);
	XCTAssertNil(ORMChild(role.element, ORMCoreNamespace, @"ValueRestriction"));
	[self.undoManager undo];
	XCTAssertEqualObjects([role.valueConstraint displayText], @"{1, 3..5}");
	[self.undoManager undo];
	XCTAssertEqualObjects([role.valueConstraint displayText], @"{0..150}");
}

/* Readings edited and deleted, a unary's implicit type renamed with its
 * reading, a role given another player; undone. */
- (void)testReadingsAndPlayers
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:nil in:editor];
	NSString *country = [self entity:@"Country" mode:nil in:editor];
	NSString *city = [self entity:@"City" mode:nil in:editor];
	ORMFactType *smokes = [editor.model elementWithId:[self fact:@[ person ] reading:@"{0} smokes" in:editor]];
	ORMObjectType *implicit = [smokes implicitRole].player;
	XCTAssertEqualObjects(implicit.name, @"Person smokes");
	ORMReading *reading = [[[smokes.readingOrders firstObject] readings] firstObject];
	XCTAssertTrue([editor.factTypeEditor setReadingText:@"{0} is a smoker" of:reading.identifier reason:NULL]);
	XCTAssertEqualObjects(reading.text, @"{0} is a smoker");
	XCTAssertEqualObjects(implicit.name, @"Person is a smoker");
	XCTAssertEqualObjects(ORMAttribute(implicit.element, @"Name"), @"Person is a smoker");

	ORMFactType *born = [editor.model elementWithId:[self fact:@[ person, country ] reading:@"{0} was born in {1}" in:editor]];
	NSArray *roles = born.roles;
	NSString *second = [editor.factTypeEditor addReading:@"{0} is birthplace of {1}"
	                                            forRoles:@[ [roles[1] identifier], [roles[0] identifier] ] reason:NULL];
	XCTAssertEqual([born.readingOrders count], 2u);
	XCTAssertTrue([editor.factTypeEditor setReadingText:@"" of:second reason:NULL]);
	XCTAssertEqual([born.readingOrders count], 1u);
	XCTAssertNil([editor.model elementWithId:second]);
	XCTAssertEqual([ORMGrandchildren(born.element, ORMCoreNamespace, @"ReadingOrders", ORMCoreNamespace, @"ReadingOrder") count], 1u);

	XCTAssertTrue([editor.factTypeEditor setPlayer:city ofRole:[roles[1] identifier] reason:NULL]);
	XCTAssertEqualObjects([roles[1] player].name, @"City");
	XCTAssertEqualObjects(ORMRef(ORMChild([(ORMRole *)roles[1] element], ORMCoreNamespace, @"RolePlayer")), city);
	XCTAssertEqual([[[editor.model elementWithId:country] playedRoles] count], 0u);

	[self.undoManager undo];
	XCTAssertEqualObjects([roles[1] player].name, @"Country");
	[self.undoManager undo];
	XCTAssertEqual([born.readingOrders count], 2u);
}

- (void)testNamesAreUnique
{
	ORMEditor *editor = [self newEditor];
	[self entity:@"Person" mode:nil in:editor];
	NSString *reason = nil;
	XCTAssertNil([editor.objectTypeEditor addValueTypeNamed:@"Person" dataType:nil onDiagram:nil at:NSZeroPoint reason:&reason]);
	XCTAssertTrue([reason length] > 0);
}

- (void)testRenamingAnEntityRenamesItsReferenceMode
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	XCTAssertTrue([editor.elementEditor rename:person to:@"Human" reason:NULL]);
	XCTAssertNotNil([editor.model objectTypeNamed:@"Human_id"]);
	XCTAssertNil([editor.model objectTypeNamed:@"Person_id"]);
	XCTAssertEqualObjects([[[[editor.model objectTypeNamed:@"Human"] referenceModeFactType] primaryReading] expandedText],
	                      @"Human has Human_id");
}

- (void)testConstraintsOnABinary
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *born = [self fact:@[ person, country ] reading:@"{0} was born in {1}" in:editor];
	ORMRole *role = [[[editor.model elementWithId:born] roles] firstObject];
	XCTAssertTrue([editor.constraintEditor setUnique:YES role:role.identifier reason:NULL]);
	XCTAssertTrue([editor.constraintEditor setMandatory:YES role:role.identifier reason:NULL]);
	role = [editor.model elementWithId:role.identifier];
	XCTAssertEqual([[role oppositeRole] multiplicity], ORMMultiplicityExactlyOne);
	XCTAssertEqualObjects((ORMAttribute([role oppositeRole].element, @"_Multiplicity")), @"ExactlyOne");
	XCTAssertEqual([[editor.model elementWithId:born] internalConstraints].count, (NSUInteger)2);
	XCTAssertTrue([editor.constraintEditor setUnique:NO role:role.identifier reason:NULL]);
	XCTAssertFalse([[editor.model elementWithId:role.identifier] isUnique]);
	/* The n-1 rule for longer fact types. */
	NSString *year = [self entity:@"Year" mode:@"nr" in:editor];
	NSString *visit = [self fact:@[ person, country, year ] reading:@"{0} visited {1} in {2}" in:editor];
	NSString *reason = nil;
	XCTAssertNil([editor.constraintEditor addUniquenessConstraintOverRoles:@[ [[[editor.model elementWithId:visit] roles][0] identifier] ]
	                                               reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"at least 2"].location != NSNotFound, @"%@", reason);
}

- (void)testAUnaryGetsItsImplicitBoolean
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *smokes = [self fact:@[ person ] reading:@"{0} smokes" in:editor];
	ORMFactType *fact = [editor.model elementWithId:smokes];
	XCTAssertTrue([fact isUnary]);
	ORMObjectType *implicit = [[fact.roles lastObject] player];
	XCTAssertTrue(implicit.isImplicitBooleanValue);
	XCTAssertEqualObjects(implicit.name, @"Person smokes");
	XCTAssertEqualObjects([implicit.valueConstraint displayText], @"{True}");
	XCTAssertTrue([[fact.roles firstObject] isUnique]);
	/* Renamed with its subject. */
	XCTAssertTrue([editor.elementEditor rename:person to:@"Human" reason:NULL]);
	XCTAssertNotNil([editor.model objectTypeNamed:@"Human smokes"]);
}

- (void)testExternalAndSetComparisonConstraints
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *name = [editor.objectTypeEditor addValueTypeNamed:@"Name" dataType:@"VariableLengthTextDataType" onDiagram:nil
	                                        at:NSZeroPoint reason:NULL];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	/* Made first: editor.model is read before a message's arguments are. */
	NSString *namedId = [self fact:@[ person, name ] reading:@"{0} has {1}" in:editor];
	NSString *bornId = [self fact:@[ person, country ] reading:@"{0} was born in {1}" in:editor];
	NSArray *named = [[editor.model elementWithId:namedId] roles];
	NSArray *born = [[editor.model elementWithId:bornId] roles];
	NSString *reason = nil;
	NSString *external = [editor.constraintEditor addUniquenessConstraintOverRoles:@[ [named[1] identifier], [born[1] identifier] ]
	                                                       reason:&reason];
	XCTAssertNotNil(external, @"%@", reason);
	XCTAssertTrue([[editor.model elementWithId:external] isExternal]);
	XCTAssertNotNil([editor.diagramEditor placeElement:external onDiagram:[self diagramOf:editor] at:ORMAutomaticPlacement]);

	NSString *xor = [editor.constraintEditor addExclusiveOrConstraintOverRoles:@[ [named[0] identifier], [born[0] identifier] ]
	                                                   reason:&reason];
	XCTAssertNotNil(xor, @"%@", reason);
	XCTAssertNotNil([[editor.model elementWithId:xor] exclusiveOrPartner]);

	NSString *subset = [editor.constraintEditor addSetComparisonConstraint:ORMSubsetConstraint
	                                            sequences:@[ @[ [named[0] identifier] ], @[ [born[0] identifier] ] ]
	                                               reason:&reason];
	XCTAssertNotNil(subset, @"%@", reason);
	XCTAssertNil(([editor.constraintEditor addSetComparisonConstraint:ORMEqualityConstraint
	                                      sequences:@[ @[ [named[0] identifier] ], @[ [born[1] identifier] ] ]
	                                         reason:&reason]), @"incompatible players accepted");
	NSString *frequency = [editor.constraintEditor addFrequencyConstraintOverRoles:@[ [named[0] identifier] ] min:2 max:3 reason:&reason];
	XCTAssertEqual([[editor.model elementWithId:frequency] maxFrequency], (NSUInteger)3);
}

/* A constraint drawn as a shape of its own is shown, as it is added, on the
 * diagrams that show its fact types, as NORMA shows one: in the same
 * change, so one undo takes both. A fact type no diagram shows, none. */
- (void)testAddedConstraintsAreShownWhereTheirFactTypesAre
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *name = [editor.objectTypeEditor addValueTypeNamed:@"Name" dataType:@"VariableLengthTextDataType" onDiagram:nil
	                                        at:NSZeroPoint reason:NULL];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *namedId = [self fact:@[ person, name ] reading:@"{0} has {1}" in:editor];
	NSString *bornId = [self fact:@[ person, country ] reading:@"{0} was born in {1}" in:editor];
	NSArray *named = [[editor.model elementWithId:namedId] roles];
	NSArray *born = [[editor.model elementWithId:bornId] roles];
	NSString *reason = nil;
	NSString *external = [editor.constraintEditor addUniquenessConstraintOverRoles:@[ [named[1] identifier], [born[1] identifier] ]
	                                                                        reason:&reason];
	XCTAssertNotNil(external, @"%@", reason);
	ORMDiagram *diagram = [editor.model.diagrams firstObject];
	XCTAssertNotNil([diagram shapeForSubject:external]);
	NSString *exclusion = [editor.constraintEditor addSetComparisonConstraint:ORMExclusionConstraint
	                                                                sequences:@[ @[ [named[0] identifier] ], @[ [born[0] identifier] ] ]
	                                                                   reason:&reason];
	XCTAssertNotNil([[editor.model.diagrams firstObject] shapeForSubject:exclusion], @"%@", reason);
	/* One step: the constraint and its shape. */
	[self.undoManager undo];
	XCTAssertNil([editor.model elementWithId:exclusion]);
	XCTAssertNil([[editor.model.diagrams firstObject] shapeForSubject:exclusion]);
	XCTAssertNotNil([[editor.model.diagrams firstObject] shapeForSubject:external]);
	/* A ring, a shape of its own too. */
	NSString *knowsId = [self fact:@[ person, person ] reading:@"{0} knows {1}" in:editor];
	NSArray *knows = [[editor.model elementWithId:knowsId] roles];
	NSString *ring = [editor.constraintEditor addRingConstraint:ORMRingIrreflexive
	                                                  overRoles:@[ [knows[0] identifier], [knows[1] identifier] ]
	                                                     reason:&reason];
	XCTAssertNotNil([[editor.model.diagrams firstObject] shapeForSubject:ring], @"%@", reason);
	/* Over a fact type no diagram shows: no shape. */
	NSString *likedId = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, person ] reading:@"{0} likes {1}" onDiagram:nil
	                                                               at:NSZeroPoint reason:&reason];
	NSArray *likes = [[editor.model elementWithId:likedId] roles];
	NSString *hidden = [editor.constraintEditor addRingConstraint:ORMRingIrreflexive
	                                                    overRoles:@[ [likes[0] identifier], [likes[1] identifier] ]
	                                                       reason:&reason];
	XCTAssertNotNil(hidden, @"%@", reason);
	XCTAssertNil([[editor.model.diagrams firstObject] shapeForSubject:hidden]);
}

/* The issues an issue navigator lists: the model's own errors, what its
 * population breaks, what the mapping warns of; errors first. */
- (void)testIssuesAreFound
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *thing = [self entity:@"Thing" mode:nil in:editor];
	NSString *likes = [self fact:@[ person, thing ] reading:@"{0} likes {1}" in:editor];
	NSArray *issues = [[[ORMIssueFinder alloc] initWithModel:editor.model mapping:nil] issues];
	NSArray *texts = [issues valueForKey:@"text"];
	XCTAssertTrue([texts containsObject:@"Thing has no reference scheme: nothing identifies it."], @"%@", texts);
	XCTAssertTrue([texts containsObject:@"\"Person likes Thing\" has no uniqueness constraint."], @"%@", texts);
	ORMIssue *first = [issues firstObject];
	XCTAssertEqual(first.severity, ORMIssueError);
	XCTAssertTrue(([@[ thing, likes ] containsObject:first.elementId]), @"%@", first.elementId);
	NSArray *roles = [[editor.model elementWithId:likes] roles];
	XCTAssertNotNil([editor.constraintEditor addUniquenessConstraintOverRoles:@[ [roles[0] identifier] ] reason:NULL]);
	texts = [[[[ORMIssueFinder alloc] initWithModel:editor.model mapping:nil] issues] valueForKey:@"text"];
	XCTAssertFalse([texts containsObject:@"\"Person likes Thing\" has no uniqueness constraint."], @"%@", texts);

	/* The Company sample: Gus breaks its deontic rule, a warning. */
	NSString *root = [[[[self fixturePath:@"x"] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
		stringByDeletingLastPathComponent];
	NSString *path = [[root stringByAppendingPathComponent:@"Samples"] stringByAppendingPathComponent:@"Company.orm"];
	ORMModel *company = [ORMModel modelOfDocument:ORMParseDocument([NSData dataWithContentsOfFile:path], NULL) reason:NULL];
	NSArray *found = [[[ORMIssueFinder alloc] initWithModel:company mapping:nil] issues];
	ORMIssue *gus = nil;
	for (ORMIssue *issue in found) {
		if ([issue.text hasPrefix:@"Lives near work:"]) {
			gus = issue;
		}
	}
	XCTAssertNotNil(gus, @"%@", [found valueForKey:@"text"]);
	XCTAssertEqual(gus.severity, ORMIssueWarning);
	XCTAssertEqualObjects(gus.area, @"Population");
	for (ORMIssue *issue in found) {
		XCTAssertNotEqual(issue.severity, ORMIssueError, @"%@", issue.text);
	}
}

/* Readings that do not read, as NORMA finds them in a file: the wrong
 * placeholders, an order missing a role, two fact types read the same way;
 * and a reading with no words but its players, a warning. */
- (void)testReadingsThatDoNotReadAreIssues
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *thing = [self entity:@"Thing" mode:@"code" in:editor];
	NSString *likes = [self fact:@[ person, thing ] reading:@"{0} likes {1}" in:editor];
	NSString *twice = [self fact:@[ person, thing ] reading:@"{0} likes  {1}" in:editor];
	NSString *hates = [self fact:@[ person, thing ] reading:@"{0} hates {1}" in:editor];
	NSString *owns = [self fact:@[ person, thing ] reading:@"{0} owns {1}" in:editor];
	NSString *bare = [self fact:@[ person, thing ] reading:@"{0} is near {1}" in:editor];
	NSArray *before = [[[[ORMIssueFinder alloc] initWithModel:editor.model mapping:nil] issues] valueForKey:@"text"];
	XCTAssertTrue([before containsObject:@"\"Person likes  Thing\" reads the same as \"Person likes Thing\", another fact type."],
	              @"%@", before);

	/* What the editor would not write, written into a copy of the file. */
	NSXMLDocument *document = [editor.document copy];
	ORMModel *model = [ORMModel modelOfDocument:document reason:NULL];
	NSXMLElement *(^data)(NSString *) = ^NSXMLElement *(NSString *factId) {
		ORMReading *reading = [[model elementWithId:factId] primaryReading];
		return ORMChild(reading.element, ORMCoreNamespace, @"Data");
	};
	[data(hates) setStringValue:@"{0} hates {2}"];
	[data(bare) setStringValue:@"{0} {1}"];
	ORMReadingOrder *order = [[[model elementWithId:owns] readingOrders] firstObject];
	NSXMLElement *sequence = ORMChild(order.element, ORMCoreNamespace, @"RoleSequence");
	[sequence removeChildAtIndex:1];
	model = [ORMModel modelOfDocument:document reason:NULL];
	NSArray *issues = [[[ORMIssueFinder alloc] initWithModel:model mapping:nil] issues];
	NSMutableDictionary *about = [NSMutableDictionary dictionary];
	for (ORMIssue *issue in issues) {
		if ([issue.text rangeOfString:@"read"].location != NSNotFound) {
			about[issue.elementId] = issue;
		}
	}
	XCTAssertEqual([about[hates] severity], ORMIssueError);
	XCTAssertTrue([[about[hates] text] hasPrefix:@"The reading \"{0} hates {2}\" of"], @"%@", [about[hates] text]);
	XCTAssertEqual([about[owns] severity], ORMIssueError, @"%@", [issues valueForKey:@"text"]);
	XCTAssertTrue([[about[owns] text] rangeOfString:@"does not place its roles"].location != NSNotFound);
	XCTAssertEqual([about[bare] severity], ORMIssueWarning, @"%@", [issues valueForKey:@"text"]);
	XCTAssertEqual([about[twice] severity], ORMIssueError);
	XCTAssertNil(about[likes]);

	/* NORMA's own files read. */
	ORMModel *stock = [ORMModel modelOfDocument:ORMParseDocument([NSData dataWithContentsOfFile:[self fixturePath:@"StockMate.orm"]], NULL)
	                                     reason:NULL];
	for (ORMIssue *issue in [[[ORMIssueFinder alloc] initWithModel:stock mapping:nil] issues]) {
		XCTAssertTrue([issue.text rangeOfString:@"read"].location == NSNotFound, @"%@", issue.text);
	}
}

/* NORMA's alignment: edges to the outermost, centres to the first,
 * spacing even between the outermost two; what a shape carries moves with
 * it; one change, one undo. */
- (void)testShapesAreAligned
{
	ORMEditor *editor = [self newEditor];
	NSString *a = [self entity:@"A" mode:@"id" in:editor];
	NSString *b = [self entity:@"B" mode:@"id" in:editor];
	NSString *c = [self entity:@"C" mode:@"id" in:editor];
	NSString *fact = [self fact:@[ a, b ] reading:@"{0} knows {1}" in:editor];
	ORMDiagram *diagram = [editor.model.diagrams firstObject];
	NSString *(^shape)(NSString *) = ^NSString *(NSString *element) {
		return [[[editor.model.diagrams firstObject] shapeForSubject:element] identifier];
	};
	NSRect (^bounds)(NSString *) = ^NSRect(NSString *element) {
		return [[[editor.model.diagrams firstObject] shapeForSubject:element] bounds];
	};
	[editor.diagramEditor setBounds:NSMakeRect(10, 10, 60, 30) ofShape:shape(a)];
	[editor.diagramEditor setBounds:NSMakeRect(100, 50, 80, 30) ofShape:shape(b)];
	[editor.diagramEditor setBounds:NSMakeRect(300, 200, 40, 20) ofShape:shape(c)];
	(void)diagram;
	NSString *reason = nil;
	XCTAssertFalse(([editor.diagramEditor alignShapes:@[ shape(a) ] as:ORMAlignLeft reason:&reason]));
	XCTAssertFalse(([editor.diagramEditor alignShapes:@[ shape(a), shape(b) ] as:ORMDistributeAcross reason:&reason]));
	XCTAssertTrue(([editor.diagramEditor alignShapes:@[ shape(a), shape(b), shape(c) ] as:ORMAlignLeft reason:&reason]));
	XCTAssertEqual(NSMinX(bounds(b)), 10.0);
	XCTAssertEqual(NSMinX(bounds(c)), 10.0);
	[self.undoManager undo];
	XCTAssertEqual(NSMinX(bounds(b)), 100.0);
	XCTAssertEqual(NSMinX(bounds(c)), 300.0);
	XCTAssertTrue(([editor.diagramEditor alignShapes:@[ shape(b), shape(a) ] as:ORMAlignCentres reason:&reason]));
	XCTAssertEqual(NSMidX(bounds(a)), NSMidX(bounds(b)));
	XCTAssertEqual(NSMidX(bounds(b)), 140.0);
	XCTAssertTrue(([editor.diagramEditor alignShapes:@[ shape(a), shape(b), shape(c) ] as:ORMDistributeDown reason:&reason]));
	double first = NSMidY(bounds(a)), middle = NSMidY(bounds(b)), last = NSMidY(bounds(c));
	XCTAssertEqualWithAccuracy(middle - first, last - middle, 0.001);
	/* A fact type's reading moves with it. */
	NSRect reading = [[[[[editor.model.diagrams firstObject] shapeForSubject:fact] relativeShapes] firstObject] bounds];
	NSRect factBounds = bounds(fact);
	XCTAssertTrue(([editor.diagramEditor alignShapes:@[ shape(a), shape(fact) ] as:ORMAlignTop reason:&reason]));
	double moved = NSMinY(bounds(fact)) - NSMinY(factBounds);
	NSRect readingNow = [[[[[editor.model.diagrams firstObject] shapeForSubject:fact] relativeShapes] firstObject] bounds];
	XCTAssertEqualWithAccuracy(NSMinY(readingNow) - NSMinY(reading), moved, 0.001);
}

- (void)testSubtypingRefusesCycles
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *student = [self entity:@"Student" mode:nil in:editor];
	XCTAssertNotNil([editor.objectTypeEditor addSubtype:student of:person reason:NULL]);
	XCTAssertTrue([[editor.model elementWithId:student] isSubtypeOf:[editor.model elementWithId:person]]);
	NSString *reason = nil;
	XCTAssertNil([editor.objectTypeEditor addSubtype:person of:student reason:&reason]);
	XCTAssertTrue([reason length] > 0);
	ORMFactType *fact = [[[editor.model elementWithId:student] supertypeFacts] firstObject];
	XCTAssertTrue(fact.providesPreferredIdentifier);
}

- (void)testObjectificationAddsLinkFactTypes
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *visit = [self fact:@[ person, country ] reading:@"{0} visited {1}" in:editor];
	NSString *reason = nil;
	NSString *visitType = [editor.factTypeEditor objectifyFactType:visit named:@"Visit" reason:&reason];
	XCTAssertNotNil(visitType, @"%@", reason);
	ORMFactType *fact = [editor.model elementWithId:visit];
	XCTAssertEqual(fact.objectifyingType, [editor.model elementWithId:visitType]);
	XCTAssertTrue([fact hasUniquenessOverRoles:fact.roles], @"a spanning constraint identifies it");
	NSUInteger links = 0;
	for (ORMFactType *link in editor.model.factTypes) {
		if (link.impliedByFactType == fact) {
			links++;
			XCTAssertNotNil([[link.roles firstObject] proxiedRole]);
		}
	}
	XCTAssertEqual(links, (NSUInteger)2);
	XCTAssertTrue([editor.factTypeEditor unobjectifyFactType:visit reason:&reason], @"%@", reason);
	XCTAssertNil([editor.model objectTypeNamed:@"Visit"]);
	for (ORMFactType *link in editor.model.factTypes) {
		XCTAssertNotEqual(link.kind, ORMFactTypeImplied);
	}
}

/* A role an objectified fact type plays is drawn to its outline: no shape
 * of its own, and arranging keeps the two together. */
- (void)testAnObjectifiedFactTypeIsWhereItsRolesAreDrawn
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *visit = [self fact:@[ person, country ] reading:@"{0} visited {1}" in:editor];
	NSString *visitType = [editor.factTypeEditor objectifyFactType:visit named:@"Visit" reason:NULL];
	NSString *period = [self entity:@"Period" mode:@"days" in:editor];
	[self fact:@[ visitType, period ] reading:@"{0} took {1}" in:editor];
	ORMDiagram *diagram = [editor.model.diagrams firstObject];
	XCTAssertNil([diagram shapeForSubject:visitType]);
	[editor.diagramEditor arrangeDiagram:diagram.identifier];
	NSRect extent = [[editor.model.diagrams firstObject] extent];
	XCTAssertTrue(NSWidth(extent) < 8 * 72 && NSHeight(extent) < 8 * 72, @"%@", NSStringFromRect(extent));
}

- (void)testDeletingCascades
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *bornId = [self fact:@[ person, country ] reading:@"{0} was born in {1}" in:editor];
	NSArray *born = [[editor.model elementWithId:bornId] roles];
	[editor.constraintEditor addMandatoryConstraintOverRoles:@[ [born[0] identifier] ] reason:NULL];
	[editor.elementEditor deleteElements:@[ person ]];
	XCTAssertNil([editor.model objectTypeNamed:@"Person"]);
	XCTAssertNil([editor.model objectTypeNamed:@"Person_id"], @"its reference mode value type goes with it");
	XCTAssertNotNil([editor.model objectTypeNamed:@"Country"]);
	XCTAssertEqual([editor.model.factTypes count], (NSUInteger)1, @"only Country's reference mode fact type is left");
	for (ORMConstraint *constraint in editor.model.constraints) {
		XCTAssertTrue([[constraint allRoles] count] > 0, @"%@ lost its roles", constraint.name);
	}
	for (ORMShape *shape in [[editor.model.diagrams firstObject] allShapes]) {
		XCTAssertNotNil(shape.subject);
	}
}

- (void)testEverythingUndoesAndRedoes
{
	ORMEditor *editor = [self newEditor];
	NSData *empty = ORMDataOfDocument(editor.document);
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	[self fact:@[ person, country ] reading:@"{0} lives in {1}" in:editor];
	[editor.elementEditor rename:person to:@"Resident" reason:NULL];
	NSData *full = ORMDataOfDocument(editor.document);
	XCTAssertTrue(editor.hasChanges);
	while ([self.undoManager canUndo]) {
		[self.undoManager undo];
	}
	XCTAssertEqualObjects(ORMDataOfDocument(editor.document), empty);
	XCTAssertFalse(editor.hasChanges);
	while ([self.undoManager canRedo]) {
		[self.undoManager redo];
	}
	XCTAssertEqualObjects(ORMDataOfDocument(editor.document), full);
}

- (void)testShapesMoveWithWhatIsPlacedOnThem
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *born = [self fact:@[ person, country ] reading:@"{0} was born in {1}" in:editor];
	ORMDiagram *diagram = [editor.model.diagrams firstObject];
	ORMShape *shape = [diagram shapeForSubject:born];
	ORMShape *reading = [shape.relativeShapes firstObject];
	XCTAssertEqual(reading.kind, ORMShapeReading);
	NSRect before = reading.bounds;
	[editor.diagramEditor moveShapes:@[ shape.identifier ] by:NSMakeSize(10, 20)];
	ORMShape *moved = [[[editor.model.diagrams firstObject] shapeForSubject:born].relativeShapes firstObject];
	XCTAssertEqualWithAccuracy(NSMinX(moved.bounds), NSMinX(before) + 10, 0.001);
	XCTAssertEqualWithAccuracy(NSMinY(moved.bounds), NSMinY(before) + 20, 0.001);
}

/* Another shape of an element the diagram shows already, as NORMA has, to
 * keep a busy diagram's lines short: its own, beside the first; placing
 * the element again finds the first; undone as one change. */
- (void)testAnElementHasAnotherShape
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *born = [self fact:@[ person, country ] reading:@"{0} was born in {1}" in:editor];
	NSString *diagramId = [self diagramOf:editor];
	NSString *first = [[[editor.model.diagrams firstObject] shapeForSubject:country] identifier];
	NSString *second = [editor.diagramEditor addShapeOfElement:country onDiagram:diagramId at:ORMAutomaticPlacement];
	XCTAssertNotNil(second);
	XCTAssertNotEqualObjects(second, first);
	ORMDiagram *diagram = [editor.model.diagrams firstObject];
	NSArray *shapes = [diagram shapesForSubject:country];
	XCTAssertEqual([shapes count], (NSUInteger)2);
	XCTAssertFalse(NSIntersectsRect([shapes[0] bounds], [shapes[1] bounds]), @"placed clear of the first");
	XCTAssertEqualObjects([editor.diagramEditor placeElement:country onDiagram:diagramId at:ORMAutomaticPlacement], first);
	/* A fact type's too, with its reading. */
	NSString *bornAgain = [editor.diagramEditor addShapeOfElement:born onDiagram:diagramId at:NSMakePoint(400, 400)];
	NSArray *bornShapes = [[editor.model.diagrams firstObject] shapesForSubject:born];
	XCTAssertEqual([bornShapes count], (NSUInteger)2);
	ORMShape *again = [[bornShapes filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"identifier == %@", bornAgain]]
	                   firstObject];
	XCTAssertEqual([again.relativeShapes count], (NSUInteger)1);
	/* Not of what has no shape of its own on a diagram. */
	XCTAssertNil([editor.diagramEditor addShapeOfElement:[[[editor.model elementWithId:born] roles][0] identifier]
	                                           onDiagram:diagramId at:ORMAutomaticPlacement]);
	[self.undoManager undo];
	[self.undoManager undo];
	XCTAssertEqual([[[editor.model.diagrams firstObject] shapesForSubject:country] count], (NSUInteger)1);
}

/* An extra shape removed: the shape alone, with what is placed on it,
 * never the element, nor its last shape; undone as one change. */
- (void)testAnExtraShapeIsRemoved
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *born = [self fact:@[ person, country ] reading:@"{0} was born in {1}" in:editor];
	NSString *diagramId = [self diagramOf:editor];
	NSString *first = [[[editor.model.diagrams firstObject] shapeForSubject:born] identifier];
	NSString *second = [editor.diagramEditor addShapeOfElement:born onDiagram:diagramId at:ORMAutomaticPlacement];
	XCTAssertTrue([editor.diagramEditor isExtraShape:second]);
	XCTAssertTrue([editor.diagramEditor isExtraShape:first], @"either is extra while there are two");
	XCTAssertFalse([editor.diagramEditor isExtraShape:[[[editor.model.diagrams firstObject] shapeForSubject:person] identifier]]);
	/* Both asked: one goes, the last stays. */
	XCTAssertEqual(([editor.diagramEditor removeExtraShapes:@[ second, first ]]), (NSUInteger)1);
	NSArray *kept = [[editor.model.diagrams firstObject] shapesForSubject:born];
	XCTAssertEqual([kept count], (NSUInteger)1);
	XCTAssertNotNil([editor.model elementWithId:born], @"the fact type stays");
	XCTAssertEqual([[kept[0] relativeShapes] count], (NSUInteger)1, @"its reading with the shape left");
	XCTAssertEqual([editor.diagramEditor removeExtraShapes:@[ [kept[0] identifier] ]], (NSUInteger)0, @"not the last");
	XCTAssertEqualObjects([self.undoManager undoActionName], @"Delete Extra Shape");
	[self.undoManager undo];
	XCTAssertEqual([[[editor.model.diagrams firstObject] shapesForSubject:born] count], (NSUInteger)2);
}

/* Every shape of the elements on the diagram. */
- (NSArray<ORMShape *> *)shapesOf:(NSArray<NSString *> *)subjects on:(ORMDiagram *)diagram
{
	NSMutableArray *shapes = [NSMutableArray array];
	for (NSString *subject in subjects) {
		[shapes addObjectsFromArray:[diagram shapesForSubject:subject]];
	}
	return shapes;
}

/* The bounds of the shapes. */
- (NSRect)extentOf:(NSArray<ORMShape *> *)shapes
{
	NSRect extent = NSZeroRect;
	for (ORMShape *shape in shapes) {
		extent = NSIsEmptyRect(extent) ? shape.bounds : NSUnionRect(extent, shape.bounds);
	}
	return extent;
}

/* Arranged in groups: the hubs (Date, a value type) taken out, what stays
 * linked is a group, laid out on its own with a shape of each hub it
 * uses, apart from the others; each group's lines to its own copy. Again,
 * the same; undone as one change. */
- (void)testADiagramIsArrangedInGroups
{
	ORMEditor *editor = [self newEditor];
	NSString *diagramId = [self diagramOf:editor];
	NSString *reason = nil;
	NSString *date = [editor.objectTypeEditor addValueTypeNamed:@"Date" dataType:@"DateDataType" onDiagram:diagramId
	                                                        at:ORMAutomaticPlacement reason:&reason];
	XCTAssertNotNil(date, @"%@", reason);
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *car = [self entity:@"Car" mode:@"vin" in:editor];
	NSString *shop = [self entity:@"Shop" mode:@"name" in:editor];
	NSString *item = [self entity:@"Item" mode:@"sku" in:editor];
	NSString *drives = [self fact:@[ person, car ] reading:@"{0} drives {1}" in:editor];
	NSString *born = [self fact:@[ person, date ] reading:@"{0} was born on {1}" in:editor];
	NSString *built = [self fact:@[ car, date ] reading:@"{0} was built on {1}" in:editor];
	NSString *stocks = [self fact:@[ shop, item ] reading:@"{0} stocks {1}" in:editor];
	NSString *opened = [self fact:@[ shop, date ] reading:@"{0} opened on {1}" in:editor];
	NSString *expires = [self fact:@[ item, date ] reading:@"{0} expires on {1}" in:editor];
	[editor.diagramEditor arrangeDiagramInGroups:diagramId];

	ORMDiagram *diagram = [editor.model.diagrams firstObject];
	NSArray *dates = [diagram shapesForSubject:date];
	XCTAssertEqual([dates count], (NSUInteger)2, @"a Date for each group");
	NSRect cars = [self extentOf:[self shapesOf:@[ person, car, drives, born, built ] on:diagram]];
	NSRect shops = [self extentOf:[self shapesOf:@[ shop, item, stocks, opened, expires ] on:diagram]];
	XCTAssertFalse(NSIntersectsRect(cars, shops), @"the groups apart: %@ %@", NSStringFromRect(cars), NSStringFromRect(shops));
	/* Each group's Date nearer its facts than the other group's. */
	for (NSArray *group in @[ @[ born, built ], @[ opened, expires ] ]) {
		NSMutableSet *nearest = [NSMutableSet set];
		for (NSString *fact in group) {
			ORMShape *factShape = [diagram shapeForSubject:fact];
			ORMShape *best = nil;
			double distance = DBL_MAX;
			for (ORMShape *each in dates) {
				double d = hypot(NSMidX(each.bounds) - NSMidX(factShape.bounds), NSMidY(each.bounds) - NSMidY(factShape.bounds));
				if (d < distance) {
					distance = d;
					best = each;
				}
			}
			[nearest addObject:best.identifier];
		}
		XCTAssertEqual([nearest count], (NSUInteger)1, @"one Date for the group");
	}
	/* Overlapping nothing. */
	NSArray *all = diagram.shapes;
	for (NSUInteger i = 0; i < [all count]; i++) {
		for (NSUInteger j = i + 1; j < [all count]; j++) {
			XCTAssertFalse(NSIntersectsRect([all[i] bounds], [all[j] bounds]), @"%@ and %@ overlap", [all[i] subjectId],
			               [all[j] subjectId]);
		}
	}
	[editor.diagramEditor arrangeDiagramInGroups:diagramId];
	XCTAssertEqual([[[editor.model.diagrams firstObject] shapesForSubject:date] count], (NSUInteger)2, @"again, the same");
	[self.undoManager undo];
	[self.undoManager undo];
	XCTAssertEqual([[[editor.model.diagrams firstObject] shapesForSubject:date] count], (NSUInteger)1);
}

/* The shape of the element nearest the point. */
- (ORMShape *)shapeOf:(NSString *)subject nearest:(NSPoint)point on:(ORMDiagram *)diagram
{
	ORMShape *best = nil;
	double distance = DBL_MAX;
	for (ORMShape *each in [diagram shapesForSubject:subject]) {
		double d = hypot(NSMidX(each.bounds) - point.x, NSMidY(each.bounds) - point.y);
		if (d < distance) {
			distance = d;
			best = each;
		}
	}
	return best;
}

/* An entity type much used is an anchor, at the head of a group of its
 * own: a fact type of two anchors goes with its first player's, which
 * shows the other once more. A constraint over fact types in two groups
 * is in one, and shows the other's fact type there too. */
- (void)testEachAnchorHasAGroupOfItsOwn
{
	ORMEditor *editor = [self newEditor];
	NSString *diagramId = [self diagramOf:editor];
	NSString *order = [self entity:@"Order" mode:@"nr" in:editor];
	NSString *item = [self entity:@"Item" mode:@"sku" in:editor];
	NSString *customer = [self entity:@"Customer" mode:@"id" in:editor];
	NSString *address = [self entity:@"Address" mode:@"id" in:editor];
	NSString *kind = [self entity:@"Kind" mode:@"code" in:editor];
	NSString *shelf = [self entity:@"Shelf" mode:@"nr" in:editor];
	NSString *supplier = [self entity:@"Supplier" mode:@"id" in:editor];
	NSString *isFor = [self fact:@[ order, item ] reading:@"{0} is for {1}" in:editor];
	NSString *placed = [self fact:@[ order, customer ] reading:@"{0} is placed by {1}" in:editor];
	NSString *shipped = [self fact:@[ order, address ] reading:@"{0} is shipped to {1}" in:editor];
	NSString *billed = [self fact:@[ order, address ] reading:@"{0} is billed to {1}" in:editor];
	NSString *isOf = [self fact:@[ item, kind ] reading:@"{0} is of {1}" in:editor];
	NSString *kept = [self fact:@[ item, shelf ] reading:@"{0} is kept on {1}" in:editor];
	NSString *supplied = [self fact:@[ item, supplier ] reading:@"{0} is supplied by {1}" in:editor];
	NSArray *forRoles = [[editor.model elementWithId:isFor] roles];
	NSArray *ofRoles = [[editor.model elementWithId:isOf] roles];
	NSString *reason = nil;
	NSString *subset = [editor.constraintEditor addSetComparisonConstraint:ORMSubsetConstraint
	                                                             sequences:@[ @[ [forRoles[1] identifier] ], @[ [ofRoles[0] identifier] ] ]
	                                                                reason:&reason];
	XCTAssertNotNil(subset, @"%@", reason);
	[editor.diagramEditor arrangeDiagramInGroups:diagramId];

	ORMDiagram *diagram = [editor.model.diagrams firstObject];
	XCTAssertEqual([[diagram shapesForSubject:order] count], (NSUInteger)1);
	XCTAssertEqual([[diagram shapesForSubject:item] count], (NSUInteger)2, @"its own, and Order's");
	NSRect orders = [self extentOf:[self shapesOf:@[ order, isFor, placed, shipped, billed, customer, address ] on:diagram]];
	NSRect items = [self extentOf:[self shapesOf:@[ kept, supplied, shelf, supplier ] on:diagram]];
	XCTAssertFalse(NSIntersectsRect(orders, items), @"the groups apart: %@ %@", NSStringFromRect(orders), NSStringFromRect(items));
	/* What a line joins is near: Item to Order's fact type, the
	 * constraint to both its fact types (Item's, once more). */
	ORMShape *forShape = [diagram shapeForSubject:isFor];
	NSPoint forAt = NSMakePoint(NSMidX(forShape.bounds), NSMidY(forShape.bounds));
	ORMShape *itemThere = [self shapeOf:item nearest:forAt on:diagram];
	XCTAssertLessThan(hypot(NSMidX(itemThere.bounds) - forAt.x, NSMidY(itemThere.bounds) - forAt.y), 2 * 72.0);
	XCTAssertEqual([[diagram shapesForSubject:isOf] count], (NSUInteger)2);
	ORMShape *constraint = [diagram shapeForSubject:subset];
	NSPoint at = NSMakePoint(NSMidX(constraint.bounds), NSMidY(constraint.bounds));
	for (NSString *fact in @[ isFor, isOf ]) {
		ORMShape *near = [self shapeOf:fact nearest:at on:diagram];
		XCTAssertLessThan(hypot(NSMidX(near.bounds) - at.x, NSMidY(near.bounds) - at.y), 2 * 72.0, @"%@",
		                  [[editor.model elementWithId:fact] name]);
	}
	[self.undoManager undo];
	XCTAssertEqual([[[editor.model.diagrams firstObject] shapesForSubject:item] count], (NSUInteger)1);
}

- (void)testReadingsAreChecked
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *reason = nil;
	XCTAssertNil(([editor.factTypeEditor addFactTypeWithPlayers:@[ person, country ] reading:@"{0} lives" onDiagram:nil
	                                         at:NSZeroPoint reason:&reason]));
	XCTAssertNil(([editor.factTypeEditor addFactTypeWithPlayers:@[ person, country ] reading:@"{0} likes {0}" onDiagram:nil
	                                         at:NSZeroPoint reason:&reason]));
	NSString *fact = [self fact:@[ person, country ] reading:@"{0} lives in {1}" in:editor];
	ORMReading *reading = [[editor.model elementWithId:fact] primaryReading];
	XCTAssertTrue([editor.factTypeEditor setReadingText:@"{0} resides in {1}" of:reading.identifier reason:&reason], @"%@", reason);
	XCTAssertEqualObjects([[[editor.model elementWithId:fact] primaryReading] expandedText], @"Person resides in Country");
	XCTAssertFalse([editor.factTypeEditor setReadingText:@"" of:reading.identifier reason:&reason], @"the last reading went");
}

@end
