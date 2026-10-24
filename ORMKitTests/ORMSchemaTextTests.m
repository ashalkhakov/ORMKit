/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* The model as schema text (ORMSchemaText): a listing written from the
 * model that reads back into the same model, its notes as comments; and
 * text applied to a model that has it, lines taken away by "- ". */
@interface ORMSchemaTextTests : ORMTestCase
@end

@implementation ORMSchemaTextTests

/* A schema with a bit of everything the text says. */
- (NSString *)schema
{
	return @"// Not a note: a blank line follows.\n"
	       @"\n"
	       @"# People\n"
	       @"\n"
	       @"Person is an entity type.\n"
	       @"Reference Mode: .id\n"
	       @"Portable data type: Other: Object ID\n"
	       @"// Seventeen letters and digits,\n"
	       @"// no I, O or Q.\n"
	       @"VIN is a value type.\n"
	       @"Portable data type: Text: Fixed Length(17)\n"
	       @"The possible values of VIN match the pattern '[A-HJ-NPR-Z0-9]{17}'.\n"
	       @"Year is a value type.\n"
	       @"Portable data type: Numeric: Unsigned Small Integer\n"
	       @"The possible values of Year are at least 1886.\n"
	       @"Unit is an entity type.\n"
	       @"Reference Mode: .code\n"
	       @"Factor is a value type.\n"
	       @"Portable data type: Numeric: Decimal(19, 8)\n"
	       @"Unit is worth Factor\n"
	       @"Each Unit is worth exactly one Factor.\n"
	       @"Reference data: km, 1\n"
	       @"Reference data: 'gal (US)', 3.785411784\n"
	       @"\n"
	       @"# Cars\n"
	       @"\n"
	       @"Car is an entity type.\n"
	       @"Reference Mode: .id\n"
	       @"Car (as OwnedCar) is owned by Person (as Owner) / Person owns Car\n"
	       @"Each Car is owned by exactly one Person.\n"
	       @"// Who may drive it.\n"
	       @"Permit is where Person drives Car.\n"
	       @"+ An owner drives the cars they own; others are entered.\n"
	       @"Car has VIN\n"
	       @"Each Car has at most one VIN.\n"
	       @"Car was built in Year\n"
	       @"Fact Type Name: BuildYear\n"
	       @"Each Car was built in exactly one Year.\n"
	       @"Each OldCar is by definition a Car that was built in some Year.\n"
	       @"// One with a driver is owned.\n"
	       @"If some Person drives some Car then some Person owns that Car.\n"
	       @"\n"
	       @"// The cars and their owners.\n"
	       @"Query Owners:\n"
	       @"✓Car\n"
	       @"  + is owned by ✓Person\n";
}

- (ORMEditor *)built
{
	ORMEditor *editor = [self newEditor];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:[self schema] failures:&failures], @"%@",
	              failures);
	return editor;
}

- (NSString *)textOf:(ORMEditor *)editor
{
	NSMutableArray *lines = [NSMutableArray array];
	for (ORMSchemaLine *line in [[[ORMSchemaText alloc] initWithEditor:editor] lines]) {
		[lines addObject:line.text];
	}
	return [lines componentsJoinedByString:@"\n"];
}

- (ORMFactType *)fact:(NSString *)reading in:(ORMModel *)model
{
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		if ([[[fact primaryReading] expandedText] isEqualToString:reading]) {
			return fact;
		}
	}
	return nil;
}

/* The text says what the model has, by diagram, comments its notes; read
 * into a new model it says the same again. */
