/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <ODataKit/ODataExpression.h>
#import <CoreData/CoreData.h>
#import <ODataKit/ODataTransport.h>
#import <ODataService/ODataService.h>

/* A transport that counts the requests it carries to the service. */
@interface ORMTestCountingTransport : NSObject <ODataTransport>
@property (nonatomic, strong) id<ODataTransport> service;
@property (atomic) NSUInteger requests;
@property (atomic, strong) NSMutableArray<NSString *> *paths;
/* Each request's query, decoded. */
@property (atomic, strong) NSMutableArray<NSString *> *queries;
@end

@implementation ORMTestCountingTransport
- (void)startExchange:(ODataExchange *)exchange
{
	self.requests++;
	[self.paths addObject:[[exchange.request.URL path] lastPathComponent] ?: @""];
	[self.queries addObject:[[exchange.request.URL query] stringByRemovingPercentEncoding] ?: @""];
	[self.service startExchange:exchange];
}
@end

/* A cursor over batches given beforehand. */
@interface ORMTestBatches : NSObject <ORMCursor>
@property (nonatomic, strong) NSMutableArray<NSArray *> *batches;
@end

@implementation ORMTestBatches
- (BOOL)atEnd
{
	return [self.batches count] == 0;
}
- (void)next:(NSUInteger)count completion:(void (^)(ORMBatch *batch, NSError *error))completion
{
	(void)count;
	NSArray *objects = [self.batches firstObject] ?: @[];
	if ([self.batches count] > 0) {
		[self.batches removeObjectAtIndex:0];
	}
	completion([ORMBatch batchWithObjects:objects answers:@{}], nil);
}
@end

/* Rows given beforehand, by object. */
@interface ORMTestRows : NSObject <ORMBatchEvaluator>
@property (nonatomic, copy) NSDictionary<NSString *, id> *answers;
@property (nonatomic, copy) NSDictionary *rows;
@end

@implementation ORMTestRows
- (BOOL)keeps:(id)object
{
	(void)object;
	return YES;
}
- (NSArray<NSArray *> *)rowsOf:(id)object
{
	return [self.rows objectForKey:object];
}
@end

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

/* Conceptual queries (ORMQuery.h): planned (ORMQueryPlanner.h), run against
 * a store (ORMQueryInterpreter.h) and sent to a service (ORMQueryOData.h),
 * on the schema and
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

- (void)tearDown
{
	_editor = nil;
	_facts = nil;
	[super tearDown];
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

/* What the interpreter does to run the query's plan, to read. */
- (NSString *)program:(NSString *)queryId
{
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	NSError *error = nil;
	NSString *program = [interpreter programForPlan:[planner planForQuery:[self query:queryId]] error:&error];
	XCTAssertNotNil(program, @"%@", error);
	return program;
}

/* The query planned through the test's mapping. */
- (ORMQueryPlan *)plan:(NSString *)queryId
{
	return [[[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]] planForQuery:[self query:queryId]];
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
	NSError *error = nil;
	ORMQueryOData *odata = [ORMQueryOData requestForQuery:[self query:queryId] model:_editor.model mapping:[self mapping]
	                                                error:&error];
	XCTAssertNotNil(odata, @"%@", error);
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

- (void)testQ1IsAPlanAndARequest
{
	NSString *q1 = [self q1];
	XCTAssertEqualObjects([[self plan:q1] text], @"read Employee\n"
	                                               @"where some city.branches as x1 has x1.nr = 52\n"
	                                               @"list self (nr)");
	ORMQueryOData *odata = [self odata:q1];
	XCTAssertEqualObjects(odata.collectionPath, @"Employees");
	XCTAssertEqualObjects([odata queryText], @"$filter=City/Branches/any(x1:x1/Nr eq 52)&$select=Nr");
	/* ODataKit's query builder writes the URL: the same query, encoded. */
	NSURL *url = [odata URLWithServiceRoot:[NSURL URLWithString:@"http://example.test/odata/"] error:NULL];
	XCTAssertEqualObjects([url path], @"/odata/Employees");
	XCTAssertEqualObjects([[url query] stringByRemovingPercentEncoding], [odata queryText]);
	ORMQueryPlan *plan = [self plan:q1];
	XCTAssertEqualObjects(plan.entityName, @"Employee");
	XCTAssertEqualObjects([[plan.columns firstObject] identifierKey], @"nr");
}

/* Absorbed, City's parts are attributes of employees and branches, and no
 * relationship joins them: branch 52 is fetched first, and the employees
 * whose city parts are its. The query is the same; the request is two. */
- (void)testQ1JoinsThroughAnAbsorbedCity
{
	/* From the service: the employees a page at a time, selecting their city
	 * parts, and for each page the branches' parts among them, grouped. */
	ORMQueryOData *odata = [ORMQueryOData requestForQuery:[self query:[self q1]] model:_editor.model mapping:nil error:NULL];
	XCTAssertEqual([odata.notes count], 0u, @"%@", odata.notes);
	XCTAssertEqual([odata.joins count], 0u);
	XCTAssertEqualObjects([odata queryText], @"$select=Nr,CityCityname,CityStateStatecode&$expand=CityStateCountry($select=Name)");
	ORMQueryODataJoin *branches = [odata.pageJoins firstObject];
	XCTAssertEqualObjects(branches.collectionPath, @"Branches");
	/* A part that is an entity is compared by its key. */
	NSArray *wirePairs = @[ @[ @[ @"CityCityname" ], @[ @"CityCityname" ] ],
	                        @[ @[ @"CityStateStatecode" ], @[ @"CityStateStatecode" ] ],
	                        @[ @[ @"CityStateCountry", @"Name" ], @[ @"CityStateCountry", @"Name" ] ] ];
	XCTAssertEqualObjects(branches.pairs, wirePairs);
	XCTAssertTrue([[odata requestText] rangeOfString:@"for each page, page1: GET Branches?$filter=Nr eq 52"].location
	              != NSNotFound, @"%@", [odata requestText]);
}

/* A join inside a not: the joined objects are fetched first wherever the
 * join is, and the plan says not of their match. */
- (void)testAJoinUnderNotIsPlanned
{
	NSString *q = [[self queries] addQueryNamed:@"Q" from:[self typeId:@"Employee"] reason:NULL];
	NSString *lives = nil;
	ORMQueryNode *city = [[self from:[self root:q].identifier through:[self role:@"livesIn" at:0] in:q step:&lives]
		firstObject];
	[[self queries] setOperator:ORMQueryNot ofStep:lives];
	ORMQueryNode *branch = [self from:city.identifier through:[self role:@"locatedIn" at:1] in:q];
	[[self queries] setCondition:@"=" value:@"52" ofNode:branch.identifier reason:NULL];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	XCTAssertEqual([plan.notes count], 0u, @"%@", plan.notes);
	XCTAssertEqualObjects(plan.condition.kind == ORMPlanNot ? @(plan.condition.operand.kind) : nil, @(ORMPlanMatches),
	                      @"%@", [plan text]);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:NULL];
	XCTAssertEqualObjects([odata queryText], @"$filter=not @join1&$select=Nr");
	XCTAssertEqual([odata.joins count], 1u);
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
	XCTAssertEqualObjects([[self plan:q] text], @"read Employee\n"
	                                              @"where some cars and branch is set\n"
	                                              @"list self (nr), branch (nr)");
	XCTAssertEqualObjects([[self odata:q] queryText], @"$filter=Cars/any() and Branch ne null&$select=Nr&"
	                                                   @"$expand=Branch($select=Nr)");
	XCTAssertEqualObjects([self program:q], @"fetch Employee where (cars.@count > 0) AND (branch != nil)\n"
	                                        @"sorted by nr; each batch after the last one's");
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
	XCTAssertEqualObjects([[self plan:q] text], @"read USbranch\n"
	                                              @"where not (some uSbranchAchievedRankInYears as x1 has (x1.rank.nr = 1 "
	                                              @"and x1.year.ad < 1998)) and employee.employeeName is set and maybe "
	                                              @"employee.cars as x2\n"
	                                              @"list self (nr), employee.employeeName, x2 (regnr)");
	ORMQueryOData *odata = [self odata:q];
	XCTAssertEqualObjects(odata.collectionPath, @"Branches/Default.USbranch");
	XCTAssertEqualObjects([odata queryText], @"$filter=not USbranchAchievedRankInYears/any(x1:x1/Rank/Nr eq 1 and "
	                                         @"x1/Year/Ad lt 1998) and Employee/EmployeeName ne null&$select=Nr&"
	                                         @"$expand=Employee($select=Nr,EmployeeName;$expand=Cars($select=Regnr))");
	ORMQueryPlan *plan = [self plan:q];
	XCTAssertEqualObjects(plan.entityName, @"USbranch");
	XCTAssertEqualObjects([plan.columns valueForKey:@"title"], (@[ @"USbranch", @"EmployeeName", @"Car" ]));
	/* A US branch is known by its number, as a branch is. */
	XCTAssertEqualObjects([[plan.columns firstObject] identifierKey], @"nr");
	XCTAssertEqualObjects([[[plan.columns lastObject] valuePath] description], @"x2.regnr");
	XCTAssertEqualObjects([[plan.columns lastObject] trail], (@[ @"employee", @"cars" ]));
	XCTAssertEqualObjects([self program:q], @"fetch USbranch where (NOT (SUBQUERY(uSbranchAchievedRankInYears, $x1, "
	                                        @"($x1.rank.nr == 1) AND ($x1.year.ad < 1998)).@count > 0)) AND "
	                                        @"(employee.employeeName != nil)\n"
	                                        @"sorted by nr; each batch after the last one's");
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
	XCTAssertEqualObjects([[self plan:q] text], @"read Employee\n"
	                                              @"where city is set and country is set and some employees as x1 has "
	                                              @"(x1.city is city and not (x1.country is country))\n"
	                                              @"list self (nr)");
	/* In the lambda, the supervisor is $it; a city, a surrogate's, by its key. */
	XCTAssertEqualObjects([[self odata:q] queryText], @"$filter=City ne null and Country ne null and "
	                                                   @"Employees/any(x1:x1/City/Id eq $it/City/Id and not "
	                                                   @"(x1/Country/Name eq $it/Country/Name))&$select=Nr");
	XCTAssertEqualObjects([self program:q], @"fetch Employee where (city != nil) AND (country != nil) AND "
	                                        @"(SUBQUERY(employees, $x1, ($x1.city == city) AND (NOT ($x1.country == "
	                                        @"country))).@count > 0)\n"
	                                        @"sorted by nr; each batch after the last one's");
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
	/* Car1 met again out of the scope it was met in: among what ownsCars
	 * reaches from the employee. */
	XCTAssertEqualObjects([[self plan:q] text], @"read Employee\n"
	                                              @"where some ownsCars and not (number of cars as x2 having x2 is among "
	                                              @"ownsCars > 1)\n"
	                                              @"list self (nr)");
	/* The cars driven that are among those owned, counted (OData 4.01): in
	 * the count's filter the car is $this, the employee still $it. */
	XCTAssertEqualObjects([[self odata:q] queryText], @"$filter=OwnsCars/any() and not (Cars/$count($filter="
	                                                   @"$this/IsOwnedByEmployees/any(y1:y1/Nr eq $it/Nr)) gt 1)&"
	                                                   @"$select=Nr");
	XCTAssertEqualObjects([self program:q], @"fetch Employee where (ownsCars.@count > 0) AND (NOT (SUBQUERY(cars, $x2, "
	                                        @"ANY $x2.isOwnedByEmployees == SELF).@count > 1))\n"
	                                        @"sorted by nr; each batch after the last one's");
}

