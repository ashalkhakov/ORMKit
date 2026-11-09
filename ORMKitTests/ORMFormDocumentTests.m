/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

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
		@"driver", @"pricePerUnit"
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
	XCTAssertEqualObjects([self attribute:@"type" of:timestamp], @"xsd:dateTime");
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

@end
