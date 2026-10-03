/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCDModel.h"

NSString * const ORMCDSourceKey = @"ormkit.source";

static NSString *
ORMCDAttr(NSXMLElement *element, NSString *name)
{
	return [[element attributeForName:name] stringValue];
}

static BOOL
ORMCDYes(NSXMLElement *element, NSString *name)
{
	return [ORMCDAttr(element, name) isEqualToString:@"YES"];
}

/* The element's attributes not named, as a dictionary. */
static NSDictionary *
ORMCDExtras(NSXMLElement *element, NSArray *known)
{
	NSMutableDictionary *extras = [NSMutableDictionary dictionary];
	for (NSXMLNode *attribute in [element attributes]) {
		if (![known containsObject:[attribute name]]) {
			[extras setObject:[attribute stringValue] ?: @"" forKey:[attribute name]];
		}
	}
	return extras;
}

static NSDictionary *
ORMCDUserInfo(NSXMLElement *element)
{
	NSMutableDictionary *info = [NSMutableDictionary dictionary];
	for (NSXMLElement *userInfo in [element elementsForName:@"userInfo"]) {
		for (NSXMLElement *entry in [userInfo elementsForName:@"entry"]) {
			NSString *key = ORMCDAttr(entry, @"key");
			if (key != nil) {
				[info setObject:ORMCDAttr(entry, @"value") ?: @"" forKey:key];
			}
		}
	}
	return info;
}

#pragma mark Properties

@implementation ORMCDProperty

- (instancetype)init
{
	if ((self = [super init])) {
		_userInfo = @{};
		_extraAttributes = @{};
		_optional = YES;
	}
	return self;
}

- (NSString *)source
{
	return [self.userInfo objectForKey:ORMCDSourceKey];
}

- (void)setSource:(NSString *)source
{
	NSMutableDictionary *info = [self.userInfo mutableCopy];
	if (source != nil) {
		[info setObject:source forKey:ORMCDSourceKey];
	} else {
		[info removeObjectForKey:ORMCDSourceKey];
	}
	self.userInfo = info;
}

- (id)copyWithZone:(NSZone *)zone
{
	ORMCDProperty *copy = [[[self class] allocWithZone:zone] init];
	copy.name = self.name;
	copy.optional = self.optional;
	copy.userInfo = self.userInfo;
	copy.extraAttributes = self.extraAttributes;
	return copy;
}

@end

@implementation ORMCDAttribute

- (id)copyWithZone:(NSZone *)zone
{
	ORMCDAttribute *copy = [super copyWithZone:zone];
	copy.attributeType = self.attributeType;
	copy.defaultValue = self.defaultValue;
	copy.minValue = self.minValue;
	copy.maxValue = self.maxValue;
	copy.regularExpression = self.regularExpression;
	copy.allowsExternalStorage = self.allowsExternalStorage;
	return copy;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@: %@%@", self.name, self.attributeType, self.optional ? @"?" : @""];
}

@end

@implementation ORMCDRelationship

- (instancetype)init
{
	if ((self = [super init])) {
		_deletionRule = @"Nullify";
	}
	return self;
}

- (id)copyWithZone:(NSZone *)zone
{
	ORMCDRelationship *copy = [super copyWithZone:zone];
	copy.destination = self.destination;
	copy.inverseName = self.inverseName;
	copy.toMany = self.toMany;
	copy.ordered = self.ordered;
	copy.minCount = self.minCount;
	copy.maxCount = self.maxCount;
	copy.deletionRule = self.deletionRule;
	return copy;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@: %@%@%@", self.name, self.toMany ? @"[" : @"", self.destination,
	        self.toMany ? @"]" : (self.optional ? @"?" : @"")];
}

@end

#pragma mark Entities

@implementation ORMCDEntity

- (instancetype)init
{
	if ((self = [super init])) {
		_attributes = [NSMutableArray array];
		_relationships = [NSMutableArray array];
		_uniquenessConstraints = [NSMutableArray array];
		_userInfo = @{};
		_extraAttributes = @{};
		_extraElements = @[];
	}
	return self;
}

- (NSString *)source
{
	return [self.userInfo objectForKey:ORMCDSourceKey];
}

