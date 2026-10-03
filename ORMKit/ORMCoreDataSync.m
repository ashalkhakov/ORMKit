/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataSync.h"
#import "ORMEditorPriv.h"

#define CD ORMCoreDataNamespace

#pragma mark Mappings in the document

@implementation ORMEditor (ORMCoreDataMappings)

- (NSXMLElement *)mappingsContainer
{
	NSXMLElement *root = [self.document rootElement];
	NSXMLElement *container = ORMChild(root, CD, @"CoreDataMappings");
	if (container == nil) {
		container = ORMNewElement(self.document, CD, @"CoreDataMappings");
		[root addChild:container];
	}
	return container;
}

- (NSXMLElement *)mappingElement:(NSString *)mappingId
{
	for (NSXMLElement *element in ORMChildren(ORMChild([self.document rootElement], CD, @"CoreDataMappings"), CD,
	                                          @"Mapping")) {
		if ([ORMAttribute(element, @"id") isEqualToString:mappingId]) {
			return element;
		}
	}
	return nil;
}

- (NSString *)addCoreDataMappingNamed:(NSString *)name path:(NSString *)path
{
	__block NSString *created = nil;
	[self change:@"Add Core Data Mapping" with:^{
		NSXMLElement *mapping = ORMNewElementWithId(self.document, CD, @"Mapping", nil);
		NSString *mappingName = [name length] > 0 ? name : self.model.name;
		ORMSetAttribute(mapping, @"Name", mappingName);
		ORMSetAttribute(mapping, @"Path", [path length] > 0 ? path
		                                                 : [mappingName stringByAppendingPathExtension:@"xcdatamodeld"]);
		ORMSetAttribute(mapping, @"Scope", @"Model");
		[[self mappingsContainer] addChild:mapping];
		created = ORMAttribute(mapping, @"id");
	}];
	return created;
}

- (void)removeCoreDataMapping:(NSString *)mappingId
{
	NSXMLElement *mapping = [self mappingElement:mappingId];
	if (mapping == nil) {
		return;
	}
	[self change:@"Remove Core Data Mapping" with:^{
		NSXMLElement *container = (NSXMLElement *)[mapping parent];
		[mapping detach];
		ORMPruneIfEmpty(container);
	}];
}

- (void)setMappingAttribute:(NSString *)attribute value:(NSString *)value of:(NSString *)mappingId
                     action:(NSString *)action
{
	NSXMLElement *mapping = [self mappingElement:mappingId];
	if (mapping == nil || [ORMAttribute(mapping, attribute) ?: @"" isEqualToString:value ?: @""]) {
		return;
	}
	[self change:action with:^{
		ORMSetAttribute(mapping, attribute, value);
	}];
}

- (BOOL)setPath:(NSString *)path ofMapping:(NSString *)mappingId reason:(NSString **)reason
{
	if (![[path pathExtension] isEqualToString:@"xcdatamodeld"]) {
		if (reason != NULL) {
			*reason = @"A Core Data model is a .xcdatamodeld.";
		}
		return NO;
	}
	[self setMappingAttribute:@"Path" value:path of:mappingId action:@"Set Model Path"];
	return YES;
}

- (void)setScope:(ORMMappingScope)scope ids:(NSArray<NSString *> *)ids ofMapping:(NSString *)mappingId
{
	NSXMLElement *mapping = [self mappingElement:mappingId];
	if (mapping == nil) {
		return;
	}
	[self change:@"Set Mapping Scope" with:^{
		ORMSetAttribute(mapping, @"Scope", scope == ORMScopeDiagram ? @"Diagram"
		                                   : scope == ORMScopeObjectTypes ? @"ObjectTypes" : @"Model");
		for (NSXMLElement *include in ORMChildren(mapping, CD, @"Include")) {
			[include detach];
		}
		NSUInteger index = 0;
		for (NSString *identifier in scope == ORMScopeModel ? @[] : ids) {
			[mapping insertChild:ORMNewRef(self.document, CD, @"Include", identifier) atIndex:index++];
		}
	}];
}

- (void)setMaterializesIdentifiers:(BOOL)flag ofMapping:(NSString *)mappingId
{
	[self setMappingAttribute:@"MaterializeIdentifiers" value:flag ? nil : @"false" of:mappingId
	                   action:@"Set Identifier Mapping"];
}

- (void)setFlattensSubtypes:(BOOL)flag ofMapping:(NSString *)mappingId
{
	[self setMappingAttribute:@"FlattenSubtypes" value:flag ? @"true" : @"false" of:mappingId action:@"Set Subtype Mapping"];
}

- (void)setValueSetsAsEntities:(BOOL)flag ofMapping:(NSString *)mappingId
{
	[self setMappingAttribute:@"ValueSetsAsEntities" value:flag ? nil : @"false" of:mappingId
	                   action:@"Set Value Set Mapping"];
}

/* The child of the mapping of the kind for the target, made or removed. */
- (void)setChild:(NSString *)local target:(NSString *)target attribute:(NSString *)attribute value:(NSString *)value
       inMapping:(NSString *)mappingId action:(NSString *)action
{
	NSXMLElement *mapping = [self mappingElement:mappingId];
	if (mapping == nil) {
		return;
	}
	NSXMLElement *existing = nil;
	for (NSXMLElement *child in ORMChildren(mapping, CD, local)) {
		BOOL matches = attribute == nil ? [ORMAttribute(child, @"Name") isEqualToString:target]
		                                : [ORMRef(child) isEqualToString:target];
		if (matches) {
			existing = child;
		}
	}
	BOOL wanted = value != nil;
	if (!wanted && existing == nil) {
		return;
	}
	if (wanted && existing != nil && (attribute == nil || [ORMAttribute(existing, attribute) isEqualToString:value])) {
		return;
	}
	[self change:action with:^{
		if (!wanted) {
			[existing detach];
			return;
		}
		NSXMLElement *child = existing;
		if (child == nil) {
			child = ORMNewElement(self.document, CD, local);
			if (attribute == nil) {
				ORMSetAttribute(child, @"Name", target);
			} else {
				ORMSetAttribute(child, @"ref", target);
			}
			/* Before the baseline, which stays last. */
			NSXMLElement *baseline = ORMChild(mapping, CD, @"Baseline");
			[mapping insertChild:child atIndex:baseline != nil ? [baseline index] : [mapping childCount]];
		}
		if (attribute != nil) {
			ORMSetAttribute(child, attribute, value);
		}
	}];
}

