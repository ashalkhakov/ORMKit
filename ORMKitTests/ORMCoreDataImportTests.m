/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* Core Data to ORM (docs/COREDATA-MAPPING.md, "Import"). */
@interface ORMCoreDataImportTests : ORMTestCase
@end

@implementation ORMCoreDataImportTests

static NSString *const ORMShopModel =
	@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
	@"<model type=\"com.apple.IDECoreDataModeler.DataModel\" documentVersion=\"1.0\">\n"
	@"  <entity name=\"Customer\" representedClassName=\"Customer\" syncable=\"YES\">\n"
	@"    <attribute name=\"email\" attributeType=\"String\" maxValueString=\"80\"/>\n"
	@"    <attribute name=\"isActive\" attributeType=\"Boolean\" usesScalarValueType=\"YES\"/>\n"
	@"    <attribute name=\"nickname\" optional=\"YES\" attributeType=\"String\"/>\n"
	@"    <relationship name=\"orders\" optional=\"YES\" toMany=\"YES\" deletionRule=\"Nullify\" destinationEntity=\"Order\" "
	@"inverseName=\"customer\" inverseEntity=\"Order\"/>\n"
	@"    <uniquenessConstraints><uniquenessConstraint><constraint value=\"email\"/></uniquenessConstraint>"
	@"</uniquenessConstraints>\n"
	@"  </entity>\n"
	@"  <entity name=\"Order\" representedClassName=\"Order\" syncable=\"YES\">\n"
	@"    <attribute name=\"number\" attributeType=\"Integer 32\" usesScalarValueType=\"YES\"/>\n"
	@"    <relationship name=\"customer\" optional=\"YES\" maxCount=\"1\" deletionRule=\"Nullify\" destinationEntity=\"Customer\" "
	@"inverseName=\"orders\" inverseEntity=\"Customer\">\n"
	@"      <userInfo><entry key=\"ormkit.mandatory\" value=\"YES\"/></userInfo>\n"
	@"    </relationship>\n"
	@"    <relationship name=\"lines\" optional=\"YES\" toMany=\"YES\" deletionRule=\"Cascade\" destinationEntity=\"Line\" "
	@"inverseName=\"order\" inverseEntity=\"Line\"/>\n"
	@"    <uniquenessConstraints><uniquenessConstraint><constraint value=\"number\"/></uniquenessConstraint>"
	@"</uniquenessConstraints>\n"
	@"  </entity>\n"
	@"  <entity name=\"Product\" representedClassName=\"Product\" syncable=\"YES\">\n"
	@"    <attribute name=\"code\" attributeType=\"String\"/>\n"
	@"    <relationship name=\"lines\" optional=\"YES\" toMany=\"YES\" deletionRule=\"Nullify\" destinationEntity=\"Line\" "
	@"inverseName=\"product\" inverseEntity=\"Line\"/>\n"
	@"    <uniquenessConstraints><uniquenessConstraint><constraint value=\"code\"/></uniquenessConstraint>"
	@"</uniquenessConstraints>\n"
	@"  </entity>\n"
	@"  <entity name=\"Line\" representedClassName=\"Line\" syncable=\"YES\">\n"
	@"    <attribute name=\"quantity\" attributeType=\"Integer 32\" usesScalarValueType=\"YES\"/>\n"
	@"    <relationship name=\"order\" optional=\"YES\" maxCount=\"1\" deletionRule=\"Nullify\" destinationEntity=\"Order\" "
	@"inverseName=\"lines\" inverseEntity=\"Order\"/>\n"
	@"    <relationship name=\"product\" optional=\"YES\" maxCount=\"1\" deletionRule=\"Nullify\" destinationEntity=\"Product\" "
	@"inverseName=\"lines\" inverseEntity=\"Product\"/>\n"
	@"    <uniquenessConstraints><uniquenessConstraint><constraint value=\"order\"/><constraint value=\"product\"/>"
	@"</uniquenessConstraint></uniquenessConstraints>\n"
	@"  </entity>\n"
	@"</model>\n";

- (ORMEditor *)imported:(ORMCDModel *)model mapping:(NSString **)mapping notes:(NSArray **)notes
{
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:@"Imported"] undoManager:nil];
	NSString *reason = nil;
	NSString *made = [editor importCoreDataModel:model path:@"/tmp/Shop.xcdatamodeld" notes:notes reason:&reason];
	XCTAssertNotNil(made, @"%@", reason);
	if (mapping != NULL) {
		*mapping = made;
	}
	return editor;
}

- (ORMCDModel *)remap:(ORMEditor *)editor mapping:(NSString *)mapping
{
	ORMCoreDataMapping *read = [ORMCoreDataMapping mappingWithId:mapping inDocument:editor.document];
	return [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:read] map];
}

- (NSSet<NSString *> *)readingsOf:(ORMModel *)model
{
	NSMutableSet *readings = [NSMutableSet set];
	for (ORMFactType *fact in model.factTypes) {
		for (ORMReadingOrder *order in fact.readingOrders) {
			for (ORMReading *reading in order.readings) {
				[readings addObject:[reading expandedText]];
			}
		}
	}
	return readings;
}

