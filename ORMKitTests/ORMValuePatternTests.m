/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* A value type's pattern: what NORMA has no constraint for, kept in
 * ORMKit's own namespace, said and read as a sentence, held by Core Data
 * and checked in sample populations. */
@interface ORMValuePatternTests : ORMTestCase
@end

@implementation ORMValuePatternTests

- (ORMEditor *)editorWith:(NSArray<NSString *> *)sentences
{
	ORMEditor *editor = [self newEditor];
	NSString *diagram = [[editor.model.diagrams firstObject] identifier];
	for (NSString *text in sentences) {
		NSString *reason = nil;
		XCTAssertNotNil([[[ORMSentenceEditor alloc] initWithEditor:editor] addFromSentence:text onDiagram:diagram
		                                                                                at:ORMAutomaticPlacement
		                                                                            reason:&reason],
		                @"%@: %@", text, reason);
	}
	return editor;
}

- (ORMEditor *)vehicles
{
	return [self editorWith:@[ @"VIN is a value type.", @"Vehicle(.id) has VIN", @"Each Vehicle has at most one VIN.",
	                           @"Vehicle uses Currency(.code)", @"Each Vehicle uses exactly one Currency.",
	                           @"The possible values of VIN match the pattern '[A-HJ-NPR-Z0-9]{17}'.",
	                           @"The possible values of Currency match the pattern '[A-Z]{3}'.",
	                           @"The possible values of Currency are 'EUR', 'USD', 'eur'." ]];
}

/* Said as it was read; on an entity type, its reference mode's. */
- (void)testAPatternFromASentenceIsSaidBack
{
	ORMEditor *editor = [self vehicles];
	ORMModel *model = editor.model;
	XCTAssertEqualObjects([[model objectTypeNamed:@"VIN"] valuePattern], @"[A-HJ-NPR-Z0-9]{17}");
	XCTAssertEqualObjects([[model objectTypeNamed:@"Currency_code"] valuePattern], @"[A-Z]{3}");
	NSArray *said = [[[[ORMVerbalizer alloc] initWithModel:model] sentencesForElement:[[model objectTypeNamed:@"VIN"] identifier]]
		valueForKey:@"text"];
	XCTAssertTrue([said containsObject:@"The possible values of VIN match the pattern '[A-HJ-NPR-Z0-9]{17}'."], @"%@", said);
	NSString *reason = nil;
	XCTAssertFalse([editor.objectTypeEditor setValuePattern:@"[A-Z" of:[[model objectTypeNamed:@"VIN"] identifier]
	                                                 reason:&reason]);
	XCTAssertTrue([reason length] > 0);
	/* One step to undo, and to redo. */
	[self.undoManager undo];
	XCTAssertNil([[editor.model objectTypeNamed:@"Currency_code"] valueConstraint]);
	[self.undoManager undo];
	XCTAssertNil([[editor.model objectTypeNamed:@"Currency_code"] valuePattern]);
	[self.undoManager redo];
	XCTAssertEqualObjects([[editor.model objectTypeNamed:@"Currency_code"] valuePattern], @"[A-Z]{3}");
}

/* In the value type's element, in ORMKit's namespace: read back the same,
 * and left out of the copy for NORMA. */
- (void)testAPatternIsKeptInTheFileAndNotGivenToNorma
{
	ORMEditor *editor = [self vehicles];
	NSData *saved = [editor dataForSaving];
	ORMModel *again = [ORMModel modelOfDocument:ORMParseDocument(saved, NULL) reason:NULL];
	XCTAssertEqualObjects([[again objectTypeNamed:@"VIN"] valuePattern], @"[A-HJ-NPR-Z0-9]{17}");
	NSString *text = [[NSString alloc] initWithData:saved encoding:NSUTF8StringEncoding];
	XCTAssertTrue([text rangeOfString:@"<ormv:Pattern>[A-HJ-NPR-Z0-9]{17}</ormv:Pattern>"].location != NSNotFound);
	NSString *norma = [[NSString alloc] initWithData:ORMDataOfDocument([editor documentForNorma])
	                                        encoding:NSUTF8StringEncoding];
	XCTAssertEqual([norma rangeOfString:@"Pattern"].location, (NSUInteger)NSNotFound);
	/* Taken away, it leaves nothing. */
	XCTAssertTrue([editor.objectTypeEditor setValuePattern:nil of:[[editor.model objectTypeNamed:@"VIN"] identifier]
	                                                reason:NULL]);
	text = [[NSString alloc] initWithData:[editor dataForSaving] encoding:NSUTF8StringEncoding];
	XCTAssertEqual([text rangeOfString:@"[A-HJ-NPR-Z0-9]{17}"].location, (NSUInteger)NSNotFound);
}

/* Core Data holds it, beside a list of values as a lookahead. */
- (void)testCoreDataHoldsThePattern
{
	ORMEditor *editor = [self vehicles];
	ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:nil] map];
	XCTAssertNil([self momcRejects:mapped]);
	ORMCDEntity *vehicle = [mapped entityNamed:@"Vehicle"];
	NSMutableDictionary *expressions = [NSMutableDictionary dictionary];
	for (ORMCDAttribute *attribute in vehicle.attributes) {
		if (attribute.regularExpression != nil) {
			[expressions setObject:attribute.regularExpression forKey:attribute.name];
		}
	}
	XCTAssertEqualObjects([expressions objectForKey:@"vin"], @"^(?:[A-HJ-NPR-Z0-9]{17})$");
	/* Currency is an entity of its own, its code an attribute. */
	NSString *currency = nil;
	for (ORMCDAttribute *attribute in [mapped entityNamed:@"Currency"].attributes) {
		currency = attribute.regularExpression ?: currency;
	}
	XCTAssertEqualObjects(currency, @"^(?=(?:[A-Z]{3})$)(?:EUR|USD|eur)$");
	NSPredicate *matches = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", currency];
	XCTAssertTrue([matches evaluateWithObject:@"EUR"]);
	XCTAssertFalse([matches evaluateWithObject:@"eur"]);
	XCTAssertFalse([matches evaluateWithObject:@"GBP"]);
}

/* A sample population's values are checked against it. */
- (void)testASamplePopulationIsChecked
{
	ORMEditor *editor = [self vehicles];
	NSString *vin = [[editor.model objectTypeNamed:@"VIN"] identifier];
	XCTAssertNotNil([editor.populationEditor addInstanceOf:vin named:@"WVWZZZ1KZEW000001" reason:NULL]);
	XCTAssertNotNil([editor.populationEditor addInstanceOf:vin named:@"WVWZZZ1KZEW00000O" reason:NULL]);
	NSArray *texts = [[[[ORMPopulationChecker alloc] initWithModel:editor.model] violations] valueForKey:@"text"];
	XCTAssertEqualObjects(texts, (@[ @"'WVWZZZ1KZEW00000O' does not match VIN's pattern '[A-HJ-NPR-Z0-9]{17}'." ]),
	                      @"%@", texts);
}

@end