- (void)setSource:(NSString *)source
{
	NSMutableDictionary *info = [self.userInfo mutableCopy];
	if (source != nil) {
		[info setObject:source forKey:ORMCDSourceKey];
	} else {
		[info removeObjectForKey:ORMCDSourceKey];
	}
	self.userInfo = info;
}

- (id)copyWithZone:(NSZone *)zone
{
	ORMCDEntity *copy = [[[self class] allocWithZone:zone] init];
	copy.name = self.name;
	copy.parentName = self.parentName;
	copy.isAbstract = self.isAbstract;
	copy.representedClassName = self.representedClassName;
	copy.codeGenerationType = self.codeGenerationType;
	for (ORMCDAttribute *attribute in self.attributes) {
		[copy.attributes addObject:[attribute copy]];
	}
	for (ORMCDRelationship *relationship in self.relationships) {
		[copy.relationships addObject:[relationship copy]];
	}
	[copy.uniquenessConstraints addObjectsFromArray:self.uniquenessConstraints];
	copy.userInfo = self.userInfo;
	copy.extraAttributes = self.extraAttributes;
	NSMutableArray *extras = [NSMutableArray array];
	for (NSXMLElement *element in self.extraElements) {
		[extras addObject:[element copy]];
	}
	copy.extraElements = extras;
	return copy;
}

- (ORMCDAttribute *)attributeNamed:(NSString *)name
{
	for (ORMCDAttribute *attribute in self.attributes) {
		if ([attribute.name isEqualToString:name]) {
			return attribute;
		}
	}
	return nil;
}

- (ORMCDRelationship *)relationshipNamed:(NSString *)name
{
	for (ORMCDRelationship *relationship in self.relationships) {
		if ([relationship.name isEqualToString:name]) {
			return relationship;
		}
	}
	return nil;
}

- (ORMCDProperty *)propertyNamed:(NSString *)name
{
	return [self attributeNamed:name] ?: (ORMCDProperty *)[self relationshipNamed:name];
}

- (NSArray<ORMCDProperty *> *)properties
{
	NSSortDescriptor *byName = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
	NSMutableArray *properties = [[self.attributes sortedArrayUsingDescriptors:@[ byName ]] mutableCopy];
	[properties addObjectsFromArray:[self.relationships sortedArrayUsingDescriptors:@[ byName ]]];
	return properties;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@%@ %@", self.name,
	        self.parentName ? [@" : " stringByAppendingString:self.parentName] : @"", [self properties]];
}

@end

#pragma mark The model

@implementation ORMCDModel

+ (instancetype)model
{
	ORMCDModel *model = [[self alloc] init];
	model.entities = [NSMutableArray array];
	model.positions = [NSMutableDictionary dictionary];
	model.modelAttributes = @{};
	model.extraElements = @[];
	return model;
}

- (id)copyWithZone:(NSZone *)zone
{
	ORMCDModel *copy = [ORMCDModel model];
	for (ORMCDEntity *entity in self.entities) {
		[copy.entities addObject:[entity copy]];
	}
	[copy.positions addEntriesFromDictionary:self.positions];
	copy.modelAttributes = self.modelAttributes;
	NSMutableArray *extras = [NSMutableArray array];
	for (NSXMLElement *element in self.extraElements) {
		[extras addObject:[element copy]];
	}
	copy.extraElements = extras;
	return copy;
}

#pragma mark Reading

+ (ORMCDAttribute *)readAttribute:(NSXMLElement *)element
{
	ORMCDAttribute *attribute = [[ORMCDAttribute alloc] init];
	attribute.name = ORMCDAttr(element, @"name");
	attribute.optional = ORMCDYes(element, @"optional");
	attribute.attributeType = ORMCDAttr(element, @"attributeType") ?: @"Undefined";
	attribute.defaultValue = ORMCDAttr(element, @"defaultValueString");
	attribute.minValue = ORMCDAttr(element, @"minValueString");
	attribute.maxValue = ORMCDAttr(element, @"maxValueString");
	attribute.regularExpression = ORMCDAttr(element, @"regularExpressionString");
	attribute.allowsExternalStorage = ORMCDYes(element, @"allowsExternalBinaryDataStorage");
	attribute.userInfo = ORMCDUserInfo(element);
	attribute.extraAttributes = ORMCDExtras(element, @[ @"name", @"optional", @"attributeType", @"defaultValueString",
	                                                    @"minValueString", @"maxValueString",
	                                                    @"regularExpressionString",
	                                                    @"allowsExternalBinaryDataStorage" ]);
	return attribute;
}

