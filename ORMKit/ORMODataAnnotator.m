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
		/* Its type's name, as the service writes it: what a cast to a
		 * subtype names, known without $metadata. */
		entity.userInfo = ORMWithEntry(entity.userInfo, @"OData.type",
		                               [NSString stringWithFormat:@"%@.%@", _mapping.odataNamespace ?: @"Default", entity.name]);
		for (ORMCDAttribute *attribute in entity.attributes) {
			[self annotateAttribute:attribute];
		}
		if ([entity.parentName length] == 0) {
			entity.userInfo = ORMWithEntry(entity.userInfo, @"OData.entitySet", [ORMCoreDataMapper pluralOf:entity.name]);
			[self keyEntity:entity];
		}
	}
	[self syncEntitiesOf:coreData];
	return _notes;
}

#pragma mark Offline

/* Each root entity's way between a device and the service, as ODataSync
 * reads it; a subentity goes its root's way. One that a device changes
 * (up, both) keeps its key after deletion, so that the deletion can be
 * sent by it, and is given what ODataSync keeps of each object's history:
 * its version vector and its last change's stamp, bookkeeping as a
 * surrogate is, which the conceptual model says nothing of. */
- (void)syncEntitiesOf:(ORMCDModel *)coreData
{
	if (_mapping.syncDirection == ORMSyncNone && [_mapping.syncOverrides count] == 0) {
		return;
	}
	NSMutableDictionary<NSString *, NSMutableArray *> *ways = [NSMutableDictionary dictionary];
	for (ORMCDEntity *entity in coreData.entities) {
		if ([entity.parentName length] > 0) {
			continue;
		}
		ORMSyncDirection direction = [_mapping syncDirectionOf:entity.source];
		NSString *way = [ORMCoreDataMapping nameOfSyncDirection:direction];
		if (way == nil) {
			continue;
		}
		NSMutableArray *named = [ways objectForKey:way] ?: [NSMutableArray array];
		[named addObject:entity.name];
		[ways setObject:named forKey:way];
		entity.userInfo = ORMWithEntry(entity.userInfo, @"ODataSync.direction", way);
		NSString *rule = [_mapping syncConflictsOf:entity.source];
		if (direction == ORMSyncBoth && [rule length] > 0) {
			entity.userInfo = ORMWithEntry(entity.userInfo, @"ODataSync.conflicts", rule);
		}
		if (direction == ORMSyncDown) {
			continue;
		}
		for (ORMCDAttribute *attribute in entity.attributes) {
			if ([[attribute.userInfo objectForKey:@"OData.key"] isEqualToString:@"YES"]) {
				attribute.extraAttributes = ORMWithEntry(attribute.extraAttributes, @"preserveAfterDeletion", @"YES");
			}
		}
		ORMCDAttribute *versions = [self bookkeeping:@"syncVersions" on:entity];
		ORMCDAttribute *modified = [self bookkeeping:@"syncModified" on:entity];
		entity.userInfo = ORMWithEntry(ORMWithEntry(entity.userInfo, @"ODataSync.versions", versions.name),
		                               @"ODataSync.modified", modified.name);
	}
	NSMutableArray *said = [NSMutableArray array];
	for (NSString *way in @[ @"down", @"up", @"both" ]) {
		NSArray *named = [[ways objectForKey:way] sortedArrayUsingSelector:@selector(compare:)];
		if ([named count] > 0) {
			[said addObject:[NSString stringWithFormat:@"%@: %@", way, [named componentsJoinedByString:@", "]]];
		}
	}
	if ([said count] > 0) {
		[_notes addObject:[ORMMappingNote noteWithKind:ORMMappingWarning
		                                          text:[NSString stringWithFormat:@"Synced offline (ODataSync), %@. What a "
		                                                                          @"device changes keeps its version and "
		                                                                          @"its last change's stamp, its "
		                                                                          @"bookkeeping (syncVersions, syncModified).",
		                                                                          [said componentsJoinedByString:@"; "]]
		                                       element:_mapping.identifier]];
	}
}

