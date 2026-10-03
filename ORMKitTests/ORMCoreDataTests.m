/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* ORM to Core Data and back (docs/COREDATA-MAPPING.md). */
@interface ORMCoreDataTests : ORMTestCase
@end

@implementation ORMCoreDataTests

- (ORMMappingEditor *)mappingsOf:(ORMEditor *)editor
{
	return [[ORMMappingEditor alloc] initWithEditor:editor];
}

- (ORMCDModel *)map:(ORMModel *)model
{
	return [[[ORMCoreDataMapper alloc] initWithModel:model mapping:nil] map];
}

- (NSString *)diagramOf:(ORMEditor *)editor
{
	return [[editor.model.diagrams firstObject] identifier];
}

- (NSString *)entity:(NSString *)name mode:(NSString *)mode in:(ORMEditor *)editor
{
	return [editor.objectTypeEditor addEntityTypeNamed:name referenceMode:mode
	                             kind:mode != nil ? ORMReferenceModePopular : ORMReferenceModeNone
	                        onDiagram:[self diagramOf:editor] at:ORMAutomaticPlacement reason:NULL];
}

- (NSArray<ORMRole *> *)rolesOf:(NSString *)factId in:(ORMEditor *)editor
{
	return [[editor.model elementWithId:factId] roles];
}

/* What Apple's model compiler says of the model, on a Mac; nil elsewhere
 * or when it accepts it. */
- (NSString *)momcRejects:(ORMCDModel *)model
{
#if defined(__APPLE__)
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	NSString *package = [directory stringByAppendingPathComponent:@"Test.xcdatamodeld"];
	NSError *error = nil;
	if (![model writeToPackage:package error:&error]) {
		return [error localizedDescription];
	}
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/usr/bin/xcrun";
	task.arguments = @[ @"momc", package, [directory stringByAppendingPathComponent:@"Test.momd"] ];
	NSPipe *pipe = [NSPipe pipe];
	task.standardError = pipe;
	task.standardOutput = pipe;
	[task launch];
	NSData *output = [[pipe fileHandleForReading] readDataToEndOfFile];
	[task waitUntilExit];
	[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL];
	NSString *text = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding];
	return [task terminationStatus] == 0 ? nil : text;
#else
	(void)model;
	return nil;
#endif
}

#pragma mark ORM to Core Data

- (ORMCDModel *)map:(NSString *)fixture configuring:(void (^)(ORMEditor *editor, NSString *mapping))configure
{
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:[self fixtureDocument:fixture] undoManager:nil];
	NSString *mappingId = [[self mappingsOf:editor] addCoreDataMappingNamed:@"Test" path:@"Test.xcdatamodeld"];
	configure(editor, mappingId);
	ORMCoreDataMapping *mapping = [ORMCoreDataMapping mappingWithId:mappingId inDocument:editor.document];
	return [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:mapping] map];
}

static NSString *
ORMSquashed(NSString *name)
{
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < [name length]; i++) {
		unichar c = [name characterAtIndex:i];
		if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
			[out appendString:[[NSString stringWithCharacters:&c length:1] lowercaseString]];
		}
	}
	return out;
}

/* The Relational style is Rmap's grouping: every table ActiveFacts' Rmap
 * makes of Heath's models is an entity, but for the types his CQL marks
 * [separate] or [static] (a modeller's choice, made here by mapping the
 * type as an entity). */
- (void)testRmapModeMakesTheTablesRmapMakes
{
	NSSet *separate = [NSSet setWithArray:@[ @"coveragetype", @"incidenttype", @"insurer", @"vehicleincident" ]];
	NSUInteger tables = 0;
	for (NSString *name in [self activeFactsFixtures]) {
		NSString *model = [[name lastPathComponent] stringByDeletingPathExtension];
		NSString *sqlName = [NSString stringWithFormat:@"ActiveFacts/sql/%@.sql", model];
		if (![[NSFileManager defaultManager] fileExistsAtPath:[self fixturePath:sqlName]]) {
			/* Heath published no tables for it (MultipleSubtyping). */
			continue;
		}
		NSString *sql = [[NSString alloc] initWithData:[self fixtureData:sqlName] encoding:NSUTF8StringEncoding];
		ORMCDModel *mapped = [self map:name configuring:^(ORMEditor *editor, NSString *mapping) {
			[[self mappingsOf:editor] setStyle:ORMStyleRelational ofMapping:mapping];
		}];
		NSMutableSet *entities = [NSMutableSet set];
		for (ORMCDEntity *entity in mapped.entities) {
			[entities addObject:ORMSquashed(entity.name)];
		}
		NSRegularExpression *create = [NSRegularExpression regularExpressionWithPattern:@"CREATE TABLE (\\w+)" options:0
		                                                                          error:NULL];
		for (NSTextCheckingResult *match in [create matchesInString:sql options:0 range:NSMakeRange(0, [sql length])]) {
			NSString *table = ORMSquashed([sql substringWithRange:[match rangeAtIndex:1]]);
			tables++;
			XCTAssertTrue([entities containsObject:table] || [separate containsObject:table], @"%@: no entity for %@",
			              model, table);
		}
		XCTAssertNil([self momcRejects:mapped], @"%@", model);
	}
	XCTAssertTrue(tables > 150);
}

