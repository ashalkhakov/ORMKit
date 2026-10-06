/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMJoinedFacade.h"
#import "ORMCoreDataMapper.h"
#if __has_include(<ORMRuntime/ORMRuntime.h>)
#import <ORMRuntime/ORMRuntime.h>
#else
#import "ORMRuntime.h"
#endif

static NSString *
ORMQuoted(NSString *text)
{
	NSString *escaped = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
		stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
	return [NSString stringWithFormat:@"@\"%@\"", escaped];
}

/* The class an attribute's value is of. */
static NSString *
ORMClassOfAttribute(ORMCDAttribute *attribute)
{
	NSDictionary *classes = @{ @"String": @"NSString", @"Decimal": @"NSDecimalNumber", @"Date": @"NSDate",
		                       @"Binary": @"NSData", @"UUID": @"NSUUID", @"URI": @"NSURL" };
	NSString *type = attribute.attributeType ?: @"";
	if ([type hasPrefix:@"Integer"] || [type isEqualToString:@"Double"] || [type isEqualToString:@"Float"]
	    || [type isEqualToString:@"Boolean"]) {
		return @"NSNumber";
	}
	return [classes objectForKey:type];
}

/* A joined entity type's code: its class, its hub, its members (each
 * after the one it joins to) and its properties. */
@interface ORMJoinedTypeCode : NSObject
@property (nonatomic, strong) ORMObjectType *type;
@property (nonatomic, copy) NSString *className;
@property (nonatomic, strong) ORMCDEntity *hub;
/* @[ entity, via name, outer, @[ @[ theirs, ours ] ], held names ]. */
@property (nonatomic, copy) NSArray<NSArray *> *members;
/* @[ name, entity name, declared type ]. */
@property (nonatomic, copy) NSArray<NSArray *> *properties;
@end

@implementation ORMJoinedTypeCode
@end

@implementation ORMJoinedFacade
{
	ORMModel *_model;
	ORMCDModel *_coreData;
	NSString *_name;
	NSArray<ORMJoinedTypeCode *> *_types;
}

- (instancetype)initWithModel:(ORMModel *)model coreData:(ORMCDModel *)coreData name:(NSString *)name
{
	if ((self = [super init])) {
		_model = model;
		_coreData = coreData;
		_name = name;
		[self collect];
	}
	return self;
}

- (BOOL)isEmpty
{
	return [_types count] == 0;
}

- (void)collect
{
	NSMutableOrderedSet *typeIds = [NSMutableOrderedSet orderedSet];
	for (ORMCDEntity *entity in _coreData.entities) {
		NSString *joins = [entity.userInfo objectForKey:@"ormkit.joins"];
		if (joins != nil && [entity.userInfo objectForKey:@"ormkit.on"] != nil) {
			[typeIds addObject:joins];
		}
	}
	NSMutableSet *classes = [NSMutableSet set];
	for (ORMCDEntity *entity in _coreData.entities) {
		[classes addObject:[entity.representedClassName length] > 0 ? entity.representedClassName : entity.name];
	}
	NSMutableArray *types = [NSMutableArray array];
	for (NSString *typeId in typeIds) {
		ORMObjectType *type = [_model elementWithId:typeId];
		ORMCDEntity *hub = [_coreData entityWithSource:typeId];
		if (![type isKindOfClass:[ORMObjectType class]] || hub == nil) {
			continue;
		}
		ORMJoinedTypeCode *joined = [[ORMJoinedTypeCode alloc] init];
		joined.type = type;
		joined.hub = hub;
		NSString *name = [ORMCoreDataMapper entityNameFor:type.name];
		joined.className = [classes containsObject:name] ? [name stringByAppendingString:@"Joined"] : name;
		[classes addObject:joined.className];
		/* Each member after the one it joins to. */
		NSMutableArray *members = [NSMutableArray array];
		NSMutableSet *placed = [NSMutableSet setWithObject:hub.name];
		NSMutableArray *pending = [NSMutableArray array];
		for (ORMCDEntity *entity in _coreData.entities) {
			if ([[entity.userInfo objectForKey:@"ormkit.joins"] isEqualToString:typeId]
			    && [entity.userInfo objectForKey:@"ormkit.on"] != nil) {
				[pending addObject:entity];
			}
		}
		for (BOOL progress = YES; progress && [pending count] > 0;) {
			progress = NO;
			for (ORMCDEntity *entity in [pending copy]) {
				NSString *via = [entity.userInfo objectForKey:@"ormkit.via"];
				if (![placed containsObject:via]) {
					continue;
				}
				NSMutableArray *pairs = [NSMutableArray array];
				for (NSString *pair in [[entity.userInfo objectForKey:@"ormkit.on"] componentsSeparatedByString:@","]) {
					[pairs addObject:[pair componentsSeparatedByString:@" "]];
				}
				NSMutableArray *held = [NSMutableArray array];
				for (ORMCDProperty *property in [entity properties]) {
					if (![property.source hasPrefix:[entity.source stringByAppendingString:@"/"]]) {
						[held addObject:property.name];
					}
				}
				[members addObject:@[ entity, via, @([[entity.userInfo objectForKey:@"ormkit.outer"] isEqualToString:@"YES"]),
				                      pairs, held ]];
				[placed addObject:entity.name];
				[pending removeObject:entity];
				progress = YES;
			}
		}
		joined.members = members;
		/* The hub's properties, then each member's own. */
		NSMutableArray *properties = [NSMutableArray array];
		NSMutableSet *names = [NSMutableSet setWithArray:@[ @"object", @"delete", @"members", @"rowIn" ]];
		NSMutableArray *places = [NSMutableArray arrayWithObject:@[ hub, [hub properties] ]];
		for (NSArray *member in members) {
			ORMCDEntity *entity = [member firstObject];
			NSMutableArray *own = [NSMutableArray array];
			for (ORMCDProperty *property in [entity properties]) {
				if ([[member lastObject] containsObject:property.name]) {
					[own addObject:property];
				}
			}
			[places addObject:@[ entity, own ]];
		}
		for (NSArray *place in places) {
			ORMCDEntity *entity = [place firstObject];
			for (ORMCDProperty *property in [place lastObject]) {
				NSString *declared = nil;
				if ([property isKindOfClass:[ORMCDAttribute class]]) {
					NSString *class = ORMClassOfAttribute((ORMCDAttribute *)property);
					declared = class != nil ? [class stringByAppendingString:@" *"] : @"id";
				} else {
					declared = ((ORMCDRelationship *)property).toMany ? @"NSSet *" : @"NSManagedObject *";
				}
				NSString *name = property.name;
				if ([names containsObject:name]) {
					name = [name stringByAppendingString:entity.name];
				}
				[names addObject:name];
				[properties addObject:@[ name, property.name, entity.name, declared ]];
			}
		}
		joined.properties = properties;
		[types addObject:joined];
	}
	_types = types;
}

