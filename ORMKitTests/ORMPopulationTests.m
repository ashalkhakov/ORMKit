/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <CoreData/CoreData.h>
#import <ODataService/ODataService.h>

/* Sample populations: written as NORMA writes them, read back, and put in
 * a Core Data store of the mapping. */
@interface ORMPopulationTests : ORMTestCase
@end

@implementation ORMPopulationTests
{
	ORMEditor *_editor;
	NSString *_person, *_country, *_born;
}

- (void)tearDown
{
	_editor = nil;
	[super tearDown];
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

/* One fact or instance at a time, as a table edits them, each instance
 * named as it shows: a fact added by its players' values; a player named
 * anew, the fact replaced, one undo; a fact removed; an instance removed
 * only once nothing has it play a role. */
- (void)testFactsAndInstancesAreEditedOneAtATime
{
	[self addAnnAndBob];
	ORMFactType *born = [_editor.model elementWithId:_born];
	NSString *personRole = [[born.roles firstObject] identifier];
	NSString *countryRole = [[born.roles lastObject] identifier];
	NSString *reason = nil;
	NSString *added = [_editor.populationEditor addFactOf:_born named:@{ personRole: @"3", countryRole: @"NZ" }
	                                               reason:&reason];
	XCTAssertNotNil(added, @"%@", reason);
	born = [_editor.model elementWithId:_born];
	XCTAssertEqual([[born instances] count], 3u);
	XCTAssertNil([_editor.populationEditor addFactOf:_born named:@{ personRole: @"4" } reason:&reason]);
	XCTAssertEqualObjects(reason, @"Name the Country too.");

	/* Ann born in New Zealand instead: the fact replaced, NZ reused. */
	ORMFactInstance *ann = [[born instances] firstObject];
	NSString *edited = [_editor.populationEditor setPlayer:@"NZ" ofRole:countryRole inFact:ann.identifier reason:&reason];
	XCTAssertNotNil(edited, @"%@", reason);
	born = [_editor.model elementWithId:_born];
	ORMFactInstance *now = [_editor.model elementWithId:edited];
	XCTAssertEqualObjects([[now.instancesByRole objectForKey:countryRole] displayText], @"'NZ'");
	XCTAssertEqualObjects([[now.instancesByRole objectForKey:personRole] displayText], @"1");
	XCTAssertEqual([[[_editor.model elementWithId:_country] instances] count], 2u);
	[self.undoManager undo];
	XCTAssertNotNil([_editor.model elementWithId:ann.identifier]);
	XCTAssertNil([_editor.model elementWithId:edited]);

	/* Person 3 plays in a fact: not removed until it is gone. */
	ORMObjectType *person = [_editor.model elementWithId:_person];
	ORMInstance *third = nil;
	for (ORMInstance *instance in [person instances]) {
		if ([[instance displayText] isEqualToString:@"3"]) {
			third = instance;
		}
	}
	XCTAssertFalse([_editor.populationEditor removeInstance:third.identifier reason:&reason]);
	XCTAssertEqualObjects(reason, @"It plays a role in 1 fact: remove it first.");
	XCTAssertTrue([_editor.populationEditor removeFact:added reason:&reason], @"%@", reason);
	XCTAssertEqual([[[_editor.model elementWithId:_born] instances] count], 2u);
	XCTAssertTrue([_editor.populationEditor removeInstance:third.identifier reason:&reason], @"%@", reason);
	XCTAssertEqual([[[_editor.model elementWithId:_person] instances] count], 2u);
	/* What identified it is a value no one has now: removed in turn. */
	ORMObjectType *ids = [[_editor.model elementWithId:_person] referenceModeValueType];
	ORMInstance *three = [[ids instances] lastObject];
	XCTAssertEqualObjects(three.value, @"3");
	XCTAssertTrue([_editor.populationEditor removeInstance:three.identifier reason:&reason], @"%@", reason);
	/* Added by name. */
	XCTAssertNotNil([_editor.populationEditor addInstanceOf:_country named:@"FR" reason:&reason], @"%@", reason);
	XCTAssertEqual([[[_editor.model elementWithId:_country] instances] count], 3u);
	XCTAssertTrue([[[ORMPopulationChecker alloc] initWithModel:_editor.model].violations count] == 0);
}

/* What the model has already is not added again: an instance, a fact, or
 * a fact edited into another's twin. An instance is renamed: an entity by
 * its identifying value, the facts it plays in kept, the value no longer
 * used gone; a value in place; never to another's name. */
- (void)testDuplicatesAreRefusedAndInstancesRenamed
{
	[self addAnnAndBob];
	ORMPopulationEditor *editor = _editor.populationEditor;
	ORMFactType *born = [_editor.model elementWithId:_born];
	NSString *personRole = [[born.roles firstObject] identifier];
	NSString *countryRole = [[born.roles lastObject] identifier];
	NSString *reason = nil;
	XCTAssertNil([editor addInstanceOf:_country named:@"AU" reason:&reason]);
	XCTAssertEqualObjects(reason, @"There is already a Country AU.");
	XCTAssertNil([editor addInstanceOf:_person named:@"2" reason:&reason]);
	XCTAssertEqualObjects(reason, @"There is already a Person 2.");
	XCTAssertNil(([editor addFactOf:_born named:@{ personRole: @"1", countryRole: @"AU" } reason:&reason]));
	XCTAssertEqualObjects(reason, @"That fact is there already.");
	XCTAssertEqual([[[_editor.model elementWithId:_born] instances] count], 2u);

	/* Ann's fact edited: as it was, nothing changes; into Bob's, refused. */
	ORMFactInstance *ann = [[[_editor.model elementWithId:_born] instances] firstObject];
	XCTAssertEqualObjects([editor setPlayer:@"AU" ofRole:countryRole inFact:ann.identifier reason:&reason], ann.identifier);
	XCTAssertNil([editor setPlayer:@"2" ofRole:personRole inFact:ann.identifier reason:&reason]);
	XCTAssertEqualObjects(reason, @"That fact is there already.");
	XCTAssertEqual([[[_editor.model elementWithId:_born] instances] count], 2u);

	/* Person 1 is Person 7 now, still born in AU; the id 1 is gone. */
	ORMInstance *first = [[(ORMObjectType *)[_editor.model elementWithId:_person] instances] firstObject];
	XCTAssertEqualObjects([editor nameOf:first], @"1");
	XCTAssertTrue([editor renameInstance:first.identifier to:@"7" reason:&reason], @"%@", reason);
	first = [_editor.model elementWithId:first.identifier];
	XCTAssertEqualObjects([editor nameOf:first], @"7");
	ann = [_editor.model elementWithId:ann.identifier];
	XCTAssertEqualObjects([editor nameOf:[ann.instancesByRole objectForKey:personRole]], @"7");
	ORMObjectType *ids = [[_editor.model elementWithId:_person] referenceModeValueType];
	XCTAssertEqualObjects([[[ids instances] valueForKey:@"value"] sortedArrayUsingSelector:@selector(compare:)], (@[ @"2", @"7" ]));
	XCTAssertFalse([editor renameInstance:first.identifier to:@"2" reason:&reason]);
	XCTAssertEqualObjects(reason, @"There is already a Person 2.");
	XCTAssertTrue([editor renameInstance:first.identifier to:@"7" reason:&reason]);
	[self.undoManager undo];
	XCTAssertEqualObjects([editor nameOf:[_editor.model elementWithId:first.identifier]], @"1");

	/* A value renamed in place: the country it identifies with it. */
	ORMObjectType *codes = [[_editor.model elementWithId:_country] referenceModeValueType];
	ORMInstance *au = [[codes instances] firstObject];
	XCTAssertTrue([editor renameInstance:au.identifier to:@"AT" reason:&reason], @"%@", reason);
	XCTAssertEqualObjects([editor nameOf:[[(ORMObjectType *)[_editor.model elementWithId:_country] instances] firstObject]], @"AT");
	XCTAssertTrue([editor addInstanceOf:_country named:@"AU" reason:&reason] != nil, @"%@", reason);
	XCTAssertFalse([editor renameInstance:au.identifier to:@"AU" reason:&reason]);
	XCTAssertEqualObjects(reason, @"There is already a Country_code AU.");

	/* A fact a file has with a role unplayed: editing the other player is
	 * refused, and the fact stays, with no step to undo. */
	ORMSamplePopulation *partial = [[ORMSamplePopulation alloc] init];
	NSString *lone = [partial factOf:_born players:@{ personRole: [self instanceOf:_person value:@"9" in:partial] }];
	XCTAssertTrue([editor addPopulation:partial reason:&reason], @"%@", reason);
	NSUInteger facts = [[[_editor.model elementWithId:_born] instances] count];
	[self.undoManager removeAllActions];
	XCTAssertNil([editor setPlayer:@"8" ofRole:personRole inFact:lone reason:&reason]);
	XCTAssertEqualObjects(reason, @"Name the Country too.");
	XCTAssertNotNil([_editor.model elementWithId:lone]);
	XCTAssertEqual([[[_editor.model elementWithId:_born] instances] count], facts);
	XCTAssertFalse([self.undoManager canUndo]);
}

/* A fact of an objectified fact type is an instance of the type that
 * objectifies it: added with the fact, and removed with it. What a removal
 * empties goes too, as NORMA writes no empty Instances or RoleInstances. */
- (void)testAnObjectifiedFactComesAndGoesWithItsInstance
{
	NSString *reason = nil;
	NSString *birth = [_editor.factTypeEditor objectifyFactType:_born named:@"Birth" reason:&reason];
	XCTAssertNotNil(birth, @"%@", reason);
	ORMFactType *born = [_editor.model elementWithId:_born];
	NSString *personRole = [[born.roles firstObject] identifier];
	NSString *countryRole = [[born.roles lastObject] identifier];
	NSString *fact = [_editor.populationEditor addFactOf:_born named:@{ personRole: @"1", countryRole: @"AU" } reason:&reason];
	XCTAssertNotNil(fact, @"%@", reason);
	ORMObjectType *objectifying = [(ORMFactType *)[_editor.model elementWithId:_born] objectifyingType];
	XCTAssertEqual([[objectifying instances] count], 1u);
	XCTAssertEqualObjects([[[[objectifying instances] firstObject] objectifiedInstance] identifier], fact);
	XCTAssertTrue([[[ORMPopulationChecker alloc] initWithModel:_editor.model].violations count] == 0,
	              @"%@", [[[ORMPopulationChecker alloc] initWithModel:_editor.model].violations valueForKey:@"text"]);

	XCTAssertTrue([_editor.populationEditor removeFact:fact reason:&reason], @"%@", reason);
	objectifying = [(ORMFactType *)[_editor.model elementWithId:_born] objectifyingType];
	XCTAssertEqual([[objectifying instances] count], 0u);
	born = [_editor.model elementWithId:_born];
	XCTAssertEqual([ORMChildren(born.element, ORMCoreNamespace, @"Instances") count], 0u);
	XCTAssertEqual([ORMChildren(objectifying.element, ORMCoreNamespace, @"Instances") count], 0u);
	for (ORMRole *role in born.roles) {
		XCTAssertEqual([ORMChildren(role.element, ORMCoreNamespace, @"RoleInstances") count], 0u);
	}
}

/* Strongly intransitive: one who supervises another reaches them by no
 * longer chain either. A chain of three that skips a step is broken; one of
 * two only is what plain intransitivity forbids too. */
- (void)testAStronglyIntransitiveRingIsCheckedOverLongChains
{
	NSString *diagram = [[_editor.model.diagrams firstObject] identifier];
	NSString *reason = nil;
	NSString *supervises = [_editor.factTypeEditor addFactTypeWithPlayers:@[ _person, _person ] reading:@"{0} supervises {1}"
	                                                            onDiagram:diagram at:ORMAutomaticPlacement reason:&reason];
	XCTAssertNotNil(supervises, @"%@", reason);
	NSArray *roles = [[_editor.model elementWithId:supervises] roles];
	NSArray *both = @[ [roles[0] identifier], [roles[1] identifier] ];
	XCTAssertNotNil([_editor.constraintEditor addUniquenessConstraintOverRoles:both reason:&reason], @"%@", reason);
	XCTAssertNotNil([_editor.constraintEditor addRingConstraint:ORMRingStronglyIntransitive overRoles:both reason:&reason],
	                @"%@", reason);
	NSArray *chain = @[ @[ @"1", @"2" ], @[ @"2", @"3" ], @[ @"3", @"4" ] ];
	for (NSArray *pair in chain) {
		XCTAssertNotNil(([_editor.populationEditor addFactOf:supervises named:@{ both[0]: pair[0], both[1]: pair[1] }
		                                              reason:&reason]), @"%@", reason);
	}
	NSArray *(^broken)(void) = ^NSArray * {
		NSMutableArray *texts = [NSMutableArray array];
		for (ORMPopulationViolation *violation in [[[ORMPopulationChecker alloc] initWithModel:self->_editor.model] violations]) {
			if (violation.constraint.kind == ORMRingConstraint) {
				[texts addObject:violation.text];
			}
		}
		return texts;
	};
	XCTAssertEqual([broken() count], 0u, @"%@", broken());
	/* 1 supervises 4, whom 1 reaches through 2 and 3. */
	XCTAssertNotNil(([_editor.populationEditor addFactOf:supervises named:@{ both[0]: @"1", both[1]: @"4" } reason:&reason]),
	                @"%@", reason);
	XCTAssertEqual([broken() count], 1u, @"%@", broken());
}

/* The fact type with this primary reading. */
- (ORMFactType *)factReading:(NSString *)text in:(ORMModel *)model
{
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		if ([[[fact primaryReading] expandedText] isEqualToString:text]) {
			return fact;
		}
	}
	return nil;
}

