/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMPath.h"
#import "ORMPopulationEditor.h"
#import "ORMDeriver.h"
#import "ORMQuery.h"

/* What a sample population adds: the order it was made in, each a kind and
 * what it names. */
typedef NS_ENUM(NSInteger, ORMSampleKind) {
	ORMSampleValue,
	ORMSampleEntity,
	ORMSampleSubtype,
	ORMSampleObjectifying,
	ORMSampleFact,
};

@interface ORMSampleItem : NSObject
@property (nonatomic) ORMSampleKind kind;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *typeId;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *byRole;
@end

@implementation ORMSampleItem
@end

@implementation ORMSamplePopulation
{
	NSMutableArray<ORMSampleItem *> *_items;
	/* "type value" and "type role=instance ..." to the instance's id. */
	NSMutableDictionary<NSString *, NSString *> *_made;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_items = [NSMutableArray array];
		_made = [NSMutableDictionary dictionary];
	}
	return self;
}

- (NSArray<ORMSampleItem *> *)items
{
	return _items;
}

- (NSString *)add:(ORMSampleKind)kind type:(NSString *)typeId key:(NSString *)key text:(NSString *)text
           byRole:(NSDictionary *)byRole
{
	NSString *made = key != nil ? [_made objectForKey:key] : nil;
	if (made != nil) {
		return made;
	}
	ORMSampleItem *item = [[ORMSampleItem alloc] init];
	item.kind = kind;
	item.identifier = ORMNewId();
	item.typeId = typeId;
	item.text = text;
	item.byRole = byRole;
	[_items addObject:item];
	if (key != nil) {
		[_made setObject:item.identifier forKey:key];
	}
	return item.identifier;
}

