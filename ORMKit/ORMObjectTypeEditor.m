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
	NSString *format = [_editor.model.referenceModeFormats objectForKey:type];
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

/* A new object type in the model: a value type with its data type, an
 * entity type with no reference mode yet. */
- (ORMObjectType *)newObjectTypeNamed:(NSString *)name kind:(ORMObjectTypeKind)kind dataType:(NSString *)typeName
{
	ORMModel *model = _editor.model;
	ORMObjectType *type = [[ORMObjectType alloc] initWithModel:model];
	type.name = name;
	type.kind = kind;
	if (kind == ORMValueType) {
		type.dataType = [self dataTypeNamed:typeName ?: @"UnspecifiedDataType"];
	} else {
		type.savedReferenceMode = @"";
	}
	[model addElement:type];
	[_editor wrote:type];
	return type;
}

/* Gives the entity type its reference mode, as NORMA builds one, inside
 * a model change: the value type (shared for a unit or general mode), "{0} has {1}" read back as "{0} is of {1}",
 * the entity's role unique and mandatory, the value's role unique and the
 * preferred identifier. */
- (void)addReferenceMode:(NSString *)mode kind:(ORMReferenceModeKind)kind to:(ORMObjectType *)entity
{
	ORMModel *model = _editor.model;
	NSString *valueName = [self valueTypeNameFor:entity.name mode:mode kind:kind];
	ORMObjectType *value = [model objectTypeNamed:valueName];
	if (value == nil || value.kind != ORMValueType) {
		value = [self newObjectTypeNamed:[_editor uniqueObjectTypeName:valueName] kind:ORMValueType
		                        dataType:ORMDefaultDataTypeForMode(mode, kind)];
	}
	ORMFactType *fact = [_editor.factTypeEditor addFactWithPlayers:@[ entity, value ] reading:@"{0} has {1}"];
	NSArray<ORMRole *> *roles = fact.roles;
	[_editor.factTypeEditor addReading:@"{0} is of {1}" to:fact roles:@[ roles[1], roles[0] ]];
	[_editor.constraintEditor addInternalUniqueness:@[ roles[0] ]];
	[_editor.constraintEditor addSimpleMandatory:roles[0]];
	entity.preferredIdentifier = [_editor.constraintEditor addInternalUniqueness:@[ roles[1] ]];
	entity.savedReferenceMode = mode;
	[_editor wrote:entity];
	/* A mode NORMA does not know gets a custom reference mode of its kind,
	 * so NORMA reads the value type's name back as this mode. */
	if (kind != ORMReferenceModePopular && [model.customReferenceModes objectForKey:mode] == nil) {
		NSMutableDictionary *customs = [model.customReferenceModes mutableCopy] ?: [NSMutableDictionary dictionary];
		[customs setObject:kind == ORMReferenceModeUnitBased ? @"UnitBased" : @"General" forKey:mode];
		model.customReferenceModes = customs;
	}
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
	BOOL identified = [mode length] > 0 && kind != ORMReferenceModeNone;
	[_editor group:@"Add Entity Type" with:^{
		[_editor modelChange:@"Add Entity Type" with:^{
			ORMObjectType *entity = [self newObjectTypeNamed:trimmed kind:ORMEntityType dataType:nil];
			if (identified) {
				[self addReferenceMode:mode kind:kind to:entity];
			}
			created = entity.identifier;
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
		[_editor modelChange:@"Add Value Type" with:^{
			created = [self newObjectTypeNamed:trimmed kind:ORMValueType dataType:typeName].identifier;
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
	BOOL renaming = oldValue != nil && entity.referenceModeKind == ORMReferenceModePopular
		&& kind == ORMReferenceModePopular && [oldValue.playedRoles count] == 1;
	if (removing || renaming) {
		[_editor modelChange:removing ? @"Remove Reference Mode" : @"Set Reference Mode" with:^{
			if (renaming) {
				oldValue.name = [self valueTypeNameFor:entity.name mode:trimmed kind:ORMReferenceModePopular];
				[_editor wrote:oldValue];
			}
			entity.savedReferenceMode = removing ? @"" : trimmed;
			[_editor wrote:entity];
		}];
		return YES;
	}
	/* The old identification goes: its fact type, and its value type when
	 * nothing else uses it. */
	BOOL valueGoes = oldValue != nil && [oldValue.playedRoles count] <= 1;
	[_editor group:@"Set Reference Mode" with:^{
		if (oldFact != nil) {
			[_editor.elementEditor deleteElements:valueGoes ? @[ oldFact.identifier, oldValue.identifier ]
			                                                : @[ oldFact.identifier ]];
		}
		[_editor modelChange:@"Set Reference Mode" with:^{
			[self addReferenceMode:trimmed kind:kind to:entity];
		}];
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

- (BOOL)setValuePattern:(NSString *)pattern of:(NSString *)objectTypeId reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	if ([type isKindOfClass:[ORMObjectType class]] && type.isEntity) {
		type = type.referenceModeValueType;
	}
	if (![type isKindOfClass:[ORMObjectType class]] || type.kind != ORMValueType) {
		if (reason != NULL) {
			*reason = @"Only a value type, or an entity type with a reference mode, has a pattern.";
		}
		return NO;
	}
	NSString *kept = [pattern length] > 0 ? pattern : nil;
	NSError *error = nil;
	if (kept != nil && [NSRegularExpression regularExpressionWithPattern:kept options:0 error:&error] == nil) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"'%@' is no regular expression.", kept];
		}
		return NO;
	}
	if ((kept == nil && type.valuePattern == nil) || [kept isEqualToString:type.valuePattern]) {
		return YES;
	}
	[_editor modelChange:@"Set Pattern" with:^{
		type.valuePattern = kept;
		[_editor wrote:type];
	}];
	return YES;
}

- (BOOL)setDerivationNote:(NSString *)text ofSubtype:(NSString *)objectTypeId reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	if (![type isKindOfClass:[ORMObjectType class]] || [type.supertypes count] == 0) {
		if (reason != NULL) {
			*reason = @"Only a subtype is derived by a rule.";
		}
		return NO;
	}
	ORMDerivationRule *rule = [_editor.model.derivationRules objectForKey:type.identifier];
	NSString *words = [text length] > 0 ? text : nil;
	if ([words ?: @"" isEqualToString:rule.informalText ?: @""] && (rule != nil) == (words != nil)) {
		return YES;
	}
	[_editor modelChange:@"Set Derivation" with:^{
		if (words == nil) {
			[_editor.model setDerivationRule:nil ofSubtype:type];
		} else {
			ORMDerivationRule *kept = rule;
			if (kept == nil) {
				kept = [[ORMDerivationRule alloc] initWithModel:_editor.model];
				kept.identifier = nil;
				kept.isSubtypeRule = YES;
				kept.paths = @[];
				kept.calculations = @[];
				kept.conditions = @[];
				kept.projections = @{};
			}
			kept.pathId = kept.pathId ?: ORMNewId();
			kept.noteId = kept.noteId ?: ORMNewId();
			kept.informalText = words;
			[_editor.model setDerivationRule:kept ofSubtype:type];
		}
		[_editor wrote:type];
	}];
	return YES;
}

- (BOOL)setDerivationPartial:(BOOL)partial
                      stored:(BOOL)stored
                   ofSubtype:(NSString *)objectTypeId
                      reason:(NSString **)reason
{
	ORMObjectType *type = [_editor.model elementWithId:objectTypeId];
	ORMDerivationRule *rule = [type isKindOfClass:[ORMObjectType class]]
		? [_editor.model.derivationRules objectForKey:type.identifier] : nil;
	if (rule.pathId == nil) {
		if (reason != NULL) {
			*reason = rule != nil ? @"Its rule is an older one, which says this itself." : @"It is not derived.";
		}
		return NO;
	}
	if (rule.isPartial == partial && rule.isStored == stored) {
		return YES;
	}
	[_editor modelChange:@"Set Derivation" with:^{
		rule.isPartial = partial;
		rule.isStored = stored;
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
	if (value && (type.preferredIdentifier != nil || [type isInSubtypeHierarchy])) {
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
	[_editor modelChange:@"Add Subtype" with:^{
		ORMModel *model = _editor.model;
		ORMFactType *fact = [[ORMFactType alloc] initWithModel:model];
		fact.kind = ORMFactTypeSubtype;
		fact.savedDerivedName = [NSString stringWithFormat:@"%@IsSubtypeOf%@", sub.name, sup.name];
		/* The first supertype identifies a subtype with no identifier. */
		if ([sub.supertypes count] == 0 && sub.preferredIdentifier == nil) {
			fact.preferredIdentificationPath = @YES;
		}
		NSMutableArray *roles = [NSMutableArray array];
		for (ORMObjectType *player in @[ sub, sup ]) {
			ORMRole *role = [[ORMRole alloc] initWithModel:model];
			role.factType = fact;
			role.index = [roles count];
			role.player = player;
			role.isSubtypeMetaRole = player == sub;
			role.isSupertypeMetaRole = player == sup;
			[model registerElement:role];
			[roles addObject:role];
		}
		fact.roles = roles;
		fact.readingOrders = @[];
		[model addElement:fact];
		[_editor wrote:fact];
		/* Each subtype instance is exactly one supertype instance, and
		 * the other way round at most one. */
		[_editor.constraintEditor addSimpleMandatory:roles[0]];
		[_editor.constraintEditor addInternalUniqueness:@[ roles[0] ]];
		[_editor.constraintEditor addInternalUniqueness:@[ roles[1] ]];
		created = fact.identifier;
	}];
	return created;
}

@end