- (void)setName:(NSString *)name forSource:(NSString *)sourceId inMapping:(NSString *)mappingId
{
	[self setChild:@"Override" target:sourceId attribute:@"Name" value:[name length] > 0 ? name : nil
	     inMapping:mappingId action:@"Rename in Core Data"];
}

- (void)setStyle:(ORMMappingStyle)style ofMapping:(NSString *)mappingId
{
	/* The style's own defaults then hold: what was set for another is
	 * cleared. */
	[self group:@"Set Mapping Style" with:^{
		[self setMappingAttribute:@"FlattenSubtypes" value:nil of:mappingId action:@"Set Mapping Style"];
		[self setMappingAttribute:@"AbsorbIdentifierTypes" value:nil of:mappingId action:@"Set Mapping Style"];
		[self setMappingAttribute:@"Style"
		                    value:style == ORMStyleRelational ? @"Relational" : style == ORMStyleEntities ? @"Entities" : nil
		                       of:mappingId
		                   action:@"Set Mapping Style"];
	}];
}

- (void)setAbsorbsIdentifierTypes:(BOOL)flag ofMapping:(NSString *)mappingId
{
	[self setMappingAttribute:@"AbsorbIdentifierTypes" value:flag ? @"true" : @"false" of:mappingId
	                   action:@"Set Identifier Type Mapping"];
}

- (void)setTransformableClass:(NSString *)className
                  transformer:(NSString *)transformerName
                 ofObjectType:(NSString *)objectTypeId
                    inMapping:(NSString *)mappingId
{
	[self group:@"Map as Transformable" with:^{
		[self setMapping:ORMMapTransformable ofObjectType:objectTypeId inMapping:mappingId];
		[self setChild:@"ObjectTypeMapping" target:objectTypeId attribute:@"Class"
		         value:[className length] > 0 ? className : @"NSString" inMapping:mappingId
		        action:@"Set Transformable Class"];
		[self setChild:@"ObjectTypeMapping" target:objectTypeId attribute:@"Transformer"
		         value:[transformerName length] > 0 ? transformerName : @"NSSecureUnarchiveFromData"
		     inMapping:mappingId
		        action:@"Set Value Transformer"];
	}];
}

- (void)setMapping:(ORMObjectTypeMapping)how ofObjectType:(NSString *)objectTypeId inMapping:(NSString *)mappingId
{
	NSArray *names = @[ @"Automatic", @"Entity", @"Absorbed", @"Ignored", @"Transformable" ];
	[self setChild:@"ObjectTypeMapping" target:objectTypeId attribute:@"As"
	         value:how == ORMMapAutomatically ? nil : [names objectAtIndex:how] inMapping:mappingId
	        action:@"Set Object Type Mapping"];
}

- (void)setExcluded:(BOOL)excluded source:(NSString *)sourceId inMapping:(NSString *)mappingId
{
	[self setChild:@"Exclude" target:sourceId attribute:@"ref" value:excluded ? sourceId : nil inMapping:mappingId
	        action:excluded ? @"Exclude from Core Data" : @"Include in Core Data"];
}

- (void)setKept:(BOOL)kept element:(NSString *)path inMapping:(NSString *)mappingId
{
	[self setChild:@"Keep" target:path attribute:nil value:kept ? path : nil inMapping:mappingId
	        action:@"Keep in Core Data"];
}

- (void)setBaseline:(ORMCDModel *)model ofMapping:(NSString *)mappingId
{
	NSXMLElement *mapping = [self mappingElement:mappingId];
	if (mapping == nil) {
		return;
	}
	NSString *contents = [[NSString alloc] initWithData:[model contentsXML] encoding:NSUTF8StringEncoding];
	if ([[ORMChild(mapping, CD, @"Baseline") stringValue] isEqualToString:contents]) {
		return;
	}
	[self change:@"Synchronize Core Data" with:^{
		ORMSetChildText(self.document, mapping, CD, @"Baseline", contents);
	}];
}

- (NSXMLDocument *)documentForNorma
{
	NSXMLDocument *copy = ORMCopyDocument([self documentForSaving]);
	NSXMLElement *root = [copy rootElement];
	for (NSXMLElement *element in ORMDescendants(root, CD, nil)) {
		[element detach];
	}
	for (NSXMLNode *namespace in [[root namespaces] copy]) {
		if ([[namespace stringValue] isEqualToString:CD]) {
			[root removeNamespaceForPrefix:[namespace name]];
		}
	}
	return copy;
}

@end

#pragma mark Changes

@interface ORMSyncChange ()
@property (nonatomic, readwrite) ORMSyncChangeKind kind;
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite, copy) NSArray<NSNumber *> *possibleActions;
@property (nonatomic, readwrite) BOOL conflicts;
/* When it is applied: entity types (0) before what is added to them (1),
 * and subtyping (2) once both ends exist. */
@property (nonatomic) NSUInteger phase;
/* What each action does, run inside the sync's undo group. */
@property (nonatomic, copy) void (^toModel)(void);
@property (nonatomic, copy) void (^toMapping)(void);
@end

@implementation ORMSyncChange

- (NSString *)description
{
	return self.text;
}

