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
	ORMCoreDataMapping *mapping = [editor.model coreDataMappingWithId:mappingId];
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
 * visit by who and where) gets a UUID whoever makes it gives it: a client
 * offline, too, and before the service has seen it. */
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
	XCTAssertEqualObjects(key.attributeType, @"UUID");
	XCTAssertFalse(key.optional);
	XCTAssertEqualObjects([key.userInfo objectForKey:@"ormkit.surrogate"], @"YES");
	XCTAssertNil([key.userInfo objectForKey:@"OData.computed"], @"a client gives it, and sends it");
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

/* A surrogate read back from the Core Data model is no fact of what it
 * keys, and maps again as it was: the same UUID key. */
- (void)testASurrogateComesBackAsASurrogate
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *married = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, person ] reading:@"{0} married {1}"
	                                                onDiagram:nil at:NSZeroPoint reason:NULL];
	[editor.factTypeEditor objectifyFactType:married named:@"Marriage" reason:NULL];
	ORMCDModel *mapped = [self map:editor serving:YES notes:NULL];

	ORMEditor *imported = [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:@"Imported"] undoManager:nil];
	NSString *reason = nil;
	NSString *mapping = [[[ORMCoreDataImporter alloc] initWithEditor:imported] importCoreDataModel:mapped
	                                                                                           path:@"/tmp/Marriage.xcdatamodeld"
	                                                                                          notes:NULL
	                                                                                         reason:&reason];
	XCTAssertNotNil(mapping, @"%@", reason);
	ORMObjectType *marriage = [imported.model objectTypeNamed:@"Marriage"];
	XCTAssertNotNil(marriage);
	/* Its people relate to it; no value is said of it, as one would be of
	 * a surrogate read as data. */
	for (ORMFactType *fact in imported.model.factTypes) {
		BOOL playsIt = NO, valued = NO;
		for (ORMRole *role in fact.roles) {
			playsIt = playsIt || role.player == marriage;
			valued = valued || role.player.kind == ORMValueType;
		}
		XCTAssertFalse(playsIt && valued, @"the surrogate made a fact of Marriage: %@", fact.name);
	}
	ORMCoreDataMapping *read = [imported.model coreDataMappingWithId:mapping];
	ORMCDModel *again = [[[ORMCoreDataMapper alloc] initWithModel:imported.model mapping:read] map];
	ORMCDAttribute *key = [[again entityNamed:@"Marriage"] attributeNamed:@"id"];
	XCTAssertEqualObjects(key.attributeType, @"UUID");
	XCTAssertEqualObjects([key.userInfo objectForKey:@"ormkit.surrogate"], @"YES");
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

	/* A bound written ".5" is JSON's 0.5: the annotations read as JSON. */
	NSString *share = [self value:@"Share" type:@"DecimalNumericDataType" in:editor];
	NSString *reason = nil;
	XCTAssertTrue([editor.objectTypeEditor setValueConstraint:@"{(.5..1]}" of:share reason:&reason], @"%@", reason);
	[self has:person value:share in:editor];
	entity = [[self map:editor serving:YES notes:NULL] entityNamed:@"Person"];
	NSString *text = [[[entity attributeNamed:@"share"] userInfo] objectForKey:@"OData.annotations"];
	XCTAssertEqualObjects(text, @"{\"Validation.Minimum\": 0.5, \"Validation.Minimum@Validation.Exclusive\": true}");
	XCTAssertNotNil([NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL],
	                @"%@", text);
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

/* Mapped with offline sync: every entity both ways but those said
 * otherwise. */
- (ORMCDModel *)mapSyncing:(ORMEditor *)editor down:(NSString *)downId notes:(NSArray<ORMMappingNote *> **)notes
{
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:editor];
	NSString *mappingId = [mappings addCoreDataMappingNamed:@"Test" path:@"Test.xcdatamodeld"];
	[mappings setSyncDirection:ORMSyncBoth ofMapping:mappingId];
	[mappings setSyncConflicts:@"lastWriter" ofMapping:mappingId];
	[mappings setSyncDirection:@(ORMSyncDown) conflicts:nil ofSource:downId inMapping:mappingId];
	ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:editor.model
	                                                             mapping:[editor.model coreDataMappingWithId:mappingId]];
	ORMCDModel *mapped = [mapper map];
	if (notes != NULL) {
		*notes = mapper.notes;
	}
	return mapped;
}

/* Each root entity says which way it goes, a subentity its root's; what a
 * device changes keeps its history in bookkeeping the conceptual model
 * says nothing of, and its key after deletion. */
