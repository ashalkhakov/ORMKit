/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCDModel.h"

@class NSManagedObjectModel;

/* The model as Core Data's runtime has it, built in memory rather than
 * compiled by momc: what ODataKit's property mapper names the service's
 * entity sets, properties, types and keys from. Entities are of
 * NSManagedObject; what Xcode alone keeps (codegen, positions, the XML
 * ORMKit does not model) is left out. */
@interface ORMCDModel (CoreData)
- (NSManagedObjectModel *)managedObjectModel;
@end
