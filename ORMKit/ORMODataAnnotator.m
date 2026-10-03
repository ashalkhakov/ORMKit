/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMODataAnnotator.h"

/* What the mapper's notes are made with. */
@interface ORMMappingNote (Making)
+ (instancetype)noteWithKind:(ORMMappingNoteKind)kind text:(NSString *)text element:(NSString *)elementId;
@end

/* A number as the model wrote it: "0", "2.5". */
@interface ORMJSONNumber : NSObject
@property (nonatomic, copy) NSString *text;
@end

@implementation ORMJSONNumber
@end

/* JSON CSDL, written by hand so that it reads the same each time: keys
 * sorted, numbers as the model wrote them. A truth value is an NSNumber. */
static void
ORMAppendJSON(NSMutableString *out, id value)
{
	if ([value isKindOfClass:[ORMJSONNumber class]]) {
		[out appendString:((ORMJSONNumber *)value).text];
	} else if ([value isKindOfClass:[NSNumber class]]) {
		[out appendString:[value boolValue] ? @"true" : @"false"];
	} else if ([value isKindOfClass:[NSArray class]]) {
		[out appendString:@"["];
		BOOL first = YES;
		for (id item in value) {
			[out appendString:first ? @"" : @", "];
			ORMAppendJSON(out, item);
			first = NO;
		}
		[out appendString:@"]"];
	} else if ([value isKindOfClass:[NSDictionary class]]) {
		[out appendString:@"{"];
		BOOL first = YES;
		for (NSString *key in [[value allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			[out appendString:first ? @"" : @", "];
			ORMAppendJSON(out, key);
			[out appendString:@": "];
			ORMAppendJSON(out, [value objectForKey:key]);
			first = NO;
		}
		[out appendString:@"}"];
	} else {
		NSString *text = [value description];
		[out appendString:@"\""];
		for (NSUInteger i = 0; i < [text length]; i++) {
			unichar c = [text characterAtIndex:i];
			if (c == '"' || c == '\\') {
				[out appendFormat:@"\\%C", c];
			} else if (c < 0x20) {
				[out appendFormat:@"\\u%04x", (unsigned)c];
			} else {
				[out appendFormat:@"%C", c];
			}
		}
		[out appendString:@"\""];
	}
}

static NSDictionary *
ORMWithEntry(NSDictionary *info, NSString *key, NSString *value)
{
	NSMutableDictionary *copy = [info mutableCopy] ?: [NSMutableDictionary dictionary];
	[copy setObject:value forKey:key];
	return copy;
}

@implementation ORMODataAnnotator {
	ORMModel *_model;
	ORMCoreDataMapping *_mapping;
	NSMutableArray<ORMMappingNote *> *_notes;
}

- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	if ((self = [super init])) {
		_model = model;
		_mapping = mapping;
	}
	return self;
}

- (NSArray<ORMMappingNote *> *)annotate:(ORMCDModel *)coreData
{
	_notes = [NSMutableArray array];
	for (ORMCDEntity *entity in coreData.entities) {
		ORMObjectType *type = [self objectTypeOf:entity];
		if ([type.definitionText length] > 0) {
			entity.userInfo = ORMWithEntry(entity.userInfo, @"OData.description", type.definitionText);
		}
		for (ORMCDAttribute *attribute in entity.attributes) {
			[self annotateAttribute:attribute];
		}
		if ([entity.parentName length] == 0) {
			entity.userInfo = ORMWithEntry(entity.userInfo, @"OData.entitySet", [ORMCoreDataMapper pluralOf:entity.name]);
			[self keyEntity:entity];
		}
	}
	return _notes;
}

- (ORMObjectType *)objectTypeOf:(ORMCDEntity *)entity
{
	id element = entity.source != nil ? [_model elementWithId:entity.source] : nil;
	return [element isKindOfClass:[ORMObjectType class]] ? element : nil;
}

#pragma mark Keys

/* Every property the role maps to, absorbed parts included. */
- (NSArray<ORMCDProperty *> *)propertiesOf:(ORMRole *)role on:(ORMCDEntity *)entity
{
	NSString *lead = [role.identifier stringByAppendingString:@"/"];
	NSMutableArray *found = [NSMutableArray array];
	for (NSArray *properties in @[ entity.attributes, entity.relationships ]) {
		for (ORMCDProperty *property in properties) {
			if ([property.source isEqualToString:role.identifier] || [property.source hasPrefix:lead]) {
				[found addObject:property];
			}
		}
	}
	return found;
}

/* The attributes the entity's preferred identifier maps to; nil when a part
 * of it is a relationship, missing or optional, none of which a key can be. */
- (NSArray<ORMCDAttribute *> *)identifierOf:(ORMCDEntity *)entity
{
	if ([[entity.userInfo objectForKey:@"ormkit.valueEntity"] isEqualToString:@"YES"]) {
		NSString *source = [entity.source stringByAppendingString:@".value"];
		for (ORMCDAttribute *attribute in entity.attributes) {
			if ([attribute.source isEqualToString:source]) {
				return @[ attribute ];
			}
		}
		return nil;
	}
	ORMConstraint *identifier = [self objectTypeOf:entity].preferredIdentifier;
	if (identifier == nil) {
		return nil;
	}
	NSMutableArray *key = [NSMutableArray array];
	for (ORMRole *role in [identifier allRoles]) {
		NSArray *properties = [self propertiesOf:role on:entity];
		if ([properties count] == 0) {
			return nil;
		}
		for (ORMCDProperty *property in properties) {
			if (![property isKindOfClass:[ORMCDAttribute class]] || property.optional) {
				return nil;
			}
			[key addObject:property];
		}
	}
	return key;
}

- (NSString *)surrogateNameOn:(ORMCDEntity *)entity source:(NSString *)source
{
	NSMutableSet *taken = [NSMutableSet set];
	for (NSArray *properties in @[ entity.attributes, entity.relationships ]) {
		for (ORMCDProperty *property in properties) {
			[taken addObject:property.name];
		}
	}
	NSString *override = [_mapping.nameOverrides objectForKey:source];
	NSString *base = [override length] > 0 ? override : @"id";
	NSString *name = base;
	for (NSUInteger n = 2; [taken containsObject:name]; n++) {
		name = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)n];
	}
	return name;
}

