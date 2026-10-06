/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMJoinedObject.h"
#import <CoreData/CoreData.h>
#import <objc/runtime.h>

/* Whether the property holds anything: a to-many not empty, anything
 * else set. */
static BOOL
ORMHolds(id object, NSString *key)
{
	id value = [object valueForKey:key];
	if ([value respondsToSelector:@selector(count)]) {
		return [value count] > 0;
	}
	return value != nil;
}

/* The hub's value: as given (the values before a change), or as it is. */
static id
ORMHubValue(NSManagedObject *hub, NSDictionary *values, NSString *key)
{
	id value = values != nil ? [values objectForKey:key] : [hub valueForKey:key];
	return value == [NSNull null] ? nil : value;
}

/* The hub's row in the entity, found by what joins it; made, with those
 * values, where there is none and create says so. nil where there is none,
 * or no value to join it by. */
static NSManagedObject *
ORMMemberRow(NSManagedObject *hub, ORMJoinedType *type, NSString *entity, BOOL create, NSDictionary *values)
{
	if ([[[hub entity] name] isEqualToString:entity]) {
		return hub;
	}
	NSDictionary *member = [type member:entity];
	NSManagedObject *via = member != nil ? ORMMemberRow(hub, type, [member objectForKey:@"via"], create, values) : nil;
	if (via == nil) {
		return nil;
	}
	NSMutableArray *parts = [NSMutableArray array];
	NSMutableArray *joining = [NSMutableArray array];
	for (NSArray *pair in [member objectForKey:@"on"]) {
		id value = via == hub ? ORMHubValue(hub, values, [pair firstObject]) : [via valueForKey:[pair firstObject]];
		if (value == nil) {
			return nil;
		}
		[joining addObject:value];
		[parts addObject:[NSPredicate predicateWithFormat:@"%K == %@", [pair lastObject], value]];
	}
	NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:entity];
	fetch.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:parts];
	NSManagedObject *row = [[[hub managedObjectContext] executeFetchRequest:fetch error:NULL] firstObject];
	if (row == nil && create) {
		row = [NSEntityDescription insertNewObjectForEntityForName:entity inManagedObjectContext:[hub managedObjectContext]];
		NSArray *on = [member objectForKey:@"on"];
		for (NSUInteger i = 0; i < [on count]; i++) {
			[row setValue:[joining objectAtIndex:i] forKey:[[on objectAtIndex:i] lastObject]];
		}
	}
	return row;
}

/* The hub's rows in its members, by entity. */
static NSDictionary *
ORMMemberRows(NSManagedObject *hub, ORMJoinedType *type, NSDictionary *values)
{
	NSMutableDictionary *rows = [NSMutableDictionary dictionary];
	for (NSDictionary *member in type.members) {
		NSManagedObject *row = ORMMemberRow(hub, type, [member objectForKey:@"entity"], NO, values);
		if (row != nil) {
			[rows setObject:row forKey:[member objectForKey:@"entity"]];
		}
	}
	return rows;
}

/* Each row joined again by the values of the one it joins to, as they are
 * now; deleted where one of those is now nil, or the row it joins to was:
 * it is no longer the instance's. */
static void
ORMRejoin(NSManagedObject *hub, ORMJoinedType *type, NSDictionary *rows)
{
	NSMutableSet *gone = [NSMutableSet set];
	for (NSDictionary *member in type.members) {
		NSManagedObject *row = [rows objectForKey:[member objectForKey:@"entity"]];
		NSString *viaName = [member objectForKey:@"via"];
		NSManagedObject *via = [[[hub entity] name] isEqualToString:viaName] ? hub : [rows objectForKey:viaName];
		if (row == nil || via == nil) {
			continue;
		}
		BOOL released = [gone containsObject:viaName];
		for (NSArray *pair in [member objectForKey:@"on"]) {
			released = released || [via valueForKey:[pair firstObject]] == nil;
		}
		if (released) {
			[[row managedObjectContext] deleteObject:row];
			[gone addObject:[member objectForKey:@"entity"]];
			continue;
		}
		for (NSArray *pair in [member objectForKey:@"on"]) {
			id value = [via valueForKey:[pair firstObject]];
			id now = [row valueForKey:[pair lastObject]];
			if (value != now && ![value isEqual:now]) {
				[row setValue:value forKey:[pair lastObject]];
			}
		}
	}
}

