/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* Constraints typed as the verbalizer says them. What the verbalizer
 * writes, the parser reads back as the constraint it came from; and a
 * model can be built from sentences alone. */
@interface ORMConstraintSentenceTests : ORMTestCase
@end

static NSSet *
ORMSpecRoles(NSArray<ORMSentenceRole *> *roles)
{
	NSMutableSet *ids = [NSMutableSet set];
	for (ORMSentenceRole *role in roles) {
		if (role.role != nil) {
			[ids addObject:role.role.identifier];
		}
	}
	return ids;
}

static NSSet *
ORMRoleIds(NSArray<ORMRole *> *roles)
{
	return [NSSet setWithArray:[roles valueForKey:@"identifier"]];
}

/* Whether what the parser made of a sentence is the element it says. */
static BOOL
ORMSpecIs(ORMSentenceConstraint *spec, id element)
{
	if ([element isKindOfClass:[ORMValueConstraint class]]) {
		NSArray *said = [ORMValueConstraintParser rangesFromString:spec.values reason:NULL];
		return spec.values != nil
			&& [said isEqualToArray:[ORMValueConstraintParser rangesFromString:[element displayText] reason:NULL]];
	}
	ORMConstraint *constraint = element;
	NSMutableArray *all = [NSMutableArray array];
	for (NSArray *sequence in spec.sequences) {
		[all addObjectsFromArray:sequence];
	}
	if (spec.values != nil) {
		return NO;
	}
	/* An exclusive-or is said by its exclusion half. */
	if (constraint.kind == ORMExclusionConstraint && constraint.exclusiveOrPartner != nil) {
		return spec.kind == ORMMandatoryConstraint && spec.isExclusiveOr
			&& [ORMSpecRoles(all) isEqualToSet:ORMRoleIds([constraint allRoles])];
	}
	if (spec.kind != constraint.kind) {
		return NO;
	}
	switch (constraint.kind) {
	case ORMValueComparisonConstraint:
		if (![spec.comparisonOperator isEqualToString:constraint.comparisonOperator]) {
			return NO;
		}
		break;
	case ORMMandatoryConstraint:
		if (spec.isExclusiveOr != (constraint.exclusiveOrPartner != nil)) {
			return NO;
		}
		break;
	case ORMRingConstraint:
		/* Each ring type is a sentence of its own. */
		if ((spec.ringType & constraint.ringType) == 0) {
			return NO;
		}
		break;
	case ORMSubsetConstraint: {
		/* Column by column: the columns' order is the modeller's. */
		if ([spec.sequences count] != 2 || [constraint.roleSequences count] != 2) {
			return NO;
		}
		NSMutableSet *said = [NSMutableSet set];
		NSMutableSet *have = [NSMutableSet set];
		NSArray *a = [[spec.sequences objectAtIndex:0] valueForKeyPath:@"role.identifier"];
		NSArray *b = [[spec.sequences objectAtIndex:1] valueForKeyPath:@"role.identifier"];
		NSArray *c = [[[constraint.roleSequences objectAtIndex:0] roles] valueForKey:@"identifier"];
		NSArray *d = [[[constraint.roleSequences objectAtIndex:1] roles] valueForKey:@"identifier"];
		for (NSUInteger i = 0; i < MIN([a count], [b count]); i++) {
			[said addObject:@[ [a objectAtIndex:i], [b objectAtIndex:i] ]];
		}
		for (NSUInteger i = 0; i < MIN([c count], [d count]); i++) {
			[have addObject:@[ [c objectAtIndex:i], [d objectAtIndex:i] ]];
		}
		return [said isEqualToSet:have];
	}
	case ORMEqualityConstraint:
	case ORMExclusionConstraint:
		if ([spec.sequences count] != [constraint.roleSequences count]) {
			return NO;
		}
		for (NSArray *sequence in spec.sequences) {
			BOOL found = NO;
			for (ORMRoleSequence *other in constraint.roleSequences) {
				found = found || [ORMSpecRoles(sequence) isEqualToSet:ORMRoleIds(other.roles)];
			}
			if (!found) {
				return NO;
			}
		}
		return YES;
	default:
		break;
	}
	return [ORMSpecRoles(all) isEqualToSet:ORMRoleIds([constraint allRoles])];
}