+ (ORMCDRelationship *)readRelationship:(NSXMLElement *)element
{
	ORMCDRelationship *relationship = [[ORMCDRelationship alloc] init];
	relationship.name = ORMCDAttr(element, @"name");
	relationship.optional = ORMCDYes(element, @"optional");
	relationship.toMany = ORMCDYes(element, @"toMany");
	relationship.ordered = ORMCDYes(element, @"ordered");
	relationship.minCount = (NSUInteger)MAX(0, [ORMCDAttr(element, @"minCount") integerValue]);
	relationship.maxCount = (NSUInteger)MAX(0, [ORMCDAttr(element, @"maxCount") integerValue]);
	relationship.deletionRule = ORMCDAttr(element, @"deletionRule") ?: @"Nullify";
	relationship.destination = ORMCDAttr(element, @"destinationEntity");
	relationship.inverseName = ORMCDAttr(element, @"inverseName");
	relationship.userInfo = ORMCDUserInfo(element);
	relationship.extraAttributes = ORMCDExtras(element, @[ @"name", @"optional", @"toMany", @"ordered", @"minCount",
	                                                       @"maxCount", @"deletionRule", @"destinationEntity",
	                                                       @"inverseName", @"inverseEntity" ]);
	return relationship;
}

+ (ORMCDEntity *)readEntity:(NSXMLElement *)element
{
	ORMCDEntity *entity = [[ORMCDEntity alloc] init];
	entity.name = ORMCDAttr(element, @"name");
	entity.parentName = ORMCDAttr(element, @"parentEntity");
	entity.isAbstract = ORMCDYes(element, @"isAbstract");
	entity.representedClassName = ORMCDAttr(element, @"representedClassName");
	entity.codeGenerationType = ORMCDAttr(element, @"codeGenerationType");
	entity.extraAttributes = ORMCDExtras(element, @[ @"name", @"parentEntity", @"isAbstract", @"representedClassName",
	                                                 @"codeGenerationType" ]);
	entity.userInfo = ORMCDUserInfo(element);
	NSMutableArray *extras = [NSMutableArray array];
	for (NSXMLNode *node in [element children]) {
		if ([node kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *child = (NSXMLElement *)node;
		NSString *name = [child name];
		if ([name isEqualToString:@"attribute"]) {
			[entity.attributes addObject:[self readAttribute:child]];
		} else if ([name isEqualToString:@"relationship"]) {
			[entity.relationships addObject:[self readRelationship:child]];
		} else if ([name isEqualToString:@"uniquenessConstraints"]) {
			for (NSXMLElement *constraint in [child elementsForName:@"uniquenessConstraint"]) {
				NSMutableArray *names = [NSMutableArray array];
				for (NSXMLElement *part in [constraint elementsForName:@"constraint"]) {
					[names addObject:ORMCDAttr(part, @"value") ?: @""];
				}
				[entity.uniquenessConstraints addObject:names];
			}
		} else if (![name isEqualToString:@"userInfo"]) {
			[extras addObject:[child copy]];
		}
	}
	entity.extraElements = extras;
	return entity;
}

+ (instancetype)modelWithContentsXML:(NSData *)data reason:(NSString **)reason
{
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:0 error:&error];
	NSXMLElement *root = [document rootElement];
	if (root == nil || ![[root name] isEqualToString:@"model"]) {
		if (reason != NULL) {
			*reason = root == nil ? ([error localizedDescription] ?: @"The contents are not XML.")
			                      : @"The contents are not a Core Data model.";
		}
		return nil;
	}
	ORMCDModel *model = [self model];
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
	for (NSXMLNode *attribute in [root attributes]) {
		[attributes setObject:[attribute stringValue] ?: @"" forKey:[attribute name]];
	}
	model.modelAttributes = attributes;
	NSMutableArray *extras = [NSMutableArray array];
	for (NSXMLNode *node in [root children]) {
		if ([node kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *child = (NSXMLElement *)node;
		if ([[child name] isEqualToString:@"entity"]) {
			[model.entities addObject:[self readEntity:child]];
		} else if ([[child name] isEqualToString:@"elements"]) {
			for (NSXMLElement *element in [child elementsForName:@"element"]) {
				NSRect rect = NSMakeRect([ORMCDAttr(element, @"positionX") doubleValue],
				                         [ORMCDAttr(element, @"positionY") doubleValue],
				                         [ORMCDAttr(element, @"width") doubleValue],
				                         [ORMCDAttr(element, @"height") doubleValue]);
				NSString *name = ORMCDAttr(element, @"name");
				if (name != nil) {
					[model.positions setObject:[NSValue valueWithRect:rect] forKey:name];
				}
			}
		} else {
			[extras addObject:[child copy]];
		}
	}
	model.extraElements = extras;
	return model;
}

/* The version a package says is current, or its only one. */
+ (NSString *)currentVersionIn:(NSString *)package
{
	NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[package stringByAppendingPathComponent:
	                                                                          @".xccurrentversion"]];
	NSString *current = [info objectForKey:@"_XCCurrentVersionName"];
	if (current != nil) {
		return current;
	}
	for (NSString *name in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:package error:NULL]
	                           sortedArrayUsingSelector:@selector(compare:)]) {
		if ([[name pathExtension] isEqualToString:@"xcdatamodel"]) {
			return name;
		}
	}
	return nil;
}

