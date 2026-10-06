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
	NSMutableDictionary *existing = [self existingInstancesWithFacts:NO];
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
				NSString *had = [existing objectForKey:[NSString stringWithFormat:@"%@ ^%@", item.typeId, resolve(item.text)]];
				if (had != nil) {
					[renamed setObject:had forKey:item.identifier];
					break;
				}
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

/* Detached, with the container it leaves empty (Instances, RoleInstances):
 * NORMA writes none empty. */
static void
ORMDetachPruning(NSXMLElement *element)
{
	NSXMLElement *container = (NSXMLElement *)[element parent];
	[element detach];
	if (![container isKindOfClass:[NSXMLElement class]]
	    || ![@[ @"Instances", @"RoleInstances" ] containsObject:[container localName] ?: @""]) {
		return;
	}
	for (NSXMLNode *child in [container children]) {
		if ([child kind] == NSXMLElementKind) {
			return;
		}
	}
	[container detach];
}

#pragma mark One at a time

/* The type an instance of this one is identified as: itself, or the
 * supertype it is identified as, having no identifier of its own. */
- (ORMObjectType *)identifiedTypeOf:(ORMObjectType *)type
{
	while (type.kind != ORMValueType && type.preferredIdentifier == nil && [type.supertypes count] > 0) {
		type = [type identifyingSupertype];
	}
	return type;
}

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
	ORMObjectType *type = [self identifiedTypeOf:[_editor.model elementWithId:objectTypeId]];
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
	ORMObjectType *identified = [self identifiedTypeOf:type];
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

/* The fact's population: the role's player named, the others' as they are. */
- (NSString *)addFactOf:(NSString *)factTypeId
                players:(NSDictionary<NSString *, NSString *> *)instancesByRole
                  named:(NSDictionary<NSString *, NSString *> *)textsByRole
                 reason:(NSString **)reason
{
	ORMFactType *fact = [_editor.model elementWithId:factTypeId];
	if (![fact isKindOfClass:[ORMFactType class]]) {
		[self refuse:@"There is no such fact type." reason:reason];
		return nil;
	}
	ORMSamplePopulation *population = [[ORMSamplePopulation alloc] init];
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
	NSString *created = [population factOf:factTypeId players:players];
	if ([self modelIdOf:created in:population] != nil) {
		[self refuse:@"That fact is there already." reason:reason];
		return nil;
	}
	/* Objectified, and identified by the fact: its instance is the fact,
	 * made with it. (One identified otherwise needs its values named.) */
	ORMObjectType *objectifying = fact.objectifyingType;
	if (objectifying != nil && [self isTheFactItObjectifies:objectifying]) {
		[population instanceOf:objectifying.identifier objectifying:created];
	}
	return [self addPopulation:population reason:reason] ? created : nil;
}

- (NSString *)addFactNowOf:(NSString *)factTypeId named:(NSDictionary<NSString *, NSString *> *)textsByRole
                 reason:(NSString **)reason
{
	return [self addFactOf:factTypeId players:nil named:textsByRole reason:reason];
}

/* Every element of the document of the kind, by what it refers to. */
- (NSArray<NSXMLElement *> *)elements:(NSString *)local referringTo:(NSString *)identifier
{
	NSMutableArray *found = [NSMutableArray array];
	for (NSXMLElement *element in ORMDescendants([_editor.document rootElement], CORE, local)) {
		if ([ORMAttribute(element, @"ref") isEqualToString:identifier]) {
			[found addObject:element];
		}
	}
	return found;
}

- (BOOL)removeFactNow:(NSString *)factInstanceId reason:(NSString **)reason
{
	NSXMLElement *fact = [_editor xml:factInstanceId];
	if (fact == nil || ![[fact localName] isEqualToString:@"FactTypeInstance"]) {
		return [self refuse:@"There is no such fact." reason:reason];
	}
	BOOL blocked = NO;
	NSXMLElement *objectifying = [self objectifyingInstanceOf:factInstanceId blocked:&blocked];
	if (blocked) {
		return [self refuse:@"An instance of the type that objectifies it is this fact, and plays a role or identifies "
		                    @"another: remove that first."
		             reason:reason];
	}
	/* Its role instances, under the roles. */
	NSMutableArray *roleInstances = [NSMutableArray array];
	for (NSXMLElement *refs in ORMChildren(fact, CORE, @"RoleInstances")) {
		for (NSXMLElement *ref in ORMChildren(refs, CORE, @"FactTypeRoleInstance")) {
			NSXMLElement *roleInstance = [_editor xml:ORMAttribute(ref, @"ref")];
			if (roleInstance != nil) {
				[roleInstances addObject:roleInstance];
			}
		}
	}
	[_editor change:@"Remove Fact" with:^{
		for (NSXMLElement *roleInstance in roleInstances) {
			ORMDetachPruning(roleInstance);
		}
		ORMDetachPruning(fact);
		if (objectifying != nil) {
			ORMDetachPruning(objectifying);
		}
	}];
	return YES;
}