/* What the parser reads now: constraints over the fact types their roles
 * are in, not over join paths, and not frequency. */
static BOOL
ORMSaidWithoutJoins(id element)
{
	if (![element isKindOfClass:[ORMConstraint class]]) {
		return YES;
	}
	ORMConstraint *constraint = element;
	if (constraint.kind == ORMFrequencyConstraint) {
		return NO;
	}
	for (ORMRoleSequence *sequence in constraint.roleSequences) {
		if ([sequence joinPath] != nil) {
			return NO;
		}
		BOOL spans = [[NSSet setWithArray:[sequence.roles valueForKey:@"factType"]] count] > 1;
		/* An external uniqueness, an inclusive-or or a value comparison
		 * spans fact types by nature; the others over several are joins. */
		BOOL byNature = constraint.kind == ORMUniquenessConstraint || constraint.kind == ORMMandatoryConstraint
			|| constraint.kind == ORMValueComparisonConstraint;
		if (spans && !byNature) {
			return NO;
		}
	}
	/* An external uniqueness over fact types that share no player is a
	 * join too. */
	if (constraint.kind == ORMUniquenessConstraint && !constraint.isInternal) {
		for (ORMRole *role in [constraint allRoles]) {
			if ([[role.factType visibleRoles] count] != 2) {
				return NO;
			}
		}
		NSMutableSet *players = [NSMutableSet set];
		for (ORMRole *role in [constraint allRoles]) {
			[players addObject:[NSValue valueWithNonretainedObject:[role oppositeRole].player]];
		}
		return [players count] == 1;
	}
	return YES;
}

/* The role names shown on a fact type's shape. */
static NSUInteger
ORMRoleNameShapes(ORMShape *factShape)
{
	NSUInteger count = 0;
	for (ORMShape *child in factShape.relativeShapes) {
		count += child.kind == ORMShapeRoleName ? 1 : 0;
	}
	return count;
}

@implementation ORMConstraintSentenceTests

/* Every statement the verbalizer makes of a constraint it can read
 * reads back as that constraint, in every model NORMA wrote. */
- (void)testWhatTheVerbalizerSaysReadsBack
{
	NSUInteger checked = 0;
	for (NSString *name in [self normaFixtures]) @autoreleasepool {
		ORMModel *model = [ORMModel modelOfDocument:[self fixtureDocument:name] reason:NULL];
		ORMVerbalizer *verbalizer = [[ORMVerbalizer alloc] initWithModel:model];
		verbalizer.verbalizesPossibilities = NO;
		for (ORMVerbalSentence *sentence in [verbalizer sentencesForModel]) @autoreleasepool {
			id element = sentence.sourceId != nil ? [model elementWithId:sentence.sourceId] : nil;
			if (sentence.kind != ORMVerbalStatement
			    || !([element isKindOfClass:[ORMConstraint class]] || [element isKindOfClass:[ORMValueConstraint class]])
			    || !ORMSaidWithoutJoins(element)) {
				continue;
			}
			NSString *reason = nil;
			ORMConstraintSentence *parsed = [ORMConstraintSentence sentenceWithString:[sentence text] model:model
			                                                                    reason:&reason];
			if (parsed.isAmbiguous) {
				/* Two fact types read the same: either could be meant. */
				continue;
			}
			BOOL found = NO;
			for (ORMSentenceConstraint *spec in parsed.constraints) {
				found = found || ORMSpecIs(spec, element);
			}
			XCTAssertTrue(found && [parsed.factTypes count] == 0, @"%@: %@ (%@)", name, [sentence text],
			              reason ?: @"read as something else");
			checked++;
		}
	}
	XCTAssertTrue(checked > 1500, @"%lu", (unsigned long)checked);
}

/* A constraint over a join path, read from its sentence and made in a
 * copy of the model, is said back as it was: what the parser made is what
 * NORMA had, as far as the sentence can tell. */