+ (instancetype)modelAtPath:(NSString *)path reason:(NSString **)reason
{
	NSString *version = path;
	if ([[path pathExtension] isEqualToString:@"xcdatamodeld"]) {
		NSString *current = [self currentVersionIn:path];
		if (current == nil) {
			if (reason != NULL) {
				*reason = [NSString stringWithFormat:@"%@ has no model version.", [path lastPathComponent]];
			}
			return nil;
		}
		version = [path stringByAppendingPathComponent:current];
	}
	NSData *data = [NSData dataWithContentsOfFile:[version stringByAppendingPathComponent:@"contents"]];
	if (data == nil) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"%@ cannot be read.", [path lastPathComponent]];
		}
		return nil;
	}
	return [self modelWithContentsXML:data reason:reason];
}

#pragma mark Looking up

- (ORMCDEntity *)entityNamed:(NSString *)name
{
	for (ORMCDEntity *entity in self.entities) {
		if ([entity.name isEqualToString:name]) {
			return entity;
		}
	}
	return nil;
}

- (ORMCDEntity *)entityWithSource:(NSString *)source
{
	for (ORMCDEntity *entity in self.entities) {
		if ([entity.source isEqualToString:source]) {
			return entity;
		}
	}
	return nil;
}

- (NSArray<ORMCDEntity *> *)subentitiesOf:(NSString *)name
{
	NSMutableArray *subentities = [NSMutableArray array];
	for (ORMCDEntity *entity in self.entities) {
		if ([entity.parentName isEqualToString:name]) {
			[subentities addObject:entity];
		}
	}
	return subentities;
}

#pragma mark Writing

