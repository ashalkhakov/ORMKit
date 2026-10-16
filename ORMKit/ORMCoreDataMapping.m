/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataMapping.h"
#import "ORMXML.h"
#import "ORMModelPriv.h"

#define CD ORMCoreDataNamespace

static NSArray *
ORMObjectTypeMappingNames(void)
{
	return @[ @"Automatic", @"Entity", @"Absorbed", @"Ignored", @"Transformable", @"Joined" ];
}

@interface ORMJoinMember ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *correlationId;
@property (nonatomic, readwrite, copy) NSString *viaId;
@property (nonatomic, readwrite) BOOL isOuter;
@property (nonatomic, readwrite) BOOL correlationIsOptional;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *heldRoleIds;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *requiredRoleIds;
@end

@implementation ORMJoinMember
@end

@implementation ORMMappingMember
@end

@implementation ORMMappingOption
@end

static NSString *
ORMNonEmpty(NSString *string)
{
	return [string length] > 0 ? string : nil;
}

static NSNumber *
ORMBoolSet(NSXMLElement *element, NSString *attribute)
{
	return ORMAttribute(element, attribute) != nil ? @(ORMBoolAttribute(element, attribute, NO)) : nil;
}

@implementation ORMCoreDataMapping
{
	ORMCDModel *_baseline;
	/* What the public values come to, until the model is derived again. */
	NSDictionary *_nameOverrides;
	NSDictionary *_objectTypeMappings;
	NSDictionary *_transformables;
	NSDictionary *_joins;
	NSSet *_excludedSources;
	NSSet *_keptElements;
}

- (void)forgetDerivedValues
{
	[super forgetDerivedValues];
	_nameOverrides = nil;
	_objectTypeMappings = nil;
	_transformables = nil;
	_joins = nil;
	_excludedSources = nil;
	_keptElements = nil;
}

+ (instancetype)defaultMappingNamed:(NSString *)name
{
	ORMCoreDataMapping *mapping = [[self alloc] init];
	[mapping resetNamed:name];
	return mapping;
}

/* A new mapping's values: the defaults. */
- (void)resetNamed:(NSString *)name
{
	self.name = name;
	self.path = [name length] > 0 ? [name stringByAppendingPathExtension:@"xcdatamodeld"] : @"Model.xcdatamodeld";
	self.validationPath = nil;
	self.scope = ORMScopeModel;
	self.scopeIds = @[];
	self.materializesIdentifiers = YES;
	self.servesOData = YES;
	self.odataNamespace = @"Default";
	self.style = ORMStyleApplication;
	self.flattensSubtypesSet = nil;
	self.absorbsIdentifierTypesSet = nil;
	self.valueSetsAsEntities = YES;
	self.codeGenerationType = @"class";
	self.overrides = @[];
	self.options = @[];
	self.excluded = @[];
	self.kept = @[];
	self.baselineXML = nil;
	[self forgetDerivedValues];
}

- (void)reset
{
	[super reset];
	[self resetNamed:@"Model"];
}

