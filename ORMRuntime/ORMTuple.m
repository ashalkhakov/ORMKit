/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTuple.h"

@implementation ORMTuple
{
	NSArray *_values;
	NSUInteger _hash;
}

+ (instancetype)tupleWithValues:(NSArray *)values
{
	if ([values isKindOfClass:[ORMTuple class]]) {
		return (ORMTuple *)values;
	}
	ORMTuple *tuple = [[self alloc] init];
	tuple->_values = [values copy];
	NSUInteger hash = [values count];
	for (id value in values) {
		hash = (hash << 5 | hash >> (sizeof(NSUInteger) * 8 - 5)) ^ [value hash];
	}
	tuple->_hash = hash;
	return tuple;
}

- (NSUInteger)count
{
	return [_values count];
}

- (id)objectAtIndex:(NSUInteger)index
{
	return [_values objectAtIndex:index];
}

- (NSArray *)values
{
	return _values;
}

- (NSUInteger)hash
{
	return _hash;
}

- (BOOL)isEqual:(id)other
{
	if (other == self) {
		return YES;
	}
	if (![other isKindOfClass:[ORMTuple class]] || ((ORMTuple *)other)->_hash != _hash) {
		return NO;
	}
	return [_values isEqualToArray:((ORMTuple *)other)->_values];
}

- (id)copyWithZone:(NSZone *)zone
{
	return self;
}

@end