- (void)testConstraintsOverJoinPathsReadBack
{
	NSUInteger same = 0;
	NSUInteger tried = 0;
	for (NSString *name in [self normaFixtures]) @autoreleasepool {
		NSData *data = [self fixtureData:name];
		ORMModel *model = [ORMModel modelOfDocument:ORMParseDocument(data, NULL) reason:NULL];
		ORMVerbalizer *verbalizer = [[ORMVerbalizer alloc] initWithModel:model];
		verbalizer.verbalizesPossibilities = NO;
		for (ORMVerbalSentence *sentence in [verbalizer sentencesForModel]) @autoreleasepool {
			ORMConstraint *constraint = sentence.sourceId != nil ? [model elementWithId:sentence.sourceId] : nil;
			if (sentence.kind != ORMVerbalStatement || ![constraint isKindOfClass:[ORMConstraint class]]
			    || (constraint.kind != ORMSubsetConstraint && constraint.kind != ORMEqualityConstraint
			        && constraint.kind != ORMExclusionConstraint)
			    || ORMSaidWithoutJoins(constraint)) {
				continue;
			}
			tried++;
			ORMEditor *editor = [[ORMEditor alloc] initWithDocument:ORMParseDocument(data, NULL) undoManager:nil];
			NSArray *made = [[[ORMSentenceEditor alloc] initWithEditor:editor] addFromSentence:[sentence text] onDiagram:nil at:ORMAutomaticPlacement reason:NULL];
			for (NSString *identifier in made) {
				if ([[editor.model elementWithId:identifier] isKindOfClass:[ORMConstraint class]]) {
					ORMVerbalizer *again = [[ORMVerbalizer alloc] initWithModel:editor.model];
					if ([[[[again sentencesForElement:identifier] firstObject] text] isEqualToString:[sentence text]]) {
						same++;
					}
				}
			}
		}
	}
	/* Two of NORMA's metamodel constraints walk subtype facts in ways a
	 * sentence does not say. */
	XCTAssertTrue(tried >= 20 && same + 2 >= tried, @"%lu of %lu", (unsigned long)same, (unsigned long)tried);
}

/* The path NORMA keeps, built from logic: StockMate's equality between
 * "Address is in Region" and the join of "Address is in Country" and
 * "Region is part of Country". */
- (void)testAJoinPathIsBuiltAsNormaKeepsOne
{
	ORMEditor *editor = [[ORMEditor alloc] initWithDocument:[self fixtureDocument:@"StockMate.orm"] undoManager:nil];
	ORMModel *model = editor.model;
	ORMConstraint *original = nil;
	for (ORMConstraint *constraint in model.constraints) {
		if ([constraint.name isEqualToString:@"EqualityConstraint1"]) {
			original = constraint;
		}
	}
	ORMRoleSequence *joined = [original.roleSequences objectAtIndex:1];
	ORMRoleSequence *plain = [original.roleSequences objectAtIndex:0];
	ORMRole *address = [joined.roles objectAtIndex:0];
	ORMRole *region = [joined.roles objectAtIndex:1];
	NSString *reason = nil;
	ORMJoinPathSpec *spec = [ORMJoinPathSpec
		specWithAtoms:@[ @{ address.identifier: @"A", [address oppositeRole].identifier: @"C" },
		                 @{ region.identifier: @"R", [region oppositeRole].identifier: @"C" } ]
		      columns:@[ @"A", @"R" ]];
	ORMJoinPathSpec *same = [ORMJoinPathSpec
		specWithAtoms:@[ @{ [[plain.roles objectAtIndex:0] identifier]: @"A", [[plain.roles objectAtIndex:1] identifier]: @"R" } ]
		      columns:@[ @"A", @"R" ]];
	NSString *created = [[[ORMJoinPathBuilder alloc] initWithEditor:editor] addSetComparisonConstraint:ORMEqualityConstraint joinPaths:@[ same, spec ] reason:&reason];
	XCTAssertNotNil(created, @"%@", reason);
	ORMConstraint *built = [editor.model elementWithId:created];
	ORMRelation *theirs = nil;
	for (ORMConstraint *constraint in editor.model.constraints) {
		if ([constraint.name isEqualToString:@"EqualityConstraint1"]) {
			theirs = [ORMLogic relationForSequence:[constraint.roleSequences objectAtIndex:1]];
		}
	}
	ORMRelation *ours = [ORMLogic relationForSequence:[built.roleSequences objectAtIndex:1]];
	XCTAssertNotNil([[built.roleSequences objectAtIndex:1] joinPath]);
	XCTAssertEqualObjects([ours description], [theirs description]);
	/* And it is said as NORMA's is. */
	ORMVerbalizer *verbalizer = [[ORMVerbalizer alloc] initWithModel:editor.model];
	XCTAssertEqualObjects([[[verbalizer sentencesForElement:created] firstObject] text],
	                      [[[verbalizer sentencesForElement:original.identifier] firstObject] text]);
	/* The file it makes is one NORMA's reader reads back the same. */
	ORMModel *reread = [ORMModel modelOfDocument:ORMParseDocument([editor dataForSaving], NULL) reason:NULL];
	ORMConstraint *saved = [reread elementWithId:created];
	XCTAssertEqualObjects([[ORMLogic relationForSequence:[saved.roleSequences objectAtIndex:1]] description],
	                      [ours description]);
}

