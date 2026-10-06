/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMSaveHook.h"
#import "ORMQueryInterpreter.h"
#import "ORMValidator.h"
#import <CoreData/CoreData.h>

/* What the property holds, as a set: nothing, one value, or a to-many's
 * objects. */
static NSSet *
ORMRelated(id object, NSString *key)
{
	id value = [object valueForKey:key];
	if (value == nil) {
		return [NSSet set];
	}
	if ([value isKindOfClass:[NSSet class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSOrderedSet class]]) {
		return [(NSOrderedSet *)value set];
	}
	return [NSSet setWithObject:value];
}

/* What the keys reach from the objects, each step every object's. */
static NSSet *
ORMWalk(NSSet *from, NSArray<NSString *> *keys)
{
	NSSet *at = from;
	for (NSString *key in keys) {
		NSMutableSet *next = [NSMutableSet set];
		for (id object in at) {
			[next unionSet:ORMRelated(object, key)];
		}
		at = next;
	}
	return at;
}

/* The value a derivation's rows give the object: its second column's, for
 * the rows of the object in the first; the set of them for "objects", else
 * the one, nil where there are none or several. */
static id
ORMDerivedValue(NSArray<NSArray *> *rows, NSString *kind)
{
	NSMutableSet *values = [NSMutableSet set];
	for (NSArray *row in rows) {
		id value = [row lastObject];
		if (value != [NSNull null]) {
			[values addObject:value];
		}
	}
	if ([kind isEqualToString:@"objects"]) {
		return values;
	}
	return [values count] == 1 ? [values anyObject] : nil;
}

/* The object's property set to the value, where it differs. YES when it
 * was set. */
static BOOL
ORMSetDerived(NSManagedObject *object, NSString *key, id value, NSString *kind)
{
	if ([kind isEqualToString:@"objects"]) {
		if ([ORMRelated(object, key) isEqualToSet:value]) {
			return NO;
		}
		NSRelationshipDescription *relationship = [[[object entity] relationshipsByName] objectForKey:key];
		[object setValue:relationship.isOrdered ? [NSOrderedSet orderedSetWithSet:value] : value forKey:key];
		return YES;
	}
	id now = [object valueForKey:key];
	if (now == value || [now isEqual:value]) {
		return NO;
	}
	[object setValue:value forKey:key];
	return YES;
}

@implementation ORMSaveHook
{
	NSMutableDictionary<NSValue *, ORMQueryInterpreter *> *_interpreters;
}

- (instancetype)initWithTables:(ORMTables *)tables
{
	if ((self = [super init])) {
		_tables = tables;
		_interpreters = [NSMutableDictionary dictionary];
	}
	return self;
}

+ (NSSet *)rootsOf:(NSString *)entityName
             backs:(NSArray<NSArray *> *)backs
           changed:(NSSet *)changed
         inContext:(NSManagedObjectContext *)context
{
	NSEntityDescription *root = [NSEntityDescription entityForName:entityName inManagedObjectContext:context];
	NSMutableSet *roots = [NSMutableSet set];
	for (NSManagedObject *object in changed) {
		if ([[object entity] isKindOfEntity:root]) {
			[roots addObject:object];
		}
		for (NSArray *back in backs) {
			NSEntityDescription *from = [NSEntityDescription entityForName:[back firstObject] inManagedObjectContext:context];
			if (from != nil && [[object entity] isKindOfEntity:from]) {
				[roots unionSet:ORMWalk([NSSet setWithObject:object], [back lastObject])];
			}
		}
	}
	return roots;
}

/* The interpreter of the context's model, made once. */
- (ORMQueryInterpreter *)interpreterFor:(NSManagedObjectContext *)context
{
	NSManagedObjectModel *model = context.persistentStoreCoordinator.managedObjectModel;
	NSValue *key = [NSValue valueWithNonretainedObject:model];
	ORMQueryInterpreter *interpreter = [_interpreters objectForKey:key];
	if (interpreter == nil) {
		interpreter = [[ORMQueryInterpreter alloc] initWithModel:model];
		[_interpreters setObject:interpreter forKey:key];
	}
	return interpreter;
}

- (BOOL)deriveInContext:(NSManagedObjectContext *)context changed:(NSMutableSet *)changed error:(NSError **)error
{
	ORMQueryInterpreter *interpreter = [self interpreterFor:context];
	for (ORMStoredDerivation *derivation in self.tables.derivations) {
		NSMutableArray *roots = [NSMutableArray array];
		for (NSManagedObject *root in [ORMSaveHook rootsOf:derivation.root backs:derivation.backs changed:changed
		                                         inContext:context]) {
			if (![root isDeleted]) {
				[roots addObject:root];
			}
		}
		if ([roots count] == 0) {
			continue;
		}
		ORMQueryResult *result = [interpreter executePlan:derivation.plan ofObjects:roots inContext:context error:error];
		if (result == nil) {
			return NO;
		}
		/* Each root's rows: those whose first column is it. */
		NSMapTable *rowsOf = [NSMapTable strongToStrongObjectsMapTable];
		for (NSArray *row in result.rows) {
			NSMutableArray *rows = [rowsOf objectForKey:[row firstObject]];
			if (rows == nil) {
				rows = [NSMutableArray array];
				[rowsOf setObject:rows forKey:[row firstObject]];
			}
			[rows addObject:row];
		}
		for (NSManagedObject *root in roots) {
			id value = ORMDerivedValue([rowsOf objectForKey:root] ?: @[], derivation.kind);
			if (ORMSetDerived(root, derivation.target, value, derivation.kind)) {
				[changed addObject:root];
			}
		}
	}
	return YES;
}

- (void)checkInContext:(NSManagedObjectContext *)context
               changed:(NSSet *)changed
            violations:(NSMutableArray<NSError *> *)violations
{
	ORMValidator *validator = [[ORMValidator alloc] initWithTables:self.tables];
	for (NSString *entity in [[self.tables.ruleBacks allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		for (NSManagedObject *root in [ORMSaveHook rootsOf:entity backs:[self.tables.ruleBacks objectForKey:entity]
		                                           changed:changed
		                                         inContext:context]) {
			if (![root isDeleted]) {
				[violations addObjectsFromArray:[validator violationsOf:root deontic:NO]];
			}
		}
	}
}

@end