static void
ORMCDEscape(NSMutableString *out, NSString *text)
{
	NSString *escaped = [text stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
	escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
	escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
	escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
	[out appendString:escaped];
}

static void
ORMCDPut(NSMutableString *out, NSString *name, NSString *value)
{
	if (value == nil) {
		return;
	}
	[out appendFormat:@" %@=\"", name];
	ORMCDEscape(out, value);
	[out appendString:@"\""];
}

static void
ORMCDPutExtras(NSMutableString *out, NSDictionary *extras)
{
	for (NSString *name in [[extras allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		ORMCDPut(out, name, [extras objectForKey:name]);
	}
}

static void
ORMCDWriteUserInfo(NSMutableString *out, NSDictionary *info, NSString *indent)
{
	if ([info count] == 0) {
		return;
	}
	[out appendFormat:@"%@<userInfo>\n", indent];
	for (NSString *key in [[info allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		[out appendFormat:@"%@    <entry", indent];
		ORMCDPut(out, @"key", key);
		ORMCDPut(out, @"value", [info objectForKey:key]);
		[out appendString:@"/>\n"];
	}
	[out appendFormat:@"%@</userInfo>\n", indent];
}

/* Whether Xcode would give the type a scalar accessor by default. */
static BOOL
ORMCDIsScalar(NSString *type)
{
	return [type hasPrefix:@"Integer"] || [type isEqualToString:@"Double"] || [type isEqualToString:@"Float"]
		|| [type isEqualToString:@"Boolean"];
}

- (void)writeAttribute:(ORMCDAttribute *)attribute to:(NSMutableString *)out
{
	[out appendString:@"        <attribute"];
	ORMCDPut(out, @"name", attribute.name);
	ORMCDPut(out, @"optional", attribute.optional ? @"YES" : nil);
	ORMCDPut(out, @"attributeType", attribute.attributeType);
	ORMCDPut(out, @"minValueString", attribute.minValue);
	ORMCDPut(out, @"maxValueString", attribute.maxValue);
	ORMCDPut(out, @"defaultValueString", attribute.defaultValue);
	ORMCDPut(out, @"regularExpressionString", attribute.regularExpression);
	ORMCDPut(out, @"allowsExternalBinaryDataStorage", attribute.allowsExternalStorage ? @"YES" : nil);
	NSMutableDictionary *extras = [attribute.extraAttributes mutableCopy];
	if ([extras objectForKey:@"usesScalarValueType"] == nil
	    && (ORMCDIsScalar(attribute.attributeType) || [attribute.attributeType isEqualToString:@"Date"]
	        || [attribute.attributeType isEqualToString:@"Decimal"] || [attribute.attributeType isEqualToString:@"UUID"])) {
		[extras setObject:ORMCDIsScalar(attribute.attributeType) ? @"YES" : @"NO" forKey:@"usesScalarValueType"];
	}
	ORMCDPutExtras(out, extras);
	if ([attribute.userInfo count] == 0) {
		[out appendString:@"/>\n"];
		return;
	}
	[out appendString:@">\n"];
	ORMCDWriteUserInfo(out, attribute.userInfo, @"            ");
	[out appendString:@"        </attribute>\n"];
}

- (void)writeRelationship:(ORMCDRelationship *)relationship of:(ORMCDEntity *)entity to:(NSMutableString *)out
{
	[out appendString:@"        <relationship"];
	ORMCDPut(out, @"name", relationship.name);
	ORMCDPut(out, @"optional", relationship.optional ? @"YES" : nil);
	ORMCDPut(out, @"toMany", relationship.toMany ? @"YES" : nil);
	ORMCDPut(out, @"ordered", relationship.ordered ? @"YES" : nil);
	NSUInteger maxCount = relationship.toMany ? relationship.maxCount : 1;
	ORMCDPut(out, @"minCount", relationship.minCount > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)relationship.minCount]
	                                                    : nil);
	ORMCDPut(out, @"maxCount", maxCount > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)maxCount] : nil);
	ORMCDPut(out, @"deletionRule", relationship.deletionRule ?: @"Nullify");
	ORMCDPut(out, @"destinationEntity", relationship.destination);
	ORMCDPut(out, @"inverseName", relationship.inverseName);
	ORMCDPut(out, @"inverseEntity", relationship.inverseName != nil ? relationship.destination : nil);
	ORMCDPutExtras(out, relationship.extraAttributes);
	if ([relationship.userInfo count] == 0) {
		[out appendString:@"/>\n"];
		return;
	}
	[out appendString:@">\n"];
	ORMCDWriteUserInfo(out, relationship.userInfo, @"            ");
	[out appendString:@"        </relationship>\n"];
}

- (NSData *)contentsXML
{
	NSMutableString *out = [NSMutableString stringWithString:@"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"];
	NSMutableDictionary *modelAttributes = [@{ @"type": @"com.apple.IDECoreDataModeler.DataModel",
	                                           @"documentVersion": @"1.0",
	                                           @"minimumToolsVersion": @"Automatic",
	                                           @"sourceLanguage": @"Objective-C",
	                                           @"userDefinedModelVersionIdentifier": @"" } mutableCopy];
	[modelAttributes addEntriesFromDictionary:self.modelAttributes];
	[out appendString:@"<model"];
	/* Xcode's order: type and documentVersion first. */
	NSArray *first = @[ @"type", @"documentVersion", @"lastSavedToolsVersion", @"systemVersion",
	                    @"minimumToolsVersion", @"sourceLanguage", @"userDefinedModelVersionIdentifier" ];
	for (NSString *name in first) {
		ORMCDPut(out, name, [modelAttributes objectForKey:name]);
		[modelAttributes removeObjectForKey:name];
	}
	ORMCDPutExtras(out, modelAttributes);
	[out appendString:@">\n"];
	NSSortDescriptor *byName = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
	for (ORMCDEntity *entity in [self.entities sortedArrayUsingDescriptors:@[ byName ]]) {
		[out appendString:@"    <entity"];
		ORMCDPut(out, @"name", entity.name);
		ORMCDPut(out, @"representedClassName", entity.representedClassName ?: entity.name);
		ORMCDPut(out, @"parentEntity", entity.parentName);
		ORMCDPut(out, @"isAbstract", entity.isAbstract ? @"YES" : nil);
		NSMutableDictionary *extras = [entity.extraAttributes mutableCopy];
		if ([extras objectForKey:@"syncable"] == nil) {
			[extras setObject:@"YES" forKey:@"syncable"];
		}
		ORMCDPutExtras(out, extras);
		ORMCDPut(out, @"codeGenerationType", entity.codeGenerationType);
		[out appendString:@">\n"];
		for (ORMCDAttribute *attribute in [entity.attributes sortedArrayUsingDescriptors:@[ byName ]]) {
			[self writeAttribute:attribute to:out];
		}
		for (ORMCDRelationship *relationship in [entity.relationships sortedArrayUsingDescriptors:@[ byName ]]) {
			[self writeRelationship:relationship of:entity to:out];
		}
		if ([entity.uniquenessConstraints count] > 0) {
			[out appendString:@"        <uniquenessConstraints>\n"];
			for (NSArray *names in entity.uniquenessConstraints) {
				[out appendString:@"            <uniquenessConstraint>\n"];
				for (NSString *name in names) {
					[out appendString:@"                <constraint"];
					ORMCDPut(out, @"value", name);
					[out appendString:@"/>\n"];
				}
				[out appendString:@"            </uniquenessConstraint>\n"];
			}
			[out appendString:@"        </uniquenessConstraints>\n"];
		}
		for (NSXMLElement *extra in entity.extraElements) {
			[out appendFormat:@"        %@\n", [extra XMLString]];
		}
		ORMCDWriteUserInfo(out, entity.userInfo, @"        ");
		[out appendString:@"    </entity>\n"];
	}
	for (NSXMLElement *extra in self.extraElements) {
		[out appendFormat:@"    %@\n", [extra XMLString]];
	}
	if ([self.positions count] > 0) {
		[out appendString:@"    <elements>\n"];
		for (NSString *name in [[self.positions allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			if ([self entityNamed:name] == nil) {
				continue;
			}
			NSRect rect = [[self.positions objectForKey:name] rectValue];
			[out appendString:@"        <element"];
			ORMCDPut(out, @"name", name);
			ORMCDPut(out, @"positionX", [NSString stringWithFormat:@"%g", NSMinX(rect)]);
			ORMCDPut(out, @"positionY", [NSString stringWithFormat:@"%g", NSMinY(rect)]);
			ORMCDPut(out, @"width", [NSString stringWithFormat:@"%g", NSWidth(rect)]);
			ORMCDPut(out, @"height", [NSString stringWithFormat:@"%g", NSHeight(rect)]);
			[out appendString:@"/>\n"];
		}
		[out appendString:@"    </elements>\n"];
	}
	[out appendString:@"</model>"];
	return [out dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)writeToPackage:(NSString *)path error:(NSError **)error
{
	NSFileManager *files = [NSFileManager defaultManager];
	if (![files createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error]) {
		return NO;
	}
	NSString *version = [ORMCDModel currentVersionIn:path];
	if (version == nil) {
		version = [[[path lastPathComponent] stringByDeletingPathExtension] stringByAppendingPathExtension:@"xcdatamodel"];
		NSDictionary *info = @{ @"_XCCurrentVersionName": version };
		NSData *plist = [NSPropertyListSerialization dataWithPropertyList:info format:NSPropertyListXMLFormat_v1_0
		                                                          options:0 error:error];
		if (plist == nil || ![plist writeToFile:[path stringByAppendingPathComponent:@".xccurrentversion"]
		                                atomically:YES]) {
			return NO;
		}
	}
	NSString *directory = [path stringByAppendingPathComponent:version];
	if (![files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
		return NO;
	}
	return [[self contentsXML] writeToFile:[directory stringByAppendingPathComponent:@"contents"]
	                               options:NSDataWritingAtomic error:error];
}

@end