/* The node a new step from the node reaches. */
- (NSString *)step:(ORMQueryEditor *)queries from:(NSString *)nodeId through:(NSString *)roleId in:(NSString *)queryId
                in:(ORMEditor *)editor
{
	NSString *reason = nil;
	NSString *step = [queries addStepTo:nodeId through:roleId reason:&reason];
	XCTAssertNotNil(step, @"%@", reason);
	for (ORMQueryNode *node in [[ORMQuery queryWithId:queryId inModel:editor.model] nodes]) {
		if ([node.step.identifier isEqualToString:step]) {
			return node.identifier;
		}
	}
	return nil;
}

/* Derived facts in a sample population (docs/DERIVATION.md): the Company
 * sample's "Employee reports to Employee", from the branch one works for
 * and the other heads, derived from its population as its instances;
 * checked against the constraints on the derived fact type; an asserted
 * fact of a fully derived one, and stored ones out of date, said wrong. */
- (void)testDerivedFactsAreCheckedAsTheSamplesFacts
{
	NSString *root = [[[[self fixturePath:@"x"] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]
		stringByDeletingLastPathComponent];
	NSData *data = [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"Samples/Company.orm"]];
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:self.undoManager];
	ORMModel *model = editor.model;
	NSString *employee = [[model objectTypeNamed:@"Employee"] identifier];
	ORMFactType *worksFor = [self factReading:@"Employee works for Branch" in:model];
	ORMFactType *heads = [self factReading:@"Employee heads Branch" in:model];
	XCTAssertNotNil(worksFor);
	XCTAssertNotNil(heads);
	NSString *diagram = [[model.diagrams firstObject] identifier];
	NSString *reason = nil;
	NSString *reports = [editor.factTypeEditor addFactTypeWithPlayers:@[ employee, employee ] reading:@"{0} reports to {1}"
	                                                        onDiagram:diagram at:ORMAutomaticPlacement reason:&reason];
	XCTAssertNotNil(reports, @"%@", reason);
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	NSString *q = [queries addQueryNamed:@"Reporting" from:employee reason:NULL];
	NSString *start = [ORMQuery queryWithId:q inModel:editor.model].root.identifier;
	NSString *branch = [self step:queries from:start through:[[worksFor.roles firstObject] identifier] in:q in:editor];
	NSString *head = [self step:queries from:branch through:[[heads.roles lastObject] identifier] in:q in:editor];
	[queries setProjected:YES ofNode:head];
	XCTAssertTrue([queries setKind:ORMQueryDerivation ofQuery:q reason:&reason], @"%@", reason);
	XCTAssertTrue([queries setDerivedFactType:reports ofQuery:q reason:&reason], @"%@", reason);

	/* One fact for each employee whose branch has a head, its players the
	 * population's own instances. */
	ORMDeriver *deriver = [[ORMDeriver alloc] initWithModel:editor.model];
	NSArray *derived = [[deriver derivedFacts] objectForKey:reports];
	XCTAssertEqualObjects([deriver notes], @[]);
	XCTAssertGreaterThan([derived count], 3u);
	for (ORMDerivedFact *fact in derived) {
		XCTAssertTrue([fact isOfInstances], @"%@", fact.players);
	}
	NSArray *(^texts)(void) = ^NSArray * {
		return [[[[ORMPopulationChecker alloc] initWithModel:editor.model] violations] valueForKey:@"text"];
	};
	NSArray *before = texts();
	/* Each employee reports to one head at most: holds. Each head is
	 * reported to by one employee at most: does not, being derived. */
	NSArray *roles = [[editor.model elementWithId:reports] roles];
	XCTAssertNotNil([editor.constraintEditor addUniquenessConstraintOverRoles:@[ [roles[0] identifier] ] reason:&reason]);
	XCTAssertEqual([texts() count], [before count], @"%@", texts());
	XCTAssertNotNil([editor.constraintEditor addUniquenessConstraintOverRoles:@[ [roles[1] identifier] ] reason:&reason]);
	XCTAssertGreaterThan([texts() count], [before count], @"%@", texts());

	/* Asserted, though fully derived. */
	ORMDerivedFact *some = [derived firstObject];
	NSMutableDictionary *named = [NSMutableDictionary dictionary];
	for (NSString *roleId in some.players) {
		[named setObject:[editor.populationEditor nameOf:[some.players objectForKey:roleId]] forKey:roleId];
	}
	XCTAssertNotNil([editor.populationEditor addFactOf:reports named:named reason:&reason], @"%@", reason);
	XCTAssertTrue([texts() containsObject:@"\"Employee reports to Employee\" is derived: its facts are not asserted."],
	              @"%@", texts());
	/* Stored, with one fact of many written: out of date. */
	XCTAssertTrue([editor.factTypeEditor setDerivationPartial:NO stored:YES of:reports reason:&reason], @"%@", reason);
	NSString *stale = [NSString stringWithFormat:@"\"Employee reports to Employee\" is stored out of date: %lu facts its "
	                                             @"rule derives are missing, 0 are not derived.",
	                                             (unsigned long)[derived count] - 1];
	XCTAssertTrue([texts() containsObject:stale], @"%@", texts());

	/* Brought up to date: each derived fact stored, once. */
	XCTAssertTrue([editor.populationEditor bringStoredDerivationsUpToDate:&reason], @"%@", reason);
	XCTAssertEqual([[(ORMFactType *)[editor.model elementWithId:reports] instances] count], [derived count]);
	XCTAssertFalse([[texts() componentsJoinedByString:@"\n"] containsString:@"stored out of date"], @"%@", texts());
	/* A new employee of a branch with a head: their report is stored with
	 * the edit, and undone with it. */
	heads = [self factReading:@"Employee heads Branch" in:editor.model];
	worksFor = [self factReading:@"Employee works for Branch" in:editor.model];
	ORMFactInstance *headed = [[heads instances] firstObject];
	ORMInstance *ofBranch = [headed.instancesByRole objectForKey:[[heads.roles lastObject] identifier]];
	NSDictionary *joins = @{ [[worksFor.roles firstObject] identifier]: @"999",
		                     [[worksFor.roles lastObject] identifier]: [editor.populationEditor nameOf:ofBranch] };
	/* Counted now: the projection is read again after the edit. */
	NSUInteger working = [[worksFor instances] count];
	XCTAssertNotNil([editor.populationEditor addFactOf:worksFor.identifier named:joins reason:&reason], @"%@", reason);
	XCTAssertEqual([[(ORMFactType *)[editor.model elementWithId:reports] instances] count], [derived count] + 1);
	[self.undoManager undo];
	XCTAssertEqual([[(ORMFactType *)[editor.model elementWithId:reports] instances] count], [derived count]);
	XCTAssertEqual([[[self factReading:@"Employee works for Branch" in:editor.model] instances] count], working);
}