/* A value type that plays a role of its own is an entity keyed by its
 * value, as Rmap gives it a table: "Some String is long". */
- (void)testAValueTypeWithRolesOfItsOwnIsAnEntity
{
	ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:@"ActiveFacts/SimplestUnary.orm"] reason:NULL];
	ORMCDModel *mapped = [self map:model];
	ORMCDEntity *entity = [mapped entityNamed:@"SomeString"];
	XCTAssertNotNil(entity);
	XCTAssertNotNil([entity attributeNamed:@"value"]);
	XCTAssertEqualObjects([[entity attributeNamed:@"isLong"] attributeType], @"Boolean");
	XCTAssertTrue([entity.uniquenessConstraints containsObject:@[ @"value" ]]);
	XCTAssertNil([self momcRejects:mapped]);
}

/* A value type of a class of its own: a URL, say. */
- (void)testAValueTypeAsTransformable
{
	__block NSString *valueTypeId = nil;
	ORMCDModel *mapped = [self map:@"StockMate.orm" configuring:^(ORMEditor *editor, NSString *mapping) {
		valueTypeId = [[editor.model objectTypeNamed:@"Barcode"] identifier];
		[[self mappingsOf:editor] setTransformableClass:@"NSURL" transformer:nil ofObjectType:valueTypeId inMapping:mapping];
	}];
	ORMCDAttribute *barcode = nil;
	for (ORMCDAttribute *attribute in [[mapped entityNamed:@"Product"] attributes]) {
		if ([[attribute.name lowercaseString] hasPrefix:@"barcode"]) {
			barcode = attribute;
		}
	}
	XCTAssertEqualObjects(barcode.attributeType, @"Transformable");
	XCTAssertEqualObjects([barcode.extraAttributes objectForKey:@"customClassName"], @"NSURL");
	XCTAssertEqualObjects([barcode.extraAttributes objectForKey:@"valueTransformerName"], @"NSSecureUnarchiveFromData");
	XCTAssertNil([self momcRejects:mapped]);
}

/* Every model NORMA wrote maps to one Core Data takes: Clifford Heath's
 * examples, NORMA's own samples, metamodels and test suites;
 * objectification, subtyping several ways, rings, ternaries. */
- (void)testEveryNormaModelMapsToAModelCoreDataAccepts
{
	for (NSString *name in [self allNormaFiles]) {
		ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:name] reason:NULL];
		XCTAssertNotNil(model, @"%@", name);
		XCTAssertNil([self momcRejects:[self map:model]], @"%@", name);
	}
}

- (void)testStockMateMapsToAModelCoreDataAccepts
{
	ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:@"StockMate.orm"] reason:NULL];
	ORMCDModel *mapped = [self map:model];
	XCTAssertNil([self momcRejects:mapped]);
	ORMCDEntity *product = [mapped entityNamed:@"Product"];
	XCTAssertNotNil(product);
	ORMCDAttribute *identifier = [product attributeNamed:@"id"];
	XCTAssertEqualObjects(identifier.attributeType, @"Integer 64");
	XCTAssertFalse(identifier.optional);
	XCTAssertTrue([product.uniquenessConstraints containsObject:@[ @"id" ]]);
	XCTAssertTrue([product.uniquenessConstraints containsObject:@[ @"sku" ]]);
	/* A measure is absorbed: Weight(kg:) is Product.weight, a Decimal. */
	XCTAssertNil([mapped entityNamed:@"Weight"]);
	XCTAssertEqualObjects([[product attributeNamed:@"weight"] attributeType], @"Decimal");
	/* A thing with an id is not, though nothing else is said of it. */
	XCTAssertNotNil([mapped entityNamed:@"UnitOfMeasure"]);
	/* Unaries are Booleans. */
	XCTAssertEqualObjects([[product attributeNamed:@"isActive"] attributeType], @"Boolean");
	/* What is no more than values is part of what uses it: a Warehouse's
	 * Address (its id a surrogate, its street, city and the rest a key),
	 * the Address's Street (three lines), named as the readings name them. */
	XCTAssertNil([mapped entityNamed:@"Address"]);
	XCTAssertNil([mapped entityNamed:@"Street"]);
	ORMCDEntity *warehouse = [mapped entityNamed:@"Warehouse"];
	for (NSString *name in @[ @"addressCity", @"addressPostalCode", @"addressStreetFirstStreetLine",
	                          @"addressStreetSecondStreetLine", @"addressStreetThirdStreetLine" ]) {
		XCTAssertNotNil([warehouse attributeNamed:name], @"%@", name);
	}
	XCTAssertNotNil([warehouse relationshipNamed:@"addressCountry"]);
}

