/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataMapper.h"

/* A mapped Core Data model made ready for ODataKit to serve: its userInfo
 * says what $metadata cannot be told by Core Data alone (docs/ODATA.md).
 *
 *   ORM                                   ODataKit's userInfo
 *   an entity's plural name               OData.entitySet, on a root entity
 *   its name in the mapping's namespace   OData.type: Default.Employee
 *   the preferred identifier, where       OData.key = YES on each attribute
 *     every role of it is an attribute
 *   any other identifier                  a surrogate: a UUID "id", OData.key
 *                                         and ormkit.surrogate, that whoever
 *                                         makes the object gives it (a client
 *                                         offline too)
 *   a definition                          OData.description
 *   a value list, an open bound           OData.annotations: AllowedValues,
 *                                         Minimum@Exclusive, Maximum@Exclusive
 *
 * and, for offline sync (ODataKit's ODataSync), where the mapping says a
 * direction (-[ORMCoreDataMapping syncDirectionOf:]):
 *
 *   the entity's direction                ODataSync.direction: down, up, both
 *   its conflict rule (both)              ODataSync.conflicts
 *   what a device changes (up, both)      bookkeeping attributes, optional
 *                                         Strings marked ormkit.bookkeeping:
 *                                         syncVersions (ODataSync.versions),
 *                                         syncModified (ODataSync.modified);
 *                                         its key preserveAfterDeletion
 *
 * Minimums, maximums and patterns Core Data holds already, and ODataKit
 * reads them from there. Subentities are served in their root's set, by its
 * key, and get neither. */

@interface ORMODataAnnotator : NSObject
- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;
/* Annotates the model in place, adding the surrogates; what it noted. */
- (NSArray<ORMMappingNote *> *)annotate:(ORMCDModel *)coreData;
@end
