/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataMapper.h"

/* A mapped Core Data model made ready for ODataKit to serve: its userInfo
 * says what $metadata cannot be told by Core Data alone (docs/ODATA.md).
 *
 *   ORM                                   ODataKit's userInfo
 *   an entity's plural name               OData.entitySet, on a root entity
 *   the preferred identifier, where       OData.key = YES on each attribute
 *     every role of it is an attribute
 *   any other identifier                  a surrogate: an Integer64 "id",
 *                                         OData.key and OData.computed, that
 *                                         the service numbers on insert
 *   a definition                          OData.description
 *   a value list, an open bound           OData.annotations: AllowedValues,
 *                                         Minimum@Exclusive, Maximum@Exclusive
 *
 * Minimums, maximums and patterns Core Data holds already, and ODataKit
 * reads them from there. Subentities are served in their root's set, by its
 * key, and get neither. */

@interface ORMODataAnnotator : NSObject
- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;
/* Annotates the model in place, adding the surrogates; what it noted. */
- (NSArray<ORMMappingNote *> *)annotate:(ORMCDModel *)coreData;
@end