- (void)readElement:(NSXMLElement *)element
{
	[self resetNamed:ORMAttribute(element, @"Name") ?: @"Model"];
	self.path = ORMAttribute(element, @"Path") ?: self.path;
	self.validationPath = ORMNonEmpty(ORMAttribute(element, @"ValidationPath"));
	NSString *scope = ORMAttribute(element, @"Scope");
	self.scope = [scope isEqualToString:@"Diagram"] ? ORMScopeDiagram
		: [scope isEqualToString:@"ObjectTypes"] ? ORMScopeObjectTypes : ORMScopeModel;
	NSMutableArray *scopeIds = [NSMutableArray array];
	for (NSXMLElement *include in ORMChildren(element, CD, @"Include")) {
		[scopeIds addObject:ORMRef(include) ?: @""];
	}
	self.scopeIds = scopeIds;
	self.materializesIdentifiers = ORMBoolAttribute(element, @"MaterializeIdentifiers", YES);
	self.servesOData = ORMBoolAttribute(element, @"ServeOData", YES);
	self.odataNamespace = ORMNonEmpty(ORMAttribute(element, @"ODataNamespace")) ?: @"Default";
	NSString *style = ORMAttribute(element, @"Style");
	self.style = [style isEqualToString:@"Relational"] ? ORMStyleRelational
		: [style isEqualToString:@"Entities"] ? ORMStyleEntities : ORMStyleApplication;
	self.flattensSubtypesSet = ORMBoolSet(element, @"FlattenSubtypes");
	self.absorbsIdentifierTypesSet = ORMBoolSet(element, @"AbsorbIdentifierTypes");
	self.valueSetsAsEntities = ORMBoolAttribute(element, @"ValueSetsAsEntities", YES);
	NSString *codegen = ORMAttribute(element, @"Codegen");
	self.codeGenerationType = codegen == nil ? @"class" : ([codegen isEqualToString:@"Manual"] ? nil : codegen);

	NSMutableArray *overrides = [NSMutableArray array];
	for (NSXMLElement *override in ORMChildren(element, CD, @"Override")) {
		NSString *target = ORMRef(override);
		NSString *name = ORMAttribute(override, @"Name");
		if (target != nil && [name length] > 0) {
			[overrides addObject:@[ target, name ]];
		}
	}
	self.overrides = overrides;
	NSMutableArray *options = [NSMutableArray array];
	for (NSXMLElement *optionElement in ORMChildren(element, CD, @"ObjectTypeMapping")) {
		NSUInteger index = [ORMObjectTypeMappingNames() indexOfObject:ORMAttribute(optionElement, @"As") ?: @""];
		if (ORMRef(optionElement) == nil || index == NSNotFound) {
			continue;
		}
		ORMMappingOption *option = [[ORMMappingOption alloc] init];
		option.objectTypeId = ORMRef(optionElement);
		option.how = (ORMObjectTypeMapping)index;
		option.className = ORMAttribute(optionElement, @"Class");
		option.transformerName = ORMAttribute(optionElement, @"Transformer");
		NSMutableArray *members = [NSMutableArray array];
		for (NSXMLElement *memberElement in ORMChildren(optionElement, CD, @"Member")) {
			ORMMappingMember *member = [[ORMMappingMember alloc] init];
			member.identifier = ORMAttribute(memberElement, @"id");
			member.name = ORMAttribute(memberElement, @"Name") ?: @"";
			member.correlationId = ORMNonEmpty(ORMAttribute(memberElement, @"By"));
			member.viaId = ORMNonEmpty(ORMAttribute(memberElement, @"Via"));
			member.isOuter = ORMBoolAttribute(memberElement, @"Outer", NO);
			member.correlationIsOptional = ORMBoolAttribute(memberElement, @"OptionalBy", NO);
			NSMutableArray *held = [NSMutableArray array];
			NSMutableArray *required = [NSMutableArray array];
			for (NSXMLElement *holds in ORMChildren(memberElement, CD, @"Holds")) {
				if (ORMRef(holds) != nil) {
					[held addObject:ORMRef(holds)];
					if (ORMBoolAttribute(holds, @"Required", NO)) {
						[required addObject:ORMRef(holds)];
					}
				}
			}
			member.heldRoleIds = held;
			member.requiredRoleIds = required;
			[members addObject:member];
		}
		option.members = members;
		[options addObject:option];
	}
	self.options = options;
	NSMutableArray *kept = [NSMutableArray array];
	for (NSXMLElement *keep in ORMChildren(element, CD, @"Keep")) {
		if (ORMAttribute(keep, @"Name") != nil) {
			[kept addObject:ORMAttribute(keep, @"Name")];
		}
	}
	self.kept = kept;
	NSMutableArray *excluded = [NSMutableArray array];
	for (NSXMLElement *exclude in ORMChildren(element, CD, @"Exclude")) {
		if (ORMRef(exclude) != nil) {
			[excluded addObject:ORMRef(exclude)];
		}
	}
	self.excluded = excluded;
	self.baselineXML = ORMNonEmpty([ORMChild(element, CD, @"Baseline") stringValue]);
	[self forgetDerivedValues];
}

- (void)setBaselineXML:(NSString *)baselineXML
{
	_baselineXML = [baselineXML copy];
	_baseline = nil;
}

