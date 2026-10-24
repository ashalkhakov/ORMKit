/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* A derivation query written as NORMA's role path (ORMDerivationPathWriter,
 * docs/DERIVATION.md): NORMA has the rule, not only its words. */
@interface ORMDerivationPathTests : ORMTestCase
@end

@implementation ORMDerivationPathTests

- (ORMEditor *)people
{
	ORMEditor *editor = [self newEditor];
	NSString *text = @"Person(.name) lives in City(.name)\n"
	                 @"Each Person lives in at most one City.\n"
	                 @"City is in Country(.code)\n"
	                 @"Each City is in exactly one Country.\n"
	                 @"Population is a value type.\n"
	                 @"Portable data type: Numeric: Unsigned Integer\n"
	                 @"City has Population\n"
	                 @"Each City has at most one Population.\n"
	                 @"Person comes from Country\n"
	                 @"Person is urban\n"
	                 @"Person is homeless\n"
	                 @"Residents is a value type.\n"
	                 @"Portable data type: Numeric: Unsigned Integer\n"
	                 @"City has Residents\n"
	                 @"Each City has at most one Residents.\n"
	                 @"Person was born in Country\n"
	                 @"Person stayed\n"
	                 @"Person is placed\n"
	                 @"Person speaks Language(.name)\n"
	                 @"Person is a polyglot\n"
	                 @"Area is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"City has Area\n"
	                 @"Each City has at most one Area.\n"
	                 @"Density is a value type.\n"
	                 @"Portable data type: Numeric: Decimal\n"
	                 @"City has Density\n"
	                 @"Each City has at most one Density.\n"
	                 @"\n"
	                 @"Query Dense:\n"
	                 @"Derivation of \"City has Density\":\n"
	                 @"✓City\n"
	                 @"  + has Population\n"
	                 @"  + has Area\n"
	                 @"  ✓Ratio: Density = Population / Area\n"
	                 @"\n"
	                 @"Query ComesFrom:\n"
	                 @"Derivation of \"Person comes from Country\":\n"
	                 @"✓Person\n"
	                 @"  + lives in City\n"
	                 @"    + is in ✓Country\n"
	                 @"\n"
	                 @"Query Urban:\n"
	                 @"Derivation of \"Person is urban\":\n"
	                 @"✓Person\n"
	                 @"  + lives in City\n"
	                 @"    + has Population > 1000000\n"
	                 @"\n"
	                 @"Query Homeless:\n"
	                 @"Derivation of \"Person is homeless\":\n"
	                 @"✓Person\n"
	                 @"  + not lives in City\n"
	                 @"\n"
	                 @"Query Counted:\n"
	                 @"Derivation of \"City has Residents\":\n"
	                 @"✓City\n"
	                 @"  + Person lives in that City\n"
	                 @"  ✓Count: Residents = count(Person) for City\n"
	                 @"\n"
	                 @"Query Stayed:\n"
	                 @"Derivation of \"Person stayed\":\n"
	                 @"✓Person\n"
	                 @"  + was born in Country1\n"
	                 @"  + lives in City\n"
	                 @"    + is in Country1\n"
	                 @"\n"
	                 @"Query Placed:\n"
	                 @"Derivation of \"Person is placed\":\n"
	                 @"✓Person\n"
	                 @"  + lives in City\n"
	                 @"  + or was born in Country\n"
	                 @"\n"
	                 @"Query Polyglot:\n"
	                 @"Derivation of \"Person is a polyglot\":\n"
	                 @"✓Person\n"
	                 @"  + speaks Language\n"
	                 @"    + count(Language) for Person > 1\n";
	NSArray *failures = nil;
	XCTAssertTrue([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromText:text failures:&failures], @"%@", failures);
	return editor;
}

- (ORMFactType *)factType:(NSString *)reading in:(ORMModel *)model
{
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		if ([[[fact primaryReading] expandedText] isEqualToString:reading]) {
			return fact;
		}
	}
	return nil;
}

/* The data without ORMKit's queries: what NORMA reads. */
- (NSData *)withoutQueries:(NSData *)data
{
	NSXMLDocument *document = ORMParseDocument(data, NULL);
	ORMDetach(ORMChild([document rootElement], ORMQueryNamespace, @"Queries"));
	return ORMDataOfDocument(document);
}