/* The rows of the plan from the store and from the service over it: the
 * same, and returned. */
- (NSArray<NSArray *> *)rowsOfPlan:(ORMQueryPlan *)plan planner:(ORMQueryPlanner *)planner
                         inContext:(NSManagedObjectContext *)context
{
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	__block ORMQueryResult *stored = nil;
	__block NSError *error = nil;
	[context performBlockAndWait:^{
		stored = [interpreter executePlan:plan inContext:context error:&error];
	}];
	XCTAssertNotNil(stored, @"%@", error);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqual([odata.notes count], 0u, @"%@", odata.notes);
	NSArray *served = [self rowsOf:odata transport:[self countedServiceOver:context]];
	XCTAssertEqualObjects([NSSet setWithArray:served], [NSSet setWithArray:stored.rows], @"%@", [odata requestText]);
	return [stored.rows sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		return [[a description] compare:[b description]];
	}];
}

/* ConQuer-II's for-clause: an aggregate for a node above the step's.
 * Which branches' employees speak more than one language between them? */
- (void)testAnAggregateForANodeAbove
{
	NSString *q = [[self queries] addQueryNamed:@"Many tongues" from:[self typeId:@"Branch"] reason:NULL];
	NSString *root = [self root:q].identifier;
	ORMQueryNode *employee = [self from:root through:[self role:@"worksFor" at:1] in:q];
	NSString *speaks = nil;
	[self from:employee.identifier through:[self role:@"speaks" at:0] in:q step:&speaks];
	XCTAssertTrue([[self queries] setCount:@">" value:1 ofStep:speaks reason:NULL]);
	NSString *reason = nil;
	XCTAssertTrue([[self queries] setGroupNode:root ofStep:speaks reason:&reason], @"%@", reason);
	XCTAssertFalse([[self queries] setGroupNode:employee.identifier ofStep:@"no such step" reason:NULL]);
	XCTAssertEqualObjects([[self query:q] outlineText], @"✓Branch\n"
	                                                    @"  + employs Employee\n"
	                                                    @"    + speaks Language\n"
	                                                    @"      + count(Language) for Branch > 1\n");
	XCTAssertTrue([[self english:q] rangeOfString:@"the number of that Language for that Branch is greater than 1"]
	                  .location != NSNotFound, @"%@", [self english:q]);
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	XCTAssertEqual([plan.notes count], 0u, @"%@", plan.notes);
	XCTAssertTrue([[plan text] rangeOfString:@"let bag1 = read Branch where some employees as x"].location != NSNotFound,
	              @"%@", [plan text]);
	XCTAssertTrue([[plan text] rangeOfString:@"count of Language in bag1 where Branch is nr > 1"].location != NSNotFound,
	              @"%@", [plan text]);
	XCTAssertEqualObjects([[ORMQueryPlan planWithPropertyList:[plan propertyList] error:NULL] text], [plan text]);
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:[planner.coreData managedObjectModel]];
	/* 52's speak English and Latin; 7's, English only. */
	XCTAssertEqualObjects([self rowsOfPlan:plan planner:planner inContext:context], (@[ @[ @52 ] ]));
	/* From the service a branch a page: the bag read for each page's. */
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:NULL];
	ORMTestCountingTransport *counted = [self countedServiceOver:context];
	XCTAssertEqualObjects([self pagesOf:odata transport:counted size:1], (@[ @[ @52 ] ]), @"%@", counted.paths);
	NSUInteger narrowed = 0;
	for (NSString *query in counted.queries) {
		narrowed += [query rangeOfString:@" and Nr eq "].location != NSNotFound;
	}
	XCTAssertGreaterThan(narrowed, 0u, @"%@", counted.queries);
}

/* ConQuer-II's aggregate compared with an aggregate: the branches, and
 * their employees who earn more than their branch's average. */
- (void)testAnAggregateComparedWithAnother
{
	NSString *q = [[self queries] addQueryNamed:@"Well paid" from:[self typeId:@"Branch"] reason:NULL];
	NSString *root = [self root:q].identifier;
	ORMQueryNode *employee = [self from:root through:[self role:@"worksFor" at:1] in:q];
	[[self queries] setProjected:YES ofNode:employee.identifier];
	NSString *earns = nil;
	ORMQueryNode *salary = [[self from:employee.identifier through:[self role:@"earns" at:0] in:q step:&earns] firstObject];
	NSString *reason = nil;
	XCTAssertTrue([[self queries] setAggregate:ORMQueryMaximum ofNode:salary.identifier comparison:@">" value:@"0"
	                                    ofStep:earns reason:&reason], @"%@", reason);
	XCTAssertTrue([[self queries] setComparedAggregate:ORMQueryAverage group:root ofStep:earns reason:&reason], @"%@",
	              reason);
	XCTAssertEqualObjects([[self query:q] outlineText], @"✓Branch\n"
	                                                    @"  + employs ✓Employee\n"
	                                                    @"    + earns Salary\n"
	                                                    @"      + max(Salary) for Employee > avg(Salary) for Branch\n");
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	XCTAssertEqual([plan.notes count], 0u, @"%@", plan.notes);
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:[planner.coreData managedObjectModel]];
	/* 52: Ann's 600 000 over 550 000; 7: Bea's 500 000 and Fay's 600 000
	 * over 383 333. */
	XCTAssertEqualObjects([self rowsOfPlan:plan planner:planner inContext:context],
	                      (@[ @[ @52, @1 ], @[ @7, @10 ], @[ @7, @2 ] ]));
	/* Taken away, it is the value again. */
	XCTAssertTrue([[self queries] setComparedAggregate:ORMQueryAverage group:nil ofStep:earns reason:NULL]);
	XCTAssertTrue([[[self query:q] outlineText] hasSuffix:@"max(Salary) for Employee > 0\n"], @"%@",
	              [[self query:q] outlineText]);
}

/* An aggregate for a node above, of the bag of the whole query: the
 * salaries of only the branch's employees who speak Latin, as a condition
 * beside the step says. 52's Latin speaker earns 600 000, its employees
 * 1 100 000 together. */
