/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <ORMKit/ORMKit.h>
#include <stdio.h>

/* The schemas of Halpin's papers, our own models of them, with the papers'
 * queries: what Samples/Company.orm, University.orm and UMLandORM.orm are
 * made by (Samples/README.md says which figures). Each is built through
 * ORMEditor and its diagrams laid out by arrangeDiagram:.
 *
 *   xcodebuild -workspace ORMKit.xcworkspace -scheme ORMKit -derivedDataPath /tmp/ormkit build
 *   P=/tmp/ormkit/Build/Products/Debug
 *   clang -fobjc-arc -fmodules -F$P -framework ORMKit -Wl,-rpath,$P Tools/fixtures/halpin.m -o /tmp/halpin
 *   /tmp/halpin Samples */

static int failures;

static void
check(BOOL ok, const char *what)
{
	if (!ok) {
		failures++;
		fprintf(stderr, "FAILED %s\n", what);
	}
}

#define CHECK(e, ...) check((e), #e)
#define REFUSED(e, ...) check(!(e), "refused: " #e)
@interface Builder : NSObject
{
	ORMEditor *_editor;
	NSString *_diagram;
	NSMutableDictionary<NSString *, NSArray<NSString *> *> *_facts;
}
@end

@implementation Builder

- (instancetype)initNamed:(NSString *)name
{
	if ((self = [super init])) {
		_editor = [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:name] undoManager:nil];
		_diagram = [[_editor.model.diagrams firstObject] identifier];
		_facts = [NSMutableDictionary dictionary];
	}
	return self;
}

