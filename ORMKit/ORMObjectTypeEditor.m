/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMValueConstraintParser.h"

/* The data type a new reference mode's value type gets: counters for
 * ids, numbers for numbers, text for names and codes, decimals for units. */
static NSString *
ORMDefaultDataTypeForMode(NSString *mode, ORMReferenceModeKind kind)
{
	if (kind == ORMReferenceModeUnitBased) {
		return @"DecimalNumericDataType";
	}
	NSString *lower = [mode lowercaseString];
	if ([lower isEqualToString:@"id"]) {
		return @"AutoCounterNumericDataType";
	}
	if ([lower isEqualToString:@"nr"] || [lower isEqualToString:@"#"] || [lower isEqualToString:@"number"]) {
		return @"UnsignedIntegerNumericDataType";
	}
	return @"VariableLengthTextDataType";
}

/* The value type's name for the mode, by its kind's format. */
@implementation ORMObjectTypeEditor

@synthesize editor = _editor;

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

/* The name of the value type a reference mode is kept by, as the model's
 * reference mode kinds format it: "Person_id" ({0}_{1}) in files NORMA
 * writes now, "Person id" ({0} {1}) in older ones, "cmValue", "ISBN". */
- (NSString *)valueTypeNameFor:(NSString *)entity mode:(NSString *)mode kind:(ORMReferenceModeKind)kind
{
	NSString *type = kind == ORMReferenceModeUnitBased ? @"UnitBased" : kind == ORMReferenceModeGeneral ? @"General" : @"Popular";
	NSString *format = kind == ORMReferenceModeUnitBased ? @"{1}Value" : kind == ORMReferenceModeGeneral ? @"{1}" : @"{0}_{1}";
	for (NSXMLElement *kindElement in ORMGrandchildren(_editor.model.modelElement, ORMCoreNamespace, @"ReferenceModeKinds",
	                                                   ORMCoreNamespace, @"ReferenceModeKind")) {
		NSString *saved = ORMAttribute(kindElement, @"FormatString");
		if ([ORMAttribute(kindElement, @"ReferenceModeType") isEqualToString:type]
		    && [saved rangeOfString:@"{1}"].location != NSNotFound) {
			format = saved;
		}
	}
	format = [format stringByReplacingOccurrencesOfString:@"{0}" withString:entity ?: @""];
	return [format stringByReplacingOccurrencesOfString:@"{1}" withString:mode ?: @""];
}

- (BOOL)checkName:(NSString *)name except:(NSString *)elementId reason:(NSString **)reason
{
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed length] == 0) {
		if (reason != NULL) {
			*reason = @"An object type needs a name.";
		}
		return NO;
	}
	ORMObjectType *existing = [_editor.model objectTypeNamed:trimmed];
	if (existing != nil && ![existing.identifier isEqualToString:elementId]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"The model already has an object type named '%@'.", trimmed];
		}
		return NO;
	}
	return YES;
}

/* The model's data type of the name, made when it has none. */
- (ORMDataType *)dataTypeNamed:(NSString *)typeName
{
	for (ORMDataType *type in _editor.model.dataTypes) {
		if ([type.typeName isEqualToString:typeName]) {
			return type;
		}
	}
	ORMDataType *made = [[ORMDataType alloc] initWithModel:_editor.model];
	made.typeName = typeName;
	[_editor.model addElement:made];
	[_editor wrote:made];
	return made;
}

/* A new <orm:ValueType>, its data type set. */
- (NSXMLElement *)newValueTypeNamed:(NSString *)name dataType:(NSString *)typeName
{
	NSXMLElement *type = ORMNewElementWithId(_editor.document, CORE, @"ValueType", nil);
	ORMSetAttribute(type, @"Name", name);
	NSXMLElement *dataType = ORMNewElementWithId(_editor.document, CORE, @"ConceptualDataType", nil);
	ORMSetAttribute(dataType, @"ref", [_editor dataTypeIdNamed:typeName ?: @"UnspecifiedDataType"]);
	ORMSetAttribute(dataType, @"Scale", @"0");
	ORMSetAttribute(dataType, @"Length", @"0");
	ORMInsertChild(type, dataType);
	[[_editor section:@"Objects"] addChild:type];
	return type;
}

/* Gives the entity type its reference mode, as NORMA builds one: the
 * value type, "{0} has {1}" read back as "{0} is of {1}", the entity's
 * role unique and mandatory, the value's role unique and the preferred
 * identifier. */