/* What the store is for decides what is absorbed: the Entities style
 * keeps an Address an entity, as reports over addresses want it. */
- (void)testTheStyleDecidesWhatIsAbsorbed
{
	ORMCDModel *entities = [self map:@"StockMate.orm" configuring:^(ORMEditor *editor, NSString *mapping) {
		[[self mappingsOf:editor] setStyle:ORMStyleEntities ofMapping:mapping];
	}];
	XCTAssertNotNil([entities entityNamed:@"Address"]);
	XCTAssertNotNil([entities entityNamed:@"Street"]);
	XCTAssertNil([self momcRejects:entities]);
	/* An object type's own mapping decides over the style. */
	ORMCDModel *kept = [self map:@"StockMate.orm" configuring:^(ORMEditor *editor, NSString *mapping) {
		[[self mappingsOf:editor] setMapping:ORMMapAsEntity ofObjectType:[[editor.model objectTypeNamed:@"Address"] identifier]
		         inMapping:mapping];
	}];
	XCTAssertNotNil([kept entityNamed:@"Address"]);
	XCTAssertNil([kept entityNamed:@"Street"]);
	/* An objectification one to one with its player is folded into it. */
	ORMCDModel *death = [self map:@"ActiveFacts/Death.orm" configuring:^(ORMEditor *editor, NSString *mapping) {
		(void)editor;
		(void)mapping;
	}];
	XCTAssertNil([death entityNamed:@"Death"]);
	XCTAssertNotNil([death entityNamed:@"Person"]);
	XCTAssertNil([self momcRejects:death]);
}

/* A model another tool wrote in NORMA's format maps as well. */
- (void)testPreventiveMaintenanceMapsToAModelCoreDataAccepts
{
	ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:@"PreventiveMaintenance.orm"] reason:NULL];
	XCTAssertEqual([model.diagrams count], (NSUInteger)3);
	ORMCDModel *mapped = [self map:model];
	XCTAssertTrue([mapped.entities count] > 5);
	XCTAssertNotNil([mapped entityNamed:@"Asset"]);
	XCTAssertNil([self momcRejects:mapped]);
	XCTAssertTrue([[[[ORMVerbalizer alloc] initWithModel:model] sentencesForModel] count] > 50);
}

- (void)testTheContentsReadBackAsWritten
{
	ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:@"StockMate.orm"] reason:NULL];
	ORMCDModel *mapped = [self map:model];
	NSData *contents = [mapped contentsXML];
	ORMCDModel *read = [ORMCDModel modelWithContentsXML:contents reason:NULL];
	XCTAssertEqualObjects([read contentsXML], contents);
	XCTAssertEqualObjects([[[read entityNamed:@"Product"] attributeNamed:@"id"] source],
	                      [[[mapped entityNamed:@"Product"] attributeNamed:@"id"] source]);
}