- (void)testTheTextReadsBack
{
	ORMEditor *editor = [self built];
	ORMModel *model = editor.model;
	/* The comments are notes: of an object type, a fact type (the
	 * objectified one's), a constraint, a query; a comment a blank line
	 * ends is none. */
	XCTAssertEqualObjects([[model objectTypeNamed:@"VIN"] noteText], @"Seventeen letters and digits,\nno I, O or Q.");
	XCTAssertEqualObjects([[self fact:@"Person drives Car" in:model] noteText], @"Who may drive it.");
	XCTAssertEqualObjects([[model objectTypeNamed:@"Person"] noteText], nil);
	ORMConstraint *subset = nil;
	for (ORMConstraint *constraint in model.constraints) {
		subset = constraint.kind == ORMSubsetConstraint ? constraint : subset;
	}
	XCTAssertEqualObjects(subset.noteText, @"One with a driver is owned.");
	NSString *saved = [[NSString alloc] initWithData:[editor dataForSaving] encoding:NSUTF8StringEncoding];
	XCTAssertTrue([saved containsString:@"<ormq:Note>The cars and their owners.</ormq:Note>"], @"%@", saved);
	XCTAssertTrue([saved containsString:@"<orm:Text>One with a driver is owned.</orm:Text>"]);
	/* A copy for NORMA has NORMA's notes and not ORMKit's. */
	NSString *norma = [[editor documentForNorma] XMLString];
	XCTAssertTrue([norma containsString:@"One with a driver is owned."]);
	XCTAssertFalse([norma containsString:@"The cars and their owners."]);

	NSString *text = [self textOf:editor];
	NSArray *expected = @[ @"# People", @"", @"Person is an entity type.", @"Reference Mode: .id",
		                   @"Portable data type: Other: Object ID", @"", @"// Seventeen letters and digits,", @"// no I, O or Q.",
		                   @"VIN is a value type.", @"Portable data type: Text: Fixed Length(17)",
		                   @"The possible values of VIN match the pattern '[A-HJ-NPR-Z0-9]{17}'." ];
	XCTAssertEqualObjects([[text componentsSeparatedByString:@"\n"] subarrayWithRange:NSMakeRange(0, [expected count])],
	                      expected, @"%@", text);
	for (NSString *line in @[ @"Reference data: 'gal (US)', 3.785411784", @"Fact Type Name: BuildYear",
	                          @"Car (as OwnedCar) is owned by Person (as Owner) / Person owns Car",
	                          @"Permit is where Person drives Car.",
	                          @"+ An owner drives the cars they own; others are entered.",
	                          @"Each OldCar is by definition a Car that was built in some Year.",
	                          @"// The cars and their owners.\nQuery Owners:\n✓Car\n  + is owned by ✓Person" ]) {
		XCTAssertTrue([text containsString:line], @"%@ in\n%@", line, text);
	}
	/* What a statement names is said before it: the query after its fact
	 * type, on the diagram it is shown on. */
	XCTAssertTrue([text rangeOfString:@"# Cars"].location < [text rangeOfString:@"Query Owners:"].location);

	ORMEditor *again = [self newEditor];
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:again] addFromText:text failures:&failures], @"%@", failures);
	XCTAssertEqualObjects([self textOf:again], text);
	XCTAssertEqual([again.model.diagrams count], 2u);
	XCTAssertEqual([[again.model ordinaryFactTypes] count], [[model ordinaryFactTypes] count]);
}

/* Text applied to the model: what is new made, what it says already left
 * as it is, a comment set as the note of what follows it, "- " taking
 * away what the line says, a query of a name the model has replaced; one
 * step to undo. */
