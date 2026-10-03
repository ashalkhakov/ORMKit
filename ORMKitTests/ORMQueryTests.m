/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* Conceptual queries (ORMQuery.h, ORMQueryFetch.h), on the schema and
 * queries of Halpin's "Conceptual Queries" (Database Newsletter 26:2,
 * figure 1): employees, the branches they work for and head, the cities
 * they live in (a city identified by its name and state, a state by its
 * code and country), the cars they drive, and US branches' ranks by year. */
@interface ORMQueryTests : ORMTestCase
@end

@implementation ORMQueryTests
{
	ORMEditor *_editor;
	NSString *_diagram;
	NSMutableDictionary<NSString *, NSArray<NSString *> *> *_facts;
}

- (NSString *)typeId:(NSString *)name
{
	return [[_editor.model objectTypeNamed:name] identifier];
}

- (NSString *)entity:(NSString *)name mode:(NSString *)mode numeric:(BOOL)numeric
{
	NSString *type = [_editor addEntityTypeNamed:name referenceMode:mode
	                                        kind:mode != nil ? ORMReferenceModePopular : ORMReferenceModeNone
	                                   onDiagram:_diagram at:ORMAutomaticPlacement reason:NULL];
	if (numeric) {
		ORMObjectType *value = [[_editor.model elementWithId:type] referenceModeValueType];
		[_editor setDataType:@"SignedIntegerNumericDataType" length:0 scale:0 of:value.identifier reason:NULL];
	}
	return type;
}

- (NSString *)value:(NSString *)name numeric:(BOOL)numeric
{
	return [_editor addValueTypeNamed:name
	                         dataType:numeric ? @"SignedIntegerNumericDataType" : @"VariableLengthTextDataType"
	                        onDiagram:_diagram at:ORMAutomaticPlacement reason:NULL];
}

/* A fact type with its reading (and inverse, if any); "1" makes the first
 * role unique (functional), "11" both (one to one), "*" spans the roles
 * (many to many); "!" makes the first role mandatory. */
