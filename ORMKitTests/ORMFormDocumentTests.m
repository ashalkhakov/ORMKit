/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <CoreData/CoreData.h>

/* A form generated as XForms (docs/FORMS.md): FORMS.md's RecordFillUp over
 * a fill-up model shaped as Logbook's is, its compound values absorbed. */
@interface ORMFormDocumentTests : ORMTestCase
@end

@implementation ORMFormDocumentTests

static NSString *const ORMFillUps = @"User is an entity type.\n"
                                    @"Reference Mode: .email\n"
                                    @"Vehicle is an entity type.\n"
                                    @"Reference Mode: .id\n"
                                    @"Portable data type: Other: Object ID\n"
                                    @"FillUp is an entity type.\n"
                                    @"Reference Mode: .id\n"
                                    @"Portable data type: Other: Object ID\n"
                                    @"Moment is a value type.\n"
                                    @"Portable data type: Temporal: Date & Time\n"
                                    @"Fuel is an entity type.\n"
                                    @"Reference Mode: .name\n"
                                    @"Station is an entity type.\n"
                                    @"Reference Mode: .name\n"
                                    @"Amount is a value type.\n"
                                    @"Portable data type: Numeric: Decimal(19, 4)\n"
                                    @"The possible values of Amount are above 0.\n"
                                    @"Currency is an entity type.\n"
                                    @"Reference Mode: .code\n"
                                    @"Portable data type: Text: Fixed Length(3)\n"
                                    @"The possible values of Currency are 'EUR', 'KZT', 'USD'.\n"
                                    @"Quantity is a value type.\n"
                                    @"Portable data type: Numeric: Decimal(15, 3)\n"
                                    @"The possible values of Quantity are at least 0.\n"
                                    @"DistanceUnit is an entity type.\n"
                                    @"Reference Mode: .code\n"
                                    @"The possible values of DistanceUnit are 'km', 'mi'.\n"
                                    @"VolumeUnit is an entity type.\n"
                                    @"Reference Mode: .code\n"
                                    @"The possible values of VolumeUnit are 'L', 'gal'.\n"
                                    @"Money is an entity type.\n"
                                    @"Money has Amount\n"
                                    @"Each Money has exactly one Amount.\n"
                                    @"Money is in Currency\n"
                                    @"Each Money is in exactly one Currency.\n"
                                    @"For each Amount and Currency, at most one Money has that Amount and is in that Currency.\n"
                                    @"This association with Amount and Currency provides the preferred identification scheme "
                                    @"for Money.\n"
                                    @"Distance is an entity type.\n"
                                    @"Distance has Quantity\n"
                                    @"Each Distance has exactly one Quantity.\n"
                                    @"Distance is in DistanceUnit\n"
                                    @"Each Distance is in exactly one DistanceUnit.\n"
                                    @"For each Quantity and DistanceUnit, at most one Distance has that Quantity and is in that "
                                    @"DistanceUnit.\n"
                                    @"This association with Quantity and DistanceUnit provides the preferred identification "
                                    @"scheme for Distance.\n"
                                    @"Volume is an entity type.\n"
                                    @"Volume has Quantity\n"
                                    @"Each Volume has exactly one Quantity.\n"
                                    @"Volume is in VolumeUnit\n"
                                    @"Each Volume is in exactly one VolumeUnit.\n"
                                    @"For each Quantity and VolumeUnit, at most one Volume has that Quantity and is in that "
                                    @"VolumeUnit.\n"
                                    @"This association with Quantity and VolumeUnit provides the preferred identification "
                                    @"scheme for Volume.\n"
                                    @"User drives Vehicle\n"
                                    @"In each population of User drives Vehicle, each User, Vehicle combination occurs at most "
                                    @"once.\n"
                                    @"FillUp is of Vehicle\n"
                                    @"Each FillUp is of exactly one Vehicle.\n"
                                    @"FillUp was at Moment (as Timestamp)\n"
                                    @"Each FillUp was at exactly one Moment.\n"
                                    @"FillUp was at Distance (as Mileage)\n"
                                    @"Each FillUp was at at most one Distance.\n"
                                    @"FillUp was of Volume\n"
                                    @"Each FillUp was of exactly one Volume.\n"
                                    @"FillUp was of Fuel\n"
                                    @"Each FillUp was of exactly one Fuel.\n"
                                    @"FillUp was at Station\n"
                                    @"Each FillUp was at at most one Station.\n"
                                    @"FillUp cost Money (as Total)\n"
                                    @"Each FillUp cost exactly one Money.\n"
                                    @"FillUp was charged Money (as Charged)\n"
                                    @"Each FillUp was charged at most one Money.\n"
                                    @"FillUp had driver User (as Driver)\n"
                                    @"Each FillUp had driver exactly one User.\n"
                                    @"FillUp filled the tank\n"
                                    @"If some FillUp was charged some Money then that FillUp was at some Station.\n"
                                    @"\n"
                                    @"Query RecordFillUp:\n"
                                    @"Form RecordFillUp:\n"
                                    @"FillUp\n"
                                    @"  + is of Vehicle1 = ?\n"
                                    @"  + was at ✎Moment\n"
                                    @"  + was at ✎Distance\n"
                                    @"  + was of ✎Volume\n"
                                    @"    + has Quantity\n"
                                    @"  + was of ✎Fuel\n"
                                    @"  + was at ✎Station\n"
                                    @"  + cost ✎Money1\n"
                                    @"    + has Amount\n"
                                    @"  + was charged ✎Money2\n"
                                    @"  + had driver ✎User\n"
                                    @"    + drives Vehicle1\n"
                                    @"  + filled the tank ✎\n"
                                    @"  ✓PricePerUnit = Amount / Quantity\n";

- (ORMEditor *)fillUps
{
	ORMEditor *editor = [self newEditor];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:ORMFillUps failures:&failures], @"%@",
	              failures);
	return editor;
}