- (void)keyEntity:(ORMCDEntity *)entity
{
	NSArray<ORMCDAttribute *> *key = [self identifierOf:entity];
	if (key != nil) {
		for (ORMCDAttribute *attribute in key) {
			attribute.userInfo = ORMWithEntry(attribute.userInfo, @"OData.key", @"YES");
		}
		return;
	}
	NSString *source = [entity.source stringByAppendingString:@".key"];
	ORMCDAttribute *surrogate = [[ORMCDAttribute alloc] init];
	surrogate.name = [self surrogateNameOn:entity source:source];
	surrogate.source = source;
	surrogate.attributeType = @"Integer 64";
	surrogate.optional = NO;
	surrogate.userInfo = ORMWithEntry(ORMWithEntry(surrogate.userInfo, @"OData.key", @"YES"), @"OData.computed", @"YES");
	[entity.attributes insertObject:surrogate atIndex:0];
	[_notes addObject:[ORMMappingNote noteWithKind:ORMMappingWarning
	                                          text:[NSString stringWithFormat:@"%@ is keyed in OData by %@, a number "
	                                                                          @"the service gives each new one: its "
	                                                                          @"identifier is not of attributes alone.",
	                                                                          entity.name, surrogate.name]
	                                       element:entity.source]];
}

#pragma mark Attributes

- (ORMValueConstraint *)valueConstraintOf:(ORMCDAttribute *)attribute objectType:(ORMObjectType **)typeOut
{
	NSString *source = attribute.source;
	if ([source hasSuffix:@".value"]) {
		ORMObjectType *type = [_model elementWithId:[source substringToIndex:[source length] - 6]];
		*typeOut = [type isKindOfClass:[ORMObjectType class]] ? type : nil;
		return (*typeOut).valueConstraint;
	}
	ORMRole *role = [_model elementWithId:[[source componentsSeparatedByString:@"/"] lastObject] ?: @""];
	if (![role isKindOfClass:[ORMRole class]]) {
		*typeOut = nil;
		return nil;
	}
	*typeOut = role.player;
	return role.valueConstraint ?: role.player.valueConstraint;
}

- (void)annotateAttribute:(ORMCDAttribute *)attribute
{
	if (attribute.source == nil) {
		return;
	}
	ORMObjectType *type = nil;
	ORMValueConstraint *constraint = [self valueConstraintOf:attribute objectType:&type];
	if (type.kind == ORMValueType && [type.definitionText length] > 0) {
		attribute.userInfo = ORMWithEntry(attribute.userInfo, @"OData.description", type.definitionText);
	}
	NSArray *ranges = constraint.ranges;
	NSString *kind = attribute.attributeType;
	if ([ranges count] == 0 || [kind isEqualToString:@"Boolean"] || [kind isEqualToString:@"Transformable"]) {
		return;
	}
	BOOL numeric = [kind hasPrefix:@"Integer"] || [kind isEqualToString:@"Decimal"]
		|| [kind isEqualToString:@"Double"] || [kind isEqualToString:@"Float"];
	id (^value)(NSString *) = ^id(NSString *text) {
		NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
		double number = 0;
		if (!numeric || ![scanner scanDouble:&number] || ![scanner isAtEnd]) {
			return text;
		}
		ORMJSONNumber *json = [[ORMJSONNumber alloc] init];
		json.text = text;
		return json;
	};
	NSMutableDictionary *annotations = [NSMutableDictionary dictionary];
	BOOL allSingle = YES;
	for (ORMValueRange *range in ranges) {
		allSingle = allSingle && [range.minValue isEqualToString:range.maxValue];
	}
	if (allSingle) {
		NSMutableArray *allowed = [NSMutableArray array];
		for (ORMValueRange *range in ranges) {
			[allowed addObject:@{ @"Value": value(range.minValue) }];
		}
		[annotations setObject:allowed forKey:@"Validation.AllowedValues"];
	} else if ([ranges count] == 1 && numeric) {
		/* Core Data holds the bounds; OData can also say they are open. */
		ORMValueRange *range = [ranges firstObject];
		if ([range.minValue length] > 0 && range.minInclusion == ORMRangeOpen) {
			[annotations setObject:value(range.minValue) forKey:@"Validation.Minimum"];
			[annotations setObject:@YES forKey:@"Validation.Minimum@Validation.Exclusive"];
		}
		if ([range.maxValue length] > 0 && range.maxInclusion == ORMRangeOpen) {
			[annotations setObject:value(range.maxValue) forKey:@"Validation.Maximum"];
			[annotations setObject:@YES forKey:@"Validation.Maximum@Validation.Exclusive"];
		}
	}
	if ([annotations count] > 0) {
		NSMutableString *json = [NSMutableString string];
		ORMAppendJSON(json, annotations);
		attribute.userInfo = ORMWithEntry(attribute.userInfo, @"OData.annotations", json);
	}
}

@end