/* An optional String of the entity's, ODataSync's to write: named as the
 * mapping overrides it (by <entity's source>.<name>), else as given, a
 * number added should the entity have a property of the name. */
- (ORMCDAttribute *)bookkeeping:(NSString *)name on:(ORMCDEntity *)entity
{
	NSString *source = [NSString stringWithFormat:@"%@.%@", entity.source ?: entity.name, name];
	NSMutableSet *taken = [NSMutableSet set];
	for (NSArray *properties in @[ entity.attributes, entity.relationships ]) {
		for (ORMCDProperty *property in properties) {
			[taken addObject:property.name];
		}
	}
	NSString *override = [_mapping.nameOverrides objectForKey:source];
	NSString *base = [ORMCoreDataMapper isCoreDataName:override] ? override : name;
	NSString *chosen = base;
	for (NSUInteger n = 2; [taken containsObject:chosen]; n++) {
		chosen = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)n];
	}
	ORMCDAttribute *attribute = [[ORMCDAttribute alloc] init];
	attribute.name = chosen;
	attribute.source = source;
	attribute.attributeType = @"String";
	attribute.optional = YES;
	attribute.userInfo = ORMWithEntry(attribute.userInfo, @"ormkit.bookkeeping", @"YES");
	[entity.attributes addObject:attribute];
	return attribute;
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
	/* A joined entity type's member: by what it correlates by, its own
	 * copies of the type's identifying values (docs/JOINED-ENTITIES.md). */
	if ([entity.userInfo objectForKey:@"ormkit.joins"] != nil) {
		NSMutableArray *key = [NSMutableArray array];
		for (ORMCDAttribute *attribute in entity.attributes) {
			if ([attribute.source hasPrefix:[entity.source stringByAppendingString:@"/"]] && !attribute.optional) {
				[key addObject:attribute];
			}
		}
		if ([key count] > 0) {
			return key;
		}
		/* Its values optional: a uniqueness of what it requires. */
		for (NSArray<NSString *> *names in entity.uniquenessConstraints) {
			NSMutableArray *unique = [NSMutableArray array];
			for (NSString *name in names) {
				ORMCDAttribute *attribute = [entity attributeNamed:name];
				if (attribute != nil && !attribute.optional) {
					[unique addObject:attribute];
				}
			}
			if ([unique count] > 0 && [unique count] == [names count]) {
				return unique;
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
	NSString *base = [ORMCoreDataMapper isCoreDataName:override] ? override : @"id";
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
	surrogate.attributeType = @"UUID";
	surrogate.optional = NO;
	surrogate.userInfo = ORMWithEntry(ORMWithEntry(surrogate.userInfo, @"OData.key", @"YES"), @"ormkit.surrogate", @"YES");
	[entity.attributes insertObject:surrogate atIndex:0];
	[_notes addObject:[ORMMappingNote noteWithKind:ORMMappingWarning
	                                          text:[NSString stringWithFormat:@"%@ is keyed in OData by %@, a UUID "
	                                                                          @"whoever makes each new one gives it: its "
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
		/* Written as JSON writes a number: ".5", "5." and "+1" are not. */
		NSRegularExpression *grammar = [NSRegularExpression
			regularExpressionWithPattern:@"^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$" options:0 error:NULL];
		NSString *written = text;
		if ([grammar numberOfMatchesInString:written options:0 range:NSMakeRange(0, [written length])] == 0) {
			written = [[NSDecimalNumber decimalNumberWithString:text] stringValue];
		}
		if ([grammar numberOfMatchesInString:written options:0 range:NSMakeRange(0, [written length])] == 0) {
			return text;
		}
		ORMJSONNumber *json = [[ORMJSONNumber alloc] init];
		json.text = written;
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