- (ORMQuery *)formIn:(ORMModel *)model
{
	for (ORMQuery *query in [ORMQuery queriesInModel:model]) {
		if ([query.name isEqualToString:@"RecordFillUp"]) {
			return query;
		}
	}
	XCTFail(@"no RecordFillUp");
	return nil;
}

- (ORMFormDocument *)documentOf:(ORMEditor *)editor
{
	NSString *reason = nil;
	ORMFormDocument *document = [ORMFormDocument documentForForm:[self formIn:editor.model] model:editor.model mapping:nil
	                                                      reason:&reason];
	XCTAssertNotNil(document, @"%@", reason);
	return document;
}

/* The document element, the instance, a bind or a control by XPath. */
- (NSArray<NSXMLNode *> *)nodes:(NSString *)path in:(NSXMLDocument *)document
{
	NSError *error = nil;
	NSArray *nodes = [document nodesForXPath:path error:&error];
	XCTAssertNil(error, @"%@", path);
	return nodes ?: @[];
}

- (NSString *)attribute:(NSString *)name of:(NSXMLNode *)node
{
	return [[(NSXMLElement *)node attributeForName:name] stringValue];
}

/* Fmap: the anchor's own representation, named as the mapping names its
 * properties, a compound by its parts, a reference by its key. */
- (void)testTheInstanceIsTheEntitysOwn
{
	ORMFormDocument *form = [self documentOf:[self fillUps]];
	XCTAssertEqualObjects(form.entityName, @"FillUp");
	NSArray *names = @[
		@"id", @"vehicle", @"timestamp", @"mileageQuantity", @"mileageDistanceUnit", @"volumeQuantity",
		@"volumeVolumeUnit", @"fuel", @"station", @"totalAmount", @"totalCurrency", @"chargedAmount", @"chargedCurrency",
		@"driver", @"pricePerUnit", @"filledTheTank"
	];
	XCTAssertEqualObjects([form.fields valueForKey:@"elementName"], names);
	XCTAssertEqualObjects([form fieldNamed:@"timestamp"].schemaType, @"xsd:dateTime");
	XCTAssertEqualObjects([form fieldNamed:@"volumeQuantity"].schemaType, @"xsd:decimal");
	ORMFormField *vehicle = [form fieldNamed:@"vehicle"];
	XCTAssertEqual(vehicle.kind, ORMFormFieldReference);
	XCTAssertEqualObjects(vehicle.entityName, @"Vehicle");
	XCTAssertEqualObjects(vehicle.keyName, @"id");
	XCTAssertEqual([form fieldNamed:@"pricePerUnit"].kind, ORMFormFieldCalculated);
	NSXMLElement *instance = [form instanceGiven:@{ @"vehicle" : @"V1" }];
	XCTAssertEqualObjects([instance name], @"FillUp");
	XCTAssertEqualObjects([[[instance elementsForName:@"vehicle"] firstObject] stringValue], @"V1", @"given as it opens");
	XCTAssertEqualObjects([[[instance elementsForName:@"driver"] firstObject] stringValue], @"");
	XCTAssertEqual([form.notes count], 0u, @"%@", form.notes);
}

/* The driver is chosen from those who drive the vehicle: a query of its
 * own, its condition the step under the reference. */
- (void)testTheDriversChoicesDependOnTheVehicle
{
	ORMFormDocument *form = [self documentOf:[self fillUps]];
	XCTAssertEqualObjects([form choiceNames], (@[ @"fuel", @"station", @"driver" ]), @"units and currencies are lists");
	XCTAssertEqualObjects([form elementsChoicesDependOn:@"driver"], @[ @"vehicle" ]);
	ORMQueryPlan *any = [form choicesPlanNamed:@"driver" given:@{}];
	XCTAssertEqualObjects(any.entityName, @"User");
	XCTAssertTrue([[any text] rangeOfString:@"V1"].location == NSNotFound, @"%@", [any text]);
	ORMQueryPlan *theirs = [form choicesPlanNamed:@"driver" given:@{ @"vehicle" : @"V1" }];
	XCTAssertTrue([[theirs text] rangeOfString:@"V1"].location != NSNotFound, @"%@", [theirs text]);
	XCTAssertNil([form choicesPlanNamed:@"timestamp" given:@{}], @"no reference");
	ORMQueryPlan *read = [form readPlanForKey:@"F1"];
	XCTAssertEqualObjects(read.entityName, @"FillUp");
	XCTAssertTrue([[read text] rangeOfString:@"F1"].location != NSNotFound, @"%@", [read text]);
	XCTAssertTrue([[read text] rangeOfString:@"drives"].location == NSNotFound, @"the choices' condition is not the read's");
}

/* The binds say the constraints over the form's roles, each control's
 * alert their words; what the form cannot check is left to its submission. */