@end

/* Xcode's attribute types back as NORMA's data types. */
static NSString *
ORMDataTypeForAttributeType(NSString *type)
{
	NSDictionary *types = @{ @"Integer 16": @"SignedSmallIntegerNumericDataType",
	                         @"Integer 32": @"SignedIntegerNumericDataType",
	                         @"Integer 64": @"SignedLargeIntegerNumericDataType",
	                         @"Decimal": @"DecimalNumericDataType",
	                         @"Double": @"DoublePrecisionFloatingPointNumericDataType",
	                         @"Float": @"SinglePrecisionFloatingPointNumericDataType",
	                         @"String": @"VariableLengthTextDataType",
	                         @"Boolean": @"TrueOrFalseLogicalDataType",
	                         @"Date": @"DateAndTimeTemporalDataType",
	                         @"Binary": @"VariableLengthRawDataDataType",
	                         @"UUID": @"ObjectIdOtherDataType",
	                         @"URI": @"VariableLengthTextDataType" };
	return [types objectForKey:type] ?: @"UnspecifiedDataType";
}

@implementation ORMCoreDataSync
{
	ORMEditor *_editor;
	NSString *_mappingId;
	ORMCDModel *_theirs;
	ORMCDModel *_base;
	NSMutableArray<ORMSyncChange *> *_changes;
}

- (instancetype)initWithEditor:(ORMEditor *)editor mapping:(NSString *)mappingId theirs:(ORMCDModel *)theirs
{
	if ((self = [super init])) {
		_editor = editor;
		_mappingId = [mappingId copy];
		_theirs = theirs;
		ORMCoreDataMapping *mapping = [ORMCoreDataMapping mappingWithId:mappingId inDocument:editor.document];
		_base = mapping.baseline ?: [ORMCDModel model];
		ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:mapping];
		_ours = [mapper map];
		_notes = mapper.notes;
		_changes = [NSMutableArray array];
		if (theirs != nil) {
			[self findChanges];
		}
	}
	return self;
}

- (NSArray<ORMSyncChange *> *)changes
{
	return _changes;
}

#pragma mark Matching

static ORMCDEntity *
ORMMatchEntity(ORMCDModel *model, ORMCDEntity *like)
{
	if (like == nil) {
		return nil;
	}
	if (like.source != nil) {
		ORMCDEntity *traced = [model entityWithSource:like.source];
		if (traced != nil) {
			return traced;
		}
	}
	ORMCDEntity *named = [model entityNamed:like.name];
	/* By name only when the name is not another element's. */
	return named.source == nil || like.source == nil || [named.source isEqualToString:like.source] ? named : nil;
}

static ORMCDProperty *
ORMMatchProperty(ORMCDEntity *entity, ORMCDProperty *like)
{
	if (entity == nil || like == nil) {
		return nil;
	}
	if (like.source != nil) {
		for (ORMCDProperty *property in [entity properties]) {
			if ([property.source isEqualToString:like.source]) {
				return property;
			}
		}
	}
	ORMCDProperty *named = [entity propertyNamed:like.name];
	if (named != nil && [named class] == [like class]
	    && (named.source == nil || like.source == nil || [named.source isEqualToString:like.source])) {
		return named;
	}
	return nil;
}

/* The ORM roles a property's source names: the far role, and the near
 * one -- the role of the entity's own object type. */
- (ORMRole *)farRoleOf:(ORMCDProperty *)property
{
	id element = property.source != nil ? [_editor.model elementWithId:property.source] : nil;
	return [element isKindOfClass:[ORMRole class]] ? element : nil;
}

- (ORMRole *)nearRoleOf:(ORMCDProperty *)property
{
	ORMRole *far = [self farRoleOf:property];
	if (far == nil) {
		return nil;
	}
	if (far.player.isImplicitBooleanValue) {
		return [[far.factType visibleRoles] firstObject];
	}
	return [far oppositeRole];
}

- (ORMObjectType *)objectTypeOf:(ORMCDEntity *)entity
{
	id element = entity.source != nil ? [_editor.model elementWithId:entity.source] : nil;
	return [element isKindOfClass:[ORMObjectType class]] ? element : nil;
}

#pragma mark Finding changes

- (ORMSyncChange *)change:(ORMSyncChangeKind)kind path:(NSString *)path text:(NSString *)text
{
	ORMSyncChange *change = [[ORMSyncChange alloc] init];
	change.kind = kind;
	change.path = path;
	change.text = text;
	change.action = ORMSyncApplyToModel;
	change.possibleActions = @[ @(ORMSyncApplyToModel), @(ORMSyncDiscard) ];
	change.phase = 1;
	[_changes addObject:change];
	return change;
}

- (NSString *)mappingId
{
	return _mappingId;
}

- (void)findChanges
{
	for (ORMCDEntity *theirs in _theirs.entities) {
		ORMCDEntity *base = ORMMatchEntity(_base, theirs);
		ORMCDEntity *ours = ORMMatchEntity(_ours, theirs);
		/* Never written by the mapping, but the ORM model maps to it
		 * already: adopting a model made elsewhere. */
		ORMCDEntity *before = base ?: ours;
		if (before == nil) {
			if (![[self keptElements] containsObject:theirs.name]) {
				[self addedEntity:theirs];
			}
			continue;
		}
		if (![before.name isEqualToString:theirs.name]) {
			[self renamedEntity:before to:theirs ours:ours];
		}
		[self compareEntity:theirs before:before ours:ours];
	}
	for (ORMCDEntity *base in _base.entities) {
		if (ORMMatchEntity(_theirs, base) == nil && ORMMatchEntity(_ours, base) != nil) {
			[self deletedEntity:base];
		}
	}
}

- (NSSet *)keptElements
{
	return [[ORMCoreDataMapping mappingWithId:_mappingId inDocument:_editor.document] keptElements];
}

