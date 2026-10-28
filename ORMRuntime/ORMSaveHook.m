/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMSaveHook.h"
#import "ORMTuple.h"
#import "ORMQueryInterpreter.h"
#import "ORMValidator.h"
#import "ORMJoinedObject.h"
#import <CoreData/CoreData.h>

/* What the property holds, as a set: nothing, one value, or a to-many's
 * objects. Nothing for an object without it: a way back through a
 * supertype's relationship (a vehicle's records) goes on by a subtype's
 * (a trip's income), which the others have not. */
static NSSet *
ORMRelated(id object, NSString *key)
{
	if ([object isKindOfClass:[NSManagedObject class]] && [[[object entity] propertiesByName] objectForKey:key] == nil) {
		return [NSSet set];
	}
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

/* The parts a derivation's rows give the object: the columns after the
 * first, where all its rows give the same ones with none missing; nil
 * otherwise. */
static NSArray *
ORMDerivedTuple(NSArray<NSArray *> *rows)
{
	NSMutableSet *tuples = [NSMutableSet set];
	for (NSArray *row in rows) {
		NSArray *tuple = [row subarrayWithRange:NSMakeRange(1, [row count] - 1)];
		if (![tuple containsObject:[NSNull null]]) {
			[tuples addObject:[ORMTuple tupleWithValues:tuple]];
		}
	}
	return [tuples count] == 1 ? [tuples anyObject] : nil;
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
	NSMutableSet *reached = [NSMutableSet setWithSet:changed];
	for (NSManagedObject *object in changed) {
		for (NSArray *back in backs) {
			NSEntityDescription *from = [NSEntityDescription entityForName:[back firstObject] inManagedObjectContext:context];
			if (from != nil && [[object entity] isKindOfEntity:from]) {
				[reached unionSet:ORMWalk([NSSet setWithObject:object], [back lastObject])];
			}
		}
	}
	/* Of the root's entity only: a way back through a supertype's
	 * relationship (a vehicle's records) reaches its other subtypes too. */
	NSMutableSet *roots = [NSMutableSet set];
	for (NSManagedObject *object in reached) {
		if ([object isKindOfClass:[NSManagedObject class]] && [[object entity] isKindOfEntity:root]) {
			[roots addObject:object];
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

- (BOOL)prepareForSaveInContext:(NSManagedObjectContext *)context error:(NSError **)error
{
	/* As a save does first: the event's changes processed, so that a
	 * deletion's rules are applied (a deleted object out of its owners'
	 * to-manys, what cascades deleted) before anything is derived or
	 * checked. */
	[context processPendingChanges];
	NSMutableSet *changed = [NSMutableSet setWithSet:[context insertedObjects]];
	[changed unionSet:[context updatedObjects]];
	[changed unionSet:[context deletedObjects]];
	if (![self deriveInContext:context changed:changed error:error]) {
		return NO;
	}
	NSMutableArray<NSError *> *violations = [NSMutableArray array];
	[self prepareJoinedInContext:context changed:changed violations:violations];
	[self checkInContext:context changed:changed violations:violations];
	return [ORMValidator report:violations error:error];
}

- (BOOL)deriveInContext:(NSManagedObjectContext *)context changed:(NSMutableSet *)changed error:(NSError **)error
{
	ORMQueryInterpreter *interpreter = [self interpreterFor:context];
	NSError *failed = nil;
	for (ORMStoredDerivation *derivation in self.tables.derivations) {
		/* What a derivation makes on the way, gone with it. */
		@autoreleasepool {
			if (![self derive:derivation interpreter:interpreter inContext:context changed:changed error:&failed]) {
				break;
			}
		}
	}
	if (failed != nil) {
		if (error != NULL) {
			*error = failed;
		}
		return NO;
	}
	return YES;
}

/* One derivation brought up to date for the roots a change reaches. */
- (BOOL)derive:(ORMStoredDerivation *)derivation
   interpreter:(ORMQueryInterpreter *)interpreter
     inContext:(NSManagedObjectContext *)context
       changed:(NSMutableSet *)changed
         error:(NSError **)error
{
	NSMutableArray *roots = [NSMutableArray array];
	for (NSManagedObject *root in [ORMSaveHook rootsOf:derivation.root backs:derivation.backs changed:changed
	                                         inContext:context]) {
		if (![root isDeleted]) {
			[roots addObject:root];
		}
	}
	if ([roots count] == 0) {
		return YES;
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
		NSArray *rows = [rowsOf objectForKey:root] ?: @[];
		if ([derivation.kind isEqualToString:@"values"]) {
			/* Each part's property its column: one tuple, or none. */
			NSArray *tuple = ORMDerivedTuple(rows);
			if (tuple == nil && derivation.partial) {
				continue;
			}
			for (NSUInteger i = 0; i < [derivation.targets count]; i++) {
				id part = tuple != nil ? [tuple objectAtIndex:i] : nil;
				if (ORMSetDerived(root, [derivation.targets objectAtIndex:i], part == [NSNull null] ? nil : part, @"value")) {
					[changed addObject:root];
				}
			}
			continue;
		}
		/* A unary's flag: whether the rule lists the object. */
		if ([derivation.kind isEqualToString:@"flag"]) {
			if ([rows count] == 0 && derivation.partial) {
				continue;
			}
			if (ORMSetDerived(root, derivation.target, @([rows count] > 0), @"value")) {
				[changed addObject:root];
			}
			continue;
		}
		id value = ORMDerivedValue(rows, derivation.kind);
		/* Partly derived: what was asserted stays where nothing is. */
		if (derivation.partial && (value == nil || ([value isKindOfClass:[NSSet class]] && [value count] == 0))) {
			continue;
		}
		if (ORMSetDerived(root, derivation.target, value, derivation.kind)) {
			[changed addObject:root];
		}
	}
	return YES;
}

- (void)prepareJoinedInContext:(NSManagedObjectContext *)context
                       changed:(NSSet *)changed
                    violations:(NSMutableArray<NSError *> *)violations
{
	(void)context;
	for (NSString *name in [[self.tables.joined allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		[ORMJoinedObject prepareType:[self.tables.joined objectForKey:name] changed:changed violations:violations];
	}
}

- (void)checkInContext:(NSManagedObjectContext *)context
               changed:(NSSet *)changed
            violations:(NSMutableArray<NSError *> *)violations
{
	ORMValidator *validator = [[ORMValidator alloc] initWithTables:self.tables];
	/* Each object once: one of a subentity is a root of its entity's
	 * rules and of each one above's, and is asked all of them at once. */
	NSMutableOrderedSet *roots = [NSMutableOrderedSet orderedSet];
	for (NSString *entity in [[self.tables.ruleBacks allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		[roots addObjectsFromArray:[[ORMSaveHook rootsOf:entity backs:[self.tables.ruleBacks objectForKey:entity] changed:changed
		                                       inContext:context] allObjects]];
	}
	for (NSManagedObject *root in roots) {
		if (![root isDeleted]) {
			@autoreleasepool {
				[violations addObjectsFromArray:[validator violationsOf:root deontic:NO]];
			}
		}
	}
}

@end
