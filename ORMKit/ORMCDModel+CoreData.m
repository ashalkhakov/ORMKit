/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCDModel+CoreData.h"
#import <CoreData/CoreData.h>

static NSAttributeType
ORMAttributeTypeNamed(NSString *name)
{
	NSDictionary *types = @{ @"Integer 16": @(NSInteger16AttributeType), @"Integer 32": @(NSInteger32AttributeType),
	                         @"Integer 64": @(NSInteger64AttributeType), @"Decimal": @(NSDecimalAttributeType),
	                         @"Double": @(NSDoubleAttributeType), @"Float": @(NSFloatAttributeType),
	                         @"String": @(NSStringAttributeType), @"Boolean": @(NSBooleanAttributeType),
	                         @"Date": @(NSDateAttributeType), @"Binary": @(NSBinaryDataAttributeType),
	                         @"Transformable": @(NSTransformableAttributeType) };
	NSNumber *type = [types objectForKey:name ?: @""];
	return type != nil ? (NSAttributeType)[type unsignedIntegerValue] : NSStringAttributeType;
}

/* Whether the derivation is a plain key path, as the mapper writes them:
 * names joined by dots. */
static BOOL
ORMIsKeyPath(NSString *text)
{
	NSCharacterSet *name = [NSCharacterSet characterSetWithCharactersInString:
	                                           @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
	NSArray *keys = [text componentsSeparatedByString:@"."];
	for (NSString *key in keys) {
		if ([key length] == 0 || [[key stringByTrimmingCharactersInSet:name] length] > 0
		    || [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[key characterAtIndex:0]]) {
			return NO;
		}
	}
	return [keys count] > 0;
}

/* A derived attribute's expression: a key path as it is, anything else
 * (a model read back) parsed as a format with no arguments; nil where it
 * does not parse. */
static NSExpression *
ORMDerivationExpression(NSString *text)
{
	if (ORMIsKeyPath(text)) {
		return [NSExpression expressionForKeyPath:text];
	}
	NSExpression *expression = nil;
	@try {
		expression = [NSExpression expressionWithFormat:text argumentArray:@[]];
	} @catch (NSException *exception) {
		expression = nil;
	}
	return expression;
}

@implementation ORMCDModel (CoreData)

- (NSManagedObjectModel *)managedObjectModel
{
	NSMutableDictionary<NSString *, NSEntityDescription *> *entities = [NSMutableDictionary dictionary];
	for (ORMCDEntity *entity in self.entities) {
		NSEntityDescription *described = [[NSEntityDescription alloc] init];
		described.name = entity.name;
		described.managedObjectClassName = @"NSManagedObject";
		described.abstract = entity.isAbstract;
		described.userInfo = entity.userInfo ?: @{};
		[entities setObject:described forKey:entity.name];
	}
	/* Each relationship, then its inverse once both are there. */
	NSMutableDictionary<NSString *, NSRelationshipDescription *> *relationships = [NSMutableDictionary dictionary];
	for (ORMCDEntity *entity in self.entities) {
		NSMutableArray *properties = [NSMutableArray array];
		for (ORMCDAttribute *attribute in entity.attributes) {
			NSAttributeDescription *described = nil;
			NSExpression *derivation = attribute.derivation != nil ? ORMDerivationExpression(attribute.derivation) : nil;
			if (derivation != nil) {
				/* Core Data derives it, at save. A derivation that does
				 * not parse leaves it a plain attribute. */
				NSDerivedAttributeDescription *derived = [[NSDerivedAttributeDescription alloc] init];
				derived.derivationExpression = derivation;
				described = derived;
			} else {
				described = [[NSAttributeDescription alloc] init];
			}
			described.name = attribute.name;
			described.attributeType = ORMAttributeTypeNamed(attribute.attributeType);
			described.optional = attribute.optional;
			described.userInfo = attribute.userInfo ?: @{};
			[properties addObject:described];
		}
		for (ORMCDRelationship *relationship in entity.relationships) {
			NSEntityDescription *destination = [entities objectForKey:relationship.destination ?: @""];
			if (destination == nil) {
				continue;
			}
			NSRelationshipDescription *described = [[NSRelationshipDescription alloc] init];
			described.name = relationship.name;
			described.destinationEntity = destination;
			described.optional = relationship.optional;
			described.minCount = relationship.minCount;
			described.maxCount = relationship.toMany ? relationship.maxCount : 1;
			described.ordered = relationship.ordered;
			described.userInfo = relationship.userInfo ?: @{};
			[properties addObject:described];
			[relationships setObject:described forKey:[NSString stringWithFormat:@"%@.%@", entity.name, relationship.name]];
		}
		[[entities objectForKey:entity.name] setProperties:properties];
	}
	for (ORMCDEntity *entity in self.entities) {
		for (ORMCDRelationship *relationship in entity.relationships) {
			NSRelationshipDescription *described = [relationships objectForKey:[NSString stringWithFormat:@"%@.%@", entity.name,
			                                                                                     relationship.name]];
			NSRelationshipDescription *inverse = [relationship.inverseName length] > 0
				? [relationships objectForKey:[NSString stringWithFormat:@"%@.%@", relationship.destination, relationship.inverseName]]
				: nil;
			described.inverseRelationship = inverse;
		}
	}
	for (ORMCDEntity *entity in self.entities) {
		NSMutableArray *subentities = [NSMutableArray array];
		for (ORMCDEntity *sub in [self subentitiesOf:entity.name]) {
			[subentities addObject:[entities objectForKey:sub.name]];
		}
		if ([subentities count] > 0) {
			[[entities objectForKey:entity.name] setSubentities:subentities];
		}
	}
	NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];
	NSMutableArray *ordered = [NSMutableArray array];
	for (ORMCDEntity *entity in self.entities) {
		[ordered addObject:[entities objectForKey:entity.name]];
	}
	model.entities = ordered;
	return model;
}

@end