- (void)renamedEntity:(ORMCDEntity *)before to:(ORMCDEntity *)theirs ours:(ORMCDEntity *)ours
{
	ORMObjectType *type = [self objectTypeOf:theirs];
	NSString *source = theirs.source ?: before.source;
	NSString *name = theirs.name;
	ORMSyncChange *change = [self change:ORMSyncRenameEntity path:theirs.name
	                                text:[NSString stringWithFormat:@"Entity %@ was renamed %@.", before.name, name]];
	change.conflicts = ours != nil && ![ours.name isEqualToString:before.name];
	change.possibleActions = @[ @(ORMSyncApplyToMapping), @(ORMSyncApplyToModel), @(ORMSyncDiscard) ];
	change.action = change.conflicts ? ORMSyncDiscard : ORMSyncApplyToMapping;
	ORMEditor *editor = _editor;
	NSString *mappingId = _mappingId;
	change.toMapping = ^{
		[editor setName:name forSource:source inMapping:mappingId];
	};
	change.toModel = ^{
		if (type != nil && [editor rename:type.identifier to:name reason:NULL]) {
			[editor setName:nil forSource:source inMapping:mappingId];
		}
	};
}

- (void)deletedEntity:(ORMCDEntity *)base
{
	ORMObjectType *type = [self objectTypeOf:base];
	ORMSyncChange *change = [self change:ORMSyncDeleteEntity path:base.name
	                                text:[NSString stringWithFormat:@"Entity %@ was deleted.", base.name]];
	change.possibleActions = @[ @(ORMSyncApplyToMapping), @(ORMSyncApplyToModel), @(ORMSyncDiscard) ];
	change.action = ORMSyncApplyToMapping;
	ORMEditor *editor = _editor;
	NSString *mappingId = _mappingId;
	NSString *source = base.source;
	change.toMapping = ^{
		if (type != nil) {
			[editor setMapping:ORMMapIgnored ofObjectType:type.identifier inMapping:mappingId];
		} else if (source != nil) {
			[editor setExcluded:YES source:source inMapping:mappingId];
		}
	};
	change.toModel = ^{
		if (source != nil) {
			[editor deleteElements:@[ source ]];
		}
	};
}

- (void)compareEntity:(ORMCDEntity *)theirs before:(ORMCDEntity *)before ours:(ORMCDEntity *)ours
{
	for (ORMCDProperty *property in [theirs properties]) {
		ORMCDProperty *was = ORMMatchProperty(before, property);
		ORMCDProperty *now = ORMMatchProperty(ours, property);
		NSString *path = [NSString stringWithFormat:@"%@.%@", theirs.name, property.name];
		if (was == nil) {
			was = now;
		}
		if (was == nil) {
			if (![[self keptElements] containsObject:path]) {
				[self addedProperty:property to:theirs];
			}
			continue;
		}
		[self compareProperty:property was:was ours:now entity:theirs];
	}
	for (ORMCDProperty *property in [before properties]) {
		if (ORMMatchProperty(theirs, property) == nil && ORMMatchProperty(ours, property) != nil) {
			[self deletedProperty:property of:before];
		}
	}
	[self compareUniqueness:theirs before:before];
}

- (void)compareProperty:(ORMCDProperty *)theirs was:(ORMCDProperty *)was ours:(ORMCDProperty *)ours
                 entity:(ORMCDEntity *)entity
{
	NSString *path = [NSString stringWithFormat:@"%@.%@", entity.name, theirs.name];
	ORMRole *near = [self nearRoleOf:was];
	ORMRole *far = [self farRoleOf:was];
	ORMEditor *editor = _editor;
	NSString *mappingId = _mappingId;
	NSString *source = theirs.source ?: was.source;
	if (![theirs.name isEqualToString:was.name]) {
		NSString *name = theirs.name;
		ORMSyncChange *change = [self change:ORMSyncRenameProperty path:path
		                                text:[NSString stringWithFormat:@"%@.%@ was renamed %@.", entity.name,
		                                                                was.name, name]];
		change.conflicts = ours != nil && ![ours.name isEqualToString:was.name];
		change.possibleActions = @[ @(ORMSyncApplyToMapping), @(ORMSyncApplyToModel), @(ORMSyncDiscard) ];
		change.action = change.conflicts ? ORMSyncDiscard : ORMSyncApplyToMapping;
		change.toMapping = ^{
			[editor setName:name forSource:source inMapping:mappingId];
		};
		/* Into the model, as the role's name, which the mapping prefers. */
		change.toModel = ^{
			if (far != nil && [editor rename:far.identifier to:name reason:NULL]) {
				[editor setName:nil forSource:source inMapping:mappingId];
			}
		};
	}
	if (theirs.optional != was.optional && near != nil) {
		BOOL mandatory = !theirs.optional;
		/* The mapping's own loosening is not the user's doing. */
		BOOL loosened = [[was.userInfo objectForKey:@"ormkit.mandatory"] isEqualToString:@"YES"];
		if (!loosened) {
			ORMSyncChange *change = [self change:ORMSyncOptionality path:path
			                                text:[NSString stringWithFormat:@"%@ was made %@.", path,
			                                                                mandatory ? @"required" : @"optional"]];
			change.conflicts = ours != nil && ours.optional != was.optional;
			change.action = change.conflicts ? ORMSyncDiscard : ORMSyncApplyToModel;
			change.toModel = ^{
				[editor setMandatory:mandatory role:near.identifier reason:NULL];
			};
		}
	}
	if ([theirs isKindOfClass:[ORMCDRelationship class]] && near != nil) {
		ORMCDRelationship *relationship = (ORMCDRelationship *)theirs;
		if (relationship.toMany != [(ORMCDRelationship *)was toMany]) {
			BOOL unique = !relationship.toMany;
			ORMSyncChange *change = [self change:ORMSyncCardinality path:path
			                                text:[NSString stringWithFormat:@"%@ was made %@.", path,
			                                                                unique ? @"to-one" : @"to-many"]];
			change.toModel = ^{
				[editor setUnique:unique role:near.identifier reason:NULL];
			};
		}
	}
	if ([theirs isKindOfClass:[ORMCDAttribute class]] && far != nil) {
		ORMCDAttribute *attribute = (ORMCDAttribute *)theirs;
		ORMCDAttribute *old = (ORMCDAttribute *)was;
		ORMObjectType *valueType = far.player.kind == ORMValueType ? far.player : far.player.referenceModeValueType;
		if (![attribute.attributeType isEqualToString:old.attributeType] && valueType != nil) {
			NSString *dataType = ORMDataTypeForAttributeType(attribute.attributeType);
			NSUInteger uses = [valueType.playedRoles count];
			ORMSyncChange *change = [self change:ORMSyncAttributeType path:path
			                                text:[NSString stringWithFormat:@"%@ became %@%@.", path,
			                                                                attribute.attributeType,
			                                                                uses > 1 ? [NSString stringWithFormat:@" (%@ is used %lu times)",
			                                                                                                    valueType.name, (unsigned long)uses]
			                                                                         : @""]];
			change.toModel = ^{
				[editor setDataType:dataType length:0 scale:0 of:valueType.identifier reason:NULL];
			};
		}
		BOOL bounds = ![attribute.minValue ?: @"" isEqualToString:old.minValue ?: @""]
			|| ![attribute.maxValue ?: @"" isEqualToString:old.maxValue ?: @""]
			|| ![attribute.regularExpression ?: @"" isEqualToString:old.regularExpression ?: @""];
		NSString *values = [self valueConstraintFor:attribute];
		if (bounds && values != nil) {
			ORMSyncChange *change = [self change:ORMSyncValueBounds path:path
			                                text:[NSString stringWithFormat:@"%@ now allows %@.", path,
			                                                                [values length] > 0 ? values : @"any value"]];
			NSString *target = valueType != nil && [valueType.playedRoles count] == 1 ? valueType.identifier
			                                                                           : far.identifier;
			change.toModel = ^{
				[editor setValueConstraint:values of:target reason:NULL];
			};
		}
	}
}