- (void)testTheBindsSayTheConstraints
{
	ORMFormDocument *form = [self documentOf:[self fillUps]];
	NSXMLDocument *document = [form document];
	NSString *bind = @"//*[local-name()='bind'][@ref='%@']";
	NSXMLNode *timestamp = [[self nodes:[NSString stringWithFormat:bind, @"timestamp"] in:document] firstObject];
	XCTAssertEqualObjects([self attribute:@"required" of:timestamp], @"true()");
	XCTAssertEqualObjects([self attribute:@"type" of:timestamp], @"xf:dateTime", @"XForms', which has empty a value");
	NSString *timestampAlert = [[[self nodes:[NSString stringWithFormat:@"//*[@bind='%@']/*[local-name()='alert']",
	                                                                   [self attribute:@"id" of:timestamp]]
	                                     in:document] firstObject] stringValue];
	XCTAssertTrue([timestampAlert rangeOfString:@"Each FillUp was at exactly one Moment."].location != NSNotFound, @"%@",
	              timestampAlert);
	/* A compound whole or not given; a value range. */
	NSXMLNode *mileage = [[self nodes:[NSString stringWithFormat:bind, @"mileageQuantity"] in:document] firstObject];
	XCTAssertEqualObjects([self attribute:@"required" of:mileage], @"(../mileageDistanceUnit != '')");
	XCTAssertTrue([[self attribute:@"constraint" of:mileage] rangeOfString:@"number(.) >= 0"].location != NSNotFound);
	/* The subset: charged only where there is a station. */
	NSXMLNode *charged = [[self nodes:[NSString stringWithFormat:bind, @"chargedAmount"] in:document] firstObject];
	XCTAssertEqualObjects([self attribute:@"relevant" of:charged], @"(not(../station = ''))");
	/* Calculated, from the compounds' parts. */
	NSXMLNode *price = [[self nodes:[NSString stringWithFormat:bind, @"pricePerUnit"] in:document] firstObject];
	XCTAssertTrue([[self attribute:@"calculate" of:price] rangeOfString:@"number(../totalAmount) div number(../volumeQuantity)"]
	                      .location != NSNotFound,
	              @"%@", [self attribute:@"calculate" of:price]);
	XCTAssertEqualObjects([self attribute:@"readonly" of:price], @"true()");
	/* The vehicle is given: read only, no control. */
	NSXMLNode *vehicle = [[self nodes:[NSString stringWithFormat:bind, @"vehicle"] in:document] firstObject];
	XCTAssertEqualObjects([self attribute:@"readonly" of:vehicle], @"true()");
	NSString *vehicleControls = [NSString stringWithFormat:@"//*[@bind='%@']", [self attribute:@"id" of:vehicle]];
	XCTAssertEqual([[self nodes:vehicleControls in:document] count], 0u);
	/* A unit from its list; the driver from its choices, read again as the
	 * vehicle changes. */
	XCTAssertEqual([[self nodes:@"//*[local-name()='select1'][*[local-name()='item']/*[local-name()='value']='mi']" in:document]
	                   count],
	               1u);
	XCTAssertEqual([[self nodes:@"//*[local-name()='select1']/*[local-name()='itemset'][@nodeset=\"instance('choices-driver')/*\"]"
	                         in:document] count],
	               1u);
	XCTAssertEqual([[self nodes:@"//*[local-name()='submission'][@resource='form:choices/driver']" in:document] count], 1u);
}

/* Well-formed XForms: XHTML around a model in the XForms namespace, the
 * instance in none. */
- (void)testTheDocumentIsXForms
{
	ORMFormDocument *form = [self documentOf:[self fillUps]];
	NSData *data = [[form document] XMLDataWithOptions:NSXMLNodePrettyPrint];
	NSError *error = nil;
	NSXMLDocument *read = [[NSXMLDocument alloc] initWithData:data options:0 error:&error];
	XCTAssertNotNil(read, @"%@", error);
	NSXMLElement *root = [read rootElement];
	XCTAssertEqualObjects([root URI], @"http://www.w3.org/1999/xhtml");
	NSArray *models = [self nodes:@"//*[local-name()='model']" in:read];
	XCTAssertEqual([models count], 1u);
	XCTAssertEqualObjects([(NSXMLElement *)[models firstObject] URI], @"http://www.w3.org/2002/xforms");
	NSXMLElement *instance = (NSXMLElement *)[[self nodes:@"//*[local-name()='instance'][@id='form']/*" in:read] firstObject];
	XCTAssertEqualObjects([instance localName], @"FillUp");
	XCTAssertEqual([[instance URI] length], 0u, @"%@", [instance URI]);
	XCTAssertEqual([[self nodes:@"//*[local-name()='bind']" in:read] count], [form.fields count]);
	for (NSString *resource in @[ @"form:read", @"form:save" ]) {
		NSString *path = [NSString stringWithFormat:@"//*[local-name()='submission'][@resource='%@']", resource];
		XCTAssertEqual([[self nodes:path in:read] count], 1u, @"%@", resource);
	}
	/* A new form's required fields are empty: its reads are not validated,
	 * its save is. */
	for (NSString *submission in @[ @"read", @"choices-driver", @"save" ]) {
		NSString *path = [NSString stringWithFormat:@"//*[local-name()='submission'][@id='%@']/@validate", submission];
		NSString *validate = [[[self nodes:path in:read] firstObject] stringValue];
		XCTAssertEqualObjects(validate, [submission isEqualToString:@"save"] ? nil : @"false", @"%@", submission);
	}
}

/* What ought to hold is XFormsKit's warning in the model: shown at its
 * element, in the rule's words, the form valid all the same. */
- (void)testAWarningIsXFormsKits
{
	ORMEditor *editor = [self fillUps];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor]
	                  addFromText:@"It is obligatory that each FillUp was at some Station.\n" failures:&failures], @"%@", failures);
	/* As a processor reads it: the document written and read again. */
	NSData *data = [[[self documentOf:editor] document] XMLDataWithOptions:NSXMLNodePrettyPrint];
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:0 error:NULL];
	NSArray *warnings = [self nodes:@"//*[local-name()='model']/*[local-name()='warning']" in:document];
	XCTAssertEqual([warnings count], 1u);
	NSXMLElement *warning = [warnings firstObject];
	XCTAssertEqualObjects([warning URI], @"urn:xformskit:extensions");
	XCTAssertEqualObjects([[warning attributeForName:@"ref"] stringValue], @"station");
	XCTAssertTrue([[warning stringValue] hasPrefix:@"It is obligatory that"], @"%@", [warning stringValue]);
	XCTAssertEqual([[self nodes:@"//*[local-name()='checks']/*[local-name()='warning']" in:document] count], 0u);
	NSString *required = [[[self nodes:@"//*[local-name()='bind'][@ref='station']/@required" in:document] firstObject] stringValue];
	XCTAssertNil(required, @"never required");
}