- (NSArray<NSString *> *)fact:(NSString *)name
                      players:(NSArray *)players
                      reading:(NSString *)reading
                      inverse:(NSString *)inverse
                   uniqueness:(NSString *)uniqueness
{
	NSString *fact = [_editor addFactTypeWithPlayers:players reading:reading onDiagram:_diagram
	                                              at:ORMAutomaticPlacement reason:NULL];
	XCTAssertNotNil(fact, @"%@", reading);
	NSArray *roles = [[[_editor.model elementWithId:fact] roles] valueForKey:@"identifier"];
	if (inverse != nil) {
		NSString *reading = [_editor addReading:inverse forRoles:@[ [roles lastObject], [roles firstObject] ] reason:NULL];
		XCTAssertNotNil(reading, @"%@", inverse);
	}
	if ([uniqueness hasPrefix:@"1"]) {
		[_editor setUnique:YES role:[roles firstObject] reason:NULL];
	}
	if ([uniqueness hasPrefix:@"11"]) {
		[_editor setUnique:YES role:[roles lastObject] reason:NULL];
	}
	if ([uniqueness hasPrefix:@"*"]) {
		[_editor addUniquenessConstraintOverRoles:roles reason:NULL];
	}
	if ([uniqueness hasSuffix:@"!"]) {
		[_editor setMandatory:YES role:[roles firstObject] reason:NULL];
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
	NSString *unique = [_editor addUniquenessConstraintOverRoles:far reason:NULL];
	XCTAssertTrue([_editor setPreferredIdentifier:unique reason:NULL], @"%@", type);
}

- (void)setUp
{
	[super setUp];
	_editor = [self newEditor];
	_diagram = [[_editor.model.diagrams firstObject] identifier];
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
	[_editor addSetComparisonConstraint:ORMExclusionConstraint
	                          sequences:@[ @[ [main lastObject] ], @[ [other lastObject] ] ]
	                             reason:NULL];
	[_editor addSetComparisonConstraint:ORMSubsetConstraint
	                          sequences:@[ @[ [other firstObject] ], @[ [main firstObject] ] ]
	                             reason:NULL];
	NSArray *reports = [self fact:@"reportsTo" players:@[ employee, employee ] reading:@"{0} reports to {1}"
	                      inverse:@"{0} supervises {1}" uniqueness:@"1"];
	[_editor addRingConstraint:ORMRingAcyclic overRoles:reports reason:NULL];
	[self fact:@"earns" players:@[ employee, salary ] reading:@"{0} earns {1}" inverse:@"{0} is earned by {1}"
	    uniqueness:@"1!"];
	[self fact:@"drives" players:@[ employee, car ] reading:@"{0} drives {1}" inverse:@"{0} is driven by {1}"
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
	[_editor setMandatory:YES role:[heads lastObject] reason:NULL];
	[_editor addSetComparisonConstraint:ORMSubsetConstraint sequences:@[ heads, works ] reason:NULL];
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
	[_editor addSubtype:usBranch of:branch reason:NULL];
	NSString *achieved = [_editor addFactTypeWithPlayers:@[ usBranch, rank, year ] reading:@"{0} achieved {1} in {2}"
	                                           onDiagram:_diagram at:ORMAutomaticPlacement reason:NULL];
	NSArray *achievedRoles = [[[_editor.model elementWithId:achieved] roles] valueForKey:@"identifier"];
	[_editor addUniquenessConstraintOverRoles:@[ [achievedRoles objectAtIndex:0], [achievedRoles objectAtIndex:2] ]
	                                   reason:NULL];
	[_facts setObject:achievedRoles forKey:@"achieved"];
}

- (ORMQuery *)query:(NSString *)queryId
{
	return [ORMQuery queryWithId:queryId inModel:_editor.model];
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

/* A step from the node through the role; the nodes it reaches. */
- (NSArray<ORMQueryNode *> *)from:(NSString *)nodeId
                          through:(NSString *)roleId
                               in:(NSString *)queryId
                             step:(NSString **)stepId
{
	NSString *reason = nil;
	NSString *step = [_editor addStepTo:nodeId through:roleId reason:&reason];
	XCTAssertNotNil(step, @"%@", reason);
	if (stepId != NULL) {
		*stepId = step;
	}
	return [[self step:step of:queryId] nodes];
}

- (ORMQueryNode *)from:(NSString *)nodeId through:(NSString *)roleId in:(NSString *)queryId
{
	return [[self from:nodeId through:roleId in:queryId step:NULL] firstObject];
}

/* The role of the named fact type: 0 its first player's, 1 its second's. */
- (NSString *)role:(NSString *)fact at:(NSUInteger)index
{
	return [[_facts objectForKey:fact] objectAtIndex:index];
}

/* The subtype link's role the type plays. */
- (NSString *)subtyping:(NSString *)type supertype:(BOOL)supertype
{
	for (ORMRole *role in [ORMQuery rolesFrom:[_editor.model objectTypeNamed:type]]) {
		if (supertype ? role.isSupertypeMetaRole : role.isSubtypeMetaRole) {
			return role.identifier;
		}
	}
	return nil;
}

- (NSString *)english:(NSString *)queryId
{
	NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:_editor.model] sentencesForQuery:[self query:queryId]];
	return [[ORMVerbalizer plainTextOfSentences:sentences]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/* The default mapping, but for City, an entity rather than absorbed into
 * employees and branches. */
- (ORMCoreDataMapping *)mapping
{
	ORMCoreDataMapping *found = [[ORMCoreDataMapping mappingsOfDocument:_editor.document] firstObject];
	if (found != nil) {
		return found;
	}
	NSString *mapping = [_editor addCoreDataMappingNamed:@"Company" path:@"Company.xcdatamodeld"];
	[_editor setMapping:ORMMapAsEntity ofObjectType:[self typeId:@"City"] inMapping:mapping];
	return [ORMCoreDataMapping mappingWithId:mapping inDocument:_editor.document];
}

- (ORMQueryFetch *)fetch:(NSString *)queryId
{
	ORMQueryFetch *fetch = [[ORMQueryFetch alloc] initWithQuery:[self query:queryId] model:_editor.model
	                                                    mapping:[self mapping]];
	XCTAssertEqual([fetch.notes count], 0u, @"%@", fetch.notes);
	XCTAssertNotNil([NSPredicate predicateWithFormat:fetch.predicateFormat]);
	return fetch;
}

/* Q1: list each employee who lives in the city that is the location of
 * branch 52. City is the join: its composite identifier is beside the
 * point. */
- (NSString *)q1
{
	NSString *q = [_editor addQueryNamed:@"Q1" from:[self typeId:@"Employee"] reason:NULL];
	ORMQueryNode *city = [self from:[self root:q].identifier through:[self role:@"livesIn" at:0] in:q];
	ORMQueryNode *branch = [self from:city.identifier through:[self role:@"locatedIn" at:1] in:q];
	XCTAssertTrue([_editor setCondition:@"=" value:@"52" ofNode:branch.identifier reason:NULL]);
	return q;
}

- (void)testQ1IsAnOutlineOfSteps
{
	NSString *q = [self q1];
	XCTAssertEqualObjects([[self query:q] outlineText], @"✓Employee\n"
	                                                    @"  + lives in City\n"
	                                                    @"    + is location of Branch = 52\n");
	XCTAssertEqualObjects([[[self query:q] projectedNodes] valueForKeyPath:@"objectType.name"], (@[ @"Employee" ]));
	XCTAssertTrue([self query:q].isComplete);
}

- (void)testQ1IsSaidInFORML
{
	XCTAssertEqualObjects([self english:[self q1]],
	                      @"List each Employee where that Employee lives in some City that is location of some Branch "
	                      @"and that Branch is 52.");
}

- (void)testQ1IsAFetchRequest
{
	ORMQueryFetch *fetch = [self fetch:[self q1]];
	XCTAssertEqualObjects(fetch.entityName, @"Employee");
	XCTAssertEqualObjects(fetch.predicateFormat, @"SUBQUERY(city.branches, $x1, $x1.nr == 52).@count > 0");
	XCTAssertEqualObjects([fetch.columns valueForKey:@"keyPath"], (@[ @"self" ]));
	XCTAssertEqualObjects([[fetch.columns firstObject] identifierKeyPath], @"nr");
	XCTAssertTrue([[fetch objectiveCSource] rangeOfString:@"fetchRequestWithEntityName:@\"Employee\""].location
	              != NSNotFound);
}

/* Absorbed, City's parts are attributes of employees and branches: the
 * join is on their values, which a predicate cannot say. */
- (void)testQ1ThroughAnAbsorbedCityIsNoted
{
	ORMQueryFetch *fetch = [[ORMQueryFetch alloc] initWithQuery:[self query:[self q1]] model:_editor.model mapping:nil];
	XCTAssertFalse([fetch isComplete]);
	XCTAssertTrue([[fetch.notes firstObject] hasPrefix:@"City is absorbed into what uses it"], @"%@", fetch.notes);
}

/* Q2: employee drivers and their branches. */
- (void)testQ2
{
	NSString *q = [_editor addQueryNamed:@"Q2" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	[self from:root through:[self role:@"drives" at:0] in:q];
	ORMQueryNode *branch = [self from:root through:[self role:@"worksFor" at:0] in:q];
	[_editor setProjected:YES ofNode:branch.identifier];
	XCTAssertEqualObjects([[self query:q] outlineText], @"✓Employee\n"
	                                                    @"  + drives Car\n"
	                                                    @"  + works for ✓Branch\n");
	ORMQueryFetch *fetch = [self fetch:q];
	XCTAssertEqualObjects(fetch.predicateFormat, @"(cars.@count > 0) AND (branch != nil)");
	XCTAssertEqualObjects([fetch.columns valueForKey:@"keyPath"], (@[ @"self", @"branch" ]));
	XCTAssertEqualObjects([[fetch.columns lastObject] identifierKeyPath], @"branch.nr");
}

/* Q3: the US branches that did not achieve the top rank before 1998, and
 * the name and cars (if any) of each one's head. */
- (void)testQ3
{
	NSString *q = [_editor addQueryNamed:@"Q3" from:[self typeId:@"USbranch"] reason:NULL];
	NSString *root = [self root:q].identifier;
	NSString *notAchieved = nil;
	NSArray *achieved = [self from:root through:[self role:@"achieved" at:0] in:q step:&notAchieved];
	[_editor setOperator:ORMQueryNot ofStep:notAchieved];
	[_editor setCondition:@"=" value:@"1" ofNode:[[achieved firstObject] identifier] reason:NULL];
	[_editor setCondition:@"<" value:@"1998" ofNode:[[achieved lastObject] identifier] reason:NULL];
	ORMQueryNode *branch = [self from:root through:[self subtyping:@"USbranch" supertype:NO] in:q];
	ORMQueryNode *head = [self from:branch.identifier through:[self role:@"heads" at:1] in:q];
	ORMQueryNode *name = [self from:head.identifier through:[self role:@"hasName" at:0] in:q];
	[_editor setProjected:YES ofNode:name.identifier];
	NSString *maybe = nil;
	ORMQueryNode *car = [[self from:head.identifier through:[self role:@"drives" at:0] in:q step:&maybe] firstObject];
	[_editor setOperator:ORMQueryMaybe ofStep:maybe];
	[_editor setProjected:YES ofNode:car.identifier];

	XCTAssertEqualObjects([[self query:q] outlineText], @"✓USbranch\n"
	                                                    @"  + not achieved Rank = 1 in Year < 1998\n"
	                                                    @"  + is Branch\n"
	                                                    @"    + is headed by Employee\n"
	                                                    @"      + has ✓EmployeeName\n"
	                                                    @"      + maybe drives ✓Car\n");
	ORMQueryFetch *fetch = [self fetch:q];
	XCTAssertEqualObjects(fetch.entityName, @"USbranch");
	XCTAssertEqualObjects(fetch.predicateFormat, @"(NOT (SUBQUERY(uSbranchAchievedRankInYears, $x1, ($x1.rank.nr == 1) "
	                                             @"AND ($x1.year.ad < 1998)).@count > 0)) AND (employee.employeeName "
	                                             @"!= nil)");
	XCTAssertEqualObjects([fetch.columns valueForKey:@"title"], (@[ @"USbranch", @"EmployeeName", @"Car" ]));
	/* A US branch is known by its number, as a branch is. */
	XCTAssertEqualObjects([[fetch.columns firstObject] identifierKeyPath], @"nr");
	XCTAssertEqualObjects([[fetch.columns lastObject] identifierKeyPath], @"employee.cars.regnr");
}

/* Who speaks more than one language; who is above 100 and lives in a city
 * of Texas or speaks Latin. */
- (void)testCountsAndAlternatives
{
	NSString *polyglots = [_editor addQueryNamed:@"Polyglots" from:[self typeId:@"Employee"] reason:NULL];
	NSString *speaks = nil;
	[self from:[self root:polyglots].identifier through:[self role:@"speaks" at:0] in:polyglots step:&speaks];
	XCTAssertTrue([_editor setCount:@">" value:1 ofStep:speaks reason:NULL]);
	XCTAssertEqualObjects([self fetch:polyglots].predicateFormat, @"languages.@count > 1");
	XCTAssertTrue([[[self query:polyglots] outlineText] rangeOfString:@"count(Language) for Employee > 1"].location
	              != NSNotFound);
	XCTAssertTrue([[self english:polyglots] hasSuffix:@"the number of that Language is greater than 1."],
	              @"%@", [self english:polyglots]);

	NSString *q = [_editor addQueryNamed:@"Q" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	[_editor setCondition:@">" value:@"100" ofNode:root reason:NULL];
	[_editor setCombinesWithOr:YES ofNode:root];
	ORMQueryNode *country = [self from:root through:[self role:@"bornIn" at:0] in:q];
	[_editor setCondition:@"=" value:@"USA" ofNode:country.identifier reason:NULL];
	ORMQueryNode *language = [self from:root through:[self role:@"speaks" at:0] in:q];
	[_editor setCondition:@"=" value:@"Latin" ofNode:language.identifier reason:NULL];
	XCTAssertEqualObjects([self fetch:q].predicateFormat,
	                      @"(nr > 100) AND ((country.name == \"USA\") OR (SUBQUERY(languages, $x1, $x1.name == "
	                      @"\"Latin\").@count > 0))");
	XCTAssertTrue([[[self query:q] outlineText] rangeOfString:@"+ or speaks Language = 'Latin'"].location != NSNotFound);
}

/* The predicate means what the query says, on objects as key-value
 * coding finds them. */
- (void)testThePredicateSelects
{
	ORMQueryFetch *fetch = [self fetch:[self q1]];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:fetch.predicateFormat];
	NSDictionary *brisbane = @{ @"branches": [NSSet setWithObject:@{ @"nr": @52 }] };
	NSDictionary *sydney = @{ @"branches": [NSSet setWithObject:@{ @"nr": @7 }] };
	XCTAssertTrue([predicate evaluateWithObject:@{ @"city": brisbane }]);
	XCTAssertFalse([predicate evaluateWithObject:@{ @"city": sydney }]);
}

- (void)testAStepMustBeOneTheNodePlays
{
	NSString *q = [_editor addQueryNamed:@"Q" from:[self typeId:@"Employee"] reason:NULL];
	NSString *reason = nil;
	XCTAssertNil([_editor addStepTo:[self root:q].identifier through:[self role:@"carModel" at:0] reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"Employee"].location != NSNotFound, @"%@", reason);
	XCTAssertFalse([_editor setCondition:@"~" value:@"x" ofNode:[self root:q].identifier reason:&reason]);
}

/* Queries are in the document: saved, undone, and left out of what is
 * written for NORMA. */
- (void)testQueriesAreInTheDocument
{
	NSString *q = [self q1];
	NSData *saved = [_editor dataForSaving];
	ORMModel *reread = [ORMModel modelOfDocument:ORMParseDocument(saved, NULL) reason:NULL];
	ORMQuery *query = [ORMQuery queryWithId:q inModel:reread];
	XCTAssertEqualObjects([query outlineText], [[self query:q] outlineText]);
	XCTAssertTrue([[[NSString alloc] initWithData:saved encoding:NSUTF8StringEncoding]
	                  rangeOfString:@"xmlns:ormq=\"http://schemas.ormkit.org/2026-10/Queries\""]
	                  .location
	              != NSNotFound);

	NSXMLDocument *forNorma = [_editor documentForNorma];
	XCTAssertEqual([[ORMQuery queriesInModel:[ORMModel modelOfDocument:forNorma reason:NULL]] count], 0u);
	XCTAssertTrue([[forNorma XMLString] rangeOfString:@"ormkit.org/2026-10/Queries"].location == NSNotFound);

	[self.undoManager undo];
	XCTAssertTrue([[[self query:q] outlineText] rangeOfString:@"= 52"].location == NSNotFound);
	[_editor renameQuery:q to:@"Neighbours of 52" reason:NULL];
	XCTAssertEqualObjects([self query:q].name, @"Neighbours of 52");
	[_editor removeQuery:q];
	XCTAssertEqual([[ORMQuery queriesInModel:_editor.model] count], 0u);
}

/* A fact type the query went through is deleted: the step is left out. */
- (void)testDeletedFactTypesLeaveTheQueryIncomplete
{
	NSString *q = [self q1];
	ORMFactType *located = [[_editor.model elementWithId:[self role:@"locatedIn" at:0]] factType];
	[_editor deleteElements:@[ located.identifier ]];
	ORMQuery *query = [self query:q];
	XCTAssertFalse(query.isComplete);
	XCTAssertEqualObjects([query outlineText], @"✓Employee\n  + lives in City\n");
	ORMQueryFetch *fetch = [[ORMQueryFetch alloc] initWithQuery:query model:_editor.model mapping:nil];
	XCTAssertFalse([fetch isComplete]);
}

@end