- (void)testAnAggregateForANodeAboveKeepsTheConditionsBesideIt
{
	NSString *q = [[self queries] addQueryNamed:@"Latin payroll" from:[self typeId:@"Branch"] reason:NULL];
	NSString *root = [self root:q].identifier;
	ORMQueryNode *employee = [self from:root through:[self role:@"worksFor" at:1] in:q];
	ORMQueryNode *language = [self from:employee.identifier through:[self role:@"speaks" at:0] in:q];
	[[self queries] setCondition:@"=" value:@"Latin" ofNode:language.identifier reason:NULL];
	NSString *earns = nil;
	ORMQueryNode *salary = [[self from:employee.identifier through:[self role:@"earns" at:0] in:q step:&earns] firstObject];
	NSString *reason = nil;
	XCTAssertTrue([[self queries] setAggregate:ORMQueryTotal ofNode:salary.identifier comparison:@"<" value:@"700000"
	                                    ofStep:earns reason:&reason], @"%@", reason);
	XCTAssertTrue([[self queries] setGroupNode:root ofStep:earns reason:&reason], @"%@", reason);
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	XCTAssertEqual([plan.notes count], 0u, @"%@", plan.notes);
	XCTAssertEqual([plan.definitions count], 1u, @"%@", [plan text]);
	XCTAssertEqualObjects([[ORMQueryPlan planWithPropertyList:[plan propertyList] error:NULL] text], [plan text]);
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:[planner.coreData managedObjectModel]];
	XCTAssertEqualObjects([self rowsOfPlan:plan planner:planner inContext:context], (@[ @[ @52 ] ]), @"%@", [plan text]);
	/* The bag run for each slice's branches, not for every branch. */
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[planner.coreData managedObjectModel]];
	NSString *program = [interpreter programForPlan:plan error:NULL];
	XCTAssertTrue([program rangeOfString:@"bag1: run for each slice, where nr is among the slice's nr"].location != NSNotFound,
	              @"%@", program);
	/* From the service: the bag read for each page's branches. */
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:NULL];
	XCTAssertEqualObjects(odata.notes, @[]);
	XCTAssertEqualObjects([[odata.bags allKeys] firstObject], @"bag1");
	XCTAssertTrue([[odata requestText] rangeOfString:@"bag1, for each page, where Nr is one of the page's nr"].location
	                  != NSNotFound, @"%@", [odata requestText]);
	XCTAssertEqualObjects([self rowsOf:odata transport:[self countedServiceOver:context]], (@[ @[ @52 ] ]),
	                      @"%@", [odata requestText]);
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* Who lives in a city with a branch headed by someone born in another
 * country than they were? City absorbed, the branches joined on its parts
 * depend on each employee by a comparison no equality says: from the
 * service, the page's branches checked on the answers, not a request for
 * each employee. */
- (void)testACorrelatedJoinIsCheckedOnTheServicesAnswers
{
	NSString *q = [[self queries] addQueryNamed:@"Abroad" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	ORMQueryNode *born = [self from:root through:[self role:@"bornIn" at:0] in:q];
	[[self queries] setLabel:@"1" ofNode:born.identifier];
	ORMQueryNode *city = [self from:root through:[self role:@"livesIn" at:0] in:q];
	ORMQueryNode *branch = [self from:city.identifier through:[self role:@"locatedIn" at:1] in:q];
	ORMQueryNode *head = [self from:branch.identifier through:[self role:@"heads" at:1] in:q];
	ORMQueryNode *headBorn = [self from:head.identifier through:[self role:@"bornIn" at:0] in:q];
	[[self queries] setLabel:@"2" ofNode:headBorn.identifier];
	NSString *reason = nil;
	XCTAssertTrue([[self queries] setCondition:@"<>" toNode:born.identifier ofNode:headBorn.identifier reason:&reason],
	              @"%@", reason);
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	XCTAssertEqual([plan.notes count], 0u, @"%@", plan.notes);
	XCTAssertEqualObjects([[plan.definitions firstObject] parameters], @[ @"o1" ], @"%@", [plan text]);
	[self addCompanyPopulation];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:_editor.model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:store.managedObjectModel];
	XCTAssertEqualObjects([self numbersOf:plan interpreter:interpreter inContext:context], (@[ @10 ]));
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqual([odata.notes count], 0u, @"%@", odata.notes);
	XCTAssertEqual([odata.pageJoins count], 1u);
	ORMTestCountingTransport *counted = [self countedServiceOver:context];
	NSArray *rows = [self rowsOf:odata transport:counted];
	XCTAssertEqualObjects(rows, (@[ @[ @10 ] ]), @"%@", counted.paths);
	/* Two requests a page, never one an employee. */
	XCTAssertLessThan(counted.requests, 12u, @"%@", counted.paths);
}

/* No tuple twice: where the rows list the object read, an object's rows
 * are compared with its own only, and nothing is kept between objects;
 * else every row given is. */
- (void)testRowsOfObjectsApartAreNotKept
{
	NSDictionary *rows = @{ @"a": @[ @[ @"a", @1 ], @[ @"a", @1 ], @[ @"a", @2 ] ], @"b": @[ @[ @"b", @1 ] ] };
	for (NSNumber *apart in @[ @YES, @NO ]) {
		ORMTestBatches *batches = [[ORMTestBatches alloc] init];
		batches.batches = [NSMutableArray arrayWithObjects:@[ @"a" ], @[ @"b" ], nil];
		ORMTestRows *evaluator = [[ORMTestRows alloc] init];
		evaluator.rows = rows;
		ORMPageReader *reader = [[ORMPageReader alloc] initWithInput:batches evaluator:evaluator columnTitles:@[ @"X", @"N" ]];
		reader.objectsApart = [apart boolValue];
		__block ORMQueryResult *page = nil;
		[reader nextPage:10 completion:^(ORMQueryResult *result, NSError *error) {
			XCTAssertNotNil(result, @"%@", error);
			page = result;
		}];
		XCTAssertEqualObjects(page.objects, (@[ @"a", @"b" ]));
		XCTAssertEqualObjects(page.rows, (@[ @[ @"a", @1 ], @[ @"a", @2 ], @[ @"b", @1 ] ]));
		XCTAssertEqual(reader.rowsKept, [apart boolValue] ? 0u : 3u);
	}
}

/* An employee like the first, numbered to come before everyone, saved. */
- (void)hire:(int)nr inContext:(NSManagedObjectContext *)context
{
	[context performBlockAndWait:^{
		NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:@"Employee"];
		fetch.predicate = [NSPredicate predicateWithFormat:@"nr == 1"];
		NSManagedObject *first = [[context executeFetchRequest:fetch error:NULL] firstObject];
		NSManagedObject *hired = [NSEntityDescription insertNewObjectForEntityForName:@"Employee" inManagedObjectContext:context];
		for (NSString *key in @[ @"city", @"country", @"salary", @"branch" ]) {
			[hired setValue:[first valueForKey:key] forKey:key];
		}
		[hired setValue:@(nr) forKey:@"nr"];
		[hired setValue:[NSString stringWithFormat:@"E%d", nr] forKey:@"employeeName"];
		NSError *error = nil;
		XCTAssertTrue([context save:&error], @"%@", error);
	}];
}

/* Each page starts after the last one's key, not after a number of
 * objects: someone hired between pages, numbered before them, neither
 * repeats nor skips anyone. */
- (void)testPagesResumeAfterTheLastKey
{
	NSString *q = [[self queries] addQueryNamed:@"Everyone" from:[self typeId:@"Employee"] reason:NULL];
	[self from:[self root:q].identifier through:[self role:@"livesIn" at:0] in:q];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	NSManagedObjectContext *context = [self companyIn:directory model:model];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
	NSString *program = [interpreter programForPlan:plan error:NULL];
	XCTAssertTrue([program hasSuffix:@"sorted by nr; each batch after the last one's"], @"%@", program);
	__block NSMutableArray *pages = [NSMutableArray array];
	ORMQueryCursor *cursor = [interpreter cursorForPlan:plan inContext:context error:NULL];
	[context performBlockAndWait:^{
		[pages addObject:[[cursor nextPage:2 error:NULL].objects valueForKey:@"nr"]];
	}];
	[self hire:0 inContext:context];
	[context performBlockAndWait:^{
		while (![cursor atEnd]) {
			[pages addObject:[[cursor nextPage:2 error:NULL].objects valueForKey:@"nr"]];
		}
	}];
	XCTAssertEqualObjects([pages valueForKeyPath:@"@unionOfArrays.self"], (@[ @1, @2, @3, @4, @5, @10, @21 ]), @"%@", pages);
	/* From the service the same: 0 and 1 first, then -1 hired. */
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:NULL];
	XCTAssertTrue([[odata requestText] rangeOfString:@"in pages ordered by nr, each after the last one's"].location
	                  != NSNotFound, @"%@", [odata requestText]);
	ORMTestCountingTransport *counted = [self countedServiceOver:context];
	ORMQueryODataCursor *served = [odata cursorWithTransport:counted serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
	NSMutableArray *servedPages = [NSMutableArray array];
	for (NSUInteger guard = 0; guard < 10 && ![served atEnd]; guard++) {
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		__block ORMQueryResult *page = nil;
		[served nextPage:2 completion:^(ORMQueryResult *result, NSError *failed) {
			XCTAssertNotNil(result, @"%@", failed);
			page = result;
			dispatch_semaphore_signal(done);
		}];
		XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC))), 0);
		[servedPages addObject:[page.objects valueForKey:@"Nr"] ?: @[]];
		if (guard == 0) {
			[self hire:-1 inContext:context];
		}
	}
	XCTAssertEqualObjects([servedPages valueForKeyPath:@"@unionOfArrays.self"], (@[ @0, @1, @2, @3, @4, @5, @10, @21 ]),
	                      @"%@\n%@", servedPages, counted.queries);
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* The same under a not: who lives in a city with no branch headed by
 * someone born in another country than they were? No page join says it:
 * for each page, the branches in its employees' cities are read, and the
 * not checked on the answers. */