/* Ids come from the form's nodes: a renamed role renames its element, and
 * keeps its bind and control. */
- (void)testIdsSurviveARenamedRole
{
	ORMEditor *editor = [self fillUps];
	ORMFormDocument *before = [self documentOf:editor];
	ORMFormField *timestamp = [before fieldNamed:@"timestamp"];
	XCTAssertTrue([[[ORMElementEditor alloc] initWithEditor:editor] rename:timestamp.role.identifier to:@"FilledAt"
	                                                                reason:NULL]);
	ORMFormDocument *after = [self documentOf:editor];
	ORMFormField *renamed = [after fieldNamed:@"filledAt"];
	XCTAssertNotNil(renamed, @"%@", [after.fields valueForKey:@"elementName"]);
	XCTAssertEqualObjects([renamed fieldId], [timestamp fieldId]);
	NSString *control = [NSString stringWithFormat:@"//*[@id='control-%@']", [timestamp fieldId]];
	XCTAssertEqual([[self nodes:control in:[after document]] count], 1u);
}

- (void)testAQueryThatIsNoFormIsRefused
{
	ORMEditor *editor = [self fillUps];
	ORMQuery *form = [self formIn:editor.model];
	XCTAssertTrue([[[ORMQueryEditor alloc] initWithEditor:editor] setKind:ORMQueryList ofQuery:form.identifier reason:NULL]);
	NSString *reason = nil;
	XCTAssertNil([ORMFormDocument documentForForm:[self formIn:editor.model] model:editor.model mapping:nil reason:&reason]);
	XCTAssertEqualObjects(reason, @"It is no form.");
}

/* "+ filled the tank ✎": a unary step entered, a flag of the form's own,
 * written and read back as the outline says it. */
- (void)testAUnaryIsEntered
{
	ORMEditor *editor = [self fillUps];
	ORMQuery *query = [self formIn:editor.model];
	XCTAssertTrue([[query outlineText] rangeOfString:@"  + filled the tank ✎\n"].location != NSNotFound, @"%@",
	              [query outlineText]);
	ORMFormDocument *form = [self documentOf:editor];
	ORMFormField *full = [form.fields lastObject];
	XCTAssertEqualObjects(full.elementName, @"filledTheTank", @"the mapping's name");
	XCTAssertEqualObjects(full.schemaType, @"xsd:boolean");
	XCTAssertEqual(full.kind, ORMFormFieldValue);
	NSString *path = [NSString stringWithFormat:@"//*[local-name()='input'][@id='control-%@']/*[local-name()='label']",
	                                            [full fieldId]];
	XCTAssertEqualObjects([[[self nodes:path in:[form document]] firstObject] stringValue], @"filled the tank");
	XCTAssertNotNil([[form readPlan] columnOfNode:full.nodeId], @"read, not asked for: %@", [[form readPlan] text]);
	/* Only a unary's step is marked, and only in a form. */
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	NSString *reason = nil;
	ORMQueryStep *driver = nil;
	for (ORMQueryStep *step in query.root.steps) {
		driver = [step.factType isUnary] ? driver : step;
	}
	XCTAssertFalse([queries setFormPart:ORMFormPartEntered ofStep:driver.identifier reason:&reason]);
	XCTAssertEqualObjects(reason, @"Only a unary step is entered or shown itself: mark its nodes.");
	XCTAssertTrue([queries setKind:ORMQueryList ofQuery:query.identifier reason:NULL]);
	XCTAssertTrue([[[self formIn:editor.model] outlineText] rangeOfString:@"✎"].location == NSNotFound, @"a list has none");
}

/* A subtype's definition is asked of every one of it: the distance a
 * metered event is defined by is needed in a fill-up's form. */
- (void)testASubtypesDefinitionIsRequired
{
	ORMEditor *editor = [self newEditor];
	NSArray *failures = nil;
	NSString *text = @"Event is an entity type.\n"
	                 @"Reference Mode: .id\n"
	                 @"Portable data type: Other: Object ID\n"
	                 @"Quantity is a value type.\n"
	                 @"Portable data type: Numeric: Decimal(15, 3)\n"
	                 @"Note is a value type.\n"
	                 @"Portable data type: Text: Variable Length(100)\n"
	                 @"Event was at Quantity (as Mileage)\n"
	                 @"Each Event was at at most one Quantity.\n"
	                 @"Event has Note\n"
	                 @"Each Event has at most one Note.\n"
	                 @"MeteredEvent is an entity type.\n"
	                 @"Each MeteredEvent is by definition an Event that was at some Quantity.\n"
	                 @"FillUp is an entity type.\n"
	                 @"Each FillUp is a MeteredEvent.\n"
	                 @"\n"
	                 @"Query MeteredEventRule:\n"
	                 @"Derivation of MeteredEvent:\n"
	                 @"✓Event\n"
	                 @"  + was at Quantity\n"
	                 @"\n"
	                 @"Query Log:\n"
	                 @"Form Log:\n"
	                 @"FillUp\n"
	                 @"  + was at ✎Quantity\n"
	                 @"  + has ✎Note\n";
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMQuery *log = nil;
	for (ORMQuery *query in [ORMQuery queriesInModel:editor.model]) {
		log = query.kind == ORMQueryForm ? query : log;
	}
	NSString *reason = nil;
	ORMFormDocument *form = [ORMFormDocument documentForForm:log model:editor.model mapping:nil reason:&reason];
	XCTAssertNotNil(form, @"%@", reason);
	NSXMLDocument *document = [form document];
	NSXMLNode *mileage = [[self nodes:@"//*[local-name()='bind'][@ref='mileage']" in:document] firstObject];
	XCTAssertEqualObjects([self attribute:@"required" of:mileage], @"true()");
	NSString *alert = [[[self nodes:@"//*[@bind='bind-mileage' or @id='control-mileage']/*[local-name()='alert']" in:document]
	    firstObject] stringValue];
	XCTAssertTrue([alert rangeOfString:@"by definition"].location != NSNotFound, @"%@", alert);
	NSXMLNode *note = [[self nodes:@"//*[local-name()='bind'][@ref='note']" in:document] firstObject];
	XCTAssertNil([self attribute:@"required" of:note], @"not in the definition");
}