/* A model from sentences, joins and all. */
- (void)testAJoinPathFromASentence
{
	ORMEditor *editor = [self editorWith:@[ @"Each Diplomat serves in some Country.", @"Each Diplomat speaks some Language.",
		                                    @"Each Language is spoken in some Country.",
		                                    (@"If some Diplomat serves in some Country then that Diplomat speaks some "
		                                     @"Language that is spoken in that Country.") ]];
	ORMConstraint *subset = nil;
	for (ORMConstraint *constraint in editor.model.constraints) {
		if (constraint.kind == ORMSubsetConstraint) {
			subset = constraint;
		}
	}
	XCTAssertNotNil([[subset.roleSequences lastObject] joinPath]);
	XCTAssertTrue([[self textsOf:subset.identifier in:editor.model]
		containsObject:@"If some Diplomat serves in some Country then that Diplomat speaks some Language that is spoken "
		               @"in that Country."]);
}

- (ORMEditor *)editorWith:(NSArray<NSString *> *)sentences
{
	ORMEditor *editor = [self newEditor];
	NSString *diagram = [[editor.model.diagrams firstObject] identifier];
	for (NSString *text in sentences) {
		NSString *reason = nil;
		NSArray *made = [[[ORMSentenceEditor alloc] initWithEditor:editor] addFromSentence:text onDiagram:diagram at:ORMAutomaticPlacement reason:&reason];
		XCTAssertNotNil(made, @"%@: %@", text, reason);
	}
	return editor;
}

