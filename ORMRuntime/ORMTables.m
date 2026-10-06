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

#pragma mark Rules

static NSArray<NSString *> *
ORMRingProperties(void)
{
	return @[ @"irreflexive", @"reflexive", @"purelyReflexive", @"symmetric", @"asymmetric", @"antisymmetric",
		      @"transitive", @"intransitive", @"stronglyIntransitive", @"acyclic" ];
}

static BOOL
ORMAreTexts(id list, NSUInteger count)
{
	if (![list isKindOfClass:[NSArray class]] || (count > 0 && [list count] != count)) {
		return NO;
	}
	for (id each in list) {
		if (!ORMIsText(each)) {
			return NO;
		}
	}
	return YES;
}

@interface ORMRuleCheck ()
@property (nonatomic, readwrite, copy) NSString *kind;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *keys;
@property (nonatomic, readwrite, copy) NSArray<ORMRuleCheck *> *operands;
@property (nonatomic, readwrite) NSUInteger number;
@property (nonatomic, readwrite) BOOL exactly;
@property (nonatomic, readwrite, copy) NSString *relation;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *properties;
@property (nonatomic, readwrite, copy) NSString *comparison;
@property (nonatomic, readwrite, copy) NSArray<NSDictionary *> *ranges;
@property (nonatomic, readwrite, strong) ORMQueryPlan *plan;
/* As it was read, or made. */
@property (nonatomic, copy) NSDictionary *list;
@end

@implementation ORMRuleCheck

/* The operands of all, any, count, not: checks. */
+ (NSArray *)operandsOf:(id)list error:(NSError **)error
{
	NSArray *items = [list isKindOfClass:[NSArray class]] ? list : list != nil ? @[ list ] : nil;
	if (items == nil) {
		*error = ORMTablesError(@"all, any, count and not are of checks.");
		return nil;
	}
	NSMutableArray *operands = [NSMutableArray array];
	for (id item in items) {
		ORMRuleCheck *operand = [self checkWithPropertyList:item error:error];
		if (operand == nil) {
			return nil;
		}
		[operands addObject:operand];
	}
	return operands;
}