- (ORMCDModel *)baseline
{
	if (_baseline == nil && _baselineXML != nil) {
		_baseline = [ORMCDModel modelWithContentsXML:[_baselineXML dataUsingEncoding:NSUTF8StringEncoding] reason:NULL];
	}
	return _baseline;
}

- (BOOL)flattensSubtypes
{
	return self.flattensSubtypesSet != nil ? [self.flattensSubtypesSet boolValue] : self.style == ORMStyleRelational;
}

- (BOOL)absorbsIdentifierTypes
{
	return self.absorbsIdentifierTypesSet != nil ? [self.absorbsIdentifierTypesSet boolValue]
	                                             : self.style == ORMStyleRelational;
}

- (NSDictionary<NSString *, NSString *> *)nameOverrides
{
	if (_nameOverrides != nil) {
		return _nameOverrides;
	}
	NSMutableDictionary *names = [NSMutableDictionary dictionary];
	for (NSArray *override in self.overrides) {
		[names setObject:[override lastObject] forKey:[override firstObject]];
	}
	return _nameOverrides = names;
}

- (NSDictionary<NSString *, NSNumber *> *)objectTypeMappings
{
	if (_objectTypeMappings != nil) {
		return _objectTypeMappings;
	}
	NSMutableDictionary *types = [NSMutableDictionary dictionary];
	for (ORMMappingOption *option in self.options) {
		[types setObject:@(option.how) forKey:option.objectTypeId];
	}
	return _objectTypeMappings = types;
}

- (NSDictionary<NSString *, NSArray<NSString *> *> *)transformables
{
	if (_transformables != nil) {
		return _transformables;
	}
	NSMutableDictionary *transformables = [NSMutableDictionary dictionary];
	for (ORMMappingOption *option in self.options) {
		if (option.how == ORMMapTransformable) {
			[transformables setObject:@[ option.className ?: @"NSString",
			                             option.transformerName ?: @"NSSecureUnarchiveFromData" ]
			                   forKey:option.objectTypeId];
		}
	}
	return _transformables = transformables;
}

/* The hub, the first member, has no Via, and is not outer: every instance
 * has a row in it. Another's Via is the hub unless it says. */
- (NSDictionary<NSString *, NSArray<ORMJoinMember *> *> *)joins
{
	if (_joins != nil) {
		return _joins;
	}
	NSMutableDictionary *joins = [NSMutableDictionary dictionary];
	for (ORMMappingOption *option in self.options) {
		if (option.how != ORMMapJoined || [option.members count] == 0) {
			continue;
		}
		NSMutableArray *members = [NSMutableArray array];
		for (ORMMappingMember *stored in option.members) {
			BOOL hub = [members count] == 0;
			ORMJoinMember *member = [[ORMJoinMember alloc] init];
			member.identifier = stored.identifier;
			member.name = stored.name;
			member.correlationId = stored.correlationId;
			member.viaId = hub ? nil : (stored.viaId ?: [(ORMJoinMember *)[members firstObject] identifier]);
			member.isOuter = !hub && stored.isOuter;
			member.correlationIsOptional = !hub && stored.correlationIsOptional;
			member.heldRoleIds = stored.heldRoleIds;
			member.requiredRoleIds = stored.requiredRoleIds;
			[members addObject:member];
		}
		[joins setObject:members forKey:option.objectTypeId];
	}
	return _joins = joins;
}

- (NSSet<NSString *> *)excludedSources
{
	return _excludedSources ?: (_excludedSources = [NSSet setWithArray:self.excluded]);
}

- (NSSet<NSString *> *)keptElements
{
	return _keptElements ?: (_keptElements = [NSSet setWithArray:self.kept]);
}

- (ORMMappingOption *)optionFor:(NSString *)objectTypeId
{
	for (ORMMappingOption *option in self.options) {
		if ([option.objectTypeId isEqualToString:objectTypeId]) {
			return option;
		}
	}
	return nil;
}

- (ORMMappingMember *)memberWithId:(NSString *)memberId
{
	for (ORMMappingOption *option in self.options) {
		for (ORMMappingMember *member in option.members) {
			if ([member.identifier isEqualToString:memberId]) {
				return member;
			}
		}
	}
	return nil;
}