/* NORMA's own rule (docs/DERIVATION.md): CinemaTickets derives "Session
 * has Seat" by a role path, the session's cinema's rows' seats. Read as a
 * query, its projections not in outline order, it derives each seat of each
 * session's cinema from a generated population; a query through the fact
 * type finds the same. */
- (void)testNormasRulesDeriveAsQueriesDo
{
	NSData *data = [NSData dataWithContentsOfFile:[self fixturePath:@"ActiveFacts/CinemaTickets.orm"]];
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
	[editor.populationEditor removePopulation];
	ORMPopulationGenerator *generator = [[ORMPopulationGenerator alloc] initWithModel:editor.model];
	NSString *reason = nil;
	XCTAssertTrue([editor.populationEditor addPopulation:[generator population] reason:&reason], @"%@", reason);
	ORMModel *model = editor.model;
	ORMFactType *hasSeat = [model elementWithId:@"_90E3EEDA-78D3-4EF4-86E2-70894A2D1104"];
	ORMQuery *rule = nil;
	for (ORMQuery *query in [ORMQuery derivationsInModel:model]) {
		rule = query.derivedFactType == hasSeat ? query : rule;
	}
	XCTAssertNotNil(rule);
	XCTAssertEqualObjects(rule.name, @"SessionHasSeat");
	XCTAssertEqualObjects([[rule derivedColumns] valueForKeyPath:@"objectType.name"], (@[ @"Session", @"Seat" ]));
	XCTAssertNil([ORMQuery derivationOf:hasSeat inModel:model], @"not a query of the document");

	/* Rows and seats are entities of their own: an application's store
	 * absorbs a Row into its Seats, and joins on it are not planned. */
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:editor];
	[mappings setStyle:ORMStyleEntities ofMapping:[mappings addCoreDataMappingNamed:@"Test" path:@"Test.xcdatamodeld"]];
	model = editor.model;
	hasSeat = [model elementWithId:hasSeat.identifier];

	/* Each seat of each session's cinema: a row's cinema, a seat's row,
	 * what identifies them. */
	ORMFactType *session = [model elementWithId:@"_6C4EA5E7-22CD-49A2-80F0-E024D2014110"];
	NSString *rowsCinema = @"_F5EE5A4F-2B2B-4A86-A513-3E7125DCAFC2";
	NSString *seatsRow = @"_D52FD4FD-18B9-4D0C-8BA2-276E6D542133";
	ORMObjectType *cinema = [model objectTypeNamed:@"Cinema"];
	NSMutableSet *expected = [NSMutableSet set];
	for (ORMFactInstance *each in [session instances]) {
		ORMInstance *at = nil;
		for (ORMRole *role in session.roles) {
			at = role.player == cinema ? [each.instancesByRole objectForKey:role.identifier] : at;
		}
		for (ORMInstance *row in [[model objectTypeNamed:@"Row"] instances]) {
			if ([[row identifyingInstancesByRole] objectForKey:rowsCinema] != at) {
				continue;
			}
			for (ORMInstance *seat in [[model objectTypeNamed:@"Seat"] instances]) {
				if ([[seat identifyingInstancesByRole] objectForKey:seatsRow] == row) {
					[expected addObject:@[ each.identifier, seat.identifier ]];
				}
			}
		}
	}
	XCTAssertGreaterThan([expected count], 0u);
	ORMDeriver *deriver = [[ORMDeriver alloc] initWithModel:model];
	NSArray *derived = [[deriver derivedFacts] objectForKey:hasSeat.identifier];
	XCTAssertEqualObjects([deriver notes], @[]);
	NSMutableSet *found = [NSMutableSet set];
	NSArray *roles = [hasSeat visibleRoles];
	for (ORMDerivedFact *fact in derived) {
		XCTAssertTrue([fact isOfInstances], @"%@", fact.players);
		ORMInstance *of = [fact.players objectForKey:[roles[0] identifier]];
		[found addObject:@[ [[of objectifiedInstance] identifier] ?: @"?",
		                    [[fact.players objectForKey:[roles[1] identifier]] identifier] ]];
	}
	XCTAssertEqualObjects(found, expected);

	/* A query from Session through it: its rule put in its place. */
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	NSString *q = [queries addQueryNamed:@"Seats" from:[[roles[0] player] identifier] reason:NULL];
	NSString *start = [ORMQuery queryWithId:q inModel:editor.model].root.identifier;
	NSString *seat = [self step:queries from:start through:[roles[0] identifier] in:q in:editor];
	[queries setProjected:YES ofNode:seat];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc]
		initWithModel:editor.model
		      mapping:[[ORMCoreDataMapping mappingsOfDocument:editor.document] firstObject]];
	ORMQueryPlan *plan = [planner planForQuery:[ORMQuery queryWithId:q inModel:editor.model]];
	XCTAssertEqualObjects(plan.notes, @[]);
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:editor.model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:store.managedObjectModel];
	__block ORMQueryResult *result = nil;
	[context performBlockAndWait:^{
		result = [interpreter executePlan:plan inContext:context error:NULL];
	}];
	XCTAssertEqual([[NSSet setWithArray:result.rows] count], [expected count], @"%@", [plan text]);
}