- (void)testRelationshipsFollowUniquenessAndMandatory
{
	ORMEditor *editor = [self newEditor];
	NSString *notebook = [self entity:@"Notebook" mode:@"id" in:editor];
	NSString *note = [self entity:@"Note" mode:@"id" in:editor];
	NSString *contains = [editor.factTypeEditor addFactTypeWithPlayers:@[ notebook, note ] reading:@"{0} contains {1}" onDiagram:nil
	                                                 at:NSZeroPoint reason:NULL];
	NSArray *roles = [self rolesOf:contains in:editor];
	[editor.constraintEditor setUnique:YES role:[roles[1] identifier] reason:NULL];
	[editor.constraintEditor setMandatory:YES role:[roles[1] identifier] reason:NULL];
	ORMCDModel *mapped = [self map:editor.model];
	ORMCDRelationship *notes = [[mapped entityNamed:@"Notebook"] relationshipNamed:@"notes"];
	ORMCDRelationship *back = [[mapped entityNamed:@"Note"] relationshipNamed:@"notebook"];
	XCTAssertTrue(notes.toMany);
	XCTAssertFalse(back.toMany);
	XCTAssertEqualObjects(notes.inverseName, @"notebook");
	/* A note belongs to exactly one notebook: deleting it deletes them. */
	XCTAssertEqualObjects(notes.deletionRule, @"Cascade");
	/* Mandatory, but Notebook has a uniqueness constraint (its id), which
	 * Core Data does not allow beside a mandatory to-one: loosened. */
	XCTAssertTrue(back.optional);
	XCTAssertEqualObjects([back.userInfo objectForKey:@"ormkit.mandatory"], @"YES");
	XCTAssertNil([self momcRejects:mapped]);
}

- (void)testManyToManyAndValueSets
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *club = [self entity:@"Club" mode:@"code" in:editor];
	NSString *language = [editor.objectTypeEditor addValueTypeNamed:@"Language" dataType:@"VariableLengthTextDataType" onDiagram:nil
	                                            at:NSZeroPoint reason:NULL];
	NSString *joined = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, club ] reading:@"{0} joined {1}" onDiagram:nil
	                                               at:NSZeroPoint reason:NULL];
	NSArray *joinedRoles = [self rolesOf:joined in:editor];
	[editor.constraintEditor addUniquenessConstraintOverRoles:@[ [joinedRoles[0] identifier], [joinedRoles[1] identifier] ] reason:NULL];
	NSString *speaks = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, language ] reading:@"{0} speaks {1}" onDiagram:nil
	                                               at:NSZeroPoint reason:NULL];
	NSArray *speaksRoles = [self rolesOf:speaks in:editor];
	[editor.constraintEditor addUniquenessConstraintOverRoles:@[ [speaksRoles[0] identifier], [speaksRoles[1] identifier] ] reason:NULL];
	ORMCDModel *mapped = [self map:editor.model];
	XCTAssertTrue([[[mapped entityNamed:@"Person"] relationshipNamed:@"clubs"] toMany]);
	XCTAssertTrue([[[mapped entityNamed:@"Club"] relationshipNamed:@"people"] toMany] ||
	              [[[mapped entityNamed:@"Club"] relationshipNamed:@"persons"] toMany]);
	ORMCDEntity *languages = [mapped entityNamed:@"Language"];
	XCTAssertNotNil(languages, @"a many-valued value type is an entity");
	XCTAssertEqualObjects([[languages attributeNamed:@"value"] attributeType], @"String");
	XCTAssertTrue([[[mapped entityNamed:@"Person"] relationshipNamed:@"languages"] toMany]);
	XCTAssertNil([self momcRejects:mapped]);
}

- (void)testSubtypesInheritAndCoveredSupertypesAreAbstract
{
	ORMEditor *editor = [self newEditor];
	NSString *party = [self entity:@"Party" mode:@"id" in:editor];
	NSString *person = [self entity:@"Person" mode:nil in:editor];
	NSString *company = [self entity:@"Company" mode:nil in:editor];
	NSString *personFact = [editor.objectTypeEditor addSubtype:person of:party reason:NULL];
	NSString *companyFact = [editor.objectTypeEditor addSubtype:company of:party reason:NULL];
	NSString *name = [editor.objectTypeEditor addValueTypeNamed:@"PersonName" dataType:nil onDiagram:nil at:NSZeroPoint reason:NULL];
	NSString *named = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, name ] reading:@"{0} has {1}" onDiagram:nil
	                                              at:NSZeroPoint reason:NULL];
	[editor.constraintEditor setUnique:YES role:[[self rolesOf:named in:editor][0] identifier] reason:NULL];
	ORMCDModel *mapped = [self map:editor.model];
	XCTAssertEqualObjects([[mapped entityNamed:@"Person"] parentName], @"Party");
	XCTAssertFalse([[mapped entityNamed:@"Party"] isAbstract]);
	XCTAssertNotNil([[mapped entityNamed:@"Person"] attributeNamed:@"personName"]);
	/* Every party is a person or a company. */
	NSString *supertypeOfPerson = [[self rolesOf:personFact in:editor][1] identifier];
	NSString *supertypeOfCompany = [[self rolesOf:companyFact in:editor][1] identifier];
	[editor.constraintEditor addMandatoryConstraintOverRoles:@[ supertypeOfPerson, supertypeOfCompany ] reason:NULL];
	mapped = [self map:editor.model];
	XCTAssertTrue([[mapped entityNamed:@"Party"] isAbstract]);
	XCTAssertNil([self momcRejects:mapped]);
}