/* What a model says, property by property, to compare two. */
static NSDictionary *
ORMSignature(ORMCDModel *model)
{
	NSMutableDictionary *signature = [NSMutableDictionary dictionary];
	for (ORMCDEntity *entity in model.entities) {
		NSMutableDictionary *properties = [NSMutableDictionary dictionary];
		[properties setObject:[NSString stringWithFormat:@"parent=%@ abstract=%d", entity.parentName ?: @"-",
		                                                 entity.isAbstract]
		               forKey:@"@"];
		for (ORMCDAttribute *attribute in entity.attributes) {
			[properties setObject:[NSString stringWithFormat:@"%@ optional=%d", attribute.attributeType,
			                                                 attribute.optional]
			               forKey:attribute.name];
		}
		for (ORMCDRelationship *relationship in entity.relationships) {
			/* Xcode writes a to-one's maximum of one; the mapper leaves it
			 * out. */
			[properties setObject:[NSString stringWithFormat:@"%@ toMany=%d optional=%d inverse=%@ %lu..%lu",
			                                                 relationship.destination, relationship.toMany,
			                                                 relationship.optional, relationship.inverseName,
			                                                 (unsigned long)relationship.minCount,
			                                                 relationship.toMany ? (unsigned long)relationship.maxCount : 0ul]
			               forKey:relationship.name];
		}
		NSMutableArray *uniques = [NSMutableArray array];
		for (NSArray *names in entity.uniquenessConstraints) {
			[uniques addObject:[[names sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@"+"]];
		}
		[properties setObject:[[uniques sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "]
		               forKey:@"#unique"];
		[signature setObject:properties forKey:entity.name];
	}
	return signature;
}

- (void)testImportSaysTheModelInORM
{
	NSString *why = nil;
	ORMCDModel *shop = [ORMCDModel modelWithContentsXML:[ORMShopModel dataUsingEncoding:NSUTF8StringEncoding]
	                                             reason:&why];
	XCTAssertNotNil(shop, @"%@", why);
	NSArray *notes = nil;
	ORMEditor *editor = [self imported:shop mapping:NULL notes:&notes];
	ORMModel *model = editor.model;

	ORMObjectType *customer = [model objectTypeNamed:@"Customer"];
	XCTAssertEqualObjects(customer.referenceMode, @"email");
	XCTAssertEqual(customer.referenceModeValueType.dataTypeLength, 80);
	XCTAssertEqualObjects([[model objectTypeNamed:@"Order"] referenceMode], @"number");

	NSSet *readings = [self readingsOf:model];
	XCTAssertTrue([readings containsObject:@"Customer is active"], @"%@", readings);
	XCTAssertTrue([readings containsObject:@"Customer has Nickname"], @"%@", readings);

	/* Required in ORM, loosened for Core Data: each order is of some
	 * customer. */
	for (ORMFactType *fact in model.factTypes) {
		for (ORMRole *role in fact.roles) {
			if ([role.player.name isEqualToString:@"Order"] && [[role oppositeRole].player.name isEqualToString:@"Customer"]) {
				XCTAssertTrue(role.isMandatory);
			}
		}
	}

	/* The line joins an order and a product: an objectification. */
	ORMObjectType *line = [model objectTypeNamed:@"Line"];
	XCTAssertNotNil(line.nestedFactType);
	XCTAssertEqual([[line.nestedFactType roles] count], 2u);
	XCTAssertEqual([notes count], 0u, @"%@", notes);
	/* The new model's empty diagram holds it. */
	XCTAssertEqual([model.diagrams count], 1u);
	XCTAssertGreaterThan([[[model.diagrams firstObject] allShapes] count], 0u);
}

- (void)testImportedModelMapsBackAsItCame
{
	ORMCDModel *shop = [ORMCDModel modelWithContentsXML:[ORMShopModel dataUsingEncoding:NSUTF8StringEncoding]
	                                             reason:NULL];
	NSString *mapping = nil;
	ORMEditor *editor = [self imported:shop mapping:&mapping notes:NULL];
	XCTAssertEqualObjects(ORMSignature([self remap:editor mapping:mapping]), ORMSignature(shop));
}

/* Every example mapped to Core Data, brought back, and mapped again:
 * the same Core Data model. */
- (void)testFixturesRoundTripThroughCoreData
{
	NSMutableArray *files = [NSMutableArray arrayWithObject:@"StockMate.orm"];
	[files addObjectsFromArray:[self activeFactsFixtures]];
	for (NSString *file in files) {
		@autoreleasepool {
			ORMEditor *source = [[ORMEditor alloc] initWithDocument:[self fixtureDocument:file] undoManager:nil];
			NSString *sourceMapping = [source addCoreDataMappingNamed:@"Model" path:@"/tmp/Model.xcdatamodeld"];
			[source setStyle:ORMStyleEntities ofMapping:sourceMapping];
			ORMCDModel *first = [self remap:source mapping:sourceMapping];
			NSString *mapping = nil;
			ORMEditor *editor = [self imported:first mapping:&mapping notes:NULL];
			NSDictionary *before = ORMSignature(first);
			NSDictionary *after = ORMSignature([self remap:editor mapping:mapping]);
			XCTAssertEqualObjects(after, before, @"%@", file);
		}
	}
}

/* One step: undone, the model is as it was. */
- (void)testImportUndoesAsOneStep
{
	ORMCDModel *shop = [ORMCDModel modelWithContentsXML:[ORMShopModel dataUsingEncoding:NSUTF8StringEncoding]
	                                             reason:NULL];
	ORMEditor *editor = [self newEditor];
	NSUInteger types = [editor.model.objectTypes count];
	XCTAssertNotNil([editor importCoreDataModel:shop path:@"/tmp/Shop.xcdatamodeld" notes:NULL reason:NULL]);
	XCTAssertGreaterThan([editor.model.objectTypes count], types);
	[self.undoManager undo];
	XCTAssertEqual([editor.model.objectTypes count], types);
}

- (void)testEmptyModelIsRefused
{
	NSString *reason = nil;
	XCTAssertNil([[self newEditor] importCoreDataModel:[ORMCDModel model] path:@"/tmp/E.xcdatamodeld" notes:NULL
	                                            reason:&reason]);
	XCTAssertNotNil(reason);
}

@end