/* An entity type identified by the facts it plays in, not one value: the
 * roles of its preferred identifier and their players. */
- (NSString *)entity:(NSString *)name identifiedBy:(NSArray<NSString *> *)players readings:(NSArray<NSString *> *)readings
{
	NSString *diagram = [[_editor.model.diagrams firstObject] identifier];
	NSString *reason = nil;
	NSString *type = [_editor.objectTypeEditor addEntityTypeNamed:name referenceMode:nil kind:ORMReferenceModePopular
	                                                    onDiagram:diagram at:ORMAutomaticPlacement reason:&reason];
	XCTAssertNotNil(type, @"%@", reason);
	NSMutableArray *identifying = [NSMutableArray array];
	for (NSUInteger i = 0; i < [players count]; i++) {
		NSString *fact = [_editor.factTypeEditor addFactTypeWithPlayers:@[ type, players[i] ] reading:readings[i]
		                                                      onDiagram:diagram at:ORMAutomaticPlacement reason:&reason];
		XCTAssertNotNil(fact, @"%@", reason);
		NSArray *roles = [[_editor.model elementWithId:fact] roles];
		XCTAssertTrue([_editor.constraintEditor setUnique:YES role:[roles[0] identifier] reason:&reason], @"%@", reason);
		XCTAssertTrue([_editor.constraintEditor setMandatory:YES role:[roles[0] identifier] reason:&reason], @"%@", reason);
		[identifying addObject:[roles[1] identifier]];
	}
	NSString *unique = [_editor.constraintEditor addUniquenessConstraintOverRoles:identifying reason:&reason];
	XCTAssertNotNil(unique, @"%@", reason);
	XCTAssertTrue([_editor.constraintEditor setPreferredIdentifier:unique reason:&reason], @"%@", reason);
	return type;
}

