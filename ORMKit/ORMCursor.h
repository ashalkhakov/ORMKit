/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

@class ORMQueryResult;

/* A plan read as a tree of cursors (docs/CURSORS.md): each gives the next
 * batch of what it reads, and is asked for more. The backends build the
 * leaves and evaluate on their own objects; the rest is here. */

/* What a cursor gives: the objects read, as the backend has them, and what
 * was read for them by name (a bag's tuples by group, a join's objects),
 * which their conditions and rows are evaluated with. */
@interface ORMBatch : NSObject
+ (instancetype)batchWithObjects:(NSArray *)objects answers:(NSDictionary<NSString *, id> *)answers;
@property (nonatomic, readonly, copy) NSArray *objects;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *answers;
/* The same answers, of these objects. */
- (ORMBatch *)batchWithObjects:(NSArray *)objects;
/* These objects, one more answer. */
- (ORMBatch *)batchAnswering:(NSString *)name with:(id)answer;
@end

@protocol ORMCursor <NSObject>
/* Up to count more objects: fewer where something is left out, or at the
 * end. The completion may be called before this returns (a store's), or
 * later on another queue (a service's). */
- (void)next:(NSUInteger)count completion:(void (^)(ORMBatch *batch, NSError *error))completion;
@property (nonatomic, readonly) BOOL atEnd;
@end

/* What evaluates on a backend's objects, a batch at a time: its answers
 * set while it is. */
@protocol ORMBatchEvaluator <NSObject>
@property (nonatomic, copy) NSDictionary<NSString *, id> *answers;
/* Whether the object meets what the read could not ask. */
- (BOOL)keeps:(id)object;
/* Its rows: a tuple for each way it meets the conditions. */
- (NSArray<NSArray *> *)rowsOf:(id)object;
@end

/* The input's objects the evaluator keeps. */
@interface ORMFilterCursor : NSObject <ORMCursor>
- (instancetype)initWithInput:(id<ORMCursor>)input evaluator:(id<ORMBatchEvaluator>)evaluator;
@end

/* What is read for a batch: for the values the scope finds in it (nil, the
 * batch has nothing the read needs), or, without a scope, once for all. */
typedef void (^ORMBindRead)(NSArray *values, void (^done)(id answer, NSError *error));

/* Each batch of the input, with what the read answered for it under the
 * name: a bound join (docs/CURSORS.md). */
@interface ORMBindJoinCursor : NSObject <ORMCursor>
- (instancetype)initWithInput:(id<ORMCursor>)input
                         name:(NSString *)name
                        scope:(NSArray *(^)(ORMBatch *batch))scope
                         read:(ORMBindRead)read;
@end

/* Pages of the input's objects and their rows, no tuple twice. */
@interface ORMPageReader : NSObject
- (instancetype)initWithInput:(id<ORMCursor>)input
                    evaluator:(id<ORMBatchEvaluator>)evaluator
                 columnTitles:(NSArray<NSString *> *)titles;
- (void)nextPage:(NSUInteger)size completion:(void (^)(ORMQueryResult *page, NSError *error))completion;
@property (nonatomic, readonly) BOOL atEnd;
/* Whether rows of different objects can never be the same tuple (the
 * rows list the object read): then an object's rows are compared with its
 * own only, and none is kept from one object to the next. NO by default:
 * every row given is kept, across pages. */
@property (nonatomic) BOOL objectsApart;
/* Whether equal rows are of objects one after another (the input is in
 * the rows' order): then only the last object's rows are kept. NO by
 * default. */
@property (nonatomic) BOOL rowsInOrder;
/* How many rows are kept to give none twice. */
@property (nonatomic, readonly) NSUInteger rowsKept;
@end

/* The order a Scan reads in, made total by the entity's key, and where its
 * next batch starts: after the last object read, by its values in that
 * order (the seek method), not after a number of objects. Each part of
 * the order: @[ its key path from the object read (an array of keys),
 * @(ascending) ]. */
@interface ORMSeek : NSObject
/* The sorts, then each part of the key no sort is by. No key, no seek. */
+ (instancetype)seekWithSorts:(NSArray<NSArray *> *)sorts key:(NSArray<NSString *> *)key;
@property (nonatomic, readonly, copy) NSArray<NSArray *> *order;
/* What comes after the values (the last object's, in the order): each
 * alternative a list of @[ key path, comparison ("=", ">" or "<"), value ],
 * all of which hold. nil where a value is nil (where nothing is, stores
 * order differently): read on by offset then. */
- (NSArray<NSArray<NSArray *> *> *)after:(NSArray *)values;
/* "nr", "name, then nr": the order, to read. */
- (NSString *)orderText;
@end

/* The next batch of a cursor whose completion is called before it returns
 * (a store's); nil, and why, when it fails or would answer later. */
ORMBatch *ORMNextNow(id<ORMCursor> cursor, NSUInteger count, NSError **error);
