/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"
#import <CoreData/CoreData.h>
#import <ODataService/ODataService.h>

/* A service's action a form submits to: the goods received, a procedure
 * of the service's, given the order as the form has it. */
@protocol ORMTestReceivingActions <ODataActions>
- (NSString *)receiveGoodsWithPurchaseOrder:(NSDictionary *)purchaseOrder reply:(ODataReply *)reply;
@end

@interface ORMTestReceiving : NSObject <ORMTestReceivingActions>
@property (atomic, strong) NSDictionary *received;
@end

@implementation ORMTestReceiving
- (NSString *)receiveGoodsWithPurchaseOrder:(NSDictionary *)purchaseOrder reply:(ODataReply *)reply
{
	(void)reply;
	self.received = purchaseOrder;
	return [[purchaseOrder objectForKey:@"Number"] description];
}
@end

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
                                    @"  + was at Moment (entered)\n"
                                    @"  + was at Distance (entered)\n"
                                    @"  + was of Volume (entered)\n"
                                    @"    + has Quantity\n"
                                    @"  + was of Fuel (entered)\n"
                                    @"  + was at Station (entered)\n"
                                    @"  + cost Money1 (entered)\n"
                                    @"    + has Amount\n"
                                    @"  + was charged Money2 (entered)\n"
                                    @"  + had driver User (entered)\n"
                                    @"    + drives Vehicle1\n"
                                    @"  + filled the tank (entered)\n"
                                    @"  PricePerUnit = Amount / Quantity (shown)\n";

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
	XCTAssertEqualObjects(document.missing, @[], @"every form here is whole: %@", document.notes);
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

/* "+ filled the tank (entered)": a unary step entered, a flag of the form's own,
 * written and read back as the outline says it. */
- (void)testAUnaryIsEntered
{
	ORMEditor *editor = [self fillUps];
	ORMQuery *query = [self formIn:editor.model];
	XCTAssertTrue([[query outlineText] rangeOfString:@"  + filled the tank (entered)\n"].location != NSNotFound, @"%@",
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
	XCTAssertTrue([[[self formIn:editor.model] outlineText] rangeOfString:@"(entered)"].location == NSNotFound, @"a list has none");
	/* A step's marks say it is entered or shown, never sorted. */
	XCTAssertNil([[[ORMOutlineReader alloc] initWithEditor:editor] addQueryNamed:nil
	                                                                      outline:@"Form Sorted:\nFillUp\n  + filled the tank (descending)\n"
	                                                                       reason:&reason]);
	XCTAssertEqualObjects(reason, @"Line 3, \"+ filled the tank (descending)\": a step is not sorted; its nodes are");
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
	                 @"Event (shown)\n"
	                 @"  + was at Quantity\n"
	                 @"\n"
	                 @"Query Log:\n"
	                 @"Form Log:\n"
	                 @"FillUp\n"
	                 @"  + was at Quantity (entered)\n"
	                 @"  + has Note (entered)\n";
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

/* What the model has in a form and the document cannot place is said as
 * missing, by name: never a form quietly without it (ormtool xforms
 * refuses to write one). Here a driver's vehicles entered, rows that are
 * facts of "drives", not objects linked to one owner. */
- (void)testWhatCannotBePlacedIsMissingNotDropped
{
	ORMEditor *editor = nil;
	ORMFormDefinition *definition = [self definitionOf:@"Drives" outline:@"User\n  + drives Vehicle (entered)\n" editor:&editor];
	XCTAssertEqualObjects([definition.problems valueForKey:@"text"], @[], @"well formed: rows of choices (D8)");
	NSString *reason = nil;
	ORMFormDocument *document = [ORMFormDocument documentForForm:definition.form model:editor.model mapping:nil reason:&reason];
	XCTAssertNotNil(document, @"%@", reason);
	XCTAssertEqualObjects(document.missing, (@[ @"vehicles: rows entered that are not each of one User, but facts of many: not written by a repeat." ]),
	                      @"(notes: %@)", document.notes);
}

/* A list beneath what the form refers to (D9): the fill-up's driver's
 * vehicles, read with the fill-up, never written. */
- (void)testAListBeneathAReferenceIsRead
{
	NSString *text = [ORMFillUps stringByReplacingOccurrencesOfString:@"  PricePerUnit ="
	                                                       withString:@"  + had driver User2\n    + drives Vehicle3 (shown)\n  PricePerUnit ="];
	ORMEditor *editor = [self editorOf:text];
	ORMFormDocument *document = [self form:@"RecordFillUp" of:editor];
	NSString *name = [[document.repeats allKeys] firstObject];
	XCTAssertEqual([document.repeats count], 1u, @"%@ %@", document.repeats, document.notes);
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	ORMForm *list = [form repeatNamed:name];
	XCTAssertTrue(list.isList, @"read only");
	NSManagedObjectContext *context = [self contextOf:editor];
	NSManagedObject *van = [self insert:@"Vehicle" values:@{ @"id" : [NSUUID UUID] } in:context];
	NSManagedObject *car = [self insert:@"Vehicle" values:@{ @"id" : [NSUUID UUID] } in:context];
	NSManagedObject *ann = [self insert:@"User" values:@{ @"email" : @"ann@example.com" } in:context];
	for (NSString *key in [[[ann entity] relationshipsByName] allKeys]) {
		if ([[[[[ann entity] relationshipsByName] objectForKey:key] destinationEntity].name isEqualToString:@"Vehicle"]) {
			[ann setValue:[NSSet setWithObjects:van, car, nil] forKey:key];
		}
	}
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	XCTAssertEqualObjects([form repeatFrom:name], @"driver", @"read for the driver's key");
	NSArray *rows = [list rowsLinkedTo:@"ann@example.com" inContext:context error:&error];
	XCTAssertEqual([rows count], 2u, @"the driver's two: %@ %@", rows, error);
	XCTAssertEqualObjects([[form instanceGiven:@{}] objectForKey:name], @[], @"none before a driver");
}

/* What is computed with read through a second step to an object absorbed
 * into the anchor's row (Logbook's price per unit: the volume entered, its
 * quantity reached again): read with the row, no maybe of its own. */
- (void)testAValueComputedThroughAnAbsorbedObjectAgainIsRead
{
	NSString *text = [ORMFillUps stringByReplacingOccurrencesOfString:@"  + was of Volume (entered)\n    + has Quantity\n"
	                                                       withString:@"  + was of Volume1 (entered)\n"];
	text = [text stringByReplacingOccurrencesOfString:@"  PricePerUnit ="
	                                       withString:@"  + was of Volume2\n    + has Quantity\n  PricePerUnit ="];
	XCTAssertNotEqualObjects(text, ORMFillUps);
	ORMEditor *editor = [self newEditor];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	ORMFormDocument *document = [self documentOf:editor];
	XCTAssertFalse([[document.notes componentsJoinedByString:@"\n"] containsString:@"places it nowhere"], @"%@", document.notes);
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	NSManagedObjectContext *context = [self storeOf:editor];
	NSDictionary *errors = nil;
	NSError *error = nil;
	NSManagedObject *saved = [form save:[self fillUpIn:form] inContext:context errors:&errors error:&error];
	XCTAssertNotNil(saved, @"%@ %@", errors, error);
	NSDictionary *read = [form readKey:[[saved valueForKey:@"id"] UUIDString] inContext:context error:&error];
	XCTAssertTrue([[read objectForKey:@"pricePerUnit"] hasPrefix:@"500"], @"%@ %@", read, error);
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

#pragma mark Repeats

static NSString *const ORMOrders = @"PurchaseOrder is an entity type.\n"
                                   @"Reference Mode: .number\n"
                                   @"PurchaseLine is an entity type.\n"
                                   @"Reference Mode: .id\n"
                                   @"Portable data type: Other: Object ID\n"
                                   @"StockItem is an entity type.\n"
                                   @"Reference Mode: .sku\n"
                                   @"Quantity is a value type.\n"
                                   @"Portable data type: Numeric: Decimal(19, 4)\n"
                                   @"Day is a value type.\n"
                                   @"Portable data type: Temporal: Date\n"
                                   @"PurchaseOrder was placed on Day\n"
                                   @"Each PurchaseOrder was placed on at most one Day.\n"
                                   @"PurchaseLine is in PurchaseOrder\n"
                                   @"Each PurchaseLine is in exactly one PurchaseOrder.\n"
                                   @"PurchaseLine is of StockItem\n"
                                   @"Each PurchaseLine is of exactly one StockItem.\n"
                                   @"PurchaseLine wants Quantity\n"
                                   @"Each PurchaseLine wants at most one Quantity.\n"
                                   @"\n"
                                   @"Query ReceiveGoods:\n"
                                   @"Form ReceiveGoods:\n"
                                   @"PurchaseOrder\n"
                                   @"  + was placed on Day (shown)\n"
                                   @"  + PurchaseLine is in that PurchaseOrder\n"
                                   @"    + is of StockItem (entered)\n"
                                   @"    + wants Quantity (entered)\n";

- (ORMEditor *)orders
{
	ORMEditor *editor = [self newEditor];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:ORMOrders failures:&failures], @"%@", failures);
	return editor;
}

- (ORMFormDocument *)receiveGoodsOf:(ORMEditor *)editor
{
	ORMQuery *form = nil;
	for (ORMQuery *query in [ORMQuery queriesInModel:editor.model]) {
		if ([query.name isEqualToString:@"ReceiveGoods"]) {
			form = query;
		}
	}
	XCTAssertNotNil(form, @"%@", [[ORMQuery queriesInModel:editor.model] valueForKey:@"name"]);
	NSString *reason = nil;
	ORMFormDocument *document = [ORMFormDocument documentForForm:form model:editor.model mapping:nil reason:&reason];
	XCTAssertNotNil(document, @"%@", reason);
	XCTAssertEqualObjects(document.missing, @[], @"every form here is whole: %@", document.notes);
	return document;
}

/* A step from the anchor to many, a repeat: a form of its own over the
 * order's lines, given the order, its read every line of it; the order's
 * own read leaves them out. */
- (void)testAStepToManyIsARepeat
{
	ORMEditor *editor = [self orders];
	ORMFormDocument *document = [self receiveGoodsOf:editor];
	XCTAssertEqualObjects([document.fields valueForKey:@"elementName"], (@[ @"number", @"day" ]), @"%@", document.notes);
	XCTAssertEqualObjects([document.repeats allKeys], @[ @"purchaseLines" ]);
	ORMFormDocument *lines = [document.repeats objectForKey:@"purchaseLines"];
	XCTAssertEqualObjects([lines.fields valueForKey:@"elementName"], (@[ @"id", @"purchaseOrder", @"stockItem", @"quantity" ]));
	XCTAssertEqualObjects(lines.linkElement, @"purchaseOrder");
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	XCTAssertEqualObjects([form repeatNames], @[ @"purchaseLines" ]);
	ORMForm *repeat = [form repeatNamed:@"purchaseLines"];
	XCTAssertEqualObjects(repeat.linkElement, @"purchaseOrder");
	XCTAssertEqualObjects([repeat elementNamed:@"quantity"].role, @"entered");
	XCTAssertEqualObjects([repeat elementNamed:@"stockItem"].role, @"entered");
	XCTAssertEqualObjects([[form instanceGiven:@{}] objectForKey:@"purchaseLines"], @[], @"a new order: no lines");
	NSUInteger columns = [form.readPlan.columns count];
	XCTAssertEqual(columns, 2u, @"the order's read: its own, not its lines'");
}

/* The order's lines read as rows, changed, added and taken away, saved in
 * the order's one save; a row refused said at its element, as they were. */
- (void)testARepeatsRowsAreReadAndSaved
{
	ORMEditor *editor = [self orders];
	ORMForm *form = [ORMForm formWithPropertyList:[[self receiveGoodsOf:editor] tablePropertyList] error:NULL];
	NSManagedObjectModel *model = [[[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map] managedObjectModel];
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	NSError *error = nil;
	XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:&error]);
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
	[context setPersistentStoreCoordinator:coordinator];
	NSManagedObject *order = [NSEntityDescription insertNewObjectForEntityForName:@"PurchaseOrder" inManagedObjectContext:context];
	[order setValue:@7 forKey:@"number"];
	NSMutableDictionary *items = [NSMutableDictionary dictionary];
	for (NSString *sku in @[ @"OIL", @"FILTER", @"WIPER" ]) {
		NSManagedObject *item = [NSEntityDescription insertNewObjectForEntityForName:@"StockItem" inManagedObjectContext:context];
		[item setValue:sku forKey:@"sku"];
		[items setObject:item forKey:sku];
	}
	for (NSString *sku in @[ @"OIL", @"FILTER" ]) {
		NSManagedObject *line = [NSEntityDescription insertNewObjectForEntityForName:@"PurchaseLine" inManagedObjectContext:context];
		[line setValue:[NSUUID UUID] forKey:@"id"];
		[line setValue:order forKey:@"purchaseOrder"];
		[line setValue:[items objectForKey:sku] forKey:@"stockItem"];
		[line setValue:[NSDecimalNumber decimalNumberWithString:@"4"] forKey:@"quantity"];
	}
	XCTAssertTrue([context save:&error], @"%@", error);

	NSDictionary *read = [form readKey:@"7" inContext:context error:&error];
	NSArray *rows = [read objectForKey:@"purchaseLines"];
	XCTAssertEqual([rows count], 2u, @"%@ %@", read, error);
	NSArray *skus = [[rows valueForKey:@"stockItem"] sortedArrayUsingSelector:@selector(compare:)];
	XCTAssertEqualObjects(skus, (@[ @"FILTER", @"OIL" ]));
	XCTAssertEqualObjects([[rows firstObject] objectForKey:@"quantity"], @"4");

	/* The oil's changed, the filter's taken away, a wiper's added. */
	NSMutableArray *changed = [NSMutableArray array];
	for (NSDictionary *row in rows) {
		if ([[row objectForKey:@"stockItem"] isEqualToString:@"OIL"]) {
			NSMutableDictionary *oil = [row mutableCopy];
			[oil setObject:@"6" forKey:@"quantity"];
			[changed addObject:oil];
		}
	}
	[changed addObject:@{ @"id": @"", @"stockItem": @"WIPER", @"quantity": @"2" }];
	NSMutableDictionary *instance = [read mutableCopy];
	[instance setObject:changed forKey:@"purchaseLines"];
	NSDictionary *errors = nil;
	XCTAssertNotNil([form save:instance inContext:context errors:&errors error:&error], @"%@ %@", errors, error);
	NSArray *now = [[form readKey:@"7" inContext:context error:NULL] objectForKey:@"purchaseLines"];
	NSMutableDictionary *quantities = [NSMutableDictionary dictionary];
	for (NSDictionary *row in now) {
		[quantities setObject:[row objectForKey:@"quantity"] forKey:[row objectForKey:@"stockItem"]];
	}
	XCTAssertEqualObjects(quantities, (@{ @"OIL": @"6", @"WIPER": @"2" }), @"one save, the filter's line gone");

	/* A row naming an item there is none of: said at it, nothing changed. */
	NSMutableArray *wrong = [now mutableCopy];
	[wrong addObject:@{ @"id": @"", @"stockItem": @"BRAKES", @"quantity": @"1" }];
	[instance setObject:wrong forKey:@"purchaseLines"];
	XCTAssertNil([form save:instance inContext:context errors:&errors error:&error]);
	XCTAssertEqualObjects([errors allKeys], @[ @"purchaseLines[2].stockItem" ], @"%@", errors);
	XCTAssertEqual([[[form readKey:@"7" inContext:context error:NULL] objectForKey:@"purchaseLines"] count], 2u, @"as they were");
}