- (void)testACorrelatedJoinUnderNotIsCheckedOnTheServicesAnswers
{
	NSString *q = [[self queries] addQueryNamed:@"Not abroad" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	ORMQueryNode *born = [self from:root through:[self role:@"bornIn" at:0] in:q];
	[[self queries] setLabel:@"1" ofNode:born.identifier];
	ORMQueryNode *city = [self from:root through:[self role:@"livesIn" at:0] in:q];
	NSString *located = nil;
	ORMQueryNode *branch = [[self from:city.identifier through:[self role:@"locatedIn" at:1] in:q step:&located] firstObject];
	[[self queries] setOperator:ORMQueryNot ofStep:located];
	ORMQueryNode *head = [self from:branch.identifier through:[self role:@"heads" at:1] in:q];
	ORMQueryNode *headBorn = [self from:head.identifier through:[self role:@"bornIn" at:0] in:q];
	[[self queries] setLabel:@"2" ofNode:headBorn.identifier];
	NSString *reason = nil;
	XCTAssertTrue([[self queries] setCondition:@"<>" toNode:born.identifier ofNode:headBorn.identifier reason:&reason],
	              @"%@", reason);
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	XCTAssertEqual([plan.notes count], 0u, @"%@", plan.notes);
	[self addCompanyPopulation];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:_editor.model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:store.managedObjectModel];
	NSArray *numbers = [self numbersOf:plan interpreter:interpreter inContext:context];
	XCTAssertGreaterThan([numbers count], 0u);
	XCTAssertFalse([numbers containsObject:@10], @"%@", numbers);
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:&error];
	XCTAssertNotNil(odata, @"%@", error);
	XCTAssertEqual([odata.notes count], 0u, @"%@", odata.notes);
	XCTAssertEqual([odata.pageJoins count], 0u);
	XCTAssertEqual([odata.wholeJoins count], 1u, @"%@", [odata requestText]);
	XCTAssertTrue([[odata requestText] rangeOfString:@"join1, for each page, where CityCityname, CityStateStatecode, "
	                                                 @"CityStateCountry/Name are one of the page's"].location != NSNotFound,
	              @"%@", [odata requestText]);
	/* Two employees a page: the branches read for each page's cities. */
	ORMTestCountingTransport *paged = [self countedServiceOver:context];
	NSArray *pages = [self pagesOf:odata transport:paged size:2];
	XCTAssertEqualObjects([[pages valueForKeyPath:@"@unionOfArrays.self"] sortedArrayUsingSelector:@selector(compare:)],
	                      numbers, @"%@", paged.queries);
	NSUInteger narrowed = 0;
	for (NSString *query in paged.queries) {
		narrowed += [query rangeOfString:@"CityCityname eq "].location != NSNotFound;
	}
	XCTAssertGreaterThan(narrowed, 1u, @"%@", paged.queries);
	NSMutableArray *served = [NSMutableArray array];
	for (NSArray *row in [self rowsOf:odata transport:[self countedServiceOver:context]]) {
		[served addObject:[row firstObject]];
	}
	XCTAssertEqualObjects([served sortedArrayUsingSelector:@selector(compare:)], numbers,
	                      @"%@\n%@", [plan text], [odata requestText]);
}

/* Q4 with City absorbed into Employee: no city to be the same one, but its
 * parts, compared one by one. */
- (void)testQ4ComparesAnAbsorbedCityPartByPart
{
	NSString *q = [self q4];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	XCTAssertEqual([plan.notes count], 0u, @"%@", plan.notes);
	XCTAssertEqualObjects([plan text], @"read Employee\n"
	                                   @"where cityCityname is set and country is set and some employees as x1 has "
	                                   @"(x1.cityCityname = cityCityname and x1.cityStateCountry is cityStateCountry and "
	                                   @"x1.cityStateStatecode = cityStateStatecode and not (x1.country is country))\n"
	                                   @"list self (nr)");
	/* The paper's company, its cities absorbed: Bea's employee Fay lives in
	 * Sydney too, born elsewhere; Ann's Gus in Perth, not Brisbane. */
	[self addCompanyPopulation];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:_editor.model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:store.managedObjectModel];
	XCTAssertEqualObjects([self numbersOf:plan interpreter:interpreter inContext:context], (@[ @2 ]));
}

/* Who owns car B and drives it? Car1 is met again out of the scope it was
 * met in, and its condition there is of the same car: asked again where
 * it is met, so owning A and driving it is not enough. */
- (void)testCorrelationKeepsTheEarlierConditions
{
	NSString *q = [[self queries] addQueryNamed:@"Drives B" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	ORMQueryNode *owned = [self from:root through:[self role:@"owns" at:0] in:q];
	[[self queries] setLabel:@"1" ofNode:owned.identifier];
	XCTAssertTrue([[self queries] setCondition:@"=" value:@"B" ofNode:owned.identifier reason:NULL]);
	ORMQueryNode *driven = [self from:root through:[self role:@"drives" at:0] in:q];
	[[self queries] setLabel:@"1" ofNode:driven.identifier];
	ORMQueryPlan *plan = [self plan:q];
	XCTAssertEqual([plan.notes count], 0u, @"%@", plan.notes);
	XCTAssertEqualObjects([plan text], @"read Employee\n"
	                                   @"where some ownsCars as x1 has x1.regnr = 'B' and some cars as x2 has "
	                                   @"(x2 is among ownsCars and x2.regnr = 'B')\n"
	                                   @"list self (nr)");
	XCTAssertEqualObjects([[self odata:q] queryText], @"$filter=OwnsCars/any(x1:x1/Regnr eq 'B') and Cars/any(x2:"
	                                                   @"x2/IsOwnedByEmployees/any(y1:y1/Nr eq $it/Nr) and x2/Regnr eq 'B')"
	                                                   @"&$select=Nr");
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:model];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
	XCTAssertEqualObjects([self numbersOf:[planner planForQuery:[self query:q]] interpreter:interpreter inContext:context],
	                      (@[ @3 ]));
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
	XCTAssertEqualObjects([[self plan:q] text], @"read Branch\n"
	                                              @"where sum of x1.salary.usd over employees as x1 > 1000000\n"
	                                              @"list self (nr)\n"
	                                              @"order by nr descending");
	ORMQueryOData *odata = [self odata:q];
	XCTAssertEqualObjects([odata queryText], @"$filter=Employees/aggregate(Salary/Usd with sum) gt 1000000&"
	                                         @"$orderby=Nr desc&$select=Nr");
	XCTAssertEqualObjects([self program:q], @"fetch Branch where employees.@sum.salary.usd > 1000000\n"
	                                        @"sorted by nr descending; each batch after the last one's");
}

/* Who speaks more than one language; who is above 100 and lives in a city
 * of Texas or speaks Latin. */
