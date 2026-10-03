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
@implementation ORMEditor (ORMObjects)

/* The name of the value type a reference mode is kept by, as the model's
 * reference mode kinds format it: "Person_id" ({0}_{1}) in files NORMA
 * writes now, "Person id" ({0} {1}) in older ones, "cmValue", "ISBN". */
- (NSString *)valueTypeNameFor:(NSString *)entity mode:(NSString *)mode kind:(ORMReferenceModeKind)kind
{
	NSString *type = kind == ORMReferenceModeUnitBased ? @"UnitBased" : kind == ORMReferenceModeGeneral ? @"General" : @"Popular";
	NSString *format = kind == ORMReferenceModeUnitBased ? @"{1}Value" : kind == ORMReferenceModeGeneral ? @"{1}" : @"{0}_{1}";
	for (NSXMLElement *kindElement in ORMGrandchildren(self.model.modelElement, ORMCoreNamespace, @"ReferenceModeKinds",
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
	ORMObjectType *existing = [self.model objectTypeNamed:trimmed];
	if (existing != nil && ![existing.identifier isEqualToString:elementId]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"The model already has an object type named '%@'.", trimmed];
		}
		return NO;
	}
	return YES;
}

/* A new <orm:ValueType>, its data type set. */
- (NSXMLElement *)newValueTypeNamed:(NSString *)name dataType:(NSString *)typeName
{
	NSXMLElement *type = ORMNewElementWithId(self.document, CORE, @"ValueType", nil);
	ORMSetAttribute(type, @"Name", name);
	NSXMLElement *dataType = ORMNewElementWithId(self.document, CORE, @"ConceptualDataType", nil);
	ORMSetAttribute(dataType, @"ref", [self dataTypeIdNamed:typeName ?: @"UnspecifiedDataType"]);
	ORMSetAttribute(dataType, @"Scale", @"0");
	ORMSetAttribute(dataType, @"Length", @"0");
	ORMInsertChild(type, dataType);
	[[self section:@"Objects"] addChild:type];
	return type;
}

/* A new <orm:Fact> over the players with one reading, roles' ids out. */
- (NSXMLElement *)newFactWithPlayers:(NSArray<NSString *> *)playerIds
                             reading:(NSString *)reading
                               roles:(NSMutableArray *)roleIds
{
	NSXMLElement *fact = ORMNewElementWithId(self.document, CORE, @"Fact", nil);
	NSXMLElement *roles = ORMEnsureChild(self.document, fact, CORE, @"FactRoles");
	for (NSString *playerId in playerIds) {
		NSXMLElement *role = ORMNewElementWithId(self.document, CORE, @"Role", nil);
		ORMSetAttribute(role, @"_IsMandatory", @"false");
		ORMSetAttribute(role, @"_Multiplicity", @"Unspecified");
		ORMSetAttribute(role, @"Name", @"");
		[role addChild:ORMNewRef(self.document, CORE, @"RolePlayer", playerId)];
		[roles addChild:role];
		[roleIds addObject:ORMAttribute(role, @"id")];
	}
	[[self section:@"Facts"] addChild:fact];
	if (reading != nil) {
		NSUInteger readable = [playerIds count];
		/* A unary's reading names its one role, not the implicit one. */
		if (readable == 2 && [reading rangeOfString:@"{1}"].location == NSNotFound) {
			readable = 1;
		}
		[self appendReading:reading to:fact roles:[roleIds subarrayWithRange:NSMakeRange(0, readable)]];
	}
	return fact;
}

