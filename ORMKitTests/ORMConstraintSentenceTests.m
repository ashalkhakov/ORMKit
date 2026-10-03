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
		/* An external uniqueness or inclusive-or spans fact types by
		 * nature; the others over several are joins. */
		BOOL byNature = constraint.kind == ORMUniquenessConstraint || constraint.kind == ORMMandatoryConstraint;
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
			NSArray *made = [editor addFromSentence:[sentence text] onDiagram:nil at:ORMAutomaticPlacement reason:NULL];
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
	NSString *created = [editor addSetComparisonConstraint:ORMEqualityConstraint joinPaths:@[ same, spec ] reason:&reason];
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
		NSArray *made = [editor addFromSentence:text onDiagram:diagram at:ORMAutomaticPlacement reason:&reason];
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

- (void)testWhatIsNotUnderstoodSaysWhy
{
	ORMEditor *editor = [self newEditor];
	NSString *reason = nil;
	XCTAssertNil(([ORMConstraintSentence sentenceWithString:@"Perhaps some Person smokes." model:editor.model
	                                                 reason:&reason]));
	XCTAssertTrue([reason length] > 0);
	/* A fact type, though, is what the Fact Editor makes. */
	NSArray *made = [editor addFromSentence:@"Person(.id) drives Car(.vin)" onDiagram:nil at:ORMAutomaticPlacement
	                                 reason:&reason];
	XCTAssertEqual([made count], (NSUInteger)1, @"%@", reason);
	XCTAssertNotNil([editor.model objectTypeNamed:@"Car"]);
}

@end