- (void)testCountsAndAlternatives
{
	NSString *polyglots = [[self queries] addQueryNamed:@"Polyglots" from:[self typeId:@"Employee"] reason:NULL];
	NSString *speaks = nil;
	[self from:[self root:polyglots].identifier through:[self role:@"speaks" at:0] in:polyglots step:&speaks];
	XCTAssertTrue([[self queries] setCount:@">" value:1 ofStep:speaks reason:NULL]);
	XCTAssertEqualObjects([self program:polyglots], @"fetch Employee where languages.@count > 1\n"
	                                                @"sorted by nr; each batch after the last one's");
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
	XCTAssertEqualObjects([self program:q], @"fetch Employee where (nr > 100) AND ((country.name == \"USA\") OR "
	                                        @"(SUBQUERY(languages, $x1, $x1.name == \"Latin\").@count > 0))\n"
	                                        @"sorted by nr; each batch after the last one's");
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
	ORMQueryPlan *plan = [[[ORMQueryPlanner alloc] initWithCoreData:remapped] planForQuery:[self query:q]];
	NSError *error = nil;
	XCTAssertNil([ORMQueryOData requestForPlan:plan coreData:remapped error:&error]);
	XCTAssertNotNil(error);
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
	ORMQueryPlan *plan = [[[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:nil] planForQuery:query];
	XCTAssertTrue([[plan.notes firstObject] rangeOfString:@"no longer in the model"].location != NSNotFound, @"%@", plan.notes);
}

/* The paper's queries, and a count, by name. */
- (NSDictionary<NSString *, NSString *> *)paperQueries
{
	NSString *polyglots = [[self queries] addQueryNamed:@"Polyglots" from:[self typeId:@"Employee"] reason:NULL];
	NSString *speaks = nil;
	[self from:[self root:polyglots].identifier through:[self role:@"speaks" at:0] in:polyglots step:&speaks];
	[[self queries] setCount:@">" value:1 ofStep:speaks reason:NULL];
	return @{ @"Q1": [self q1], @"Q2": [self q2], @"Q3": [self q3], @"Q4": [self q4], @"Q5": [self q5],
	          @"Payroll": [self payroll], @"Polyglots": polyglots };
}

/* The rows each of them asks for, of the store -companyIn: fills. */
- (NSDictionary<NSString *, NSArray *> *)paperAnswers
{
	return @{ @"Q1": @[ @1, @3 ], @"Q2": @[ @1, @3, @4 ], @"Q3": @[ @102 ], @"Q4": @[ @2 ], @"Q5": @[ @1, @4 ],
	          @"Payroll": @[ @52, @7 ], @"Polyglots": @[ @1 ] };
}

/* A SQLite store of the mapped model, as Core Data describes it, filled
 * with the paper's company: what each backend is asked about. */
- (NSManagedObjectContext *)companyIn:(NSString *)directory model:(NSManagedObjectModel *)model
{
	NSError *error = nil;
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
	return context;
}

/* The plans, run against the store by the interpreter: the rows the
 * paper's queries ask for, in fetches and on the objects fetched. */
- (void)testTheStoreAnswersTheQueries
{
	NSDictionary *queries = [self paperQueries];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:model];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
	NSDictionary *answers = [self paperAnswers];
	for (NSString *name in answers) {
		ORMQueryPlan *plan = [planner planForQuery:[self query:[queries objectForKey:name]]];
		__block ORMQueryResult *result = nil;
		__block NSError *error = nil;
		[context performBlockAndWait:^{
			result = [interpreter executePlan:plan inContext:context error:&error];
		}];
		XCTAssertNotNil(result, @"%@: %@", name, error);
		NSArray *numbers = [result.objects valueForKey:@"nr"];
		/* The order the query asks for, where it does. */
		if ([plan.sorts count] == 0) {
			numbers = [numbers sortedArrayUsingSelector:@selector(compare:)];
		}
		XCTAssertEqualObjects(numbers, [answers objectForKey:name], @"%@\n%@", name,
		                      [interpreter programForPlan:plan error:NULL]);
	}
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* The paper's company as the model's sample population: what -companyIn:
 * makes in Core Data, made as NORMA would keep it. */
- (void)addCompanyPopulation
{
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	/* An instance by its reference mode's value. */
	NSString *(^one)(NSString *, NSString *) = ^NSString *(NSString *typeName, NSString *text) {
		ORMObjectType *type = [self->_editor.model objectTypeNamed:typeName];
		ORMRole *role = [[type.preferredIdentifier allRoles] firstObject];
		return [population instanceOf:type.identifier
		                 identifiedBy:@{ role.identifier: [population value:text of:role.player.identifier] }];
	};
	void (^fact)(NSString *, NSArray *) = ^(NSString *name, NSArray *players) {
		NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
		for (NSUInteger i = 0; i < [players count]; i++) {
			[byRole setObject:[players objectAtIndex:i] forKey:[self role:name at:i]];
		}
		ORMRole *role = [self->_editor.model elementWithId:[self role:name at:0]];
		[population factOf:role.factType.identifier players:byRole];
	};
	NSString *australia = one(@"Country", @"Australia"), *usa = one(@"Country", @"USA"), *uk = one(@"Country", @"UK");
	NSString *(^state)(NSString *, NSString *) = ^NSString *(NSString *country, NSString *code) {
		return [population instanceOf:[self typeId:@"State"]
		                 identifiedBy:@{ [self role:@"stateCountry" at:1]: country,
		                                 [self role:@"stateCode" at:1]: [population value:code of:[self typeId:@"Statecode"]] }];
	};
	NSString *(^city)(NSString *, NSString *) = ^NSString *(NSString *name, NSString *inState) {
		return [population instanceOf:[self typeId:@"City"]
		                 identifiedBy:@{ [self role:@"cityName" at:1]: [population value:name of:[self typeId:@"Cityname"]],
		                                 [self role:@"cityState" at:1]: inState }];
	};
	NSString *brisbane = city(@"Brisbane", state(australia, @"QLD")), *sydney = city(@"Sydney", state(australia, @"NSW"));
	NSString *perth = city(@"Perth", state(australia, @"WA")), *seattle = city(@"Seattle", state(usa, @"WA"));
	NSMutableDictionary *employees = [NSMutableDictionary dictionary];
	for (NSArray *row in @[ @[ @1, brisbane, australia, @"600000" ], @[ @2, sydney, australia, @"500000" ],
	                        @[ @3, brisbane, australia, @"500000" ], @[ @4, seattle, usa, @"50000" ],
	                        @[ @5, seattle, usa, @"50000" ], @[ @10, sydney, uk, @"600000" ],
	                        @[ @21, perth, uk, @"50000" ] ]) {
		NSString *e = one(@"Employee", [[row firstObject] stringValue]);
		[employees setObject:e forKey:[row firstObject]];
		fact(@"hasName", @[ e, [population value:[NSString stringWithFormat:@"E%@", [row firstObject]]
		                                   of:[self typeId:@"EmployeeName"]] ]);
		fact(@"livesIn", @[ e, [row objectAtIndex:1] ]);
		fact(@"bornIn", @[ e, [row objectAtIndex:2] ]);
		fact(@"earns", @[ e, one(@"Salary", [row lastObject]) ]);
	}
	NSString *(^employee)(int) = ^NSString *(int nr) {
		return [employees objectForKey:@(nr)];
	};
	fact(@"reportsTo", @[ employee(10), employee(2) ]);
	fact(@"reportsTo", @[ employee(21), employee(1) ]);
	NSString *b52 = one(@"Branch", @"52"), *b7 = one(@"Branch", @"7");
	NSString *us1 = [population instanceOf:[self typeId:@"USbranch"] supertypeInstance:one(@"Branch", @"101")];
	NSString *us2 = [population instanceOf:[self typeId:@"USbranch"] supertypeInstance:one(@"Branch", @"102")];
	for (NSArray *row in @[ @[ b52, brisbane, @1 ], @[ b7, sydney, @2 ], @[ us1, seattle, @4 ], @[ us2, seattle, @5 ] ]) {
		fact(@"locatedIn", @[ [row firstObject], [row objectAtIndex:1] ]);
		fact(@"heads", @[ employee([[row lastObject] intValue]), [row firstObject] ]);
	}
	for (NSArray *row in @[ @[ @1, b52 ], @[ @3, b52 ], @[ @2, b7 ], @[ @10, b7 ], @[ @21, b7 ], @[ @4, us1 ], @[ @5, us2 ] ]) {
		fact(@"worksFor", @[ employee([[row firstObject] intValue]), [row lastObject] ]);
	}
	NSString *ute = one(@"CarModel", @"Ute");
	NSString *a = one(@"Car", @"A"), *b = one(@"Car", @"B"), *c = one(@"Car", @"C");
	for (NSString *car in @[ a, b, c ]) {
		fact(@"carModel", @[ car, ute ]);
	}
	for (NSArray *row in @[ @[ @1, c ], @[ @3, a ], @[ @3, b ], @[ @4, a ] ]) {
		fact(@"drives", @[ employee([[row firstObject] intValue]), [row lastObject] ]);
	}
	for (NSArray *row in @[ @[ @1, b ], @[ @3, a ], @[ @3, b ], @[ @4, a ] ]) {
		fact(@"owns", @[ employee([[row firstObject] intValue]), [row lastObject] ]);
	}
	NSString *english = one(@"Language", @"English"), *latin = one(@"Language", @"Latin");
	fact(@"speaks", @[ employee(1), english ]);
	fact(@"speaks", @[ employee(1), latin ]);
	fact(@"speaks", @[ employee(2), english ]);
	for (NSArray *row in @[ @[ us1, @"1", @"1995" ], @[ us2, @"1", @"2001" ], @[ us2, @"2", @"1996" ] ]) {
		fact(@"achieved", @[ [row firstObject], one(@"Rank", [row objectAtIndex:1]), one(@"Year", [row lastObject]) ]);
	}
	NSString *reason = nil;
	XCTAssertTrue([_editor.populationEditor addPopulation:population reason:&reason], @"%@", reason);
}

/* The company as a sample population, put in a store of the mapping by
 * ORMPopulationStore: the same rows as the store made by hand. */
- (void)testASamplePopulationAnswersTheQueries
{
	NSDictionary *queries = [self paperQueries];
	[self addCompanyPopulation];
	ORMPopulationChecker *checker = [[ORMPopulationChecker alloc] initWithModel:_editor.model];
	XCTAssertEqualObjects([[checker violations] valueForKey:@"text"], @[]);
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMPopulationStore *store = [[ORMPopulationStore alloc] initWithModel:_editor.model coreData:planner.coreData];
	NSError *error = nil;
	NSManagedObjectContext *context = [store newContextWithError:&error];
	XCTAssertNotNil(context, @"%@", error);
	XCTAssertEqualObjects(store.notes, @[]);
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:store.managedObjectModel];
	NSDictionary *answers = [self paperAnswers];
	for (NSString *name in answers) {
		ORMQueryPlan *plan = [planner planForQuery:[self query:[queries objectForKey:name]]];
		__block ORMQueryResult *result = nil;
		__block NSError *runError = nil;
		[context performBlockAndWait:^{
			result = [interpreter executePlan:plan inContext:context error:&runError];
		}];
		XCTAssertNotNil(result, @"%@: %@", name, runError);
		NSArray *numbers = [result.objects valueForKey:@"nr"];
		if ([plan.sorts count] == 0) {
			numbers = [numbers sortedArrayUsingSelector:@selector(compare:)];
		}
		XCTAssertEqualObjects(numbers, [answers objectForKey:name], @"%@\n%@", name,
		                      [interpreter programForPlan:plan error:NULL]);
	}
}

