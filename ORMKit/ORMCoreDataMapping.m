/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataMapping.h"
#import "ORMXML.h"

#define CD ORMCoreDataNamespace

@interface ORMCoreDataMapping ()
@property (nonatomic, readwrite, copy) NSString *identifier;
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite, copy) NSString *validationPath;
@property (nonatomic, readwrite) ORMMappingScope scope;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *scopeIds;
@property (nonatomic, readwrite) BOOL materializesIdentifiers;
@property (nonatomic, readwrite) BOOL servesOData;
@property (nonatomic, readwrite) BOOL flattensSubtypes;
@property (nonatomic, readwrite) BOOL absorbsIdentifierTypes;
@property (nonatomic, readwrite) ORMMappingStyle style;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSArray<NSString *> *> *transformables;
@property (nonatomic, readwrite) BOOL valueSetsAsEntities;
@property (nonatomic, readwrite, copy) NSString *codeGenerationType;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *nameOverrides;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSNumber *> *objectTypeMappings;
@property (nonatomic, readwrite, copy) NSSet<NSString *> *keptElements;
@property (nonatomic, readwrite, copy) NSSet<NSString *> *excludedSources;
@property (nonatomic, readwrite, strong) ORMCDModel *baseline;
@property (nonatomic, readwrite, strong) NSXMLElement *element;
@end

static NSArray *
ORMObjectTypeMappingNames(void)
{
	return @[ @"Automatic", @"Entity", @"Absorbed", @"Ignored", @"Transformable" ];
}

@implementation ORMCoreDataMapping

+ (instancetype)defaultMappingNamed:(NSString *)name
{
	ORMCoreDataMapping *mapping = [[self alloc] init];
	mapping.name = name;
	mapping.path = [name length] > 0 ? [name stringByAppendingPathExtension:@"xcdatamodeld"] : @"Model.xcdatamodeld";
	mapping.scope = ORMScopeModel;
	mapping.scopeIds = @[];
	mapping.materializesIdentifiers = YES;
	mapping.servesOData = YES;
	mapping.valueSetsAsEntities = YES;
	mapping.codeGenerationType = @"class";
	mapping.nameOverrides = @{};
	mapping.objectTypeMappings = @{};
	mapping.transformables = @{};
	mapping.keptElements = [NSSet set];
	mapping.excludedSources = [NSSet set];
	return mapping;
}

+ (instancetype)mappingOfElement:(NSXMLElement *)element
{
	ORMCoreDataMapping *mapping = [self defaultMappingNamed:ORMAttribute(element, @"Name") ?: @"Model"];
	mapping.element = element;
	mapping.identifier = ORMAttribute(element, @"id");
	mapping.path = ORMAttribute(element, @"Path") ?: mapping.path;
	mapping.validationPath = [ORMAttribute(element, @"ValidationPath") length] > 0
		? ORMAttribute(element, @"ValidationPath") : nil;
	NSString *scope = ORMAttribute(element, @"Scope");
	mapping.scope = [scope isEqualToString:@"Diagram"] ? ORMScopeDiagram
		: [scope isEqualToString:@"ObjectTypes"] ? ORMScopeObjectTypes : ORMScopeModel;
	NSMutableArray *scopeIds = [NSMutableArray array];
	for (NSXMLElement *include in ORMChildren(element, CD, @"Include")) {
		[scopeIds addObject:ORMRef(include) ?: @""];
	}
	mapping.scopeIds = scopeIds;
	mapping.materializesIdentifiers = ORMBoolAttribute(element, @"MaterializeIdentifiers", YES);
	mapping.servesOData = ORMBoolAttribute(element, @"ServeOData", YES);
	NSString *style = ORMAttribute(element, @"Style");
	mapping.style = [style isEqualToString:@"Relational"] ? ORMStyleRelational
		: [style isEqualToString:@"Entities"] ? ORMStyleEntities : ORMStyleApplication;
	BOOL relational = mapping.style == ORMStyleRelational;
	mapping.flattensSubtypes = ORMBoolAttribute(element, @"FlattenSubtypes", relational);
	mapping.absorbsIdentifierTypes = ORMBoolAttribute(element, @"AbsorbIdentifierTypes", relational);
	mapping.valueSetsAsEntities = ORMBoolAttribute(element, @"ValueSetsAsEntities", YES);
	NSString *codegen = ORMAttribute(element, @"Codegen");
	mapping.codeGenerationType = codegen == nil ? @"class" : ([codegen isEqualToString:@"Manual"] ? nil : codegen);

	NSMutableDictionary *names = [NSMutableDictionary dictionary];
	for (NSXMLElement *override in ORMChildren(element, CD, @"Override")) {
		NSString *target = ORMRef(override);
		NSString *name = ORMAttribute(override, @"Name");
		if (target != nil && [name length] > 0) {
			[names setObject:name forKey:target];
		}
	}
	mapping.nameOverrides = names;
	NSMutableDictionary *types = [NSMutableDictionary dictionary];
	NSMutableDictionary *transformables = [NSMutableDictionary dictionary];
	for (NSXMLElement *option in ORMChildren(element, CD, @"ObjectTypeMapping")) {
		NSUInteger index = [ORMObjectTypeMappingNames() indexOfObject:ORMAttribute(option, @"As") ?: @""];
		if (ORMRef(option) != nil && index != NSNotFound) {
			[types setObject:@(index) forKey:ORMRef(option)];
			if (index == ORMMapTransformable) {
				[transformables setObject:@[ ORMAttribute(option, @"Class") ?: @"NSString",
				                             ORMAttribute(option, @"Transformer") ?: @"NSSecureUnarchiveFromData" ]
				                   forKey:ORMRef(option)];
			}
		}
	}
	mapping.objectTypeMappings = types;
	mapping.transformables = transformables;
	NSMutableSet *kept = [NSMutableSet set];
	for (NSXMLElement *keep in ORMChildren(element, CD, @"Keep")) {
		if (ORMAttribute(keep, @"Name") != nil) {
			[kept addObject:ORMAttribute(keep, @"Name")];
		}
	}
	mapping.keptElements = kept;
	NSMutableSet *excluded = [NSMutableSet set];
	for (NSXMLElement *exclude in ORMChildren(element, CD, @"Exclude")) {
		if (ORMRef(exclude) != nil) {
			[excluded addObject:ORMRef(exclude)];
		}
	}
	mapping.excludedSources = excluded;
	NSXMLElement *baseline = ORMChild(element, CD, @"Baseline");
	NSString *contents = [baseline stringValue];
	if ([contents length] > 0) {
		mapping.baseline = [ORMCDModel modelWithContentsXML:[contents dataUsingEncoding:NSUTF8StringEncoding] reason:NULL];
	}
	return mapping;
}

+ (NSArray<ORMCoreDataMapping *> *)mappingsOfDocument:(NSXMLDocument *)document
{
	NSMutableArray *mappings = [NSMutableArray array];
	NSXMLElement *container = ORMChild([document rootElement], CD, @"CoreDataMappings");
	for (NSXMLElement *element in ORMChildren(container, CD, @"Mapping")) {
		[mappings addObject:[self mappingOfElement:element]];
	}
	return mappings;
}

+ (ORMCoreDataMapping *)mappingWithId:(NSString *)identifier inDocument:(NSXMLDocument *)document
{
	for (ORMCoreDataMapping *mapping in [self mappingsOfDocument:document]) {
		if ([mapping.identifier isEqualToString:identifier]) {
			return mapping;
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