/* The instance of the objectifying type that is the fact; with blocked,
 * when it cannot go with the fact: it plays a role, identifies another or
 * is a subtype's, or is identified by more than the fact. */
- (NSXMLElement *)objectifyingInstanceOf:(NSString *)factInstanceId blocked:(BOOL *)blocked
{
	*blocked = NO;
	NSXMLElement *ref = [[self elements:@"ObjectifiedInstance" referringTo:factInstanceId] firstObject];
	NSXMLElement *instance = (NSXMLElement *)[ref parent];
	NSString *identifier = ORMAttribute(instance, @"id");
	if (identifier == nil) {
		return nil;
	}
	BOOL referred = NO;
	for (NSString *local in @[ @"FactTypeRoleInstance", @"EntityTypeRoleInstance", @"SupertypeInstance" ]) {
		for (NSXMLElement *element in [self elements:local referringTo:identifier]) {
			/* A role instance's own element names its player by ref too. */
			referred = referred || [ORMAttribute(element, @"id") length] > 0 || [local isEqualToString:@"SupertypeInstance"];
		}
	}
	*blocked = referred || [ORMChildren(instance, CORE, @"RoleInstances") count] > 0;
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
	return [self addPopulation:population reason:reason] ? created : nil;
}

- (NSString *)addInstanceNowOf:(NSString *)objectTypeId named:(NSString *)text reason:(NSString **)reason
{
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
		NSXMLElement *element = [_editor xml:instanceId];
		[_editor change:@"Rename Value" with:^{
			for (NSString *local in @[ @"Value", @"InvariantValue" ]) {
				[ORMChild(element, CORE, local) setStringValue:text];
			}
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
	for (NSXMLElement *refs in ORMChildren([_editor xml:instanceId], CORE, @"RoleInstances")) {
		for (NSXMLElement *ref in ORMChildren(refs, CORE, @"EntityTypeRoleInstance")) {
			NSXMLElement *roleInstance = [_editor xml:ORMAttribute(ref, @"ref")];
			NSXMLElement *role = (NSXMLElement *)[[roleInstance parent] parent];
			NSString *roleId = ORMAttribute(role, @"id");
			if (roleId != nil && [named objectForKey:roleId] != nil) {
				[roleInstances setObject:roleInstance forKey:roleId];
			}
		}
	}
	return [_editor group:@"Rename Instance" trying:^BOOL {
		/* The new parts first: they may be found, or made, under other ids. */
		NSMutableDictionary *parts = [NSMutableDictionary dictionary];
		for (NSString *roleId in named) {
			NSString *had = [self modelIdOf:[named objectForKey:roleId] in:population];
			[parts setObject:had ?: [named objectForKey:roleId] forKey:roleId];
		}
		if (![population isEmpty] && ![self addPopulation:population reason:reason]) {
			return NO;
		}
		NSMutableArray *old = [NSMutableArray array];
		[self->_editor change:@"Rename Instance" with:^{
			for (NSString *roleId in roleInstances) {
				NSXMLElement *roleInstance = [roleInstances objectForKey:roleId];
				[old addObject:ORMAttribute(roleInstance, @"ref") ?: @""];
				ORMSetAttribute(roleInstance, @"ref", [parts objectForKey:roleId]);
			}
		}];
		/* A value that identified it and nothing else now goes. */
		for (NSString *identifier in old) {
			NSXMLElement *element = [self->_editor xml:identifier];
			if ([[element localName] isEqualToString:@"ValueTypeInstance"]
			    && [[self elements:@"EntityTypeRoleInstance" referringTo:identifier] count] == 0
			    && [[self elements:@"FactTypeRoleInstance" referringTo:identifier] count] == 0) {
				[self->_editor change:@"Remove Value" with:^{
					ORMDetachPruning(element);
				}];
			}
		}
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
	NSXMLElement *instance = [_editor xml:instanceId];
	if (instance == nil || ![@[ @"ValueTypeInstance", @"EntityTypeInstance", @"EntityTypeSubtypeInstance" ]
	                           containsObject:[instance localName]]) {
		return [self refuse:@"There is no such instance." reason:reason];
	}
	/* Role instances refer to their player; a fact's refers to those. */
	NSUInteger playing = 0;
	for (NSXMLElement *roleInstance in [self elements:@"FactTypeRoleInstance" referringTo:instanceId]) {
		playing += [ORMAttribute(roleInstance, @"id") length] > 0;
	}
	if (playing > 0) {
		return [self refuse:[NSString stringWithFormat:@"It plays a role in %lu %@: remove %@ first.", (unsigned long)playing,
		                                               playing == 1 ? @"fact" : @"facts", playing == 1 ? @"it" : @"them"]
		             reason:reason];
	}
	for (NSXMLElement *roleInstance in [self elements:@"EntityTypeRoleInstance" referringTo:instanceId]) {
		if ([ORMAttribute(roleInstance, @"id") length] > 0) {
			return [self refuse:@"It identifies another instance: remove that first." reason:reason];
		}
	}
	if ([[self elements:@"SupertypeInstance" referringTo:instanceId] count] > 0) {
		return [self refuse:@"A subtype's instance is it: remove that first." reason:reason];
	}
	/* What identifies it: its own role instances, under the roles. */
	NSMutableArray *identifying = [NSMutableArray array];
	for (NSXMLElement *refs in ORMChildren(instance, CORE, @"RoleInstances")) {
		for (NSXMLElement *ref in ORMChildren(refs, CORE, @"EntityTypeRoleInstance")) {
			NSXMLElement *roleInstance = [_editor xml:ORMAttribute(ref, @"ref")];
			if (roleInstance != nil) {
				[identifying addObject:roleInstance];
			}
		}
	}
	[_editor change:@"Remove Instance" with:^{
		for (NSXMLElement *roleInstance in identifying) {
			ORMDetachPruning(roleInstance);
		}
		ORMDetachPruning(instance);
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

/* An edit of the population, then its stored derived facts brought up to
 * date: one change, undone as one, refused as one. An edit inside another
 * is that one's. */
- (BOOL)edit:(NSString *)name with:(BOOL (^)(void))edit
{
	if (_editing > 0 || ![self hasStoredDerivations]) {
		return edit();
	}
	_editing++;
	BOOL done = [_editor group:name trying:^BOOL {
		return edit() && [self bringStoredDerivationsUpToDate:NULL];
	}];
	_editing--;
	return done;
}

- (BOOL)bringStoredDerivationsUpToDate:(NSString **)reason
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
	for (NSString *factInstanceId in gone) {
		if (![self removeFactNow:factInstanceId reason:reason]) {
			return NO;
		}
	}
	return [population isEmpty] || [self addPopulation:population reason:reason];
}

- (NSString *)addFactOf:(NSString *)factTypeId named:(NSDictionary<NSString *, NSString *> *)textsByRole
                 reason:(NSString **)reason
{
	__block NSString *made = nil;
	[self edit:@"Add Fact" with:^BOOL {
		made = [self addFactNowOf:factTypeId named:textsByRole reason:reason];
		return made != nil;
	}];
	return made;
}

- (BOOL)removeFact:(NSString *)factInstanceId reason:(NSString **)reason
{
	return [self edit:@"Remove Fact" with:^BOOL {
		return [self removeFactNow:factInstanceId reason:reason];
	}];
}

- (NSString *)setPlayer:(NSString *)text ofRole:(NSString *)roleId inFact:(NSString *)factInstanceId
                 reason:(NSString **)reason
{
	__block NSString *made = nil;
	[self edit:@"Edit Fact" with:^BOOL {
		made = [self setPlayerNow:text ofRole:roleId inFact:factInstanceId reason:reason];
		return made != nil;
	}];
	return made;
}

- (NSString *)addInstanceOf:(NSString *)objectTypeId named:(NSString *)text reason:(NSString **)reason
{
	__block NSString *made = nil;
	[self edit:@"Add Instance" with:^BOOL {
		made = [self addInstanceNowOf:objectTypeId named:text reason:reason];
		return made != nil;
	}];
	return made;
}

- (BOOL)renameInstance:(NSString *)instanceId to:(NSString *)text reason:(NSString **)reason
{
	return [self edit:@"Rename Instance" with:^BOOL {
		return [self renameInstanceNow:instanceId to:text reason:reason];
	}];
}

- (BOOL)renameInstance:(NSString *)instanceId role:(NSString *)roleId to:(NSString *)text reason:(NSString **)reason
{
	return [self edit:@"Rename Instance" with:^BOOL {
		return [self renameInstanceNow:instanceId role:roleId to:text reason:reason];
	}];
}

- (NSString *)addInstanceOf:(NSString *)objectTypeId
                namedByRole:(NSDictionary<NSString *, NSString *> *)textsByRole
                     reason:(NSString **)reason
{
	__block NSString *made = nil;
	[self edit:@"Add Instance" with:^BOOL {
		made = [self addInstanceNowOf:objectTypeId namedByRole:textsByRole reason:reason];
		return made != nil;
	}];
	return made;
}

- (BOOL)removeInstance:(NSString *)instanceId reason:(NSString **)reason
{
	return [self edit:@"Remove Instance" with:^BOOL {
		return [self removeInstanceNow:instanceId reason:reason];
	}];
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