/* The pairs in role order, so the same identity is the same key. */
static NSString *
ORMKeyOf(NSString *typeId, NSDictionary<NSString *, NSString *> *byRole)
{
	NSMutableString *key = [NSMutableString stringWithString:typeId];
	for (NSString *role in [[byRole allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		[key appendFormat:@" %@=%@", role, [byRole objectForKey:role]];
	}
	return key;
}

- (NSString *)value:(NSString *)text of:(NSString *)valueTypeId
{
	return [self add:ORMSampleValue type:valueTypeId key:[NSString stringWithFormat:@"%@ %@", valueTypeId, text]
	            text:text byRole:nil];
}

- (NSString *)instanceOf:(NSString *)entityTypeId identifiedBy:(NSDictionary<NSString *, NSString *> *)instancesByRole
{
	return [self add:ORMSampleEntity type:entityTypeId key:ORMKeyOf(entityTypeId, instancesByRole) text:nil
	          byRole:instancesByRole];
}

- (NSString *)instanceOf:(NSString *)subtypeId supertypeInstance:(NSString *)instanceId
{
	return [self add:ORMSampleSubtype type:subtypeId key:[NSString stringWithFormat:@"%@ ^%@", subtypeId, instanceId]
	            text:instanceId byRole:nil];
}

- (NSString *)factOf:(NSString *)factTypeId players:(NSDictionary<NSString *, NSString *> *)instancesByRole
{
	return [self add:ORMSampleFact type:factTypeId key:nil text:nil byRole:instancesByRole];
}

- (void)factOf:(NSString *)factTypeId players:(NSDictionary<NSString *, NSString *> *)instancesByRole
    identifier:(NSString *)identifier
{
	[self add:ORMSampleFact type:factTypeId key:nil text:nil byRole:instancesByRole];
	[[_items lastObject] setIdentifier:identifier];
}

- (NSString *)instanceOf:(NSString *)entityTypeId objectifying:(NSString *)factInstanceId
{
	return [self instanceOf:entityTypeId objectifying:factInstanceId identifiedBy:nil];
}

- (NSString *)instanceOf:(NSString *)entityTypeId
            objectifying:(NSString *)factInstanceId
            identifiedBy:(NSDictionary<NSString *, NSString *> *)instancesByRole
{
	return [self add:ORMSampleObjectifying type:entityTypeId
	             key:[NSString stringWithFormat:@"%@ =%@", entityTypeId, factInstanceId] text:factInstanceId
	          byRole:instancesByRole];
}

- (BOOL)isEmpty
{
	return [_items count] == 0;
}

- (BOOL)removeInstance:(NSString *)instanceId
{
	ORMSampleItem *found = nil;
	for (ORMSampleItem *item in _items) {
		if ([item.identifier isEqualToString:instanceId]) {
			found = item;
			continue;
		}
		if ([[item.byRole allValues] containsObject:instanceId]
		    || (item.kind != ORMSampleValue && [item.text isEqualToString:instanceId])) {
			return NO;
		}
	}
	if (found == nil) {
		return NO;
	}
	[_items removeObject:found];
	for (NSString *key in [_made allKeysForObject:instanceId]) {
		[_made removeObjectForKey:key];
	}
	return YES;
}

@end

@implementation ORMPopulationEditor
{
	/* Edits within an edit: the stored derived facts are brought up to date
	 * once, by the outermost. */
	NSUInteger _editing;
}

@synthesize editor = _editor;

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

/* A number or a moment: NORMA writes its culture-invariant form beside it. */
static BOOL
ORMHasInvariantForm(ORMObjectType *type)
{
	ORMDataTypeFamily family = type.dataType.family;
	return family == ORMDataTypeNumeric || family == ORMDataTypeTemporal;
}

- (BOOL)refuse:(NSString *)why reason:(NSString **)reason
{
	if (reason != NULL) {
		*reason = why;
	}
	return NO;
}

/* What each id names: the population's own instances first, by kind and
 * type, then the model's. */
/* What the model has, by what makes it the one it is: a value by its
 * type and text, an entity by the instances identifying it, a subtype's
 * by its supertype's; with facts, a fact by its players. A sample
 * population's item so keyed is that instance, not another. Facts only
 * when asked: reading every fact type's is slow, and adding needs none. */
- (NSMutableDictionary<NSString *, NSString *> *)existingInstancesWithFacts:(BOOL)facts
{
	ORMModel *model = _editor.model;
	NSMutableDictionary *existing = [NSMutableDictionary dictionary];
	for (ORMObjectType *type in model.objectTypes) {
		for (ORMInstance *instance in [type instances]) {
			if (instance.value != nil) {
				[existing setObject:instance.identifier forKey:[NSString stringWithFormat:@"%@ %@", type.identifier,
				                                                                           instance.value]];
				continue;
			}
			if ([instance supertypeInstance] != nil) {
				[existing setObject:instance.identifier
				             forKey:[NSString stringWithFormat:@"%@ ^%@", type.identifier,
				                                               [[instance supertypeInstance] identifier]]];
				continue;
			}
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			NSDictionary *identifying = [instance identifyingInstancesByRole];
			for (NSString *roleId in identifying) {
				[byRole setObject:[[identifying objectForKey:roleId] identifier] forKey:roleId];
			}
			if ([byRole count] > 0) {
				[existing setObject:instance.identifier forKey:ORMKeyOf(type.identifier, byRole)];
			}
		}
	}
	for (ORMFactType *fact in facts ? model.factTypes : @[]) {
		for (ORMFactInstance *instance in [fact instances]) {
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			for (NSString *roleId in instance.instancesByRole) {
				ORMInstance *player = [instance.instancesByRole objectForKey:roleId];
				/* A unary's truth value is not named when one is added. */
				if (!player.objectType.isImplicitBooleanValue) {
					[byRole setObject:player.identifier forKey:roleId];
				}
			}
			[existing setObject:instance.identifier forKey:ORMKeyOf(fact.identifier, byRole)];
		}
	}
	return existing;
}

/* The model's instance or fact a population's item would be, as adding it
 * would find it; nil when it would be new. */
- (NSString *)modelIdOf:(NSString *)sampleId in:(ORMSamplePopulation *)population
{
	BOOL facts = NO;
	for (ORMSampleItem *item in [population items]) {
		facts = facts || item.kind == ORMSampleFact;
	}
	NSDictionary *existing = [self existingInstancesWithFacts:facts];
	NSMutableDictionary *found = [NSMutableDictionary dictionary];
	for (ORMSampleItem *item in [population items]) {
		NSString *key = nil;
		NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
		BOOL known = YES;
		for (NSString *roleId in item.byRole) {
			NSString *player = [item.byRole objectForKey:roleId];
			NSString *had = [found objectForKey:player] ?: ([_editor.model elementWithId:player] != nil ? player : nil);
			known = known && had != nil;
			[byRole setObject:had ?: player forKey:roleId];
		}
		switch (item.kind) {
		case ORMSampleValue:
			key = [NSString stringWithFormat:@"%@ %@", item.typeId, item.text];
			break;
		case ORMSampleSubtype: {
			NSString *supertype = [found objectForKey:item.text] ?: item.text;
			key = [NSString stringWithFormat:@"%@ ^%@", item.typeId, supertype];
			break;
		}
		case ORMSampleEntity:
		case ORMSampleFact:
			key = known ? ORMKeyOf(item.typeId, byRole) : nil;
			break;
		case ORMSampleObjectifying:
			break;
		}
		NSString *had = key != nil ? [existing objectForKey:key] : nil;
		if (had != nil) {
			[found setObject:had forKey:item.identifier];
		}
	}
	return [found objectForKey:sampleId];
}

- (BOOL)check:(ORMSamplePopulation *)population types:(NSMutableDictionary *)types reason:(NSString **)reason
{
	ORMModel *model = _editor.model;
	/* The type an id's instance is of: made here, or the model's. */
	ORMObjectType *(^typeOf)(NSString *) = ^ORMObjectType *(NSString *identifier) {
		ORMObjectType *type = [types objectForKey:identifier];
		if (type == nil) {
			ORMInstance *instance = [model elementWithId:identifier];
			type = [instance isKindOfClass:[ORMInstance class]] ? instance.objectType : nil;
		}
		return type;
	};
	/* Whether an instance of the type may play the role. */
	BOOL (^plays)(ORMObjectType *, ORMRole *) = ^BOOL(ORMObjectType *type, ORMRole *role) {
		return type != nil && (type == role.player || [type isSubtypeOf:role.player]);
	};
	/* The fact type of each fact, made here or the model's. */
	NSMutableDictionary *factTypes = [NSMutableDictionary dictionary];
	for (ORMSampleItem *item in [population items]) {
		if (item.kind == ORMSampleFact) {
			[factTypes setObject:item.typeId forKey:item.identifier];
		}
	}
	for (ORMSampleItem *item in [population items]) {
		id element = [model elementWithId:item.typeId];
		switch (item.kind) {
		case ORMSampleValue:
			if (![element isKindOfClass:[ORMObjectType class]] || [(ORMObjectType *)element isEntity]) {
				return [self refuse:[NSString stringWithFormat:@"%@ is not a value type.", item.typeId] reason:reason];
			}
			[types setObject:element forKey:item.identifier];
			break;
		case ORMSampleEntity: {
			ORMObjectType *type = element;
			if (![type isKindOfClass:[ORMObjectType class]] || ![type isEntity] || type.preferredIdentifier == nil) {
				return [self refuse:[NSString stringWithFormat:@"%@ is not an entity type with a preferred identifier.",
				                                  [element name] ?: item.typeId] reason:reason];
			}
			NSArray *roles = [type.preferredIdentifier allRoles];
			if ([roles count] != [item.byRole count]) {
				return [self refuse:[NSString stringWithFormat:@"An instance of %@ is identified by %lu instances.", type.name,
				                                  (unsigned long)[roles count]] reason:reason];
			}
			for (ORMRole *role in roles) {
				if (!plays(typeOf([item.byRole objectForKey:role.identifier]), role)) {
					return [self refuse:[NSString stringWithFormat:@"An instance of %@ is identified by a %@.", type.name,
					                                  role.player.name] reason:reason];
				}
			}
			[types setObject:type forKey:item.identifier];
			break;
		}
		case ORMSampleSubtype: {
			ORMObjectType *type = element;
			ORMObjectType *supertype = typeOf(item.text);
			if (![type isKindOfClass:[ORMObjectType class]] || supertype == nil || ![type isSubtypeOf:supertype]) {
				return [self refuse:[NSString stringWithFormat:@"%@ is no subtype of %@.", [element name] ?: item.typeId,
				                                  supertype.name ?: item.text] reason:reason];
			}
			[types setObject:type forKey:item.identifier];
			break;
		}
		case ORMSampleObjectifying: {
			ORMObjectType *type = element;
			ORMFactInstance *had = [model elementWithId:item.text];
			NSString *factTypeId = [factTypes objectForKey:item.text]
				?: ([had isKindOfClass:[ORMFactInstance class]] ? had.factType.identifier : nil);
			if (![type isKindOfClass:[ORMObjectType class]] || type.nestedFactType == nil
			    || ![type.nestedFactType.identifier isEqualToString:factTypeId ?: @""]) {
				return [self refuse:[NSString stringWithFormat:@"%@ does not objectify the fact %@.",
				                                               [element name] ?: item.typeId, item.text]
				             reason:reason];
			}
			[types setObject:type forKey:item.identifier];
			break;
		}
		case ORMSampleFact: {
			ORMFactType *fact = element;
			if (![fact isKindOfClass:[ORMFactType class]] || [item.byRole count] == 0) {
				return [self refuse:[NSString stringWithFormat:@"%@ is not a fact type.", item.typeId] reason:reason];
			}
			for (NSString *roleId in item.byRole) {
				ORMRole *role = [model elementWithId:roleId];
				if (![role isKindOfClass:[ORMRole class]] || role.factType != fact) {
					return [self refuse:[NSString stringWithFormat:@"%@ is not a role of %@.", roleId, fact.name] reason:reason];
				}
				if (!plays(typeOf([item.byRole objectForKey:roleId]), role)) {
					return [self refuse:[NSString stringWithFormat:@"%@ plays no role %@ plays in %@.",
					                                  typeOf([item.byRole objectForKey:roleId]).name ?: @"Nothing",
					                                  role.player.name, fact.name] reason:reason];
				}
			}
			break;
		}
		}
	}
	return YES;
}

/* An id of the population, or what the model has instead. */
static NSString *
ORMResolved(NSDictionary<NSString *, NSString *> *renamed, NSString *identifier)
{
	return [renamed objectForKey:identifier] ?: identifier;
}

/* A role instance of the kind, on the role, for the instance, inside a
 * model change. Its id. */
- (NSString *)roleInstance:(NSString *)local on:(ORMRole *)role for:(NSString *)instanceId
{
	ORMRoleInstance *roleInstance = [[ORMRoleInstance alloc] initWithModel:_editor.model];
	roleInstance.elementName = local;
	roleInstance.role = role;
	roleInstance.instanceId = instanceId;
	[_editor.model addPopulationElement:roleInstance];
	[_editor wrote:roleInstance];
	return roleInstance.identifier;
}

/* A new instance of the type, of NORMA's kind, with the id, inside a
 * model change. */
- (ORMInstance *)newInstance:(NSString *)local of:(ORMObjectType *)type identifier:(NSString *)identifier
{
	ORMInstance *instance = [[ORMInstance alloc] initWithModel:_editor.model];
	instance.identifier = identifier ?: instance.identifier;
	instance.objectType = type;
	instance.elementName = local;
	return instance;
}

- (void)addInstance:(ORMInstance *)instance
{
	[_editor.model addPopulationElement:instance];
	[_editor wrote:instance];
}

/* The implicit boolean value type's "True", made when it has none. */
- (NSString *)truthOf:(ORMObjectType *)type existing:(NSMutableDictionary *)existing
{
	NSString *key = [NSString stringWithFormat:@"%@ True", type.identifier];
	NSString *had = [existing objectForKey:key];
	if (had != nil) {
		return had;
	}
	ORMInstance *instance = [self newInstance:@"ValueTypeInstance" of:type identifier:nil];
	instance.value = @"True";
	[self addInstance:instance];
	[existing setObject:instance.identifier forKey:key];
	return instance.identifier;
}

- (BOOL)addPopulationNow:(ORMSamplePopulation *)population reason:(NSString **)reason
{
	NSMutableDictionary *types = [NSMutableDictionary dictionary];
	if (![self check:population types:types reason:reason]) {
		return NO;
	}
	if ([population isEmpty]) {
		return YES;
	}
	ORMModel *model = _editor.model;
	NSMutableDictionary *existing = [self existingInstancesWithFacts:NO];
	[_editor modelChange:@"Add Sample Population" with:^{
		NSMutableDictionary *renamed = [NSMutableDictionary dictionary];
		for (ORMSampleItem *item in [population items]) {
			ORMObjectType *type = [model elementWithId:item.typeId];
			switch (item.kind) {
			case ORMSampleValue: {
				NSString *had = [existing objectForKey:[NSString stringWithFormat:@"%@ %@", item.typeId, item.text]];
				if (had != nil) {
					[renamed setObject:had forKey:item.identifier];
					break;
				}
				ORMInstance *instance = [self newInstance:@"ValueTypeInstance" of:type identifier:item.identifier];
				instance.value = item.text;
				if (ORMHasInvariantForm([types objectForKey:item.identifier])) {
					instance.invariantValue = item.text;
				}
				[self addInstance:instance];
				break;
			}
			case ORMSampleEntity: {
				NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
				for (NSString *roleId in item.byRole) {
					[byRole setObject:ORMResolved(renamed, [item.byRole objectForKey:roleId]) forKey:roleId];
				}
				NSString *had = [existing objectForKey:ORMKeyOf(item.typeId, byRole)];
				if (had != nil) {
					[renamed setObject:had forKey:item.identifier];
					break;
				}
				ORMInstance *instance = [self newInstance:@"EntityTypeInstance" of:type identifier:item.identifier];
				NSMutableArray *identifying = [NSMutableArray array];
				for (ORMRole *role in [type.preferredIdentifier allRoles]) {
					[identifying addObject:[self roleInstance:@"EntityTypeRoleInstance" on:role
					                                       for:[byRole objectForKey:role.identifier]]];
				}
				instance.identifyingRoleInstances = identifying;
				[self addInstance:instance];
				break;
			}
			case ORMSampleObjectifying: {
				ORMInstance *instance = [self newInstance:@"EntityTypeInstance" of:type identifier:item.identifier];
				NSMutableArray *identifying = [NSMutableArray array];
				for (ORMRole *role in [item.byRole count] > 0 ? [type.preferredIdentifier allRoles] : @[]) {
					NSString *player = [item.byRole objectForKey:role.identifier];
					if (player != nil) {
						[identifying addObject:[self roleInstance:@"EntityTypeRoleInstance" on:role
						                                       for:ORMResolved(renamed, player)]];
					}
				}
				instance.identifyingRoleInstances = identifying;
				instance.objectifiedInstanceId = ORMResolved(renamed, item.text);
				[self addInstance:instance];
				break;
			}
			case ORMSampleSubtype: {
				NSString *supertype = ORMResolved(renamed, item.text);
				NSString *had = [existing objectForKey:[NSString stringWithFormat:@"%@ ^%@", item.typeId, supertype]];
				if (had != nil) {
					[renamed setObject:had forKey:item.identifier];
					break;
				}
				ORMInstance *instance = [self newInstance:@"EntityTypeSubtypeInstance" of:type identifier:item.identifier];
				instance.supertypeInstanceId = supertype;
				[self addInstance:instance];
				break;
			}
			case ORMSampleFact: {
				ORMFactType *fact = [model elementWithId:item.typeId];
				ORMFactInstance *instance = [[ORMFactInstance alloc] initWithModel:model];
				instance.identifier = item.identifier;
				instance.factType = fact;
				NSMutableArray *roleInstances = [NSMutableArray array];
				for (ORMRole *role in fact.roles) {
					NSString *player = [item.byRole objectForKey:role.identifier];
					if (player == nil && role.player.isImplicitBooleanValue) {
						/* A unary's implicit role, played by its truth. */
						player = [self truthOf:role.player existing:existing];
					}
					if (player != nil) {
						[roleInstances addObject:[self roleInstance:@"FactTypeRoleInstance" on:role
						                                        for:ORMResolved(renamed, player)]];
					}
				}
				instance.roleInstanceIds = roleInstances;
				[model addPopulationElement:instance];
				[_editor wrote:instance];
				break;
			}
			}
		}
	}];
	return YES;
}

/* The role instances of the model that name the instance as their player,
 * of the kind. */
- (NSArray<ORMRoleInstance *> *)roleInstances:(NSString *)local of:(NSString *)instanceId
{
	NSMutableArray *found = [NSMutableArray array];
	for (ORMFactType *fact in _editor.model.factTypes) {
		for (ORMRole *role in fact.roles) {
			for (ORMRoleInstance *roleInstance in role.roleInstances) {
				if ([roleInstance.instanceId isEqualToString:instanceId] && [roleInstance.elementName isEqualToString:local]) {
					[found addObject:roleInstance];
				}
			}
		}
	}
	return found;
}

/* The instances of the model whose property names the id. */
- (NSArray<ORMInstance *> *)instancesWhose:(NSString *)key is:(NSString *)identifier
{
	NSMutableArray *found = [NSMutableArray array];
	for (ORMObjectType *type in _editor.model.objectTypes) {
		for (ORMInstance *instance in [type instances]) {
			if ([[instance valueForKey:key] isEqual:identifier]) {
				[found addObject:instance];
			}
		}
	}
	return found;
}

/* An element of the population out of the model, inside a model change. */
- (void)removeFromPopulation:(ORMElement *)element
{
	[_editor.model removePopulationElement:element];
	[_editor deleted:element];
}

#pragma mark One at a time

/* Whether what identifies the type is the fact it objectifies. */
- (BOOL)isTheFactItObjectifies:(ORMObjectType *)type
{
	ORMFactType *nested = type.nestedFactType;
	for (ORMRole *role in [type.preferredIdentifier allRoles]) {
		if (nested != nil && role.factType == nested) {
			return YES;
		}
	}
	return NO;
}

- (NSArray<ORMRole *> *)compositeRolesOf:(NSString *)objectTypeId
{
	id element = [_editor.model elementWithId:objectTypeId];
	ORMObjectType *type = [element isKindOfClass:[ORMObjectType class]] ? [(ORMObjectType *)element identifiedType] : nil;
	if (![type isKindOfClass:[ORMObjectType class]] || type.kind == ORMValueType || [self isTheFactItObjectifies:type]) {
		return @[];
	}
	NSArray *roles = [type.preferredIdentifier allRoles];
	return [roles count] > 1 ? roles : @[];
}

/* The parts of a name, split at the commas outside parentheses and quotes. */
static NSArray<NSString *> *
ORMNameParts(NSString *text)
{
	NSMutableArray *parts = [NSMutableArray array];
	NSInteger depth = 0;
	BOOL quoted = NO;
	NSUInteger start = 0;
	for (NSUInteger i = 0; i < [text length]; i++) {
		unichar c = [text characterAtIndex:i];
		if (c == '\'') {
			quoted = !quoted;
		} else if (!quoted && c == '(') {
			depth++;
		} else if (!quoted && c == ')') {
			depth--;
		} else if (!quoted && depth == 0 && c == ',') {
			[parts addObject:[text substringWithRange:NSMakeRange(start, i - start)]];
			start = i + 1;
		}
	}
	[parts addObject:[text substringFromIndex:start]];
	return parts;
}

/* A part as it is named: out of its parentheses or quotes. */
static NSString *
ORMUnwrapPart(NSString *part)
{
	NSString *text = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	NSUInteger length = [text length];
	if (length >= 2 && [text hasPrefix:@"("] && [text hasSuffix:@")"]) {
		return [text substringWithRange:NSMakeRange(1, length - 2)];
	}
	if (length >= 2 && [text hasPrefix:@"'"] && [text hasSuffix:@"'"]) {
		return [[text substringWithRange:NSMakeRange(1, length - 2)] stringByReplacingOccurrencesOfString:@"''"
		                                                                                        withString:@"'"];
	}
	return text;
}

/* A part of a name, so that it reads back as itself. */
static NSString *
ORMWrapPart(NSString *name, BOOL composite)
{
	if (composite) {
		return [NSString stringWithFormat:@"(%@)", name];
	}
	NSCharacterSet *special = [NSCharacterSet characterSetWithCharactersInString:@",()'"];
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if ([name length] == 0 || [name rangeOfCharacterFromSet:special].location != NSNotFound
	    || ![trimmed isEqualToString:name]) {
		return [NSString stringWithFormat:@"'%@'", [name stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
	}
	return name;
}

- (NSString *)nameOf:(ORMInstance *)instance
{
	if (instance == nil) {
		return @"";
	}
	if (instance.value != nil) {
		return instance.value;
	}
	if ([instance supertypeInstance] != nil) {
		return [self nameOf:[instance supertypeInstance]];
	}
	NSDictionary *identifying = [instance identifyingInstancesByRole];
	NSArray *roles = [instance.objectType.preferredIdentifier allRoles];
	if ([identifying count] == 0 || [roles count] == 0) {
		return [instance displayText] ?: @"";
	}
	if ([roles count] == 1) {
		return [self nameOf:[identifying objectForKey:[[roles firstObject] identifier]]];
	}
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMRole *role in roles) {
		ORMInstance *part = [identifying objectForKey:role.identifier];
		[parts addObject:part != nil ? ORMWrapPart([self nameOf:part], [[self compositeRolesOf:part.objectType.identifier] count] > 0)
		                             : @"?"];
	}
	return [parts componentsJoinedByString:@", "];
}

- (NSString *)instanceOf:(NSString *)objectTypeId
                   named:(NSString *)text
                    into:(ORMSamplePopulation *)population
                  reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	if (![type isKindOfClass:[ORMObjectType class]] || [text length] == 0) {
		[self refuse:[type isKindOfClass:[ORMObjectType class]] ? @"Name the instance." : @"There is no such object type."
		      reason:reason];
		return nil;
	}
	if (type.kind == ORMValueType) {
		return [population value:text of:objectTypeId];
	}
	if (type.preferredIdentifier == nil && [type.supertypes count] > 0) {
		/* Identified as its supertype is: that instance, which it is. */
		NSString *supertype = [self instanceOf:[[type identifyingSupertype] identifier] named:text into:population
		                                reason:reason];
		return supertype != nil ? [population instanceOf:objectTypeId supertypeInstance:supertype] : nil;
	}
	NSArray *identifying = [type.preferredIdentifier allRoles];
	if ([identifying count] == 0 || [self isTheFactItObjectifies:type]) {
		[self refuse:[NSString stringWithFormat:@"%@ is the fact it objectifies: add that fact.", type.name] reason:reason];
		return nil;
	}
	if ([identifying count] == 1) {
		ORMRole *role = [identifying firstObject];
		NSString *part = [self instanceOf:role.player.identifier named:text into:population reason:reason];
		return part != nil ? [population instanceOf:objectTypeId identifiedBy:@{ role.identifier: part }] : nil;
	}
	NSArray *parts = ORMNameParts(text);
	if ([parts count] != [identifying count]) {
		NSMutableArray *names = [NSMutableArray array];
		for (ORMRole *role in identifying) {
			[names addObject:role.player.name ?: @"?"];
		}
		[self refuse:[NSString stringWithFormat:@"%@ is identified by %@: name each, separated by commas.", type.name,
		                                        [names componentsJoinedByString:@", "]]
		      reason:reason];
		return nil;
	}
	NSMutableDictionary *texts = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [parts count]; i++) {
		[texts setObject:ORMUnwrapPart([parts objectAtIndex:i]) forKey:[[identifying objectAtIndex:i] identifier]];
	}
	return [self instanceOf:objectTypeId namedByRole:texts into:population reason:reason];
}

/* An entity identified by several values, each named by its role. */
- (NSString *)instanceOf:(NSString *)objectTypeId
             namedByRole:(NSDictionary<NSString *, NSString *> *)textsByRole
                    into:(ORMSamplePopulation *)population
                  reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	ORMObjectType *identified = [type identifiedType];
	NSArray *roles = [self compositeRolesOf:objectTypeId];
	if ([roles count] == 0) {
		[self refuse:@"It is not identified by several values." reason:reason];
		return nil;
	}
	NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
	for (ORMRole *role in roles) {
		/* As named: a quoted part keeps its spaces. */
		NSString *text = [textsByRole objectForKey:role.identifier];
		if ([[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
			[self refuse:[NSString stringWithFormat:@"Name the %@ too.", role.player.name] reason:reason];
			return nil;
		}
		NSString *part = [self instanceOf:role.player.identifier named:text into:population reason:reason];
		if (part == nil) {
			return nil;
		}
		[byRole setObject:part forKey:role.identifier];
	}
	NSString *instance = [population instanceOf:identified.identifier identifiedBy:byRole];
	/* A subtype identified as its supertype: down to it, each in turn. */
	NSMutableArray *chain = [NSMutableArray array];
	for (ORMObjectType *each = type; each != identified; each = [each identifyingSupertype]) {
		[chain insertObject:each atIndex:0];
	}
	for (ORMObjectType *each in chain) {
		instance = [population instanceOf:each.identifier supertypeInstance:instance];
	}
	return instance;
}

/* The fact, into the population, the role's player named, the others'
 * as they are; nil, and why, where it cannot be, or the model has it. */
- (NSString *)fact:(ORMFactType *)fact
           players:(NSDictionary<NSString *, NSString *> *)instancesByRole
             named:(NSDictionary<NSString *, NSString *> *)textsByRole
              into:(ORMSamplePopulation *)population
            reason:(NSString **)reason
{
	if (![fact isKindOfClass:[ORMFactType class]]) {
		[self refuse:@"There is no such fact type." reason:reason];
		return nil;
	}
	NSMutableDictionary *players = [NSMutableDictionary dictionaryWithDictionary:instancesByRole ?: @{}];
	for (ORMRole *role in [fact visibleRoles]) {
		NSString *text = [textsByRole objectForKey:role.identifier];
		if (text == nil) {
			continue;
		}
		NSString *instance = [self instanceOf:role.player.identifier named:text into:population reason:reason];
		if (instance == nil) {
			return nil;
		}
		[players setObject:instance forKey:role.identifier];
	}
	for (ORMRole *role in [fact visibleRoles]) {
		if ([players objectForKey:role.identifier] == nil) {
			[self refuse:[NSString stringWithFormat:@"Name the %@ too.", role.player.name] reason:reason];
			return nil;
		}
	}
	NSString *created = [population factOf:fact.identifier players:players];
	if ([self modelIdOf:created in:population] != nil) {
		[self refuse:@"That fact is there already." reason:reason];
		return nil;
	}
	return created;
}

/* The fact's population: the role's player named, the others' as they are. */
- (NSString *)addFactOf:(NSString *)factTypeId
                players:(NSDictionary<NSString *, NSString *> *)instancesByRole
                  named:(NSDictionary<NSString *, NSString *> *)textsByRole
                 reason:(NSString **)reason
{
	ORMFactType *fact = [_editor.model elementWithId:factTypeId];
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	NSString *created = [self fact:fact players:instancesByRole named:textsByRole into:population reason:reason];
	if (created == nil) {
		return nil;
	}
	/* Objectified, and identified by the fact: its instance is the fact,
	 * made with it. One identified otherwise is made with its own values
	 * named: -addInstanceOf:named:objectifying:reason:. */
	ORMObjectType *objectifying = fact.objectifyingType;
	if (objectifying != nil && [self isTheFactItObjectifies:objectifying]) {
		[population instanceOf:objectifying.identifier objectifying:created];
	} else if (objectifying != nil) {
		[self refuse:[NSString stringWithFormat:@"Each such fact is objectified by %@, identified by its own %@: add the "
		                                        @"%@ with its fact.",
		                                        objectifying.name, [self identifierNameOf:objectifying],
		                                        objectifying.name]
		      reason:reason];
		return nil;
	}
	return [self addPopulationNow:population reason:reason] ? created : nil;
}

- (NSString *)addFactNowOf:(NSString *)factTypeId named:(NSDictionary<NSString *, NSString *> *)textsByRole
                 reason:(NSString **)reason
{
	return [self addFactOf:factTypeId players:nil named:textsByRole reason:reason];
}

- (BOOL)removeFactNow:(NSString *)factInstanceId reason:(NSString **)reason
{
	ORMFactInstance *fact = [_editor.model elementWithId:factInstanceId];
	if (![fact isKindOfClass:[ORMFactInstance class]] || fact.isKeptOnPlayer) {
		return [self refuse:@"There is no such fact." reason:reason];
	}
	BOOL blocked = NO;
	ORMInstance *objectifying = [self objectifyingInstanceOf:factInstanceId blocked:&blocked];
	if (blocked) {
		return [self refuse:@"An instance of the type that objectifies it is this fact, and plays a role or identifies "
		                    @"another: remove that first."
		             reason:reason];
	}
	[_editor modelChange:@"Remove Fact" with:^{
		/* Its role instances, on the roles. */
		for (NSString *roleInstanceId in fact.roleInstanceIds) {
			ORMRoleInstance *roleInstance = [_editor.model elementWithId:roleInstanceId];
			if ([roleInstance isKindOfClass:[ORMRoleInstance class]]) {
				[self removeFromPopulation:roleInstance];
			}
		}
		[self removeFromPopulation:fact];
		if (objectifying != nil) {
			[self removeFromPopulation:objectifying];
		}
	}];
	return YES;
}

/* The instance of the objectifying type that is the fact; with blocked,
 * when it cannot go with the fact: it plays a role, identifies another or
 * is a subtype's, or is identified by more than the fact. */
- (ORMInstance *)objectifyingInstanceOf:(NSString *)factInstanceId blocked:(BOOL *)blocked
{
	*blocked = NO;
	ORMInstance *instance = [[self instancesWhose:@"objectifiedInstanceId" is:factInstanceId] firstObject];
	if (instance == nil) {
		return nil;
	}
	*blocked = [[self roleInstances:@"FactTypeRoleInstance" of:instance.identifier] count] > 0
		|| [[self roleInstances:@"EntityTypeRoleInstance" of:instance.identifier] count] > 0
		|| [[self instancesWhose:@"supertypeInstanceId" is:instance.identifier] count] > 0
		|| [instance.identifyingRoleInstances count] > 0;
	return instance;
}

- (NSString *)setPlayerNow:(NSString *)text ofRole:(NSString *)roleId inFact:(NSString *)factInstanceId
                 reason:(NSString **)reason
{
	ORMFactInstance *fact = [_editor.model elementWithId:factInstanceId];
	if (![fact isKindOfClass:[ORMFactInstance class]] || [fact.factType.roles indexOfObjectPassingTest:^BOOL(ORMRole *role,
	                                                                                                       NSUInteger i, BOOL *stop) {
		    (void)i;
		    (void)stop;
		    return [role.identifier isEqualToString:roleId];
	    }] == NSNotFound) {
		[self refuse:@"There is no such fact, or role of it." reason:reason];
		return nil;
	}
	NSMutableDictionary *kept = [NSMutableDictionary dictionary];
	for (NSString *role in fact.instancesByRole) {
		if (![role isEqualToString:roleId] && ![[_editor.model elementWithId:role] player].isImplicitBooleanValue) {
			[kept setObject:[[fact.instancesByRole objectForKey:role] identifier] forKey:role];
		}
	}
	NSString *factTypeId = fact.factType.identifier;
	/* What would refuse it, asked before anything changes. */
	ORMRole *role = [_editor.model elementWithId:roleId];
	ORMSamplePopulation *trial = [[ORMSamplePopulation alloc] init];
	NSString *player = [self instanceOf:role.player.identifier named:text into:trial reason:reason];
	if (player == nil) {
		return nil;
	}
	NSMutableDictionary *players = [kept mutableCopy];
	[players setObject:player forKey:roleId];
	NSString *same = [self modelIdOf:[trial factOf:factTypeId players:players] in:trial];
	if ([same isEqualToString:factInstanceId]) {
		/* Named as it was: nothing to change. */
		return factInstanceId;
	}
	if (same != nil) {
		[self refuse:@"That fact is there already." reason:reason];
		return nil;
	}
	BOOL blocked = NO;
	[self objectifyingInstanceOf:factInstanceId blocked:&blocked];
	if (blocked) {
		[self refuse:@"An instance of the type that objectifies it is this fact, and plays a role or identifies "
		             @"another: remove that first."
		      reason:reason];
		return nil;
	}
	__block NSString *created = nil;
	/* Refused part way (a role of an incomplete fact still unnamed), the
	 * fact stays as it was. */
	[_editor group:@"Edit Fact" trying:^BOOL {
		if ([self removeFact:factInstanceId reason:reason]) {
			created = [self addFactOf:factTypeId players:kept named:@{ roleId: text } reason:reason];
		}
		return created != nil;
	}];
	return created;
}

/* The instance added, unless the model has it already. */
- (NSString *)addInstance:(NSString *)created of:(NSString *)objectTypeId in:(ORMSamplePopulation *)population
                   reason:(NSString **)reason
{
	if (created == nil) {
		return nil;
	}
	NSString *had = [self modelIdOf:created in:population];
	if (had != nil) {
		ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
		[self refuse:[NSString stringWithFormat:@"There is already a %@ %@.", type.name,
		                                        [self nameOf:[_editor.model elementWithId:had]]]
		      reason:reason];
		return nil;
	}
	return [self addPopulationNow:population reason:reason] ? created : nil;
}

/* What identifies the type, as the table names it: "Booking Nr". */
- (NSString *)identifierNameOf:(ORMObjectType *)type
{
	NSArray *names = [[type.preferredIdentifier allRoles] valueForKeyPath:@"player.name"] ?: @[];
	return [names count] > 0 ? [names componentsJoinedByString:@" and "] : @"identifier";
}

- (NSString *)addInstanceNowOf:(NSString *)objectTypeId
                         named:(NSString *)text
                  objectifying:(NSDictionary<NSString *, NSString *> *)textsByRole
                        reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	ORMFactType *fact = [type isKindOfClass:[ORMObjectType class]] ? type.nestedFactType : nil;
	if (fact == nil || [self isTheFactItObjectifies:type]) {
		[self refuse:@"Only an objectifying type identified otherwise than by its fact is added so." reason:reason];
		return nil;
	}
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	NSString *made = [self fact:fact players:nil named:textsByRole into:population reason:reason];
	if (made == nil) {
		return nil;
	}
	/* Its own values, as an instance of it is named. */
	NSArray<ORMRole *> *identifying = [type.preferredIdentifier allRoles];
	NSArray *parts = [identifying count] == 1 ? @[ text ?: @"" ] : ORMNameParts(text ?: @"");
	if ([text length] == 0 || [parts count] != [identifying count]) {
		[self refuse:[NSString stringWithFormat:@"Name the %@.", [self identifierNameOf:type]] reason:reason];
		return nil;
	}
	NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [identifying count]; i++) {
		ORMRole *role = [identifying objectAtIndex:i];
		NSString *part = [self instanceOf:role.player.identifier named:ORMUnwrapPart([parts objectAtIndex:i])
		                             into:population reason:reason];
		if (part == nil) {
			return nil;
		}
		[byRole setObject:part forKey:role.identifier];
	}
	NSString *created = [population instanceOf:objectTypeId objectifying:made identifiedBy:byRole];
	return [self addInstance:created of:objectTypeId in:population reason:reason];
}

