/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlan.h"
#import "ORMQueryInterpreter.h"

@class NSManagedObjectModel;

/* ODataKit's <ODataKit/ODataExpression.h>, imported where they are used. */
@class ODataExpression, ODataQueryOptions;
@protocol ODataTransport;

/* A query plan (ORMQueryPlan.h) as requests to the OData service ODataKit
 * makes of the mapped model (docs/ODATA.md): what an application, a report
 * or another service sends. Every name is ODataKit's (its property mapper's,
 * of the model as Core Data describes it), the request is ODataKit's typed
 * tree, and its URL is written by ODataKit's query builder.
 *
 *   the plan                              OData
 *   read Employee                         Employees; a subentity's, cast:
 *                                         Branches/Default.USbranch
 *   compare, is set                       Rating gt 5, Branch ne null
 *   some collection as x1 has ...         Awardeds/any(x1:...)
 *   number of ... having ... > n          Cars/$count($filter=...) gt n, the
 *                                         member $this (OData 4.01); any or
 *                                         not any for some or none
 *   sum of x.salary.usd over employees    Employees/aggregate(Salary/Usd with sum)
 *   is a Professor                        isof(x1,Default.Professor)
 *   is (the same object), is among        by key: x1/Id eq $it/Id; back
 *                                         along the inverses to $it
 *   ... match [read Branch ...]           a request made first (the service
 *                                         has no $root), its rows put in the
 *                                         filter by -filterJoining:error:
 *   columns, order                        $select and $expand, $orderby
 *
 * What OData cannot say (an aggregate of the members meeting conditions; a
 * join whose objects depend on each object read) is noted. A name ODataKit's builders refuse (one that is no identifier, a
 * model's OData.property, say) is an error: no request is made. */

@interface ORMQueryODataJoin : NSObject
/* Where its rows go in the request's filter, and the key -filterJoining:
 * takes them by. */
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *entityName;
@property (nonatomic, readonly, copy) NSString *collectionPath;
@property (nonatomic, readonly, strong) ODataQueryOptions *options;
/* Each part: @[ its path on the request's side, its path on the joined
 * rows ], each a wire path ("CityStateCountry/Name"). */
@property (nonatomic, readonly, copy) NSArray<NSArray<NSArray<NSString *> *> *> *pairs;
- (NSURL *)URLWithServiceRoot:(NSURL *)serviceRoot error:(NSError **)error;
@end

/* A plan being read from the service, a page at a time, through a
 * transport (ODataKit's: the network, or a service in process). A page is
 * one request for the plan's objects, and for each join one more, asking
 * which of that page's values the joined objects have (grouped, so each
 * once): never a request per object. Its objects are the entities as the
 * service gives them (JSON), its rows the columns' values, no tuple twice. */
@interface ORMQueryODataCursor : NSObject
/* Up to size more objects; none at the end. The completion is called on
 * whatever queue the transport answers on. */
- (void)nextPage:(NSUInteger)size completion:(void (^)(ORMQueryResult *page, NSError *error))completion;
@property (nonatomic, readonly) BOOL atEnd;
@end

@interface ORMQueryOData : NSObject
/* The plan as requests to the service of the Core Data model: nil, and
 * why, when a name the plan reaches is one ODataKit refuses. ORMKit makes
 * one of an ORM query too (ORMQueryOData+ORMKit.h). */
+ (instancetype)requestForPlan:(ORMQueryPlan *)plan model:(NSManagedObjectModel *)model error:(NSError **)error;

@property (nonatomic, readonly, strong) ORMQueryPlan *plan;
/* The entity whose objects are the results; nil when the plan reads none. */
@property (nonatomic, readonly, copy) NSString *entityName;
/* Its entity set, cast to its type when that is derived in the set. */
@property (nonatomic, readonly, copy) NSString *collectionPath;
/* $filter, $select, $expand and $orderby. */
@property (nonatomic, readonly, strong) ODataQueryOptions *options;
@property (nonatomic, readonly, strong) ODataExpression *filter;
/* "$filter=...&$select=...", not percent-encoded: to read. */
- (NSString *)queryText;
/* The requests to read: "GET Employees?$filter=...", each join's first. */
- (NSString *)requestText;
- (NSURL *)URLWithServiceRoot:(NSURL *)serviceRoot error:(NSError **)error;

/* The requests to make first, each a join of this one's. */
@property (nonatomic, readonly, copy) NSArray<ORMQueryODataJoin *> *joins;
/* The filter with each join's rows, by its name, as the service answered
 * them (JSON objects), in its place: its parts equal to one row's. */
- (ODataExpression *)filterJoining:(NSDictionary<NSString *, NSArray<NSDictionary *> *> *)joined error:(NSError **)error;
/* The request with the joins' rows, at the service's root. */
- (NSURL *)URLJoining:(NSDictionary<NSString *, NSArray<NSDictionary *> *> *)joined
          serviceRoot:(NSURL *)serviceRoot
                error:(NSError **)error;

/* The joins asked for page by page: a join among the plan's conditions
 * (not under a not, an or or a some), uncorrelated, or correlated by the
 * joined objects' parts equal to the object read's. Each a request whose
 * filter -cursorWithTransport:serviceRoot: adds the page's values to. */
@property (nonatomic, readonly, copy) NSArray<ORMQueryODataJoin *> *pageJoins;
/* The correlated joins no page join says (under a not, an or or a
 * lambda): the joined objects read whole once, filtered by what does not
 * depend on the object read, and the conditions they are in checked on
 * the answers. */
@property (nonatomic, readonly, copy) NSArray<ORMQueryODataJoin *> *wholeJoins;
/* The bags the plan's aggregates are of, each a request of its own, by
 * its name: read whole once, before the first page, and the aggregates
 * worked out of its rows. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, ORMQueryOData *> *bags;
/* The plan read from the service at the root, through the transport. */
- (ORMQueryODataCursor *)cursorWithTransport:(id<ODataTransport>)transport serviceRoot:(NSURL *)serviceRoot;

/* The plan's notes, and what OData could not say. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
- (BOOL)isComplete;
@end