- (void)buildCompany
{
	_facts = [NSMutableDictionary dictionary];
	NSString *employee = [self entity:@"Employee" mode:@"nr" numeric:YES];
	NSString *branch = [self entity:@"Branch" mode:@"nr" numeric:YES];
	NSString *car = [self entity:@"Car" mode:@"regnr" numeric:NO];
	NSString *color = [self entity:@"Color" mode:@"name" numeric:NO];
	NSString *model = [self entity:@"CarModel" mode:@"name" numeric:NO];
	NSString *language = [self entity:@"Language" mode:@"name" numeric:NO];
	NSString *country = [self entity:@"Country" mode:@"name" numeric:NO];
	NSString *city = [self entity:@"City" mode:nil numeric:NO];
	NSString *state = [self entity:@"State" mode:nil numeric:NO];
	NSString *salary = [self entity:@"Salary" mode:@"usd" numeric:YES];
	NSString *rank = [self entity:@"Rank" mode:@"nr" numeric:YES];
	NSString *year = [self entity:@"Year" mode:@"AD" numeric:YES];
	NSString *name = [self value:@"EmployeeName" numeric:NO];
	NSString *phone = [self value:@"PhoneNr" numeric:NO];
	NSString *cityname = [self value:@"Cityname" numeric:NO];
	NSString *statecode = [self value:@"Statecode" numeric:NO];

	[self fact:@"hasName" players:@[ employee, name ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1!"];
	NSArray *main = [self fact:@"hasMainPhone" players:@[ employee, phone ] reading:@"{0} has main- {1}" inverse:nil
	                uniqueness:@"11"];
	NSArray *other = [self fact:@"hasOtherPhone" players:@[ employee, phone ] reading:@"{0} has other- {1}" inverse:nil
	                 uniqueness:@"*"];
	[_editor.constraintEditor addSetComparisonConstraint:ORMExclusionConstraint
	                          sequences:@[ @[ [main lastObject] ], @[ [other lastObject] ] ]
	                             reason:NULL];
	[_editor.constraintEditor addSetComparisonConstraint:ORMSubsetConstraint
	                          sequences:@[ @[ [other firstObject] ], @[ [main firstObject] ] ]
	                             reason:NULL];
	NSArray *reports = [self fact:@"reportsTo" players:@[ employee, employee ] reading:@"{0} reports to {1}"
	                      inverse:@"{0} supervises {1}" uniqueness:@"1"];
	[_editor.constraintEditor addRingConstraint:ORMRingAcyclic overRoles:reports reason:NULL];
	[self fact:@"earns" players:@[ employee, salary ] reading:@"{0} earns {1}" inverse:@"{0} is earned by {1}"
	    uniqueness:@"1!"];
	[self fact:@"drives" players:@[ employee, car ] reading:@"{0} drives {1}" inverse:@"{0} is driven by {1}"
	    uniqueness:@"*"];
	/* Not in figure 1: ConQuer-II's Q5 asks it. */
	[self fact:@"owns" players:@[ employee, car ] reading:@"{0} owns {1}" inverse:@"{0} is owned by {1}"
	    uniqueness:@"*"];
	[self fact:@"carColor" players:@[ car, color ] reading:@"{0} has {1}" inverse:nil uniqueness:@"*"];
	[self fact:@"carModel" players:@[ car, model ] reading:@"{0} is of {1}" inverse:nil uniqueness:@"1!"];
	[self fact:@"speaks" players:@[ employee, language ] reading:@"{0} speaks {1}" inverse:@"{0} is spoken by {1}"
	    uniqueness:@"*"];
	[self fact:@"bornIn" players:@[ employee, country ] reading:@"{0} was born in {1}"
	    inverse:@"{0} is birthplace of {1}" uniqueness:@"1!"];
	[self fact:@"livesIn" players:@[ employee, city ] reading:@"{0} lives in {1}" inverse:nil uniqueness:@"1!"];
	NSArray *works = [self fact:@"worksFor" players:@[ employee, branch ] reading:@"{0} works for {1}"
	                    inverse:@"{0} employs {1}" uniqueness:@"1!"];
	NSArray *heads = [self fact:@"heads" players:@[ employee, branch ] reading:@"{0} heads {1}"
	                    inverse:@"{0} is headed by {1}" uniqueness:@"11"];
	[_editor.constraintEditor setMandatory:YES role:[heads lastObject] reason:NULL];
	[_editor.constraintEditor addSetComparisonConstraint:ORMSubsetConstraint sequences:@[ heads, works ] reason:NULL];
	[self fact:@"locatedIn" players:@[ branch, city ] reading:@"{0} is located in {1}"
	    inverse:@"{0} is location of {1}" uniqueness:@"1!"];
	[self fact:@"cityName" players:@[ city, cityname ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1!"];
	[self fact:@"cityState" players:@[ city, state ] reading:@"{0} is in {1}" inverse:nil uniqueness:@"1!"];
	[self identify:city by:@[ @"cityName", @"cityState" ]];
	[self fact:@"stateCountry" players:@[ state, country ] reading:@"{0} is in {1}" inverse:nil uniqueness:@"1!"];
	[self fact:@"stateCode" players:@[ state, statecode ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1!"];
	[self identify:state by:@[ @"stateCountry", @"stateCode" ]];
	[self fact:@"usedIn" players:@[ language, country ] reading:@"{0} is used in {1}" inverse:@"{0} uses {1}"
	    uniqueness:@"*"];
	NSString *usBranch = [self entity:@"USbranch" mode:nil numeric:NO];
	[_editor.objectTypeEditor addSubtype:usBranch of:branch reason:NULL];
	NSString *achieved = [_editor.factTypeEditor addFactTypeWithPlayers:@[ usBranch, rank, year ] reading:@"{0} achieved {1} in {2}"
	                                           onDiagram:_diagram at:ORMAutomaticPlacement reason:NULL];
	NSArray *achievedRoles = [[[_editor.model elementWithId:achieved] roles] valueForKey:@"identifier"];
	[_editor.constraintEditor addUniquenessConstraintOverRoles:@[ [achievedRoles objectAtIndex:0], [achievedRoles objectAtIndex:2] ]
	                                   reason:NULL];
	[_facts setObject:achievedRoles forKey:@"achieved"];
}

- (NSString *)typeId:(NSString *)name
{
	return [[_editor.model objectTypeNamed:name] identifier];
}

- (NSString *)entity:(NSString *)name mode:(NSString *)mode numeric:(BOOL)numeric
{
	NSString *type = [_editor.objectTypeEditor addEntityTypeNamed:name referenceMode:mode
	                                        kind:mode != nil ? ORMReferenceModePopular : ORMReferenceModeNone
	                                   onDiagram:_diagram at:ORMAutomaticPlacement reason:NULL];
	if (numeric) {
		ORMObjectType *value = [[_editor.model elementWithId:type] referenceModeValueType];
		[_editor.objectTypeEditor setDataType:@"SignedIntegerNumericDataType" length:0 scale:0 of:value.identifier reason:NULL];
	}
	return type;
}

- (NSString *)value:(NSString *)name numeric:(BOOL)numeric
{
	return [_editor.objectTypeEditor addValueTypeNamed:name
	                         dataType:numeric ? @"SignedIntegerNumericDataType" : @"VariableLengthTextDataType"
	                        onDiagram:_diagram at:ORMAutomaticPlacement reason:NULL];
}

- (NSArray<NSString *> *)fact:(NSString *)name
                      players:(NSArray *)players
                      reading:(NSString *)reading
                      inverse:(NSString *)inverse
                   uniqueness:(NSString *)uniqueness
{
	NSString *fact = [_editor.factTypeEditor addFactTypeWithPlayers:players reading:reading onDiagram:_diagram
	                                              at:ORMAutomaticPlacement reason:NULL];
	CHECK(fact != nil, @"%@", reading);
	NSArray *roles = [[[_editor.model elementWithId:fact] roles] valueForKey:@"identifier"];
	if (inverse != nil) {
		NSString *reading = [_editor.factTypeEditor addReading:inverse forRoles:@[ [roles lastObject], [roles firstObject] ] reason:NULL];
		CHECK(reading != nil, @"%@", inverse);
	}
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

- (void)identify:(NSString *)type by:(NSArray<NSString *> *)facts
{
	NSMutableArray *far = [NSMutableArray array];
	for (NSString *name in facts) {
		[far addObject:[[_facts objectForKey:name] lastObject]];
	}
	NSString *unique = [_editor.constraintEditor addUniquenessConstraintOverRoles:far reason:NULL];
	CHECK([_editor.constraintEditor setPreferredIdentifier:unique reason:NULL], @"%@", type);
}

- (ORMQuery *)query:(NSString *)queryId
{
	return [ORMQuery queryWithId:queryId inModel:_editor.model];
}

- (ORMQueryEditor *)queries
{
	return [[ORMQueryEditor alloc] initWithEditor:_editor];
}

- (ORMQueryNode *)root:(NSString *)queryId
{
	return [self query:queryId].root;
}

- (ORMQueryStep *)step:(NSString *)stepId of:(NSString *)queryId
{
	for (ORMQueryNode *node in [[self query:queryId] nodes]) {
		for (ORMQueryStep *step in node.steps) {
			if ([step.identifier isEqualToString:stepId]) {
				return step;
			}
		}
	}
	return nil;
}

- (NSArray<ORMQueryNode *> *)from:(NSString *)nodeId
                          through:(NSString *)roleId
                               in:(NSString *)queryId
                             step:(NSString **)stepId
{
	NSString *reason = nil;
	NSString *step = [[self queries] addStepTo:nodeId through:roleId reason:&reason];
	CHECK(step != nil, @"%@", reason);
	if (stepId != NULL) {
		*stepId = step;
	}
	return [[self step:step of:queryId] nodes];
}

- (ORMQueryNode *)from:(NSString *)nodeId through:(NSString *)roleId in:(NSString *)queryId
{
	return [[self from:nodeId through:roleId in:queryId step:NULL] firstObject];
}

- (NSString *)role:(NSString *)fact at:(NSUInteger)index
{
	return [[_facts objectForKey:fact] objectAtIndex:index];
}

- (NSString *)subtyping:(NSString *)type supertype:(BOOL)supertype
{
	for (ORMRole *role in [ORMQuery rolesFrom:[_editor.model objectTypeNamed:type]]) {
		if (supertype ? role.isSupertypeMetaRole : role.isSubtypeMetaRole) {
			return role.identifier;
		}
	}
	return nil;
}

- (NSString *)q1
{
	NSString *q = [[self queries] addQueryNamed:@"Q1" from:[self typeId:@"Employee"] reason:NULL];
	ORMQueryNode *city = [self from:[self root:q].identifier through:[self role:@"livesIn" at:0] in:q];
	ORMQueryNode *branch = [self from:city.identifier through:[self role:@"locatedIn" at:1] in:q];
	CHECK([[self queries] setCondition:@"=" value:@"52" ofNode:branch.identifier reason:NULL]);
	return q;
}

- (NSString *)q2
{
	NSString *q = [[self queries] addQueryNamed:@"Q2" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	[self from:root through:[self role:@"drives" at:0] in:q];
	ORMQueryNode *branch = [self from:root through:[self role:@"worksFor" at:0] in:q];
	[[self queries] setProjected:YES ofNode:branch.identifier];
	return q;
}

- (NSString *)q3
{
	NSString *q = [[self queries] addQueryNamed:@"Q3" from:[self typeId:@"USbranch"] reason:NULL];
	NSString *root = [self root:q].identifier;
	NSString *notAchieved = nil;
	NSArray *achieved = [self from:root through:[self role:@"achieved" at:0] in:q step:&notAchieved];
	[[self queries] setOperator:ORMQueryNot ofStep:notAchieved];
	[[self queries] setCondition:@"=" value:@"1" ofNode:[[achieved firstObject] identifier] reason:NULL];
	[[self queries] setCondition:@"<" value:@"1998" ofNode:[[achieved lastObject] identifier] reason:NULL];
	ORMQueryNode *branch = [self from:root through:[self subtyping:@"USbranch" supertype:NO] in:q];
	ORMQueryNode *head = [self from:branch.identifier through:[self role:@"heads" at:1] in:q];
	ORMQueryNode *name = [self from:head.identifier through:[self role:@"hasName" at:0] in:q];
	[[self queries] setProjected:YES ofNode:name.identifier];
	NSString *maybe = nil;
	ORMQueryNode *car = [[self from:head.identifier through:[self role:@"drives" at:0] in:q step:&maybe] firstObject];
	[[self queries] setOperator:ORMQueryMaybe ofStep:maybe];
	[[self queries] setProjected:YES ofNode:car.identifier];

	return q;
}

- (NSString *)q4
{
	NSString *q = [[self queries] addQueryNamed:@"Q4" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	[[self queries] setLabel:@"1" ofNode:root];
	ORMQueryNode *city = [self from:root through:[self role:@"livesIn" at:0] in:q];
	[[self queries] setLabel:@"1" ofNode:city.identifier];
	ORMQueryNode *country = [self from:root through:[self role:@"bornIn" at:0] in:q];
	[[self queries] setLabel:@"1" ofNode:country.identifier];
	ORMQueryNode *supervised = [self from:root through:[self role:@"reportsTo" at:1] in:q];
	[[self queries] setLabel:@"2" ofNode:supervised.identifier];
	ORMQueryNode *theirCity = [self from:supervised.identifier through:[self role:@"livesIn" at:0] in:q];
	[[self queries] setLabel:@"1" ofNode:theirCity.identifier];
	ORMQueryNode *theirCountry = [self from:supervised.identifier through:[self role:@"bornIn" at:0] in:q];
	[[self queries] setLabel:@"2" ofNode:theirCountry.identifier];
	NSString *reason = nil;
	CHECK([[self queries] setCondition:@"<>" toNode:country.identifier ofNode:theirCountry.identifier
	                                    reason:&reason], @"%@", reason);
	REFUSED([[self queries] setCondition:@"=" toNode:city.identifier ofNode:theirCountry.identifier
	                                     reason:&reason]);

	return q;
}

- (NSString *)q5
{
	NSString *q = [[self queries] addQueryNamed:@"Q5" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	ORMQueryNode *owned = [self from:root through:[self role:@"owns" at:0] in:q];
	[[self queries] setLabel:@"1" ofNode:owned.identifier];
	NSString *notDrives = nil;
	ORMQueryNode *driven = [[self from:root through:[self role:@"drives" at:0] in:q step:&notDrives] firstObject];
	[[self queries] setLabel:@"1" ofNode:driven.identifier];
	[[self queries] setOperator:ORMQueryNot ofStep:notDrives];
	[[self queries] setCount:@">" value:1 ofStep:notDrives reason:NULL];
	return q;
}

- (NSString *)payroll
{
	NSString *q = [[self queries] addQueryNamed:@"Payroll" from:[self typeId:@"Branch"] reason:NULL];
	NSString *root = [self root:q].identifier;
	NSString *employs = nil;
	ORMQueryNode *employee = [[self from:root through:[self role:@"worksFor" at:1] in:q step:&employs] firstObject];
	ORMQueryNode *salary = [self from:employee.identifier through:[self role:@"earns" at:0] in:q];
	NSString *reason = nil;
	CHECK([[self queries] setAggregate:ORMQueryTotal ofNode:salary.identifier comparison:@">" value:@"1000000"
	                                    ofStep:employs reason:&reason], @"%@", reason);
	REFUSED([[self queries] setAggregate:ORMQueryTotal ofNode:root comparison:@">" value:@"1" ofStep:employs
	                                     reason:&reason]);
	[[self queries] setSortOrder:ORMQueryDescending ofNode:root];

	return q;
}

/* A diagram of its own, from here on. */
- (void)diagram:(NSString *)name
{
	if ([[[_editor.model.diagrams firstObject] allShapes] count] == 0 && [_editor.model.diagrams count] == 1) {
		_diagram = [[_editor.model.diagrams firstObject] identifier];
		[_editor.elementEditor rename:_diagram to:name reason:NULL];
	} else {
		_diagram = [_editor.diagramEditor addDiagramNamed:name];
	}
}

- (NSString *)text:(NSString *)name
{
	return [self value:name numeric:NO];
}

- (void)note:(NSString *)text on:(NSString *)elementId
{
	[_editor.elementEditor setDefinition:text of:elementId reason:NULL];
}

- (void)save:(NSString *)path
{
	for (ORMDiagram *diagram in _editor.model.diagrams) {
		[_editor.diagramEditor arrangeDiagram:diagram.identifier];
	}
	/* A sample's population keeps its constraints. */
	for (ORMPopulationViolation *violation in [[[ORMPopulationChecker alloc] initWithModel:_editor.model] violations]) {
		check(NO, [[NSString stringWithFormat:@"%@: %@", [path lastPathComponent], violation.text] UTF8String]);
	}
	[[_editor dataForSaving] writeToFile:path atomically:YES];
	NSLog(@"wrote %@: %lu object types, %lu fact types, %lu queries", path,
	      (unsigned long)[_editor.model.objectTypes count], (unsigned long)[_editor.model.factTypes count],
	      (unsigned long)[[ORMQuery queriesInModel:_editor.model] count]);
}

#pragma mark Populations

/* An instance by its reference mode's value. */
- (NSString *)one:(NSString *)typeName value:(NSString *)text in:(ORMSamplePopulation *)population
{
	ORMObjectType *type = [_editor.model objectTypeNamed:typeName];
	ORMRole *role = [[type.preferredIdentifier allRoles] firstObject];
	return [population instanceOf:type.identifier
	                 identifiedBy:@{ role.identifier: [population value:text of:role.player.identifier] }];
}

/* A fact of the fact type named as -fact:players: named it, its players in
 * its roles' order. Its id. */
- (NSString *)fact:(NSString *)name of:(NSArray<NSString *> *)players in:(ORMSamplePopulation *)population
{
	NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [players count]; i++) {
		[byRole setObject:[players objectAtIndex:i] forKey:[self role:name at:i]];
	}
	ORMRole *role = [_editor.model elementWithId:[self role:name at:0]];
	return [population factOf:role.factType.identifier players:byRole];
}

- (void)add:(ORMSamplePopulation *)population
{
	NSString *reason = nil;
	CHECK([_editor.populationEditor addPopulation:population reason:&reason], reason);
}

/* The company the query tests ask about: each paper's query finds what the
 * paper says it should. */
- (void)companyPopulation
{
	ORMSamplePopulation *p = [[ORMSamplePopulation alloc] init];
	NSString *australia = [self one:@"Country" value:@"Australia" in:p];
	NSString *usa = [self one:@"Country" value:@"USA" in:p];
	NSString *uk = [self one:@"Country" value:@"UK" in:p];
	NSString *(^state)(NSString *, NSString *) = ^NSString *(NSString *country, NSString *code) {
		return [p instanceOf:[self typeId:@"State"]
		        identifiedBy:@{ [self role:@"stateCountry" at:1]: country,
		                        [self role:@"stateCode" at:1]: [p value:code of:[self typeId:@"Statecode"]] }];
	};
	NSString *(^city)(NSString *, NSString *) = ^NSString *(NSString *name, NSString *inState) {
		return [p instanceOf:[self typeId:@"City"]
		        identifiedBy:@{ [self role:@"cityName" at:1]: [p value:name of:[self typeId:@"Cityname"]],
		                        [self role:@"cityState" at:1]: inState }];
	};
	NSString *brisbane = city(@"Brisbane", state(australia, @"QLD")), *sydney = city(@"Sydney", state(australia, @"NSW"));
	NSString *perth = city(@"Perth", state(australia, @"WA")), *seattle = city(@"Seattle", state(usa, @"WA"));
	NSMutableDictionary *employees = [NSMutableDictionary dictionary];
	NSDictionary *names = @{ @1: @"Ann", @2: @"Bea", @3: @"Cal", @4: @"Dee", @5: @"Eve", @10: @"Fay", @21: @"Gus" };
	for (NSArray *row in @[ @[ @1, brisbane, australia, @"600000" ], @[ @2, sydney, australia, @"500000" ],
	                        @[ @3, brisbane, australia, @"500000" ], @[ @4, seattle, usa, @"50000" ],
	                        @[ @5, seattle, usa, @"50000" ], @[ @10, sydney, uk, @"600000" ],
	                        @[ @21, perth, uk, @"50000" ] ]) {
		NSString *e = [self one:@"Employee" value:[[row firstObject] stringValue] in:p];
		[employees setObject:e forKey:[row firstObject]];
		[self fact:@"hasName" of:@[ e, [p value:[names objectForKey:[row firstObject]] of:[self typeId:@"EmployeeName"]] ]
		        in:p];
		[self fact:@"livesIn" of:@[ e, [row objectAtIndex:1] ] in:p];
		[self fact:@"bornIn" of:@[ e, [row objectAtIndex:2] ] in:p];
		[self fact:@"earns" of:@[ e, [self one:@"Salary" value:[row lastObject] in:p] ] in:p];
	}
	NSString *(^employee)(int) = ^NSString *(int nr) {
		return [employees objectForKey:@(nr)];
	};
	[self fact:@"reportsTo" of:@[ employee(10), employee(2) ] in:p];
	[self fact:@"reportsTo" of:@[ employee(21), employee(1) ] in:p];
	NSString *b52 = [self one:@"Branch" value:@"52" in:p], *b7 = [self one:@"Branch" value:@"7" in:p];
	NSString *us1 = [p instanceOf:[self typeId:@"USbranch"] supertypeInstance:[self one:@"Branch" value:@"101" in:p]];
	NSString *us2 = [p instanceOf:[self typeId:@"USbranch"] supertypeInstance:[self one:@"Branch" value:@"102" in:p]];
	for (NSArray *row in @[ @[ b52, brisbane, @1 ], @[ b7, sydney, @2 ], @[ us1, seattle, @4 ], @[ us2, seattle, @5 ] ]) {
		[self fact:@"locatedIn" of:@[ [row firstObject], [row objectAtIndex:1] ] in:p];
		[self fact:@"heads" of:@[ employee([[row lastObject] intValue]), [row firstObject] ] in:p];
	}
	for (NSArray *row in @[ @[ @1, b52 ], @[ @3, b52 ], @[ @2, b7 ], @[ @10, b7 ], @[ @21, b7 ], @[ @4, us1 ], @[ @5, us2 ] ]) {
		[self fact:@"worksFor" of:@[ employee([[row firstObject] intValue]), [row lastObject] ] in:p];
	}
	NSString *ute = [self one:@"CarModel" value:@"Ute" in:p];
	NSString *a = [self one:@"Car" value:@"A" in:p], *b = [self one:@"Car" value:@"B" in:p];
	NSString *c = [self one:@"Car" value:@"C" in:p];
	for (NSString *car in @[ a, b, c ]) {
		[self fact:@"carModel" of:@[ car, ute ] in:p];
	}
	for (NSArray *row in @[ @[ @1, c ], @[ @3, a ], @[ @3, b ], @[ @4, a ] ]) {
		[self fact:@"drives" of:@[ employee([[row firstObject] intValue]), [row lastObject] ] in:p];
	}
	for (NSArray *row in @[ @[ @1, b ], @[ @3, a ], @[ @3, b ], @[ @4, a ] ]) {
		[self fact:@"owns" of:@[ employee([[row firstObject] intValue]), [row lastObject] ] in:p];
	}
	NSString *english = [self one:@"Language" value:@"English" in:p], *latin = [self one:@"Language" value:@"Latin" in:p];
	[self fact:@"speaks" of:@[ employee(1), english ] in:p];
	[self fact:@"speaks" of:@[ employee(1), latin ] in:p];
	[self fact:@"speaks" of:@[ employee(2), english ] in:p];
	for (NSArray *row in @[ @[ us1, @"1", @"1995" ], @[ us2, @"1", @"2001" ], @[ us2, @"2", @"1996" ] ]) {
		[self fact:@"achieved" of:@[ [row firstObject], [self one:@"Rank" value:[row objectAtIndex:1] in:p],
		                             [self one:@"Year" value:[row lastObject] in:p] ]
		        in:p];
	}
	[self add:p];
}

/* A Core Data mapping keeping City an entity of its own, so a query can
 * compare cities (Q4): absorbed, a city has no one value to compare. */
- (void)companyMapping
{
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:_editor];
	NSString *mapping = [mappings addCoreDataMappingNamed:@"Company" path:@"Company.xcdatamodeld"];
	[mappings setMapping:ORMMapAsEntity ofObjectType:[self typeId:@"City"] inMapping:mapping];
}

/* Five academics: Q1 finds three, Q2 the one professor of informatics with
 * no degree from UQ, Q3 all five, two of them with no degree rated above 5. */
- (void)universityPopulation
{
	ORMSamplePopulation *p = [[ORMSamplePopulation alloc] init];
	NSMutableDictionary *universities = [NSMutableDictionary dictionary];
	for (NSString *code in @[ @"UQ", @"MIT", @"ANU" ]) {
		[universities setObject:[self one:@"University" value:code in:p] forKey:code];
	}
	NSMutableDictionary *degrees = [NSMutableDictionary dictionary];
	for (NSArray *row in @[ @[ @"BSc", @"UQ", @"6" ], @[ @"PhD", @"UQ", @"7" ], @[ @"BSc", @"MIT", @"5" ],
	                        @[ @"PhD", @"MIT", @"7" ], @[ @"MSc", @"ANU", @"4" ] ]) {
		NSString *degree = [p instanceOf:[self typeId:@"Degree"]
		                    identifiedBy:@{ [self role:@"degreeCode" at:1]: [p value:[row firstObject]
		                                                                          of:[self typeId:@"Degreecode"]],
		                                    [self role:@"degreeUniversity" at:1]: [universities objectForKey:row[1]] }];
		[self fact:@"rating" of:@[ degree, [p value:[row lastObject] of:[self typeId:@"Rating"]] ] in:p];
		[degrees setObject:degree forKey:[NSString stringWithFormat:@"%@ %@", row[0], row[1]]];
	}
	NSMutableDictionary *academics = [NSMutableDictionary dictionary];
	for (NSArray *row in @[ @[ @"715", @"P", @"Ana Lima" ], @[ @"720", @"P", @"Ben Cho" ], @[ @"430", @"SL", @"Cara Diaz" ],
	                        @[ @"503", @"L", @"Dev Rao" ], @[ @"651", @"AL", @"Eli Moss" ] ]) {
		NSString *academic = [self one:@"Academic" value:[row firstObject] in:p];
		[academics setObject:academic forKey:[row firstObject]];
		[self fact:@"rank" of:@[ academic, [self one:@"Rank" value:row[1] in:p] ] in:p];
		[self fact:@"academicName" of:@[ academic, [p value:row[2] of:[self typeId:@"AcademicName"]] ] in:p];
	}
	for (NSArray *row in @[ @[ @"715", @"Databases" ], @[ @"720", @"Informatics" ] ]) {
		NSString *professor = [p instanceOf:[self typeId:@"Professor"]
		                  supertypeInstance:[academics objectForKey:[row firstObject]]];
		[self fact:@"holds" of:@[ professor, [self one:@"Chair" value:[row lastObject] in:p] ] in:p];
	}
	for (NSArray *row in @[ @[ @"715", @"BSc UQ", @"1979" ], @[ @"715", @"PhD MIT", @"1984" ],
	                        @[ @"720", @"BSc MIT", @"1975" ], @[ @"720", @"PhD MIT", @"1980" ],
	                        @[ @"430", @"BSc UQ", @"1990" ], @[ @"430", @"PhD UQ", @"1995" ],
	                        @[ @"503", @"MSc ANU", @"2001" ] ]) {
		[self fact:@"awarded" of:@[ [academics objectForKey:row[0]], [degrees objectForKey:row[1]],
		                            [self one:@"Year" value:row[2] in:p] ]
		        in:p];
	}
	[self add:p];
}

/* Figures 4 and 7's populations, as the paper gives them; and a few
 * writings of our own, two of them on one paper. */
- (void)umlAndORMPopulation
{
	ORMSamplePopulation *p = [[ORMSamplePopulation alloc] init];
	NSMutableDictionary *facilities = [NSMutableDictionary dictionary];
	for (NSArray *row in @[ @[ @"DP", @"Data projection unit" ], @[ @"INT", @"Internet access" ],
	                        @[ @"PA", @"Public Address system" ] ]) {
		NSString *facility = [self one:@"Facility" value:[row firstObject] in:p];
		[facilities setObject:facility forKey:[row firstObject]];
		[self fact:@"facilityName" of:@[ facility, [p value:[row lastObject] of:[self typeId:@"FacilityName"]] ] in:p];
	}
	for (NSArray *row in @[ @[ @"10", @"PA" ], @[ @"20", @"DP" ], @[ @"33", @"DP" ], @[ @"33", @"INT" ], @[ @"33", @"PA" ] ]) {
		[self fact:@"provides" of:@[ [self one:@"Room" value:row[0] in:p], [facilities objectForKey:row[1]] ] in:p];
	}
	for (NSArray *row in @[ @[ @"VM class", @"DP" ], @[ @"AQ demo", @"DP" ], @[ @"AQ demo", @"INT" ] ]) {
		[self fact:@"requires" of:@[ [self one:@"Activity" value:row[0] in:p], [facilities objectForKey:row[1]] ] in:p];
	}
	for (NSArray *row in @[ @[ @"20", @"Mon 9am", @"VM class" ], @[ @"20", @"Tue 2pm", @"VM class" ],
	                        @[ @"33", @"Tue 2pm", @"AQ demo" ], @[ @"33", @"Wed 3pm", @"VM class" ],
	                        @[ @"33", @"Fri 5pm", @"Party" ] ]) {
		[self fact:@"used" of:@[ [self one:@"Room" value:row[0] in:p], [self one:@"Time" value:row[1] in:p],
		                         [self one:@"Activity" value:row[2] in:p] ]
		        in:p];
	}
	for (NSArray *row in @[ @[ @"Lady", @"F" ], @[ @"Mr", @"M" ], @[ @"Mrs", @"F" ], @[ @"Ms", @"F" ] ]) {
		[self fact:@"determines" of:@[ [p value:row[0] of:[self typeId:@"Title"]], [self one:@"Sex" value:row[1] in:p] ]
		        in:p];
	}
	/* Our own: who wrote which paper, and how long each writing took. */
	ORMObjectType *writing = [_editor.model objectTypeNamed:@"Writing"];
	for (NSArray *row in @[ @[ @"Terry", @"1", @"30" ], @[ @"Anthony", @"1", @"30" ], @[ @"Terry", @"2", @"12" ],
	                        @[ @"Erik", @"3", @"45" ] ]) {
		NSString *wrote = [self fact:@"wrote" of:@[ [self one:@"Person" value:row[0] in:p],
		                                            [self one:@"Paper" value:row[1] in:p] ]
		                          in:p];
		NSString *instance = [p instanceOf:writing.identifier objectifying:wrote];
		[self fact:@"took" of:@[ instance, [self one:@"Period" value:row[2] in:p] ] in:p];
	}
	[self add:p];
}

#pragma mark Company

/* Halpin, "Conceptual Queries" (1998), figure 1, with an "owns" fact
 * ConQuer-II's Q5 asks of; the papers' queries. */
- (void)company
{
	[self buildCompany];
	/* Who, beside which number: each employee a query lists, named. */
	for (NSString *q in @[ [self q1], [self q2], [self q4], [self q5] ]) {
		[self name:[self root:q].identifier through:@"hasName" in:q];
	}
	[self q3];
	[self payroll];
	NSString *polyglots = [[self queries] addQueryNamed:@"Polyglots" from:[self typeId:@"Employee"] reason:NULL];
	NSString *speaks = nil;
	[self from:[self root:polyglots].identifier through:[self role:@"speaks" at:0] in:polyglots step:&speaks];
	[[self queries] setCount:@">" value:1 ofStep:speaks reason:NULL];
	[self name:[self root:polyglots].identifier through:@"hasName" in:polyglots];
	/* Q4's: and whom they supervise. */
	for (ORMQuery *query in [ORMQuery queriesInModel:_editor.model]) {
		if ([query.name isEqualToString:@"Q4"]) {
			for (ORMQueryNode *node in [query nodes]) {
				if ([node.label isEqualToString:@"2"] && [node.objectType.name isEqualToString:@"Employee"]) {
					[[self queries] setProjected:YES ofNode:node.identifier];
					[self name:node.identifier through:@"hasName" in:query.identifier];
				}
			}
		}
	}
}

/* The node's name listed beside it, through the fact type naming it. */
- (void)name:(NSString *)nodeId through:(NSString *)fact in:(NSString *)queryId
{
	ORMQueryNode *name = [self from:nodeId through:[self role:fact at:0] in:queryId];
	[[self queries] setProjected:YES ofNode:name.identifier];
}

#pragma mark University

/* Bloesch and Halpin, "Conceptual Queries using ConQuer-II" (ER '97),
 * figure 2, and its queries Q1 to Q3. */
- (void)university
{
	NSString *academic = [self entity:@"Academic" mode:@"empnr" numeric:YES];
	NSString *degree = [self entity:@"Degree" mode:nil numeric:NO];
	NSString *code = [self text:@"Degreecode"];
	NSString *university = [self entity:@"University" mode:@"code" numeric:NO];
	NSString *rating = [self value:@"Rating" numeric:YES];
	NSString *year = [self entity:@"Year" mode:@"AD" numeric:YES];
	NSString *rank = [self entity:@"Rank" mode:@"code" numeric:NO];
	NSString *chair = [self entity:@"Chair" mode:@"name" numeric:NO];
	NSString *professor = [self entity:@"Professor" mode:nil numeric:NO];
	/* Not in the paper: a name, for a reader to see who a row is. */
	NSString *academicName = [self text:@"AcademicName"];
	[self fact:@"academicName" players:@[ academic, academicName ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1!"];
	[self fact:@"degreeCode" players:@[ degree, code ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1!"];
	[self fact:@"degreeUniversity" players:@[ degree, university ] reading:@"{0} is from {1}" inverse:@"{0} awarded {1}"
	    uniqueness:@"1!"];
	[self identify:degree by:@[ @"degreeCode", @"degreeUniversity" ]];
	[self fact:@"rating" players:@[ degree, rating ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1"];
	[_editor.objectTypeEditor setValueConstraint:@"{1..7}" of:rating reason:NULL];
	NSArray *awarded = [self fact:@"awarded" players:@[ academic, degree, year ] reading:@"{0} was awarded {1} in {2}"
	                      inverse:nil uniqueness:@""];
	[_editor.constraintEditor addUniquenessConstraintOverRoles:@[ awarded[0], awarded[1] ] reason:NULL];
	[self fact:@"rank" players:@[ academic, rank ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1!"];
	ORMObjectType *rankType = [_editor.model elementWithId:rank];
	[_editor.objectTypeEditor setValueConstraint:@"{'AL', 'L', 'SL', 'P'}" of:rankType.referenceModeValueType.identifier
	                                     reason:NULL];
	[_editor.objectTypeEditor addSubtype:professor of:academic reason:NULL];
	[self note:@"Each Professor is an Academic who has Rank 'P'." on:professor];
	[self fact:@"holds" players:@[ professor, chair ] reading:@"{0} holds {1}" inverse:@"{0} is held by {1}"
	    uniqueness:@"11!"];

	/* Q1: academics awarded a degree rated above 5, and those degrees. */
	NSString *q1 = [[self queries] addQueryNamed:@"Q1" from:academic reason:NULL];
	NSString *awardedStep = nil;
	ORMQueryNode *awardedDegree = [[self from:[self root:q1].identifier through:awarded[0] in:q1 step:&awardedStep] firstObject];
	[[self queries] setProjected:YES ofNode:awardedDegree.identifier];
	ORMQueryNode *rated = [self from:awardedDegree.identifier through:[self role:@"rating" at:0] in:q1];
	[[self queries] setCondition:@">" value:@"5" ofNode:rated.identifier reason:NULL];
	[self name:[self root:q1].identifier through:@"academicName" in:q1];

	/* Q2: professors holding the informatics chair, with no degree from UQ. */
	NSString *q2 = [[self queries] addQueryNamed:@"Q2" from:academic reason:NULL];
	ORMQueryNode *isProfessor = [self from:[self root:q2].identifier through:[self subtyping:@"Academic" supertype:YES] in:q2];
	ORMQueryNode *held = [self from:isProfessor.identifier through:[self role:@"holds" at:0] in:q2];
	[[self queries] setCondition:@"=" value:@"Informatics" ofNode:held.identifier reason:NULL];
	NSString *notAwarded = nil;
	ORMQueryNode *anyDegree = [[self from:[self root:q2].identifier through:awarded[0] in:q2 step:&notAwarded] firstObject];
	[[self queries] setOperator:ORMQueryNot ofStep:notAwarded];
	ORMQueryNode *from = [self from:anyDegree.identifier through:[self role:@"degreeUniversity" at:0] in:q2];
	[[self queries] setCondition:@"=" value:@"UQ" ofNode:from.identifier reason:NULL];
	[self name:[self root:q2].identifier through:@"academicName" in:q2];

	/* Q3: each academic, and maybe their degrees rated above 5. */
	NSString *q3 = [[self queries] addQueryNamed:@"Q3" from:academic reason:NULL];
	NSString *maybe = nil;
	ORMQueryNode *maybeDegree = [[self from:[self root:q3].identifier through:awarded[0] in:q3 step:&maybe] firstObject];
	[[self queries] setOperator:ORMQueryMaybe ofStep:maybe];
	[[self queries] setProjected:YES ofNode:maybeDegree.identifier];
	ORMQueryNode *maybeRated = [self from:maybeDegree.identifier through:[self role:@"rating" at:0] in:q3];
	[[self queries] setCondition:@">" value:@"5" ofNode:maybeRated.identifier reason:NULL];
	[self name:[self root:q3].identifier through:@"academicName" in:q3];
}

#pragma mark UML and ORM

/* Halpin and Bloesch, "Data modeling in UML and ORM: a comparison" (JDM
 * 1999): its ORM figures, a diagram each. Figures 4 and 7's join-subset
 * constraints are not here: ORMKit does not yet make constraint join paths. */
- (void)umlAndORM
{
	/* Figure 1: writing, objectified. */
	[self diagram:@"Writing"];
	NSString *person = [self entity:@"Person" mode:@"name" numeric:NO];
	NSString *paper = [self entity:@"Paper" mode:@"nr" numeric:YES];
	NSString *period = [self entity:@"Period" mode:@"days" numeric:YES];
	NSArray *wrote = [self fact:@"wrote" players:@[ person, paper ] reading:@"{0} wrote {1}" inverse:@"{0} is written by {1}"
	                 uniqueness:@"*"];
	[_editor.constraintEditor setMandatory:YES role:wrote[1] reason:NULL];
	ORMFactType *writtenFact = [[_editor.model elementWithId:wrote[0]] factType];
	NSString *writing = [_editor.factTypeEditor objectifyFactType:writtenFact.identifier named:@"Writing" reason:NULL];
	[self fact:@"took" players:@[ writing, period ] reading:@"{0} took {1}" inverse:nil uniqueness:@"1"];

	/* Figures 3 and 4: rooms used at times for activities, which need
	 * facilities the rooms provide. */
	[self diagram:@"Room usage"];
	NSString *room = [self entity:@"Room" mode:@"nr" numeric:YES];
	NSString *time = [self entity:@"Time" mode:@"dh" numeric:NO];
	NSString *activity = [self entity:@"Activity" mode:@"name" numeric:NO];
	NSString *facility = [self entity:@"Facility" mode:@"code" numeric:NO];
	NSString *facilityName = [self text:@"FacilityName"];
	[self fact:@"provides" players:@[ room, facility ] reading:@"{0} provides {1}" inverse:@"{0} is in {1}" uniqueness:@"*"];
	[self fact:@"requires" players:@[ activity, facility ] reading:@"{0} requires {1}" inverse:nil uniqueness:@"*"];
	NSArray *named = [self fact:@"facilityName" players:@[ facility, facilityName ] reading:@"{0} has {1}"
	                    inverse:@"{0} refers to {1}" uniqueness:@"11!"];
	(void)named;
	NSArray *used = [self fact:@"used" players:@[ room, time, activity ] reading:@"{0} at {1} is used for {2}" inverse:nil
	                uniqueness:@""];
	[_editor.constraintEditor addUniquenessConstraintOverRoles:@[ used[0], used[1] ] reason:NULL];
	[_editor.constraintEditor addUniquenessConstraintOverRoles:@[ used[1], used[2] ] reason:NULL];
	[self note:@"If a Room at a Time is used for an Activity that requires a Facility then that Room provides that "
	           @"Facility (the paper's join-subset constraint; not yet drawn)."
	        on:room];

	/* Figure 5: subset constraints. */
	[self diagram:@"Students"];
	NSString *student = [self entity:@"Student" mode:@"nr" numeric:YES];
	NSString *surname = [self text:@"Surname"];
	NSString *firstName = [self text:@"FirstName"];
	NSString *secondName = [self text:@"SecondName"];
	NSString *course = [self entity:@"Course" mode:@"code" numeric:NO];
	NSString *test = [self entity:@"Test" mode:@"nr" numeric:YES];
	[self fact:@"surname" players:@[ student, surname ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1!"];
	NSArray *first = [self fact:@"firstName" players:@[ student, firstName ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1"];
	NSArray *second = [self fact:@"secondName" players:@[ student, secondName ] reading:@"{0} has {1}" inverse:nil
	                  uniqueness:@"1"];
	[_editor.constraintEditor addSetComparisonConstraint:ORMSubsetConstraint sequences:@[ @[ second[0] ], @[ first[0] ] ]
	                                              reason:NULL];
	NSArray *enrolled = [self fact:@"enrolled" players:@[ student, course ] reading:@"{0} enrolled in {1}" inverse:nil
	                    uniqueness:@"*"];
	NSArray *passed = [self fact:@"passed" players:@[ student, course, test ] reading:@"{0} on {1} passed {2}" inverse:nil
	                  uniqueness:@"*"];
	[_editor.constraintEditor addSetComparisonConstraint:ORMSubsetConstraint
	                                           sequences:@[ @[ passed[0], passed[1] ], @[ enrolled[0], enrolled[1] ] ]
	                                              reason:NULL];

	/* Figure 7: title and sex. */
	[self diagram:@"Title and sex"];
	NSString *employee = [self entity:@"Employee" mode:@"empNr" numeric:NO];
	NSString *title = [self text:@"Title"];
	NSString *sex = [self entity:@"Sex" mode:@"code" numeric:NO];
	[self fact:@"title" players:@[ employee, title ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1!"];
	[self fact:@"sex" players:@[ employee, sex ] reading:@"{0} is of {1}" inverse:nil uniqueness:@"1!"];
	[self fact:@"determines" players:@[ title, sex ] reading:@"{0} determines {1}" inverse:nil uniqueness:@"1"];
	ORMObjectType *sexType = [_editor.model elementWithId:sex];
	[_editor.objectTypeEditor setValueConstraint:@"{'M', 'F'}" of:sexType.referenceModeValueType.identifier reason:NULL];
	[self note:@"If an Employee has a Title that determines a Sex then that Employee is of that Sex (the paper's join-subset "
	           @"constraint; not yet drawn)."
	        on:employee];

	/* Figure 8: a co-referenced account. */
	[self diagram:@"Accounts"];
	NSString *account = [self entity:@"Account" mode:nil numeric:NO];
	NSString *bank = [self entity:@"Bank" mode:@"name" numeric:NO];
	NSString *accountNr = [self text:@"AccountNr"];
	NSString *customer = [self entity:@"Customer" mode:@"custnr" numeric:NO];
	[self fact:@"accountBank" players:@[ account, bank ] reading:@"{0} is in {1}" inverse:nil uniqueness:@"1!"];
	[self fact:@"accountNr" players:@[ account, accountNr ] reading:@"{0} has {1}" inverse:nil uniqueness:@"1!"];
	[self identify:account by:@[ @"accountBank", @"accountNr" ]];
	[self fact:@"uses" players:@[ account, customer ] reading:@"{0} is used by {1}" inverse:@"{0} uses {1}" uniqueness:@"1"];

	/* What the join-subset constraint forbids, as a query: rooms used for
	 * an activity that requires a facility the room does not provide. */
	NSString *q = [[self queries] addQueryNamed:@"Rooms lacking a facility" from:room reason:NULL];
	[[self queries] setLabel:@"1" ofNode:[self root:q].identifier];
	NSArray *usage = [self from:[self root:q].identifier through:used[0] in:q step:NULL];
	ORMQueryNode *forActivity = [usage lastObject];
	[[self queries] setProjected:YES ofNode:forActivity.identifier];
	ORMQueryNode *needed = [self from:forActivity.identifier through:[self role:@"requires" at:0] in:q];
	[[self queries] setLabel:@"1" ofNode:needed.identifier];
	[[self queries] setProjected:YES ofNode:needed.identifier];
	[self name:needed.identifier through:@"facilityName" in:q];
	NSString *notProvides = nil;
	ORMQueryNode *provided = [[self from:[self root:q].identifier through:[self role:@"provides" at:0] in:q step:&notProvides]
		firstObject];
	[[self queries] setOperator:ORMQueryNot ofStep:notProvides];
	[[self queries] setLabel:@"1" ofNode:provided.identifier];

	/* Papers written by more than one person. */
	NSString *coauthored = [[self queries] addQueryNamed:@"Coauthored papers" from:paper reason:NULL];
	NSString *by = nil;
	[self from:[self root:coauthored].identifier through:wrote[1] in:coauthored step:&by];
	[[self queries] setCount:@">" value:1 ofStep:by reason:NULL];
}

@end

int main(int argc, char **argv)
{
	@autoreleasepool {
		if (argc != 2) {
			fprintf(stderr, "usage: %s directory\n", argv[0]);
			return 2;
		}
		NSString *out = [NSString stringWithUTF8String:argv[1]];
		Builder *company = [[Builder alloc] initNamed:@"Company"];
		[company company];
		[company companyPopulation];
		[company companyMapping];
		[company save:[out stringByAppendingPathComponent:@"Company.orm"]];
		Builder *university = [[Builder alloc] initNamed:@"University"];
		[university university];
		[university universityPopulation];
		[university save:[out stringByAppendingPathComponent:@"University.orm"]];
		Builder *uml = [[Builder alloc] initNamed:@"UMLandORM"];
		[uml umlAndORM];
		[uml umlAndORMPopulation];
		[uml save:[out stringByAppendingPathComponent:@"UMLandORM.orm"]];
	}
	return failures > 0;
}