- (void)testEntitiesSyncAsTheMappingSays
{
	ORMEditor *editor = [self newEditor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *employee = [self entity:@"Employee" mode:nil in:editor];
	[editor.objectTypeEditor addSubtype:employee of:person reason:NULL];
	NSString *lives = [editor.factTypeEditor addFactTypeWithPlayers:@[ person, country ] reading:@"{0} lives in {1}"
	                                              onDiagram:nil at:NSZeroPoint reason:NULL];
	[editor.constraintEditor setUnique:YES role:[[[[editor.model elementWithId:lives] roles] firstObject] identifier]
	                            reason:NULL];
	NSArray<ORMMappingNote *> *notes = nil;
	ORMCDModel *mapped = [self mapSyncing:editor down:country notes:&notes];

	ORMCDEntity *people = [mapped entityNamed:@"Person"];
	XCTAssertEqualObjects([people.userInfo objectForKey:@"ODataSync.direction"], @"both");
	XCTAssertEqualObjects([people.userInfo objectForKey:@"ODataSync.conflicts"], @"lastWriter");
	XCTAssertEqualObjects([people.userInfo objectForKey:@"ODataSync.versions"], @"syncVersions");
	XCTAssertEqualObjects([people.userInfo objectForKey:@"ODataSync.modified"], @"syncModified");
	for (NSString *name in @[ @"syncVersions", @"syncModified" ]) {
		ORMCDAttribute *bookkeeping = [people attributeNamed:name];
		XCTAssertEqualObjects(bookkeeping.attributeType, @"String");
		XCTAssertTrue(bookkeeping.optional);
		XCTAssertEqualObjects([bookkeeping.userInfo objectForKey:@"ormkit.bookkeeping"], @"YES");
		XCTAssertEqualObjects(bookkeeping.source, ([person stringByAppendingFormat:@".%@", name]));
	}
	XCTAssertEqualObjects([[[people attributeNamed:@"id"] extraAttributes] objectForKey:@"preserveAfterDeletion"], @"YES");
	ORMCDEntity *employees = [mapped entityNamed:@"Employee"];
	XCTAssertEqualObjects(employees.parentName, @"Person");
	XCTAssertNil([employees.userInfo objectForKey:@"ODataSync.direction"], @"a subentity goes its root's way");
	XCTAssertNil([employees attributeNamed:@"syncVersions"]);

	ORMCDEntity *countries = [mapped entityNamed:@"Country"];
	XCTAssertEqualObjects([countries.userInfo objectForKey:@"ODataSync.direction"], @"down");
	XCTAssertNil([countries.userInfo objectForKey:@"ODataSync.conflicts"], @"the service's: no conflict");
	XCTAssertNil([countries.userInfo objectForKey:@"ODataSync.versions"]);
	XCTAssertNil([countries attributeNamed:@"syncVersions"]);
	XCTAssertNil([[[countries attributeNamed:@"code"] extraAttributes] objectForKey:@"preserveAfterDeletion"]);
	BOOL noted = NO;
	for (ORMMappingNote *note in notes) {
		noted = noted || [note.text rangeOfString:@"down: Country; both: Person"].location != NSNotFound;
	}
	XCTAssertTrue(noted, @"%@", notes);
	XCTAssertNil([self momcRejects:mapped]);
}

/* A bookkeeping attribute does not take a name the model's own has, and
 * is renamed as any property is. */
- (void)testBookkeepingTakesNoNameOfTheModel
{
	ORMEditor *editor = [self newEditor];
	NSString *person = [self entity:@"Person" mode:@"id" in:editor];
	NSString *stamp = [self value:@"SyncModified" type:@"VariableLengthTextDataType" in:editor];
	[self has:person value:stamp in:editor];
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:editor];
	NSString *mappingId = [mappings addCoreDataMappingNamed:@"Test" path:@"Test.xcdatamodeld"];
	[mappings setSyncDirection:ORMSyncUp ofMapping:mappingId];
	[mappings setName:@"history" forSource:[person stringByAppendingString:@".syncVersions"] inMapping:mappingId];
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:editor.model
	                                                       mapping:[editor.model coreDataMappingWithId:mappingId]] map];
	ORMCDEntity *people = [mapped entityNamed:@"Person"];
	XCTAssertEqualObjects([people.userInfo objectForKey:@"ODataSync.direction"], @"up");
	XCTAssertEqualObjects([people.userInfo objectForKey:@"ODataSync.versions"], @"history");
	XCTAssertEqualObjects([people.userInfo objectForKey:@"ODataSync.modified"], @"syncModified2");
	XCTAssertNil([[people attributeNamed:@"syncModified"].userInfo objectForKey:@"ormkit.bookkeeping"], @"the model's own");
}

/* The options are the document's: written into the mapping's element,
 * read back the same, and undone as any change. */