#pragma mark The code

- (NSString *)header
{
	NSMutableString *out = [NSMutableString string];
	for (ORMJoinedTypeCode *joined in _types) {
		NSMutableArray *kept = [NSMutableArray arrayWithObject:joined.hub.name];
		for (NSArray *member in joined.members) {
			[kept addObject:[(ORMCDEntity *)[member firstObject] name]];
		}
		[out appendFormat:@"\n/* %@, kept in %@ (docs/JOINED-ENTITIES.md). Its\n"
		                  @" * properties are read from and written to the entity that holds each. */\n"
		                  @"@interface %@ : ORMJoinedObject\n",
		                  [joined.type.name stringByReplacingOccurrencesOfString:@"*/" withString:@"* /"],
		                  [kept componentsJoinedByString:@", "], joined.className];
		for (NSArray *property in joined.properties) {
			NSString *declared = [property lastObject];
			[out appendFormat:@"@property (nonatomic, strong) %@%@%@;\n", declared,
			                  [declared hasSuffix:@"*"] ? @"" : @" ", [property firstObject]];
		}
		[out appendString:@"@end\n"];
	}
	return out;
}

- (NSString *)implementation
{
	NSMutableString *out = [NSMutableString string];
	for (ORMJoinedTypeCode *joined in _types) {
		[out appendFormat:@"\n@implementation %@\n\n", joined.className];
		NSMutableArray *names = [NSMutableArray array];
		for (NSArray *property in joined.properties) {
			[names addObject:[property firstObject]];
		}
		if ([names count] > 0) {
			[out appendFormat:@"@dynamic %@;\n\n", [names componentsJoinedByString:@", "]];
		}
		[out appendFormat:@"+ (NSString *)tablesName\n"
		                  @"{\n"
		                  @"\treturn %@;\n"
		                  @"}\n\n@end\n",
		                  ORMQuoted(_name)];
	}
	return out;
}

- (NSDictionary<NSString *, ORMJoinedType *> *)types
{
	NSMutableDictionary *types = [NSMutableDictionary dictionary];
	for (ORMJoinedTypeCode *joined in _types) {
		NSMutableArray *members = [NSMutableArray array];
		for (NSArray *member in joined.members) {
			[members addObject:@{ @"entity": [(ORMCDEntity *)[member firstObject] name], @"via": [member objectAtIndex:1],
				                  @"outer": [member objectAtIndex:2], @"on": [member objectAtIndex:3],
				                  @"holds": [member lastObject] }];
		}
		NSMutableDictionary *properties = [NSMutableDictionary dictionary];
		for (NSArray *property in joined.properties) {
			[properties setObject:@[ [property objectAtIndex:1], [property objectAtIndex:2] ] forKey:[property firstObject]];
		}
		[types setObject:[ORMJoinedType typeWithHub:joined.hub.name members:members properties:properties]
		          forKey:joined.className];
	}
	return types;
}

@end