/* A total of the employees who speak Latin: the store aggregates no
 * subquery, so the interpreter asks the objects it fetches. Unfiltered, both
 * branches would pass; filtered, only 52's Latin speaker earns enough. */
- (void)testAnAggregateOfSomeMembersIsTakenOnTheObjects
{
	NSString *q = [self payroll];
	ORMQueryNode *employee = [[[[self query:q].root.steps firstObject] nodes] firstObject];
	ORMQueryNode *language = [self from:employee.identifier through:[self role:@"speaks" at:0] in:q];
	[[self queries] setCondition:@"=" value:@"Latin" ofNode:language.identifier reason:NULL];
	ORMQueryStep *employs = [[self query:q].root.steps firstObject];
	ORMQueryNode *salary = nil;
	for (ORMQueryStep *step in [[employs.nodes firstObject] steps]) {
		if ([[[step.nodes firstObject] objectType].name isEqualToString:@"Salary"]) {
			salary = [step.nodes firstObject];
		}
	}
	XCTAssertTrue([[self queries] setAggregate:ORMQueryTotal ofNode:salary.identifier comparison:@">" value:@"550000"
	                                    ofStep:employs.identifier reason:NULL]);
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	XCTAssertTrue([[plan text] rangeOfString:@"having"].location != NSNotFound, @"%@", [plan text]);
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
	NSString *program = [interpreter programForPlan:plan error:NULL];
	XCTAssertTrue([program rangeOfString:@"keep those where SUBQUERY(employees"].location != NSNotFound, @"%@", program);
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:model];
	__block ORMQueryResult *result = nil;
	__block NSError *error = nil;
	[context performBlockAndWait:^{
		result = [interpreter executePlan:plan inContext:context error:&error];
	}];
	XCTAssertEqualObjects([result.objects valueForKey:@"nr"], (@[ @52 ]), @"%@", error);
	/* From the service, which aggregates no filtered collection: checked on
	 * its answers, the members' salaries expanded. */
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:NULL];
	XCTAssertEqualObjects(odata.notes, @[]);
	XCTAssertEqualObjects([self rowsOf:odata transport:[self countedServiceOver:context]], (@[ @[ @52 ] ]),
	                      @"%@", [odata requestText]);
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* A store of the default mapping, City absorbed into employees and
 * branches: Ann and Cal live in Brisbane, where branch 52 is and Ann heads
 * it; Bea lives there too, but heads branch 7, in Sydney. */
- (NSManagedObjectContext *)absorbedCompanyIn:(NSString *)directory model:(NSManagedObjectModel *)model
{
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	NSError *error = nil;
	XCTAssertNotNil([coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil
	                                                    URL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"A.sqlite"]]
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
		NSManagedObject *pay = make(@"Salary", @{ @"usd": @50000 });
		NSDictionary *brisbane = @{ @"cityCityname": @"Brisbane", @"cityStateStatecode": @"QLD", @"cityStateCountry": australia };
		NSDictionary *sydney = @{ @"cityCityname": @"Sydney", @"cityStateStatecode": @"NSW", @"cityStateCountry": australia };
		NSManagedObject *(^employee)(int, NSDictionary *) = ^NSManagedObject *(int nr, NSDictionary *city) {
			NSMutableDictionary *values = [NSMutableDictionary dictionaryWithDictionary:city];
			[values addEntriesFromDictionary:@{ @"nr": @(nr), @"employeeName": @"E", @"country": australia, @"salary": pay }];
			return make(@"Employee", values);
		};
		NSManagedObject *e1 = employee(1, brisbane), *e2 = employee(2, brisbane), *e3 = employee(3, brisbane);
		NSManagedObject *e4 = employee(4, sydney);
		NSMutableDictionary *b52 = [NSMutableDictionary dictionaryWithDictionary:brisbane];
		[b52 addEntriesFromDictionary:@{ @"nr": @52, @"employee": e1 }];
		NSMutableDictionary *b7 = [NSMutableDictionary dictionaryWithDictionary:sydney];
		[b7 addEntriesFromDictionary:@{ @"nr": @7, @"employee": e2 }];
		NSManagedObject *branch52 = make(@"Branch", b52), *branch7 = make(@"Branch", b7);
		for (NSArray *works in @[ @[ e1, branch52 ], @[ e3, branch52 ], @[ e2, branch7 ], @[ e4, branch7 ] ]) {
			[[works firstObject] setValue:[works lastObject] forKey:@"branch"];
		}
		NSError *saveError = nil;
		XCTAssertTrue([context save:&saveError], @"%@", [saveError userInfo]);
	}];
	return context;
}

/* ODataKit's service over the store, its requests counted. */
- (ORMTestCountingTransport *)countedServiceOver:(NSManagedObjectContext *)context
{
	ORMTestCountingTransport *counted = [[ORMTestCountingTransport alloc] init];
	counted.paths = [NSMutableArray array];
	counted.queries = [NSMutableArray array];
	counted.service = [[ODataService alloc] initWithPersistentStoreCoordinator:context.persistentStoreCoordinator
	                                                               serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
	return counted;
}

/* The numbers of what a request reads, page by page, through the transport. */
- (NSArray *)pagesOf:(ORMQueryOData *)odata transport:(id<ODataTransport>)transport size:(NSUInteger)size
{
	ORMQueryODataCursor *cursor = [odata cursorWithTransport:transport serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
	NSMutableArray *pages = [NSMutableArray array];
	for (NSUInteger guard = 0; guard < 10 && ![cursor atEnd]; guard++) {
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		__block ORMQueryResult *page = nil;
		__block NSError *error = nil;
		[cursor nextPage:size completion:^(ORMQueryResult *result, NSError *failed) {
			page = result;
			error = failed;
			dispatch_semaphore_signal(done);
		}];
		XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC))), 0);
		XCTAssertNotNil(page, @"%@", error);
		if ([page.objects count] == 0) {
			break;
		}
		[pages addObject:[[page.objects valueForKey:@"Nr"] sortedArrayUsingSelector:@selector(compare:)]];
	}
	return pages;
}

- (NSArray *)numbersOf:(ORMQueryPlan *)plan interpreter:(ORMQueryInterpreter *)interpreter
             inContext:(NSManagedObjectContext *)context
{
	__block ORMQueryResult *result = nil;
	__block NSError *error = nil;
	[context performBlockAndWait:^{
		result = [interpreter executePlan:plan inContext:context error:&error];
	}];
	XCTAssertNotNil(result, @"%@", error);
	return [[result.objects valueForKey:@"nr"] sortedArrayUsingSelector:@selector(compare:)];
}

/* Q1 with City absorbed: branch 52 fetched first, and the employees whose
 * city parts are its; with too many branches to fetch, each employee
 * probed instead. */