/* A reading in the reading order for the roles, making the order. */
- (NSXMLElement *)appendReading:(NSString *)text to:(NSXMLElement *)fact roles:(NSArray<NSString *> *)roleIds
{
	NSXMLElement *orders = ORMEnsureChild(self.document, fact, CORE, @"ReadingOrders");
	NSXMLElement *order = nil;
	for (NSXMLElement *existing in ORMChildren(orders, CORE, @"ReadingOrder")) {
		NSMutableArray *refs = [NSMutableArray array];
		for (NSXMLElement *ref in ORMChildren(ORMChild(existing, CORE, @"RoleSequence"), CORE, @"Role")) {
			[refs addObject:ORMRef(ref) ?: @""];
		}
		if ([refs isEqualToArray:roleIds]) {
			order = existing;
			break;
		}
	}
	if (order == nil) {
		order = ORMNewElementWithId(self.document, CORE, @"ReadingOrder", nil);
		[order addChild:ORMNewElement(self.document, CORE, @"Readings")];
		NSXMLElement *sequence = ORMNewElement(self.document, CORE, @"RoleSequence");
		for (NSString *roleId in roleIds) {
			[sequence addChild:ORMNewRef(self.document, CORE, @"Role", roleId)];
		}
		[order addChild:sequence];
		[orders addChild:order];
	}
	NSXMLElement *reading = ORMNewElementWithId(self.document, CORE, @"Reading", nil);
	NSXMLElement *data = ORMNewElement(self.document, CORE, @"Data");
	[data setStringValue:text];
	[reading addChild:data];
	[ORMChild(order, CORE, @"Readings") addChild:reading];
	return reading;
}

/* An internal constraint over the roles: uniqueness or simple mandatory. */
- (NSXMLElement *)newInternalUniqueness:(NSArray<NSString *> *)roleIds
{
	NSXMLElement *constraint = [self newConstraint:@"UniquenessConstraint" named:@"InternalUniquenessConstraint"];
	ORMSetAttribute(constraint, @"IsInternal", @"true");
	[constraint addChild:[self newRoleSequence:roleIds withId:NO]];
	return constraint;
}