/* What the verbalizer says of the fact type's rule, formally. */
- (NSString *)derivationOf:(NSString *)reading in:(ORMModel *)model
{
	ORMFactType *fact = [self factType:reading in:model];
	NSArray *said = [[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:fact.identifier];
	for (NSString *text in [said valueForKey:@"text"]) {
		if ([text hasPrefix:@"* "]) {
			return text;
		}
	}
	return nil;
}

/* The rule of each fact type the path says, read as NORMA reads it
 * (without ORMKit's queries), as the query does: in NORMA's words where
 * they are its own (a range, "for that Person"). */
- (void)testTheRuleIsWrittenAsNormasPath
{
	ORMEditor *editor = [self people];
	NSData *data = [editor dataForSaving];
	ORMModel *norma = [ORMModel modelOfDocument:ORMParseDocument([self withoutQueries:data], NULL) reason:NULL];
	for (NSString *reading in @[ @"Person comes from Country", @"Person is homeless", @"Person stayed", @"Person is placed" ]) {
		ORMDerivationRule *rule = [[self factType:reading in:norma] derivationRule];
		XCTAssertEqual([rule.paths count], 1u, @"%@", reading);
		XCTAssertEqualObjects([self derivationOf:reading in:norma], [self derivationOf:reading in:editor.model], @"%@", reading);
	}
	XCTAssertEqualObjects([self derivationOf:@"Person is urban" in:norma],
	                      @"* For each Person, that Person is urban if and only if that Person lives in some City that has "
	                      @"some Population in {(1000000..]}.");
	XCTAssertEqualObjects([self derivationOf:@"City has Residents" in:norma],
	                      @"* For each City and Residents, that City has that Residents if and only if some Person lives in "
	                      @"that City and that Residents is the number of that Person for that City.");
	XCTAssertEqualObjects([self derivationOf:@"City has Density" in:norma],
	                      @"* For each City and Density, that City has that Density if and only if that City has some "
	                      @"Population and has some Area and that Density is that Population divided by that Area.");
	XCTAssertEqualObjects([self derivationOf:@"Person is a polyglot" in:norma],
	                      @"* For each Person, that Person is a polyglot if and only if that Person speaks some Language and "
	                      @"the number of that Language for that Person is greater than 1.");
	/* The functions calculated with, declared by the model. */
	NSXMLDocument *document = ORMParseDocument(data, NULL);
	NSXMLElement *functions = ORMChild(ORMChild([document rootElement], ORMCoreNamespace, @"ORMModel"), ORMCoreNamespace,
	                                   @"Functions");
	NSMutableArray *names = [NSMutableArray array];
	for (NSXMLElement *function in ORMChildren(functions, ORMCoreNamespace, @"Function")) {
		[names addObject:ORMAttribute(function, @"Name")];
	}
	XCTAssertEqualObjects([names sortedArrayUsingSelector:@selector(compare:)], (@[ @"count", @"divide", @"greaterThan" ]));

	/* Read again, the rule is the query's, and written the same: every
	 * element written from the model, the same bytes. */
	document = ORMParseDocument(data, NULL);
	ORMModel *model = [ORMModel modelOfDocument:document reason:NULL];
	XCTAssertEqual([[[self factType:@"Person comes from Country" in:model] derivationRule].paths count], 0u);
	[[[ORMNormaWriter alloc] initWithModel:model] writeModel];
	XCTAssertEqualObjects(ORMDataOfDocument(document), data);
}

/* An edit of the query is one of its path; a query gone takes its rule. */
- (void)testThePathFollowsTheQuery
{
	ORMEditor *editor = [self people];
	ORMQuery *urban = nil;
	for (ORMQuery *query in [ORMQuery queriesInModel:editor.model]) {
		urban = [query.name isEqualToString:@"Urban"] ? query : urban;
	}
	ORMQueryNode *population = nil;
	for (ORMQueryNode *node in [urban nodes]) {
		population = [node.objectType.name isEqualToString:@"Population"] ? node : population;
	}
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	NSString *reason = nil;
	XCTAssertTrue([queries setCondition:@">=" value:@"500000" ofNode:population.identifier reason:&reason], @"%@", reason);
	ORMModel *norma = [ORMModel modelOfDocument:ORMParseDocument([self withoutQueries:[editor dataForSaving]], NULL) reason:NULL];
	XCTAssertEqualObjects([self derivationOf:@"Person is urban" in:norma],
	                      @"* For each Person, that Person is urban if and only if that Person lives in some City that has "
	                      @"some Population in {500000..}.");
	[queries removeQuery:urban.identifier];
	XCTAssertNil(ORMChild([self factType:@"Person is urban" in:editor.model].element, ORMCoreNamespace, @"DerivationRule"));
	[self.undoManager undo];
	norma = [ORMModel modelOfDocument:ORMParseDocument([self withoutQueries:[editor dataForSaving]], NULL) reason:NULL];
	XCTAssertEqual([[[self factType:@"Person is urban" in:norma] derivationRule].paths count], 1u);
}

@end