/* An outer member's row let go of where it keeps nothing, and nothing
 * joins to it; then the one it joins to, the same way. */
static void
ORMReleaseRow(NSManagedObject *hub, ORMJoinedType *type, NSString *entity)
{
	NSDictionary *member = [type member:entity];
	if (member == nil || ![[member objectForKey:@"outer"] boolValue]) {
		return;
	}
	NSManagedObject *row = ORMMemberRow(hub, type, entity, NO, nil);
	if (row == nil) {
		return;
	}
	for (NSString *key in [member objectForKey:@"holds"]) {
		if (ORMHolds(row, key)) {
			return;
		}
	}
	for (NSDictionary *other in type.members) {
		if ([[other objectForKey:@"via"] isEqualToString:entity]
		    && ORMMemberRow(hub, type, [other objectForKey:@"entity"], NO, nil) != nil) {
			return;
		}
	}
	[[row managedObjectContext] deleteObject:row];
	ORMReleaseRow(hub, type, [member objectForKey:@"via"]);
}

static NSError *
ORMJoinViolation(NSManagedObject *hub, NSString *text)
{
	return [NSError errorWithDomain:NSCocoaErrorDomain
	                           code:NSManagedObjectValidationError
	                       userInfo:@{ NSLocalizedDescriptionKey: text, NSValidationObjectErrorKey: hub,
		                               @"ORMConstraint": @"Joined", @"ORMKeys": @[] }];
}

#pragma mark Properties, resolved from the table

/* The getter's and setter's property: "balance", or "setBalance:"'s. */
static NSString *
ORMPropertyOf(SEL selector)
{
	NSString *name = NSStringFromSelector(selector);
	if ([name hasPrefix:@"set"] && [name hasSuffix:@":"] && [name length] > 4) {
		NSString *upper = [name substringWithRange:NSMakeRange(3, [name length] - 4)];
		return [[[upper substringToIndex:1] lowercaseString] stringByAppendingString:[upper substringFromIndex:1]];
	}
	return name;
}

static id
ORMJoinedGetter(ORMJoinedObject *self, SEL _cmd)
{
	NSArray *place = [[[[self class] joinedType] properties] objectForKey:ORMPropertyOf(_cmd)];
	return [self valueForKey:[place firstObject] in:[place lastObject]];
}

static void
ORMJoinedSetter(ORMJoinedObject *self, SEL _cmd, id value)
{
	NSArray *place = [[[[self class] joinedType] properties] objectForKey:ORMPropertyOf(_cmd)];
	[self setValue:value forKey:[place firstObject] in:[place lastObject]];
}

@implementation ORMJoinedObject

+ (NSString *)tablesName
{
	return nil;
}

+ (ORMJoinedType *)joinedType
{
	NSError *error = nil;
	ORMTables *tables = [self tablesName] != nil ? [ORMTables tablesNamed:[self tablesName] error:&error] : nil;
	ORMJoinedType *type = [tables.joined objectForKey:NSStringFromClass(self)];
	if (type == nil) {
		[NSException raise:NSInternalInconsistencyException format:@"%@ is no joined type of the tables %@: %@",
		                                                           NSStringFromClass(self), [self tablesName],
		                                                           [error localizedDescription] ?: @"none has it"];
	}
	return type;
}

+ (BOOL)resolveInstanceMethod:(SEL)selector
{
	NSString *name = NSStringFromSelector(selector);
	BOOL setter = [name hasPrefix:@"set"] && [name hasSuffix:@":"];
	if (self != [ORMJoinedObject class] && [self tablesName] != nil
	    && [[[self joinedType] properties] objectForKey:ORMPropertyOf(selector)] != nil) {
		return setter ? class_addMethod(self, selector, (IMP)ORMJoinedSetter, "v@:@")
		              : class_addMethod(self, selector, (IMP)ORMJoinedGetter, "@@:");
	}
	return [super resolveInstanceMethod:selector];
}

+ (NSArray *)allInContext:(NSManagedObjectContext *)context
{
	NSMutableArray *all = [NSMutableArray array];
	NSFetchRequest *fetch = [NSFetchRequest fetchRequestWithEntityName:[[self joinedType] hub]];
	for (NSManagedObject *object in [context executeFetchRequest:fetch error:NULL]) {
		[all addObject:[[self alloc] initWithObject:object]];
	}
	return all;
}