/* An attribute's bounds as a value constraint: "{1..10}", "{'M', 'F'}";
 * nil when they say more than one can (a pattern of any other shape). */
- (NSString *)valueConstraintFor:(ORMCDAttribute *)attribute
{
	if ([attribute.regularExpression length] > 0) {
		NSString *pattern = attribute.regularExpression;
		if (![pattern hasPrefix:@"^(?:"] || ![pattern hasSuffix:@")$"]) {
			return nil;
		}
		NSString *inner = [pattern substringWithRange:NSMakeRange(4, [pattern length] - 6)];
		NSMutableArray *values = [NSMutableArray array];
		for (NSString *alternative in [inner componentsSeparatedByString:@"|"]) {
			NSString *plain = [alternative stringByReplacingOccurrencesOfString:@"\\" withString:@""];
			[values addObject:[NSString stringWithFormat:@"'%@'", [plain stringByReplacingOccurrencesOfString:@"'"
			                                                                                      withString:@"''"]]];
		}
		return [NSString stringWithFormat:@"{%@}", [values componentsJoinedByString:@", "]];
	}
	if ([attribute.attributeType isEqualToString:@"String"]) {
		/* A string's bounds are its length, a data type's business. */
		return nil;
	}
	if ([attribute.minValue length] == 0 && [attribute.maxValue length] == 0) {
		return @"";
	}
	return [NSString stringWithFormat:@"{%@..%@}", attribute.minValue ?: @"", attribute.maxValue ?: @""];
}

- (void)deletedProperty:(ORMCDProperty *)property of:(ORMCDEntity *)entity
{
	NSString *path = [NSString stringWithFormat:@"%@.%@", entity.name, property.name];
	ORMRole *far = [self farRoleOf:property];
	ORMSyncChange *change = [self change:ORMSyncDeleteProperty path:path
	                                text:[NSString stringWithFormat:@"%@ was deleted.", path]];
	change.possibleActions = @[ @(ORMSyncApplyToMapping), @(ORMSyncApplyToModel), @(ORMSyncDiscard) ];
	change.action = ORMSyncApplyToMapping;
	ORMEditor *editor = _editor;
	NSString *mappingId = _mappingId;
	NSString *source = property.source;
	change.toMapping = ^{
		if (source != nil) {
			[editor setExcluded:YES source:source inMapping:mappingId];
		}
	};
	change.toModel = ^{
		if (far != nil) {
			[editor deleteElements:@[ far.factType.identifier ]];
		}
	};
}

/* The sources a list of property names stands for, on an entity: a
 * property's own, or that of the property it matches in the entity it is
 * compared with (an adopted model's properties have none). */
static NSArray *
ORMSourcesOf(ORMCDEntity *entity, NSArray *names, ORMCDEntity *compared)
{
	NSMutableArray *sources = [NSMutableArray array];
	for (NSString *name in names) {
		ORMCDProperty *property = [entity propertyNamed:name];
		NSString *source = property.source ?: ORMMatchProperty(compared, property).source;
		[sources addObject:source ?: [@"?" stringByAppendingString:name]];
	}
	return sources;
}