- (NSXMLElement *)newSimpleMandatory:(NSString *)roleId
{
	NSXMLElement *constraint = [self newConstraint:@"MandatoryConstraint" named:@"SimpleMandatoryConstraint"];
	ORMSetAttribute(constraint, @"IsSimple", @"true");
	[constraint addChild:[self newRoleSequence:@[ roleId ] withId:NO]];
	return constraint;
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
	ORMObjectType *existing = [self.model objectTypeNamed:valueName];
	if (existing != nil && existing.kind == ORMValueType) {
		value = existing.element;
	} else {
		value = [self newValueTypeNamed:[self uniqueObjectTypeName:valueName]
		                       dataType:ORMDefaultDataTypeForMode(mode, kind)];
	}
	NSMutableArray *roles = [NSMutableArray array];
	NSXMLElement *fact = [self newFactWithPlayers:@[ ORMAttribute(entity, @"id"), ORMAttribute(value, @"id") ]
	                                      reading:@"{0} has {1}"
	                                        roles:roles];
	[self appendReading:@"{0} is of {1}" to:fact roles:@[ [roles objectAtIndex:1], [roles objectAtIndex:0] ]];
	[self newInternalUniqueness:@[ [roles objectAtIndex:0] ]];
	[self newSimpleMandatory:[roles objectAtIndex:0]];
	NSXMLElement *identifier = [self newInternalUniqueness:@[ [roles objectAtIndex:1] ]];
	[ORMChild(entity, CORE, @"PreferredIdentifier") detach];
	ORMInsertChild(entity, ORMNewRef(self.document, CORE, @"PreferredIdentifier", ORMAttribute(identifier, @"id")));
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
	NSXMLElement *modes = ORMChild(ORMModelElementOfDocument(self.document), CORE, @"CustomReferenceModes");
	for (NSXMLElement *custom in ORMChildren(modes, CORE, @"CustomReferenceMode")) {
		if ([ORMAttribute(custom, @"Name") isEqualToString:mode]) {
			return;
		}
	}
	NSString *kindId = nil;
	for (NSXMLElement *element in ORMChildren([self section:@"ReferenceModeKinds"], CORE, @"ReferenceModeKind")) {
		if ([ORMAttribute(element, @"ReferenceModeType") isEqualToString:kindName]) {
			kindId = ORMAttribute(element, @"id");
		}
	}
	if (kindId == nil) {
		NSXMLElement *element = ORMNewElementWithId(self.document, CORE, @"ReferenceModeKind", nil);
		ORMSetAttribute(element, @"FormatString", kind == ORMReferenceModeUnitBased ? @"{1}Value" : @"{1}");
		ORMSetAttribute(element, @"ReferenceModeType", kindName);
		[[self section:@"ReferenceModeKinds"] addChild:element];
		kindId = ORMAttribute(element, @"id");
	}
	NSXMLElement *custom = ORMNewElementWithId(self.document, CORE, @"CustomReferenceMode", nil);
	ORMSetAttribute(custom, @"Name", mode);
	[custom addChild:ORMNewRef(self.document, CORE, @"Kind", kindId)];
	[[self section:@"CustomReferenceModes"] addChild:custom];
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
	[self group:@"Add Entity Type" with:^{
		[self change:@"Add Entity Type" with:^{
			NSXMLElement *entity = ORMNewElementWithId(self.document, CORE, @"EntityType", nil);
			ORMSetAttribute(entity, @"Name", trimmed);
			ORMSetAttribute(entity, @"_ReferenceMode", @"");
			[[self section:@"Objects"] addChild:entity];
			created = ORMAttribute(entity, @"id");
			if ([mode length] > 0 && kind != ORMReferenceModeNone) {
				[self buildReferenceMode:mode kind:kind forEntity:entity];
			}
		}];
		/* Placed once the projection knows the entity type. */
		if (diagramId != nil) {
			[self placeElement:created onDiagram:diagramId at:point];
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
	[self group:@"Add Value Type" with:^{
		[self change:@"Add Value Type" with:^{
			created = ORMAttribute([self newValueTypeNamed:trimmed dataType:typeName], @"id");
		}];
		if (diagramId != nil) {
			[self placeElement:created onDiagram:diagramId at:point];
		}
	}];
	return created;
}

- (BOOL)rename:(NSString *)elementId to:(NSString *)name reason:(NSString **)reason
{
	id element = [self.model elementWithId:elementId];
	if (element == nil) {
		if (reason != NULL) {
			*reason = @"There is nothing to rename.";
		}
		return NO;
	}
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([element isKindOfClass:[ORMObjectType class]]) {
		ORMObjectType *type = element;
		if (![self checkName:trimmed except:elementId reason:reason]) {
			return NO;
		}
		if ([trimmed isEqualToString:type.name]) {
			return YES;
		}
		/* Person_id follows Person to Human_id; a shared unit or general
		 * mode's value type stays. */
		ORMObjectType *value = type.referenceModeKind == ORMReferenceModePopular ? type.referenceModeValueType : nil;
		NSString *valueName = value != nil ? [self valueTypeNameFor:trimmed mode:type.referenceMode kind:ORMReferenceModePopular] : nil;
		[self change:@"Rename" with:^{
			ORMSetAttribute(type.element, @"Name", trimmed);
			if (value != nil && [self.model objectTypeNamed:valueName] == nil) {
				ORMSetAttribute(value.element, @"Name", valueName);
			}
		}];
		return YES;
	}
	if ([element isKindOfClass:[ORMRole class]] || [element isKindOfClass:[ORMConstraint class]]
	    || [element isKindOfClass:[ORMDiagram class]] || [element isKindOfClass:[ORMFactType class]]) {
		if ([element isKindOfClass:[ORMConstraint class]] && [trimmed length] == 0) {
			if (reason != NULL) {
				*reason = @"A constraint needs a name.";
			}
			return NO;
		}
		NSXMLElement *xml = [(ORMElement *)element element];
		[self change:@"Rename" with:^{
			/* A fact type's own name; NORMA otherwise derives one. */
			ORMSetAttribute(xml, @"Name", trimmed);
		}];
		return YES;
	}
	if (reason != NULL) {
		*reason = @"That cannot be renamed.";
	}
	return NO;
}

- (BOOL)setReferenceMode:(NSString *)mode
                    kind:(ORMReferenceModeKind)kind
                ofEntity:(NSString *)entityId
                  reason:(NSString **)reason
{
	ORMObjectType *entity = [self.model elementWithId:entityId];
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
		ORMObjectType *clash = [self.model objectTypeNamed:valueName];
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
	[self change:removing ? @"Remove Reference Mode" : @"Set Reference Mode" with:^{
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
			[self deleteElements:@[ oldFact.identifier ]];
			if (oldValue != nil && [oldValue.playedRoles count] <= 1) {
				[self deleteElements:@[ oldValue.identifier ]];
			}
		}
		[self buildReferenceMode:trimmed kind:kind forEntity:[self xml:entityId]];
	}];
	return YES;
}

- (BOOL)setDataType:(NSString *)typeName
             length:(NSInteger)length
              scale:(NSInteger)scale
                 of:(NSString *)objectTypeId
             reason:(NSString **)reason
{
	ORMObjectType *type = [self.model elementWithId:objectTypeId];
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
	[self change:@"Set Data Type" with:^{
		NSXMLElement *dataType = ORMChild(type.element, CORE, @"ConceptualDataType");
		if (dataType == nil) {
			dataType = ORMNewElementWithId(self.document, CORE, @"ConceptualDataType", nil);
			ORMInsertChild(type.element, dataType);
		}
		ORMSetAttribute(dataType, @"ref", [self dataTypeIdNamed:typeName]);
		ORMSetAttribute(dataType, @"Scale", [NSString stringWithFormat:@"%ld", (long)MAX(scale, (NSInteger)0)]);
		ORMSetAttribute(dataType, @"Length", [NSString stringWithFormat:@"%ld", (long)MAX(length, (NSInteger)0)]);
	}];
	return YES;
}

- (BOOL)setFlag:(NSString *)attribute to:(BOOL)flag of:(NSString *)objectTypeId named:(NSString *)action
         reason:(NSString **)reason
{
	ORMObjectType *type = [self.model elementWithId:objectTypeId];
	if (![type isKindOfClass:[ORMObjectType class]]) {
		if (reason != NULL) {
			*reason = @"Pick an object type.";
		}
		return NO;
	}
	if (ORMBoolAttribute(type.element, attribute, NO) == flag) {
		return YES;
	}
	[self change:action with:^{
		ORMSetBoolAttribute(type.element, attribute, flag, NO);
	}];
	return YES;
}

- (BOOL)setIndependent:(BOOL)flag of:(NSString *)objectTypeId reason:(NSString **)reason
{
	return [self setFlag:@"IsIndependent" to:flag of:objectTypeId named:@"Set Independent" reason:reason];
}

- (BOOL)setPersonal:(BOOL)flag of:(NSString *)objectTypeId reason:(NSString **)reason
{
	return [self setFlag:@"IsPersonal" to:flag of:objectTypeId named:@"Set Personal" reason:reason];
}

- (BOOL)setExternal:(BOOL)flag of:(NSString *)objectTypeId reason:(NSString **)reason
{
	return [self setFlag:@"IsExternal" to:flag of:objectTypeId named:@"Set External" reason:reason];
}

- (BOOL)setValueType:(BOOL)value of:(NSString *)objectTypeId reason:(NSString **)reason
{
	ORMObjectType *type = [self.model elementWithId:objectTypeId];
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
	[self change:value ? @"Make Value Type" : @"Make Entity Type" with:^{
		NSXMLElement *old = type.element;
		NSXMLElement *replacement = ORMNewElement(self.document, CORE, value ? @"ValueType" : @"EntityType");
		for (NSXMLNode *attribute in [old attributes]) {
			if (![[attribute name] isEqualToString:@"_ReferenceMode"]) {
				[replacement addAttribute:[attribute copy]];
			}
		}
		for (NSXMLNode *child in [old children]) {
			NSString *local = [child localName];
			if (!value && ([local isEqualToString:@"ConceptualDataType"] || [local isEqualToString:@"ValueRestriction"])) {
				continue;
			}
			[replacement addChild:[child copy]];
		}
		if (value) {
			NSXMLElement *dataType = ORMNewElementWithId(self.document, CORE, @"ConceptualDataType", nil);
			ORMSetAttribute(dataType, @"ref", [self dataTypeIdNamed:@"UnspecifiedDataType"]);
			ORMSetAttribute(dataType, @"Scale", @"0");
			ORMSetAttribute(dataType, @"Length", @"0");
			ORMInsertChild(replacement, dataType);
		} else {
			ORMSetAttribute(replacement, @"_ReferenceMode", @"");
		}
		[(NSXMLElement *)[old parent] replaceChildAtIndex:[old index] withNode:replacement];
	}];
	return YES;
}

- (BOOL)setValueConstraint:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason
{
	id target = [self.model elementWithId:elementId];
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
	NSXMLElement *owner = [(ORMElement *)target element];
	[self change:@"Set Value Constraint" with:^{
		NSXMLElement *restriction = ORMChild(owner, CORE, @"ValueRestriction");
		NSXMLElement *constraint = nil;
		for (NSXMLNode *node in [restriction children]) {
			if ([node kind] == NSXMLElementKind) {
				constraint = (NSXMLElement *)node;
			}
		}
		if (ranges == nil) {
			[restriction detach];
			return;
		}
		if (constraint == nil) {
			restriction = restriction ?: ORMEnsureChild(self.document, owner, CORE, @"ValueRestriction");
			constraint = ORMNewElementWithId(self.document, CORE,
			                                 isRole ? @"RoleValueConstraint" : @"ValueConstraint", nil);
			ORMSetAttribute(constraint, @"Name",
			                [self nextName:isRole ? @"RoleValueConstraint" : @"ValueTypeValueConstraint"]);
			[restriction addChild:constraint];
		}
		[ORMChild(constraint, CORE, @"ValueRanges") detach];
		NSXMLElement *rangesElement = ORMNewElement(self.document, CORE, @"ValueRanges");
		for (NSDictionary *range in ranges) {
			NSXMLElement *element = ORMNewElementWithId(self.document, CORE, @"ValueRange", nil);
			ORMSetAttribute(element, @"MinValue", [range objectForKey:@"min"]);
			ORMSetAttribute(element, @"MaxValue", [range objectForKey:@"max"]);
			ORMSetAttribute(element, @"MinInclusion", [range objectForKey:@"minInclusion"]);
			ORMSetAttribute(element, @"MaxInclusion", [range objectForKey:@"maxInclusion"]);
			[rangesElement addChild:element];
		}
		[constraint addChild:rangesElement];
	}];
	return YES;
}

/* Definitions/Definition/Text or Notes/Note/Text. */
- (BOOL)setNested:(NSString *)container item:(NSString *)item text:(NSString *)text of:(NSString *)elementId
           action:(NSString *)action reason:(NSString **)reason
{
	id target = [self.model elementWithId:elementId];
	if (![target isKindOfClass:[ORMObjectType class]] && ![target isKindOfClass:[ORMFactType class]]) {
		if (reason != NULL) {
			*reason = @"Only object types and fact types have definitions and notes.";
		}
		return NO;
	}
	NSXMLElement *owner = [(ORMElement *)target element];
	[self change:action with:^{
		NSXMLElement *outer = ORMChild(owner, CORE, container);
		if ([text length] == 0) {
			[outer detach];
			return;
		}
		outer = outer ?: ORMEnsureChild(self.document, owner, CORE, container);
		NSXMLElement *inner = ORMChild(outer, CORE, item);
		if (inner == nil) {
			inner = ORMNewElementWithId(self.document, CORE, item, nil);
			[outer addChild:inner];
		}
		ORMSetChildText(self.document, inner, CORE, @"Text", text);
	}];
	return YES;
}

- (BOOL)setDefinition:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason
{
	return [self setNested:@"Definitions" item:@"Definition" text:text of:elementId action:@"Set Definition"
	                reason:reason];
}

- (BOOL)setNote:(NSString *)text of:(NSString *)elementId reason:(NSString **)reason
{
	return [self setNested:@"Notes" item:@"Note" text:text of:elementId action:@"Set Note" reason:reason];
}

@end
