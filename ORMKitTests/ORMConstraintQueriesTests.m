/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* Constraints over roles of more than one fact type, as the rule queries
 * whose rows break them: checked in sample populations, and by the
 * validation code. */
@interface ORMConstraintQueriesTests : ORMTestCase
@end

@implementation ORMConstraintQueriesTests

- (ORMEditor *)fleet
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Moment is a value type.\n"
	                 @"Portable data type: Temporal: Date & Time\n"
	                 @"Vehicle(.id) is owned by User(.id) / User owns Vehicle\n"
	                 @"Each Vehicle is owned by exactly one User.\n"
	                 @"User drives Vehicle\n"
	                 @"In each population of User drives Vehicle, each User, Vehicle combination occurs at most once.\n"
	                 @"Trip(.id) is of Vehicle\n"
	                 @"Each Trip is of exactly one Vehicle.\n"
	                 @"Trip had driver User\n"
	                 @"Each Trip had driver exactly one User.\n"
	                 @"Trip started at Moment\n"
	                 @"Each Trip started at at most one Moment.\n"
	                 @"Trip ended at Moment\n"
	                 @"Each Trip ended at at most one Moment.\n"
	                 @"If some Trip had driver some User and that Trip is of some Vehicle then that User drives that Vehicle.\n"
	                 @"No User owns and drives the same Vehicle.\n"
	                 @"For each Trip, if that Trip started at some Moment1 and that Trip ended at some Moment2 then Moment1 is "
	                 @"less than or equal to Moment2.\n"
	                 @"Each Trip started at some Moment or ended at some Moment.\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	return editor;
}

- (ORMConstraint *)constraint:(ORMConstraintKind)kind in:(ORMModel *)model
{
	for (ORMConstraint *constraint in model.constraints) {
		if (constraint.kind == kind && !constraint.isImplied && !constraint.isInternal) {
			return constraint;
		}
	}
	return nil;
}

- (NSArray<NSString *> *)outlinesOf:(ORMConstraintKind)kind in:(ORMEditor *)editor
{
	NSString *reason = nil;
	NSArray *made = [[[ORMConstraintQueries alloc] initWithEditor:editor] queriesFor:[self constraint:kind in:editor.model]
	                                                                         reason:&reason];
	XCTAssertNotNil(made, @"%@", reason);
	NSMutableArray *outlines = [NSMutableArray array];
	for (NSString *identifier in made) {
		[outlines addObject:[[ORMQuery queryWithId:identifier inModel:editor.model] outlineText]];
	}
	return outlines;
}

/* Each kind as the query whose rows break it. */
- (void)testEachKindIsAQuery
{
	ORMEditor *editor = [self fleet];
	XCTAssertEqualObjects([self outlinesOf:ORMSubsetConstraint in:editor],
	                      (@[ @"It is impossible that:\n✓Trip\n  + is of Vehicle1\n  + had driver User\n"
	                          @"    + not drives Vehicle1\n" ]));
	XCTAssertEqualObjects([self outlinesOf:ORMExclusionConstraint in:editor],
	                      (@[ @"It is impossible that:\n✓User1\n  + owns Vehicle\n    + User1 drives that Vehicle\n" ]));
	XCTAssertEqualObjects([self outlinesOf:ORMValueComparisonConstraint in:editor],
	                      (@[ @"It is impossible that:\n✓Trip\n  + started at Moment1\n  + ended at Moment2 < Moment1\n" ]));
	NSString *reason = nil;
	ORMConstraint *inclusiveOr = nil;
	for (ORMConstraint *constraint in editor.model.constraints) {
		if (constraint.kind == ORMMandatoryConstraint && !constraint.isSimple && !constraint.isImplied) {
			inclusiveOr = constraint;
		}
	}
	NSArray *made = [[[ORMConstraintQueries alloc] initWithEditor:editor] queriesFor:inclusiveOr reason:&reason];
	XCTAssertEqualObjects([[ORMQuery queryWithId:[made firstObject] inModel:editor.model] outlineText],
	                      @"It is impossible that:\n✓Trip\n  + not started at Moment\n  + not ended at Moment\n");
}

/* A sample population breaking one is told so, as the constraint. */
- (void)testASamplePopulationIsCheckedAgainstThem
{
	ORMEditor *editor = [self fleet];
	ORMModel *model = editor.model;
	NSMutableDictionary *facts = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		[facts setObject:fact forKey:[[fact primaryReading] expandedText]];
	}
	NSString *reason = nil;
	/* User 2 drove trip 100 of vehicle 10, which only user 1 drives. */
	for (NSArray *each in @[ @[ @"Vehicle is owned by User", @"10", @"1" ], @[ @"User drives Vehicle", @"3", @"10" ],
	                         @[ @"Trip is of Vehicle", @"100", @"10" ], @[ @"Trip had driver User", @"100", @"2" ] ]) {
		ORMFactType *fact = [facts objectForKey:each[0]];
		NSArray *roles = [fact visibleRoles];
		XCTAssertNotNil(([editor.populationEditor addFactOf:fact.identifier
		                                              named:@{ [roles[0] identifier]: each[1], [roles[1] identifier]: each[2] }
		                                             reason:&reason]),
		                @"%@", reason);
	}
	ORMPopulationChecker *checker = [[ORMPopulationChecker alloc] initWithModel:model];
	NSArray *violations = [checker violations];
	ORMConstraint *subset = [self constraint:ORMSubsetConstraint in:model];
	NSMutableArray *ofSubset = [NSMutableArray array];
	for (ORMPopulationViolation *violation in violations) {
		if (violation.constraint == subset) {
			[ofSubset addObject:violation.text];
		}
	}
	XCTAssertEqual([ofSubset count], (NSUInteger)1, @"%@", [violations valueForKey:@"text"]);
	XCTAssertEqualObjects([ofSubset firstObject], @"SubsetConstraint1: Trip 100.");
	XCTAssertFalse([[checker unchecked] containsObject:@"SubsetConstraint1: a sequence over more than one fact type is not checked."]);
}

/* The validation code checks the subset as a rule of User. */
- (void)testTheValidationCodeChecksThem
{
	ORMEditor *editor = [self fleet];
	ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:editor.model mapping:nil name:@"Fleet"];
	NSString *name = [self constraint:ORMSubsetConstraint in:editor.model].name;
	for (NSString *note in generator.notes) {
		XCTAssertFalse([note hasPrefix:name], @"%@", note);
	}
	NSString *source = [[generator files] objectForKey:@"FleetValidation.m"] ?: @"";
	NSString *plans = @"";
	for (NSString *file in [generator files]) {
		plans = [plans stringByAppendingString:[[generator files] objectForKey:file]];
	}
	XCTAssertTrue([plans rangeOfString:name].location != NSNotFound, @"%@", [[generator files] allKeys]);
	XCTAssertNotNil(source);
}

@end