/* What an app runs: the read of the key, and the driver's choices for the
 * vehicle, take them as parameters; the table goes through a property list
 * and back. */
- (void)testTheReadAndChoicesTakeParameters
{
	ORMFormDocument *document = [self documentOf:[self fillUps]];
	XCTAssertEqualObjects([[document readPlan] parameterNames], @[ @"id" ], @"%@", [[document readPlan] text]);
	XCTAssertEqualObjects([[document choicesPlanNamed:@"driver"] parameterNames], @[ @"vehicle" ]);
	XCTAssertNil([document choicesPlanNamed:@"fuel"], @"depends on nothing");
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:[document tablePropertyList]
	                                                          format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
	XCTAssertNotNil(data);
	NSError *error = nil;
	ORMForm *form = [ORMForm formWithPropertyList:[NSPropertyListSerialization propertyListWithData:data options:0 format:NULL
	                                                                                           error:NULL]
	                                        error:&error];
	XCTAssertNotNil(form, @"%@", error);
	XCTAssertEqualObjects(form.keyElement, @"id");
	XCTAssertEqualObjects([form choiceNames], (@[ @"fuel", @"station", @"driver" ]));
	XCTAssertEqualObjects([form elementsChoicesDependOn:@"driver"], @[ @"vehicle" ]);
	XCTAssertEqual([[[form choicesPlanNamed:@"driver" values:@{} error:NULL] parameterNames] count], 0u, @"every one");
	ORMQueryPlan *theirs = [form choicesPlanNamed:@"driver" values:@{ @"vehicle" : @"7" } error:&error];
	XCTAssertTrue([[theirs text] rangeOfString:@"7"].location != NSNotFound, @"%@ %@", [theirs text], error);
	XCTAssertNil([form.readPlan planBinding:@{} error:&error], @"no key");
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"id"].location != NSNotFound, @"%@", error);
	XCTAssertFalse([form elementNamed:@"pricePerUnit"].written, @"computed");
	XCTAssertFalse([form elementNamed:@"id"].written, @"found by");
	XCTAssertTrue([form elementNamed:@"vehicle"].written, @"given");
	XCTAssertTrue([form elementNamed:@"driver"].written, @"entered");
}

static NSString *const ORMCarSeven = @"00000000-0000-4000-8000-000000000007";
static NSString *const ORMCarEight = @"00000000-0000-4000-8000-000000000008";

/* A store over the fill-up model, with a car, its drivers, and what a
 * fill-up refers to. */
- (NSManagedObjectContext *)storeOf:(ORMEditor *)editor
{
	NSManagedObjectModel *model = [[[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map] managedObjectModel];
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	NSError *error = nil;
	XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:&error],
	                @"%@", error);
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
	[context setPersistentStoreCoordinator:coordinator];
	NSDictionary *objects = @{
		@"Vehicle" : @[ ORMCarSeven, ORMCarEight ], @"User" : @[ @"ann@example.com", @"bob@example.com" ], @"Fuel" : @[ @"Diesel", @"Petrol" ],
		@"Station" : @[ @"Shell" ], @"Currency" : @[ @"KZT", @"EUR" ], @"DistanceUnit" : @[ @"km", @"mi" ],
		@"VolumeUnit" : @[ @"L", @"gal" ]
	};
	for (NSString *entityName in objects) {
		NSEntityDescription *entity = [[model entitiesByName] objectForKey:entityName];
		NSAttributeDescription *key = [[[entity attributesByName] allValues] firstObject];
		for (NSString *text in [objects objectForKey:entityName]) {
			NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:context];
			[object setValue:[key attributeType] == NSUUIDAttributeType ? (id)[[NSUUID alloc] initWithUUIDString:text] : text
			          forKey:[key name]];
		}
	}
	XCTAssertTrue([context save:&error], @"%@", error);
	/* Ann drives car 7; Bob drives car 8. */
	NSManagedObject *seven = [self object:@"Vehicle" key:ORMCarSeven in:context];
	NSManagedObject *eight = [self object:@"Vehicle" key:ORMCarEight in:context];
	[[[self object:@"User" key:@"ann@example.com" in:context] mutableSetValueForKey:@"vehicles"] addObject:seven];
	[[[self object:@"User" key:@"bob@example.com" in:context] mutableSetValueForKey:@"vehicles"] addObject:eight];
	XCTAssertTrue([context save:&error], @"%@", error);
	return context;
}

- (NSManagedObject *)object:(NSString *)entityName key:(NSString *)text in:(NSManagedObjectContext *)context
{
	NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:entityName];
	NSArray *objects = [context executeFetchRequest:request error:NULL];
	for (NSManagedObject *object in objects) {
		for (NSString *key in [[[object entity] attributesByName] allKeys]) {
			id value = [object valueForKey:key];
			if ([([value isKindOfClass:[NSUUID class]] ? [value UUIDString] : [value description]) isEqualToString:text]) {
				return object;
			}
		}
	}
	return nil;
}

/* A fill-up as the user enters it, for car 7. */
- (NSMutableDictionary<NSString *, NSString *> *)fillUpIn:(ORMForm *)form
{
	NSMutableDictionary *instance = [[form instanceGiven:@{ @"vehicle" : ORMCarSeven }] mutableCopy];
	[instance addEntriesFromDictionary:@{
		@"timestamp" : @"2026-11-10T08:30:00Z", @"mileageQuantity" : @"12345.5", @"mileageDistanceUnit" : @"km",
		@"volumeQuantity" : @"40.5", @"volumeVolumeUnit" : @"L", @"fuel" : @"Diesel", @"station" : @"Shell",
		@"totalAmount" : @"20250", @"totalCurrency" : @"KZT", @"driver" : @"ann@example.com", @"filledTheTank" : @"true"
	}];
	return instance;
}