- (void)compareUniqueness:(ORMCDEntity *)theirs before:(ORMCDEntity *)before
{
	NSMutableSet *was = [NSMutableSet set];
	for (NSArray *names in before.uniquenessConstraints) {
		[was addObject:[NSSet setWithArray:ORMSourcesOf(before, names, nil)]];
	}
	NSMutableSet *now = [NSMutableSet set];
	for (NSArray *names in theirs.uniquenessConstraints) {
		[now addObject:[NSSet setWithArray:ORMSourcesOf(theirs, names, before)]];
	}
	ORMEditor *editor = _editor;
	for (NSSet *sources in now) {
		if ([was containsObject:sources]) {
			continue;
		}
		NSMutableArray *roles = [NSMutableArray array];
		for (NSString *source in sources) {
			id role = [editor.model elementWithId:source];
			if ([role isKindOfClass:[ORMRole class]]) {
				[roles addObject:[role identifier]];
			}
		}
		if ([roles count] != [sources count]) {
			continue;
		}
		ORMSyncChange *change = [self change:ORMSyncAddUniqueness path:theirs.name
		                                text:[NSString stringWithFormat:@"%@ was made unique over %@.", theirs.name,
		                                                                [[sources allObjects] count] == 1 ? @"one property"
		                                                                                                  : @"several properties"]];
		change.toModel = ^{
			if ([roles count] == 1) {
				[editor setUnique:YES role:[roles firstObject] reason:NULL];
			} else {
				[editor addUniquenessConstraintOverRoles:roles reason:NULL];
			}
		};
	}
	for (NSSet *sources in was) {
		if ([now containsObject:sources]) {
			continue;
		}
		ORMSyncChange *change = [self change:ORMSyncRemoveUniqueness path:theirs.name
		                                text:[NSString stringWithFormat:@"A uniqueness constraint of %@ was removed.",
		                                                                theirs.name]];
		change.toModel = ^{
			ORMModel *model = editor.model;
			NSMutableSet *roles = [NSMutableSet set];
			for (NSString *source in sources) {
				id role = [model elementWithId:source];
				if (role != nil) {
					[roles addObject:role];
				}
			}
			for (ORMConstraint *constraint in model.constraints) {
				if (constraint.kind == ORMUniquenessConstraint && constraint.preferredIdentifierFor == nil
				    && [[NSSet setWithArray:[constraint allRoles]] isEqualToSet:roles]) {
					[editor deleteElements:@[ constraint.identifier ]];
					break;
				}
			}
		};
	}
}

#pragma mark Additions

/* The diagram showing the object type, for placing what is added beside it. */
- (NSString *)diagramShowing:(NSString *)objectTypeId
{
	for (ORMDiagram *diagram in _editor.model.diagrams) {
		if ([diagram shapeForSubject:objectTypeId] != nil) {
			return diagram.identifier;
		}
	}
	return nil;
}

/* Adds to the ORM model a fact type for the attribute on the object type:
 * "X has V", functional on X, V's value type reused by name. */
- (void)addAttribute:(ORMCDAttribute *)attribute ofEntity:(ORMCDEntity *)entity toObjectType:(NSString *)objectTypeId
{
	ORMEditor *editor = _editor;
	NSString *valueName = [ORMCoreDataMapper entityNameFor:attribute.name];
	ORMObjectType *existing = [editor.model objectTypeNamed:valueName];
	NSString *valueId = nil;
	if (existing != nil && existing.kind == ORMValueType) {
		valueId = existing.identifier;
	} else {
		if (existing != nil) {
			valueName = [valueName stringByAppendingString:@"Value"];
		}
		valueId = [editor addValueTypeNamed:valueName dataType:ORMDataTypeForAttributeType(attribute.attributeType)
		                          onDiagram:nil at:NSZeroPoint reason:NULL];
	}
	if (valueId == nil) {
		return;
	}
	NSString *diagram = [self diagramShowing:objectTypeId];
	NSString *fact = [editor addFactTypeWithPlayers:@[ objectTypeId, valueId ] reading:@"{0} has {1}"
	                                      onDiagram:diagram at:ORMAutomaticPlacement reason:NULL];
	ORMFactType *made = [editor.model elementWithId:fact];
	ORMRole *near = [made.roles objectAtIndex:0];
	ORMRole *far = [made.roles objectAtIndex:1];
	[editor setUnique:YES role:near.identifier reason:NULL];
	if (!attribute.optional) {
		[editor setMandatory:YES role:near.identifier reason:NULL];
	}
	for (NSArray *names in entity.uniquenessConstraints) {
		if ([names isEqualToArray:@[ attribute.name ]]) {
			[editor setUnique:YES role:far.identifier reason:NULL];
		}
	}
	NSString *values = [self valueConstraintFor:attribute];
	if ([values length] > 0) {
		[editor setValueConstraint:values of:valueId reason:NULL];
	}
	[editor setName:attribute.name forSource:far.identifier inMapping:_mappingId];
}

/* Adds a binary fact type between the two object types for a relationship
 * and its inverse, unique on each to-one side. */
- (void)addRelationship:(ORMCDRelationship *)relationship
                inverse:(ORMCDRelationship *)inverse
                   from:(NSString *)fromId
                     to:(NSString *)toId
{
	ORMEditor *editor = _editor;
	NSString *diagram = [self diagramShowing:fromId];
	NSString *fact = [editor addFactTypeWithPlayers:@[ fromId, toId ] reading:@"{0} has {1}" onDiagram:diagram
	                                             at:ORMAutomaticPlacement reason:NULL];
	ORMFactType *made = [editor.model elementWithId:fact];
	ORMRole *near = [made.roles objectAtIndex:0];
	ORMRole *far = [made.roles objectAtIndex:1];
	BOOL manyForward = relationship.toMany;
	BOOL manyBackward = inverse == nil || inverse.toMany;
	if (!manyForward) {
		[editor setUnique:YES role:near.identifier reason:NULL];
	}
	if (!manyBackward) {
		[editor setUnique:YES role:far.identifier reason:NULL];
	}
	if (manyForward && manyBackward) {
		[editor addUniquenessConstraintOverRoles:@[ near.identifier, far.identifier ] reason:NULL];
	}
	if (!relationship.optional) {
		[editor setMandatory:YES role:near.identifier reason:NULL];
	}
	if (inverse != nil && !inverse.optional) {
		[editor setMandatory:YES role:far.identifier reason:NULL];
	}
	[editor setName:relationship.name forSource:far.identifier inMapping:_mappingId];
	if (inverse != nil) {
		[editor setName:inverse.name forSource:near.identifier inMapping:_mappingId];
	}
}

