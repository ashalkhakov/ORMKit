/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMPath.h"
#import "ORMPopulationEditor.h"

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

@end

@implementation ORMPopulationEditor

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

/* A role instance under the role, of the kind, for the instance. Its id. */
- (NSString *)roleInstance:(NSString *)local on:(NSString *)roleId for:(NSString *)instanceId
{
	NSXMLDocument *document = _editor.document;
	NSXMLElement *container = ORMEnsureChild(document, [_editor xml:roleId], CORE, @"RoleInstances");
	NSXMLElement *roleInstance = ORMNewElement(document, CORE, local);
	NSString *identifier = ORMNewId();
	ORMSetAttribute(roleInstance, @"id", identifier);
	ORMSetAttribute(roleInstance, @"ref", instanceId);
	[container addChild:roleInstance];
	return identifier;
}

/* The implicit boolean value type's "True", made when it has none. */
- (NSString *)truthOf:(ORMObjectType *)type existing:(NSMutableDictionary *)existing
{
	NSString *key = [NSString stringWithFormat:@"%@ True", type.identifier];
	NSString *had = [existing objectForKey:key];
	if (had != nil) {
		return had;
	}
	NSXMLDocument *document = _editor.document;
	NSXMLElement *instance = ORMNewElement(document, CORE, @"ValueTypeInstance");
	NSString *identifier = ORMNewId();
	ORMSetAttribute(instance, @"id", identifier);
	NSXMLElement *value = ORMNewElement(document, CORE, @"Value");
	[value setStringValue:@"True"];
	[instance addChild:value];
	[[self instancesOf:type.identifier] addChild:instance];
	[existing setObject:identifier forKey:key];
	return identifier;
}

- (NSXMLElement *)instancesOf:(NSString *)elementId
{
	return ORMEnsureChild(_editor.document, [_editor xml:elementId], CORE, @"Instances");
}

