/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQuery.h"
#import "ORMCoreDataMapper.h"

/* A conceptual query as a Core Data fetch request, through a mapping: the
 * query names fact types, the request the entities, attributes and
 * relationships they map to, so the query keeps its meaning when the
 * mapping changes (an object type absorbed, a subtype flattened) and only
 * the request is made again.
 *
 *   ORM                                   Core Data
 *   the root object type                  the entity fetched
 *   a step to a value                     the attribute: "rating > 5"
 *   a step through a to-one               a key path: "degree.rating > 5"
 *   a step through a to-many, or an       SUBQUERY(awardeds, $x1, $x1.degree.rating > 5).@count > 0
 *   objectified fact type's entity
 *   a unary                               "isRetired == YES"
 *   a subtype                             entity.name IN {"Professor"}
 *   not                                   NOT (...)
 *   maybe                                 nothing: listed, not required
 *   count(X) > n                          SUBQUERY(..).@count > n
 *   a condition on an entity              on its identifier: "code == \"UQ\""
 *
 * The ticked object types are key paths from the fetched object, to what
 * each one is ("awardeds.degree" for an academic's degrees). Through a
 * to-many they reach every related object, not only those meeting the
 * conditions: the request fetches objects, not the rows ConQuer lists.
 * What cannot be said (a condition on a composite identifier, a step whose
 * fact type maps to nothing) is left out and noted. */

@interface ORMQueryColumn : NSObject
@property (nonatomic, readonly, copy) NSString *title;
@property (nonatomic, readonly, copy) NSString *nodeId;
/* From the fetched object; "self" for the root. */
@property (nonatomic, readonly, copy) NSString *keyPath;
/* The identifier's, for an entity with a simple one: "degree.code". */
@property (nonatomic, readonly, copy) NSString *identifierKeyPath;
@end

@interface ORMQueryFetch : NSObject
- (instancetype)initWithQuery:(ORMQuery *)query coreData:(ORMCDModel *)coreData;
/* Through the mapping (the defaults for nil). */
- (instancetype)initWithQuery:(ORMQuery *)query model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;

/* nil when the root maps to no entity. */
@property (nonatomic, readonly, copy) NSString *entityName;
/* NSPredicate's format: "TRUEPREDICATE" for every object. */
@property (nonatomic, readonly, copy) NSString *predicateFormat;
@property (nonatomic, readonly, copy) NSArray<ORMQueryColumn *> *columns;
/* What could not be said, and was left out. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
- (BOOL)isComplete;

/* The request in Objective-C, to paste. */
- (NSString *)objectiveCSource;
@end