- (void)buildReferenceMode:(NSString *)mode kind:(ORMReferenceModeKind)kind forEntity:(NSXMLElement *)entity
{
	NSString *entityName = ORMAttribute(entity, @"Name");
	NSString *valueName = [self valueTypeNameFor:entityName mode:mode kind:kind];
	/* A unit or general mode's value type is shared: kgValue identifies
	 * every entity type measured in kg. */
	NSXMLElement *value = nil;
	ORMObjectType *existing = [_editor.model objectTypeNamed:valueName];
	if (existing != nil && existing.kind == ORMValueType) {
		value = existing.element;
	} else {
		value = [self newValueTypeNamed:[_editor uniqueObjectTypeName:valueName]
		                       dataType:ORMDefaultDataTypeForMode(mode, kind)];
	}
	NSMutableArray *roles = [NSMutableArray array];
	NSXMLElement *fact = [_editor.factTypeEditor newFactWithPlayers:@[ ORMAttribute(entity, @"id"), ORMAttribute(value, @"id") ]
	                                      reading:@"{0} has {1}"
	                                        roles:roles];
	[_editor.factTypeEditor appendReading:@"{0} is of {1}" to:fact roles:@[ [roles objectAtIndex:1], [roles objectAtIndex:0] ]];
	[_editor.constraintEditor newInternalUniqueness:@[ [roles objectAtIndex:0] ]];
	[_editor.constraintEditor newSimpleMandatory:[roles objectAtIndex:0]];
	NSXMLElement *identifier = [_editor.constraintEditor newInternalUniqueness:@[ [roles objectAtIndex:1] ]];
	[ORMChild(entity, CORE, @"PreferredIdentifier") detach];
	ORMInsertChild(entity, ORMNewRef(_editor.document, CORE, @"PreferredIdentifier", ORMAttribute(identifier, @"id")));
	ORMSetAttribute(entity, @"_ReferenceMode", mode);
	[self registerCustomReferenceMode:mode kind:kind];
}

/* A mode NORMA does not know gets a custom reference mode of its kind,
 * so NORMA reads the value type's name back as this mode. */
- (void)registerCustomReferenceMode:(NSString *)mode kind:(ORMReferenceModeKind)kind
{
	if (kind == ORMReferenceModePopular) {
		return;
	}
	NSString *kindName = kind == ORMReferenceModeUnitBased ? @"UnitBased" : @"General";
	NSXMLElement *modes = ORMChild(ORMModelElementOfDocument(_editor.document), CORE, @"CustomReferenceModes");
	for (NSXMLElement *custom in ORMChildren(modes, CORE, @"CustomReferenceMode")) {
		if ([ORMAttribute(custom, @"Name") isEqualToString:mode]) {
			return;
		}
	}
	NSString *kindId = nil;
	for (NSXMLElement *element in ORMChildren([_editor section:@"ReferenceModeKinds"], CORE, @"ReferenceModeKind")) {
		if ([ORMAttribute(element, @"ReferenceModeType") isEqualToString:kindName]) {
			kindId = ORMAttribute(element, @"id");
		}
	}
	if (kindId == nil) {
		NSXMLElement *element = ORMNewElementWithId(_editor.document, CORE, @"ReferenceModeKind", nil);
		ORMSetAttribute(element, @"FormatString", kind == ORMReferenceModeUnitBased ? @"{1}Value" : @"{1}");
		ORMSetAttribute(element, @"ReferenceModeType", kindName);
		[[_editor section:@"ReferenceModeKinds"] addChild:element];
		kindId = ORMAttribute(element, @"id");
	}
	NSXMLElement *custom = ORMNewElementWithId(_editor.document, CORE, @"CustomReferenceMode", nil);
	ORMSetAttribute(custom, @"Name", mode);
	[custom addChild:ORMNewRef(_editor.document, CORE, @"Kind", kindId)];
	[[_editor section:@"CustomReferenceModes"] addChild:custom];
}

- (NSString *)addEntityTypeNamed:(NSString *)name
                   referenceMode:(NSString *)mode
                            kind:(ORMReferenceModeKind)kind
                       onDiagram:(NSString *)diagramId
                              at:(NSPoint)point
                          reason:(NSString **)reason
{
	if (![self checkName:name except:nil reason:reason]) {
		return nil;
	}
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	__block NSString *created = nil;
	[_editor group:@"Add Entity Type" with:^{
		[_editor change:@"Add Entity Type" with:^{
			NSXMLElement *entity = ORMNewElementWithId(_editor.document, CORE, @"EntityType", nil);
			ORMSetAttribute(entity, @"Name", trimmed);
			ORMSetAttribute(entity, @"_ReferenceMode", @"");
			[[_editor section:@"Objects"] addChild:entity];
			created = ORMAttribute(entity, @"id");
			if ([mode length] > 0 && kind != ORMReferenceModeNone) {
				[self buildReferenceMode:mode kind:kind forEntity:entity];
			}
		}];
		/* Placed once the projection knows the entity type. */
		if (diagramId != nil) {
			[_editor.diagramEditor placeElement:created onDiagram:diagramId at:point];
		}
	}];
	return created;
}