- (NSArray<NSString *> *)textsOf:(NSString *)elementId in:(ORMModel *)model
{
	return [[[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:elementId] valueForKey:@"text"];
}

/* As in NORMA: what a sentence names that the model lacks is made. */
- (void)testASentenceMakesWhatItNames
{
	ORMEditor *editor = [self editorWith:@[ @"Each Person was born in exactly one Country." ]];
	ORMModel *model = editor.model;
	ORMObjectType *person = [model objectTypeNamed:@"Person"];
	XCTAssertNotNil(person);
	XCTAssertNotNil([model objectTypeNamed:@"Country"]);
	ORMFactType *born = [[model ordinaryFactTypes] firstObject];
	XCTAssertEqualObjects([[born primaryReading] text], @"{0} was born in {1}");
	ORMRole *role = [[born visibleRoles] firstObject];
	XCTAssertTrue(role.isUnique && role.isMandatory);
	XCTAssertTrue([[self textsOf:born.identifier in:model] containsObject:@"Each Person was born in exactly one Country."]);
	/* Both on the diagram. */
	XCTAssertNotNil([[model.diagrams firstObject] shapeForSubject:born.identifier]);
	XCTAssertNotNil([[model.diagrams firstObject] shapeForSubject:person.identifier]);
	/* One step to undo. */
	[self.undoManager undo];
	XCTAssertNil([editor.model objectTypeNamed:@"Person"]);
}

/* A model from sentences alone, and back. */
- (void)testAModelFromSentences
{
	NSArray *sentences = @[ @"Each Person smokes or drinks.", @"No Person smokes and drinks.",
		                    @"If some Person smokes then that Person is cancer prone.",
		                    @"Each Person was born in at most one Country.",
		                    @"No Person is parent of itself.",
		                    (@"In each population of Person speaks Language, each Person, Language combination occurs "
		                     @"at most once."),
		                    @"For each Person and Sport, that Person played that Sport for at most one Country.",
		                    @"The possible values of Gender are 'M', 'F'.",
		                    @"Each Person is of exactly one Gender.",
		                    @"It is obligatory that each Person was born in some Country." ];
	ORMEditor *editor = [self editorWith:sentences];
	ORMModel *model = editor.model;
	NSMutableArray *said = [NSMutableArray array];
	ORMVerbalizer *verbalizer = [[ORMVerbalizer alloc] initWithModel:model];
	verbalizer.verbalizesPossibilities = NO;
	for (ORMVerbalSentence *sentence in [verbalizer sentencesForModel]) {
		[said addObject:[sentence text]];
	}
	for (NSString *text in @[ @"Each Person smokes or drinks.", @"No Person smokes and drinks.",
	                          @"If some Person smokes then that Person is cancer prone.", @"No Person is parent of itself.",
	                          @"For each Person and Sport, that Person played that Sport for at most one Country.",
	                          @"The possible values of Gender are 'M', 'F'.", @"Each Person is of exactly one Gender.",
	                          @"It is obligatory that each Person was born in some Country." ]) {
		XCTAssertTrue([said containsObject:text], @"%@ not said back: %@", text, said);
	}
	/* "at most one" and the obligatory "some" on one role are said as one
	 * NORMA sentence each way. */
	ORMObjectType *person = [model objectTypeNamed:@"Person"];
	XCTAssertEqual([[[model objectTypeNamed:@"Gender"] valueConstraint].ranges count], (NSUInteger)2);
	XCTAssertNotNil(person);
}

/* A value comparison, and over a supertype's fact type and a subtype's,
 * said "For each" the subtype. */
- (void)testAValueComparisonFromASentence
{
	NSString *dates = @"For each Project, if that Project starts on some Date1 and that Project ends on some Date2 then "
	                  @"Date1 is less than or equal to Date2.";
	ORMEditor *editor = [self editorWith:@[ @"Each Project starts on exactly one Date.", @"Each Project ends on at most one Date.",
	                                        dates, @"Each Event is at exactly one Moment.", @"Each Trip is an Event.",
	                                        @"Each Trip ended at at most one Moment." ]];
	NSString *moments = @"For each Trip, if that Trip is at some Moment1 and that Trip ended at some Moment2 then "
	                    @"Moment1 is less than Moment2.";
	NSString *reason = nil;
	NSArray *made = [[[ORMSentenceEditor alloc] initWithEditor:editor] addFromSentence:moments onDiagram:nil
	                                                                                  at:ORMAutomaticPlacement
	                                                                              reason:&reason];
	XCTAssertEqual([made count], (NSUInteger)1, @"%@", reason);
	NSMutableArray *comparisons = [NSMutableArray array];
	for (ORMConstraint *constraint in editor.model.constraints) {
		if (constraint.kind == ORMValueComparisonConstraint) {
			[comparisons addObject:constraint];
		}
	}
	XCTAssertEqual([comparisons count], (NSUInteger)2);
	XCTAssertEqualObjects([[comparisons firstObject] comparisonOperator], @"LessThanOrEqual");
	XCTAssertEqualObjects([[comparisons lastObject] comparisonOperator], @"LessThan");
	XCTAssertTrue([[self textsOf:[[comparisons firstObject] identifier] in:editor.model] containsObject:dates]);
	XCTAssertTrue([[self textsOf:[[comparisons lastObject] identifier] in:editor.model] containsObject:moments]);
	/* No "some" to compare. */
	XCTAssertNil(([[[ORMSentenceEditor alloc] initWithEditor:editor]
		addFromSentence:@"For each Project, if that Project starts on some Date1 then Date1 is less than Date3."
		      onDiagram:nil at:ORMAutomaticPlacement reason:&reason]));
	XCTAssertTrue([reason rangeOfString:@"Date3"].location != NSNotFound, @"%@", reason);
}

/* What the verbalizer says of object types reads back as them. */
- (void)testObjectTypesFromStatements
{
	ORMEditor *editor = [self editorWith:@[ @"Amount is a value type.", @"Currency is an entity type.",
	                                        @"Each Money has exactly one Amount.", @"Each Money is in exactly one Currency.",
	                                        (@"For each Amount and Currency, at most one Money has that Amount and is in that "
	                                         @"Currency."),
	                                        (@"This association with Amount and Currency provides the preferred "
	                                         @"identification scheme for Money."),
	                                        @"Each Male is a Person.",
	                                        @"Each Adult is by definition a Person who is of some Age.",
	                                        @"Enrolment is where Student enrolled in Course." ]];
	ORMModel *model = editor.model;
	XCTAssertFalse([[model objectTypeNamed:@"Amount"] isEntity]);
	XCTAssertTrue([[model objectTypeNamed:@"Currency"] isEntity]);
	ORMObjectType *money = [model objectTypeNamed:@"Money"];
	XCTAssertEqual([[[money preferredIdentifier] allRoles] count], (NSUInteger)2);
	ORMObjectType *person = [model objectTypeNamed:@"Person"];
	XCTAssertTrue([[model objectTypeNamed:@"Male"] isSubtypeOf:person]);
	ORMObjectType *adult = [model objectTypeNamed:@"Adult"];
	XCTAssertTrue([adult isSubtypeOf:person]);
	XCTAssertEqualObjects(adult.definitionText, @"Each Adult is by definition a Person who is of some Age.");
	ORMObjectType *enrolment = [model objectTypeNamed:@"Enrolment"];
	XCTAssertEqualObjects([[enrolment.nestedFactType primaryReading] text], @"{0} enrolled in {1}");
	XCTAssertTrue([[self textsOf:money.identifier in:model]
		containsObject:@"Reference Scheme: Money has Amount; Money is in Currency."]);
	/* Said again of one the model has: nothing new. */
	NSUInteger count = [model.objectTypes count];
	NSString *reason = nil;
	NSArray *made = [[[ORMSentenceEditor alloc] initWithEditor:editor] addFromSentence:@"Currency is an entity type."
	                                                                         onDiagram:nil at:ORMAutomaticPlacement
	                                                                            reason:&reason];
	XCTAssertEqualObjects(made, @[ [[model objectTypeNamed:@"Currency"] identifier] ]);
	XCTAssertEqual([editor.model.objectTypes count], count);
	XCTAssertNil(([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromSentence:@"Amount is an entity type."
	                                                                       onDiagram:nil at:ORMAutomaticPlacement
	                                                                          reason:&reason]));
	XCTAssertTrue([reason length] > 0);
}

/* A schema as text: diagrams by heading, details and derivations going on
 * from the line before, every line not read said with its number. */
- (void)testASchemaFromText
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"// Money and records\n"
	                 @"# Money\n"
	                 @"Amount is a value type.\n"
	                 @"Portable data type: Numeric: Decimal(19, 4)\n"
	                 @"Currency is an entity type.\n"
	                 @"Reference Mode: .code\n"
	                 @"Each Money has exactly one Amount.\n"
	                 @"\n"
	                 @"# Records\n"
	                 @"Record(.id) cost Money\n"
	                 @"Fact Type Name: RecordCost\n"
	                 @"** the sum of its items' costs\n"
	                 @"is late, and lazy.\n"
	                 @"Portable data type: Numeric: Whatever\n";
	NSArray *failures = nil;
	XCTAssertFalse([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures]);
	XCTAssertEqual([failures count], (NSUInteger)2, @"%@", failures);
	XCTAssertTrue([[failures firstObject] hasPrefix:@"13: "], @"%@", failures);
	XCTAssertTrue([[failures lastObject] hasPrefix:@"14: "], @"%@", failures);
	ORMModel *model = editor.model;
	XCTAssertEqualObjects([model.diagrams valueForKey:@"name"], (@[ @"Money", @"Records" ]));
	ORMObjectType *amount = [model objectTypeNamed:@"Amount"];
	XCTAssertEqualObjects(amount.dataType.typeName, @"DecimalNumericDataType");
	XCTAssertEqual(amount.dataTypeLength, (NSInteger)19);
	XCTAssertEqual(amount.dataTypeScale, (NSInteger)4);
	XCTAssertEqualObjects([[model objectTypeNamed:@"Currency"] referenceMode], @"code");
	ORMFactType *cost = nil;
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		if ([[[fact primaryReading] text] isEqualToString:@"{0} cost {1}"]) {
			cost = fact;
		}
	}
	XCTAssertTrue(cost.isDerived);
	XCTAssertEqualObjects(cost.explicitName, @"RecordCost");
	XCTAssertTrue([[self textsOf:cost.identifier in:model] containsObject:@"** the sum of its items' costs."],
	              @"%@", [self textsOf:cost.identifier in:model]);
	/* Each diagram has what its lines named. */
	ORMDiagram *records = [model.diagrams lastObject];
	XCTAssertNotNil([records shapeForSubject:cost.identifier]);
	XCTAssertNotNil([records shapeForSubject:[[model objectTypeNamed:@"Money"] identifier]]);
	/* One step to undo. */
	[self.undoManager undo];
	XCTAssertNil([editor.model objectTypeNamed:@"Amount"]);
}