/* An instance identified by several values is named by them, in its
 * preferred identifier's order and separated by commas, a part named so in
 * turn in parentheses; the name reads back as the same instance. */
- (void)testInstancesIdentifiedBySeveralValuesAreNamed
{
	NSString *diagram = [[_editor.model.diagrams firstObject] identifier];
	NSString *building = [_editor.objectTypeEditor addEntityTypeNamed:@"Building" referenceMode:@"nr"
	                                                            kind:ORMReferenceModePopular onDiagram:diagram
	                                                              at:ORMAutomaticPlacement reason:NULL];
	NSString *roomNr = [_editor.objectTypeEditor addValueTypeNamed:@"RoomNr" dataType:nil onDiagram:diagram
	                                                            at:ORMAutomaticPlacement reason:NULL];
	NSString *room = [self entity:@"Room" identifiedBy:@[ building, roomNr ] readings:@[ @"{0} is in {1}", @"{0} has {1}" ]];
	ORMPopulationEditor *editor = _editor.populationEditor;
	NSArray *roles = [editor compositeRolesOf:room];
	XCTAssertEqual([roles count], 2u);
	XCTAssertEqualObjects([[roles[0] player] name], @"Building");

	NSString *reason = nil;
	NSString *added = [editor addInstanceOf:room named:@"1, 101" reason:&reason];
	XCTAssertNotNil(added, @"%@", reason);
	ORMInstance *first = [_editor.model elementWithId:added];
	XCTAssertEqualObjects([editor nameOf:first], @"1, 101");
	XCTAssertEqual([[[_editor.model elementWithId:building] instances] count], 1u);
	/* Named again, spaced otherwise: the same one, not added twice. */
	XCTAssertNil([editor addInstanceOf:room named:@" 1 ,101 " reason:&reason]);
	XCTAssertEqualObjects(reason, @"There is already a Room 1, 101.");
	XCTAssertEqual([[[_editor.model elementWithId:room] instances] count], 1u);
	XCTAssertNil([editor addInstanceOf:room named:@"1" reason:&reason]);
	XCTAssertEqualObjects(reason, @"Room is identified by Building, RoomNr: name each, separated by commas.");

	/* By role, as a table's columns name it; a comma quoted. */
	added = [editor addInstanceOf:room namedByRole:@{ [roles[0] identifier]: @"2", [roles[1] identifier]: @"A, east" }
	                       reason:&reason];
	XCTAssertNotNil(added, @"%@", reason);
	NSString *name = [editor nameOf:[_editor.model elementWithId:added]];
	XCTAssertEqualObjects(name, @"2, 'A, east'");
	XCTAssertNil([editor addInstanceOf:room named:name reason:&reason]);
	XCTAssertEqual([[[_editor.model elementWithId:room] instances] count], 2u);
	XCTAssertNil([editor addInstanceOf:room namedByRole:@{ [roles[0] identifier]: @"3" } reason:&reason]);
	XCTAssertEqualObjects(reason, @"Name the RoomNr too.");
	/* A part quoted for its spaces keeps them. */
	added = [editor addInstanceOf:room named:@"3, ' 7 '" reason:&reason];
	XCTAssertNotNil(added, @"%@", reason);
	XCTAssertEqualObjects([editor nameOf:[_editor.model elementWithId:added]], @"3, ' 7 '");
	XCTAssertTrue([editor removeInstance:added reason:&reason], @"%@", reason);
	XCTAssertNil([editor addInstanceOf:room named:@"2, 'A, east'" reason:&reason]);
	XCTAssertEqualObjects(reason, @"There is already a Room 2, 'A, east'.");
	/* One part renamed; into another's name, refused. */
	XCTAssertTrue([editor renameInstance:first.identifier role:[roles[1] identifier] to:@"102" reason:&reason], @"%@", reason);
	XCTAssertEqualObjects([editor nameOf:[_editor.model elementWithId:first.identifier]], @"1, 102");
	XCTAssertFalse([editor renameInstance:first.identifier to:@"2, 'A, east'" reason:&reason]);
	XCTAssertEqualObjects(reason, @"There is already a Room 2, 'A, east'.");
	XCTAssertTrue([editor renameInstance:first.identifier to:@"1, 101" reason:&reason], @"%@", reason);

	/* A desk is identified by its room and its number: nested. */
	NSString *deskNr = [_editor.objectTypeEditor addValueTypeNamed:@"DeskNr" dataType:nil onDiagram:diagram
	                                                            at:ORMAutomaticPlacement reason:NULL];
	NSString *desk = [self entity:@"Desk" identifiedBy:@[ room, deskNr ] readings:@[ @"{0} is in {1}", @"{0} has {1}" ]];
	added = [editor addInstanceOf:desk named:@"(1, 101), 3" reason:&reason];
	XCTAssertNotNil(added, @"%@", reason);
	XCTAssertEqualObjects([editor nameOf:[_editor.model elementWithId:added]], @"(1, 101), 3");
	XCTAssertEqual([[[_editor.model elementWithId:room] instances] count], 2u);

	/* A fact's player named so too. */
	NSString *works = [_editor.factTypeEditor addFactTypeWithPlayers:@[ _person, desk ] reading:@"{0} works at {1}"
	                                                       onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	NSArray *workRoles = [[_editor.model elementWithId:works] roles];
	NSString *fact = [editor addFactOf:works named:@{ [workRoles[0] identifier]: @"1", [workRoles[1] identifier]: @"(2, 'A, east'), 9" }
	                            reason:&reason];
	XCTAssertNotNil(fact, @"%@", reason);
	ORMFactInstance *instance = [_editor.model elementWithId:fact];
	XCTAssertEqualObjects([editor nameOf:[instance.instancesByRole objectForKey:[workRoles[1] identifier]]], @"(2, 'A, east'), 9");
	XCTAssertEqual([[[_editor.model elementWithId:room] instances] count], 2u);
	XCTAssertEqual([[[_editor.model elementWithId:desk] instances] count], 2u);
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
	for (NSString *name in @[ @"Company.orm", @"University.orm", @"UMLandORM.orm", @"Customers.orm" ]) {
		[paths addObject:[[samples stringByAppendingPathComponent:@"Samples"] stringByAppendingPathComponent:name]];
	}
	for (NSString *name in [@[ @"StockMate.orm", @"WorkMate.orm" ] arrayByAddingObjectsFromArray:[self activeFactsFixtures]]) {
		[paths addObject:[self fixturePath:name]];
	}
	return paths;
}

/* Every model gets a population that is written, read back and put in the
 * store of its default mapping. All but two break nothing (the samples,
 * StockMate, WorkMate, 27 of the 29 ActiveFacts models); for those two the
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
		/* The graphical constraints: a rule (a constraint query) is no
		 * generator's to meet. */
		NSMutableArray *violations = [NSMutableArray array];
		for (ORMPopulationViolation *violation in [checker violations]) {
			if (violation.rule == nil) {
				[violations addObject:violation.text];
			}
		}
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
	XCTAssertEqualObjects(broken, ([NSSet setWithArray:@[ @"Diplomacy.orm", @"Metamodel.orm" ]]));
}

