/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* The mapping's userInfo for ODataKit (ORMODataAnnotator.h). */
@interface ORMODataTests : ORMTestCase
@end

@implementation ORMODataTests

- (NSString *)entity:(NSString *)name mode:(NSString *)mode in:(ORMEditor *)editor
{
	return [editor.objectTypeEditor addEntityTypeNamed:name referenceMode:mode
	                             kind:mode != nil ? ORMReferenceModePopular : ORMReferenceModeNone
	                        onDiagram:[[editor.model.diagrams firstObject] identifier] at:ORMAutomaticPlacement reason:NULL];
}

- (NSString *)value:(NSString *)name type:(NSString *)dataType in:(ORMEditor *)editor
{
	return [editor.objectTypeEditor addValueTypeNamed:name dataType:dataType onDiagram:nil at:NSZeroPoint reason:NULL];
}

/* "{0} has {1}", unique on the first role: an attribute of the first. */
- (NSString *)has:(NSString *)owner value:(NSString *)value in:(ORMEditor *)editor
{
	NSString *fact = [editor.factTypeEditor addFactTypeWithPlayers:@[ owner, value ] reading:@"{0} has {1}" onDiagram:nil
	                                             at:NSZeroPoint reason:NULL];
	[editor.constraintEditor setUnique:YES role:[[[[editor.model elementWithId:fact] roles] firstObject] identifier] reason:NULL];
	return fact;
}

- (ORMCDModel *)map:(ORMEditor *)editor serving:(BOOL)serving notes:(NSArray<ORMMappingNote *> **)notes
{
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:editor];
	NSString *mappingId = [mappings addCoreDataMappingNamed:@"Test" path:@"Test.xcdatamodeld"];
	[mappings setServesOData:serving ofMapping:mappingId];
	ORMCoreDataMapping *mapping = [ORMCoreDataMapping mappingWithId:mappingId inDocument:editor.document];
	ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:mapping];
	ORMCDModel *mapped = [mapper map];
	if (notes != NULL) {
		*notes = mapper.notes;
	}
	return mapped;
}

static NSArray<NSString *> *
ORMKeyOf(ORMCDEntity *entity)
{
	NSMutableArray *names = [NSMutableArray array];
	for (ORMCDAttribute *attribute in entity.attributes) {
		if ([[attribute.userInfo objectForKey:@"OData.key"] isEqualToString:@"YES"]) {
			[names addObject:attribute.name];
		}
	}
	return names;
}

/* Each entity in a set of its plural name, keyed by its reference mode;
 * a subtype in its supertype's, by its key. */
- (void)testEntitiesAreServedInSetsByTheirIdentifiers
{
	ORMEditor *editor = [self newEditor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *city = [self entity:@"City" mode:@"id" in:editor];
	[editor.objectTypeEditor addSubtype:city of:country reason:NULL];
	[editor.elementEditor setDefinition:@"A sovereign state." of:country reason:NULL];
	ORMCDModel *mapped = [self map:editor serving:YES notes:NULL];
	ORMCDEntity *countries = [mapped entityNamed:@"Country"];
	XCTAssertEqualObjects([countries.userInfo objectForKey:@"OData.entitySet"], @"Countries");
	XCTAssertEqualObjects([countries.userInfo objectForKey:@"OData.description"], @"A sovereign state.");
	XCTAssertEqualObjects(ORMKeyOf(countries), (@[ @"code" ]));
	ORMCDEntity *cities = [mapped entityNamed:@"City"];
	XCTAssertEqualObjects(cities.parentName, @"Country");
	XCTAssertNil([cities.userInfo objectForKey:@"OData.entitySet"]);
	XCTAssertEqualObjects(ORMKeyOf(cities), @[]);
}

/* What is identified by what it relates (a marriage by its partners, a
 * visit by who and where) gets a number the service gives it. */
- (void)testAnIdentifierOfRelationshipsGetsASurrogateKey
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *married = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, person ] reading:@"{0} married {1}"
	                                                onDiagram:nil at:NSZeroPoint reason:NULL];
	[editor.factTypeEditor objectifyFactType:married named:@"Marriage" reason:NULL];
	NSArray<ORMMappingNote *> *notes = nil;
	ORMCDModel *mapped = [self map:editor serving:YES notes:&notes];
	ORMCDEntity *marriage = [mapped entityNamed:@"Marriage"];
	XCTAssertEqualObjects(ORMKeyOf(marriage), (@[ @"id" ]));
	ORMCDAttribute *key = [marriage attributeNamed:@"id"];
	XCTAssertEqualObjects(key.attributeType, @"Integer 64");
	XCTAssertFalse(key.optional);
	XCTAssertEqualObjects([key.userInfo objectForKey:@"OData.computed"], @"YES");
	XCTAssertEqualObjects(key.source, [[[editor.model objectTypeNamed:@"Marriage"] identifier] stringByAppendingString:@".key"]);
	BOOL noted = NO;
	for (ORMMappingNote *note in notes) {
		noted = noted || [note.text rangeOfString:@"Marriage is keyed in OData by id"].location != NSNotFound;
	}
	XCTAssertTrue(noted, @"%@", notes);
	/* The person keeps its own, and nothing is added. */
	XCTAssertEqualObjects(ORMKeyOf([mapped entityNamed:@"Person"]), (@[ @"id" ]));
	XCTAssertNil([self momcRejects:mapped]);
}

