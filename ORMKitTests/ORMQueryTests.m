/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <ODataKit/ODataExpression.h>
#if defined(__APPLE__)
#import <CoreData/CoreData.h>
#import <ODataKit/ODataTransport.h>
#import <ODataService/ODataService.h>

/* An exchange with the service, waited for. */
@interface ORMTestExchangeWaiter : NSObject
@end

@implementation ORMTestExchangeWaiter
{
	dispatch_semaphore_t _done;
}
- (instancetype)init
{
	if ((self = [super init])) {
		_done = dispatch_semaphore_create(0);
	}
	return self;
}
- (void)exchangeDidFinish:(id)exchange
{
	(void)exchange;
	dispatch_semaphore_signal(_done);
}
- (BOOL)wait
{
	return dispatch_semaphore_wait(_done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC))) == 0;
}
@end
#endif

/* Conceptual queries (ORMQuery.h, ORMQueryFetch.h), on the schema and
 * queries of Halpin's "Conceptual Queries" (Database Newsletter 26:2,
 * figure 1): employees, the branches they work for and head, the cities
 * they live in (a city identified by its name and state, a state by its
 * code and country), the cars they drive, and US branches' ranks by year. */
@interface ORMQueryTests : ORMTestCase
@end

/* An object as key-value coding sees it, equal only to itself: what a
 * predicate walks, inverse relationships and all. */
@interface ORMTestThing : NSObject
@property (nonatomic, strong) NSMutableDictionary *values;
@end

@implementation ORMTestThing
- (instancetype)init
{
	if ((self = [super init])) {
		_values = [NSMutableDictionary dictionary];
	}
	return self;
}
- (id)valueForUndefinedKey:(NSString *)key
{
	return [self.values objectForKey:key];
}
- (void)setValue:(id)value forUndefinedKey:(NSString *)key
{
	[self.values setObject:value forKey:key];
}
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

/* A fact type with its reading (and inverse, if any); "1" makes the first
 * role unique (functional), "11" both (one to one), "*" spans the roles
 * (many to many); "!" makes the first role mandatory. */