/* The object type an entity of theirs stands for: its source's, or the
 * one an added entity of the same name became. */
- (NSString *)objectTypeIdFor:(NSString *)entityName
{
	ORMCDEntity *entity = [_theirs entityNamed:entityName];
	ORMObjectType *traced = [self objectTypeOf:entity];
	if (traced != nil) {
		return traced.identifier;
	}
	ORMCDEntity *mapped = [_ours entityNamed:entityName];
	traced = [self objectTypeOf:mapped];
	if (traced != nil) {
		return traced.identifier;
	}
	return [[_editor.model objectTypeNamed:entityName] identifier];
}

- (void)addedProperty:(ORMCDProperty *)property to:(ORMCDEntity *)entity
{
	NSString *path = [NSString stringWithFormat:@"%@.%@", entity.name, property.name];
	BOOL isRelationship = [property isKindOfClass:[ORMCDRelationship class]];
	ORMCDRelationship *relationship = isRelationship ? (ORMCDRelationship *)property : nil;
	ORMCDRelationship *inverse = nil;
	if (relationship != nil) {
		inverse = [[_theirs entityNamed:relationship.destination] relationshipNamed:relationship.inverseName];
		/* A pair is one fact type: proposed from one side only. */
		if (inverse != nil && [inverse.source length] == 0
		    && [[NSString stringWithFormat:@"%@.%@", relationship.destination, inverse.name] compare:path] == NSOrderedAscending) {
			return;
		}
	}
	ORMSyncChange *change = [self change:isRelationship ? ORMSyncAddRelationship : ORMSyncAddAttribute path:path
	                                text:[NSString stringWithFormat:@"%@ %@ was added.",
	                                                                isRelationship ? @"Relationship" : @"Attribute", path]];
	change.possibleActions = @[ @(ORMSyncApplyToModel), @(ORMSyncApplyToMapping), @(ORMSyncDiscard) ];
	ORMEditor *editor = _editor;
	NSString *mappingId = _mappingId;
	NSString *entityName = entity.name;
	change.toMapping = ^{
		[editor setKept:YES element:path inMapping:mappingId];
		if (inverse != nil) {
			[editor setKept:YES element:[NSString stringWithFormat:@"%@.%@", relationship.destination, inverse.name]
			      inMapping:mappingId];
		}
	};
	__weak ORMCoreDataSync *weakSelf = self;
	change.toModel = ^{
		ORMCoreDataSync *sync = weakSelf;
		NSString *from = [sync objectTypeIdFor:entityName];
		if (from == nil) {
			return;
		}
		if (relationship != nil) {
			NSString *to = [sync objectTypeIdFor:relationship.destination];
			if (to != nil) {
				[sync addRelationship:relationship inverse:inverse from:from to:to];
			}
		} else {
			[sync addAttribute:(ORMCDAttribute *)property ofEntity:entity toObjectType:from];
		}
	};
}

- (void)addedEntity:(ORMCDEntity *)entity
{
	ORMSyncChange *change = [self change:ORMSyncAddEntity path:entity.name
	                                text:[NSString stringWithFormat:@"Entity %@ was added, with %lu properties.",
	                                                                entity.name, (unsigned long)[[entity properties] count]]];
	change.possibleActions = @[ @(ORMSyncApplyToModel), @(ORMSyncApplyToMapping), @(ORMSyncDiscard) ];
	change.phase = 0;
	ORMEditor *editor = _editor;
	NSString *mappingId = _mappingId;
	change.toMapping = ^{
		[editor setKept:YES element:entity.name inMapping:mappingId];
	};
	/* The entity type first; its properties are added as changes of
	 * their own, after every added entity type exists. */
	change.toModel = ^{
		NSString *type = [editor addEntityTypeNamed:entity.name referenceMode:nil kind:ORMReferenceModeNone
		                                  onDiagram:[[editor.model.diagrams firstObject] identifier]
		                                         at:ORMAutomaticPlacement reason:NULL];
		if (type != nil && ![[ORMCoreDataMapper entityNameFor:entity.name] isEqualToString:entity.name]) {
			[editor setName:entity.name forSource:type inMapping:mappingId];
		}
	};
	for (ORMCDProperty *property in [entity properties]) {
		[self addedProperty:property to:entity];
	}
	if (entity.parentName != nil) {
		ORMSyncChange *subtype = [self change:ORMSyncAddEntity path:entity.name
		                                 text:[NSString stringWithFormat:@"%@ is a kind of %@.", entity.name,
		                                                                 entity.parentName]];
		subtype.phase = 2;
		__weak ORMCoreDataSync *weakSelf = self;
		NSString *parent = entity.parentName;
		subtype.toModel = ^{
			ORMCoreDataSync *sync = weakSelf;
			NSString *sub = [sync objectTypeIdFor:entity.name];
			NSString *sup = [sync objectTypeIdFor:parent];
			if (sub != nil && sup != nil) {
				[editor addSubtype:sub of:sup reason:NULL];
			}
		};
	}
}

#pragma mark Applying

/* The mapping's model with what Core Data has and ORM does not kept from
 * theirs: their classes, codegen and positions, fetch requests and
 * configurations, defaults and patterns ORM does not say, deletion rules
 * the user chose, and elements the user keeps. */