/* The local store: the form opened on a new fill-up for a car, filled in
 * and saved, and read back into a fresh instance. */
- (void)testAFillUpIsSavedToTheStoreAndReadBack
{
	ORMEditor *editor = [self fillUps];
	ORMForm *form = [ORMForm formWithPropertyList:[[self documentOf:editor] tablePropertyList] error:NULL];
	NSManagedObjectContext *context = [self storeOf:editor];
	NSMutableDictionary *instance = [self fillUpIn:form];
	NSDictionary *errors = nil;
	NSError *error = nil;
	NSManagedObject *saved = [form save:instance inContext:context errors:&errors error:&error];
	XCTAssertNotNil(saved, @"%@ %@", errors, error);
	XCTAssertFalse([saved hasChanges], @"saved");
	NSString *key = [[saved valueForKey:@"id"] UUIDString];
	XCTAssertTrue([key length] > 0, @"given a key");
	NSDictionary *read = [form readKey:key inContext:context error:&error];
	XCTAssertNotNil(read, @"%@", error);
	for (NSString *name in instance) {
		if ([name length] > 0 && ![name isEqualToString:@"id"] && ![name isEqualToString:@"pricePerUnit"]) {
			XCTAssertEqualObjects([read objectForKey:name], [instance objectForKey:name], @"%@", name);
		}
	}
	XCTAssertEqualObjects([read objectForKey:@"id"], key);
	XCTAssertTrue([[read objectForKey:@"pricePerUnit"] hasPrefix:@"500"], @"computed where it is read: %@",
	              [read objectForKey:@"pricePerUnit"]);
	/* Changed and saved again: the same object. */
	NSMutableDictionary *changed = [read mutableCopy];
	[changed setObject:@"12400" forKey:@"mileageQuantity"];
	XCTAssertEqual([form save:changed inContext:context errors:&errors error:&error], saved);
	XCTAssertEqualObjects([[form readKey:key inContext:context error:NULL] objectForKey:@"mileageQuantity"], @"12400");
	/* The driver's choices: who drives that car; the fuels, every one. */
	XCTAssertEqualObjects([form choicesNamed:@"driver" values:changed inContext:context error:&error], @[ @"ann@example.com" ],
	                      @"%@", error);
	NSArray *fuels = [form choicesNamed:@"fuel" values:@{} inContext:context error:&error];
	XCTAssertEqualObjects([fuels sortedArrayUsingSelector:@selector(compare:)], (@[ @"Diesel", @"Petrol" ]));
	NSArray *drivers = [form choicesNamed:@"driver" values:@{} inContext:context error:&error];
	XCTAssertEqual([drivers count], 2u, @"no car chosen: any driver");
	/* A plan whose parameters have no values is not run. */
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[[context persistentStoreCoordinator] managedObjectModel]];
	XCTAssertNil([interpreter executePlan:form.readPlan inContext:context error:&error]);
	XCTAssertTrue([[error localizedDescription] rangeOfString:@"bind them first"].location != NSNotFound, @"%@", error);
}

/* Refused: said at the element, and the object as it was. */
- (void)testARefusalIsSaidAtItsElement
{
	ORMEditor *editor = [self fillUps];
	ORMForm *form = [ORMForm formWithPropertyList:[[self documentOf:editor] tablePropertyList] error:NULL];
	NSManagedObjectContext *context = [self storeOf:editor];
	NSMutableDictionary *instance = [self fillUpIn:form];
	[instance setObject:@"" forKey:@"timestamp"];
	NSDictionary *errors = nil;
	NSError *error = nil;
	XCTAssertNil([form save:instance inContext:context errors:&errors error:&error]);
	XCTAssertEqualObjects([errors allKeys], @[ @"timestamp" ], @"%@", errors);
	XCTAssertEqual([[context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"FillUp"] error:NULL] count], 0u,
	               @"nothing made");
	/* One the store does not have; one not of its type. */
	instance = [self fillUpIn:form];
	[instance setObject:@"nobody@example.com" forKey:@"driver"];
	[instance setObject:@"forty" forKey:@"volumeQuantity"];
	XCTAssertNil([form save:instance inContext:context errors:&errors error:&error]);
	XCTAssertEqualObjects([errors objectForKey:@"driver"], @"There is no User nobody@example.com.");
	XCTAssertEqualObjects([errors objectForKey:@"volumeQuantity"], @"Not a number.");
	/* An existing one changed and refused: as it was. */
	NSManagedObject *saved = [form save:[self fillUpIn:form] inContext:context errors:&errors error:&error];
	XCTAssertNotNil(saved, @"%@ %@", errors, error);
	NSDictionary *read = [form readKey:[[saved valueForKey:@"id"] UUIDString] inContext:context error:NULL];
	NSMutableDictionary *cleared = [read mutableCopy];
	[cleared setObject:@"" forKey:@"timestamp"];
	[cleared setObject:@"13000" forKey:@"mileageQuantity"];
	XCTAssertNil([form save:cleared inContext:context errors:&errors error:&error]);
	XCTAssertNotNil([errors objectForKey:@"timestamp"]);
	XCTAssertNotNil([saved valueForKey:@"timestamp"], @"put back");
	XCTAssertEqualObjects([[saved valueForKey:@"mileageQuantity"] description], @"12345.5");
	/* Saved as the app saves: its refusal said at the element, the object
	 * as it was. */
	NSError *rule = [NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationErrorMinimum
	                                userInfo:@{ NSValidationKeyErrorKey : @"station",
	                                            NSLocalizedDescriptionKey : @"Each FillUp was at some Station." }];
	NSMutableDictionary *moved = [read mutableCopy];
	[moved setObject:@"13000" forKey:@"mileageQuantity"];
	XCTAssertNil([form save:moved inContext:context saving:^BOOL(NSManagedObjectContext *saving, NSError **failure) {
		*failure = rule;
		return NO;
	} errors:&errors error:&error]);
	XCTAssertEqualObjects([errors allKeys], @[ @"station" ], @"%@", errors);
	XCTAssertEqualObjects([[saved valueForKey:@"mileageQuantity"] description], @"12345.5");
	XCTAssertNotNil([form save:moved inContext:context saving:^BOOL(NSManagedObjectContext *saving, NSError **failure) {
		return [saving save:failure];
	} errors:&errors error:&error], @"%@", errors);
	XCTAssertEqualObjects([[saved valueForKey:@"mileageQuantity"] description], @"13000");
}