/* A value list and an open bound, which Core Data cannot say, as
 * Validation terms; what it can say (a closed range) left to it. */
- (void)testValueConstraintsCoreDataCannotSayAreAnnotated
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *gender = [self value:@"Gender" type:@"FixedLengthTextDataType" in:editor];
	NSString *rating = [self value:@"Rating" type:@"SignedIntegerNumericDataType" in:editor];
	NSString *score = [self value:@"Score" type:@"DecimalNumericDataType" in:editor];
	NSString *age = [self value:@"Age" type:@"UnsignedSmallIntegerNumericDataType" in:editor];
	[editor.objectTypeEditor setValueConstraint:@"{'M', 'F'}" of:gender reason:NULL];
	[editor.objectTypeEditor setValueConstraint:@"{1, 2, 3}" of:rating reason:NULL];
	[editor.objectTypeEditor setValueConstraint:@"{(0..100]}" of:score reason:NULL];
	[editor.objectTypeEditor setValueConstraint:@"{0..140}" of:age reason:NULL];
	[editor.elementEditor setDefinition:@"In whole years." of:age reason:NULL];
	for (NSString *value in @[ gender, rating, score, age ]) {
		[self has:person value:value in:editor];
	}
	ORMCDEntity *entity = [[self map:editor serving:YES notes:NULL] entityNamed:@"Person"];
	NSString *(^annotations)(NSString *) = ^NSString *(NSString *name) {
		return [[[entity attributeNamed:name] userInfo] objectForKey:@"OData.annotations"];
	};
	XCTAssertEqualObjects(annotations(@"gender"), @"{\"Validation.AllowedValues\": [{\"Value\": \"M\"}, {\"Value\": \"F\"}]}");
	XCTAssertEqualObjects(annotations(@"rating"), @"{\"Validation.AllowedValues\": [{\"Value\": 1}, {\"Value\": 2}, {\"Value\": 3}]}");
	XCTAssertEqualObjects(annotations(@"score"), @"{\"Validation.Minimum\": 0, \"Validation.Minimum@Validation.Exclusive\": true}");
	XCTAssertNil(annotations(@"age"));
	XCTAssertEqualObjects([[[entity attributeNamed:@"age"] userInfo] objectForKey:@"OData.description"], @"In whole years.");
}

/* Off, the mapping says nothing of OData and adds nothing. */
- (void)testAMappingNotServedSaysNothingOfOData
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *married = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, person ] reading:@"{0} married {1}"
	                                                onDiagram:nil at:NSZeroPoint reason:NULL];
	[editor.factTypeEditor objectifyFactType:married named:@"Marriage" reason:NULL];
	ORMCDModel *mapped = [self map:editor serving:NO notes:NULL];
	for (ORMCDEntity *entity in mapped.entities) {
		XCTAssertNil([entity.userInfo objectForKey:@"OData.entitySet"]);
		XCTAssertEqualObjects(ORMKeyOf(entity), @[]);
	}
	XCTAssertNil([[mapped entityNamed:@"Marriage"] attributeNamed:@"id"]);
}

@end