+ (instancetype)checkWithPropertyList:(id)list error:(NSError **)error
{
	NSError * __autoreleasing ignored = nil;
	if (error == NULL) {
		error = &ignored;
	}
	if (![list isKindOfClass:[NSDictionary class]]) {
		*error = ORMTablesError(@"a check is a dictionary.");
		return nil;
	}
	ORMRuleCheck *check = [[self alloc] init];
	check.list = list;
	for (NSString *kind in @[ @"present", @"true" ]) {
		if ([list objectForKey:kind] != nil) {
			if (!ORMIsText([list objectForKey:kind])) {
				*error = ORMTablesError([NSString stringWithFormat:@"%@ is of a key.", kind]);
				return nil;
			}
			check.kind = kind;
			check.keys = @[ [list objectForKey:kind] ];
			return check;
		}
	}
	for (NSString *kind in @[ @"all", @"any", @"not", @"count" ]) {
		if ([list objectForKey:kind] != nil) {
			check.kind = kind;
			check.operands = [self operandsOf:[list objectForKey:kind] error:error];
			if (check.operands == nil) {
				return nil;
			}
			if ([kind isEqualToString:@"not"] && [check.operands count] != 1) {
				*error = ORMTablesError(@"not is of one check.");
				return nil;
			}
			if ([kind isEqualToString:@"count"]) {
				id bound = [list objectForKey:@"atMost"] ?: [list objectForKey:@"exactly"];
				if (![bound isKindOfClass:[NSNumber class]]) {
					*error = ORMTablesError(@"a count is at most, or exactly, a number.");
					return nil;
				}
				check.number = [bound unsignedIntegerValue];
				check.exactly = [list objectForKey:@"exactly"] != nil;
			}
			return check;
		}
	}
	if ([list objectForKey:@"sets"] != nil) {
		check.kind = @"sets";
		check.keys = [list objectForKey:@"sets"];
		check.relation = [list objectForKey:@"relation"];
		if (!ORMAreTexts(check.keys, 2) || ![@[ @"disjoint", @"subset", @"equal" ] containsObject:check.relation]) {
			*error = ORMTablesError(@"sets are two keys, disjoint, a subset or equal.");
			return nil;
		}
		return check;
	}
	if ([list objectForKey:@"ring"] != nil) {
		check.kind = @"ring";
		check.properties = [list objectForKey:@"ring"];
		check.keys = ORMIsText([list objectForKey:@"key"]) ? @[ [list objectForKey:@"key"] ] : nil;
		BOOL known = ORMAreTexts(check.properties, 0) && [check.properties count] > 0 && check.keys != nil;
		for (NSString *property in known ? check.properties : @[]) {
			known = known && [ORMRingProperties() containsObject:property];
		}
		if (!known) {
			*error = ORMTablesError(@"a ring check is of ring properties, over a key.");
			return nil;
		}
		return check;
	}
	if ([list objectForKey:@"compare"] != nil) {
		check.kind = @"compare";
		check.keys = [list objectForKey:@"compare"];
		check.comparison = [list objectForKey:@"comparison"];
		if (!ORMAreTexts(check.keys, 2) || ![@[ @"<", @"<=", @">", @">=", @"==", @"!=" ] containsObject:check.comparison]) {
			*error = ORMTablesError(@"a comparison is of two keys, by <, <=, >, >=, == or !=.");
			return nil;
		}
		return check;
	}
	if ([list objectForKey:@"within"] != nil) {
		check.kind = @"within";
		check.keys = ORMIsText([list objectForKey:@"within"]) ? @[ [list objectForKey:@"within"] ] : nil;
		check.ranges = [list objectForKey:@"ranges"];
		BOOL ranges = check.keys != nil && [check.ranges isKindOfClass:[NSArray class]];
		for (id range in ranges ? check.ranges : @[]) {
			ranges = ranges && [range isKindOfClass:[NSDictionary class]];
			for (NSString *bound in ranges ? @[ @"min", @"max", @"minOpen", @"maxOpen" ] : @[]) {
				id value = [range objectForKey:bound];
				ranges = ranges && (value == nil || [value isKindOfClass:[NSNumber class]]);
			}
		}
		if (!ranges) {
			*error = ORMTablesError(@"within is of a key, and ranges of numbers.");
			return nil;
		}
		return check;
	}
	if ([list objectForKey:@"plan"] != nil) {
		check.kind = @"plan";
		check.plan = [ORMQueryPlan planWithPropertyList:[list objectForKey:@"plan"] error:error];
		return check.plan != nil ? check : nil;
	}
	*error = ORMTablesError([NSString stringWithFormat:@"%@ is no check.", [[list allKeys] firstObject] ?: @"{}"]);
	return nil;
}

- (id)propertyList
{
	return self.list;
}

@end

@interface ORMRule ()
@property (nonatomic, readwrite, copy) NSString *constraint;
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *keys;
@property (nonatomic, readwrite) BOOL deontic;
@property (nonatomic, readwrite, strong) ORMRuleCheck *check;
@end

@implementation ORMRule

+ (instancetype)ruleNamed:(NSString *)constraint
                     text:(NSString *)text
                     keys:(NSArray<NSString *> *)keys
                  deontic:(BOOL)deontic
                    check:(ORMRuleCheck *)check
{
	ORMRule *rule = [[self alloc] init];
	rule.constraint = constraint;
	rule.text = text;
	rule.keys = keys ?: @[];
	rule.deontic = deontic;
	rule.check = check;
	return rule;
}

- (id)propertyList
{
	NSMutableDictionary *list = [NSMutableDictionary dictionaryWithDictionary:@{
		@"constraint": self.constraint ?: @"", @"text": self.text ?: @"", @"keys": self.keys,
		@"deontic": @(self.deontic), @"check": [self.check propertyList] }];
	if (self.remark != nil) {
		[list setObject:self.remark forKey:@"remark"];
	}
	return list;
}