- (NSArray<NSString *> *)fact:(NSString *)name
                      players:(NSArray *)players
                      reading:(NSString *)reading
                      inverse:(NSString *)inverse
                   uniqueness:(NSString *)uniqueness
{
	NSString *fact = [_editor.factTypeEditor addFactTypeWithPlayers:players reading:reading onDiagram:_diagram
	                                              at:ORMAutomaticPlacement reason:NULL];
	XCTAssertNotNil(fact, @"%@", reading);
	NSArray *roles = [[[_editor.model elementWithId:fact] roles] valueForKey:@"identifier"];
	if (inverse != nil) {
		NSString *reading = [_editor.factTypeEditor addReading:inverse forRoles:@[ [roles lastObject], [roles firstObject] ] reason:NULL];
		XCTAssertNotNil(reading, @"%@", inverse);
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
	XCTAssertTrue([_editor.constraintEditor setPreferredIdentifier:unique reason:NULL], @"%@", type);
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

/* A step from the node through the role; the nodes it reaches. */
- (NSArray<ORMQueryNode *> *)from:(NSString *)nodeId
                          through:(NSString *)roleId
                               in:(NSString *)queryId
                             step:(NSString **)stepId
{
	NSString *reason = nil;
	NSString *step = [[self queries] addStepTo:nodeId through:roleId reason:&reason];
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
	NSString *mapping = [[[ORMMappingEditor alloc] initWithEditor:_editor] addCoreDataMappingNamed:@"Company" path:@"Company.xcdatamodeld"];
	[[[ORMMappingEditor alloc] initWithEditor:_editor] setMapping:ORMMapAsEntity ofObjectType:[self typeId:@"City"] inMapping:mapping];
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

/* The query as a request to the service: no notes, and its filter is OData
 * ODataKit reads back as it was written. */
- (ORMQueryOData *)odata:(NSString *)queryId
{
	ORMQueryOData *odata = [self odata:queryId notes:0];
	XCTAssertEqual([odata.notes count], 0u, @"%@", odata.notes);
	return odata;
}

- (ORMQueryOData *)odata:(NSString *)queryId notes:(NSUInteger)notes
{
	ORMQueryOData *odata = [[ORMQueryOData alloc] initWithQuery:[self query:queryId] model:_editor.model
	                                                    mapping:[self mapping]];
	XCTAssertEqual([odata.notes count], notes, @"%@", odata.notes);
	if (odata.filter != nil) {
		NSError *error = nil;
		ODataExpression *reread = [ODataExpression expressionWithString:[odata.filter description] error:&error];
		XCTAssertEqualObjects([reread description], [odata.filter description], @"%@", error);
	}
	return odata;
}

/* Q1: list each employee who lives in the city that is the location of
 * branch 52. City is the join: its composite identifier is beside the
 * point. */
- (NSString *)q1
{
	NSString *q = [[self queries] addQueryNamed:@"Q1" from:[self typeId:@"Employee"] reason:NULL];
	ORMQueryNode *city = [self from:[self root:q].identifier through:[self role:@"livesIn" at:0] in:q];
	ORMQueryNode *branch = [self from:city.identifier through:[self role:@"locatedIn" at:1] in:q];
	XCTAssertTrue([[self queries] setCondition:@"=" value:@"52" ofNode:branch.identifier reason:NULL]);
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
	NSString *q1 = [self q1];
	ORMQueryFetch *fetch = [self fetch:q1];
	ORMQueryOData *odata = [self odata:q1];
	XCTAssertEqualObjects(odata.collectionPath, @"Employees");
	XCTAssertEqualObjects([odata queryText], @"$filter=City/Branches/any(x1:x1/Nr eq 52)&$select=Nr");
	/* ODataKit's query builder writes the URL: the same query, encoded. */
	NSURL *url = [odata URLWithServiceRoot:[NSURL URLWithString:@"http://example.test/odata/"] error:NULL];
	XCTAssertEqualObjects([url path], @"/odata/Employees");
	XCTAssertEqualObjects([[url query] stringByRemovingPercentEncoding], [odata queryText]);
	XCTAssertEqualObjects(fetch.entityName, @"Employee");
	XCTAssertEqualObjects(fetch.predicateFormat, @"SUBQUERY(city.branches, $x1, $x1.nr == 52).@count > 0");
	XCTAssertEqualObjects([fetch.columns valueForKey:@"keyPath"], (@[ @"self" ]));
	XCTAssertEqualObjects([[fetch.columns firstObject] identifierKeyPath], @"nr");
	XCTAssertTrue([[fetch objectiveCSource] rangeOfString:@"fetchRequestWithEntityName:@\"Employee\""].location
	              != NSNotFound);
}

/* Absorbed, City's parts are attributes of employees and branches, and no
 * relationship joins them: branch 52 is fetched first, and the employees
 * whose city parts are its. The query is the same; the request is two. */
- (void)testQ1JoinsThroughAnAbsorbedCity
{
	ORMQueryFetch *fetch = [[ORMQueryFetch alloc] initWithQuery:[self query:[self q1]] model:_editor.model mapping:nil];
	XCTAssertEqual([fetch.notes count], 0u, @"%@", fetch.notes);
	XCTAssertEqualObjects(fetch.entityName, @"Employee");
	XCTAssertEqualObjects(fetch.predicateFormat, @"cityCityname != nil");
	XCTAssertEqual([fetch.joins count], 1u);
	ORMQueryJoin *join = [fetch.joins firstObject];
	XCTAssertEqualObjects(join.entityName, @"Branch");
	XCTAssertEqualObjects(join.predicateFormat, @"nr == 52");
	NSArray *expected = @[ @[ @"cityCityname", @"cityCityname" ], @[ @"cityStateStatecode", @"cityStateStatecode" ],
	                       @[ @"cityStateCountry", @"cityStateCountry" ] ];
	XCTAssertEqualObjects(join.pairs, expected);

	/* Branch 52 is in Brisbane, Queensland, Australia: who lives there. */
	NSDictionary *australia = @{ @"name": @"Australia" };
	NSDictionary *branch = @{ @"cityCityname": @"Brisbane", @"cityStateStatecode": @"QLD", @"cityStateCountry": australia };
	NSPredicate *predicate = [fetch predicateJoining:@{ join.name: @[ branch ] }];
	NSDictionary *local = @{ @"cityCityname": @"Brisbane", @"cityStateStatecode": @"QLD", @"cityStateCountry": australia };
	NSDictionary *elsewhere = @{ @"cityCityname": @"Brisbane", @"cityStateStatecode": @"QLD",
	                             @"cityStateCountry": @{ @"name": @"Elsewhere" } };
	XCTAssertTrue([predicate evaluateWithObject:local]);
	XCTAssertFalse([predicate evaluateWithObject:elsewhere]);
	/* No such branch: nobody. */
	XCTAssertFalse([[fetch predicateJoining:@{ join.name: @[] }] evaluateWithObject:local]);

	NSString *source = [fetch objectiveCSource];
	XCTAssertTrue([source rangeOfString:@"cityCityname == %@ AND cityStateStatecode == %@ AND cityStateCountry == %@"]
	                  .location != NSNotFound, @"%@", source);
	XCTAssertTrue([source rangeOfString:@"orPredicateWithSubpredicates:join1Matches"].location != NSNotFound);

	/* The same two requests to the service. */
	ORMQueryOData *odata = [[ORMQueryOData alloc] initWithQuery:[self query:[self q1]] model:_editor.model mapping:nil];
	XCTAssertEqual([odata.notes count], 0u, @"%@", odata.notes);
	XCTAssertEqualObjects([odata queryText], @"$filter=CityCityname ne null&$select=Nr");
	ORMQueryODataJoin *branches = [odata.joins firstObject];
	NSURL *joinURL = [branches URLWithServiceRoot:[NSURL URLWithString:@"http://example.test/odata/"] error:NULL];
	XCTAssertEqualObjects([joinURL path], @"/odata/Branches");
	XCTAssertEqualObjects([[joinURL query] stringByRemovingPercentEncoding],
	                      @"$filter=Nr eq 52&$select=CityCityname,CityStateStatecode&$expand=CityStateCountry($select=Name)");
	/* A part that is an entity is compared by its key. */
	NSArray *wirePairs = @[ @[ @[ @"CityCityname" ], @[ @"CityCityname" ] ],
	                        @[ @[ @"CityStateStatecode" ], @[ @"CityStateStatecode" ] ],
	                        @[ @[ @"CityStateCountry", @"Name" ], @[ @"CityStateCountry", @"Name" ] ] ];
	XCTAssertEqualObjects(branches.pairs, wirePairs);
	NSDictionary *row = @{ @"CityCityname": @"Brisbane", @"CityStateStatecode": @"QLD",
	                       @"CityStateCountry": @{ @"Name": @"Australia" } };
	XCTAssertEqualObjects([[odata filterJoining:@{ branches.name: @[ row ] }] description],
	                      @"CityCityname ne null and (CityCityname eq 'Brisbane' and CityStateStatecode eq 'QLD' and "
	                      @"CityStateCountry/Name eq 'Australia')");
	XCTAssertEqualObjects([[odata filterJoining:@{ branches.name: @[] }] description], @"CityCityname ne null and false");
}

/* A join inside a not takes fetches within fetches: noted, not made. */
- (void)testAJoinUnderNotIsNoted
{
	NSString *q = [[self queries] addQueryNamed:@"Q" from:[self typeId:@"Employee"] reason:NULL];
	NSString *lives = nil;
	ORMQueryNode *city = [[self from:[self root:q].identifier through:[self role:@"livesIn" at:0] in:q step:&lives]
		firstObject];
	[[self queries] setOperator:ORMQueryNot ofStep:lives];
	ORMQueryNode *branch = [self from:city.identifier through:[self role:@"locatedIn" at:1] in:q];
	[[self queries] setCondition:@"=" value:@"52" ofNode:branch.identifier reason:NULL];
	ORMQueryFetch *fetch = [[ORMQueryFetch alloc] initWithQuery:[self query:q] model:_editor.model mapping:nil];
	XCTAssertFalse([fetch isComplete]);
	XCTAssertEqual([fetch.joins count], 0u);
	XCTAssertTrue([[fetch.notes firstObject] rangeOfString:@"inside a not"].location != NSNotFound, @"%@", fetch.notes);
}

/* Q2: employee drivers and their branches. */
- (NSString *)q2
{
	NSString *q = [[self queries] addQueryNamed:@"Q2" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	[self from:root through:[self role:@"drives" at:0] in:q];
	ORMQueryNode *branch = [self from:root through:[self role:@"worksFor" at:0] in:q];
	[[self queries] setProjected:YES ofNode:branch.identifier];
	return q;
}

- (void)testQ2
{
	NSString *q = [self q2];
	XCTAssertEqualObjects([[self query:q] outlineText], @"✓Employee\n"
	                                                    @"  + drives Car\n"
	                                                    @"  + works for ✓Branch\n");
	ORMQueryFetch *fetch = [self fetch:q];
	XCTAssertEqualObjects([[self odata:q] queryText], @"$filter=Cars/any() and Branch ne null&$select=Nr&"
	                                                   @"$expand=Branch($select=Nr)");
	XCTAssertEqualObjects(fetch.predicateFormat, @"(cars.@count > 0) AND (branch != nil)");
	XCTAssertEqualObjects([fetch.columns valueForKey:@"keyPath"], (@[ @"self", @"branch" ]));
	XCTAssertEqualObjects([[fetch.columns lastObject] identifierKeyPath], @"branch.nr");
}

/* Q3: the US branches that did not achieve the top rank before 1998, and
 * the name and cars (if any) of each one's head. */
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

- (void)testQ3
{
	NSString *q = [self q3];
	XCTAssertEqualObjects([[self query:q] outlineText], @"✓USbranch\n"
	                                                    @"  + not achieved Rank = 1 in Year < 1998\n"
	                                                    @"  + is Branch\n"
	                                                    @"    + is headed by Employee\n"
	                                                    @"      + has ✓EmployeeName\n"
	                                                    @"      + maybe drives ✓Car\n");
	ORMQueryFetch *fetch = [self fetch:q];
	ORMQueryOData *odata = [self odata:q];
	XCTAssertEqualObjects(odata.collectionPath, @"Branches/Default.USbranch");
	XCTAssertEqualObjects([odata queryText], @"$filter=not USbranchAchievedRankInYears/any(x1:x1/Rank/Nr eq 1 and "
	                                         @"x1/Year/Ad lt 1998) and Employee/EmployeeName ne null&$select=Nr&"
	                                         @"$expand=Employee($select=Nr,EmployeeName;$expand=Cars($select=Regnr))");
	XCTAssertEqualObjects(fetch.entityName, @"USbranch");
	XCTAssertEqualObjects(fetch.predicateFormat, @"(NOT (SUBQUERY(uSbranchAchievedRankInYears, $x1, ($x1.rank.nr == 1) "
	                                             @"AND ($x1.year.ad < 1998)).@count > 0)) AND (employee.employeeName "
	                                             @"!= nil)");
	XCTAssertEqualObjects([fetch.columns valueForKey:@"title"], (@[ @"USbranch", @"EmployeeName", @"Car" ]));
	/* A US branch is known by its number, as a branch is. */
	XCTAssertEqualObjects([[fetch.columns firstObject] identifierKeyPath], @"nr");
	XCTAssertEqualObjects([[fetch.columns lastObject] identifierKeyPath], @"employee.cars.regnr");
}

/* Q4: who supervises an employee who lives in the same city as the
 * supervisor but was born in a different country? Subscripts say which
 * occurrences are the same object, and a condition compares two. */
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
	XCTAssertTrue([[self queries] setCondition:@"<>" toNode:country.identifier ofNode:theirCountry.identifier
	                                    reason:&reason], @"%@", reason);
	XCTAssertFalse([[self queries] setCondition:@"=" toNode:city.identifier ofNode:theirCountry.identifier
	                                     reason:&reason]);

	return q;
}

- (void)testQ4Correlates
{
	NSString *q = [self q4];
	XCTAssertEqualObjects([[self query:q] outlineText], @"✓Employee1\n"
	                                                    @"  + lives in City1\n"
	                                                    @"  + was born in Country1\n"
	                                                    @"  + supervises Employee2\n"
	                                                    @"    + lives in City1\n"
	                                                    @"    + was born in Country2 <> Country1\n");
	XCTAssertEqualObjects([self english:q],
	                      @"List each Employee1 where Employee1 lives in some City and was born in some Country1 and "
	                      @"supervises some Employee2 that lives in that City and Employee2 was born in some Country2 "
	                      @"and Country2 is not Country1.");
	/* The supervised employee's city and country, against the supervisor's:
	 * a key path in the subquery is the fetched object's. */
	ORMQueryFetch *fetch = [self fetch:q];
	/* In the lambda, the supervisor is $it; a city, a surrogate's, by its key. */
	XCTAssertEqualObjects([[self odata:q] queryText], @"$filter=City ne null and Country ne null and "
	                                                   @"Employees/any(x1:x1/City/Id eq $it/City/Id and not "
	                                                   @"(x1/Country/Name eq $it/Country/Name))&$select=Nr");
	XCTAssertEqualObjects(fetch.predicateFormat, @"(city != nil) AND (country != nil) AND (SUBQUERY(employees, $x1, "
	                                             @"($x1.city == city) AND ($x1.country != country)).@count > 0)");
	NSDictionary *sydney = @{ @"name": @"Sydney" }, *perth = @{ @"name": @"Perth" };
	NSDictionary *australia = @{ @"name": @"Australia" }, *uk = @{ @"name": @"UK" };
	NSDictionary *migrant = @{ @"city": sydney, @"country": uk };
	NSDictionary *local = @{ @"city": sydney, @"country": australia };
	NSDictionary *away = @{ @"city": perth, @"country": uk };
	NSPredicate *predicate = [NSPredicate predicateWithFormat:fetch.predicateFormat];
	BOOL holds1 = [predicate evaluateWithObject:@{ @"city": sydney, @"country": australia,
	                                               @"employees": [NSSet setWithObjects:local, migrant, nil] }];
	XCTAssertTrue(holds1);
	BOOL holds2 = [predicate evaluateWithObject:@{ @"city": sydney, @"country": australia,
	                                                @"employees": [NSSet setWithObjects:local, away, nil] }];
	XCTAssertFalse(holds2);
}

/* Q5: who owns a car, and does not drive more than one of the cars they
 * own? Car1, met through a to-many, is a set where it is met again. */
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

- (void)testQ5CorrelatesWithASet
{
	NSString *q = [self q5];
	XCTAssertEqualObjects([[self query:q] outlineText], @"✓Employee\n"
	                                                    @"  + owns Car1\n"
	                                                    @"  + not drives Car1\n"
	                                                    @"    + count(Car1) for Employee > 1\n");
	XCTAssertEqualObjects([self english:q], @"List each Employee where that Employee owns some Car and it is not "
	                                        @"true that that Employee drives that Car and the number of that Car is "
	                                        @"greater than 1.");
	/* ConQuer-II's S5: the cars driven that are among those owned, found
	 * from each car back to its owners. */
	ORMQueryFetch *fetch = [self fetch:q];
	/* The cars driven that are among those owned, counted (OData 4.01): in
	 * the count's filter the car is $this, the employee still $it. */
	XCTAssertEqualObjects([[self odata:q] queryText], @"$filter=OwnsCars/any() and not (Cars/$count($filter="
	                                                   @"$this/IsOwnedByEmployees/any(x3:x3/Nr eq $it/Nr)) gt 1)&"
	                                                   @"$select=Nr");
	XCTAssertEqualObjects(fetch.predicateFormat, @"(ownsCars.@count > 0) AND (NOT (SUBQUERY(cars, $x2, ANY "
	                                             @"$x2.isOwnedByEmployees == SELF).@count > 1))");
	NSPredicate *predicate = [NSPredicate predicateWithFormat:fetch.predicateFormat];
	ORMTestThing *(^employee)(NSArray *, NSArray *) = ^ORMTestThing *(NSArray *owned, NSArray *driven) {
		ORMTestThing *person = [[ORMTestThing alloc] init];
		[person setValue:[NSSet setWithArray:owned] forKey:@"ownsCars"];
		[person setValue:[NSSet setWithArray:driven] forKey:@"cars"];
		for (ORMTestThing *car in owned) {
			[[car valueForKey:@"isOwnedByEmployees"] addObject:person];
		}
		return person;
	};
	ORMTestThing *(^car)(void) = ^ORMTestThing *(void) {
		ORMTestThing *thing = [[ORMTestThing alloc] init];
		[thing setValue:[NSMutableSet set] forKey:@"isOwnedByEmployees"];
		return thing;
	};
	ORMTestThing *a = car(), *b = car(), *c = car();
	/* Owns two and drives both: more than one. */
	XCTAssertFalse([predicate evaluateWithObject:employee(@[ a, b ], @[ a, b ])]);
	/* Drives two, one of them their own. */
	XCTAssertTrue([predicate evaluateWithObject:employee(@[ c ], @[ c, a ])]);
	/* Owns none. */
	XCTAssertFalse([predicate evaluateWithObject:employee(@[], @[ a ])]);
}

/* ConQuer-II's: "what are the branches and total salary costs of branches
 * with a total salary cost of more than $1 000 000?", the richest first. */
- (NSString *)payroll
{
	NSString *q = [[self queries] addQueryNamed:@"Payroll" from:[self typeId:@"Branch"] reason:NULL];
	NSString *root = [self root:q].identifier;
	NSString *employs = nil;
	ORMQueryNode *employee = [[self from:root through:[self role:@"worksFor" at:1] in:q step:&employs] firstObject];
	ORMQueryNode *salary = [self from:employee.identifier through:[self role:@"earns" at:0] in:q];
	NSString *reason = nil;
	XCTAssertTrue([[self queries] setAggregate:ORMQueryTotal ofNode:salary.identifier comparison:@">" value:@"1000000"
	                                    ofStep:employs reason:&reason], @"%@", reason);
	XCTAssertFalse([[self queries] setAggregate:ORMQueryTotal ofNode:root comparison:@">" value:@"1" ofStep:employs
	                                     reason:&reason]);
	[[self queries] setSortOrder:ORMQueryDescending ofNode:root];

	return q;
}

- (void)testTotalsAndSorting
{
	NSString *q = [self payroll];
	XCTAssertEqualObjects([[self query:q] outlineText], @"✓Branch ↓\n"
	                                                    @"  + employs Employee\n"
	                                                    @"    + total(Salary) for Branch > 1000000\n"
	                                                    @"    + earns Salary\n");
	XCTAssertTrue([[self english:q] hasSuffix:@"the total of that Salary is greater than 1000000 in descending order of "
	                                          @"Branch."], @"%@", [self english:q]);
	ORMQueryFetch *fetch = [self fetch:q];
	ORMQueryOData *odata = [self odata:q];
	XCTAssertEqualObjects([odata queryText], @"$filter=Employees/aggregate(Salary/Usd with sum) gt 1000000&"
	                                         @"$orderby=Nr desc&$select=Nr");
	XCTAssertEqualObjects(fetch.predicateFormat, @"employees.@sum.salary.usd > 1000000");
	XCTAssertEqualObjects(fetch.sortDescriptors, @[ [NSSortDescriptor sortDescriptorWithKey:@"nr" ascending:NO] ]);
	XCTAssertTrue([[fetch objectiveCSource] rangeOfString:@"sortDescriptorWithKey:@\"nr\" ascending:NO"].location
	              != NSNotFound);

	NSPredicate *predicate = [NSPredicate predicateWithFormat:fetch.predicateFormat];
	NSDictionary *rich = @{ @"employees": [NSSet setWithObjects:@{ @"salary": @{ @"usd": @600000 } },
	                                                            @{ @"salary": @{ @"usd": @500000 } }, nil] };
	NSDictionary *poor = @{ @"employees": [NSSet setWithObject:@{ @"salary": @{ @"usd": @900000 } }] };
	BOOL richHolds = [predicate evaluateWithObject:rich];
	BOOL poorHolds = [predicate evaluateWithObject:poor];
	XCTAssertTrue(richHolds);
	XCTAssertFalse(poorHolds);
}

/* Who speaks more than one language; who is above 100 and lives in a city
 * of Texas or speaks Latin. */
- (void)testCountsAndAlternatives
{
	NSString *polyglots = [[self queries] addQueryNamed:@"Polyglots" from:[self typeId:@"Employee"] reason:NULL];
	NSString *speaks = nil;
	[self from:[self root:polyglots].identifier through:[self role:@"speaks" at:0] in:polyglots step:&speaks];
	XCTAssertTrue([[self queries] setCount:@">" value:1 ofStep:speaks reason:NULL]);
	XCTAssertEqualObjects([self fetch:polyglots].predicateFormat, @"languages.@count > 1");
	XCTAssertEqualObjects([[self odata:polyglots] queryText], @"$filter=Languages/$count gt 1&$select=Nr");
	XCTAssertTrue([[[self query:polyglots] outlineText] rangeOfString:@"count(Language) for Employee > 1"].location
	              != NSNotFound);
	XCTAssertTrue([[self english:polyglots] hasSuffix:@"the number of that Language is greater than 1."],
	              @"%@", [self english:polyglots]);

	NSString *q = [[self queries] addQueryNamed:@"Q" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	[[self queries] setCondition:@">" value:@"100" ofNode:root reason:NULL];
	[[self queries] setCombinesWithOr:YES ofNode:root];
	ORMQueryNode *country = [self from:root through:[self role:@"bornIn" at:0] in:q];
	[[self queries] setCondition:@"=" value:@"USA" ofNode:country.identifier reason:NULL];
	ORMQueryNode *language = [self from:root through:[self role:@"speaks" at:0] in:q];
	[[self queries] setCondition:@"=" value:@"Latin" ofNode:language.identifier reason:NULL];
	XCTAssertEqualObjects([self fetch:q].predicateFormat,
	                      @"(nr > 100) AND ((country.name == \"USA\") OR (SUBQUERY(languages, $x1, $x1.name == "
	                      @"\"Latin\").@count > 0))");
	XCTAssertTrue([[[self query:q] outlineText] rangeOfString:@"+ or speaks Language = 'Latin'"].location != NSNotFound);
	XCTAssertEqualObjects([[self odata:q] queryText], @"$filter=Nr gt 100 and (Country/Name eq 'USA' or "
	                                                   @"Languages/any(x1:x1/Name eq 'Latin'))&$select=Nr");
}

/* A name that is no identifier could carry filter text into a request.
 * An override in a .orm is not used by the mapping; one that reaches the
 * request anyway (a model's OData.property, set by hand) is refused by
 * ODataKit's builders, and the request is not written. */
- (void)testANameThatIsNoIdentifierIsRefused
{
	NSString *q = [self q1];
	ORMCoreDataMapping *mapping = [self mapping];
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:_editor.model mapping:mapping] map];
	NSString *source = [[[mapped entityNamed:@"Employee"] attributeNamed:@"nr"] source];
	XCTAssertNotNil(source);
	[[[ORMMappingEditor alloc] initWithEditor:_editor] setName:@"nr eq 0 or true" forSource:source
	                                                 inMapping:mapping.identifier];
	ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMCDModel *remapped = [mapper map];
	XCTAssertNotNil([[remapped entityNamed:@"Employee"] attributeNamed:@"nr"]);
	BOOL noted = NO;
	for (ORMMappingNote *note in mapper.notes) {
		noted = noted || [note.text rangeOfString:@"no name Core Data allows"].location != NSNotFound;
	}
	XCTAssertTrue(noted, @"%@", mapper.notes);
	XCTAssertEqualObjects([[self odata:q] queryText], @"$filter=City/Branches/any(x1:x1/Nr eq 52)&$select=Nr");

	ORMCDAttribute *nr = [[remapped entityNamed:@"Employee"] attributeNamed:@"nr"];
	NSMutableDictionary *info = [nr.userInfo mutableCopy];
	[info setObject:@"Nr eq 0 or true" forKey:@"OData.property"];
	nr.userInfo = info;
	ORMQueryOData *odata = [[ORMQueryOData alloc] initWithQuery:[self query:q] coreData:remapped];
	XCTAssertFalse([odata isComplete]);
	XCTAssertTrue([[odata.notes lastObject] rangeOfString:@"cannot be written"].location != NSNotFound, @"%@", odata.notes);
	XCTAssertNil([odata URLWithServiceRoot:[NSURL URLWithString:@"http://example.test/odata/"] error:NULL]);
	XCTAssertNil(odata.filter);
}

/* The predicate means what the query says, on objects as key-value
 * coding finds them. */
- (void)testThePredicateSelects
{
	ORMQueryFetch *fetch = [self fetch:[self q1]];
	NSPredicate *predicate = [NSPredicate predicateWithFormat:fetch.predicateFormat];
	NSDictionary *brisbane = @{ @"branches": [NSSet setWithObject:@{ @"nr": @52 }] };
	NSDictionary *sydney = @{ @"branches": [NSSet setWithObject:@{ @"nr": @7 }] };
	BOOL holds5 = [predicate evaluateWithObject:@{ @"city": brisbane }];
	XCTAssertTrue(holds5);
	BOOL holds6 = [predicate evaluateWithObject:@{ @"city": sydney }];
	XCTAssertFalse(holds6);
}

- (void)testAStepMustBeOneTheNodePlays
{
	NSString *q = [[self queries] addQueryNamed:@"Q" from:[self typeId:@"Employee"] reason:NULL];
	NSString *reason = nil;
	XCTAssertNil([[self queries] addStepTo:[self root:q].identifier through:[self role:@"carModel" at:0] reason:&reason]);
	XCTAssertTrue([reason rangeOfString:@"Employee"].location != NSNotFound, @"%@", reason);
	XCTAssertFalse([[self queries] setCondition:@"~" value:@"x" ofNode:[self root:q].identifier reason:&reason]);
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
	[[self queries] renameQuery:q to:@"Neighbours of 52" reason:NULL];
	XCTAssertEqualObjects([self query:q].name, @"Neighbours of 52");
	[[self queries] removeQuery:q];
	XCTAssertEqual([[ORMQuery queriesInModel:_editor.model] count], 0u);
}

/* A fact type the query went through is deleted: the step is left out. */
- (void)testDeletedFactTypesLeaveTheQueryIncomplete
{
	NSString *q = [self q1];
	ORMFactType *located = [[_editor.model elementWithId:[self role:@"locatedIn" at:0]] factType];
	[_editor.elementEditor deleteElements:@[ located.identifier ]];
	ORMQuery *query = [self query:q];
	XCTAssertFalse(query.isComplete);
	XCTAssertEqualObjects([query outlineText], @"✓Employee\n  + lives in City\n");
	ORMQueryFetch *fetch = [[ORMQueryFetch alloc] initWithQuery:query model:_editor.model mapping:nil];
	XCTAssertFalse([fetch isComplete]);
}

#if defined(__APPLE__)
/* The requests, sent to ODataKit's service over the mapped model in a
 * SQLite store: the rows the paper's queries ask for. */
- (void)testTheServiceAnswersTheQueries
{
	NSString *q1 = [self q1], *q2 = [self q2], *q3 = [self q3], *q4 = [self q4], *q5 = [self q5];
	NSString *payroll = [self payroll];
	NSString *polyglots = [[self queries] addQueryNamed:@"Polyglots" from:[self typeId:@"Employee"] reason:NULL];
	NSString *speaks = nil;
	[self from:[self root:polyglots].identifier through:[self role:@"speaks" at:0] in:polyglots step:&speaks];
	[[self queries] setCount:@">" value:1 ofStep:speaks reason:NULL];

	/* The mapping as an application has it: compiled, in a store. */
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:_editor.model mapping:[self mapping]] map];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	NSString *package = [directory stringByAppendingPathComponent:@"Company.xcdatamodeld"];
	NSString *compiled = [directory stringByAppendingPathComponent:@"Company.momd"];
	NSError *error = nil;
	XCTAssertTrue([mapped writeToPackage:package error:&error], @"%@", error);
	NSTask *momc = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/xcrun" arguments:@[ @"momc", package, compiled ]];
	[momc waitUntilExit];
	NSManagedObjectModel *model = [[NSManagedObjectModel alloc] initWithContentsOfURL:[NSURL fileURLWithPath:compiled]];
	XCTAssertNotNil(model);
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	XCTAssertNotNil([coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
	                                                    URL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"Company.sqlite"]]
	                                                options:nil error:&error], @"%@", error);
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	context.persistentStoreCoordinator = coordinator;
	[context performBlockAndWait:^{
		NSManagedObject *(^make)(NSString *, NSDictionary *) = ^NSManagedObject *(NSString *entity, NSDictionary *values) {
			NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:context];
			[object setValuesForKeysWithDictionary:values];
			return object;
		};
		NSManagedObject *australia = make(@"Country", @{ @"name": @"Australia" });
		NSManagedObject *usa = make(@"Country", @{ @"name": @"USA" });
		NSManagedObject *uk = make(@"Country", @{ @"name": @"UK" });
		/* A city is identified by its name and state: in OData, by the
		 * number the service would give it. */
		NSManagedObject *brisbane = make(@"City", @{ @"id": @1, @"cityname": @"Brisbane", @"stateStatecode": @"QLD",
		                                             @"stateCountry": australia });
		NSManagedObject *sydney = make(@"City", @{ @"id": @2, @"cityname": @"Sydney", @"stateStatecode": @"NSW",
		                                           @"stateCountry": australia });
		NSManagedObject *perth = make(@"City", @{ @"id": @3, @"cityname": @"Perth", @"stateStatecode": @"WA",
		                                          @"stateCountry": australia });
		NSManagedObject *seattle = make(@"City", @{ @"id": @4, @"cityname": @"Seattle", @"stateStatecode": @"WA",
		                                            @"stateCountry": usa });
		NSDictionary *salaries = @{ @50: make(@"Salary", @{ @"usd": @50000 }), @500: make(@"Salary", @{ @"usd": @500000 }),
		                            @600: make(@"Salary", @{ @"usd": @600000 }) };
		NSManagedObject *(^employee)(int, NSManagedObject *, NSManagedObject *, int) =
			^NSManagedObject *(int nr, NSManagedObject *city, NSManagedObject *country, int thousands) {
			return make(@"Employee", @{ @"nr": @(nr), @"employeeName": [NSString stringWithFormat:@"E%d", nr], @"city": city,
			                            @"country": country, @"salary": [salaries objectForKey:@(thousands)] });
		};
		NSManagedObject *e1 = employee(1, brisbane, australia, 600), *e2 = employee(2, sydney, australia, 500);
		NSManagedObject *e3 = employee(3, brisbane, australia, 500), *e4 = employee(4, seattle, usa, 50);
		NSManagedObject *e5 = employee(5, seattle, usa, 50), *e10 = employee(10, sydney, uk, 600);
		NSManagedObject *e21 = employee(21, perth, uk, 50);
		/* Bea supervises an employee of her city born elsewhere; Ann one
		 * of another city. */
		[e10 setValue:e2 forKey:@"employee"];
		[e21 setValue:e1 forKey:@"employee"];
		NSManagedObject *b52 = make(@"Branch", @{ @"nr": @52, @"city": brisbane, @"employee": e1 });
		NSManagedObject *b7 = make(@"Branch", @{ @"nr": @7, @"city": sydney, @"employee": e2 });
		NSManagedObject *us1 = make(@"USbranch", @{ @"nr": @101, @"city": seattle, @"employee": e4 });
		NSManagedObject *us2 = make(@"USbranch", @{ @"nr": @102, @"city": seattle, @"employee": e5 });
		for (NSArray *works in @[ @[ e1, b52 ], @[ e3, b52 ], @[ e2, b7 ], @[ e10, b7 ], @[ e21, b7 ], @[ e4, us1 ],
		                          @[ e5, us2 ] ]) {
			[[works firstObject] setValue:[works lastObject] forKey:@"branch"];
		}
		NSManagedObject *ute = make(@"CarModel", @{ @"name": @"Ute" });
		NSManagedObject *a = make(@"Car", @{ @"regnr": @"A", @"carModel": ute });
		NSManagedObject *b = make(@"Car", @{ @"regnr": @"B", @"carModel": ute });
		NSManagedObject *c = make(@"Car", @{ @"regnr": @"C", @"carModel": ute });
		[[e1 mutableSetValueForKey:@"cars"] addObject:c];
		[[e3 mutableSetValueForKey:@"cars"] addObjectsFromArray:@[ a, b ]];
		[[e4 mutableSetValueForKey:@"cars"] addObject:a];
		/* Q5's owners: Ann drives none of hers, Cal both of his, Dee one. */
		[[e1 mutableSetValueForKey:@"ownsCars"] addObject:b];
		[[e3 mutableSetValueForKey:@"ownsCars"] addObjectsFromArray:@[ a, b ]];
		[[e4 mutableSetValueForKey:@"ownsCars"] addObject:a];
		NSManagedObject *english = make(@"Language", @{ @"name": @"English" });
		NSManagedObject *latin = make(@"Language", @{ @"name": @"Latin" });
		[[e1 mutableSetValueForKey:@"languages"] addObjectsFromArray:@[ english, latin ]];
		[[e2 mutableSetValueForKey:@"languages"] addObject:english];
		NSManagedObject *first = make(@"Rank", @{ @"nr": @1 }), *second = make(@"Rank", @{ @"nr": @2 });
		NSManagedObject *y1995 = make(@"Year", @{ @"ad": @1995 }), *y1996 = make(@"Year", @{ @"ad": @1996 });
		NSManagedObject *y2001 = make(@"Year", @{ @"ad": @2001 });
		make(@"USbranchAchievedRankInYear", @{ @"id": @1, @"uSbranch": us1, @"rank": first, @"year": y1995 });
		make(@"USbranchAchievedRankInYear", @{ @"id": @2, @"uSbranch": us2, @"rank": first, @"year": y2001 });
		make(@"USbranchAchievedRankInYear", @{ @"id": @3, @"uSbranch": us2, @"rank": second, @"year": y1996 });
		NSError *saveError = nil;
		XCTAssertTrue([context save:&saveError], @"%@", [saveError userInfo]);
	}];

	ODataService *service = [[ODataService alloc] initWithPersistentStoreCoordinator:coordinator
	                                                                     serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
	NSArray *(^numbers)(NSString *) = ^NSArray *(NSString *queryId) {
		ORMQueryOData *odata = [self odata:queryId];
		NSError *urlError = nil;
		NSURL *url = [odata URLWithServiceRoot:[NSURL URLWithString:@"http://example.test/odata/"] error:&urlError];
		XCTAssertNotNil(url, @"%@", urlError);
		ORMTestExchangeWaiter *waiter = [[ORMTestExchangeWaiter alloc] init];
		ODataExchange *exchange = [[ODataExchange alloc] initWithRequest:[NSURLRequest requestWithURL:url] target:waiter
		                                                          action:@selector(exchangeDidFinish:)];
		[service startExchange:exchange];
		XCTAssertTrue([waiter wait]);
		NSInteger status = ((NSHTTPURLResponse *)exchange.URLResponse).statusCode;
		NSString *body = [[NSString alloc] initWithData:exchange.data ?: [NSData data] encoding:NSUTF8StringEncoding];
		XCTAssertEqual(status, 200, @"%@: %@", url, body);
		NSDictionary *answer = [NSJSONSerialization JSONObjectWithData:exchange.data ?: [NSData data] options:0 error:NULL];
		return [[answer objectForKey:@"value"] valueForKey:@"Nr"];
	};
	NSArray *(^sorted)(NSArray *) = ^NSArray *(NSArray *values) {
		return [values sortedArrayUsingSelector:@selector(compare:)];
	};
	XCTAssertEqualObjects(sorted(numbers(q1)), (@[ @1, @3 ]));
	XCTAssertEqualObjects(sorted(numbers(q2)), (@[ @1, @3, @4 ]));
	XCTAssertEqualObjects(sorted(numbers(q3)), (@[ @102 ]));
	XCTAssertEqualObjects(sorted(numbers(q4)), (@[ @2 ]));
	XCTAssertEqualObjects(sorted(numbers(q5)), (@[ @1, @4 ]));
	/* In the order the query asks for: the larger number first. */
	XCTAssertEqualObjects(numbers(payroll), (@[ @52, @7 ]));
	XCTAssertEqualObjects(sorted(numbers(polyglots)), (@[ @1 ]));
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}
#endif

@end

