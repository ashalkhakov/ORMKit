/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlaces.h"

@implementation ORMQueryPlaces
{
	NSMutableDictionary<NSString *, NSArray *> *_bySource;
}

- (instancetype)initWithCoreData:(ORMCDModel *)coreData
{
	if ((self = [super init])) {
		_coreData = coreData;
		_bySource = [NSMutableDictionary dictionary];
		for (ORMCDEntity *entity in coreData.entities) {
			for (ORMCDProperty *property in [entity properties]) {
				if (property.source != nil) {
					[_bySource setObject:@[ entity, property ] forKey:property.source];
				}
			}
		}
	}
	return self;
}

- (ORMCDEntity *)entityOf:(ORMObjectType *)type
{
	NSMutableArray *pending = [NSMutableArray arrayWithObject:type];
	while ([pending count] > 0) {
		ORMObjectType *at = [pending objectAtIndex:0];
		[pending removeObjectAtIndex:0];
		ORMCDEntity *entity = [_coreData entityWithSource:at.identifier];
		if (entity != nil) {
			return entity;
		}
		[pending addObjectsFromArray:at.supertypes];
	}
	return nil;
}

- (ORMCDEntity *)parentOf:(ORMCDEntity *)entity
{
	return entity.parentName != nil ? [_coreData entityNamed:entity.parentName] : nil;
}

- (BOOL)entity:(ORMCDEntity *)entity inherits:(ORMCDEntity *)ancestor
{
	for (ORMCDEntity *at = entity; at != nil; at = [self parentOf:at]) {
		if (at == ancestor) {
			return YES;
		}
	}
	return NO;
}

- (ORMCDProperty *)propertyOf:(ORMCDEntity *)entity source:(NSString *)source
{
	NSArray *place = source != nil ? [_bySource objectForKey:source] : nil;
	if (place == nil || entity == nil || ![self entity:entity inherits:[place firstObject]]) {
		return nil;
	}
	return [place lastObject];
}

+ (NSString *)sourceOfRole:(ORMRole *)role
{
	if (role.proxiedRole != nil) {
		return role.proxiedRole.identifier;
	}
	for (ORMRole *other in role.factType.roles) {
		if (other != role && other.proxiedRole != nil) {
			return [other.proxiedRole.factType.identifier stringByAppendingFormat:@".%@", other.proxiedRole.identifier];
		}
	}
	return role.identifier;
}

- (ORMCDProperty *)property:(NSString *)name of:(ORMCDEntity *)entity
{
	for (ORMCDEntity *at = entity; at != nil; at = [self parentOf:at]) {
		ORMCDProperty *property = [at propertyNamed:name];
		if (property != nil) {
			return property;
		}
	}
	return nil;
}

- (NSArray<NSString *> *)namesOf:(ORMCDEntity *)entity
{
	NSMutableArray *names = [NSMutableArray arrayWithObject:entity.name];
	for (NSUInteger i = 0; i < [names count]; i++) {
		for (ORMCDEntity *sub in [_coreData subentitiesOf:[names objectAtIndex:i]]) {
			[names addObject:sub.name];
		}
	}
	return names;
}

- (ORMCDAttribute *)identifierOf:(ORMObjectType *)type on:(ORMCDEntity *)entity
{
	for (ORMRole *role in type.referenceModeFactType.roles) {
		if (role.player == type.referenceModeValueType) {
			ORMCDProperty *property = [self propertyOf:entity source:role.identifier];
			return [property isKindOfClass:[ORMCDAttribute class]] ? (ORMCDAttribute *)property : nil;
		}
	}
	/* A subtype is identified as its supertype is. */
	if (type.preferredIdentifier == nil) {
		for (ORMObjectType *supertype in type.supertypes) {
			ORMCDAttribute *identifier = [self identifierOf:supertype on:entity];
			if (identifier != nil) {
				return identifier;
			}
		}
	}
	return nil;
}

- (NSArray<NSArray<NSString *> *> *)identifyingPartsOf:(ORMObjectType *)type on:(ORMCDEntity *)entity
{
	if (type == nil || entity == nil || [self identifierOf:type on:entity] != nil) {
		return nil;
	}
	ORMObjectType *identified = type;
	while (identified.preferredIdentifier == nil && [identified.supertypes count] > 0) {
		identified = [identified identifyingSupertype];
	}
	NSArray *roles = [identified.preferredIdentifier allRoles];
	if ([roles count] == 0) {
		return nil;
	}
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMRole *role in roles) {
		ORMCDProperty *property = [self propertyOf:entity source:role.identifier];
		if ([property isKindOfClass:[ORMCDAttribute class]]) {
			[parts addObject:@[ property.name ]];
			continue;
		}
		ORMCDRelationship *relationship = [property isKindOfClass:[ORMCDRelationship class]] ? (ORMCDRelationship *)property : nil;
		ORMCDEntity *destination = relationship != nil && !relationship.toMany ? [_coreData entityNamed:relationship.destination] : nil;
		if (destination == nil) {
			return nil;
		}
		/* A part that is an entity: by its identifier, or its own parts. */
		ORMCDAttribute *identifier = [self identifierOf:role.player on:destination];
		NSArray *inner = identifier != nil ? @[ @[ identifier.name ] ] : [self identifyingPartsOf:role.player on:destination];
		if (inner == nil) {
			return nil;
		}
		for (NSArray *keys in inner) {
			[parts addObject:[@[ relationship.name ] arrayByAddingObjectsFromArray:keys]];
		}
	}
	return parts;
}

- (NSArray<NSArray *> *)absorbedParts:(NSString *)base on:(ORMCDEntity *)entity
{
	NSMutableArray *parts = [NSMutableArray array];
	NSString *lead = [base stringByAppendingString:@"/"];
	for (ORMCDEntity *at = entity; at != nil; at = [self parentOf:at]) {
		for (ORMCDProperty *property in [at properties]) {
			if ([property.source hasPrefix:lead] && ![property.source hasSuffix:@".inverse"]) {
				[parts addObject:@[ [property.source substringFromIndex:[base length]], property ]];
			}
		}
	}
	return parts;
}

@end