/* A role named as CQL names it: shown on the diagram as NORMA shows it,
 * and the attribute Core Data gets is called so. */
- (void)testARoleNamedInASentence
{
	ORMEditor *editor = [self editorWith:@[ @"Vehicle(.id) was acquired on Date() (as PurchaseDate)",
	                                        @"Each Vehicle was acquired on at most one Date." ]];
	ORMModel *model = editor.model;
	ORMFactType *acquired = nil;
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		if ([[[fact primaryReading] text] isEqualToString:@"{0} was acquired on {1}"]) {
			acquired = fact;
		}
	}
	XCTAssertNotNil(acquired);
	ORMRole *date = [[acquired visibleRoles] lastObject];
	XCTAssertEqualObjects(date.name, @"PurchaseDate");
	ORMDiagram *diagram = [model.diagrams firstObject];
	ORMShape *factShape = [diagram shapeForSubject:acquired.identifier];
	XCTAssertEqual(ORMRoleNameShapes(factShape), (NSUInteger)1);
	ORMCDModel *coreData = [[[ORMCoreDataMapper alloc] initWithModel:model mapping:nil] map];
	NSMutableArray *names = [NSMutableArray array];
	for (ORMCDEntity *entity in coreData.entities) {
		if ([entity.name isEqualToString:@"Vehicle"]) {
			[names addObjectsFromArray:[entity.attributes valueForKey:@"name"]];
		}
	}
	XCTAssertTrue([names containsObject:@"purchaseDate"], @"%@", names);
	/* Its name taken away, so is its shape. */
	XCTAssertTrue([editor.elementEditor rename:date.identifier to:@"" reason:NULL]);
	factShape = [[editor.model.diagrams firstObject] shapeForSubject:acquired.identifier];
	XCTAssertEqual(ORMRoleNameShapes(factShape), (NSUInteger)0);
}

- (void)testWhatIsNotUnderstoodSaysWhy
{
	ORMEditor *editor = [self newEditor];
	NSString *reason = nil;
	XCTAssertNil(([ORMConstraintSentence sentenceWithString:@"Perhaps some Person smokes." model:editor.model
	                                                 reason:&reason]));
	XCTAssertTrue([reason length] > 0);
	/* A fact type, though, is what the Fact Editor makes. */
	NSArray *made = [[[ORMSentenceEditor alloc] initWithEditor:editor] addFromSentence:@"Person(.id) drives Car(.vin)" onDiagram:nil at:ORMAutomaticPlacement
	                                 reason:&reason];
	XCTAssertEqual([made count], (NSUInteger)1, @"%@", reason);
	XCTAssertNotNil([editor.model objectTypeNamed:@"Car"]);
}

@end