- (NSString *)addValueTypeNamed:(NSString *)name
                       dataType:(NSString *)typeName
                      onDiagram:(NSString *)diagramId
                             at:(NSPoint)point
                         reason:(NSString **)reason
{
	if (![self checkName:name except:nil reason:reason]) {
		return nil;
	}
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	__block NSString *created = nil;
	[_editor group:@"Add Value Type" with:^{
		[_editor change:@"Add Value Type" with:^{
			created = ORMAttribute([self newValueTypeNamed:trimmed dataType:typeName], @"id");
		}];
		if (diagramId != nil) {
			[_editor.diagramEditor placeElement:created onDiagram:diagramId at:point];
		}
	}];
	return created;
}

- (BOOL)setReferenceMode:(NSString *)mode
                    kind:(ORMReferenceModeKind)kind
                ofEntity:(NSString *)entityId
                  reason:(NSString **)reason
{
	ORMObjectType *entity = [_editor.model elementWithId:entityId];
	if (![entity isKindOfClass:[ORMObjectType class]] || !entity.isEntity) {
		if (reason != NULL) {
			*reason = @"Only an entity type has a reference mode.";
		}
		return NO;
	}
	NSString *trimmed = [mode stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed hasPrefix:@"."]) {
		trimmed = [trimmed substringFromIndex:1];
		kind = ORMReferenceModePopular;
	} else if ([trimmed hasSuffix:@":"]) {
		trimmed = [trimmed substringToIndex:[trimmed length] - 1];
		kind = ORMReferenceModeUnitBased;
	}
	BOOL removing = [trimmed length] == 0 || kind == ORMReferenceModeNone;
	if (!removing && [trimmed isEqualToString:entity.referenceMode] && kind == entity.referenceModeKind) {
		return YES;
	}
	if (!removing) {
		NSString *valueName = [self valueTypeNameFor:entity.name mode:trimmed kind:kind];
		ORMObjectType *clash = [_editor.model objectTypeNamed:valueName];
		if (clash != nil && (clash.kind != ORMValueType || kind == ORMReferenceModePopular)
		    && clash != entity.referenceModeValueType) {
			if (reason != NULL) {
				*reason = [NSString stringWithFormat:@"'%@' is already an object type of the model.", valueName];
			}
			return NO;
		}
	}
	/* A popular mode's value type is renamed in place: what it plays and
	 * its constraints stay. Otherwise the old identification goes. */
	ORMObjectType *oldValue = entity.referenceModeValueType;
	ORMFactType *oldFact = entity.referenceModeFactType;
	[_editor change:removing ? @"Remove Reference Mode" : @"Set Reference Mode" with:^{
		if (removing) {
			ORMSetAttribute(entity.element, @"_ReferenceMode", @"");
			return;
		}
		if (oldValue != nil && entity.referenceModeKind == ORMReferenceModePopular && kind == ORMReferenceModePopular
		    && [oldValue.playedRoles count] == 1) {
			ORMSetAttribute(oldValue.element, @"Name",
			                [self valueTypeNameFor:entity.name mode:trimmed kind:ORMReferenceModePopular]);
			ORMSetAttribute(entity.element, @"_ReferenceMode", trimmed);
			return;
		}
		if (oldFact != nil) {
			[_editor.elementEditor deleteElements:@[ oldFact.identifier ]];
			if (oldValue != nil && [oldValue.playedRoles count] <= 1) {
				[_editor.elementEditor deleteElements:@[ oldValue.identifier ]];
			}
		}
		[self buildReferenceMode:trimmed kind:kind forEntity:[_editor xml:entityId]];
	}];
	return YES;
}