- (void)testAJoinIsAFetchMadeFirst
{
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:[self q1]]];
	XCTAssertEqualObjects([plan text], @"let join1 = read Branch where nr = 52\n"
	                                   @"read Employee\n"
	                                   @"where cityCityname = cityCityname, cityStateStatecode = cityStateStatecode, "
	                                   @"cityStateCountry = cityStateCountry in join1\n"
	                                   @"list self (nr)");
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
	NSString *program = [interpreter programForPlan:plan error:NULL];
	XCTAssertTrue([program hasPrefix:@"join1: fetch Branch where nr == 52\n"], @"%@", program);
	XCTAssertTrue([program rangeOfString:@"for one of join1"].location != NSNotFound, @"%@", program);

	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self absorbedCompanyIn:directory model:model];
	XCTAssertEqualObjects([self numbersOf:plan interpreter:interpreter inContext:context], (@[ @1, @2, @3 ]));
	interpreter.joinPrefetchLimit = 0;
	XCTAssertEqualObjects([self numbersOf:plan interpreter:interpreter inContext:context], (@[ @1, @2, @3 ]));
	/* From the service: the branches' parts asked for page by page. */
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:NULL];
	XCTAssertEqual([odata.pageJoins count], 1u);
	ORMTestCountingTransport *counted = [self countedServiceOver:context];
	NSArray *pages = [self pagesOf:odata transport:counted size:2];
	XCTAssertEqualObjects([pages valueForKeyPath:@"@unionOfArrays.self"], (@[ @1, @2, @3 ]), @"%@", pages);
	/* A page of two is two requests: the employees, and the branches'
	 * parts among theirs. */
	XCTAssertLessThanOrEqual(counted.requests, 2u * [pages count] + 2u, @"%@", counted.paths);
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* Who heads a branch in the city they live in? Employee1 is met again in
 * the join, so the branches depend on each employee: o1 in the joined
 * plan. The branches in a batch's cities are read once for the batch, and
 * which one each employee heads is asked of them. */
- (void)testACorrelatedJoinIsReadForEachBatch
{
	NSString *q = [[self queries] addQueryNamed:@"Heads at home" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:q].identifier;
	[[self queries] setLabel:@"1" ofNode:root];
	ORMQueryNode *city = [self from:root through:[self role:@"livesIn" at:0] in:q];
	ORMQueryNode *branch = [self from:city.identifier through:[self role:@"locatedIn" at:1] in:q];
	ORMQueryNode *head = [self from:branch.identifier through:[self role:@"heads" at:1] in:q];
	[[self queries] setLabel:@"1" ofNode:head.identifier];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:nil];
	ORMQueryPlan *plan = [planner planForQuery:[self query:q]];
	XCTAssertEqual([plan.notes count], 0u, @"%@", plan.notes);
	XCTAssertEqualObjects([plan text], @"let join1(o1) = read Branch where employee is o1\n"
	                                   @"read Employee\n"
	                                   @"where cityCityname = cityCityname, cityStateStatecode = cityStateStatecode, "
	                                   @"cityStateCountry = cityStateCountry in join1 (o1 is this)\n"
	                                   @"list self (nr)");
	XCTAssertEqualObjects([[ORMQueryPlan planWithPropertyList:[plan propertyList] error:NULL] text], [plan text]);
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
	NSString *program = [interpreter programForPlan:plan error:NULL];
	XCTAssertTrue([program hasPrefix:@"join1, for each (o1 is this): fetch Branch where employee == o1"], @"%@", program);
	XCTAssertTrue([program rangeOfString:@"keep those where"].location != NSNotFound, @"%@", program);
	XCTAssertTrue([program rangeOfString:@"join1: read for each batch, where its parts are the batch's"].location
	                  != NSNotFound, @"%@", program);
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self absorbedCompanyIn:directory model:model];
	XCTAssertEqualObjects([self numbersOf:plan interpreter:interpreter inContext:context], (@[ @1 ]));
	/* From the service: a request for a page of employees, and one for the
	 * branches among their parts, the head one of them; never one each. */
	ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:NULL];
	XCTAssertEqual([odata.notes count], 0u, @"%@", odata.notes);
	XCTAssertEqual([odata.joins count], 0u);
	XCTAssertEqual([odata.pageJoins count], 1u);
	NSMutableArray *headPairs = [NSMutableArray array];
	for (NSArray *pair in [odata.pageJoins firstObject].pairs) {
		[headPairs addObject:[pair lastObject]];
	}
	XCTAssertTrue([headPairs containsObject:(@[ @"Employee", @"Nr" ])], @"%@", headPairs);
	ORMTestCountingTransport *counted = [self countedServiceOver:context];
	NSArray *pages = [self pagesOf:odata transport:counted size:10];
	XCTAssertEqualObjects(pages, (@[ @[ @1 ] ]));
	XCTAssertEqual(counted.requests, 2u, @"%@", counted.paths);
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* What the interpreter returns is a result set: a tuple per way the
 * conditions are met, the members a step binds and only those, each value
 * a maybe reaches or none, and no tuple twice. */
- (void)testRowsAreAResultSet
{
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:model];
	NSArray *(^rows)(NSString *) = ^NSArray *(NSString *queryId) {
		ORMQueryPlan *plan = [planner planForQuery:[self query:queryId]];
		__block ORMQueryResult *result = nil;
		__block NSError *error = nil;
		[context performBlockAndWait:^{
			result = [interpreter executePlan:plan inContext:context error:&error];
		}];
		XCTAssertNotNil(result, @"%@", error);
		return [result.rows sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
			return [[a description] compare:[b description]];
		}];
	};
	NSNull *none = [NSNull null];

	/* Each employee, their branch, and maybe each car they drive. */
	NSString *drivers = [[self queries] addQueryNamed:@"Drivers" from:[self typeId:@"Employee"] reason:NULL];
	NSString *root = [self root:drivers].identifier;
	ORMQueryNode *branch = [self from:root through:[self role:@"worksFor" at:0] in:drivers];
	[[self queries] setProjected:YES ofNode:branch.identifier];
	NSString *maybe = nil;
	ORMQueryNode *car = [[self from:root through:[self role:@"drives" at:0] in:drivers step:&maybe] firstObject];
	[[self queries] setOperator:ORMQueryMaybe ofStep:maybe];
	[[self queries] setProjected:YES ofNode:car.identifier];
	NSArray *expected = @[ @[ @1, @52, @"C" ], @[ @10, @7, none ], @[ @2, @7, none ], @[ @21, @7, none ],
	                       @[ @3, @52, @"A" ], @[ @3, @52, @"B" ], @[ @4, @101, @"A" ], @[ @5, @102, none ] ];
	XCTAssertEqualObjects(rows(drivers), [expected sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
		return [[a description] compare:[b description]];
	}]);

	/* Who speaks Latin, and the language: Latin, not every language they
	 * speak. */
	NSString *latin = [[self queries] addQueryNamed:@"Latinists" from:[self typeId:@"Employee"] reason:NULL];
	ORMQueryNode *language = [self from:[self root:latin].identifier through:[self role:@"speaks" at:0] in:latin];
	[[self queries] setCondition:@"=" value:@"Latin" ofNode:language.identifier reason:NULL];
	[[self queries] setProjected:YES ofNode:language.identifier];
	XCTAssertEqualObjects(rows(latin), (@[ @[ @1, @"Latin" ] ]));

	/* The branches employees work for, the employees not listed: each
	 * branch once. */
	NSString *branches = [[self queries] addQueryNamed:@"Branches" from:[self typeId:@"Employee"] reason:NULL];
	[[self queries] setProjected:NO ofNode:[self root:branches].identifier];
	ORMQueryNode *employer = [self from:[self root:branches].identifier through:[self role:@"worksFor" at:0] in:branches];
	[[self queries] setProjected:YES ofNode:employer.identifier];
	XCTAssertEqualObjects(rows(branches), (@[ @[ @101 ], @[ @102 ], @[ @52 ], @[ @7 ] ]));
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* A cursor reads a page at a time, in the plan's order, as far as asked:
 * also where what it fetches is checked on the objects. */