+ (instancetype)ruleWithPropertyList:(id)list error:(NSError **)error
{
	if (![list isKindOfClass:[NSDictionary class]] || !ORMAreTexts([list objectForKey:@"keys"] ?: @[], 0)) {
		*error = ORMTablesError(@"a rule is a dictionary, its keys names.");
		return nil;
	}
	ORMRuleCheck *check = [ORMRuleCheck checkWithPropertyList:[list objectForKey:@"check"] error:error];
	if (check == nil) {
		return nil;
	}
	ORMRule *rule = [self ruleNamed:[list objectForKey:@"constraint"] text:[list objectForKey:@"text"]
	                           keys:[list objectForKey:@"keys"]
	                        deontic:[[list objectForKey:@"deontic"] boolValue]
	                          check:check];
	rule.remark = [list objectForKey:@"remark"];
	return rule;
}

@end

@interface ORMTables ()
@property (nonatomic, readwrite, copy) NSString *model;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, ORMQueryPlan *> *queries;
@property (nonatomic, readwrite, copy) NSArray<ORMStoredDerivation *> *derivations;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSArray<ORMRule *> *> *rules;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSArray<NSArray *> *> *ruleBacks;
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
	tables.rules = @{};
	tables.ruleBacks = @{};
	tables.others = @{};
	return tables;
}

+ (instancetype)tablesOfModel:(NSString *)model
                      queries:(NSDictionary<NSString *, ORMQueryPlan *> *)queries
                  derivations:(NSArray<ORMStoredDerivation *> *)derivations
                        rules:(NSDictionary<NSString *, NSArray<ORMRule *> *> *)rules
                    ruleBacks:(NSDictionary<NSString *, NSArray<NSArray *> *> *)ruleBacks
{
	ORMTables *tables = [self tablesOfModel:model queries:queries derivations:derivations];
	tables.rules = rules ?: @{};
	tables.ruleBacks = ruleBacks ?: @{};
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
	NSMutableDictionary *rules = [NSMutableDictionary dictionary];
	for (NSString *entity in self.rules) {
		NSMutableArray *items = [NSMutableArray array];
		for (ORMRule *rule in [self.rules objectForKey:entity]) {
			[items addObject:[rule propertyList]];
		}
		[rules setObject:items forKey:entity];
	}
	[list setObject:rules forKey:@"rules"];
	[list setObject:self.ruleBacks forKey:@"ruleBacks"];
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
	id ruleLists = [list objectForKey:@"rules"] ?: @{};
	id backLists = [list objectForKey:@"ruleBacks"] ?: @{};
	if (![ruleLists isKindOfClass:[NSDictionary class]] || ![backLists isKindOfClass:[NSDictionary class]]) {
		*error = ORMTablesError(@"rules and their ways back are by entity.");
		return nil;
	}
	NSMutableDictionary *rules = [NSMutableDictionary dictionary];
	for (NSString *entity in ruleLists) {
		NSMutableArray *items = [NSMutableArray array];
		id each = [ruleLists objectForKey:entity];
		for (id item in [each isKindOfClass:[NSArray class]] ? each : @[ @0 ]) {
			ORMRule *rule = [ORMRule ruleWithPropertyList:item error:error];
			if (rule == nil) {
				return nil;
			}
			[items addObject:rule];
		}
		[rules setObject:items forKey:entity];
	}
	for (NSString *entity in backLists) {
		id backs = [backLists objectForKey:entity];
		BOOL valid = [backs isKindOfClass:[NSArray class]];
		for (id back in valid ? backs : @[]) {
			valid = valid && ORMIsBack(back);
		}
		if (!valid) {
			*error = ORMTablesError(@"a rule's way back is an entity and its keys.");
			return nil;
		}
	}
	ORMTables *tables = [self tablesOfModel:[list objectForKey:@"model"] queries:queries derivations:derivations
	                                  rules:rules
	                              ruleBacks:backLists];
	NSMutableDictionary *others = [NSMutableDictionary dictionaryWithDictionary:list];
	[others removeObjectsForKeys:@[ @"format", @"model", @"queries", @"derivations", @"rules", @"ruleBacks" ]];
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