/* The samples' own populations: each query finds what its paper says, or
 * the sample's README. The first column's distinct values, sorted where the
 * query sorts nothing. */
- (void)testTheSamplesAnswerTheirQueries
{
	NSDictionary *expected = @{
		@"Company.orm": @{ @"Q1": @[ @1, @3 ], @"Q2": @[ @1, @3, @4 ], @"Q3": @[ @102 ], @"Q4": @[ @2 ],
		                   @"Q5": @[ @1, @4 ], @"Payroll": @[ @52, @7 ], @"Polyglots": @[ @1 ],
		                   @"Lives near work": @[ @21 ], @"Workplace": @[ @1, @2, @3, @4, @5, @10, @21 ],
		                   @"Works where": @[ @1, @2, @3, @4, @5, @10, @21 ], @"Branch country": @[ @7, @52, @101, @102 ],
		                   @"Australian branches": @[ @7, @52 ] },
		@"Customers.orm": @{ @"Owing": @[ @1, @2, @3 ], @"Mailing list": @[ @1, @3 ], @"Readers": @[ @"deals", @"news" ] },
		@"University.orm": @{ @"Q1": @[ @430, @715, @720 ], @"Q2": @[ @720 ], @"Q3": @[ @430, @503, @651, @715, @720 ] },
		@"UMLandORM.orm": @{ @"Rooms lacking a facility": @[], @"Coauthored papers": @[ @1 ] },
	};
	for (NSString *path in [self generatedModels]) {
		NSDictionary *answers = [expected objectForKey:[path lastPathComponent]];
		if (answers == nil) {
			continue;
		}
		ORMModel *model = [ORMModel modelOfDocument:ORMParseDocument([NSData dataWithContentsOfFile:path], NULL) reason:NULL];
		/* What breaks a deontic rule is to be told of; nothing alethic. */
		NSMutableArray *alethic = [NSMutableArray array];
		for (ORMPopulationViolation *violation in [[[ORMPopulationChecker alloc] initWithModel:model] violations]) {
			if (!(violation.rule != nil ? violation.rule.isDeontic : violation.constraint.modality == ORMDeontic)) {
				[alethic addObject:violation.text];
			}
		}
		XCTAssertEqualObjects(alethic, @[], @"%@", [path lastPathComponent]);
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
				/* A degree is identified by its code and its university's: the
				 * row has those, not the object. */
				NSMutableSet *degrees = [NSMutableSet set];
				for (NSArray *row in result.rows) {
					if ([row objectAtIndex:1] != [NSNull null]) {
						[degrees addObject:[row objectAtIndex:1]];
					}
				}
				XCTAssertTrue([degrees containsObject:(@[ @"BSc", @"UQ" ])], @"%@", degrees);
				XCTAssertTrue([degrees containsObject:(@[ @"PhD", @"MIT" ])], @"%@", degrees);
				/* The service's rows are the same. */
				ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
				XCTAssertNotNil(odata, @"%@", error);
				ORMQueryODataCursor *cursor = [odata
					cursorWithTransport:[[ODataService alloc] initWithPersistentStoreCoordinator:context.persistentStoreCoordinator
					                                                                 serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]]
					        serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
				NSMutableArray *served = [NSMutableArray array];
				for (NSUInteger guard = 0; guard < 20 && ![cursor atEnd]; guard++) {
					dispatch_semaphore_t done = dispatch_semaphore_create(0);
					[cursor nextPage:3 completion:^(ORMQueryResult *page, NSError *failed) {
						XCTAssertNotNil(page, @"%@", failed);
						[served addObjectsFromArray:page.rows ?: @[]];
						dispatch_semaphore_signal(done);
					}];
					dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC)));
				}
				XCTAssertEqualObjects([NSSet setWithArray:served], [NSSet setWithArray:result.rows], @"%@", [odata requestText]);
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