- (void)testLongerAndObjectifiedFactTypesAreEntities
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *year = [editor.objectTypeEditor addValueTypeNamed:@"Year" dataType:@"SignedIntegerNumericDataType" onDiagram:nil
	                                        at:NSZeroPoint reason:NULL];
	NSString *visited = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, country, year ] reading:@"{0} visited {1} in {2}"
	                                         onDiagram:nil at:NSZeroPoint reason:NULL];
	NSArray *roles = [self rolesOf:visited in:editor];
	[editor.constraintEditor addUniquenessConstraintOverRoles:@[ [roles[0] identifier], [roles[1] identifier] ] reason:NULL];
	NSString *married = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, person ] reading:@"{0} married {1}" onDiagram:nil
	                                                at:NSZeroPoint reason:NULL];
	[editor.factTypeEditor objectifyFactType:married named:@"Marriage" reason:NULL];
	ORMCDModel *mapped = [self map:editor.model];
	ORMCDEntity *visit = [mapped entityNamed:@"PersonVisitedCountryInYear"];
	XCTAssertNotNil(visit);
	XCTAssertNotNil([visit relationshipNamed:@"person"]);
	XCTAssertNotNil([visit attributeNamed:@"year"]);
	XCTAssertTrue([visit.uniquenessConstraints containsObject:(@[ @"person", @"country" ])]);
	ORMCDEntity *marriage = [mapped entityNamed:@"Marriage"];
	XCTAssertNotNil(marriage);
	XCTAssertEqual([marriage.relationships count], (NSUInteger)2, @"%@", marriage);
	XCTAssertNil([self momcRejects:mapped]);
}

- (void)testValueConstraintsBecomeBoundsAndPatterns
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *gender = [editor.objectTypeEditor addValueTypeNamed:@"Gender" dataType:@"FixedLengthTextDataType" onDiagram:nil
	                                          at:NSZeroPoint reason:NULL];
	NSString *age = [editor.objectTypeEditor addValueTypeNamed:@"Age" dataType:@"UnsignedSmallIntegerNumericDataType" onDiagram:nil
	                                       at:NSZeroPoint reason:NULL];
	[editor.objectTypeEditor setValueConstraint:@"{'M', 'F'}" of:gender reason:NULL];
	[editor.objectTypeEditor setValueConstraint:@"{0..140}" of:age reason:NULL];
	for (NSString *value in @[ gender, age ]) {
		NSString *fact = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, value ] reading:@"{0} has {1}" onDiagram:nil
		                                             at:NSZeroPoint reason:NULL];
		[editor.constraintEditor setUnique:YES role:[[self rolesOf:fact in:editor][0] identifier] reason:NULL];
	}
	ORMCDEntity *entity = [[self map:editor.model] entityNamed:@"Person"];
	XCTAssertEqualObjects([[entity attributeNamed:@"gender"] regularExpression], @"^(?:M|F)$");
	XCTAssertEqualObjects([[entity attributeNamed:@"age"] minValue], @"0");
	XCTAssertEqualObjects([[entity attributeNamed:@"age"] maxValue], @"140");
}

- (void)testNamedRolesNameTheWayBack
{
	ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:@"WorkMate.orm"] reason:NULL];
	ORMCDModel *mapped = [self map:model];
	XCTAssertNil([self momcRejects:mapped]);
	ORMCDEntity *order = [mapped entityNamed:@"WorkOrder"];
	XCTAssertEqualObjects([[order relationshipNamed:@"requestor"] inverseName], @"workOrdersAsRequestor");
	XCTAssertEqualObjects([[order relationshipNamed:@"assignee"] inverseName], @"workOrdersAsAssignee");
	XCTAssertEqualObjects([[[mapped entityNamed:@"EquipmentType"] relationshipNamed:@"parent"] inverseName],
	                      @"equipmentTypesAsParent");
	/* A composite name is a composite uniqueness constraint. */
	XCTAssertTrue([[mapped entityNamed:@"Meter"].uniquenessConstraints containsObject:(@[ @"meterGroup", @"meterName" ])]);
}

