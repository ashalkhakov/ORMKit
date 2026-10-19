/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTestSupport.h"

/* An aggregate over a window (ORMWindow, docs/QUERIES.md): a group's
 * tuples sorted by a column once, each object's answered by its value. */
@interface ORMWindowTests : ORMTestCase
@end

@implementation ORMWindowTests

/* @[ key, value ]: two tuples tie at 20, one has no key. */
- (NSArray *)tuples
{
	return @[ @[ @30, @3 ], @[ @10, @1 ], @[ @20, @2 ], @[ @20, @5 ], @[ [NSNull null], @100 ], @[ @40, [NSNull null] ] ];
}

- (id)of:(NSString *)function where:(NSString *)comparison than:(id)value
{
	ORMWindow *window = [ORMWindow windowOf:[self tuples] key:0 value:1 function:function order:ORMWindowCompare];
	return [window aggregateWhereKey:comparison than:value];
}

- (void)testEachSideOfAValue
{
	/* Below 20: the tuple at 10; at most 20: the ties too. */
	XCTAssertEqualObjects([self of:@"max" where:@"<" than:@20], @1);
	XCTAssertEqualObjects([self of:@"max" where:@"<=" than:@20], @5);
	XCTAssertEqualObjects([self of:@"min" where:@">" than:@20], @3);
	XCTAssertEqualObjects([self of:@"min" where:@">=" than:@20], @2);
	/* A value between keys, and one past them all. */
	XCTAssertEqualObjects([self of:@"max" where:@"<" than:@25], @5);
	XCTAssertEqualObjects([self of:@"count" where:@"<" than:@1000], @4);
	/* The key without a value counts for nothing; without a key, never. */
	XCTAssertEqualObjects([self of:@"count" where:@">" than:@30], @0);
	XCTAssertEqualObjects([[self of:@"sum" where:@">=" than:@20] description], @"10");
	XCTAssertEqualWithAccuracy([[self of:@"average" where:@"<=" than:@20] doubleValue], 8.0 / 3.0, 1e-9);
}

- (id)of:(NSString *)function where:(NSString *)comparison than:(id)value and:(NSString *)other than:(id)otherValue
{
	ORMWindow *window = [ORMWindow windowOf:[self tuples] key:0 value:1 function:function order:ORMWindowCompare];
	return [window aggregateWhereKey:comparison than:value and:other than:otherValue];
}

/* Between two bounds: (10, 30] is the ties at 20 and 30. */
- (void)testBetweenTwoValues
{
	XCTAssertEqualObjects([self of:@"count" where:@">" than:@10 and:@"<=" than:@30], @3);
	XCTAssertEqualObjects([[self of:@"sum" where:@">" than:@10 and:@"<=" than:@30] description], @"10");
	XCTAssertEqualObjects([self of:@"max" where:@">=" than:@20 and:@"<" than:@40], @5);
	XCTAssertEqualObjects([self of:@"min" where:@">" than:@20 and:@"<=" than:@40], @3);
	XCTAssertEqualObjects([self of:@"max" where:@">=" than:@10 and:@"<=" than:@40], @5);
	/* Bounds that admit nothing. */
	XCTAssertEqualObjects([self of:@"count" where:@">" than:@30 and:@"<" than:@20], @0);
	XCTAssertNil([self of:@"min" where:@">" than:@30 and:@"<" than:@40]);
	XCTAssertNil([self of:@"max" where:@">" than:@10 and:@"<" than:[NSNull null]]);
}

- (void)testNoneOnASide
{
	XCTAssertNil([self of:@"max" where:@"<" than:@10]);
	XCTAssertEqualObjects([self of:@"count" where:@"<" than:@10], @0);
	XCTAssertEqualObjects([[self of:@"sum" where:@"<" than:@10] description], @"0");
	XCTAssertNil([self of:@"average" where:@">" than:@40]);
	/* Compared with nothing: no comparison holds. */
	XCTAssertNil([self of:@"max" where:@"<" than:[NSNull null]]);
	XCTAssertEqualObjects([self of:@"count" where:@">=" than:nil], @0);
}

@end