- (BOOL)addPopulation:(ORMSamplePopulation *)population reason:(NSString **)reason
{
	NSMutableDictionary *types = [NSMutableDictionary dictionary];
	if (![self check:population types:types reason:reason]) {
		return NO;
	}
	if ([population isEmpty]) {
		return YES;
	}
	ORMModel *model = _editor.model;
	/* A value, or an entity so identified, the model has already is that
	 * instance, not another. */
	NSMutableDictionary *existing = [NSMutableDictionary dictionary];
	for (ORMObjectType *type in model.objectTypes) {
		for (ORMInstance *instance in [type instances]) {
			if (instance.value != nil) {
				[existing setObject:instance.identifier forKey:[NSString stringWithFormat:@"%@ %@", type.identifier,
				                                                                           instance.value]];
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
	[_editor change:@"Add Sample Population" with:^{
		NSXMLDocument *document = self->_editor.document;
		NSMutableDictionary *renamed = [NSMutableDictionary dictionary];
		NSString *(^resolve)(NSString *) = ^NSString *(NSString *identifier) {
			return [renamed objectForKey:identifier] ?: identifier;
		};
		for (ORMSampleItem *item in [population items]) {
			switch (item.kind) {
			case ORMSampleValue: {
				NSString *had = [existing objectForKey:[NSString stringWithFormat:@"%@ %@", item.typeId, item.text]];
				if (had != nil) {
					[renamed setObject:had forKey:item.identifier];
					break;
				}
				NSXMLElement *instance = ORMNewElement(document, CORE, @"ValueTypeInstance");
				ORMSetAttribute(instance, @"id", item.identifier);
				NSXMLElement *value = ORMNewElement(document, CORE, @"Value");
				[value setStringValue:item.text];
				[instance addChild:value];
				if (ORMHasInvariantForm([types objectForKey:item.identifier])) {
					NSXMLElement *invariant = ORMNewElement(document, CORE, @"InvariantValue");
					[invariant setStringValue:item.text];
					[instance addChild:invariant];
				}
				[[self instancesOf:item.typeId] addChild:instance];
				break;
			}
			case ORMSampleEntity: {
				NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
				for (NSString *roleId in item.byRole) {
					[byRole setObject:resolve([item.byRole objectForKey:roleId]) forKey:roleId];
				}
				NSString *had = [existing objectForKey:ORMKeyOf(item.typeId, byRole)];
				if (had != nil) {
					[renamed setObject:had forKey:item.identifier];
					break;
				}
				NSXMLElement *instance = ORMNewElement(document, CORE, @"EntityTypeInstance");
				ORMSetAttribute(instance, @"id", item.identifier);
				NSXMLElement *refs = ORMNewElement(document, CORE, @"RoleInstances");
				ORMObjectType *type = [model elementWithId:item.typeId];
				for (ORMRole *role in [type.preferredIdentifier allRoles]) {
					NSString *roleInstance = [self roleInstance:@"EntityTypeRoleInstance" on:role.identifier
					                                        for:resolve([item.byRole objectForKey:role.identifier])];
					[refs addChild:ORMNewRef(document, CORE, @"EntityTypeRoleInstance", roleInstance)];
				}
				[instance addChild:refs];
				[[self instancesOf:item.typeId] addChild:instance];
				break;
			}
			case ORMSampleObjectifying: {
				NSXMLElement *instance = ORMNewElement(document, CORE, @"EntityTypeInstance");
				ORMSetAttribute(instance, @"id", item.identifier);
				if ([item.byRole count] > 0) {
					NSXMLElement *refs = ORMNewElement(document, CORE, @"RoleInstances");
					ORMObjectType *type = [model elementWithId:item.typeId];
					for (ORMRole *role in [type.preferredIdentifier allRoles]) {
						NSString *player = [item.byRole objectForKey:role.identifier];
						if (player != nil) {
							NSString *roleInstance = [self roleInstance:@"EntityTypeRoleInstance" on:role.identifier
							                                        for:resolve(player)];
							[refs addChild:ORMNewRef(document, CORE, @"EntityTypeRoleInstance", roleInstance)];
						}
					}
					[instance addChild:refs];
				}
				[instance addChild:ORMNewRef(document, CORE, @"ObjectifiedInstance", resolve(item.text))];
				[[self instancesOf:item.typeId] addChild:instance];
				break;
			}
			case ORMSampleSubtype: {
				NSXMLElement *instance = ORMNewElement(document, CORE, @"EntityTypeSubtypeInstance");
				ORMSetAttribute(instance, @"id", item.identifier);
				[instance addChild:ORMNewRef(document, CORE, @"SupertypeInstance", resolve(item.text))];
				[[self instancesOf:item.typeId] addChild:instance];
				break;
			}
			case ORMSampleFact: {
				NSXMLElement *instance = ORMNewElement(document, CORE, @"FactTypeInstance");
				ORMSetAttribute(instance, @"id", item.identifier);
				NSXMLElement *refs = ORMNewElement(document, CORE, @"RoleInstances");
				ORMFactType *fact = [model elementWithId:item.typeId];
				for (ORMRole *role in fact.roles) {
					NSString *player = [item.byRole objectForKey:role.identifier];
					if (player == nil && role.player.isImplicitBooleanValue) {
						/* A unary's implicit role, played by its truth. */
						player = [self truthOf:role.player existing:existing];
					}
					if (player != nil) {
						NSString *roleInstance = [self roleInstance:@"FactTypeRoleInstance" on:role.identifier
						                                        for:resolve(player)];
						[refs addChild:ORMNewRef(document, CORE, @"FactTypeRoleInstance", roleInstance)];
					}
				}
				[instance addChild:refs];
				[[self instancesOf:item.typeId] addChild:instance];
				break;
			}
			}
		}
	}];
	return YES;
}

- (void)removePopulation
{
	ORMModel *model = _editor.model;
	NSMutableArray *containers = [NSMutableArray array];
	for (ORMObjectType *type in model.objectTypes) {
		[containers addObjectsFromArray:ORMChildren(type.element, CORE, @"Instances")];
	}
	for (ORMFactType *fact in model.factTypes) {
		[containers addObjectsFromArray:ORMChildren(fact.element, CORE, @"Instances")];
		for (ORMRole *role in fact.roles) {
			[containers addObjectsFromArray:ORMChildren(role.element, CORE, @"RoleInstances")];
		}
	}
	if ([containers count] == 0) {
		return;
	}
	[_editor change:@"Remove Sample Population" with:^{
		for (NSXMLElement *container in containers) {
			[container detach];
		}
	}];
}

@end