- (BOOL)setDataType:(NSString *)typeName
             length:(NSInteger)length
              scale:(NSInteger)scale
                 of:(NSString *)objectTypeId
             reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	if ([type isKindOfClass:[ORMObjectType class]] && type.isEntity) {
		type = type.referenceModeValueType;
	}
	if (![type isKindOfClass:[ORMObjectType class]] || type.kind != ORMValueType) {
		if (reason != NULL) {
			*reason = @"Only a value type, or an entity type with a reference mode, has a data type.";
		}
		return NO;
	}
	if (![[ORMDataType allTypeNames] containsObject:typeName]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"'%@' is not a data type.", typeName];
		}
		return NO;
	}
	[_editor modelChange:@"Set Data Type" with:^{
		type.dataType = [self dataTypeNamed:typeName];
		type.dataTypeScale = MAX(scale, (NSInteger)0);
		type.dataTypeLength = MAX(length, (NSInteger)0);
		[_editor wrote:type];
	}];
	return YES;
}

/* One of an object type's flags, by its property's key. */
- (BOOL)setFlag:(NSString *)key to:(BOOL)flag of:(NSString *)objectTypeId named:(NSString *)action
         reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	if (![type isKindOfClass:[ORMObjectType class]]) {
		if (reason != NULL) {
			*reason = @"Pick an object type.";
		}
		return NO;
	}
	if ([[type valueForKey:key] boolValue] == flag) {
		return YES;
	}
	[_editor modelChange:action with:^{
		[type setValue:@(flag) forKey:key];
		[_editor wrote:type];
	}];
	return YES;
}

- (BOOL)setIndependent:(BOOL)flag of:(NSString *)objectTypeId reason:(NSString **)reason
{
	return [self setFlag:@"isIndependent" to:flag of:objectTypeId named:@"Set Independent" reason:reason];
}

- (BOOL)setPersonal:(BOOL)flag of:(NSString *)objectTypeId reason:(NSString **)reason
{
	return [self setFlag:@"isPersonal" to:flag of:objectTypeId named:@"Set Personal" reason:reason];
}

- (BOOL)setExternal:(BOOL)flag of:(NSString *)objectTypeId reason:(NSString **)reason
{
	return [self setFlag:@"isExternal" to:flag of:objectTypeId named:@"Set External" reason:reason];
}

- (BOOL)setValueType:(BOOL)value of:(NSString *)objectTypeId reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	if (![type isKindOfClass:[ORMObjectType class]] || type.kind == ORMObjectifiedType) {
		if (reason != NULL) {
			*reason = @"Only entity and value types change kind; an objectified fact type stays an entity type.";
		}
		return NO;
	}
	if ((type.kind == ORMValueType) == value) {
		return YES;
	}
	if (value && (type.preferredIdentifier != nil || [type.subtypes count] > 0 || [type.supertypes count] > 0)) {
		if (reason != NULL) {
			*reason = @"An entity type with an identifier or subtypes cannot become a value type; remove them first.";
		}
		return NO;
	}
	[_editor modelChange:value ? @"Make Value Type" : @"Make Entity Type" with:^{
		if (value) {
			type.kind = ORMValueType;
			type.dataType = [self dataTypeNamed:@"UnspecifiedDataType"];
			type.savedReferenceMode = nil;
		} else {
			type.kind = ORMEntityType;
			type.dataType = nil;
			[_editor.model removeElement:type.ownValueConstraint];
			type.ownValueConstraint = nil;
			type.savedReferenceMode = @"";
		}
		type.dataTypeLength = type.dataTypeScale = 0;
		[_editor wrote:type];
	}];
	return YES;
}

- (BOOL)setValueConstraint:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason
{
	id target = [_editor.model elementWithId:elementId];
	if ([target isKindOfClass:[ORMObjectType class]] && [(ORMObjectType *)target isEntity]) {
		target = [(ORMObjectType *)target referenceModeValueType];
	}
	BOOL isRole = [target isKindOfClass:[ORMRole class]];
	if (!isRole && !([target isKindOfClass:[ORMObjectType class]] && [(ORMObjectType *)target kind] == ORMValueType)) {
		if (reason != NULL) {
			*reason = @"Values are constrained on a value type, an entity type's reference mode, or a role.";
		}
		return NO;
	}
	NSArray *ranges = nil;
	NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed length] > 0) {
		ranges = [ORMValueConstraintParser rangesFromString:trimmed reason:reason];
		if (ranges == nil) {
			return NO;
		}
	}
	[_editor modelChange:@"Set Value Constraint" with:^{
		[self setRanges:ranges of:target];
	}];
	return YES;
}

/* A value type's or a role's value constraint, its ranges those parsed
 * (ORMValueConstraintParser's): made when it has none, taken away when
 * there are none. */