- (ORMCDModel *)merge:(ORMCDModel *)ours keeping:(NSSet *)kept
{
	ORMCDModel *result = [ours copy];
	if (_theirs == nil) {
		return result;
	}
	for (ORMCDEntity *entity in result.entities) {
		ORMCDEntity *theirs = ORMMatchEntity(_theirs, entity);
		ORMCDEntity *base = ORMMatchEntity(_base, entity);
		if (theirs == nil) {
			continue;
		}
		if (theirs.representedClassName != nil && ![theirs.representedClassName isEqualToString:theirs.name]) {
			entity.representedClassName = theirs.representedClassName;
		}
		if (base == nil || ![theirs.codeGenerationType ?: @"" isEqualToString:base.codeGenerationType ?: @""]) {
			entity.codeGenerationType = theirs.codeGenerationType;
		}
		NSMutableDictionary *extras = [entity.extraAttributes mutableCopy];
		[extras addEntriesFromDictionary:theirs.extraAttributes];
		entity.extraAttributes = extras;
		entity.extraElements = theirs.extraElements;
		entity.userInfo = [self userInfo:entity.userInfo keeping:theirs.userInfo];
		NSValue *position = [_theirs.positions objectForKey:theirs.name];
		if (position != nil) {
			[result.positions setObject:position forKey:entity.name];
		}
		for (ORMCDProperty *property in [entity properties]) {
			ORMCDProperty *theirProperty = ORMMatchProperty(theirs, property);
			ORMCDProperty *baseProperty = ORMMatchProperty(base, property);
			if (theirProperty == nil) {
				continue;
			}
			NSMutableDictionary *propertyExtras = [property.extraAttributes mutableCopy];
			[propertyExtras addEntriesFromDictionary:theirProperty.extraAttributes];
			property.extraAttributes = propertyExtras;
			property.userInfo = [self userInfo:property.userInfo keeping:theirProperty.userInfo];
			if ([property isKindOfClass:[ORMCDAttribute class]]) {
				ORMCDAttribute *attribute = (ORMCDAttribute *)property;
				ORMCDAttribute *theirAttribute = (ORMCDAttribute *)theirProperty;
				attribute.defaultValue = attribute.defaultValue ?: theirAttribute.defaultValue;
				attribute.regularExpression = attribute.regularExpression ?: theirAttribute.regularExpression;
				attribute.minValue = attribute.minValue ?: theirAttribute.minValue;
				attribute.maxValue = attribute.maxValue ?: theirAttribute.maxValue;
				attribute.allowsExternalStorage = attribute.allowsExternalStorage || theirAttribute.allowsExternalStorage;
			} else {
				ORMCDRelationship *relationship = (ORMCDRelationship *)property;
				ORMCDRelationship *theirRelationship = (ORMCDRelationship *)theirProperty;
				relationship.ordered = theirRelationship.ordered;
				ORMCDRelationship *baseRelationship = (ORMCDRelationship *)baseProperty;
				if (![theirRelationship.deletionRule isEqualToString:baseRelationship.deletionRule ?: relationship.deletionRule]) {
					relationship.deletionRule = theirRelationship.deletionRule;
				}
			}
		}
		/* Their own properties, kept. */
		for (ORMCDProperty *property in [theirs properties]) {
			NSString *path = [NSString stringWithFormat:@"%@.%@", theirs.name, property.name];
			if (ORMMatchProperty(entity, property) == nil && [kept containsObject:path]
			    && [entity propertyNamed:property.name] == nil) {
				if ([property isKindOfClass:[ORMCDAttribute class]]) {
					[entity.attributes addObject:[property copy]];
				} else {
					[entity.relationships addObject:[property copy]];
				}
			}
		}
	}
	for (ORMCDEntity *theirs in _theirs.entities) {
		if (ORMMatchEntity(result, theirs) == nil && [kept containsObject:theirs.name]) {
			[result.entities addObject:[theirs copy]];
			NSValue *position = [_theirs.positions objectForKey:theirs.name];
			if (position != nil) {
				[result.positions setObject:position forKey:theirs.name];
			}
		}
	}
	NSMutableDictionary *modelAttributes = [result.modelAttributes mutableCopy];
	[modelAttributes addEntriesFromDictionary:_theirs.modelAttributes];
	result.modelAttributes = modelAttributes;
	result.extraElements = _theirs.extraElements;
	return result;
}

/* The mapping's userInfo entries, with the user's own from theirs. */
- (NSDictionary *)userInfo:(NSDictionary *)ours keeping:(NSDictionary *)theirs
{
	NSMutableDictionary *merged = [ours mutableCopy];
	for (NSString *key in theirs) {
		if (![key hasPrefix:@"ormkit."]) {
			[merged setObject:[theirs objectForKey:key] forKey:key];
		}
	}
	return merged;
}

- (ORMCDModel *)apply
{
	__block ORMCDModel *result = nil;
	ORMEditor *editor = _editor;
	NSString *mappingId = _mappingId;
	NSArray *changes = [_changes copy];
	[editor group:@"Synchronize Core Data" with:^{
		for (NSUInteger phase = 0; phase <= 2; phase++) {
			for (ORMSyncChange *change in changes) {
				if (change.phase != phase) {
					continue;
				}
				if (change.action == ORMSyncApplyToModel && change.toModel != nil) {
					change.toModel();
				} else if (change.action == ORMSyncApplyToMapping && change.toMapping != nil) {
					change.toMapping();
				}
			}
		}
		ORMCoreDataMapping *mapping = [ORMCoreDataMapping mappingWithId:mappingId inDocument:editor.document];
		ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:editor.model mapping:mapping];
		self->_ours = [mapper map];
		self->_notes = mapper.notes;
		result = [self merge:self->_ours keeping:mapping.keptElements];
		[editor setBaseline:result ofMapping:mappingId];
	}];
	return result;
}

@end
