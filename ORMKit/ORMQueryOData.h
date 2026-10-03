/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryFetch.h"
/* ODataKit's <ODataKit/ODataExpression.h>, imported where they are used. */
@class ODataExpression, ODataQueryOptions;

/* A conceptual query as a request to the OData service ODataKit makes of the
 * mapped Core Data model (docs/ODATA.md): the URL an application, a report
 * or another service sends, in the names the service answers to (the entity
 * sets and properties of its $metadata), built as ODataKit's own expression
 * tree, which is what the service reads it back into.
 *
 *   ORM                                   OData
 *   the root object type                  its entity set: Employees; a
 *                                         subtype's, cast: Branches/Default.USbranch
 *   a step to a value                     $filter=Rating gt 5
 *   a step through a to-one               Degree/Rating gt 5
 *   a step through a to-many              Awardeds/any(x1: x1/Degree/Rating gt 5)
 *   a node met before, out of the lambda  $it/City/Name eq x1/City/Name (objects by key)
 *   a subtype                             isof(x1, Default.Professor)
 *   not                                   not (...)
 *   count(X) > n                          Languages/$count gt 1
 *   total(X) > n                          Employees/aggregate(Salary/Usd with sum) gt 1000000
 *   the ticked object types               $select, and $expand for what is reached
 *   the order                             $orderby=Nr desc
 *
 * As with a fetch request, an object type absorbed into others is joined
 * on its parts' values by a request made first (the service has no $root
 * to say it in one). What OData cannot say (a count of the objects meeting
 * conditions, other than none or some) is noted. */

@interface ORMQueryODataJoin : NSObject
/* What the joined rows are passed as, to -filterJoining:. */
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *entityName;
@property (nonatomic, readonly, copy) NSString *collectionPath;
@property (nonatomic, readonly, strong) ODataQueryOptions *options;
/* Each part: @[ its path on the request's rows, its path on the joined
 * rows ], each a wire path ("CityStateCountry/Name"). */
@property (nonatomic, readonly, copy) NSArray<NSArray<NSArray<NSString *> *> *> *pairs;
/* The request: collection path and query, the options percent-encoded. */
- (NSString *)relativeURLString;
@end

@interface ORMQueryOData : NSObject
- (instancetype)initWithQuery:(ORMQuery *)query coreData:(ORMCDModel *)coreData;
/* Through the mapping (the defaults for nil). */
- (instancetype)initWithQuery:(ORMQuery *)query model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;

/* The entity whose objects are the results; nil when the root maps to none. */
@property (nonatomic, readonly, copy) NSString *entityName;
/* Its entity set, cast to its type when that is derived in the set. */
@property (nonatomic, readonly, copy) NSString *collectionPath;
/* $filter, $select, $expand and $orderby. */
@property (nonatomic, readonly, strong) ODataQueryOptions *options;
@property (nonatomic, readonly, strong) ODataExpression *filter;
/* "$filter=...&$select=...", not percent-encoded: to read. */
- (NSString *)queryText;
/* The request relative to the service root: collection path and query,
 * percent-encoded. */
- (NSString *)relativeURLString;
/* The requests to read: "GET Employees?$filter=...", each join's first. */
- (NSString *)requestText;

/* The requests to make first, each a join of this one's. */
@property (nonatomic, readonly, copy) NSArray<ORMQueryODataJoin *> *joins;
/* The filter with each join's rows, by its name, as the service answered
 * them (JSON objects): its own, and for each join, its parts equal to one
 * row's. */
- (ODataExpression *)filterJoining:(NSDictionary<NSString *, NSArray<NSDictionary *> *> *)joined;

/* What could not be said, and was left out. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
- (BOOL)isComplete;

/* ODataKit's names for the mapped model: what ODataKit's property mapper
 * makes of the userInfo the mapping writes. */
+ (NSString *)wireNameOf:(ORMCDProperty *)property;
+ (NSString *)entitySetOf:(ORMCDEntity *)entity in:(ORMCDModel *)coreData;
+ (NSString *)typeNameOf:(ORMCDEntity *)entity;
/* The attributes the service keys the entity by: its root's OData.key. */
+ (NSArray<ORMCDAttribute *> *)keyOf:(ORMCDEntity *)entity in:(ORMCDModel *)coreData;
@end