- (void)testACursorReadsPages
{
	NSDictionary *queries = [self paperQueries];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:model];
	NSArray *(^pages)(NSString *, NSUInteger) = ^NSArray *(NSString *name, NSUInteger size) {
		ORMQueryPlan *plan = [planner planForQuery:[self query:[queries objectForKey:name]]];
		NSMutableArray *read = [NSMutableArray array];
		[context performBlockAndWait:^{
			NSError *error = nil;
			ORMQueryCursor *cursor = [interpreter cursorForPlan:plan inContext:context error:&error];
			XCTAssertNotNil(cursor, @"%@", error);
			for (NSUInteger guard = 0; guard < 10; guard++) {
				ORMQueryResult *page = [cursor nextPage:size error:&error];
				XCTAssertNotNil(page, @"%@", error);
				XCTAssertLessThanOrEqual([page.objects count], size);
				if ([page.objects count] == 0) {
					XCTAssertTrue([cursor atEnd]);
					break;
				}
				[read addObject:[page.objects valueForKey:@"nr"]];
			}
		}];
		return read;
	};
	/* In its order, the larger number first, one at a time. */
	XCTAssertEqualObjects(pages(@"Payroll", 1), (@[ @[ @52 ], @[ @7 ] ]));
	/* The same from the service. */
	ORMQueryOData *payroll = [ORMQueryOData requestForPlan:[planner planForQuery:[self query:[queries objectForKey:@"Payroll"]]]
	                                              coreData:planner.coreData error:NULL];
	XCTAssertEqualObjects([self pagesOf:payroll transport:[self countedServiceOver:context] size:1], (@[ @[ @52 ], @[ @7 ] ]));
	NSArray *drivers = pages(@"Q2", 2);
	XCTAssertEqual([drivers count], 2u);
	XCTAssertEqualObjects([[drivers valueForKeyPath:@"@unionOfArrays.self"] sortedArrayUsingSelector:@selector(compare:)],
	                      (@[ @1, @3, @4 ]));
	/* Checked on the objects (Q5's correlation out of scope is the store's;
	 * a total of some members is not): still a page at a time. */
	NSString *q = [self payroll];
	ORMQueryStep *employs = [[self query:q].root.steps firstObject];
	ORMQueryNode *language = [self from:[[employs.nodes firstObject] identifier] through:[self role:@"speaks" at:0] in:q];
	[[self queries] setCondition:@"=" value:@"Latin" ofNode:language.identifier reason:NULL];
	for (ORMQueryStep *step in [[employs.nodes firstObject] steps]) {
		if ([[[step.nodes firstObject] objectType].name isEqualToString:@"Salary"]) {
			[[self queries] setAggregate:ORMQueryTotal ofNode:[[step.nodes firstObject] identifier] comparison:@">"
			                       value:@"550000" ofStep:employs.identifier reason:NULL];
		}
	}
	ORMQueryPlan *latin = [planner planForQuery:[self query:q]];
	XCTAssertTrue([[latin text] rangeOfString:@"having"].location != NSNotFound, @"%@", [latin text]);
	__block NSArray *first = nil;
	__block BOOL ended = NO;
	[context performBlockAndWait:^{
		ORMQueryCursor *cursor = [interpreter cursorForPlan:latin inContext:context error:NULL];
		first = [[cursor nextPage:1 error:NULL].objects valueForKey:@"nr"];
		ended = [[cursor nextPage:1 error:NULL].objects count] == 0 && [cursor atEnd];
	}];
	XCTAssertEqualObjects(first, (@[ @52 ]));
	XCTAssertTrue(ended);
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}

/* A plan is data: written as a property list and read back the same; one
 * that names what no model can is refused. */
- (void)testAPlanIsAPropertyList
{
	NSDictionary *queries = [self paperQueries];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	for (NSString *name in queries) {
		ORMQueryPlan *plan = [planner planForQuery:[self query:[queries objectForKey:name]]];
		id list = [plan propertyList];
		NSData *data = [NSPropertyListSerialization dataWithPropertyList:list format:NSPropertyListXMLFormat_v1_0 options:0
		                                                           error:NULL];
		XCTAssertNotNil(data, @"%@", name);
		id read = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
		NSError *error = nil;
		ORMQueryPlan *back = [ORMQueryPlan planWithPropertyList:read error:&error];
		XCTAssertEqualObjects([back text], [plan text], @"%@: %@", name, error);
	}
	ORMQueryPlan *joined = [[[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:nil] planForQuery:[self query:[self q1]]];
	XCTAssertEqualObjects([[ORMQueryPlan planWithPropertyList:[joined propertyList] error:NULL] text], [joined text]);

	NSMutableDictionary *bad = [[[planner planForQuery:[self query:[self q1]]] propertyList] mutableCopy];
	[bad setObject:@"Employee where 1" forKey:@"entity"];
	NSError *error = nil;
	XCTAssertNil([ORMQueryPlan planWithPropertyList:bad error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"no entity's name"].location != NSNotFound, @"%@", error);
	NSDictionary *badPath = @{ @"entity": @"Employee",
	                           @"condition": @{ @"kind": @"notNull",
	                                            @"path": @{ @"steps": @[ @{ @"key": @"nr eq 0 or true" } ] } } };
	XCTAssertNil([ORMQueryPlan planWithPropertyList:badPath error:&error]);
	/* A set used before it is defined, or not at all, is refused. */
	NSMutableDictionary *undefined = [[joined propertyList] mutableCopy];
	[undefined removeObjectForKey:@"definitions"];
	XCTAssertNil([ORMQueryPlan planWithPropertyList:undefined error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"defined before"].location != NSNotFound, @"%@", error);
	XCTAssertEqual([[[ORMQueryPlan planWithPropertyList:[joined propertyList] error:NULL] definitions] count], 1u);
}

/* The requests, sent to ODataKit's service over the same store: the same
 * rows. */
/* Every row a cursor reads from the service, page by page. */
- (NSArray<NSArray *> *)rowsOf:(ORMQueryOData *)odata transport:(id<ODataTransport>)transport
{
	ORMQueryODataCursor *cursor = [odata cursorWithTransport:transport serviceRoot:[NSURL URLWithString:@"http://example.test/odata/"]];
	NSMutableArray *rows = [NSMutableArray array];
	for (NSUInteger guard = 0; guard < 20 && ![cursor atEnd]; guard++) {
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		__block ORMQueryResult *page = nil;
		__block NSError *error = nil;
		[cursor nextPage:3 completion:^(ORMQueryResult *result, NSError *failed) {
			page = result;
			error = failed;
			dispatch_semaphore_signal(done);
		}];
		XCTAssertEqual(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_SEC))), 0);
		XCTAssertNotNil(page, @"%@", error);
		if (page == nil || [page.objects count] == 0) {
			break;
		}
		[rows addObjectsFromArray:page.rows];
	}
	return rows;
}

/* The rows from the service are a result set, as the store's are: the same
 * tuples, a some's members only those meeting its conditions, a maybe's
 * each or none. */
- (void)testTheServiceRowsAreTheStoresRows
{
	NSMutableDictionary *queries = [NSMutableDictionary dictionaryWithDictionary:[self paperQueries]];
	NSString *latin = [[self queries] addQueryNamed:@"Latin" from:[self typeId:@"Employee"] reason:NULL];
	ORMQueryNode *language = [self from:[self root:latin].identifier through:[self role:@"speaks" at:0] in:latin];
	[[self queries] setProjected:YES ofNode:language.identifier];
	XCTAssertTrue([[self queries] setCondition:@"=" value:@"Latin" ofNode:language.identifier reason:NULL]);
	[queries setObject:latin forKey:@"Latin"];
	ORMQueryPlanner *planner = [[ORMQueryPlanner alloc] initWithModel:_editor.model mapping:[self mapping]];
	NSManagedObjectModel *model = [planner.coreData managedObjectModel];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:model];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
	ORMTestCountingTransport *counted = [self countedServiceOver:context];
	for (NSString *name in queries) {
		/* Each query's let go of before the next: GNUstep's XCTest drains
		 * nothing between them, and the service's answers are many. */
		@autoreleasepool {
			ORMQueryPlan *plan = [planner planForQuery:[self query:[queries objectForKey:name]]];
			__block ORMQueryResult *stored = nil;
			[context performBlockAndWait:^{
				stored = [interpreter executePlan:plan inContext:context error:NULL];
			}];
			ORMQueryOData *odata = [ORMQueryOData requestForPlan:plan coreData:planner.coreData error:NULL];
			NSArray *served = [self rowsOf:odata transport:counted];
			XCTAssertEqualObjects([NSSet setWithArray:served], [NSSet setWithArray:stored.rows], @"%@\n%@", name,
			                      [odata requestText]);
			XCTAssertEqual([served count], [stored.rows count], @"%@", name);
		}
	}
	ORMQueryPlan *plan = [planner planForQuery:[self query:latin]];
	__block ORMQueryResult *latinRows = nil;
	[context performBlockAndWait:^{
		latinRows = [interpreter executePlan:plan inContext:context error:NULL];
	}];
	XCTAssertEqualObjects(latinRows.rows, (@[ @[ @1, @"Latin" ] ]));
}

- (void)testTheServiceAnswersTheQueries
{
	NSDictionary *queries = [self paperQueries];
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:_editor.model mapping:[self mapping]] map];
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	[[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
	NSManagedObjectContext *context = [self companyIn:directory model:[mapped managedObjectModel]];
	NSPersistentStoreCoordinator *coordinator = context.persistentStoreCoordinator;
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
	NSDictionary *answers = [self paperAnswers];
	for (NSString *name in answers) {
		@autoreleasepool {
			NSArray *got = numbers([queries objectForKey:name]);
			/* In the order the query asks for, where it does. */
			XCTAssertEqualObjects([name isEqualToString:@"Payroll"] ? got : sorted(got), [answers objectForKey:name], @"%@",
			                      name);
		}
	}
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
}


@end