/* A unary fact as newer NORMA writes it: no fact instance, but the role
 * referred to from the instance playing it (EntityTypeUnaryRoleInstance).
 * Read as a fact of the unary fact type, it is kept in the store as the
 * player's Boolean, true. */
- (void)testAUnaryFactKeptOnItsPlayerIsRead
{
	[self addAnnAndBob];
	NSString *diagram = [[_editor.model.diagrams firstObject] identifier];
	NSString *smokes = [_editor.factTypeEditor addFactTypeWithPlayers:@[ _person ] reading:@"{0} smokes"
	                                                       onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	ORMFactType *fact = [_editor.model elementWithId:smokes];
	ORMRole *role = [[fact visibleRoles] firstObject];
	ORMInstance *ann = nil;
	for (ORMInstance *instance in [(ORMObjectType *)[_editor.model elementWithId:_person] instances]) {
		ann = [[instance displayText] isEqualToString:@"1"] ? instance : ann;
	}
	XCTAssertNotNil(ann);
	NSXMLElement *roleInstances = nil;
	for (NSXMLNode *node in [ann.element children]) {
		roleInstances = [[node localName] isEqualToString:@"RoleInstances"] ? (NSXMLElement *)node : roleInstances;
	}
	XCTAssertNotNil(roleInstances);
	NSXMLElement *unary = [[NSXMLElement alloc] initWithName:@"orm:EntityTypeUnaryRoleInstance" URI:ORMCoreNamespace];
	[unary addAttribute:[NSXMLNode attributeWithName:@"ref" stringValue:role.identifier]];
	[roleInstances addChild:unary];

	NSString *reason = nil;
	ORMModel *model = [ORMModel modelOfDocument:_editor.document reason:&reason];
	XCTAssertNotNil(model, @"%@", reason);
	NSArray *facts = [(ORMFactType *)[model elementWithId:smokes] instances];
	XCTAssertEqual([facts count], 1u);
	ORMFactInstance *read = [facts firstObject];
	XCTAssertEqualObjects([[read.instancesByRole objectForKey:role.identifier] displayText], @"1");
	XCTAssertEqualObjects([[[ORMPopulationChecker alloc] initWithModel:model] violations], @[]);

	ORMCDModel *coreData = [[[ORMCoreDataMapper alloc] initWithModel:model mapping:nil] map];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:model coreData:coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	NSString *flag = nil;
	ORMRole *implicit = nil;
	for (ORMRole *each in fact.roles) {
		implicit = each != role ? each : implicit;
	}
	for (ORMCDAttribute *attribute in [coreData entityNamed:@"Person"].attributes) {
		flag = [attribute.source isEqualToString:implicit.identifier] ? attribute.name : flag;
	}
	XCTAssertNotNil(flag);
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Person"];
	request.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"id" ascending:YES] ];
	NSArray *people = [context executeFetchRequest:request error:&error];
	XCTAssertEqual([people count], 2u);
	XCTAssertTrue([[[people firstObject] valueForKey:flag] boolValue]);
	XCTAssertFalse([[[people lastObject] valueForKey:flag] boolValue], @"Bob does not smoke: no fact says so");
}

