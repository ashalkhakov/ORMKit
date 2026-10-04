/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCursor.h"
#import "ORMQueryInterpreter.h"
#import "ORMQueryPlan.h"

@implementation ORMBatch

+ (instancetype)batchWithObjects:(NSArray *)objects answers:(NSDictionary<NSString *, id> *)answers
{
	ORMBatch *batch = [[self alloc] init];
	batch->_objects = [objects copy] ?: @[];
	batch->_answers = [answers copy] ?: @{};
	return batch;
}

- (ORMBatch *)batchWithObjects:(NSArray *)objects
{
	return [ORMBatch batchWithObjects:objects answers:_answers];
}

- (ORMBatch *)batchAnswering:(NSString *)name with:(id)answer
{
	NSMutableDictionary *answers = [NSMutableDictionary dictionaryWithDictionary:_answers];
	[answers setObject:answer ?: [NSNull null] forKey:name];
	return [ORMBatch batchWithObjects:_objects answers:answers];
}

@end

#pragma mark Filter

@implementation ORMFilterCursor
{
	id<ORMCursor> _input;
	id<ORMBatchEvaluator> _evaluator;
}

- (instancetype)initWithInput:(id<ORMCursor>)input evaluator:(id<ORMBatchEvaluator>)evaluator
{
	if ((self = [super init])) {
		_input = input;
		_evaluator = evaluator;
	}
	return self;
}

- (BOOL)atEnd
{
	return _input.atEnd;
}

- (void)next:(NSUInteger)count completion:(void (^)(ORMBatch *batch, NSError *error))completion
{
	[_input next:count completion:^(ORMBatch *batch, NSError *error) {
		if (batch == nil) {
			completion(nil, error);
			return;
		}
		NSMutableArray *kept = [NSMutableArray array];
		self->_evaluator.answers = batch.answers;
		for (id object in batch.objects) {
			if ([self->_evaluator keeps:object]) {
				[kept addObject:object];
			}
		}
		self->_evaluator.answers = nil;
		completion([batch batchWithObjects:kept], nil);
	}];
}

@end

#pragma mark Bound joins

@implementation ORMBindJoinCursor
{
	id<ORMCursor> _input;
	NSString *_name;
	NSArray * (^_scope)(ORMBatch *);
	ORMBindRead _read;
	/* Without a scope, what was read once. */
	id _whole;
}

- (instancetype)initWithInput:(id<ORMCursor>)input
                         name:(NSString *)name
                        scope:(NSArray *(^)(ORMBatch *batch))scope
                         read:(ORMBindRead)read
{
	if ((self = [super init])) {
		_input = input;
		_name = [name copy];
		_scope = [scope copy];
		_read = [read copy];
	}
	return self;
}

- (BOOL)atEnd
{
	return _input.atEnd;
}

- (void)next:(NSUInteger)count completion:(void (^)(ORMBatch *batch, NSError *error))completion
{
	[_input next:count completion:^(ORMBatch *batch, NSError *error) {
		if (batch == nil) {
			completion(nil, error);
			return;
		}
		if ([batch.objects count] == 0) {
			completion(batch, nil);
			return;
		}
		if (self->_scope == nil && self->_whole != nil) {
			completion([batch batchAnswering:self->_name with:self->_whole], nil);
			return;
		}
		NSArray *values = self->_scope != nil ? self->_scope(batch) : nil;
		self->_read(values, ^(id answer, NSError *failed) {
			if (answer == nil) {
				completion(nil, failed);
				return;
			}
			if (self->_scope == nil) {
				self->_whole = answer;
			}
			completion([batch batchAnswering:self->_name with:answer], nil);
		});
	}];
}

@end

#pragma mark Pages

@implementation ORMPageReader
{
	id<ORMCursor> _input;
	id<ORMBatchEvaluator> _evaluator;
	NSArray<NSString *> *_titles;
	NSMutableSet<NSArray *> *_given;
}

- (instancetype)initWithInput:(id<ORMCursor>)input
                    evaluator:(id<ORMBatchEvaluator>)evaluator
                 columnTitles:(NSArray<NSString *> *)titles
{
	if ((self = [super init])) {
		_input = input;
		_evaluator = evaluator;
		_titles = [titles copy];
		_given = [NSMutableSet set];
	}
	return self;
}

- (BOOL)atEnd
{
	return _input.atEnd;
}

/* The batch's objects and rows, with its answers, added to the page. */
- (void)take:(ORMBatch *)batch objects:(NSMutableArray *)objects rows:(NSMutableArray *)rows
{
	_evaluator.answers = batch.answers;
	for (id object in batch.objects) {
		for (NSArray *tuple in [_evaluator rowsOf:object]) {
			if (![_given containsObject:tuple]) {
				[_given addObject:tuple];
				[rows addObject:tuple];
			}
		}
	}
	_evaluator.answers = nil;
	[objects addObjectsFromArray:batch.objects];
}

/* Batches until the page has its objects or the input is at its end: in
 * a loop while the input answers at once, from its completion when it
 * answers later. */
- (void)fill:(NSMutableArray *)objects
        rows:(NSMutableArray *)rows
        size:(NSUInteger)size
  completion:(void (^)(ORMQueryResult *page, NSError *error))completion
{
	while ([objects count] < size && !_input.atEnd) {
		NSObject *token = [[NSObject alloc] init];
		__block BOOL answered = NO, returned = NO;
		__block ORMBatch *next = nil;
		__block NSError *failed = nil;
		[_input next:size - [objects count] completion:^(ORMBatch *batch, NSError *error) {
			BOOL later = NO;
			@synchronized(token) {
				answered = YES;
				next = batch;
				failed = error;
				later = returned;
			}
			if (!later) {
				return;
			}
			if (batch == nil) {
				completion(nil, error);
				return;
			}
			[self take:batch objects:objects rows:rows];
			[self fill:objects rows:rows size:size completion:completion];
		}];
		BOOL now = NO;
		@synchronized(token) {
			returned = YES;
			now = answered;
		}
		if (!now) {
			/* Its completion goes on. */
			return;
		}
		if (next == nil) {
			completion(nil, failed);
			return;
		}
		[self take:next objects:objects rows:rows];
	}
	completion([ORMQueryResult resultWithObjects:objects columnTitles:_titles rows:rows], nil);
}

- (void)nextPage:(NSUInteger)size completion:(void (^)(ORMQueryResult *page, NSError *error))completion
{
	[self fill:[NSMutableArray array] rows:[NSMutableArray array] size:MAX(size, (NSUInteger)1) completion:completion];
}

@end

ORMBatch *
ORMNextNow(id<ORMCursor> cursor, NSUInteger count, NSError **error)
{
	__block ORMBatch *next = nil;
	__block NSError *failed = nil;
	__block BOOL answered = NO;
	[cursor next:count completion:^(ORMBatch *batch, NSError *why) {
		next = batch;
		failed = why;
		answered = YES;
	}];
	if (!answered) {
		failed = [NSError errorWithDomain:ORMQueryPlanErrorDomain code:3
		                         userInfo:@{ NSLocalizedDescriptionKey: @"A cursor that should answer at once did not." }];
	}
	if (next == nil && error != NULL) {
		*error = failed;
	}
	return next;
}