- (void)testCollidingNamesComeFromTheReadings
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	for (NSString *reading in @[ @"{0} was born in {1}", @"{0} lives in {1}" ]) {
		NSString *fact = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, country ] reading:reading onDiagram:nil
		                                             at:NSZeroPoint reason:NULL];
		[editor.constraintEditor setUnique:YES role:[[self rolesOf:fact in:editor][0] identifier] reason:NULL];
	}
	ORMCDEntity *entity = [[self map:editor.model] entityNamed:@"Person"];
	XCTAssertNotNil([entity relationshipNamed:@"country"]);
	XCTAssertNotNil([entity relationshipNamed:@"livesInCountry"], @"%@", entity);
}

- (void)testOverridesExclusionsAndIgnoredObjectTypes
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *secret = [self entity:@"Secret" mode:@"id" in:editor];
	NSString *knows = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, secret ] reading:@"{0} knows {1}" onDiagram:nil
	                                              at:NSZeroPoint reason:NULL];
	[editor.constraintEditor setUnique:YES role:[[self rolesOf:knows in:editor][0] identifier] reason:NULL];
	NSString *mapping = [[self mappingsOf:editor] addCoreDataMappingNamed:@"App" path:@"App.xcdatamodeld"];
	[[self mappingsOf:editor] setName:@"Human" forSource:person inMapping:mapping];
	ORMCoreDataMapping *read = [ORMCoreDataMapping mappingWithId:mapping inDocument:editor.document];
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:read] map];
	XCTAssertNotNil([mapped entityNamed:@"Human"]);
	XCTAssertNotNil([[mapped entityNamed:@"Human"] relationshipNamed:@"secret"]);
	[[self mappingsOf:editor] setMapping:ORMMapIgnored ofObjectType:secret inMapping:mapping];
	read = [ORMCoreDataMapping mappingWithId:mapping inDocument:editor.document];
	mapped = [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:read] map];
	XCTAssertNil([mapped entityNamed:@"Secret"]);
	XCTAssertNil([[mapped entityNamed:@"Human"] relationshipNamed:@"secret"]);
	/* What NORMA is given does not have it. */
	NSXMLDocument *forNorma = [editor documentForNorma];
	XCTAssertEqual([ORMDescendants([forNorma rootElement], ORMCoreDataNamespace, nil) count], (NSUInteger)0);
}

#pragma mark Core Data back to ORM

/* A model with a mapping synchronized once: the baseline written. */
- (NSString *)syncedMappingIn:(ORMEditor *)editor
{
	NSString *mapping = [[self mappingsOf:editor] addCoreDataMappingNamed:@"App" path:@"App.xcdatamodeld"];
	ORMCoreDataSync *sync = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:nil];
	XCTAssertEqual([sync.changes count], (NSUInteger)0);
	[sync apply];
	XCTAssertNotNil([[ORMCoreDataMapping mappingWithId:mapping inDocument:editor.document] baseline]);
	return mapping;
}

- (ORMCDModel *)baselineOf:(NSString *)mapping in:(ORMEditor *)editor
{
	return [[[ORMCoreDataMapping mappingWithId:mapping inDocument:editor.document] baseline] copy];
}

- (ORMEditor *)personModel
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *name = [editor.objectTypeEditor addValueTypeNamed:@"Name" dataType:@"VariableLengthTextDataType" onDiagram:nil
	                                        at:NSZeroPoint reason:NULL];
	NSString *named = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, name ] reading:@"{0} has {1}" onDiagram:nil
	                                              at:NSZeroPoint reason:NULL];
	[editor.constraintEditor setUnique:YES role:[[self rolesOf:named in:editor][0] identifier] reason:NULL];
	return editor;
}

- (void)testANewModelSynchronizesWithNothingToAsk
{
	ORMEditor *editor = [self personModel];
	NSString *mapping = [self syncedMappingIn:editor];
	ORMCDModel *theirs = [self baselineOf:mapping in:editor];
	ORMCoreDataSync *again = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:theirs];
	XCTAssertEqual([again.changes count], (NSUInteger)0, @"%@", again.changes);
}

- (void)testARenameInCoreDataIsKeptAsAnOverride
{
	ORMEditor *editor = [self personModel];
	NSString *mapping = [self syncedMappingIn:editor];
	ORMCDModel *theirs = [self baselineOf:mapping in:editor];
	[[theirs entityNamed:@"Person"] attributeNamed:@"name"].name = @"fullName";
	ORMCoreDataSync *sync = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:theirs];
	XCTAssertEqual([sync.changes count], (NSUInteger)1, @"%@", sync.changes);
	XCTAssertEqual([sync.changes.firstObject kind], ORMSyncRenameProperty);
	ORMCDModel *written = [sync apply];
	XCTAssertNotNil([[written entityNamed:@"Person"] attributeNamed:@"fullName"]);
	XCTAssertNil([[written entityNamed:@"Person"] attributeNamed:@"name"]);
	/* And it stays so the next time round. */
	ORMCoreDataSync *next = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:written];
	XCTAssertEqual([next.changes count], (NSUInteger)0, @"%@", next.changes);
}

