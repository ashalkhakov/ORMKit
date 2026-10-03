/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* Role sequences, join paths and fact types as logic. What a formula
 * should say is what Franconi and Halpin's ORM abstract syntax and
 * semantics says the construct means: a join path is a path expression
 * P.i ➤ [P.j ⋈ PATH], an external uniqueness constraint a uniqueness over
 * the fact types joined on their common player. */
@interface ORMLogicTests : ORMTestCase
@end

@implementation ORMLogicTests

- (ORMModel *)stockMate
{
	return [ORMModel modelOfDocument:[self fixtureDocument:@"StockMate.orm"] reason:NULL];
}

- (ORMConstraint *)constraintNamed:(NSString *)name in:(ORMModel *)model
{
	for (ORMConstraint *constraint in model.constraints) {
		if ([constraint.name isEqualToString:name]) {
			return constraint;
		}
	}
	XCTFail(@"no constraint %@", name);
	return nil;
}

- (NSString *)relationText:(ORMRelation *)relation
{
	[ORMLogic numberVariables:[relation.formula variables]];
	return [relation description];
}

- (void)testAJoinPathJoinsOnTheObjectTypeItPassesThrough
{
	ORMModel *model = [self stockMate];
	ORMConstraint *equality = [self constraintNamed:@"EqualityConstraint1" in:model];
	ORMRoleSequence *second = [equality.roleSequences objectAtIndex:1];
	XCTAssertNotNil([second joinPath]);
	ORMRelation *relation = [ORMLogic relationForSequence:second];
	XCTAssertFalse(relation.isIncomplete);
	XCTAssertEqualObjects([self relationText:relation],
	                      @"[Address, Region] (AddressIsInCountry(Address, Country) and RegionIsPartOfCountry(Region, Country))");
	/* The columns are the variables the facts share them by. */
	ORMFormula *regionFact = [[relation.formula facts] objectAtIndex:1];
	ORMRole *regionRole = [[regionFact.factType visibleRoles] firstObject];
	XCTAssertTrue([regionFact variableForRole:regionRole] == [relation.columns objectAtIndex:1]);
}

- (void)testAJoinPathCanEndInAUnary
{
	ORMModel *model = [self stockMate];
	ORMConstraint *subset = [self constraintNamed:@"SubsetConstraint2" in:model];
	ORMRelation *superset = [ORMLogic relationForSequence:[subset.roleSequences objectAtIndex:1]];
	XCTAssertEqualObjects([self relationText:superset],
	                      @"[Lot, LotType] (LotIsOfLotType(Lot, LotType) and LotTypeTracksLotNumbers(LotType))");
}

- (void)testASequenceWithoutAJoinPathJoinsOnItsCommonPlayer
{
	ORMModel *model = [self stockMate];
	ORMConstraint *subset = [self constraintNamed:@"SubsetConstraint2" in:model];
	ORMRoleSequence *first = [subset.roleSequences firstObject];
	XCTAssertNil([first joinPath]);
	ORMRelation *relation = [ORMLogic relationForSequence:first];
	XCTAssertFalse(relation.isIncomplete);
	XCTAssertEqualObjects([self relationText:relation],
	                      @"[Lot, LotType] (LotHasLotNumber(Lot, LotNumber) and LotIsOfLotType(Lot, LotType))");

	ORMConstraint *unique = [self constraintNamed:@"ExternalUniquenessConstraint3" in:model];
	XCTAssertEqualObjects([self relationText:[ORMLogic relationForSequence:[unique.roleSequences firstObject]]],
	                      @"[Country, RegionISOCode] (RegionIsPartOfCountry(Region, Country) and "
	                      @"RegionHasRegionISOCode(Region, RegionISOCode))");
}

- (void)testASequenceInOneFactTypeIsThatFactType
{
	ORMModel *model = [self stockMate];
	for (ORMConstraint *constraint in model.constraints) {
		for (ORMRoleSequence *sequence in constraint.roleSequences) {
			NSSet *facts = [NSSet setWithArray:[sequence.roles valueForKey:@"factType"]];
			if ([facts count] != 1) {
				continue;
			}
			ORMRelation *relation = [ORMLogic relationForSequence:sequence];
			XCTAssertEqual([[relation.formula facts] count], (NSUInteger)1, @"%@", constraint.name);
			XCTAssertFalse(relation.isIncomplete, @"%@", constraint.name);
			XCTAssertEqual([relation.columns count], [sequence.roles count], @"%@", constraint.name);
		}
	}
}

/* Through an objectification: NORMA names the objectified role and then
 * the link fact type's other role (WaiterTips), or the link fact type's
 * objectified role and then the role its proxy stands for
 * (CinemaTickets). Either way it is one walk through the link fact
 * type. */
- (void)testPathsThroughLinkFactTypes
{
	ORMModel *waiters = [ORMModel modelOfDocument:[self fixtureDocument:@"ActiveFacts/WaiterTips.orm"] reason:NULL];
	ORMConstraint *equality = [self constraintNamed:@"EqualityConstraint1" in:waiters];
	ORMRelation *relation = nil;
	for (ORMRoleSequence *sequence in equality.roleSequences) {
		if ([sequence joinPath] != nil) {
			relation = [ORMLogic relationForSequence:sequence];
		}
	}
	XCTAssertEqualObjects([self relationText:relation],
	                      @"[Waiter, Meal, Amount] (Service(Waiter, Meal) and MealIsInvolvedInService(Meal, Service) and "
	                      @"ServiceEarnedATipOfAmount(Service, Amount))");

	ORMModel *cinema = [ORMModel modelOfDocument:[self fixtureDocument:@"ActiveFacts/CinemaTickets.orm"] reason:NULL];
	for (ORMFactType *fact in cinema.factTypes) {
		if ([fact.name isEqualToString:@"SessionHasSeat"]) {
			relation = [ORMLogic relationForDerivation:[fact derivationRule] of:fact];
		}
	}
	XCTAssertEqualObjects([self relationText:relation],
	                      @"[Session, Seat] (CinemaHasSession(Cinema, Session) and RowIsInCinema(Row, Cinema) and "
	                      @"SeatIsInRow(Seat, Row))");
}

- (void)testVariablesOfOneTypeAreNumbered
{
	ORMModel *model = [self stockMate];
	ORMFactType *ring = nil;
	for (ORMFactType *fact in model.factTypes) {
		if ([fact.name isEqualToString:@"ItemCategoryIsChildOfItemCategory"]) {
			ring = fact;
		}
	}
	XCTAssertEqualObjects([self relationText:[ORMLogic relationForFactType:ring]],
	                      @"[ItemCategory1, ItemCategory2] "
	                      @"ItemCategoryIsChildOfItemCategory(ItemCategory1, ItemCategory2)");
}

@end