/* The form's contract, whatever shows it: what each element is to whoever
 * opens the form, what it is called, and what the form is given. */
- (void)testTheContractSaysWhatEachElementIs
{
	ORMForm *form = [ORMForm formWithPropertyList:[[self documentOf:[self fillUps]] tablePropertyList] error:NULL];
	XCTAssertEqualObjects([form elementNamed:@"id"].role, @"key");
	XCTAssertEqualObjects([form elementNamed:@"vehicle"].role, @"given");
	XCTAssertTrue([form elementNamed:@"vehicle"].given);
	XCTAssertEqualObjects([form elementNamed:@"timestamp"].role, @"entered");
	XCTAssertEqualObjects([form elementNamed:@"driver"].role, @"entered");
	XCTAssertEqualObjects([form elementNamed:@"filledTheTank"].role, @"entered");
	XCTAssertEqualObjects([form elementNamed:@"pricePerUnit"].role, @"calculated");
	XCTAssertEqualObjects([form inputNames], @[ @"vehicle" ]);
	XCTAssertEqualObjects([form elementNamed:@"filledTheTank"].label, @"filled the tank", @"its reading");
	for (ORMFormElement *element in form.elements) {
		XCTAssertTrue([element.label length] > 0, @"%@ called something", element.name);
	}
	/* A table from before roles: what it writes entered, the rest shown. */
	NSMutableDictionary *old = [[form propertyList] mutableCopy];
	NSMutableArray *elements = [NSMutableArray array];
	for (NSDictionary *each in [old objectForKey:@"elements"]) {
		NSMutableDictionary *element = [each mutableCopy];
		[element removeObjectsForKeys:@[ @"role", @"given", @"label" ]];
		[elements addObject:element];
	}
	[old setObject:elements forKey:@"elements"];
	ORMForm *older = [ORMForm formWithPropertyList:old error:NULL];
	XCTAssertEqualObjects([older elementNamed:@"id"].role, @"key");
	XCTAssertEqualObjects([older elementNamed:@"timestamp"].role, @"entered");
	XCTAssertEqualObjects([older elementNamed:@"pricePerUnit"].role, @"calculated");
	XCTAssertEqualObjects([older elementNamed:@"timestamp"].label, @"timestamp");
}

/* A rule over several of the fill-up's properties is said at the one the
 * form enters, not at the vehicle it is given; one property's at it; one
 * the form cannot place, of the form. */
- (void)testARuleIsSaidWhereTheUserCanChangeIt
{
	ORMForm *form = [ORMForm formWithPropertyList:[[self documentOf:[self fillUps]] tablePropertyList] error:NULL];
	NSError *drives = [NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectValidationError
	                                  userInfo:@{ NSLocalizedDescriptionKey : @"That User drives that Vehicle.",
	                                              NSValidationKeyErrorKey : @"vehicle", @"ORMKeys" : @[ @"vehicle", @"driver" ] }];
	XCTAssertEqualObjects([form elementErrorsOf:drives], (@{ @"driver" : @"That User drives that Vehicle." }));
	NSError *missing = [NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationMissingMandatoryPropertyError
	                                   userInfo:@{ NSLocalizedDescriptionKey : @"Each FillUp was at some Moment.",
	                                               NSValidationKeyErrorKey : @"timestamp" }];
	XCTAssertEqualObjects([[form elementErrorsOf:missing] allKeys], @[ @"timestamp" ]);
	NSError *given = [NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectValidationError
	                                 userInfo:@{ NSLocalizedDescriptionKey : @"Each Vehicle is owned by some User.",
	                                             NSValidationKeyErrorKey : @"vehicle", @"ORMKeys" : @[ @"vehicle" ] }];
	XCTAssertEqualObjects([[form elementErrorsOf:given] allKeys], @[ @"" ], @"the vehicle is given: of the form");
}

/* A session over the store, as a view of the app's own runs the form:
 * opened with its inputs, its values set one by one, the driver's choices
 * those of the car given, refused at the element, saved, and read again. */
