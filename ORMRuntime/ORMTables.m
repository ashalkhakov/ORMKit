/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMTables.h"

const NSUInteger ORMTablesFormat = 1;

static NSError *
ORMTablesError(NSString *text)
{
	return [NSError errorWithDomain:ORMQueryPlanErrorDomain code:4
	                       userInfo:@{ NSLocalizedDescriptionKey: [@"Not the model's tables: " stringByAppendingString:text] }];
}

static BOOL
ORMIsText(id value)
{
	return [value isKindOfClass:[NSString class]] && [value length] > 0;
}

/* @[ entity, @[ key, ... ] ], each a name. */
static BOOL
ORMIsBack(id back)
{
	if (![back isKindOfClass:[NSArray class]] || [back count] != 2 || !ORMIsText([back firstObject])
	    || ![[back lastObject] isKindOfClass:[NSArray class]]) {
		return NO;
	}
	for (id key in [back lastObject]) {
		if (!ORMIsText(key)) {
			return NO;
		}
	}
	return YES;
}

@interface ORMStoredDerivation ()
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite, copy) NSString *root;
@property (nonatomic, readwrite, strong) ORMQueryPlan *plan;
@property (nonatomic, readwrite, copy) NSString *target;
@property (nonatomic, readwrite, copy) NSString *kind;
@property (nonatomic, readwrite, copy) NSArray<NSArray *> *backs;
@end

@implementation ORMStoredDerivation

+ (instancetype)derivationWithText:(NSString *)text
                              root:(NSString *)root
                              plan:(ORMQueryPlan *)plan
                            target:(NSString *)target
                              kind:(NSString *)kind
                             backs:(NSArray<NSArray *> *)backs
{
	ORMStoredDerivation *derivation = [[self alloc] init];
	derivation.text = text;
	derivation.root = root;
	derivation.plan = plan;
	derivation.target = target;
	derivation.kind = kind;
	derivation.backs = backs ?: @[];
	return derivation;
}

- (id)propertyList
{
	return @{ @"text": self.text ?: @"", @"root": self.root, @"plan": [self.plan propertyList], @"target": self.target,
		      @"kind": self.kind, @"backs": self.backs };
}

+ (instancetype)derivationWithPropertyList:(id)list error:(NSError **)error
{
	if (![list isKindOfClass:[NSDictionary class]]) {
		*error = ORMTablesError(@"a derivation is a dictionary.");
		return nil;
	}
	NSString *root = [list objectForKey:@"root"];
	NSString *target = [list objectForKey:@"target"];
	NSString *kind = [list objectForKey:@"kind"];
	NSArray *backs = [list objectForKey:@"backs"];
	if (!ORMIsText(root) || !ORMIsText(target) || ![@[ @"value", @"object", @"objects" ] containsObject:kind]
	    || ![backs isKindOfClass:[NSArray class]]) {
		*error = ORMTablesError(@"a derivation has its root, target, kind (value, object or objects) and backs.");
		return nil;
	}
	for (id back in backs) {
		if (!ORMIsBack(back)) {
			*error = ORMTablesError(@"a derivation's way back is an entity and its keys.");
			return nil;
		}
	}
	ORMQueryPlan *plan = [ORMQueryPlan planWithPropertyList:[list objectForKey:@"plan"] error:error];
	if (plan == nil) {
		return nil;
	}
	if (![plan.entityName isEqualToString:root] || [plan.columns count] != 2) {
		*error = ORMTablesError(@"a derivation's plan reads its root, and lists it and what it derives.");
		return nil;
	}
	return [self derivationWithText:[list objectForKey:@"text"] root:root plan:plan target:target kind:kind backs:backs];
}

@end

@interface ORMTables ()
@property (nonatomic, readwrite, copy) NSString *model;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, ORMQueryPlan *> *queries;
@property (nonatomic, readwrite, copy) NSArray<ORMStoredDerivation *> *derivations;
/* What a later step's tables say, kept as it is. */
@property (nonatomic, copy) NSDictionary *others;
@end

@implementation ORMTables

+ (instancetype)tablesOfModel:(NSString *)model
                      queries:(NSDictionary<NSString *, ORMQueryPlan *> *)queries
                  derivations:(NSArray<ORMStoredDerivation *> *)derivations
{
	ORMTables *tables = [[self alloc] init];
	tables.model = model;
	tables.queries = queries ?: @{};
	tables.derivations = derivations ?: @[];
	tables.others = @{};
	return tables;
}