+ (instancetype)insertInContext:(NSManagedObjectContext *)context
{
	return [[self alloc] initWithObject:[NSEntityDescription insertNewObjectForEntityForName:[[self joinedType] hub]
	                                                                  inManagedObjectContext:context]];
}

- (instancetype)initWithObject:(NSManagedObject *)object
{
	if ((self = [super init])) {
		_object = object;
	}
	return self;
}

- (BOOL)isEqual:(id)other
{
	return [other isKindOfClass:[ORMJoinedObject class]] && [((ORMJoinedObject *)other).object isEqual:_object];
}

- (NSUInteger)hash
{
	return [_object hash];
}

/* Key-value coding of its properties: the table's, as their accessors
 * are, whatever a platform's coding finds of methods it resolves. */
- (id)valueForKey:(NSString *)key
{
	NSArray *place = [self class] != [ORMJoinedObject class] && [[self class] tablesName] != nil
		? [[[[self class] joinedType] properties] objectForKey:key] : nil;
	return place != nil ? [self valueForKey:[place firstObject] in:[place lastObject]] : [super valueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key
{
	NSArray *place = [self class] != [ORMJoinedObject class] && [[self class] tablesName] != nil
		? [[[[self class] joinedType] properties] objectForKey:key] : nil;
	if (place != nil) {
		[self setValue:value forKey:[place firstObject] in:[place lastObject]];
	} else {
		[super setValue:value forKey:key];
	}
}

- (NSManagedObject *)rowIn:(NSString *)entityName
{
	return ORMMemberRow(_object, [[self class] joinedType], entityName, NO, nil);
}

- (id)valueForKey:(NSString *)key in:(NSString *)entityName
{
	return [[self rowIn:entityName] valueForKey:key];
}

- (void)setValue:(id)value forKey:(NSString *)key in:(NSString *)entityName
{
	ORMJoinedType *type = [[self class] joinedType];
	BOOL some = value != nil && !([value respondsToSelector:@selector(count)] && [value count] == 0);
	NSManagedObject *row = ORMMemberRow(_object, type, entityName, some, nil);
	if (row == nil) {
		if (some) {
			[NSException raise:NSInternalInconsistencyException format:@"%@ has no value to keep its %@ row by.",
			                                                           [[_object entity] name], entityName];
		}
		return;
	}
	NSDictionary *rows = ORMMemberRows(_object, type, nil);
	[row setValue:value forKey:key];
	ORMRejoin(_object, type, rows);
	if (!some && row != _object) {
		ORMReleaseRow(_object, type, entityName);
	}
}

- (void)delete
{
	for (NSManagedObject *row in [ORMMemberRows(_object, [[self class] joinedType], nil) allValues]) {
		[[row managedObjectContext] deleteObject:row];
	}
	[[_object managedObjectContext] deleteObject:_object];
}

+ (void)prepareType:(ORMJoinedType *)type
            changed:(NSSet *)changed
         violations:(NSMutableArray<NSError *> *)violations
{
	for (NSManagedObject *hub in [changed allObjects]) {
		if (![[[hub entity] name] isEqualToString:type.hub]) {
			continue;
		}
		if ([hub isDeleted]) {
			/* Its rows by its values before the change, and by those it had
			 * when deleted: re-keyed through the class, its rows followed it. */
			NSMutableSet *rows = [NSMutableSet set];
			[rows addObjectsFromArray:[ORMMemberRows(hub, type, [hub committedValuesForKeys:nil]) allValues]];
			[rows addObjectsFromArray:[ORMMemberRows(hub, type, nil) allValues]];
			for (NSManagedObject *row in rows) {
				[[hub managedObjectContext] deleteObject:row];
			}
			continue;
		}
		if (![hub isInserted]) {
			ORMRejoin(hub, type, ORMMemberRows(hub, type, [hub committedValuesForKeys:nil]));
			continue;
		}
		for (NSDictionary *member in type.members) {
			if ([[member objectForKey:@"outer"] boolValue]
			    || ORMMemberRow(hub, type, [member objectForKey:@"entity"], YES, nil) != nil) {
				continue;
			}
			[violations addObject:ORMJoinViolation(hub, [NSString stringWithFormat:@"%@ has no value to keep its %@ row by.",
			                                                                       type.hub, [member objectForKey:@"entity"]])];
		}
	}
}

@end