/* A session over an order: its lines as rows, set and saved; and
 * submitted instead of saved, what the submission refuses said by row. */
- (void)testASessionHasRowsAndMaySubmit
{
	ORMEditor *editor = [self orders];
	ORMForm *form = [ORMForm formWithPropertyList:[[self receiveGoodsOf:editor] tablePropertyList] error:NULL];
	NSManagedObjectModel *model = [[[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map] managedObjectModel];
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	[coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:NULL];
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
	[context setPersistentStoreCoordinator:coordinator];
	NSManagedObject *order = [NSEntityDescription insertNewObjectForEntityForName:@"PurchaseOrder" inManagedObjectContext:context];
	[order setValue:@9 forKey:@"number"];
	NSManagedObject *item = [NSEntityDescription insertNewObjectForEntityForName:@"StockItem" inManagedObjectContext:context];
	[item setValue:@"OIL" forKey:@"sku"];
	NSManagedObject *line = [NSEntityDescription insertNewObjectForEntityForName:@"PurchaseLine" inManagedObjectContext:context];
	[line setValue:[NSUUID UUID] forKey:@"id"];
	[line setValue:order forKey:@"purchaseOrder"];
	[line setValue:item forKey:@"stockItem"];
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);

	ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form given:@{}];
	[session useContext:context saving:nil];
	session.key = @"9";
	XCTAssertTrue([session open:&error], @"%@", error);
	NSArray *rows = [session rowsOfRepeat:@"purchaseLines"];
	XCTAssertEqual([rows count], 1u);
	XCTAssertEqualObjects([session choicesNamed:@"stockItem" inRepeat:@"purchaseLines" row:0 error:&error], @[ @"OIL" ], @"%@", error);
	NSMutableDictionary *row = [[rows firstObject] mutableCopy];
	[row setObject:@"12" forKey:@"quantity"];
	[session setRows:@[ row ] forRepeat:@"purchaseLines"];
	XCTAssertTrue([session save:&error], @"%@ %@", session.errors, error);
	XCTAssertEqualObjects([[[session rowsOfRepeat:@"purchaseLines"] firstObject] objectForKey:@"quantity"], @"12", @"read again");

	/* Submitted: the handler's refusal by row, then done. */
	__block NSDictionary *submitted = nil;
	session.submitting = ^NSDictionary *(NSDictionary *values, NSString **made) {
		submitted = values;
		NSString *quantity = [[[values objectForKey:@"purchaseLines"] firstObject] objectForKey:@"quantity"];
		if ([quantity doubleValue] > 10) {
			return @{ @"purchaseLines[0].quantity": @"More than was ordered." };
		}
		*made = @"R1";
		return @{};
	};
	XCTAssertFalse([session save:&error]);
	XCTAssertEqualObjects(session.errors, (@{ @"purchaseLines[0].quantity": @"More than was ordered." }));
	XCTAssertEqual([[submitted objectForKey:@"purchaseLines"] count], 1u, @"handed the rows");
	[row setObject:@"8" forKey:@"quantity"];
	[session setRows:@[ row ] forRepeat:@"purchaseLines"];
	XCTAssertTrue([session save:&error]);
	XCTAssertEqualObjects(session.savedKey, @"R1", @"what it made");
	XCTAssertEqualObjects([[line valueForKey:@"quantity"] description], @"12", @"submitted, not written");
}

#pragma mark Flows

/* The fill-up model, with a list of its vehicles: a flow's screens. */
- (ORMEditor *)fillUpsWithVehicles
{
	ORMEditor *editor = [self fillUps];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:@"Query Vehicles:\nVehicle (shown)\n" failures:&failures],
	              @"%@", failures);
	return editor;
}

- (ORMQuery *)query:(NSString *)name in:(ORMModel *)model
{
	for (ORMQuery *query in [ORMQuery queriesInModel:model]) {
		if ([query.name isEqualToString:name]) {
			return query;
		}
	}
	XCTFail(@"no %@", name);
	return nil;
}

/* The form's given node of the type. */
- (ORMQueryNode *)givenNodeOf:(ORMQuery *)form type:(NSString *)typeName
{
	for (ORMQueryNode *node in [form nodes]) {
		if (node.isGiven && [node.objectType.name isEqualToString:typeName]) {
			return node;
		}
	}
	XCTFail(@"no given %@", typeName);
	return nil;
}

- (NSString *)flowXMLFrom:(ORMQuery *)vehicles to:(ORMQuery *)form giving:(NSString *)nodeId
{
	return [NSString stringWithFormat:
	                     @"<flow:Flow xmlns:flow=\"http://schemas.ormkit.org/2026-10/Flows\" Name=\"Records\" Model=\"Logbook.orm\">"
	                     @"<flow:Entry Name=\"Start\" Screen=\"s1\"/>"
	                     @"<flow:Screen id=\"s1\" Query=\"%@\" Name=\"Vehicles\" X=\"0\" Y=\"0\" Width=\"390\" Height=\"844\"/>"
	                     @"<flow:Screen id=\"s2\" Form=\"%@\" Name=\"RecordFillUp\" X=\"480\" Y=\"0\" Width=\"390\" Height=\"844\"/>"
	                     @"<flow:Transition From=\"s1\" On=\"RowChosen\" To=\"s2\"><flow:Give Node=\"%@\" From=\"row\"/></flow:Transition>"
	                     @"<flow:Transition From=\"s2\" On=\"SubmitDone\" Kind=\"Back\"/>"
	                     @"<flow:Transition From=\"s2\" On=\"Cancel\" Kind=\"Back\"/>"
	                     @"</flow:Flow>",
	                     vehicles.identifier, form.identifier, nodeId];
}

/* A flow read, checked against the model, said, and written back as read. */
- (void)testAFlowOfTheModelsFormsHolds
{
	ORMEditor *editor = [self fillUpsWithVehicles];
	ORMQuery *vehicles = [self query:@"Vehicles" in:editor.model], *form = [self formIn:editor.model];
	ORMQueryNode *vehicle = [self givenNodeOf:form type:@"Vehicle"];
	NSError *error = nil;
	ORMFlow *flow = [ORMFlow flowWithData:[[self flowXMLFrom:vehicles to:form giving:vehicle.identifier] dataUsingEncoding:NSUTF8StringEncoding]
	                                error:&error];
	XCTAssertNotNil(flow, @"%@", error);
	XCTAssertEqualObjects(flow.name, @"Records");
	XCTAssertEqualObjects(flow.modelPath, @"Logbook.orm");
	XCTAssertEqual([flow.screens count], 2u);
	XCTAssertEqualObjects([flow screenWithId:@"s2"].formId, form.identifier);
	XCTAssertEqual([flow screenWithId:@"s1"].width, 390.0);
	XCTAssertEqualObjects([flow problemsInModel:editor.model], @[]);
	XCTAssertEqualObjects([flow inputsLeftBy:[flow.transitions firstObject] inModel:editor.model], @[], @"the vehicle given");
	NSString *text = [flow textInModel:editor.model];
	XCTAssertTrue([text rangeOfString:@"▶ Start: Vehicles\n"].location != NSNotFound, @"%@", text);
	XCTAssertTrue([text rangeOfString:@"Vehicles (list) —RowChosen→ RecordFillUp (form): Vehicle = row\n"].location != NSNotFound, @"%@", text);
	XCTAssertTrue([text rangeOfString:@"RecordFillUp (form) —SubmitDone→ back\n"].location != NSNotFound, @"%@", text);
	ORMFlow *again = [ORMFlow flowWithData:[flow XMLData] error:&error];
	XCTAssertEqualObjects([again XMLData], [flow XMLData], @"written back as read");
	XCTAssertEqualObjects([again textInModel:editor.model], text);
}

/* A flow's ways on from a screen, in the actions of its form's document:
 * the save done opening the next form, given its vehicle; Cancel going
 * back; a trigger opening a list. Without a flow, none. */