- (void)testTextIsApplied
{
	ORMEditor *editor = [self built];
	ORMModel *model = editor.model;
	NSString *before = [self textOf:editor];
	NSUInteger facts = [[model ordinaryFactTypes] count];
	NSUInteger diagrams = [model.diagrams count];
	NSString *changes = @"# Cars\n"
	                    @"// Its colour, as the owner says it.\n"
	                    @"Car is painted Colour()\n"
	                    @"Each Car is painted at most one Colour.\n"
	                    @"// Owned by one person.\n"
	                    @"Car is owned by Person\n"
	                    @"Each Car is owned by exactly one Person.\n"
	                    @"- + An owner drives the cars they own; others are entered.\n"
	                    @"- Reference data: km, 1\n"
	                    @"- // Who may drive it.\n"
	                    @"- The possible values of Year are at least 1886.\n"
	                    /* As the text says it, not as it was put. */
	                    @"- If some Person drives some Car then that Car is owned by some Person.\n"
	                    @"- Car has VIN\n"
	                    @"\n"
	                    @"Query Owners:\n"
	                    @"✓Person\n"
	                    @"  + owns ✓Car\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:changes failures:&failures], @"%@", failures);
	/* The diagram it named, not a new one; the fact type said again not
	 * made again, and its note set. */
	XCTAssertEqual([model.diagrams count], diagrams);
	ORMFactType *painted = [self fact:@"Car is painted Colour" in:model];
	XCTAssertNotNil(painted);
	XCTAssertEqualObjects(painted.noteText, @"Its colour, as the owner says it.");
	XCTAssertEqual([[model ordinaryFactTypes] count], facts + 1 - 1);
	XCTAssertEqualObjects([[self fact:@"Car is owned by Person" in:model] noteText], @"Owned by one person.");
	XCTAssertNil([self fact:@"Car has VIN" in:model]);
	ORMFactType *drives = [self fact:@"Person drives Car" in:model];
	XCTAssertFalse(drives.isDerived);
	XCTAssertNil(drives.noteText);
	XCTAssertEqual([[[self fact:@"Unit is worth Factor" in:model] instances] count], 1u);
	XCTAssertNil([[model objectTypeNamed:@"Year"] valueConstraint]);
	ORMDiagram *cars = nil;
	for (ORMDiagram *diagram in model.diagrams) {
		cars = [diagram.name isEqualToString:@"Cars"] ? diagram : cars;
	}
	XCTAssertNotNil([cars shapeForSubject:painted.identifier]);
	NSString *text = [self textOf:editor];
	XCTAssertTrue([text containsString:@"Query Owners:\n✓Person\n  + owns ✓Car"], @"%@", text);
	XCTAssertFalse([text containsString:@"If some Person drives"], @"%@", text);

	[self.undoManager undo];
	XCTAssertEqualObjects([self textOf:editor], before);

	/* What the model does not say is not taken away, and nothing is. */
	XCTAssertFalse([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:@"- Car is painted Colour\n"
	                                                                     failures:&failures]);
	XCTAssertEqual([failures count], 1u);
	XCTAssertTrue([[failures firstObject] hasPrefix:@"1: "], @"%@", failures);
}

/* A diagram taken away is out of the model's diagrams at once. */
- (void)testADiagramDeletedLeavesTheModel
{
	ORMEditor *editor = [self built];
	NSUInteger count = [editor.model.diagrams count];
	[editor.elementEditor deleteElements:@[ [[editor.model.diagrams lastObject] identifier] ]];
	XCTAssertEqual([editor.model.diagrams count], count - 1);
	[self.undoManager undo];
	XCTAssertEqual([editor.model.diagrams count], count);
}

/* Every NORMA file's own listing, applied to it, changes nothing: each
 * line found as what the model says already, the file the bytes it was. */
- (void)testAModelsOwnTextChangesNothing
{
	NSMutableArray *files = [NSMutableArray arrayWithArray:[self normaFixtures]];
	[files addObjectsFromArray:[self activeFactsFixtures]];
	for (NSString *file in [NSOrderedSet orderedSetWithArray:files]) {
		@autoreleasepool {
			NSData *data = [self fixtureData:file];
			ORMEditor *editor = [self newEditorWithDocument:[self fixtureDocument:file]];
			NSString *text = [[[ORMSchemaText alloc] initWithEditor:editor] textFromFile:file];
			NSArray *failures = nil;
			XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@: %@",
			              file, failures);
			XCTAssertFalse(editor.hasChanges, @"%@", file);
			XCTAssertEqualObjects([editor dataForSaving], data, @"%@", file);
		}
	}
}

@end