- (id)propertyList
{
	NSMutableDictionary *list = [NSMutableDictionary dictionaryWithDictionary:self.others];
	[list setObject:@(ORMTablesFormat) forKey:@"format"];
	[list setObject:self.model ?: @"" forKey:@"model"];
	NSMutableDictionary *queries = [NSMutableDictionary dictionary];
	for (NSString *name in self.queries) {
		[queries setObject:[[self.queries objectForKey:name] propertyList] forKey:name];
	}
	[list setObject:queries forKey:@"queries"];
	NSMutableArray *derivations = [NSMutableArray array];
	for (ORMStoredDerivation *derivation in self.derivations) {
		[derivations addObject:[derivation propertyList]];
	}
	[list setObject:derivations forKey:@"derivations"];
	return list;
}

+ (instancetype)tablesWithPropertyList:(id)list error:(NSError **)error
{
	NSError * __autoreleasing ignored = nil;
	if (error == NULL) {
		error = &ignored;
	}
	if (![list isKindOfClass:[NSDictionary class]]) {
		*error = ORMTablesError(@"they are a dictionary.");
		return nil;
	}
	id format = [list objectForKey:@"format"];
	if (![format isKindOfClass:[NSNumber class]] || [format unsignedIntegerValue] == 0
	    || [format unsignedIntegerValue] > ORMTablesFormat) {
		*error = ORMTablesError([NSString stringWithFormat:@"format %@ is not one this runtime reads (up to %lu).", format,
		                                                   (unsigned long)ORMTablesFormat]);
		return nil;
	}
	id queryLists = [list objectForKey:@"queries"] ?: @{};
	id derivationLists = [list objectForKey:@"derivations"] ?: @[];
	if (![queryLists isKindOfClass:[NSDictionary class]] || ![derivationLists isKindOfClass:[NSArray class]]) {
		*error = ORMTablesError(@"queries are a dictionary, derivations a list.");
		return nil;
	}
	NSMutableDictionary *queries = [NSMutableDictionary dictionary];
	for (NSString *name in queryLists) {
		ORMQueryPlan *plan = [ORMQueryPlan planWithPropertyList:[queryLists objectForKey:name] error:error];
		if (plan == nil) {
			return nil;
		}
		[queries setObject:plan forKey:name];
	}
	NSMutableArray *derivations = [NSMutableArray array];
	for (id each in derivationLists) {
		ORMStoredDerivation *derivation = [ORMStoredDerivation derivationWithPropertyList:each error:error];
		if (derivation == nil) {
			return nil;
		}
		[derivations addObject:derivation];
	}
	ORMTables *tables = [self tablesOfModel:[list objectForKey:@"model"] queries:queries derivations:derivations];
	NSMutableDictionary *others = [NSMutableDictionary dictionaryWithDictionary:list];
	[others removeObjectsForKeys:@[ @"format", @"model", @"queries", @"derivations" ]];
	tables.others = others;
	return tables;
}

#pragma mark Found by name

static NSMutableDictionary<NSString *, ORMTables *> *
ORMRegisteredTables(void)
{
	static NSMutableDictionary *registered;
	if (registered == nil) {
		registered = [NSMutableDictionary dictionary];
	}
	return registered;
}

+ (void)registerTables:(ORMTables *)tables named:(NSString *)name
{
	@synchronized(self) {
		if (tables != nil) {
			[ORMRegisteredTables() setObject:tables forKey:name];
		} else {
			[ORMRegisteredTables() removeObjectForKey:name];
		}
	}
}

/* <name>.ormplans in a bundle the process has: the main one first. */
static NSString *
ORMTablesPath(NSString *name)
{
	NSMutableArray *bundles = [NSMutableArray arrayWithObject:[NSBundle mainBundle]];
	[bundles addObjectsFromArray:[NSBundle allFrameworks]];
	[bundles addObjectsFromArray:[NSBundle allBundles]];
	for (NSBundle *bundle in bundles) {
		NSString *path = [bundle pathForResource:name ofType:@"ormplans"];
		if (path != nil) {
			return path;
		}
	}
	return nil;
}

+ (instancetype)tablesNamed:(NSString *)name error:(NSError **)error
{
	@synchronized(self) {
		ORMTables *tables = [ORMRegisteredTables() objectForKey:name];
		if (tables != nil) {
			return tables;
		}
		NSString *path = ORMTablesPath(name);
		if (path == nil) {
			if (error != NULL) {
				*error = ORMTablesError([NSString stringWithFormat:@"no bundle has %@.ormplans.", name]);
			}
			return nil;
		}
		NSData *data = [NSData dataWithContentsOfFile:path];
		if (data == nil) {
			if (error != NULL) {
				*error = ORMTablesError([NSString stringWithFormat:@"%@ cannot be read.", path]);
			}
			return nil;
		}
		id list = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:error];
		tables = list != nil ? [self tablesWithPropertyList:list error:error] : nil;
		if (tables != nil) {
			[ORMRegisteredTables() setObject:tables forKey:name];
		}
		return tables;
	}
}

@end
