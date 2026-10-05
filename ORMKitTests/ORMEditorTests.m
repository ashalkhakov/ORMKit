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