/* An objectifying type with an identifier of its own (Orienteering's Entry,
 * by its ID, is where a Person entered a Course of an Event): its instance
 * and its fact are each the other, so they are added together, and neither
 * alone. */
- (void)testAnObjectifyingInstanceWithItsOwnIdentifierIsAddedWithItsFact
{
	NSData *data = [NSData dataWithContentsOfFile:[self fixturePath:@"ActiveFacts/Orienteering.orm"]];
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
	[editor.populationEditor removePopulation];
	ORMObjectType *entry = [editor.model objectTypeNamed:@"Entry"];
	ORMFactType *entered = entry.nestedFactType;
	XCTAssertNotNil(entered);
	NSMutableDictionary *texts = [NSMutableDictionary dictionary];
	for (ORMRole *role in [entered visibleRoles]) {
		NSArray *parts = [editor.populationEditor compositeRolesOf:role.player.identifier];
		NSMutableArray *values = [NSMutableArray array];
		for (NSUInteger k = 0; k < MAX([parts count], 1u); k++) {
			[values addObject:[NSString stringWithFormat:@"%lu", (unsigned long)k + 1]];
		}
		[texts setObject:[values componentsJoinedByString:@", "] forKey:role.identifier];
	}
	NSString *reason = nil;
	XCTAssertNil([editor.populationEditor addFactOf:entered.identifier named:texts reason:&reason]);
	XCTAssertEqualObjects(reason, @"Each such fact is objectified by Entry, identified by its own Entry ID: add the Entry "
	                              @"with its fact.");
	XCTAssertNil([editor.populationEditor addInstanceOf:entry.identifier named:@"7" reason:&reason]);
	XCTAssertTrue([reason hasPrefix:@"Each Entry is a fact of "], @"%@", reason);
	NSString *made = [editor.populationEditor addInstanceOf:entry.identifier named:@"7" objectifying:texts reason:&reason];
	XCTAssertNotNil(made, @"%@", reason);
	ORMInstance *instance = [editor.model elementWithId:made];
	XCTAssertEqualObjects([editor.populationEditor nameOf:instance], @"7");
	ORMFactInstance *fact = [instance objectifiedInstance];
	XCTAssertEqual(fact.factType, [editor.model elementWithId:entered.identifier]);
	XCTAssertEqual([fact.instancesByRole count], [[entered visibleRoles] count]);
	XCTAssertEqual([[(ORMFactType *)[editor.model elementWithId:entered.identifier] instances] count], 1u);
	/* The same again: there is one. */
	XCTAssertNil([editor.populationEditor addInstanceOf:entry.identifier named:@"8" objectifying:texts reason:&reason]);
	XCTAssertEqualObjects(reason, @"That fact is there already.");
}

@end