- (void)setRanges:(NSArray<NSDictionary *> *)parsed of:(ORMElement *)owner
{
	BOOL isRole = [owner isKindOfClass:[ORMRole class]];
	ORMValueConstraint *values = isRole ? [(ORMRole *)owner valueConstraint] : [(ORMObjectType *)owner ownValueConstraint];
	ORMModel *model = _editor.model;
	if (parsed == nil) {
		[model removeElement:values];
		values = nil;
	} else if (values == nil) {
		values = [[ORMValueConstraint alloc] initWithModel:model];
		values.name = [_editor nextName:isRole ? @"RoleValueConstraint" : @"ValueTypeValueConstraint"];
		[model addElement:values];
	} else {
		for (ORMValueRange *range in values.ranges) {
			[model removeElement:range];
		}
	}
	NSMutableArray *ranges = [NSMutableArray array];
	for (NSDictionary *range in parsed) {
		ORMValueRange *made = [[ORMValueRange alloc] initWithModel:model];
		made.minValue = [range objectForKey:@"min"] ?: @"";
		made.maxValue = [range objectForKey:@"max"] ?: @"";
		made.minInclusion = ORMInclusionNamed([range objectForKey:@"minInclusion"]);
		made.maxInclusion = ORMInclusionNamed([range objectForKey:@"maxInclusion"]);
		made.constraint = values;
		[model addElement:made];
		[ranges addObject:made];
	}
	values.ranges = ranges;
	if (isRole) {
		[(ORMRole *)owner setValueConstraint:values];
	} else {
		[(ORMObjectType *)owner setOwnValueConstraint:values];
	}
	[_editor wrote:owner];
	[_editor wrote:values];
}

- (NSString *)addSubtype:(NSString *)subtypeId of:(NSString *)supertypeId reason:(NSString **)reason
{
	ORMObjectType *sub = [_editor.model elementWithId:subtypeId];
	ORMObjectType *sup = [_editor.model elementWithId:supertypeId];
	if (![sub isKindOfClass:[ORMObjectType class]] || ![sup isKindOfClass:[ORMObjectType class]]) {
		if (reason != NULL) {
			*reason = @"Subtyping connects two object types.";
		}
		return nil;
	}
	if (sub == sup || [sup isSubtypeOf:sub]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"%@ would be its own supertype.", sub.name];
		}
		return nil;
	}
	if ([sub.supertypes indexOfObjectIdenticalTo:sup] != NSNotFound) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"%@ is already a subtype of %@.", sub.name, sup.name];
		}
		return nil;
	}
	if (sub.isEntity != sup.isEntity) {
		if (reason != NULL) {
			*reason = @"An entity type subtypes entity types, and a value type value types.";
		}
		return nil;
	}
	__block NSString *created = nil;
	[_editor change:@"Add Subtype" with:^{
		NSXMLElement *fact = ORMNewElementWithId(_editor.document, CORE, @"SubtypeFact", nil);
		ORMSetAttribute(fact, @"_Name", [NSString stringWithFormat:@"%@IsSubtypeOf%@", sub.name, sup.name]);
		/* The first supertype identifies a subtype with no identifier. */
		if ([sub.supertypes count] == 0 && sub.preferredIdentifier == nil) {
			ORMSetAttribute(fact, @"PreferredIdentificationPath", @"true");
		}
		NSXMLElement *roles = ORMEnsureChild(_editor.document, fact, CORE, @"FactRoles");
		NSMutableArray *roleIds = [NSMutableArray array];
		for (NSArray *pair in @[ @[ @"SubtypeMetaRole", subtypeId ], @[ @"SupertypeMetaRole", supertypeId ] ]) {
			NSXMLElement *role = ORMNewElementWithId(_editor.document, CORE, [pair objectAtIndex:0], nil);
			ORMSetAttribute(role, @"_IsMandatory", @"false");
			ORMSetAttribute(role, @"_Multiplicity", @"Unspecified");
			ORMSetAttribute(role, @"Name", @"");
			[role addChild:ORMNewRef(_editor.document, CORE, @"RolePlayer", [pair objectAtIndex:1])];
			[roles addChild:role];
			[roleIds addObject:ORMAttribute(role, @"id")];
		}
		[[_editor section:@"Facts"] addChild:fact];
		/* Each subtype instance is exactly one supertype instance, and
		 * the other way round at most one. */
		[_editor.constraintEditor newSimpleMandatory:[roleIds firstObject]];
		[_editor.constraintEditor newInternalUniqueness:@[ [roleIds firstObject] ]];
		[_editor.constraintEditor newInternalUniqueness:@[ [roleIds lastObject] ]];
		created = ORMAttribute(fact, @"id");
	}];
	return created;
}

@end