- (BOOL)absorbsValueLikeTypes
{
	return self.style != ORMStyleEntities;
}

- (ORMObjectTypeMapping)mappingOfObjectType:(NSString *)objectTypeId
{
	NSNumber *mapping = [self.objectTypeMappings objectForKey:objectTypeId];
	return mapping != nil ? [mapping integerValue] : ORMMapAutomatically;
}

static NSString *
ORMResolvedPath(NSString *path, NSString *documentPath)
{
	if (path == nil || [path isAbsolutePath] || documentPath == nil) {
		return path;
	}
	return [[[documentPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:path]
		stringByStandardizingPath];
}

- (NSString *)resolvedPathRelativeTo:(NSString *)documentPath
{
	return ORMResolvedPath(self.path, documentPath);
}

- (NSString *)resolvedValidationPathRelativeTo:(NSString *)documentPath
{
	return ORMResolvedPath(self.validationPath, documentPath);
}

@end

@implementation ORMModel (ORMCoreDataMappingReading)

- (void)readCoreDataMappings
{
	NSMutableArray *mappings = [NSMutableArray array];
	NSXMLElement *container = ORMChild([self.document rootElement], CD, @"CoreDataMappings");
	for (NSXMLElement *element in ORMChildren(container, CD, @"Mapping")) {
		ORMCoreDataMapping *mapping = [self element:[ORMCoreDataMapping class] for:element];
		[mapping readElement:element];
		[mappings addObject:mapping];
		[self registerElement:mapping];
	}
	self.coreDataMappings = mappings;
}

@end

#pragma mark Written

/* A new child of the mapping goes before the baseline, which stays last. */
static void
ORMAddToMapping(NSXMLElement *mapping, NSXMLElement *child)
{
	NSXMLElement *baseline = ORMChild(mapping, CD, @"Baseline");
	ORMInsertChildAt(mapping, child, baseline != nil ? [baseline index] : [mapping childCount]);
}

static void
ORMWriteAttribute(NSXMLElement *element, NSString *attribute, NSString *value)
{
	if (![ORMAttribute(element, attribute) ?: @"" isEqualToString:value ?: @""]
	    || (ORMAttribute(element, attribute) == nil) != (value == nil)) {
		ORMSetAttribute(element, attribute, value);
	}
}

static BOOL
ORMSameObject(id one, id other)
{
	return one == other || [one isEqual:other];
}

/* The children of a kind keyed by an attribute, as the keys: those of a
 * key gone go, the others stay where they are. The key's element, the
 * last of it, by key. */
static NSDictionary<NSString *, NSXMLElement *> *
ORMKeepChildren(NSXMLElement *parent, NSString *local, NSString *attribute, NSArray<NSString *> *keys)
{
	NSMutableDictionary *kept = [NSMutableDictionary dictionary];
	NSSet *wanted = [NSSet setWithArray:keys];
	for (NSXMLElement *child in ORMChildren(parent, CD, local)) {
		NSString *key = ORMAttribute(child, attribute);
		if (key == nil) {
			continue;
		}
		if ([wanted containsObject:key]) {
			[kept setObject:child forKey:key];
		} else {
			ORMDetach(child);
		}
	}
	return kept;
}

@implementation ORMNormaWriter (ORMCoreDataMappings)

- (void)writeCoreDataMapping:(ORMCoreDataMapping *)mapping
{
	NSXMLDocument *document = [self.model.modelElement rootDocument];
	NSXMLElement *element = mapping.element;
	if (element == nil) {
		NSXMLElement *root = [document rootElement];
		NSXMLElement *container = ORMChild(root, CD, @"CoreDataMappings");
		if (container == nil) {
			container = ORMNewElement(document, CD, @"CoreDataMappings");
			ORMAddChild(root, container);
		}
		element = ORMNewElementWithId(document, CD, @"Mapping", mapping.identifier);
		ORMSetAttribute(element, @"Name", mapping.name);
		ORMSetAttribute(element, @"Path", mapping.path);
		ORMSetAttribute(element, @"Scope", @"Model");
		ORMAddChild(container, element);
		mapping.element = element;
	}
	/* What the element has: a value it already has is left as written. */
	ORMCoreDataMapping *was = [[ORMCoreDataMapping alloc] init];
	[was readElement:element];
	if (![was.path isEqualToString:mapping.path]) {
		ORMSetAttribute(element, @"Path", mapping.path);
	}
	if (!ORMSameObject(was.validationPath, mapping.validationPath)) {
		ORMSetAttribute(element, @"ValidationPath", mapping.validationPath);
	}
	if (was.scope != mapping.scope) {
		ORMSetAttribute(element, @"Scope", mapping.scope == ORMScopeDiagram ? @"Diagram"
		                                   : mapping.scope == ORMScopeObjectTypes ? @"ObjectTypes" : @"Model");
	}
	if (![was.scopeIds isEqualToArray:mapping.scopeIds]) {
		for (NSXMLElement *include in ORMChildren(element, CD, @"Include")) {
			ORMDetach(include);
		}
		NSUInteger index = 0;
		for (NSString *identifier in mapping.scopeIds) {
			ORMInsertChildAt(element, ORMNewRef(document, CD, @"Include", identifier), index++);
		}
	}
	if (was.materializesIdentifiers != mapping.materializesIdentifiers) {
		ORMSetAttribute(element, @"MaterializeIdentifiers", mapping.materializesIdentifiers ? nil : @"false");
	}
	if (was.servesOData != mapping.servesOData) {
		ORMSetAttribute(element, @"ServeOData", mapping.servesOData ? nil : @"false");
	}
	if (!ORMSameObject(was.flattensSubtypesSet, mapping.flattensSubtypesSet)) {
		ORMSetAttribute(element, @"FlattenSubtypes", mapping.flattensSubtypesSet == nil ? nil
		                                             : [mapping.flattensSubtypesSet boolValue] ? @"true" : @"false");
	}
	if (!ORMSameObject(was.absorbsIdentifierTypesSet, mapping.absorbsIdentifierTypesSet)) {
		ORMSetAttribute(element, @"AbsorbIdentifierTypes", mapping.absorbsIdentifierTypesSet == nil ? nil
		                                    : [mapping.absorbsIdentifierTypesSet boolValue] ? @"true" : @"false");
	}
	if (was.style != mapping.style) {
		ORMSetAttribute(element, @"Style", mapping.style == ORMStyleRelational ? @"Relational"
		                                   : mapping.style == ORMStyleEntities ? @"Entities" : nil);
	}
	if (was.valueSetsAsEntities != mapping.valueSetsAsEntities) {
		ORMSetAttribute(element, @"ValueSetsAsEntities", mapping.valueSetsAsEntities ? nil : @"false");
	}

	/* Names, unless the element's name nothing (it is not read). */
	NSMutableArray *sources = [NSMutableArray array];
	for (NSArray *override in mapping.overrides) {
		[sources addObject:[override firstObject]];
	}
	NSMutableArray *named = [NSMutableArray array];
	for (NSXMLElement *child in ORMChildren(element, CD, @"Override")) {
		if ([ORMAttribute(child, @"Name") length] == 0) {
			[named addObject:ORMAttribute(child, @"ref") ?: @""];
		}
	}
	NSDictionary *overrides = ORMKeepChildren(element, @"Override", @"ref", [sources arrayByAddingObjectsFromArray:named]);
	for (NSArray *override in mapping.overrides) {
		NSXMLElement *child = [overrides objectForKey:[override firstObject]];
		if (child == nil) {
			child = ORMNewRef(document, CD, @"Override", [override firstObject]);
			ORMAddToMapping(element, child);
		}
		ORMWriteAttribute(child, @"Name", [override lastObject]);
	}
	[self writeOptionsOf:mapping into:element];
	NSDictionary *excluded = ORMKeepChildren(element, @"Exclude", @"ref", mapping.excluded);
	for (NSString *source in mapping.excluded) {
		if ([excluded objectForKey:source] == nil) {
			ORMAddToMapping(element, ORMNewRef(document, CD, @"Exclude", source));
		}
	}
	NSDictionary *kept = ORMKeepChildren(element, @"Keep", @"Name", mapping.kept);
	for (NSString *path in mapping.kept) {
		if ([kept objectForKey:path] == nil) {
			NSXMLElement *keep = ORMNewElement(document, CD, @"Keep");
			ORMSetAttribute(keep, @"Name", path);
			ORMAddToMapping(element, keep);
		}
	}
	if (!ORMSameObject(was.baselineXML, mapping.baselineXML)) {
		ORMSetChildText(document, element, CD, @"Baseline", mapping.baselineXML);
	}
}

/* Each object type's mapping: one it does not read (an unknown As) stays. */
- (void)writeOptionsOf:(ORMCoreDataMapping *)mapping into:(NSXMLElement *)element
{
	NSXMLDocument *document = [element rootDocument];
	NSMutableArray *types = [NSMutableArray array];
	for (ORMMappingOption *option in mapping.options) {
		[types addObject:option.objectTypeId];
	}
	for (NSXMLElement *child in ORMChildren(element, CD, @"ObjectTypeMapping")) {
		if ([ORMObjectTypeMappingNames() indexOfObject:ORMAttribute(child, @"As") ?: @""] == NSNotFound) {
			[types addObject:ORMRef(child) ?: @""];
		}
	}
	NSDictionary *existing = ORMKeepChildren(element, @"ObjectTypeMapping", @"ref", types);
	for (ORMMappingOption *option in mapping.options) {
		NSXMLElement *child = [existing objectForKey:option.objectTypeId];
		if (child == nil) {
			child = ORMNewRef(document, CD, @"ObjectTypeMapping", option.objectTypeId);
			ORMAddToMapping(element, child);
		}
		ORMWriteAttribute(child, @"As", [ORMObjectTypeMappingNames() objectAtIndex:option.how]);
		ORMWriteAttribute(child, @"Class", option.className);
		ORMWriteAttribute(child, @"Transformer", option.transformerName);
		NSMutableArray *ids = [NSMutableArray array];
		for (ORMMappingMember *member in option.members) {
			[ids addObject:member.identifier ?: @""];
		}
		NSDictionary *members = ORMKeepChildren(child, @"Member", @"id", ids);
		for (ORMMappingMember *member in option.members) {
			NSXMLElement *memberElement = [members objectForKey:member.identifier ?: @""];
			if (memberElement == nil) {
				memberElement = ORMNewElementWithId(document, CD, @"Member", member.identifier);
				ORMAddChild(child, memberElement);
			}
			[self writeMember:member into:memberElement];
		}
	}
}

- (void)writeMember:(ORMMappingMember *)member into:(NSXMLElement *)element
{
	NSXMLDocument *document = [element rootDocument];
	ORMWriteAttribute(element, @"Name", ORMAttribute(element, @"Name") == nil && [member.name length] == 0 ? nil : member.name);
	if (!ORMSameObject(ORMNonEmpty(ORMAttribute(element, @"By")), member.correlationId)) {
		ORMSetAttribute(element, @"By", member.correlationId);
	}
	if (!ORMSameObject(ORMNonEmpty(ORMAttribute(element, @"Via")), member.viaId)) {
		ORMSetAttribute(element, @"Via", member.viaId);
	}
	if (ORMBoolAttribute(element, @"Outer", NO) != member.isOuter) {
		ORMSetAttribute(element, @"Outer", member.isOuter ? @"true" : nil);
	}
	if (ORMBoolAttribute(element, @"OptionalBy", NO) != member.correlationIsOptional) {
		ORMSetAttribute(element, @"OptionalBy", member.correlationIsOptional ? @"true" : nil);
	}
	NSDictionary *holds = ORMKeepChildren(element, @"Holds", @"ref", member.heldRoleIds);
	for (NSString *roleId in member.heldRoleIds) {
		NSXMLElement *child = [holds objectForKey:roleId];
		if (child == nil) {
			child = ORMNewRef(document, CD, @"Holds", roleId);
			ORMAddChild(element, child);
		}
		BOOL required = [member.requiredRoleIds containsObject:roleId];
		if (ORMBoolAttribute(child, @"Required", NO) != required) {
			ORMSetAttribute(child, @"Required", required ? @"true" : nil);
		}
	}
}

@end