- (void)testRequiringAnAttributeMakesTheRoleMandatory
{
	ORMEditor *editor = [self personModel];
	NSString *mapping = [self syncedMappingIn:editor];
	ORMCDModel *theirs = [self baselineOf:mapping in:editor];
	[[theirs entityNamed:@"Person"] attributeNamed:@"name"].optional = NO;
	ORMCoreDataSync *sync = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:theirs];
	XCTAssertEqual([sync.changes.firstObject kind], ORMSyncOptionality);
	[sync apply];
	ORMRole *role = [[[editor.model objectTypeNamed:@"Person"] playedRoles] lastObject];
	XCTAssertTrue(role.isMandatory, @"%@", [[role factType] name]);
}

- (void)testAnAttributeAddedInCoreDataBecomesAFactType
{
	ORMEditor *editor = [self personModel];
	NSString *mapping = [self syncedMappingIn:editor];
	ORMCDModel *theirs = [self baselineOf:mapping in:editor];
	ORMCDAttribute *born = [[ORMCDAttribute alloc] init];
	born.name = @"birthDate";
	born.attributeType = @"Date";
	born.optional = NO;
	[[theirs entityNamed:@"Person"].attributes addObject:born];
	ORMCoreDataSync *sync = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:theirs];
	XCTAssertEqual([sync.changes.firstObject kind], ORMSyncAddAttribute);
	ORMCDModel *written = [sync apply];
	ORMObjectType *birthDate = [editor.model objectTypeNamed:@"BirthDate"];
	XCTAssertNotNil(birthDate);
	XCTAssertEqual(birthDate.dataType.family, ORMDataTypeTemporal);
	ORMCDAttribute *mapped = [[written entityNamed:@"Person"] attributeNamed:@"birthDate"];
	XCTAssertNotNil(mapped);
	XCTAssertFalse(mapped.optional);
	XCTAssertNotNil(mapped.source, @"traced to the new fact type");
	ORMCoreDataSync *next = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:written];
	XCTAssertEqual([next.changes count], (NSUInteger)0, @"%@", next.changes);
}

- (void)testAnEntityAndRelationshipAddedInCoreData
{
	ORMEditor *editor = [self personModel];
	NSString *mapping = [self syncedMappingIn:editor];
	ORMCDModel *theirs = [self baselineOf:mapping in:editor];
	ORMCDEntity *pet = [[ORMCDEntity alloc] init];
	pet.name = @"Pet";
	ORMCDAttribute *petName = [[ORMCDAttribute alloc] init];
	petName.name = @"nickname";
	petName.attributeType = @"String";
	petName.optional = YES;
	[pet.attributes addObject:petName];
	ORMCDRelationship *owner = [[ORMCDRelationship alloc] init];
	owner.name = @"owner";
	owner.destination = @"Person";
	owner.inverseName = @"pets";
	owner.optional = NO;
	[pet.relationships addObject:owner];
	ORMCDRelationship *pets = [[ORMCDRelationship alloc] init];
	pets.name = @"pets";
	pets.destination = @"Pet";
	pets.inverseName = @"owner";
	pets.toMany = YES;
	[[theirs entityNamed:@"Person"].relationships addObject:pets];
	[theirs.entities addObject:pet];
	ORMCoreDataSync *sync = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:theirs];
	ORMCDModel *written = [sync apply];
	XCTAssertNotNil([editor.model objectTypeNamed:@"Pet"]);
	ORMCDEntity *mappedPet = [written entityNamed:@"Pet"];
	XCTAssertNotNil([mappedPet attributeNamed:@"nickname"], @"%@", mappedPet);
	ORMCDRelationship *mappedOwner = [mappedPet relationshipNamed:@"owner"];
	XCTAssertFalse(mappedOwner.toMany);
	XCTAssertEqualObjects(mappedOwner.inverseName, @"pets");
	XCTAssertTrue([[[written entityNamed:@"Person"] relationshipNamed:@"pets"] toMany]);
	XCTAssertNil([self momcRejects:written]);
	ORMCoreDataSync *next = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:written];
	XCTAssertEqual([next.changes count], (NSUInteger)0, @"%@", next.changes);
}