- (void)testASessionRunsTheFormOnTheStore
{
	ORMEditor *editor = [self fillUps];
	ORMForm *form = [ORMForm formWithPropertyList:[[self documentOf:editor] tablePropertyList] error:NULL];
	NSManagedObjectContext *context = [self storeOf:editor];
	ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form given:@{ @"vehicle" : ORMCarSeven }];
	[session useContext:context saving:nil];
	NSError *error = nil;
	XCTAssertTrue([session open:&error], @"%@", error);
	XCTAssertEqualObjects([session valueForElement:@"vehicle"], ORMCarSeven, @"given");
	XCTAssertEqualObjects([session valueForElement:@"driver"], @"");
	XCTAssertEqualObjects([session valueForElement:@"filledTheTank"], @"false", @"a flag not set is not so");
	XCTAssertEqualObjects([session choicesNamed:@"driver" error:&error], @[ @"ann@example.com" ], @"%@", error);
	NSDictionary *fillUp = [self fillUpIn:form];
	for (NSString *name in fillUp) {
		if ([name length] > 0 && ![name isEqualToString:@"vehicle"]) {
			[session setValue:[fillUp objectForKey:name] forElement:name];
		}
	}
	[session setValue:@"" forElement:@"timestamp"];
	XCTAssertFalse([session save:&error]);
	XCTAssertEqualObjects([session.errors allKeys], @[ @"timestamp" ], @"%@", session.errors);
	XCTAssertNil(session.savedKey);
	[session setValue:@"2026-11-10T08:30:00Z" forElement:@"timestamp"];
	XCTAssertTrue([session save:&error], @"%@ %@", session.errors, error);
	XCTAssertEqual([session.errors count], 0u);
	XCTAssertTrue([session.savedKey length] > 0, @"its result, the object's key");
	XCTAssertTrue([[session valueForElement:@"pricePerUnit"] hasPrefix:@"500"], @"read again: %@",
	              [session valueForElement:@"pricePerUnit"]);
	/* Opened on what it saved: the same values. */
	ORMFormSession *again = [[ORMFormSession alloc] initWithForm:form given:@{}];
	[again useContext:context saving:nil];
	again.key = session.savedKey;
	XCTAssertTrue([again open:&error], @"%@", error);
	XCTAssertEqualObjects([again valueForElement:@"mileageQuantity"], @"12345.5");
	XCTAssertEqualObjects([again valueForElement:@"driver"], @"ann@example.com");
}

/* The service: the instance sent as OData, its names the service's; a
 * refusal's details said at their elements. */
- (void)testTheServiceIsSentTheInstance
{
	ORMEditor *editor = [self fillUps];
	ORMForm *form = [ORMForm formWithPropertyList:[[self documentOf:editor] tablePropertyList] error:NULL];
	NSManagedObjectModel *model = [[[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map] managedObjectModel];
	NSMutableDictionary *instance = [self fillUpIn:form];
	NSError *error = nil;
	ORMFormRequest *post = [form saveRequestFor:instance original:nil etag:nil model:model error:&error];
	XCTAssertNotNil(post, @"%@", error);
	XCTAssertEqualObjects(post.method, @"POST");
	XCTAssertEqualObjects(post.path, @"FillUps");
	XCTAssertEqualObjects([post.body objectForKey:@"Timestamp"], @"2026-11-10T08:30:00Z");
	XCTAssertEqualObjects([[post.body objectForKey:@"MileageQuantity"] description], @"12345.5");
	XCTAssertEqualObjects([post.body objectForKey:@"FilledTheTank"], @YES);
	XCTAssertEqualObjects([post.body objectForKey:@"Driver@odata.bind"], @"Users('ann@example.com')");
	XCTAssertEqualObjects([post.body objectForKey:@"Vehicle@odata.bind"], ([NSString stringWithFormat:@"Vehicles(%@)", ORMCarSeven]));
	XCTAssertEqualObjects([post.body objectForKey:@"TotalCurrency@odata.bind"], @"Currencies('KZT')");
	XCTAssertNil([post.body objectForKey:@"ChargedAmount"], @"none given");
	XCTAssertNil([post.body objectForKey:@"PricePerUnit"], @"computed");
	XCTAssertNotNil([NSJSONSerialization JSONObjectWithData:[post bodyData] options:0 error:NULL]);
	/* Changed: what differs, with the ETag it was read with. */
	NSString *key = @"00000000-0000-4000-8000-000000000041";
	[instance setObject:key forKey:@"id"];
	NSMutableDictionary *changed = [instance mutableCopy];
	[changed setObject:@"12400" forKey:@"mileageQuantity"];
	[changed setObject:@"bob@example.com" forKey:@"driver"];
	[changed setObject:@"" forKey:@"station"];
	ORMFormRequest *patch = [form saveRequestFor:changed original:instance etag:@"W/\"3\"" model:model error:&error];
	XCTAssertEqualObjects(patch.method, @"PATCH");
	XCTAssertEqualObjects(patch.path, ([NSString stringWithFormat:@"FillUps(%@)", key]));
	XCTAssertEqualObjects([patch.headers objectForKey:@"If-Match"], @"W/\"3\"");
	XCTAssertEqualObjects([[patch.body allKeys] sortedArrayUsingSelector:@selector(compare:)],
	                      (@[ @"Driver@odata.bind", @"MileageQuantity", @"Station@odata.bind" ]));
	XCTAssertEqualObjects([patch.body objectForKey:@"Station@odata.bind"], [NSNull null], @"emptied");
	[changed setObject:@"forty" forKey:@"volumeQuantity"];
	XCTAssertNil([form saveRequestFor:changed original:instance etag:nil model:model error:&error]);
	XCTAssertEqualObjects([error localizedDescription], @"Not a number.");
	/* Refused: each detail at its element, by its name on the wire. */
	NSData *refusal = [@"{\"error\":{\"code\":\"400\",\"message\":\"The fill-up is refused.\",\"details\":["
	                   @"{\"code\":\"1570\",\"message\":\"A value is required.\",\"target\":\"Timestamp\"},"
	                   @"{\"code\":\"rule\",\"message\":\"The meter goes up.\"}]}}" dataUsingEncoding:NSUTF8StringEncoding];
	XCTAssertEqualObjects([form elementErrorsOfResponse:refusal model:model],
	                      (@{ @"timestamp" : @"A value is required.", @"" : @"The meter goes up." }));
	XCTAssertEqualObjects([form elementErrorsOfResponse:[@"{\"error\":{\"message\":\"No.\"}}" dataUsingEncoding:NSUTF8StringEncoding]
	                                              model:model],
	                      @{ @"" : @"No." });
}

@end