- (NSString *)addInstanceNowOf:(NSString *)objectTypeId named:(NSString *)text reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	if ([type isKindOfClass:[ORMObjectType class]] && type.nestedFactType != nil && ![self isTheFactItObjectifies:type]) {
		[self refuse:[NSString stringWithFormat:@"Each %@ is a fact of \"%@\" too: name its players as well.", type.name,
		                                        [type.nestedFactType displayText]]
		      reason:reason];
		return nil;
	}
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	NSString *created = [self instanceOf:objectTypeId named:text into:population reason:reason];
	return [self addInstance:created of:objectTypeId in:population reason:reason];
}

/* The instance with the values identifying it named anew, by the role
 * each plays; or, for a value, the value. */
- (BOOL)renameInstance:(NSString *)instanceId parts:(NSDictionary<NSString *, NSString *> *)textsByRole
                reason:(NSString **)reason
{
	ORMInstance *instance = [_editor.model elementWithId:instanceId];
	if (![instance isKindOfClass:[ORMInstance class]]) {
		return [self refuse:@"There is no such instance." reason:reason];
	}
	ORMObjectType *type = instance.objectType;
	if ([instance supertypeInstance] != nil) {
		/* Identified as its supertype is: that one renamed. */
		return [self renameInstance:[[instance supertypeInstance] identifier] parts:textsByRole reason:reason];
	}
	if (instance.value != nil) {
		NSString *text = [textsByRole objectForKey:@""];
		if ([text length] == 0) {
			return [self refuse:@"Name the instance." reason:reason];
		}
		if ([text isEqualToString:instance.value]) {
			return YES;
		}
		for (ORMInstance *other in [type instances]) {
			if ([other.value isEqualToString:text]) {
				return [self refuse:[NSString stringWithFormat:@"There is already a %@ %@.", type.name, text] reason:reason];
			}
		}
		[_editor modelChange:@"Rename Value" with:^{
			instance.value = text;
			if (instance.invariantValue != nil) {
				instance.invariantValue = text;
			}
			[_editor wrote:instance];
		}];
		return YES;
	}
	if ([instance objectifiedInstance] != nil || [self isTheFactItObjectifies:type]) {
		return [self refuse:[NSString stringWithFormat:@"%@ is the fact it objectifies: edit that fact.", type.name]
		             reason:reason];
	}
	/* The new parts, found or made; the others kept. */
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
	NSDictionary *identifying = [instance identifyingInstancesByRole];
	for (NSString *roleId in identifying) {
		[byRole setObject:[[identifying objectForKey:roleId] identifier] forKey:roleId];
	}
	NSMutableDictionary *named = [NSMutableDictionary dictionary];
	for (NSString *roleId in textsByRole) {
		ORMRole *role = [_editor.model elementWithId:roleId];
		if (![role isKindOfClass:[ORMRole class]] || [byRole objectForKey:roleId] == nil) {
			return [self refuse:@"It is not identified by that role." reason:reason];
		}
		NSString *part = [self instanceOf:role.player.identifier named:[textsByRole objectForKey:roleId] into:population
		                           reason:reason];
		if (part == nil) {
			return NO;
		}
		[byRole setObject:part forKey:roleId];
		[named setObject:part forKey:roleId];
	}
	/* Another so identified, when each part is one the model has. */
	NSMutableDictionary *resolved = [NSMutableDictionary dictionary];
	BOOL known = YES;
	for (NSString *roleId in byRole) {
		NSString *part = [byRole objectForKey:roleId];
		NSString *had = [_editor.model elementWithId:part] != nil ? part : [self modelIdOf:part in:population];
		known = known && had != nil;
		[resolved setObject:had ?: part forKey:roleId];
	}
	NSString *same = known ? [[self existingInstancesWithFacts:NO] objectForKey:ORMKeyOf(type.identifier, resolved)] : nil;
	if ([same isEqualToString:instanceId]) {
		return YES;
	}
	if (same != nil) {
		return [self refuse:[NSString stringWithFormat:@"There is already a %@ %@.", type.name,
		                                               [self nameOf:[_editor.model elementWithId:same]]]
		             reason:reason];
	}
	/* Its role instances for those roles, pointed at the new parts. */
	NSMutableDictionary *roleInstances = [NSMutableDictionary dictionary];
	for (NSString *roleInstanceId in instance.identifyingRoleInstances) {
		ORMRoleInstance *roleInstance = [_editor.model elementWithId:roleInstanceId];
		if ([roleInstance isKindOfClass:[ORMRoleInstance class]] && [named objectForKey:roleInstance.role.identifier] != nil) {
			[roleInstances setObject:roleInstance forKey:roleInstance.role.identifier];
		}
	}
	return [_editor group:@"Rename Instance" trying:^BOOL {
		/* The new parts first: they may be found, or made, under other ids. */
		NSMutableDictionary *parts = [NSMutableDictionary dictionary];
		for (NSString *roleId in named) {
			NSString *had = [self modelIdOf:[named objectForKey:roleId] in:population];
			[parts setObject:had ?: [named objectForKey:roleId] forKey:roleId];
		}
		if (![population isEmpty] && ![self addPopulationNow:population reason:reason]) {
			return NO;
		}
		[self->_editor modelChange:@"Rename Instance" with:^{
			NSMutableArray *old = [NSMutableArray array];
			for (NSString *roleId in roleInstances) {
				ORMRoleInstance *roleInstance = [roleInstances objectForKey:roleId];
				[old addObject:roleInstance.instanceId ?: @""];
				roleInstance.instanceId = [parts objectForKey:roleId];
				[self->_editor wrote:roleInstance];
			}
			/* A value that identified it and nothing else now goes. */
			for (NSString *identifier in old) {
				ORMInstance *value = [self->_editor.model elementWithId:identifier];
				if ([value isKindOfClass:[ORMInstance class]] && [value.elementName isEqualToString:@"ValueTypeInstance"]
				    && [[self roleInstances:@"EntityTypeRoleInstance" of:identifier] count] == 0
				    && [[self roleInstances:@"FactTypeRoleInstance" of:identifier] count] == 0) {
					[self removeFromPopulation:value];
				}
			}
		}];
		return YES;
	}];
}