- (void)testSyncOptionsAreKeptInTheDocument
{
	ORMEditor *editor = [self newEditor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	ORMMappingEditor *mappings = [[ORMMappingEditor alloc] initWithEditor:editor];
	NSString *mappingId = [mappings addCoreDataMappingNamed:@"Test" path:@"Test.xcdatamodeld"];
	[mappings setSyncDirection:ORMSyncBoth ofMapping:mappingId];
	[mappings setSyncConflicts:@"merge" ofMapping:mappingId];
	[mappings setSyncDirection:@(ORMSyncDown) conflicts:nil ofSource:country inMapping:mappingId];
	NSXMLElement *element = [[editor.model coreDataMappingWithId:mappingId] element];
	XCTAssertEqualObjects([[element attributeForName:@"Sync"] stringValue], @"Both");
	XCTAssertEqualObjects([[element attributeForName:@"SyncConflicts"] stringValue], @"merge");

	NSXMLDocument *saved = ORMParseDocument([editor dataForSaving], NULL);
	ORMModel *read = [ORMModel modelOfDocument:saved reason:NULL];
	ORMCoreDataMapping *mapping = [read coreDataMappingWithId:mappingId];
	XCTAssertEqual(mapping.syncDirection, ORMSyncBoth);
	XCTAssertEqualObjects(mapping.syncConflicts, @"merge");
	XCTAssertEqual([mapping syncDirectionOf:country], ORMSyncDown);
	XCTAssertEqual([mapping syncDirectionOf:@"_another"], ORMSyncBoth);
	XCTAssertEqualObjects([mapping syncConflictsOf:country], @"merge");

	[mappings setSyncDirection:nil conflicts:nil ofSource:country inMapping:mappingId];
	XCTAssertEqual([[editor.model coreDataMappingWithId:mappingId] syncDirectionOf:country], ORMSyncBoth);
	[self.undoManager undo];
	XCTAssertEqual([[editor.model coreDataMappingWithId:mappingId] syncDirectionOf:country], ORMSyncDown);
	[mappings setSyncDirection:ORMSyncNone ofMapping:mappingId];
	XCTAssertNil([element attributeForName:@"Sync"], @"none is said by saying nothing");
}

/* Bookkeeping read back from the Core Data model is no fact; the way each
 * entity goes is the mapping's again. */
- (void)testBookkeepingComesBackAsTheMappings
{
	ORMEditor *editor = [self newEditor];
	NSString *country = [self entity:@"Country" mode:@"code" in:editor];
	[self entity:@"Person" mode:@"id" in:editor];
	ORMCDModel *mapped = [self mapSyncing:editor down:country notes:NULL];

	ORMEditor *imported = [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:@"Imported"] undoManager:nil];
	NSString *reason = nil;
	NSString *mappingId = [[[ORMCoreDataImporter alloc] initWithEditor:imported] importCoreDataModel:mapped
	                                                                                             path:@"/tmp/Sync.xcdatamodeld"
	                                                                                            notes:NULL
	                                                                                           reason:&reason];
	XCTAssertNotNil(mappingId, @"%@", reason);
	for (ORMObjectType *type in imported.model.objectTypes) {
		XCTAssertFalse([type.name rangeOfString:@"Sync" options:NSCaseInsensitiveSearch].location != NSNotFound,
		               @"bookkeeping made a fact: %@", type.name);
	}
	ORMCoreDataMapping *mapping = [imported.model coreDataMappingWithId:mappingId];
	ORMCDModel *again = [[[ORMCoreDataMapper alloc] initWithModel:imported.model mapping:mapping] map];
	XCTAssertEqualObjects([[again entityNamed:@"Country"].userInfo objectForKey:@"ODataSync.direction"], @"down");
	XCTAssertEqualObjects([[again entityNamed:@"Person"].userInfo objectForKey:@"ODataSync.direction"], @"both");
	XCTAssertEqualObjects([[again entityNamed:@"Person"].userInfo objectForKey:@"ODataSync.conflicts"], @"lastWriter");
	XCTAssertNotNil([[again entityNamed:@"Person"] attributeNamed:@"syncVersions"]);
}

/* Without a direction, nothing is said of sync. */
- (void)testAMappingNotSyncedSaysNothingOfSync
{
	ORMEditor *editor = [self newEditor];
	[self entity:@"Person" mode:@"id" in:editor];
	ORMCDEntity *people = [[self map:editor serving:YES notes:NULL] entityNamed:@"Person"];
	for (NSString *key in people.userInfo) {
		XCTAssertFalse([key hasPrefix:@"ODataSync."], @"%@", key);
	}
	XCTAssertNil([people attributeNamed:@"syncVersions"]);
}

@end