- (void)testAFlowIsGeneratedIntoTheFormsActions
{
	ORMEditor *editor = [self fillUpsWithVehicles];
	ORMQuery *vehicles = [self query:@"Vehicles" in:editor.model], *form = [self formIn:editor.model];
	ORMQueryNode *vehicle = [self givenNodeOf:form type:@"Vehicle"];
	NSString *xml = [NSString stringWithFormat:
	                              @"<flow:Flow xmlns:flow=\"http://schemas.ormkit.org/2026-10/Flows\" Name=\"Records\" Model=\"Logbook.orm\">"
	                              @"<flow:Entry Name=\"Start\" Screen=\"s1\"/>"
	                              @"<flow:Screen id=\"s1\" Query=\"%@\" Name=\"Vehicles\"/>"
	                              @"<flow:Screen id=\"s2\" Form=\"%@\" Name=\"RecordFillUp\"/>"
	                              @"<flow:Transition From=\"s1\" On=\"RowChosen\" To=\"s2\"><flow:Give Node=\"%@\" From=\"row\"/></flow:Transition>"
	                              @"<flow:Transition From=\"s2\" On=\"SubmitDone\" To=\"s2\"><flow:Give Node=\"%@\" From=\"s2.%@\"/></flow:Transition>"
	                              @"<flow:Transition From=\"s2\" On=\"Cancel\" Kind=\"Back\"/>"
	                              @"<flow:Transition From=\"s2\" On=\"Trigger\" Control=\"vehicles\" To=\"s1\"/>"
	                              @"</flow:Flow>",
	                              vehicles.identifier, form.identifier, vehicle.identifier, vehicle.identifier, vehicle.identifier];
	NSError *error = nil;
	ORMFlow *flow = [ORMFlow flowWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
	XCTAssertNotNil(flow, @"%@", error);
	XCTAssertEqualObjects([flow problemsInModel:editor.model], @[]);
	ORMFormDocument *document = [self documentOf:editor];
	XCTAssertEqualObjects([document elementOfNode:vehicle.identifier], @"vehicle");
	XCTAssertEqual([[self nodes:@"//*[local-name()='load']" in:[document document]] count], 0u, @"no flow, no way on");
	[document setFlow:flow screen:[flow screenWithId:@"s2"]];
	NSXMLDocument *xforms = [document document];
	NSArray *done = [self nodes:@"//*[local-name()='submission'][@id='save']/*[local-name()='action']" in:xforms];
	XCTAssertEqual([done count], 1u, @"%@", [xforms XMLString]);
	XCTAssertEqualObjects([self attribute:@"ev:event" of:[done firstObject]], @"xforms-submit-done");
	NSXMLNode *resource = [[self nodes:@"//*[local-name()='submission'][@id='save']//*[local-name()='resource']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"value" of:resource], @"concat('form:open/RecordFillUp', '?vehicle=', instance('form')/vehicle)",
	                      @"the next form given this one's vehicle");
	NSXMLNode *back = [[self nodes:@"//*[local-name()='trigger'][@id='control-cancel']//*[local-name()='load']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"resource" of:back], @"form:back");
	NSXMLNode *list = [[self nodes:@"//*[local-name()='trigger'][@id='control-vehicles']//*[local-name()='load']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"resource" of:list], @"form:list/Vehicles");
	XCTAssertEqualObjects([[[self nodes:@"//*[local-name()='trigger'][@id='control-vehicles']/*[local-name()='label']" in:xforms] firstObject]
	                          stringValue],
	                      @"Vehicles", @"labelled with where it goes");
}

/* The fill-ups with a sample: two cars, Ann driving the first, and what a
 * fill-up refers to. */
- (ORMEditor *)fillUpsWithPopulation
{
	ORMEditor *editor = [self fillUpsWithVehicles];
	ORMModel *model = editor.model;
	NSString *reason = nil;
	NSDictionary *instances = @{
		@"Vehicle" : @[ ORMCarSeven, ORMCarEight ], @"User" : @[ @"ann@example.com" ], @"Fuel" : @[ @"Diesel" ], @"Station" : @[ @"Shell" ],
		@"Currency" : @[ @"KZT" ], @"DistanceUnit" : @[ @"km" ], @"VolumeUnit" : @[ @"L" ]
	};
	for (NSString *type in instances) {
		for (NSString *name in [instances objectForKey:type]) {
			XCTAssertNotNil([editor.populationEditor addInstanceOf:[[model objectTypeNamed:type] identifier] named:name reason:&reason],
			                @"%@ %@: %@", type, name, reason);
		}
	}
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		if ([[[fact primaryReading] expandedText] isEqualToString:@"User drives Vehicle"]) {
			NSArray *roles = [fact visibleRoles];
			XCTAssertNotNil(([editor.populationEditor addFactOf:fact.identifier
			                                              named:@{ [roles[0] identifier] : @"ann@example.com", [roles[1] identifier] : ORMCarSeven }
			                                             reason:&reason]),
			                @"%@", reason);
		}
	}
	return editor;
}

/* A flow walked through over the sample population: the cars listed, the
 * first chosen, its fill-up's form opened given it, its driver Ann alone;
 * saved empty, refused in the rule's words; filled in, saved, and back to
 * the cars. On its own: each way taken once. */
- (void)testAFlowIsWalkedOverThePopulation
{
	ORMEditor *editor = [self fillUpsWithPopulation];
	ORMQuery *vehicles = [self query:@"Vehicles" in:editor.model], *form = [self formIn:editor.model];
	ORMQueryNode *vehicle = [self givenNodeOf:form type:@"Vehicle"];
	NSError *error = nil;
	ORMFlow *flow = [ORMFlow flowWithData:[[self flowXMLFrom:vehicles to:form giving:vehicle.identifier] dataUsingEncoding:NSUTF8StringEncoding]
	                                error:&error];
	ORMFlowWalk *walk = [[ORMFlowWalk alloc] initWithFlow:flow model:editor.model mapping:nil];
	XCTAssertTrue([walk beginAt:@"Start" error:&error], @"%@", error);
	XCTAssertEqualObjects(walk.screen.identifier, @"s1");
	XCTAssertNil(walk.session, @"a list");
	XCTAssertEqual([walk.rows count], 2u, @"%@", walk.rows);
	NSUInteger seven = [walk.rowKeys indexOfObject:ORMCarSeven];
	XCTAssertNotEqual(seven, (NSUInteger)NSNotFound, @"%@", walk.rowKeys);
	ORMFlowTransition *chosen = [[walk transitions] firstObject];
	XCTAssertTrue([walk take:chosen row:seven error:&error], @"%@", error);
	XCTAssertEqualObjects(walk.screen.identifier, @"s2");
	XCTAssertEqualObjects([walk.session valueForElement:@"vehicle"], ORMCarSeven, @"given the car chosen");
	XCTAssertEqualObjects([walk.session choicesNamed:@"driver" error:&error], @[ @"ann@example.com" ], @"the car's drivers: %@", error);
	XCTAssertEqualObjects([walk labelOfKey:@"ann@example.com" element:@"driver"], @"ann@example.com", @"a user known by the key");
	XCTAssertEqualObjects([walk labelOfKey:ORMCarSeven element:@"vehicle"], ORMCarSeven, @"a car with no other text, by its key");
	XCTAssertEqualObjects([walk labelOfKey:@"Diesel" element:@"timestamp"], @"Diesel", @"no reference: as it is");
	/* What the model lists the values of offered as its choices. */
	NSMutableArray *listed = [NSMutableArray array];
	for (ORMFormElement *element in walk.session.form.elements) {
		if (element.items != nil) {
			[listed addObject:element.name];
			XCTAssertEqualObjects([walk.session choicesNamed:element.name error:NULL], element.items, @"%@", element.name);
		}
	}
	XCTAssertTrue([listed count] > 0, @"%@", [walk.session.form.elements valueForKey:@"name"]);
	XCTAssertFalse([walk submit:&error], @"nothing entered");
	XCTAssertEqualObjects(walk.screen.identifier, @"s2", @"no way on a refusal: still there");
	XCTAssertTrue([[walk.log lastObject] hasPrefix:@"RecordFillUp refused: "], @"%@", walk.log);
	XCTAssertTrue([[walk.log lastObject] rangeOfString:@"timestamp: "].location != NSNotFound, @"said at its element: %@", walk.log);
	NSMutableDictionary *fillUp = [self fillUpIn:walk.session.form];
	[fillUp removeObjectForKey:@"vehicle"];
	for (NSString *name in fillUp) {
		if ([name length] > 0) {
			[walk.session setValue:[fillUp objectForKey:name] forElement:name];
		}
	}
	XCTAssertTrue([walk submit:&error], @"%@ %@", walk.session.errors, error);
	XCTAssertEqualObjects(walk.screen.identifier, @"s1", @"saved: back to the cars, %@", walk.log);
	XCTAssertEqualObjects([walk.log lastObject], @"RecordFillUp —SubmitDone→ back: Vehicles");

	ORMFlowWalk *alone = [[ORMFlowWalk alloc] initWithFlow:flow model:editor.model mapping:nil];
	NSString *text = [alone walkFrom:nil error:&error];
	XCTAssertNotNil(text, @"%@", error);
	XCTAssertTrue([text hasPrefix:@"▶ Start: Vehicles, 2 rows: "], @"%@", text);
	XCTAssertTrue([text rangeOfString:@"Vehicles —RowChosen ("].location != NSNotFound, @"%@", text);
	XCTAssertTrue([text rangeOfString:@"→ RecordFillUp, given vehicle = "].location != NSNotFound, @"%@", text);
	XCTAssertTrue([text rangeOfString:@"RecordFillUp refused: "].location != NSNotFound, @"%@", text);
	XCTAssertTrue([text rangeOfString:@"RecordFillUp —Cancel→ back: Vehicles\n"].location != NSNotFound, @"%@", text);
}

/* An overlay returns what it made to the form it was opened over: the
 * fill-up's new car, made in a car's own form, given back to it. */
- (void)testAnOverlayReturnsWhatItMade
{
	ORMEditor *editor = [self fillUpsWithPopulation];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:@"Nickname is a value type.\n"
	                                                                             @"Portable data type: Text: Variable Length(40)\n"
	                                                                             @"Vehicle has Nickname\n"
	                                                                             @"Each Vehicle has at most one Nickname.\n"
	                                                                             @"\n"
	                                                                             @"Query NewVehicle:\n"
	                                                                             @"Form NewVehicle:\n"
	                                                                             @"Vehicle\n"
	                                                                             @"  + has Nickname (entered)\n"
	                                                                    failures:&failures],
	              @"%@", failures);
	ORMQuery *form = [self formIn:editor.model], *car = [self query:@"NewVehicle" in:editor.model];
	ORMQueryNode *vehicle = [self givenNodeOf:form type:@"Vehicle"];
	NSString *xml = [NSString stringWithFormat:
	                              @"<flow:Flow xmlns:flow=\"http://schemas.ormkit.org/2026-10/Flows\" Name=\"Records\" Model=\"Logbook.orm\">"
	                              @"<flow:Entry Name=\"Start\" Screen=\"s2\"/>"
	                              @"<flow:Screen id=\"s2\" Form=\"%@\" Name=\"RecordFillUp\"/>"
	                              @"<flow:Screen id=\"s3\" Form=\"%@\" Name=\"NewVehicle\"/>"
	                              @"<flow:Transition From=\"s2\" On=\"Trigger\" Control=\"newVehicle\" To=\"s3\" Kind=\"Overlay\"/>"
	                              @"<flow:Transition From=\"s3\" On=\"SubmitDone\" Kind=\"Close\"><flow:Give Node=\"%@\" From=\"result\"/></flow:Transition>"
	                              @"</flow:Flow>",
	                              form.identifier, car.identifier, vehicle.identifier];
	NSError *error = nil;
	ORMFlow *flow = [ORMFlow flowWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
	XCTAssertEqualObjects([flow problemsInModel:editor.model], @[], @"a Close gives to the form it is over");
	XCTAssertEqualObjects([flow openerOf:[flow screenWithId:@"s3"]].identifier, @"s2");
	ORMFlowWalk *walk = [[ORMFlowWalk alloc] initWithFlow:flow model:editor.model mapping:nil];
	XCTAssertTrue([walk beginAt:nil error:&error], @"%@", error);
	XCTAssertTrue([walk take:[[walk transitions] firstObject] row:0 error:&error], @"%@", error);
	XCTAssertEqualObjects(walk.screen.identifier, @"s3", @"over it");
	XCTAssertTrue([walk submit:&error], @"%@ %@", walk.session.errors, error);
	NSString *made = [[walk.log objectAtIndex:[walk.log count] - 2] substringFromIndex:[@"NewVehicle saved: " length]];
	XCTAssertEqualObjects(walk.screen.identifier, @"s2", @"closed: %@", walk.log);
	XCTAssertEqualObjects([walk.session valueForElement:@"vehicle"], made, @"given the car it made: %@", walk.log);
	XCTAssertTrue([[walk.log lastObject] hasPrefix:@"NewVehicle —SubmitDone→ closed: RecordFillUp, given vehicle = "], @"%@", walk.log);
	/* And in its document: the overlay's save closes it, giving its key. */
	NSString *reason = nil;
	ORMFormDocument *document = [ORMFormDocument documentForForm:car model:editor.model mapping:nil reason:&reason];
	[document setFlow:flow screen:[flow screenWithId:@"s3"]];
	NSXMLNode *resource = [[self nodes:@"//*[local-name()='submission'][@id='save']//*[local-name()='resource']" in:[document document]] firstObject];
	XCTAssertEqualObjects([self attribute:@"value" of:resource], @"concat('form:close', '?vehicle=', instance('form')/id)");
	ORMFormDocument *opener = [self documentOf:editor];
	[opener setFlow:flow screen:[flow screenWithId:@"s2"]];
	NSXMLNode *over = [[self nodes:@"//*[local-name()='trigger'][@id='control-newVehicle']//*[local-name()='load']" in:[opener document]] firstObject];
	XCTAssertEqualObjects([self attribute:@"show" of:over], @"new", @"an overlay, over it");
	XCTAssertEqualObjects([self attribute:@"resource" of:over], @"form:open/NewVehicle");
}

/* What a flow says wrong of the model, each said. */
- (void)testAFlowSaysWhatIsWrongOfIt
{
	ORMEditor *editor = [self fillUpsWithVehicles];
	ORMQuery *vehicles = [self query:@"Vehicles" in:editor.model], *form = [self formIn:editor.model];
	NSError *error = nil;
	/* A value given to what is no input of the form. */
	ORMFlow *flow = [ORMFlow flowWithData:[[self flowXMLFrom:vehicles to:form giving:@"_nowhere"] dataUsingEncoding:NSUTF8StringEncoding] error:&error];
	NSArray *problems = [flow problemsInModel:editor.model];
	XCTAssertEqual([problems count], 1u, @"%@", problems);
	XCTAssertTrue([[problems firstObject] rangeOfString:@"gives _nowhere, which is not an input of RecordFillUp"].location != NSNotFound, @"%@", problems);
	XCTAssertEqual([[flow inputsLeftBy:[flow.transitions firstObject] inModel:editor.model] count], 1u, @"the vehicle left to the app");
	/* A list shown as a form, a form gone, a row chosen in a form, no entry. */
	ORMFlowScreen *asForm = [[ORMFlowScreen alloc] init];
	asForm.identifier = @"s3";
	asForm.formId = vehicles.identifier;
	ORMFlowScreen *gone = [[ORMFlowScreen alloc] init];
	gone.identifier = @"s4";
	gone.formId = @"_gone";
	ORMFlowTransition *row = [[ORMFlowTransition alloc] init];
	row.fromScreen = @"s2";
	row.on = ORMFlowOnRowChosen;
	row.toScreen = @"s1";
	row.kind = ORMFlowKindNavigate;
	flow.screens = [flow.screens arrayByAddingObjectsFromArray:@[ asForm, gone ]];
	flow.transitions = [flow.transitions arrayByAddingObject:row];
	flow.entries = @[];
	problems = [flow problemsInModel:editor.model];
	NSString *all = [problems componentsJoinedByString:@"\n"];
	for (NSString *said in @[ @"shows Vehicles as a form, which is not one", @"shows _gone, which the model no longer has",
	                          @"RecordFillUp on RowChosen: a form has no rows to choose", @"The flow has no entry" ]) {
		XCTAssertTrue([all rangeOfString:said].location != NSNotFound, @"%@ in %@", said, all);
	}
}

/* A flow designed: screens added for the model's list and form, the first
 * the entry; a transition from the list giving the form its vehicle, the
 * row; a return; moved, renamed, removed; each one undo step. */
- (void)testAFlowIsDesignedOneStepAtATime
{
	ORMEditor *editor = [self fillUpsWithVehicles];
	NSUndoManager *undo = [[NSUndoManager alloc] init];
	[undo setGroupsByEvent:NO];
	ORMFlow *flow = [[ORMFlow alloc] init];
	flow.name = @"Records";
	flow.modelPath = @"Logbook.orm";
	ORMFlowEditor *designer = [[ORMFlowEditor alloc] initWithFlow:flow model:editor.model undoManager:undo];
	XCTAssertEqualObjects([[designer forms] valueForKey:@"name"], @[ @"RecordFillUp" ]);
	XCTAssertEqualObjects([[designer lists] valueForKey:@"name"], @[ @"Vehicles" ]);
	__block NSUInteger told = 0;
	id observer = [[NSNotificationCenter defaultCenter] addObserverForName:ORMFlowEditorDidChangeNotification object:designer queue:nil
	                                                            usingBlock:^(NSNotification *note) { told++; }];
	[undo beginUndoGrouping];
	ORMFlowScreen *vehicles = [designer addScreenForQuery:[[designer lists] firstObject] at:NSMakePoint(10, 20)];
	[undo endUndoGrouping];
	[undo beginUndoGrouping];
	ORMFlowScreen *form = [designer addScreenForQuery:[[designer forms] firstObject] at:NSMakePoint(400, 20)];
	[undo endUndoGrouping];
	XCTAssertEqualObjects(vehicles.identifier, @"Vehicles");
	XCTAssertEqualObjects(form.identifier, @"RecordFillUp");
	XCTAssertEqualObjects([flow.entries valueForKey:@"screen"], @[ @"Vehicles" ], @"the first screen the entry");
	XCTAssertEqual([[designer inputsOfScreen:form] count], 1u);
	[undo beginUndoGrouping];
	ORMFlowTransition *chosen = [designer addTransitionFrom:@"Vehicles" to:@"RecordFillUp"];
	[undo endUndoGrouping];
	XCTAssertEqualObjects(chosen.on, ORMFlowOnRowChosen);
	XCTAssertEqual([chosen.gives count], 1u, @"the vehicle, given the row");
	XCTAssertEqualObjects([[chosen.gives firstObject] from], @"row");
	XCTAssertEqualObjects([designer nameOfNode:[[chosen.gives firstObject] nodeId] inScreen:form], @"Vehicle");
	XCTAssertNil([designer addTransitionFrom:@"Vehicles" to:@"Vehicles"], @"not to itself");
	[undo beginUndoGrouping];
	[designer addReturnFrom:@"RecordFillUp" on:ORMFlowOnSubmitDone kind:ORMFlowKindBack];
	[undo endUndoGrouping];
	XCTAssertEqualObjects([designer problems], @[], @"it holds");
	[undo beginUndoGrouping];
	[designer moveScreens:@[ @"RecordFillUp" ] by:NSMakeSize(30, -5)];
	[undo endUndoGrouping];
	XCTAssertEqual(form.x, 430.0);
	[undo beginUndoGrouping];
	[designer renameScreen:@"RecordFillUp" to:@"  Fill-up  "];
	[undo endUndoGrouping];
	XCTAssertEqualObjects([flow screenWithId:@"RecordFillUp"].name, @"Fill-up");
	NSData *designed = [designer XMLData];
	[undo beginUndoGrouping];
	[designer removeScreens:@[ @"RecordFillUp" ]];
	[undo endUndoGrouping];
	XCTAssertEqual([flow.screens count], 1u);
	XCTAssertEqual([flow.transitions count], 0u, @"its transitions gone with it");
	[undo undo];
	XCTAssertEqualObjects([designer XMLData], designed, @"undone: as it was");
	XCTAssertEqualObjects([undo redoActionName], @"Delete Screen");
	[undo undo];
	XCTAssertEqualObjects([flow screenWithId:@"RecordFillUp"].name, @"RecordFillUp");
	XCTAssertEqual(told, 9u, @"told of each change, undo included");
	[[NSNotificationCenter defaultCenter] removeObserver:observer];
	ORMFlow *read = [ORMFlow flowWithData:[designer XMLData] error:NULL];
	XCTAssertEqualObjects([read problemsInModel:editor.model], @[], @"written as it is, it holds");
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

#pragma mark Beyond the anchor's own (Logbook's stock and records)

/* Logbook's shapes: a receipt of an order from a supplier known by its
 * contact; a customer whose contact, and the contact's address, are made
 * with it; an event that is a trip or a fill-up. */
static NSString *const ORMBeyond = @"Catalog is an entity type.\n"
                                   @"Reference Mode: .code\n"
                                   @"Contact is an entity type.\n"
                                   @"Reference Mode: .id\n"
                                   @"Portable data type: Other: Object ID\n"
                                   @"Address is an entity type.\n"
                                   @"Reference Mode: .id\n"
                                   @"Portable data type: Other: Object ID\n"
                                   @"Customer is an entity type.\n"
                                   @"Reference Mode: .id\n"
                                   @"Portable data type: Other: Object ID\n"
                                   @"Supplier is an entity type.\n"
                                   @"Reference Mode: .id\n"
                                   @"Portable data type: Other: Object ID\n"
                                   @"PurchaseOrder is an entity type.\n"
                                   @"Reference Mode: .number\n"
                                   @"Receipt is an entity type.\n"
                                   @"Reference Mode: .id\n"
                                   @"Portable data type: Other: Object ID\n"
                                   @"ContactName is a value type.\n"
                                   @"Portable data type: Text: Variable Length(200)\n"
                                   @"AddressLines is a value type.\n"
                                   @"Portable data type: Text: Variable Length\n"
                                   @"City is a value type.\n"
                                   @"Portable data type: Text: Variable Length\n"
                                   @"PostCode is a value type.\n"
                                   @"Portable data type: Text: Variable Length\n"
                                   @"Day is a value type.\n"
                                   @"Portable data type: Temporal: Date\n"
                                   @"Contact has ContactName\n"
                                   @"Each Contact has exactly one ContactName.\n"
                                   @"Address has AddressLines\n"
                                   @"Each Address has exactly one AddressLines.\n"
                                   @"Address is in City\n"
                                   @"Each Address is in at most one City.\n"
                                   @"Address has PostCode\n"
                                   @"Each Address has at most one PostCode.\n"
                                   @"Contact ships to Address (as ShippingAddress)\n"
                                   @"Each Contact ships to at most one Address.\n"
                                   @"Customer is of Catalog\n"
                                   @"Each Customer is of exactly one Catalog.\n"
                                   @"Customer is of Contact\n"
                                   @"Each Customer is of exactly one Contact.\n"
                                   @"For each Contact, at most one Customer is of that Contact.\n"
                                   @"Supplier is of Contact\n"
                                   @"Each Supplier is of exactly one Contact.\n"
                                   @"PurchaseOrder is from Supplier\n"
                                   @"Each PurchaseOrder is from exactly one Supplier.\n"
                                   @"Receipt is of PurchaseOrder\n"
                                   @"Each Receipt is of exactly one PurchaseOrder.\n"
                                   @"Receipt was received on Day\n"
                                   @"Each Receipt was received on at most one Day.\n"
                                   @"\n"
                                   @"Query ReceiveFromSupplier:\n"
                                   @"Form ReceiveFromSupplier:\n"
                                   @"Receipt\n"
                                   @"  + is of PurchaseOrder = ?\n"
                                   @"    + is from Supplier\n"
                                   @"      + is of Contact\n"
                                   @"        + has ContactName (shown)\n"
                                   @"  + was received on Day (entered)\n"
                                   @"\n"
                                   @"Query NewCustomer:\n"
                                   @"Form NewCustomer:\n"
                                   @"Customer\n"
                                   @"  + is of Catalog = ?\n"
                                   @"  + is of Contact\n"
                                   @"    + has ContactName (entered)\n"
                                   @"    + ships to Address\n"
                                   @"      + has AddressLines (entered)\n"
                                   @"      + is in City (entered)\n"
                                   @"      + has PostCode (entered)\n";

static NSString *const ORMEvents = @"Vehicle is an entity type.\n"
                                   @"Reference Mode: .id\n"
                                   @"Portable data type: Other: Object ID\n"
                                   @"Event is an entity type.\n"
                                   @"Reference Mode: .id\n"
                                   @"Portable data type: Other: Object ID\n"
                                   @"Trip is an entity type.\n"
                                   @"FillUp is an entity type.\n"
                                   @"Each Trip is an Event.\n"
                                   @"Each FillUp is an Event.\n"
                                   @"Moment is a value type.\n"
                                   @"Portable data type: Temporal: Date & Time\n"
                                   @"Place is a value type.\n"
                                   @"Portable data type: Text: Variable Length\n"
                                   @"Litres is a value type.\n"
                                   @"Portable data type: Numeric: Decimal(10, 2)\n"
                                   @"Event is of Vehicle\n"
                                   @"Each Event is of exactly one Vehicle.\n"
                                   @"Event was at Moment\n"
                                   @"Each Event was at exactly one Moment.\n"
                                   @"Trip went to Place\n"
                                   @"Each Trip went to exactly one Place.\n"
                                   @"FillUp took Litres\n"
                                   @"Each FillUp took exactly one Litres.\n"
                                   @"\n"
                                   @"Query RecordEvent:\n"
                                   @"Form RecordEvent:\n"
                                   @"Event\n"
                                   @"  + is of Vehicle = ?\n"
                                   @"  + was at Moment (entered)\n"
                                   @"  + is Trip\n"
                                   @"    + went to Place (entered)\n"
                                   @"  + is FillUp\n"
                                   @"    + took Litres (entered)\n";

- (ORMEditor *)editorOf:(NSString *)text
{
	ORMEditor *editor = [self newEditor];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	return editor;
}

- (ORMFormDocument *)form:(NSString *)name of:(ORMEditor *)editor
{
	NSString *reason = nil;
	ORMFormDocument *document = [ORMFormDocument documentForForm:[self query:name in:editor.model] model:editor.model mapping:nil
	                                                      reason:&reason];
	XCTAssertNotNil(document, @"%@", reason);
	XCTAssertEqualObjects(document.missing, @[], @"every form here is whole: %@", document.notes);
	return document;
}

- (NSManagedObjectContext *)contextOf:(ORMEditor *)editor
{
	NSManagedObjectModel *model = [[[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map] managedObjectModel];
	NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
	NSError *error = nil;
	XCTAssertNotNil([coordinator addPersistentStoreWithType:NSInMemoryStoreType configuration:nil URL:nil options:nil error:&error]);
	NSManagedObjectContext *context = [[NSManagedObjectContext alloc] init];
	[context setPersistentStoreCoordinator:coordinator];
	return context;
}

- (NSManagedObject *)insert:(NSString *)entity values:(NSDictionary *)values in:(NSManagedObjectContext *)context
{
	NSManagedObject *object = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:context];
	for (NSString *key in values) {
		[object setValue:[values objectForKey:key] forKey:key];
	}
	return object;
}

/* Through an object it refers to (the order's supplier's contact's name):
 * shown, read with the receipt, and as the order chosen has it; never
 * written. */
- (void)testAValueThroughAReferenceIsShown
{
	ORMEditor *editor = [self editorOf:ORMBeyond];
	ORMFormDocument *document = [self form:@"ReceiveFromSupplier" of:editor];
	XCTAssertEqualObjects([document.fields valueForKey:@"elementName"],
	                      (@[ @"id", @"purchaseOrder", @"purchaseOrderSupplierContactContactName", @"day" ]), @"%@", document.notes);
	ORMFormField *name = [document fieldNamed:@"purchaseOrderSupplierContactContactName"];
	XCTAssertTrue(name.isThrough);
	XCTAssertEqualObjects(name.keys, (@[ @"purchaseOrder", @"supplier", @"contact", @"contactName" ]));
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	ORMFormElement *element = [form elementNamed:name.elementName];
	XCTAssertEqualObjects(element.role, @"shown");
	XCTAssertFalse(element.written);
	XCTAssertNil(element.group);
	NSXMLDocument *xforms = [document document];
	NSString *output = [NSString stringWithFormat:@"//*[local-name()='output'][@bind='bind-%@']", [name fieldId]];
	XCTAssertEqual([[self nodes:output in:xforms] count], 1u);
	XCTAssertEqual([[self nodes:@"//*[local-name()='instance'][@id='form']/*/*[local-name()='purchaseOrderSupplierContactContactName']" in:xforms] count], 1u);

	NSManagedObjectContext *context = [self contextOf:editor];
	NSManagedObject *contact = [self insert:@"Contact" values:@{ @"id" : [NSUUID UUID], @"contactName" : @"Acme Parts" } in:context];
	NSManagedObject *supplier = [self insert:@"Supplier" values:@{ @"id" : [NSUUID UUID], @"contact" : contact } in:context];
	[self insert:@"PurchaseOrder" values:@{ @"number" : @7, @"supplier" : supplier } in:context];
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	XCTAssertEqualObjects([form throughValuesOf:@{ @"purchaseOrder" : @"7" } inContext:context],
	                      (@{ name.elementName : @"Acme Parts" }));
	XCTAssertEqualObjects([form throughValuesOf:@{ @"purchaseOrder" : @"" } inContext:context], (@{ name.elementName : @"" }));
	ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form given:@{ @"purchaseOrder" : @"7" }];
	[session useContext:context saving:nil];
	XCTAssertTrue([session open:&error], @"%@", error);
	XCTAssertEqualObjects([session valueForElement:name.elementName], @"Acme Parts", @"shown as it opens");
	[session setValue:@"2026-11-11" forElement:@"day"];
	XCTAssertTrue([session save:&error], @"%@ %@", session.errors, error);
	XCTAssertEqualObjects([contact valueForKey:@"contactName"], @"Acme Parts", @"never written");
	NSDictionary *read = [form readKey:session.savedKey inContext:context error:&error];
	XCTAssertEqualObjects([read objectForKey:name.elementName], @"Acme Parts", @"read with the receipt: %@", error);
}

/* Owned (a customer's contact, the contact's address): its elements in a
 * group of their own, nested in the instance; made with the customer,
 * changed with it, and put back where its save is refused. */
- (void)testAnOwnedObjectIsMadeWithTheAnchor
{
	ORMEditor *editor = [self editorOf:ORMBeyond];
	ORMFormDocument *document = [self form:@"NewCustomer" of:editor];
	XCTAssertEqualObjects([document.fields valueForKey:@"elementName"],
	                      (@[ @"id", @"catalog", @"contact/contactName", @"contact/shippingAddress/addressLines",
	                          @"contact/shippingAddress/city", @"contact/shippingAddress/postCode" ]), @"%@", document.notes);
	XCTAssertEqualObjects([document fieldNamed:@"contact/shippingAddress/city"].groupName, @"contact/shippingAddress");
	NSXMLDocument *xforms = [document document];
	XCTAssertEqual([[self nodes:@"//*[local-name()='instance'][@id='form']/*/*[local-name()='contact']/*[local-name()='shippingAddress']/*[local-name()='city']"
	                         in:xforms] count], 1u, @"nested: %@", [xforms XMLStringWithOptions:NSXMLNodePrettyPrint]);
	XCTAssertEqual([[self nodes:@"//*[local-name()='group'][@id='control-contact']//*[local-name()='group'][@id='control-contact-shippingAddress']"
	                         in:xforms] count], 1u);
	NSDictionary *required = [document requiredElements];
	XCTAssertNotNil([required objectForKey:@"contact/contactName"], @"the contact is the customer's: %@", required);
	NSXMLNode *lines = [[self nodes:@"//*[local-name()='bind'][@ref='contact/shippingAddress/addressLines']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"required" of:lines], @"(../* != '')", @"an address entered at all has its lines");
	/* Its other constraints bound too, from within its group: an address
	 * entered at all is in a city or has a post code. */
	NSMutableArray *either = [NSMutableArray array];
	for (ORMFactType *fact in editor.model.factTypes) {
		ORMRole *address = [fact.roles firstObject];
		NSString *other = [[[fact.roles lastObject] player] name];
		if ([address.player.name isEqualToString:@"Address"] && ([other isEqualToString:@"City"] || [other isEqualToString:@"PostCode"])) {
			[either addObject:address.identifier];
		}
	}
	XCTAssertEqual([either count], 2u);
	XCTAssertNotNil([editor.constraintEditor addMandatoryConstraintOverRoles:either reason:NULL]);
	document = [self form:@"NewCustomer" of:editor];
	xforms = [document document];
	NSXMLNode *city = [[self nodes:@"//*[local-name()='bind'][@ref='contact/shippingAddress/city']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"required" of:city], @"((../../../contact/shippingAddress/postCode = '') and ../* != '')",
	                      @"%@", [xforms XMLStringWithOptions:NSXMLNodePrettyPrint]);
	XCTAssertFalse([[document.checkedWhereSubmitted componentsJoinedByString:@"\n"] rangeOfString:@"City"].location != NSNotFound, @"%@", document.checkedWhereSubmitted);

	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	XCTAssertEqualObjects([[form groups] valueForKey:@"name"], (@[ @"contact", @"contact/shippingAddress" ]));
	XCTAssertEqualObjects([[form groups] valueForKey:@"needed"], (@[ @YES, @NO ]));
	NSManagedObjectContext *context = [self contextOf:editor];
	[self insert:@"Catalog" values:@{ @"code" : @"GAR" } in:context];
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);

	/* No address entered: none made. */
	NSMutableDictionary *instance = [[form instanceGiven:@{ @"catalog" : @"GAR" }] mutableCopy];
	[instance setObject:@"Ann's Garage" forKey:@"contact/contactName"];
	NSDictionary *errors = nil;
	NSManagedObject *customer = [form save:instance inContext:context errors:&errors error:&error];
	XCTAssertNotNil(customer, @"%@ %@", errors, error);
	NSManagedObject *contact = [customer valueForKey:@"contact"];
	XCTAssertEqualObjects([contact valueForKey:@"contactName"], @"Ann's Garage");
	XCTAssertNotNil([contact valueForKey:@"id"], @"given a key");
	XCTAssertNil([contact valueForKey:@"shippingAddress"]);

	/* Read again, its address entered: made, the contact the same. */
	NSString *key = [[customer valueForKey:@"id"] UUIDString];
	NSMutableDictionary *read = [[form readKey:key inContext:context error:&error] mutableCopy];
	XCTAssertEqualObjects([read objectForKey:@"contact/contactName"], @"Ann's Garage", @"%@", error);
	[read setObject:@"1 Abay Ave" forKey:@"contact/shippingAddress/addressLines"];
	[read setObject:@"Almaty" forKey:@"contact/shippingAddress/city"];
	XCTAssertNotNil([form save:read inContext:context errors:&errors error:&error], @"%@ %@", errors, error);
	XCTAssertEqual([customer valueForKey:@"contact"], contact);
	XCTAssertEqualObjects([[contact valueForKey:@"shippingAddress"] valueForKey:@"city"], @"Almaty");

	/* A new customer's, refused (no name): nothing of it left. */
	NSUInteger contacts = [[context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Contact"] error:NULL] count];
	NSMutableDictionary *nameless = [[form instanceGiven:@{ @"catalog" : @"GAR" }] mutableCopy];
	[nameless setObject:@"Almaty" forKey:@"contact/shippingAddress/city"];
	XCTAssertNil([form save:nameless inContext:context errors:&errors error:&error]);
	XCTAssertTrue([[errors allKeys] count] > 0, @"%@", error);
	XCTAssertEqual([[context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Contact"] error:NULL] count], contacts,
	               @"put back: %@", errors);
	XCTAssertEqual([[context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Address"] error:NULL] count], 1u);

	/* To the service: nested, a deep insert. */
	NSManagedObjectModel *model = [[context persistentStoreCoordinator] managedObjectModel];
	ORMFormRequest *post = [form saveRequestFor:instance original:nil etag:nil model:model error:&error];
	XCTAssertEqualObjects(post.method, @"POST", @"%@", error);
	NSDictionary *nested = nil;
	for (id value in [post.body allValues]) {
		nested = [value isKindOfClass:[NSDictionary class]] ? value : nested;
	}
	XCTAssertTrue([[nested allValues] containsObject:@"Ann's Garage"], @"%@", post.body);
}

/* Subtype parts (+ is Trip, + is FillUp): the kind the object is chosen,
 * each part relevant where it is that; made of it, read as it, and stays
 * it. */
- (void)testASubtypesPartIsTheObjectsWhereItIsOne
{
	ORMEditor *editor = [self editorOf:ORMEvents];
	ORMFormDocument *document = [self form:@"RecordEvent" of:editor];
	XCTAssertEqualObjects([document.fields valueForKey:@"elementName"],
	                      (@[ @"id", @"isA", @"vehicle", @"moment", @"place", @"litres" ]), @"%@", document.notes);
	XCTAssertEqualObjects([document fieldNamed:@"place"].subtypeEntity, @"Trip");
	XCTAssertEqualObjects([document fieldNamed:@"litres"].schemaType, @"xsd:decimal", @"the fill-up's own attribute");
	NSXMLDocument *xforms = [document document];
	NSXMLNode *place = [[self nodes:@"//*[local-name()='bind'][@ref='place']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"relevant" of:place], @"(../isA = 'Trip')");
	XCTAssertEqualObjects([self attribute:@"required" of:place], @"true()", @"a trip's, where it is one");
	XCTAssertEqual([[self nodes:@"//*[local-name()='select1'][*[local-name()='label']='Kind']/*[local-name()='item']" in:xforms] count], 2u);

	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	ORMFormElement *kind = [form elementNamed:@"isA"];
	XCTAssertEqualObjects(kind.kind, @"subtype");
	XCTAssertEqualObjects(kind.items, (@[ @"Trip", @"FillUp" ]));
	XCTAssertEqualObjects(kind.itemLabels, (@[ @"Trip", @"Fill up" ]), @"said as a reader does");
	XCTAssertEqualObjects([kind labelOfItem:@"FillUp"], @"Fill up");
	XCTAssertEqual([[self nodes:@"//*[local-name()='select1']/*[local-name()='item'][*[local-name()='label']='Fill up'][*[local-name()='value']='FillUp']"
	                         in:[document document]] count], 1u, @"the XForms item");
	XCTAssertEqualObjects([form elementNamed:@"litres"].subtype, @"FillUp");
	NSManagedObjectContext *context = [self contextOf:editor];
	NSManagedObject *van = [self insert:@"Vehicle" values:@{ @"id" : [NSUUID UUID] } in:context];
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	NSString *vanKey = [[van valueForKey:@"id"] UUIDString];

	/* A trip: its place, not the fill-up's litres. */
	NSMutableDictionary *trip = [[form instanceGiven:@{ @"vehicle" : vanKey }] mutableCopy];
	[trip addEntriesFromDictionary:@{ @"isA" : @"Trip", @"moment" : @"2026-11-11T08:00:00Z", @"place" : @"Almaty", @"litres" : @"40" }];
	NSDictionary *errors = nil;
	NSManagedObject *made = [form save:trip inContext:context errors:&errors error:&error];
	XCTAssertNotNil(made, @"%@ %@", errors, error);
	XCTAssertEqualObjects([[made entity] name], @"Trip");
	XCTAssertEqualObjects([made valueForKey:@"place"], @"Almaty");
	NSDictionary *read = [form readKey:[[made valueForKey:@"id"] UUIDString] inContext:context error:&error];
	XCTAssertEqualObjects([read objectForKey:@"isA"], @"Trip", @"%@", error);
	XCTAssertEqualObjects([read objectForKey:@"place"], @"Almaty");
	XCTAssertEqualObjects([read objectForKey:@"litres"], @"", @"a trip has none");

	/* It stays a trip. */
	NSMutableDictionary *changed = [read mutableCopy];
	[changed setObject:@"FillUp" forKey:@"isA"];
	XCTAssertNil([form save:changed inContext:context errors:&errors error:&error]);
	XCTAssertNotNil([errors objectForKey:@"isA"], @"%@", errors);

	/* To the service: a fill-up, named so. */
	NSMutableDictionary *fillUp = [[form instanceGiven:@{ @"vehicle" : vanKey }] mutableCopy];
	[fillUp addEntriesFromDictionary:@{ @"isA" : @"FillUp", @"moment" : @"2026-11-11T09:00:00Z", @"place" : @"Almaty", @"litres" : @"40" }];
	ORMFormRequest *post = [form saveRequestFor:fillUp original:nil etag:nil model:[[context persistentStoreCoordinator] managedObjectModel]
	                                     error:&error];
	XCTAssertTrue([[post.body objectForKey:@"@odata.type"] hasSuffix:@"FillUp"], @"%@ %@", post.body, error);
	XCTAssertFalse([[post.body allValues] containsObject:@"Almaty"], @"a fill-up's own only: %@", post.body);
}

#pragma mark The definition

/* FORMS.md's definition, each rule: the fill-up model with a vehicle's
 * plate (its key), colour and seats, and a form of each outline after. */
static NSString *const ORMVehicleFacts = @"Plate is a value type.\n"
                                         @"Vehicle has Plate\n"
                                         @"Each Vehicle has exactly one Plate.\n"
                                         @"For each Plate, at most one Vehicle has that Plate.\n"
                                         @"Colour is a value type.\n"
                                         @"Vehicle has Colour\n"
                                         @"Each Vehicle has at most one Colour.\n"
                                         @"Seats is a value type.\n"
                                         @"Portable data type: Numeric: Decimal(5, 0)\n"
                                         @"Vehicle has Seats\n"
                                         @"Each Vehicle has at most one Seats.\n";

/* The fill-up model, the vehicle's facts, and the form; the definition of
 * the form named. */
- (ORMFormDefinition *)definitionOf:(NSString *)name outline:(NSString *)outline editor:(ORMEditor **)made
{
	NSString *text = [ORMFillUps stringByReplacingOccurrencesOfString:@"\n\nQuery RecordFillUp:"
	                                                       withString:[NSString stringWithFormat:@"\n%@\nQuery %@:\nForm %@:\n%@\n"
	                                                                                             @"Query RecordFillUp:",
	                                                                                             ORMVehicleFacts, name, name,
	                                                                                             outline]];
	XCTAssertNotEqualObjects(text, ORMFillUps);
	ORMEditor *editor = [self newEditor];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	if (made != NULL) {
		*made = editor;
	}
	for (ORMQuery *query in [ORMQuery queriesInModel:editor.model]) {
		if ([query.name isEqualToString:name]) {
			return [ORMFormDefinition definitionOfForm:query model:editor.model mapping:nil];
		}
	}
	XCTFail(@"no form %@", name);
	return nil;
}

/* Each node and unary step and its rule, in outline order. */
- (NSArray<NSString *> *)rulesOf:(ORMFormDefinition *)definition
{
	NSMutableArray *rules = [NSMutableArray array];
	for (ORMQueryNode *node in [definition.form nodes]) {
		[rules addObject:[NSString stringWithFormat:@"%@ %@", [node designation], [definition ruleOf:node.identifier]]];
		for (ORMQueryStep *step in node.steps) {
			NSString *rule = [definition ruleOf:step.identifier];
			if (rule != nil) {
				NSString *name = [step.factType isUnary] ? [step.factType displayText]
				                                         : [[[step.nodes firstObject] designation] stringByAppendingString:@" step"];
				[rules addObject:[NSString stringWithFormat:@"%@ %@", name, rule]];
			}
		}
	}
	return rules;
}

/* FORMS.md's RecordFillUp, each node by its rule: well formed. */
- (void)testEachNodeOfAFormHasItsRule
{
	ORMEditor *editor = [self fillUps];
	ORMFormDefinition *definition = [ORMFormDefinition definitionOfForm:[self formIn:editor.model] model:editor.model mapping:nil];
	XCTAssertEqualObjects([definition.problems valueForKey:@"text"], @[]);
	XCTAssertEqualObjects([self rulesOf:definition], (@[
		@"FillUp D1", @"FillUp filled the tank D10", @"Vehicle1 D2", @"Moment D3", @"Distance D11", @"Volume D11",
		@"Quantity path", @"Fuel D4", @"Station D4", @"Money1 D11", @"Amount path", @"Money2 D11", @"User D4",
		@"Vehicle1 D5", @"PricePerUnit D13",
	]));
}

/* A choice's entered values identify it where they are one of its keys
 * (D6), the plate; a colour identifies a set of vehicles at best (E1). */
- (void)testAChoiceIsIdentifiedByItsKeyOnly
{
	ORMEditor *editor = nil;
	ORMFormDefinition *byPlate = [self definitionOf:@"ByPlate" outline:@"FillUp\n  + is of Vehicle (entered)\n    + has Plate (entered)\n"
	                                         editor:&editor];
	XCTAssertEqualObjects([byPlate.problems valueForKey:@"text"], @[]);
	XCTAssertEqualObjects([self rulesOf:byPlate], (@[ @"FillUp D1", @"Vehicle D4", @"Plate D6" ]));
	ORMFormDefinition *byColour = [self definitionOf:@"ByColour" outline:@"FillUp\n  + is of Vehicle (entered)\n    + has Colour (entered)\n"
	                                          editor:&editor];
	XCTAssertEqualObjects([byColour.problems valueForKey:@"text"], (@[
		@"E1: Colour: entered beneath Vehicle, the object chosen, but not exactly the values of one of its uniqueness "
		@"constraints: they identify a set of Vehicle at best, not one."
	]));
	NSString *reason = nil;
	XCTAssertNil([ORMFormDocument documentForForm:byColour.form model:editor.model mapping:nil reason:&reason]);
	XCTAssertTrue([reason hasPrefix:@"The outline is no form. E1: Colour: "], @"%@", reason);
}

/* E2-E6, each where it is drawn; an aggregate over rows is D14. */
- (void)testWhatIsNoFormIsSaidByItsRule
{
	NSDictionary *outlines = @{
		@"E2" : @"FillUp\n  + is of Vehicle1 = ?\n    + has Colour (entered)\n",
		@"E3" : @"User\n  + drives Vehicle = ?\n",
		@"E4" : @"User\n  + drives Vehicle (shown)\n    + has Seats (shown)\n  Most = Seats (shown)\n",
		@"E5" : @"FillUp\n  + had driver User (entered)\n    + drives Vehicle\n      + has Seats\n  Seated = Seats (shown)\n",
		@"E6" : @"FillUp\n  + was at Moment (entered)\n  + was at Station\n",
	};
	NSDictionary *said = @{
		@"E2" : @"E2: Colour: entered beneath Vehicle1, an object the form refers to and does not make or change.",
		@"E3" : @"E3: Vehicle: given beneath a step to many: a parameter is one value, not one per row.",
		@"E4" : @"E4: Most: computed with Seats, one of many, outside an aggregate (count, total, avg, max, min).",
		@"E5" : @"E5: Seated: computed with Seats, a condition on the choice User, which is not read.",
		@"E6" : @"E6: Station: neither entered, shown nor given, leading to nothing that is, and no condition on a choice.",
	};
	for (NSString *rule in [[outlines allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		ORMFormDefinition *definition = [self definitionOf:rule outline:[outlines objectForKey:rule] editor:NULL];
		XCTAssertEqualObjects([definition.problems valueForKey:@"text"], @[ [said objectForKey:rule] ], @"%@", rule);
	}
	ORMFormDefinition *total = [self definitionOf:@"Total"
	                                      outline:@"User\n  + drives Vehicle (shown)\n    + has Seats (shown)\n"
	                                              @"  Most = max(Seats) for User (shown)\n"
	                                       editor:NULL];
	XCTAssertEqualObjects([total.problems valueForKey:@"text"], @[]);
	XCTAssertEqualObjects([self rulesOf:total], (@[ @"User D1", @"Vehicle step D9", @"Vehicle D7", @"Seats D7", @"Most D14" ]));
}

#pragma mark Beneath a choice

/* An order placed for a customer found by email (D6), the customer's name
 * shown as the customer found has it (D7 beneath the choice). */
static NSString *const ORMCustomerOrders = @"Customer is an entity type.\n"
                                   @"Reference Mode: .id\n"
                                   @"Portable data type: Other: Object ID\n"
                                   @"Order is an entity type.\n"
                                   @"Reference Mode: .number\n"
                                   @"CustomerName is a value type.\n"
                                   @"Email is a value type.\n"
                                   @"Day is a value type.\n"
                                   @"Portable data type: Temporal: Date\n"
                                   @"Customer has CustomerName\n"
                                   @"Each Customer has exactly one CustomerName.\n"
                                   @"Customer has Email\n"
                                   @"Each Customer has at most one Email.\n"
                                   @"For each Email, at most one Customer has that Email.\n"
                                   @"Order is for Customer\n"
                                   @"Each Order is for exactly one Customer.\n"
                                   @"Order was placed on Day\n"
                                   @"Each Order was placed on exactly one Day.\n"
                                   @"\n"
                                   @"Query PlaceOrder:\n"
                                   @"Form PlaceOrder:\n"
                                   @"Order\n"
                                   @"  + is for Customer (entered)\n"
                                   @"    + has Email (entered)\n"
                                   @"    + has CustomerName (shown)\n"
                                   @"  + was placed on Day (entered)\n";

- (void)testAChoiceFoundByItsKeyIsTheOrdersCustomer
{
	ORMEditor *editor = [self editorOf:ORMCustomerOrders];
	ORMFormDocument *document = [self form:@"PlaceOrder" of:editor];
	XCTAssertEqualObjects([document.fields valueForKey:@"elementName"],
	                      (@[ @"number", @"customer", @"customerEmail", @"customerCustomerName", @"day" ]), @"%@", document.notes);
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	XCTAssertEqualObjects([form elementNamed:@"customer"].role, @"identified");
	XCTAssertEqualObjects([form elementNamed:@"customerEmail"].role, @"entered");
	XCTAssertEqualObjects([form elementNamed:@"customerEmail"].identifies, @"customer");
	XCTAssertFalse([form elementNamed:@"customerEmail"].written, @"the customer's, not the order's");
	XCTAssertEqualObjects([form elementNamed:@"customerCustomerName"].role, @"shown");
	XCTAssertEqualObjects([form choiceNames], @[], @"found, not chosen from a list");
	XCTAssertEqualObjects([form identifiedNames], @[ @"customer" ]);
	XCTAssertEqualObjects([[document identifyPlanNamed:@"customer"] text], @"read Customer\nwhere email = $customerEmail\nlist self (id)");
	NSXMLDocument *xforms = [document document];
	XCTAssertEqual([[self nodes:@"//*[local-name()='select1'][@bind='bind-customer']" in:xforms] count], 0u);
	XCTAssertEqual([[self nodes:@"//*[local-name()='input'][contains(@bind, 'bind-')]/*[local-name()='label'][.='Email']" in:xforms] count], 1u,
	               @"%@", [xforms XMLStringWithOptions:NSXMLNodePrettyPrint]);
	NSXMLNode *email = [[self nodes:@"//*[local-name()='bind'][@ref='customerEmail']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"required" of:email], @"true()", @"an order is for a customer");
	NSXMLNode *customer = [[self nodes:@"//*[local-name()='bind'][@ref='customer']" in:xforms] firstObject];
	XCTAssertNil([self attribute:@"required" of:customer], @"found by the app, not entered");

	NSManagedObjectContext *context = [self contextOf:editor];
	NSManagedObject *ann = [self insert:@"Customer" values:@{ @"id" : [NSUUID UUID], @"customerName" : @"Ann", @"email" : @"ann@example.com" }
	                                 in:context];
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form given:@{}];
	[session useContext:context saving:nil];
	XCTAssertTrue([session open:&error], @"%@", error);
	[session setValue:@"ann@example.com" forElement:@"customerEmail"];
	XCTAssertEqualObjects([session valueForElement:@"customer"], [[ann valueForKey:@"id"] UUIDString], @"found as it is entered");
	XCTAssertEqualObjects([session valueForElement:@"customerCustomerName"], @"Ann", @"and shown");
	[session setValue:@"2026-11-12" forElement:@"day"];
	XCTAssertTrue([session save:&error], @"%@ %@", session.errors, error);
	NSDictionary *read = [form readKey:session.savedKey inContext:context error:&error];
	XCTAssertEqualObjects([read objectForKey:@"customerEmail"], @"ann@example.com", @"%@", error);
	XCTAssertEqualObjects([read objectForKey:@"customerCustomerName"], @"Ann");

	/* No customer has the email: refused at it. */
	ORMFormSession *unknown = [[ORMFormSession alloc] initWithForm:form given:@{}];
	[unknown useContext:context saving:nil];
	XCTAssertTrue([unknown open:&error], @"%@", error);
	[unknown setValue:@"bob@example.com" forElement:@"customerEmail"];
	[unknown setValue:@"2026-11-12" forElement:@"day"];
	XCTAssertEqualObjects([unknown valueForElement:@"customer"], @"", @"none found");
	XCTAssertFalse([unknown save:&error], @"%@", [unknown values]);
	XCTAssertEqualObjects([unknown.errors objectForKey:@"customerEmail"], @"There is no Customer with that Email.", @"%@", unknown.errors);

	/* The service is asked for the customer of the email. */
	ORMQueryOData *find = [form identifyRequestNamed:@"customer" values:@{ @"customerEmail" : @"ann@example.com" }
	                                           model:[[context persistentStoreCoordinator] managedObjectModel] error:&error];
	XCTAssertTrue([[find queryText] rangeOfString:@"Email eq 'ann@example.com'"].location != NSNotFound, @"%@ %@", [find queryText], error);
}

#pragma mark Beyond the anchor

/* The Beyond model, its contacts verified and given a limit, its orders a
 * total, some of its suppliers local, with a tax number. */
- (ORMEditor *)beyondFurther
{
	NSString *facts = @"Amount is a value type.\n"
	                  @"Portable data type: Numeric: Decimal(19, 4)\n"
	                  @"Currency is an entity type.\n"
	                  @"Reference Mode: .code\n"
	                  @"The possible values of Currency are 'EUR', 'KZT'.\n"
	                  @"Money is an entity type.\n"
	                  @"Money has Amount\n"
	                  @"Each Money has exactly one Amount.\n"
	                  @"Money is in Currency\n"
	                  @"Each Money is in exactly one Currency.\n"
	                  @"For each Amount and Currency, at most one Money has that Amount and is in that Currency.\n"
	                  @"This association with Amount and Currency provides the preferred identification scheme for Money.\n"
	                  @"TaxNumber is a value type.\n"
	                  @"LocalSupplier is an entity type.\n"
	                  @"Each LocalSupplier is a Supplier.\n"
	                  @"LocalSupplier has TaxNumber\n"
	                  @"Each LocalSupplier has exactly one TaxNumber.\n"
	                  @"Contact is verified\n"
	                  @"Contact may spend Money\n"
	                  @"Each Contact may spend at most one Money.\n"
	                  @"PurchaseOrder totals Money\n"
	                  @"Each PurchaseOrder totals at most one Money.\n";
	NSString *forms = @"\n"
	                  @"Query VerifiedCustomer:\n"
	                  @"Form VerifiedCustomer:\n"
	                  @"Customer\n"
	                  @"  + is of Catalog = ?\n"
	                  @"  + is of Contact\n"
	                  @"    + has ContactName (entered)\n"
	                  @"    + is verified (entered)\n"
	                  @"    + may spend Money (entered)\n"
	                  @"\n"
	                  @"Query ReceiveLocally:\n"
	                  @"Form ReceiveLocally:\n"
	                  @"Receipt\n"
	                  @"  + is of PurchaseOrder = ?\n"
	                  @"    + totals Money (shown)\n"
	                  @"    + is from Supplier\n"
	                  @"      + is LocalSupplier\n"
	                  @"        + has TaxNumber (shown)\n"
	                  @"  + was received on Day (entered)\n";
	NSString *text = [[ORMBeyond stringByReplacingOccurrencesOfString:@"\n\nQuery ReceiveFromSupplier:"
	                                                       withString:[NSString stringWithFormat:@"\n%@\nQuery ReceiveFromSupplier:", facts]]
	                     stringByAppendingString:forms];
	return [self editorOf:text];
}

/* An owned object's flag (D10) and compound (D11): elements of its group,
 * written into it with the anchor. */
- (void)testAnOwnedObjectsFlagAndCompoundAreItsOwn
{
	ORMEditor *editor = [self beyondFurther];
	ORMFormDocument *document = [self form:@"VerifiedCustomer" of:editor];
	NSArray *names = [document.fields valueForKey:@"elementName"];
	XCTAssertEqual([names count], 6u, @"%@ %@", names, document.notes);
	for (ORMFormField *field in document.fields) {
		if (![@[ @"id", @"catalog" ] containsObject:field.elementName]) {
			XCTAssertEqualObjects(field.groupName, @"contact", @"%@", field.elementName);
		}
	}
	NSString *flag = nil, *amount = nil, *currency = nil;
	for (ORMFormField *field in document.fields) {
		flag = [field.schemaType isEqualToString:@"xsd:boolean"] ? field.elementName : flag;
		amount = [field.elementName hasSuffix:@"Amount"] ? field.elementName : amount;
		currency = [field.elementName hasSuffix:@"Currency"] ? field.elementName : currency;
	}
	XCTAssertNotNil(flag, @"%@", names);
	XCTAssertNotNil(amount, @"%@", names);
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	XCTAssertTrue([form elementNamed:flag].written);
	XCTAssertEqualObjects([form elementNamed:flag].role, @"entered");
	NSManagedObjectContext *context = [self contextOf:editor];
	[self insert:@"Catalog" values:@{ @"code" : @"GAR" } in:context];
	[self insert:@"Currency" values:@{ @"code" : @"KZT" } in:context];
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	NSMutableDictionary *instance = [[form instanceGiven:@{ @"catalog" : @"GAR" }] mutableCopy];
	[instance addEntriesFromDictionary:@{ @"contact/contactName" : @"Ann's Garage", flag : @"true", amount : @"500", currency : @"KZT" }];
	NSDictionary *errors = nil;
	NSManagedObject *customer = [form save:instance inContext:context errors:&errors error:&error];
	XCTAssertNotNil(customer, @"%@ %@", errors, error);
	NSDictionary *read = [form readKey:[[customer valueForKey:@"id"] UUIDString] inContext:context error:&error];
	XCTAssertEqualObjects([read objectForKey:flag], @"true", @"%@ %@", read, error);
	XCTAssertEqualObjects([read objectForKey:currency], @"KZT", @"%@", read);
	XCTAssertTrue([[read objectForKey:amount] hasPrefix:@"500"], @"%@", read);
}

/* Through the order given: its total, a compound shown (D11), and its
 * supplier's tax number where the supplier is a local one (D12). */
- (void)testWhatIsShownThroughAReferenceMayBeACompoundOrASubtypes
{
	ORMEditor *editor = [self beyondFurther];
	ORMFormDocument *document = [self form:@"ReceiveLocally" of:editor];
	NSArray *names = [document.fields valueForKey:@"elementName"];
	XCTAssertEqual([names count], 6u, @"%@ %@", names, document.notes);
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	NSString *tax = nil, *amount = nil;
	for (ORMFormField *field in document.fields) {
		tax = [field.elementName hasSuffix:@"TaxNumber"] ? field.elementName : tax;
		amount = [field.elementName hasSuffix:@"Amount"] ? field.elementName : amount;
		if (![@[ @"id", @"purchaseOrder", @"day" ] containsObject:field.elementName]) {
			XCTAssertEqualObjects([form elementNamed:field.elementName].role, @"shown", @"%@", field.elementName);
			XCTAssertTrue(field.isThrough, @"%@", field.elementName);
		}
	}
	NSManagedObjectContext *context = [self contextOf:editor];
	NSManagedObject *contact = [self insert:@"Contact" values:@{ @"id" : [NSUUID UUID], @"contactName" : @"Acme Parts", @"isVerified" : @NO }
	                                     in:context];
	NSManagedObject *local = [self insert:@"LocalSupplier" values:@{ @"id" : [NSUUID UUID], @"contact" : contact, @"taxNumber" : @"KZ-7" }
	                                   in:context];
	NSManagedObject *order = [self insert:@"PurchaseOrder" values:@{ @"number" : @7, @"supplier" : local } in:context];
	for (ORMFormField *field in document.fields) {
		if ([field.elementName hasSuffix:@"Amount"] || [field.elementName hasSuffix:@"Currency"]) {
			id value = [field.elementName hasSuffix:@"Amount"] ? (id)[NSDecimalNumber decimalNumberWithString:@"120"]
			                                                  : [self insert:@"Currency" values:@{ @"code" : @"EUR" } in:context];
			[order setValue:value forKey:[field.keys lastObject]];
		}
	}
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	NSDictionary *through = [form throughValuesOf:@{ @"purchaseOrder" : @"7" } inContext:context];
	XCTAssertEqualObjects([through objectForKey:tax], @"KZ-7", @"%@", through);
	XCTAssertTrue([[through objectForKey:amount] hasPrefix:@"120"], @"%@", through);
	ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form given:@{ @"purchaseOrder" : @"7" }];
	[session useContext:context saving:nil];
	XCTAssertTrue([session open:&error], @"%@", error);
	[session setValue:@"2026-11-12" forElement:@"day"];
	XCTAssertTrue([session save:&error], @"%@ %@", session.errors, error);
	NSDictionary *read = [form readKey:session.savedKey inContext:context error:&error];
	XCTAssertEqualObjects([read objectForKey:tax], @"KZ-7", @"read with the receipt: %@ %@", read, error);
}

#pragma mark Rows in the document

/* The order's lines in the XForms document: rows of the instance, each
 * bound and shown in an xf:repeat, added from a template and removed. */
- (void)testARepeatIsAnXFormsRepeat
{
	ORMEditor *editor = [self orders];
	ORMFormDocument *document = [self receiveGoodsOf:editor];
	ORMFormDocument *lines = [document.repeats objectForKey:@"purchaseLines"];
	NSXMLDocument *xforms = [document document];
	NSString *pretty = [xforms XMLStringWithOptions:NSXMLNodePrettyPrint];
	XCTAssertEqual([[self nodes:@"//*[local-name()='instance'][@id='row-purchaseLines']/*[local-name()='purchaseLines']/*[local-name()='quantity']" in:xforms] count], 1u, @"%@", pretty);
	XCTAssertEqual([[self nodes:@"//*[local-name()='instance'][@id='form']/*/*[local-name()='purchaseLines']" in:xforms] count], 0u, @"a new order: no rows");
	XCTAssertEqual([[self nodes:@"//*[local-name()='bind'][@ref='purchaseLines/quantity']" in:xforms] count], 1u, @"%@", pretty);
	NSString *quantity = [[lines fieldNamed:@"quantity"] fieldId];
	NSString *input = [NSString stringWithFormat:@"//*[local-name()='repeat'][@id='repeat-purchaseLines'][@nodeset='purchaseLines']//*[local-name()='input'][@bind='bind-%@']", quantity];
	XCTAssertEqual([[self nodes:input in:xforms] count], 1u, @"%@", pretty);
	XCTAssertEqual([[self nodes:@"//*[local-name()='repeat'][@id='repeat-purchaseLines']//*[local-name()='select1'][*[local-name()='itemset'][@nodeset=\"instance('choices-purchaseLines-stockItem')/*\"]]" in:xforms] count], 1u,
	               @"a line's item chosen from its own choices: %@", pretty);
	XCTAssertEqual([[self nodes:@"//*[local-name()='instance'][@id='choices-purchaseLines-stockItem']" in:xforms] count], 1u);
	XCTAssertEqual([[self nodes:@"//*[local-name()='submission'][@resource='form:choices/purchaseLines/stockItem']" in:xforms] count], 1u);
	NSXMLNode *insert = [[self nodes:@"//*[local-name()='trigger'][@id='control-add-purchaseLines']/*[local-name()='insert']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"origin" of:insert], @"instance('row-purchaseLines')/purchaseLines", @"%@", pretty);
	XCTAssertEqualObjects([self attribute:@"nodeset" of:insert], @"purchaseLines");
	XCTAssertEqual([[self nodes:@"//*[local-name()='repeat'][@id='repeat-purchaseLines']//*[local-name()='delete'][@nodeset='.']" in:xforms] count], 1u);
	NSString *link = [NSString stringWithFormat:@"//*[local-name()='repeat']//*[@bind='bind-%@']", [[lines fieldNamed:lines.linkElement] fieldId]];
	XCTAssertEqual([[self nodes:link in:xforms] count], 0u, @"the link is the app's");
}

/* Aggregates over the order's lines (D14): calculated in the document over
 * the rows, and worked out by ORMRuntime from the rows it has. */
- (void)testAnAggregateOverRowsIsCalculated
{
	NSString *text = [ORMOrders stringByAppendingString:@"\n"
	                                                    @"Query CountGoods:\n"
	                                                    @"Form CountGoods:\n"
	                                                    @"PurchaseOrder\n"
	                                                    @"  + PurchaseLine is in that PurchaseOrder\n"
	                                                    @"    + is of StockItem (entered)\n"
	                                                    @"    + wants Quantity (entered)\n"
	                                                    @"  Wanted = total(Quantity) for PurchaseOrder (shown)\n"
	                                                    @"  Most = max(Quantity) for PurchaseOrder (shown)\n"
	                                                    @"  Lines: Quantity = count(Quantity) for PurchaseOrder (shown)\n"];
	ORMEditor *editor = [self editorOf:text];
	ORMFormDocument *document = [self form:@"CountGoods" of:editor];
	XCTAssertEqualObjects([document.fields valueForKey:@"elementName"], (@[ @"number", @"wanted", @"most", @"lines" ]), @"%@", document.notes);
	NSXMLDocument *xforms = [document document];
	NSXMLNode *wanted = [[self nodes:@"//*[local-name()='bind'][@ref='wanted']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"calculate" of:wanted], @"sum(../purchaseLines/quantity[. != ''])");
	NSXMLNode *most = [[self nodes:@"//*[local-name()='bind'][@ref='most']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"calculate" of:most],
	                      @"choose(count(../purchaseLines/quantity[. != '']) > 0, max(../purchaseLines/quantity[. != '']), '')");
	NSXMLNode *count = [[self nodes:@"//*[local-name()='bind'][@ref='lines']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"calculate" of:count], @"count(../purchaseLines/quantity[. != ''])");

	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	NSDictionary *empty = [form instanceGiven:@{}];
	XCTAssertEqualObjects([empty objectForKey:@"wanted"], @"0", @"%@", empty);
	XCTAssertEqualObjects([empty objectForKey:@"lines"], @"0");
	XCTAssertEqualObjects([empty objectForKey:@"most"], @"");
	ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form given:@{}];
	[session setRows:@[ @{ @"stockItem" : @"OIL", @"quantity" : @"4" }, @{ @"stockItem" : @"FILTER", @"quantity" : @"2.5" },
	                    @{ @"stockItem" : @"WIPER", @"quantity" : @"" } ]
	       forRepeat:@"purchaseLines"];
	XCTAssertEqualObjects([session valueForElement:@"wanted"], @"6.5");
	XCTAssertEqualObjects([session valueForElement:@"most"], @"4");
	XCTAssertEqualObjects([session valueForElement:@"lines"], @"2");

	NSManagedObjectContext *context = [self contextOf:editor];
	NSManagedObject *order = [self insert:@"PurchaseOrder" values:@{ @"number" : @7 } in:context];
	NSManagedObject *oil = [self insert:@"StockItem" values:@{ @"sku" : @"OIL" } in:context];
	for (NSString *quantity in @[ @"4", @"3" ]) {
		[self insert:@"PurchaseLine" values:@{ @"id" : [NSUUID UUID], @"purchaseOrder" : order, @"stockItem" : oil,
		                                       @"quantity" : [NSDecimalNumber decimalNumberWithString:quantity] } in:context];
	}
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	NSDictionary *read = [form readKey:@"7" inContext:context error:&error];
	XCTAssertEqualObjects([read objectForKey:@"wanted"], @"7", @"%@ %@", read, error);
	XCTAssertEqualObjects([read objectForKey:@"lines"], @"2");
}

/* Rows beneath an owned object (D8): a contact's phones, written into the
 * contact made with the customer, read with it. */
- (void)testRowsBeneathAnOwnedObjectAreItsOwn
{
	NSString *facts = @"Phone is an entity type.\n"
	                  @"Reference Mode: .id\n"
	                  @"Portable data type: Other: Object ID\n"
	                  @"PhoneNumber is a value type.\n"
	                  @"Phone is of Contact\n"
	                  @"Each Phone is of exactly one Contact.\n"
	                  @"Phone has PhoneNumber\n"
	                  @"Each Phone has exactly one PhoneNumber.\n";
	NSString *text = [[ORMBeyond stringByReplacingOccurrencesOfString:@"\n\nQuery ReceiveFromSupplier:"
	                                                       withString:[NSString stringWithFormat:@"\n%@\nQuery ReceiveFromSupplier:", facts]]
	                     stringByAppendingString:@"\n"
	                                             @"Query PhoneCustomer:\n"
	                                             @"Form PhoneCustomer:\n"
	                                             @"Customer\n"
	                                             @"  + is of Catalog = ?\n"
	                                             @"  + is of Contact\n"
	                                             @"    + has ContactName (entered)\n"
	                                             @"    + Phone is of that Contact\n"
	                                             @"      + has PhoneNumber (entered)\n"];
	ORMEditor *editor = [self editorOf:text];
	ORMFormDocument *document = [self form:@"PhoneCustomer" of:editor];
	XCTAssertEqualObjects([document.repeats allKeys], @[ @"contact/phones" ], @"%@", document.notes);
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	XCTAssertFalse([form repeatNamed:@"contact/phones"].isList);
	NSXMLDocument *xforms = [document document];
	XCTAssertEqual([[self nodes:@"//*[local-name()='repeat'][@nodeset='contact/phones']" in:xforms] count], 1u);
	XCTAssertEqual([[self nodes:@"//*[local-name()='bind'][@ref='contact/phones/phoneNumber']" in:xforms] count], 1u,
	               @"%@", [xforms XMLStringWithOptions:NSXMLNodePrettyPrint]);
	NSXMLNode *insert = [[self nodes:@"//*[local-name()='insert']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"context" of:insert], @"contact");
	XCTAssertEqualObjects([self attribute:@"nodeset" of:insert], @"phones");
	XCTAssertEqualObjects([self attribute:@"origin" of:insert], @"instance('row-contact-phones')/phones");

	NSManagedObjectContext *context = [self contextOf:editor];
	[self insert:@"Catalog" values:@{ @"code" : @"GAR" } in:context];
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	NSMutableDictionary *instance = [[form instanceGiven:@{ @"catalog" : @"GAR" }] mutableCopy];
	[instance setObject:@"Ann's Garage" forKey:@"contact/contactName"];
	[instance setObject:@[ @{ @"id" : @"", @"phoneNumber" : @"+7 701 000 0001" }, @{ @"id" : @"", @"phoneNumber" : @"+7 701 000 0002" } ]
	             forKey:@"contact/phones"];
	NSDictionary *errors = nil;
	NSManagedObject *customer = [form save:instance inContext:context errors:&errors error:&error];
	XCTAssertNotNil(customer, @"%@ %@", errors, error);
	NSDictionary *read = [form readKey:[[customer valueForKey:@"id"] UUIDString] inContext:context error:&error];
	NSArray *phones = [[[read objectForKey:@"contact/phones"] valueForKey:@"phoneNumber"] sortedArrayUsingSelector:@selector(compare:)];
	XCTAssertEqualObjects(phones, (@[ @"+7 701 000 0001", @"+7 701 000 0002" ]), @"%@ %@", read, error);
	/* One taken away: gone from the contact. */
	NSMutableDictionary *changed = [read mutableCopy];
	[changed setObject:@[ [[read objectForKey:@"contact/phones"] firstObject] ] forKey:@"contact/phones"];
	XCTAssertNotNil([form save:changed inContext:context errors:&errors error:&error], @"%@ %@", errors, error);
	XCTAssertEqual([[context executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"Phone"] error:NULL] count], 1u);
}

#pragma mark Rows through the service

/* An order's lines through the model's service, ODataService over a store:
 * the order read with its lines, lines added as it is saved (a deep update,
 * a delta), changed, and taken away (removed as deleted); a new order and
 * its lines one deep insert. */
- (void)testRowsAreSavedThroughTheService
{
	ORMEditor *editor = [self orders];
	ORMForm *form = [ORMForm formWithPropertyList:[[self receiveGoodsOf:editor] tablePropertyList] error:NULL];
	NSManagedObjectContext *context = [self contextOf:editor];
	NSManagedObjectModel *model = [[context persistentStoreCoordinator] managedObjectModel];
	[self insert:@"PurchaseOrder" values:@{ @"number" : @7 } in:context];
	for (NSString *sku in @[ @"OIL", @"FILTER", @"WIPER" ]) {
		[self insert:@"StockItem" values:@{ @"sku" : sku } in:context];
	}
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	NSURL *root = [NSURL URLWithString:@"http://example.test/odata/"];
	ODataService *service = [[ODataService alloc] initWithPersistentStoreCoordinator:[context persistentStoreCoordinator] serviceRoot:root];
	ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form given:@{}];
	[session useServiceRoot:root model:model transport:service];
	session.key = @"7";
	XCTAssertTrue([session open:&error], @"%@", error);
	XCTAssertEqualObjects([session rowsOfRepeat:@"purchaseLines"], @[]);
	XCTAssertEqualObjects(([session choicesNamed:@"stockItem" inRepeat:@"purchaseLines" row:0 error:&error]),
	                      (@[ @"FILTER", @"OIL", @"WIPER" ]), @"a row's choices from the service: %@", error);
	[session setRows:@[ @{ @"id" : @"", @"stockItem" : @"OIL", @"quantity" : @"4" }, @{ @"id" : @"", @"stockItem" : @"FILTER", @"quantity" : @"2" } ]
	       forRepeat:@"purchaseLines"];
	XCTAssertTrue([session save:&error], @"%@ %@", session.errors, error);
	NSDictionary *(^quantities)(void) = ^NSDictionary *{
		NSManagedObjectContext *fresh = [[NSManagedObjectContext alloc] init];
		[fresh setPersistentStoreCoordinator:[context persistentStoreCoordinator]];
		NSMutableDictionary *found = [NSMutableDictionary dictionary];
		for (NSManagedObject *line in [fresh executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"PurchaseLine"] error:NULL]) {
			[found setObject:[[line valueForKey:@"quantity"] stringValue] forKey:[[line valueForKey:@"stockItem"] valueForKey:@"sku"]];
		}
		return found;
	};
	XCTAssertEqualObjects(quantities(), (@{ @"OIL" : @"4", @"FILTER" : @"2" }));
	NSArray *rows = [session rowsOfRepeat:@"purchaseLines"];
	XCTAssertEqual([rows count], 2u, @"read again from the service: %@", [session values]);

	/* The oil's changed, the filter's taken away, a wiper's added. */
	NSMutableArray *changed = [NSMutableArray array];
	for (NSDictionary *row in rows) {
		if ([[row objectForKey:@"stockItem"] isEqualToString:@"OIL"]) {
			NSMutableDictionary *oil = [row mutableCopy];
			[oil setObject:@"6" forKey:@"quantity"];
			[changed addObject:oil];
		}
	}
	[changed addObject:@{ @"id" : @"", @"stockItem" : @"WIPER", @"quantity" : @"1" }];
	NSDictionary *before = [session values];
	NSMutableDictionary *after = [before mutableCopy];
	[after setObject:changed forKey:@"purchaseLines"];
	ORMFormRequest *patch = [form saveRequestFor:after original:before etag:nil model:model error:&error];
	NSArray *delta = [patch.body objectForKey:@"PurchaseLines@delta"];
	XCTAssertEqual([delta count], 3u, @"%@ %@", patch.body, error);
	NSUInteger removed = 0;
	for (NSDictionary *entry in delta) {
		removed += [[[entry objectForKey:@"@removed"] objectForKey:@"reason"] isEqualToString:@"deleted"] ? 1 : 0;
	}
	XCTAssertEqual(removed, 1u, @"%@", delta);
	[session setRows:changed forRepeat:@"purchaseLines"];
	XCTAssertTrue([session save:&error], @"%@ %@", session.errors, error);
	XCTAssertEqualObjects(quantities(), (@{ @"OIL" : @"6", @"WIPER" : @"1" }), @"one save, the filter's line deleted");

	/* A new order: it and its lines, one deep insert. */
	NSMutableDictionary *fresh = [[form instanceGiven:@{}] mutableCopy];
	[fresh setObject:@"8" forKey:@"number"];
	[fresh setObject:@[ @{ @"id" : @"", @"stockItem" : @"OIL", @"quantity" : @"3" } ] forKey:@"purchaseLines"];
	ORMFormRequest *post = [form saveRequestFor:fresh original:nil etag:nil model:model error:&error];
	XCTAssertEqualObjects(post.method, @"POST", @"%@", error);
	XCTAssertEqual([[post.body objectForKey:@"PurchaseLines"] count], 1u, @"%@", post.body);
}

/* A form submitted to an action of the service's, not saved: the order's
 * lines handed to ReceiveGoods, its answer the key of what it did. */
- (void)testAFormSubmitsToAnAction
{
	ORMEditor *editor = [self orders];
	ORMFormDocument *document = [self receiveGoodsOf:editor];
	document.action = @"ReceiveGoods";
	NSXMLDocument *xforms = [document document];
	XCTAssertEqual([[self nodes:@"//*[local-name()='submission'][@id='save'][@resource='form:submit/ReceiveGoods']" in:xforms] count], 1u,
	               @"%@", [xforms XMLStringWithOptions:NSXMLNodePrettyPrint]);
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	XCTAssertEqualObjects(form.action, @"ReceiveGoods");
	NSManagedObjectContext *context = [self contextOf:editor];
	NSManagedObjectModel *model = [[context persistentStoreCoordinator] managedObjectModel];
	[self insert:@"PurchaseOrder" values:@{ @"number" : @7 } in:context];
	[self insert:@"StockItem" values:@{ @"sku" : @"OIL" } in:context];
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	NSURL *root = [NSURL URLWithString:@"http://example.test/odata/"];
	ODataService *service = [[ODataService alloc] initWithPersistentStoreCoordinator:[context persistentStoreCoordinator] serviceRoot:root];
	ORMTestReceiving *receiving = [[ORMTestReceiving alloc] init];
	service.serviceOperations = receiving;
	XCTAssertEqualObjects(service.operationProblems, @[]);
	ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form given:@{}];
	[session useServiceRoot:root model:model transport:service];
	session.key = @"7";
	XCTAssertTrue([session open:&error], @"%@", error);
	[session setRows:@[ @{ @"id" : @"", @"stockItem" : @"OIL", @"quantity" : @"4" } ] forRepeat:@"purchaseLines"];
	XCTAssertTrue([session save:&error], @"%@ %@", session.errors, error);
	XCTAssertEqualObjects(session.savedKey, @"7");
	XCTAssertEqualObjects([[receiving.received objectForKey:@"Number"] description], @"7", @"%@", receiving.received);
	XCTAssertEqual([[receiving.received objectForKey:@"PurchaseLines"] count], 1u, @"the lines with it: %@", receiving.received);
	NSManagedObjectContext *fresh = [[NSManagedObjectContext alloc] init];
	[fresh setPersistentStoreCoordinator:[context persistentStoreCoordinator]];
	XCTAssertEqual([[fresh executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:@"PurchaseLine"] error:NULL] count], 0u,
	               @"submitted, not saved: the action's to do");
}

#pragma mark Rules and derivations as binds

/* The fill-up model with a rule (no fill-up of more than 200) and a
 * derivation (a fill-up's unit price, its cost by its volume), and a form
 * of each outline after. */
- (ORMEditor *)fillUpsRuledWith:(NSString *)forms
{
	NSString *facts = @"UnitPrice is a value type.\n"
	                  @"Portable data type: Numeric: Decimal(19, 4)\n"
	                  @"FillUp has UnitPrice\n"
	                  @"Each FillUp has at most one UnitPrice.\n";
	NSString *queries = @"Query TooMuch:\n"
	                    @"It is impossible that:\n"
	                    @"FillUp\n"
	                    @"  + was of Volume\n"
	                    @"    + has Quantity > 200\n"
	                    @"\n"
	                    @"Query UnitPriceOf:\n"
	                    @"Derivation of \"FillUp has UnitPrice\":\n"
	                    @"FillUp (shown)\n"
	                    @"  + cost Money\n"
	                    @"    + has Amount\n"
	                    @"  + was of Volume\n"
	                    @"    + has Quantity\n"
	                    @"  Price: UnitPrice = Amount / Quantity (shown)\n"
	                    @"\n";
	NSString *text = [ORMFillUps stringByReplacingOccurrencesOfString:@"\n\nQuery RecordFillUp:"
	                                                       withString:[NSString stringWithFormat:@"\n%@\n%@Query RecordFillUp:", facts, queries]];
	return [self editorOf:[text stringByAppendingFormat:@"\n%@", forms]];
}

/* A rule over the form's own values, a bind: the volume entered is checked
 * as it is entered, said in the rule's words, and no longer left to where
 * the form is submitted. */
- (void)testARuleOverTheFormsValuesIsABind
{
	ORMEditor *editor = [self fillUpsRuledWith:@""];
	ORMFormDocument *document = [self documentOf:editor];
	XCTAssertFalse([[document.checkedWhereSubmitted componentsJoinedByString:@"\n"] rangeOfString:@"200"].location != NSNotFound,
	               @"%@", document.checkedWhereSubmitted);
	NSXMLDocument *xforms = [document document];
	NSXMLNode *quantity = [[self nodes:@"//*[local-name()='bind'][@ref='volumeQuantity']" in:xforms] firstObject];
	XCTAssertTrue([[self attribute:@"constraint" of:quantity] rangeOfString:@"not(../volumeQuantity != '' and number(../volumeQuantity) > 200)"].location != NSNotFound,
	              @"%@", [self attribute:@"constraint" of:quantity]);
	NSXMLNode *alert = [[self nodes:@"//*[@bind=//*[local-name()='bind'][@ref='volumeQuantity']/@id]/*[local-name()='alert']" in:xforms] firstObject];
	XCTAssertTrue([[alert stringValue] rangeOfString:@"200"].location != NSNotFound, @"said in the rule's words: %@", [alert stringValue]);
}

/* A derived fact type shown, calculated from the form's values as its
 * derivation says (the unit price, the cost by the volume). */
- (void)testADerivedValueShownIsCalculated
{
	ORMEditor *editor = [self fillUpsRuledWith:@"Query PricedFillUp:\n"
	                                           @"Form PricedFillUp:\n"
	                                           @"FillUp\n"
	                                           @"  + is of Vehicle = ?\n"
	                                           @"  + cost Money (entered)\n"
	                                           @"  + was of Volume (entered)\n"
	                                           @"  + has UnitPrice (shown)\n"];
	ORMFormDocument *document = [self form:@"PricedFillUp" of:editor];
	NSXMLDocument *xforms = [document document];
	NSXMLNode *price = [[self nodes:@"//*[local-name()='bind'][@ref='unitPrice']" in:xforms] firstObject];
	XCTAssertEqualObjects([self attribute:@"calculate" of:price],
	                      @"choose(../totalAmount != '' and ../volumeQuantity != '', (number(../totalAmount) div number(../volumeQuantity)), '')",
	                      @"%@ %@", [xforms XMLStringWithOptions:NSXMLNodePrettyPrint], document.notes);
	/* Read on its own, by the key: the read of the fill-up cannot take it. */
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	XCTAssertNotNil([form elementNamed:@"unitPrice"].read);
	NSManagedObjectContext *context = [self contextOf:editor];
	NSManagedObject *fill = [self insertWhole:@"FillUp" values:@{ @"totalAmount" : [NSDecimalNumber decimalNumberWithString:@"20000"],
	                                                              @"volumeQuantity" : [NSDecimalNumber decimalNumberWithString:@"40"] }
	                                       in:context];
	NSError *error = nil;
	XCTAssertTrue([context save:&error], @"%@", error);
	NSDictionary *read = [form readKey:[[fill valueForKey:@"id"] UUIDString] inContext:context error:&error];
	XCTAssertEqualObjects([read objectForKey:@"unitPrice"], @"500", @"%@ %@", read, error);
}

/* An object of the entity with the values, every other property the store
 * requires given one: an empty text, zero, now, no, a new key, a related
 * object made so in turn. */
- (NSManagedObject *)insertWhole:(NSString *)entity values:(NSDictionary *)values in:(NSManagedObjectContext *)context
{
	NSManagedObject *object = [self insert:entity values:values in:context];
	for (NSPropertyDescription *property in [[object entity] properties]) {
		if ([property isOptional] || [values objectForKey:[property name]] != nil || [property isTransient]) {
			continue;
		}
		if ([property isKindOfClass:[NSRelationshipDescription class]]) {
			NSRelationshipDescription *relationship = (NSRelationshipDescription *)property;
			if (![relationship isToMany]) {
				[object setValue:[self insertWhole:[[relationship destinationEntity] name] values:@{} in:context] forKey:[property name]];
			}
			continue;
		}
		NSAttributeType type = [(NSAttributeDescription *)property attributeType];
		id value = type == NSUUIDAttributeType ? [NSUUID UUID]
		         : type == NSStringAttributeType ? [[NSUUID UUID] UUIDString]
		         : type == NSDateAttributeType ? [NSDate date]
		         : type == NSBooleanAttributeType ? @NO
		         : type == NSDecimalAttributeType ? [NSDecimalNumber one]
		         : @1;
		[object setValue:value forKey:[property name]];
	}
	return object;
}

/* The app's words for a rule, by its name: in the document's alerts, and
 * where the store refuses it. */
- (void)testARuleIsSaidInTheAppsWords
{
	ORMEditor *editor = [self fillUpsRuledWith:@""];
	ORMFormDocument *document = [self documentOf:editor];
	document.messages = @{ @"TooMuch" : @"No tank holds that much." };
	NSXMLDocument *xforms = [document document];
	NSXMLNode *alert = [[self nodes:@"//*[@bind=//*[local-name()='bind'][@ref='volumeQuantity']/@id]/*[local-name()='alert']" in:xforms] firstObject];
	XCTAssertTrue([[alert stringValue] rangeOfString:@"No tank holds that much."].location != NSNotFound, @"%@", [alert stringValue]);
	XCTAssertFalse([[alert stringValue] rangeOfString:@"impossible"].location != NSNotFound, @"%@", [alert stringValue]);
	ORMForm *form = [ORMForm formWithPropertyList:[document tablePropertyList] error:NULL];
	NSError *refused = [NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectValidationError
	                                   userInfo:@{ NSLocalizedDescriptionKey : @"It is impossible that some FillUp ...",
	                                               NSValidationKeyErrorKey : @"volumeQuantity", @"ORMConstraint" : @"TooMuch",
	                                               @"ORMKeys" : @[ @"volumeQuantity" ] }];
	XCTAssertEqualObjects([form elementErrorsOf:refused], (@{ @"volumeQuantity" : @"No tank holds that much." }));
}

@end