- (BOOL)renameInstanceNow:(NSString *)instanceId to:(NSString *)text reason:(NSString **)reason
{
	ORMInstance *instance = [_editor.model elementWithId:instanceId];
	while ([instance isKindOfClass:[ORMInstance class]] && [instance supertypeInstance] != nil) {
		instance = [instance supertypeInstance];
	}
	if (![instance isKindOfClass:[ORMInstance class]]) {
		return [self refuse:@"There is no such instance." reason:reason];
	}
	if (instance.value != nil) {
		return [self renameInstance:instance.identifier parts:@{ @"": text ?: @"" } reason:reason];
	}
	NSArray *roles = [instance.objectType.preferredIdentifier allRoles];
	if ([roles count] == 1) {
		return [self renameInstance:instance.identifier parts:@{ [[roles firstObject] identifier]: text ?: @"" }
		                     reason:reason];
	}
	NSArray *parts = ORMNameParts(text ?: @"");
	if ([roles count] == 0 || [parts count] != [roles count]) {
		return [self refuse:[NSString stringWithFormat:@"Name each of what identifies %@, separated by commas.",
		                                               instance.objectType.name]
		             reason:reason];
	}
	NSMutableDictionary *texts = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		[texts setObject:ORMUnwrapPart([parts objectAtIndex:i]) forKey:[[roles objectAtIndex:i] identifier]];
	}
	return [self renameInstance:instance.identifier parts:texts reason:reason];
}

