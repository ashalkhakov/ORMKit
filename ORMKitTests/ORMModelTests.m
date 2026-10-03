/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* The projection, checked against what NORMA itself derived and saved in
 * its files: the underscored attributes are NORMA's own reading of the
 * model, so ORMKit's must agree with them. */
@interface ORMModelTests : ORMTestCase
@end

static NSString *
ORMMultiplicityText(ORMMultiplicity multiplicity)
{
	return @[ @"Unspecified", @"ZeroToOne", @"ZeroToMany", @"ExactlyOne", @"OneToMany" ][multiplicity];
}

@implementation ORMModelTests

- (ORMModel *)model:(NSString *)name
{
	ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:name] reason:NULL];
	XCTAssertNotNil(model);
	return model;
}

- (void)testItReadsEveryElementOfANormaModel
{
	ORMModel *model = [self model:@"StockMate.orm"];
	XCTAssertEqualObjects(model.name, @"StockMate");
	XCTAssertEqual([model.objectTypes count], (NSUInteger)53);
	XCTAssertEqual([model.factTypes count], (NSUInteger)66);
	XCTAssertEqual([model.constraints count], (NSUInteger)185);
	XCTAssertEqual([model.dataTypes count], (NSUInteger)7);
	XCTAssertEqual([model.notes count], (NSUInteger)1);
	XCTAssertEqual([model.diagrams count], (NSUInteger)4);
}

- (void)testAModelWithoutTheRootWrapperReads
{
	ORMModel *model = [self model:@"StockMate.CoRef.orm"];
	XCTAssertEqual([model.objectTypes count], (NSUInteger)53);
	XCTAssertEqual([model.diagrams count], (NSUInteger)0);
}

- (void)testMandatoryAndMultiplicityAgreeWithNorma
{
	for (NSString *name in ORMNormaFixtures) {
		ORMModel *model = [self model:name];
		NSUInteger checked = 0;
		for (ORMFactType *fact in model.factTypes) {
			for (ORMRole *role in fact.roles) {
				NSString *mandatory = ORMAttribute(role.element, @"_IsMandatory");
				NSString *multiplicity = ORMAttribute(role.element, @"_Multiplicity");
				if (mandatory != nil) {
					XCTAssertEqual([mandatory isEqualToString:@"true"], role.isMandatory, @"%@ role %lu", fact.name,
					               (unsigned long)role.index);
					checked++;
				}
				if (multiplicity != nil) {
					XCTAssertEqualObjects(ORMMultiplicityText([role multiplicity]), multiplicity, @"%@ role %lu",
					                      fact.name, (unsigned long)role.index);
				}
			}
		}
		XCTAssertTrue(checked > 100);
	}
}

- (void)testReferenceModesAndNamesAgreeWithNorma
{
	ORMModel *model = [self model:@"StockMate.orm"];
	for (ORMObjectType *type in model.objectTypes) {
		NSString *saved = ORMAttribute(type.element, @"_ReferenceMode");
		if ([saved length] > 0) {
			XCTAssertEqualObjects(type.referenceMode, saved, @"%@", type.name);
		}
	}
	for (ORMFactType *fact in model.factTypes) {
		NSString *saved = ORMAttribute(fact.element, @"_Name");
		if (saved != nil) {
			XCTAssertEqualObjects([fact derivedName], saved);
		}
	}
	XCTAssertEqualObjects([[model objectTypeNamed:@"Product"] displayName], @"Product(.Id)");
	XCTAssertEqualObjects([[model objectTypeNamed:@"Weight"] displayName], @"Weight(kg:)");
}

- (void)testAUnaryIsABinaryWithAnImplicitBoolean
{
	ORMModel *model = [self model:@"StockMate.orm"];
	ORMFactType *enabled = nil;
	for (ORMFactType *fact in model.factTypes) {
		if ([fact.name isEqualToString:@"WarehouseIsEnabled"]) {
			enabled = fact;
		}
	}
	XCTAssertNotNil(enabled);
	XCTAssertEqual([enabled.roles count], (NSUInteger)2);
	XCTAssertEqual([enabled arity], (NSUInteger)1);
	XCTAssertTrue([enabled isUnary]);
	XCTAssertTrue([[enabled.roles lastObject] player].isImplicitBooleanValue);
	XCTAssertFalse([[model visibleObjectTypes] containsObject:[[enabled.roles lastObject] player]]);
}

- (void)testConstraintsAreReadWithTheirArguments
{
	ORMModel *model = [self model:@"StockMate.orm"];
	ORMConstraint *ring = nil;
	ORMConstraint *equality = nil;
	for (ORMConstraint *constraint in model.constraints) {
		if (constraint.kind == ORMRingConstraint) {
			ring = constraint;
		} else if (constraint.kind == ORMEqualityConstraint) {
			equality = constraint;
		}
	}
	XCTAssertEqual(ring.ringType, ORMRingAcyclic);
	XCTAssertEqual([[ring allRoles] count], (NSUInteger)2);
	XCTAssertEqual([equality.roleSequences count], (NSUInteger)2);
	ORMObjectType *street = [model objectTypeNamed:@"Street"];
	XCTAssertFalse(street.preferredIdentifier.isInternal);
	XCTAssertEqual([[street.preferredIdentifier allRoles] count], (NSUInteger)3);
	XCTAssertEqual(street.preferredIdentifier.preferredIdentifierFor, street);
}

- (void)testReadingsKeepTheirHyphenBinding
{
	ORMModel *model = [self model:@"StockMate.orm"];
	NSMutableArray *texts = [NSMutableArray array];
	for (ORMFactType *fact in model.factTypes) {
		[texts addObject:[[fact primaryReading] text] ?: @""];
	}
	XCTAssertTrue([texts containsObject:@"{0} includes first- {1}"]);
}

- (void)testDiagramsShowTheirSubjects
{
	ORMModel *model = [self model:@"StockMate.orm"];
	for (ORMDiagram *diagram in model.diagrams) {
		XCTAssertTrue([[diagram allShapes] count] > 0);
		for (ORMShape *shape in [diagram allShapes]) {
			XCTAssertNotNil(shape.subject, @"%@ in %@", shape.identifier, diagram.name);
			XCTAssertTrue(NSWidth(shape.bounds) > 0);
			if (shape.kind == ORMShapeFactType) {
				XCTAssertEqual([shape.roleDisplayOrder count], [shape.factType.roles count]);
			}
		}
	}
	ORMDiagram *products = [model.diagrams firstObject];
	XCTAssertEqualObjects(products.name, @"Products");
	XCTAssertNotNil([products shapeForSubject:[[model objectTypeNamed:@"Product"] identifier]]);
}

- (void)testValueConstraintsShowAsADiagramDoes
{
	NSString *reason = nil;
	ORMEditor *editor = [self newEditor];
	NSString *gender = [editor addValueTypeNamed:@"Gender" dataType:@"FixedLengthTextDataType" onDiagram:nil
	                                          at:NSZeroPoint reason:&reason];
	XCTAssertTrue([editor setValueConstraint:@"{'M', 'F'}" of:gender reason:&reason], @"%@", reason);
	XCTAssertEqualObjects([[[editor.model elementWithId:gender] valueConstraint] displayText], @"{'M', 'F'}");
	XCTAssertTrue([editor setValueConstraint:@"(0..100]" of:gender reason:&reason], @"%@", reason);
	XCTAssertEqualObjects([[[editor.model elementWithId:gender] valueConstraint] displayText], @"{(0..100]}");
}

@end