- (void)testADeletionIsAnExclusionByDefault
{
	ORMEditor *editor = [self personModel];
	NSString *mapping = [self syncedMappingIn:editor];
	ORMCDModel *theirs = [self baselineOf:mapping in:editor];
	ORMCDEntity *person = [theirs entityNamed:@"Person"];
	[person.attributes removeObject:[person attributeNamed:@"name"]];
	ORMCoreDataSync *sync = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:theirs];
	XCTAssertEqual([sync.changes.firstObject kind], ORMSyncDeleteProperty);
	XCTAssertEqual([sync.changes.firstObject action], ORMSyncApplyToMapping);
	ORMCDModel *written = [sync apply];
	XCTAssertNil([[written entityNamed:@"Person"] attributeNamed:@"name"]);
	XCTAssertNotNil([editor.model objectTypeNamed:@"Name"], @"the ORM model keeps it");
}

- (void)testWhatOnlyCoreDataHasIsKept
{
	ORMEditor *editor = [self personModel];
	NSString *mapping = [self syncedMappingIn:editor];
	ORMCDModel *theirs = [self baselineOf:mapping in:editor];
	ORMCDEntity *person = [theirs entityNamed:@"Person"];
	person.representedClassName = @"MYPerson";
	[person attributeNamed:@"name"].defaultValue = @"Anonymous";
	[theirs.positions setObject:[NSValue valueWithRect:NSMakeRect(10, 20, 128, 80)] forKey:@"Person"];
	NSXMLElement *fetch = [[NSXMLElement alloc] initWithXMLString:@"<fetchRequest name=\"All\" entity=\"Person\"/>"
	                                                       error:NULL];
	theirs.extraElements = @[ fetch ];
	ORMCoreDataSync *sync = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:theirs];
	XCTAssertEqual([sync.changes count], (NSUInteger)0, @"%@", sync.changes);
	ORMCDModel *written = [sync apply];
	ORMCDEntity *merged = [written entityNamed:@"Person"];
	XCTAssertEqualObjects(merged.representedClassName, @"MYPerson");
	XCTAssertEqualObjects([merged attributeNamed:@"name"].defaultValue, @"Anonymous");
	XCTAssertNotNil([written.positions objectForKey:@"Person"]);
	XCTAssertEqual([written.extraElements count], (NSUInteger)1);
}

- (void)testAConflictKeepsTheORMSide
{
	ORMEditor *editor = [self personModel];
	NSString *mapping = [self syncedMappingIn:editor];
	ORMCDModel *theirs = [self baselineOf:mapping in:editor];
	[[theirs entityNamed:@"Person"] attributeNamed:@"name"].name = @"fullName";
	NSString *nameRole = [[[[editor.model objectTypeNamed:@"Name"] playedRoles] firstObject] identifier];
	[[self mappingsOf:editor] setName:@"label" forSource:nameRole inMapping:mapping];
	ORMCoreDataSync *sync = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:theirs];
	ORMSyncChange *change = sync.changes.firstObject;
	XCTAssertTrue(change.conflicts);
	XCTAssertEqual(change.action, ORMSyncDiscard);
	ORMCDModel *written = [sync apply];
	XCTAssertNotNil([[written entityNamed:@"Person"] attributeNamed:@"label"]);
}

- (void)testAModelMadeElsewhereIsAdopted
{
	ORMEditor *editor = [self personModel];
	NSString *mapping = [[self mappingsOf:editor] addCoreDataMappingNamed:@"App" path:@"App.xcdatamodeld"];
	/* The same model, written by hand: no traces, matched by name. */
	ORMCDModel *theirs = [[self map:editor.model] copy];
	for (ORMCDEntity *entity in theirs.entities) {
		[entity setSource:nil];
		for (ORMCDProperty *property in [entity properties]) {
			[property setSource:nil];
		}
	}
	ORMCDAttribute *extra = [[ORMCDAttribute alloc] init];
	extra.name = @"email";
	extra.attributeType = @"String";
	extra.optional = YES;
	[[theirs entityNamed:@"Person"].attributes addObject:extra];
	ORMCoreDataSync *sync = [[ORMCoreDataSync alloc] initWithEditor:editor mapping:mapping theirs:theirs];
	XCTAssertEqual([sync.changes count], (NSUInteger)1, @"%@", sync.changes);
	[sync apply];
	XCTAssertNotNil([editor.model objectTypeNamed:@"Email"]);
}

@end