- (BOOL)renameInstanceNow:(NSString *)instanceId role:(NSString *)roleId to:(NSString *)text reason:(NSString **)reason
{
	ORMInstance *instance = [_editor.model elementWithId:instanceId];
	while ([instance isKindOfClass:[ORMInstance class]] && [instance supertypeInstance] != nil) {
		instance = [instance supertypeInstance];
	}
	if ([[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
		return [self refuse:@"Name the instance." reason:reason];
	}
	return [self renameInstance:instance.identifier parts:@{ roleId ?: @"": text } reason:reason];
}

- (NSString *)addInstanceNowOf:(NSString *)objectTypeId
                namedByRole:(NSDictionary<NSString *, NSString *> *)textsByRole
                     reason:(NSString **)reason
{
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	NSString *created = [self instanceOf:objectTypeId namedByRole:textsByRole into:population reason:reason];
	return [self addInstance:created of:objectTypeId in:population reason:reason];
}

- (BOOL)removeInstanceNow:(NSString *)instanceId reason:(NSString **)reason
{
	ORMInstance *instance = [_editor.model elementWithId:instanceId];
	if (![instance isKindOfClass:[ORMInstance class]]) {
		return [self refuse:@"There is no such instance." reason:reason];
	}
	/* Role instances refer to their player; a fact's refers to those. */
	NSUInteger playing = [[self roleInstances:@"FactTypeRoleInstance" of:instanceId] count];
	if (playing > 0) {
		return [self refuse:[NSString stringWithFormat:@"It plays a role in %lu %@: remove %@ first.", (unsigned long)playing,
		                                               playing == 1 ? @"fact" : @"facts", playing == 1 ? @"it" : @"them"]
		             reason:reason];
	}
	if ([[self roleInstances:@"EntityTypeRoleInstance" of:instanceId] count] > 0) {
		return [self refuse:@"It identifies another instance: remove that first." reason:reason];
	}
	if ([[self instancesWhose:@"supertypeInstanceId" is:instanceId] count] > 0) {
		return [self refuse:@"A subtype's instance is it: remove that first." reason:reason];
	}
	[_editor modelChange:@"Remove Instance" with:^{
		/* What identifies it: its own role instances, on the roles. */
		for (NSString *roleInstanceId in instance.identifyingRoleInstances) {
			ORMRoleInstance *roleInstance = [_editor.model elementWithId:roleInstanceId];
			if ([roleInstance isKindOfClass:[ORMRoleInstance class]]) {
				[self removeFromPopulation:roleInstance];
			}
		}
		[self removeFromPopulation:instance];
	}];
	return YES;
}

#pragma mark Derived and stored facts

/* Whether a derivation of the model is stored: its facts are written into
 * the population (docs/DERIVATION.md). */
- (BOOL)hasStoredDerivations
{
	for (ORMQuery *query in [ORMQuery derivationsInModel:_editor.model]) {
		if ([query.derivedFactType derivationRule].isStored) {
			return YES;
		}
	}
	return NO;
}

/* A population added, and the stored derived facts brought up to date
 * with it: one change. */
- (BOOL)addPopulation:(ORMSamplePopulation *)population reason:(NSString **)reason
{
	return [self edit:@"Add Sample Population" reason:reason with:^BOOL {
		return [self addPopulationNow:population reason:reason];
	}];
}

/* An edit of the population, then its stored derived facts brought up to
 * date: one change, undone as one, refused as one. An edit inside another
 * is that one's. */
- (BOOL)edit:(NSString *)name reason:(NSString **)reason with:(BOOL (^)(void))edit
{
	if (_editing > 0 || ![self hasStoredDerivations]) {
		return edit();
	}
	_editing++;
	BOOL done = [_editor group:name trying:^BOOL {
		return edit() && [self bringStoredDerivationsUpToDate:reason];
	}];
	_editing--;
	return done;
}

/* Round after round, till no stored derivation changes: one that reads
 * another sees what that one stored the round before. Derivations do not
 * recur, so it ends; the bound guards it all the same. */
- (BOOL)bringStoredDerivationsUpToDate:(NSString **)reason
{
	NSUInteger rounds = [[ORMQuery derivationsInModel:_editor.model] count] + 1;
	for (NSUInteger round = 0; round < rounds; round++) {
		BOOL changed = NO;
		if (![self bringStoredDerivationsOnce:&changed reason:reason]) {
			return NO;
		}
		if (!changed) {
			return YES;
		}
	}
	return YES;
}

/* One round: each stored derivation's facts made what its rule derives
 * from the population as it is. */
- (BOOL)bringStoredDerivationsOnce:(BOOL *)changed reason:(NSString **)reason
{
	ORMDeriver *deriver = [[ORMDeriver alloc] initWithModel:_editor.model];
	NSDictionary *derived = [deriver derivedFacts];
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
	NSMutableArray *gone = [NSMutableArray array];
	for (NSString *factId in derived) {
		ORMFactType *fact = [_editor.model elementWithId:factId];
		ORMDerivationRule *rule = [fact derivationRule];
		if (!rule.isStored) {
			continue;
		}
		/* What is stored, by its players; a unary's truth left out. */
		NSMutableDictionary *stored = [NSMutableDictionary dictionary];
		for (ORMFactInstance *instance in [fact instances]) {
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			for (NSString *roleId in instance.instancesByRole) {
				ORMInstance *player = [instance.instancesByRole objectForKey:roleId];
				if (!player.objectType.isImplicitBooleanValue) {
					[byRole setObject:player.identifier forKey:roleId];
				}
			}
			[stored setObject:instance.identifier forKey:byRole];
		}
		NSMutableSet *kept = [NSMutableSet set];
		for (ORMDerivedFact *each in [derived objectForKey:factId]) {
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			BOOL known = YES;
			for (NSString *roleId in each.players) {
				id player = [each.players objectForKey:roleId];
				if ([player isKindOfClass:[ORMInstance class]]) {
					[byRole setObject:[player identifier] forKey:roleId];
				} else {
					/* A value no instance has yet: made. */
					ORMRole *role = [_editor.model elementWithId:roleId];
					[byRole setObject:[population value:player of:role.player.identifier] forKey:roleId];
					known = NO;
				}
			}
			if (known && [stored objectForKey:byRole] != nil) {
				[kept addObject:byRole];
				continue;
			}
			[population factOf:factId players:byRole];
		}
		/* A fully derived one's facts the rule no longer derives go; a
		 * partly derived one's may be asserted, and stay. */
		if (!rule.isPartial) {
			for (NSDictionary *byRole in stored) {
				if (![kept containsObject:byRole]) {
					[gone addObject:[stored objectForKey:byRole]];
				}
			}
		}
	}
	*changed = [gone count] > 0 || ![population isEmpty];
	for (NSString *factInstanceId in gone) {
		if (![self removeFactNow:factInstanceId reason:reason]) {
			return NO;
		}
	}
	return [population isEmpty] || [self addPopulationNow:population reason:reason];
}

- (NSString *)addFactOf:(NSString *)factTypeId named:(NSDictionary<NSString *, NSString *> *)textsByRole
                 reason:(NSString **)reason
{
	__block NSString *made = nil;
	BOOL done = [self edit:@"Add Fact" reason:reason with:^BOOL {
		made = [self addFactNowOf:factTypeId named:textsByRole reason:reason];
		return made != nil;
	}];
	return done ? made : nil;
}

- (BOOL)removeFact:(NSString *)factInstanceId reason:(NSString **)reason
{
	return [self edit:@"Remove Fact" reason:reason with:^BOOL {
		return [self removeFactNow:factInstanceId reason:reason];
	}];
}

- (NSString *)setPlayer:(NSString *)text ofRole:(NSString *)roleId inFact:(NSString *)factInstanceId
                 reason:(NSString **)reason
{
	__block NSString *made = nil;
	BOOL done = [self edit:@"Edit Fact" reason:reason with:^BOOL {
		made = [self setPlayerNow:text ofRole:roleId inFact:factInstanceId reason:reason];
		return made != nil;
	}];
	return done ? made : nil;
}

- (NSString *)addInstanceOf:(NSString *)objectTypeId named:(NSString *)text reason:(NSString **)reason
{
	__block NSString *made = nil;
	BOOL done = [self edit:@"Add Instance" reason:reason with:^BOOL {
		made = [self addInstanceNowOf:objectTypeId named:text reason:reason];
		return made != nil;
	}];
	return done ? made : nil;
}

- (NSString *)addInstanceOf:(NSString *)objectTypeId
                      named:(NSString *)text
               objectifying:(NSDictionary<NSString *, NSString *> *)textsByRole
                     reason:(NSString **)reason
{
	__block NSString *made = nil;
	BOOL done = [self edit:@"Add Instance" reason:reason with:^BOOL {
		made = [self addInstanceNowOf:objectTypeId named:text objectifying:textsByRole reason:reason];
		return made != nil;
	}];
	return done ? made : nil;
}

- (BOOL)renameInstance:(NSString *)instanceId to:(NSString *)text reason:(NSString **)reason
{
	return [self edit:@"Rename Instance" reason:reason with:^BOOL {
		return [self renameInstanceNow:instanceId to:text reason:reason];
	}];
}

- (BOOL)renameInstance:(NSString *)instanceId role:(NSString *)roleId to:(NSString *)text reason:(NSString **)reason
{
	return [self edit:@"Rename Instance" reason:reason with:^BOOL {
		return [self renameInstanceNow:instanceId role:roleId to:text reason:reason];
	}];
}

- (NSString *)addInstanceOf:(NSString *)objectTypeId
                namedByRole:(NSDictionary<NSString *, NSString *> *)textsByRole
                     reason:(NSString **)reason
{
	__block NSString *made = nil;
	BOOL done = [self edit:@"Add Instance" reason:reason with:^BOOL {
		made = [self addInstanceNowOf:objectTypeId namedByRole:textsByRole reason:reason];
		return made != nil;
	}];
	return done ? made : nil;
}

- (BOOL)removeInstance:(NSString *)instanceId reason:(NSString **)reason
{
	return [self edit:@"Remove Instance" reason:reason with:^BOOL {
		return [self removeInstanceNow:instanceId reason:reason];
	}];
}

- (void)removePopulation
{
	ORMModel *model = _editor.model;
	NSMutableArray *gone = [NSMutableArray array];
	for (ORMObjectType *type in model.objectTypes) {
		[gone addObjectsFromArray:[type instances]];
	}
	for (ORMFactType *fact in model.factTypes) {
		for (ORMFactInstance *instance in [fact instances]) {
			/* A unary fact NORMA keeps on its player goes with it. */
			if (!instance.isKeptOnPlayer) {
				[gone addObject:instance];
			}
		}
		for (ORMRole *role in fact.roles) {
			[gone addObjectsFromArray:role.roleInstances ?: @[]];
		}
	}
	if ([gone count] == 0) {
		return;
	}
	[_editor modelChange:@"Remove Sample Population" with:^{
		for (ORMElement *element in gone) {
			[self removeFromPopulation:element];
		}
	}];
}

@end
