/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataMapper.h"
#import "ORMDiagram.h"
#import "ORMReadingText.h"
#import "ORMVerbalizer.h"

@interface ORMMappingNote ()
@property (nonatomic, readwrite) ORMMappingNoteKind kind;
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite, copy) NSString *elementId;
@end

@implementation ORMMappingNote

- (NSString *)description
{
	return self.text;
}

@end

/* How the mapper ends up treating an object type. */
typedef NS_ENUM(NSInteger, ORMResolved) {
	ORMResolvedOutOfScope,
	ORMResolvedEntity,
	/* A value type, or an entity type absorbed into attributes. */
	ORMResolvedValue,
	ORMResolvedIgnored,
	/* An entity type identified by several fact types and nothing else
	 * (an Address): absorbed into whatever refers to it, as its
	 * identifying values. */
	ORMResolvedComposite,
	/* An objectified fact type one-to-one with a player (Death of a
	 * Person): its properties are the player's. */
	ORMResolvedFolded,
};

@implementation ORMCoreDataMapper
{
	ORMCDModel *_out;
	NSMutableArray<ORMMappingNote *> *_notes;
	NSMutableDictionary<NSString *, NSNumber *> *_resolved;
	/* Object type id -> the entity its properties go in. */
	NSMutableDictionary<NSString *, ORMCDEntity *> *_entityOf;
	/* Value type id -> the entity a many-valued use of it makes. */
	NSMutableDictionary<NSString *, ORMCDEntity *> *_valueEntities;
	/* Root entity name -> the property names its inheritance tree uses:
	 * Core Data refuses a subentity's property named as its parent's. */
	NSMutableDictionary<NSString *, NSMutableSet *> *_names;
	NSMutableSet<NSString *> *_entityNames;
	/* A folded objectification's id -> the role of the player it folds
	 * into. */
	NSMutableDictionary<NSString *, ORMRole *> *_folds;
}

- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	if ((self = [super init])) {
		_model = model;
		_mapping = mapping ?: [ORMCoreDataMapping defaultMappingNamed:model.name];
	}
	return self;
}

#pragma mark Names

static NSArray *
ORMWordsOf(NSString *name)
{
	NSMutableArray *words = [NSMutableArray array];
	NSCharacterSet *separators = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
	for (NSString *word in [name componentsSeparatedByCharactersInSet:separators]) {
		if ([word length] > 0) {
			[words addObject:word];
		}
	}
	return words;
}

+ (NSString *)entityNameFor:(NSString *)name
{
	NSMutableString *out = [NSMutableString string];
	for (NSString *word in ORMWordsOf(name)) {
		[out appendString:[[word substringToIndex:1] uppercaseString]];
		[out appendString:[word substringFromIndex:1]];
	}
	if ([out length] == 0 || [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[out characterAtIndex:0]]) {
		[out insertString:@"E" atIndex:0];
	}
	return out;
}

/* A word lowered as an identifier's start: "SKU" to "sku", "ItemCategory"
 * to "itemCategory", "kgValue" as it is. */
static NSString *
ORMLowerFirst(NSString *word)
{
	if ([word isEqualToString:[word uppercaseString]]) {
		return [word lowercaseString];
	}
	NSUInteger upper = 0;
	while (upper < [word length] && [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:[word characterAtIndex:upper]]) {
		upper++;
	}
	/* "URLPath" to "urlPath": the run of capitals but the last. */
	NSUInteger lower = upper > 1 && upper < [word length] ? upper - 1 : MAX(upper, (NSUInteger)1);
	return [[[word substringToIndex:lower] lowercaseString] stringByAppendingString:[word substringFromIndex:lower]];
}

+ (NSString *)propertyNameFor:(NSString *)name
{
	NSArray *words = ORMWordsOf(name);
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < [words count]; i++) {
		NSString *word = [words objectAtIndex:i];
		if (i == 0) {
			[out appendString:ORMLowerFirst(word)];
		} else {
			[out appendString:[[word substringToIndex:1] uppercaseString]];
			[out appendString:[word substringFromIndex:1]];
		}
	}
	if ([out length] == 0 || [[NSCharacterSet decimalDigitCharacterSet] characterIsMember:[out characterAtIndex:0]]) {
		[out insertString:@"value" atIndex:0];
	}
	return out;
}

+ (NSString *)pluralOf:(NSString *)name
{
	if ([name length] == 0) {
		return name;
	}
	NSString *lower = [name lowercaseString];
	if ([lower hasSuffix:@"s"] || [lower hasSuffix:@"x"] || [lower hasSuffix:@"ch"] || [lower hasSuffix:@"sh"]
	    || [lower hasSuffix:@"z"]) {
		return [name stringByAppendingString:@"es"];
	}
	if ([lower hasSuffix:@"y"] && [lower length] > 1
	    && [@"aeiou" rangeOfString:[lower substringWithRange:NSMakeRange([lower length] - 2, 1)]].location == NSNotFound) {
		return [[name substringToIndex:[name length] - 1] stringByAppendingString:@"ies"];
	}
	return [name stringByAppendingString:@"s"];
}

/* Names NSManagedObject and NSObject already answer to. */
static NSSet *
ORMReservedNames(void)
{
	static NSSet *reserved;
	if (reserved == nil) {
		reserved = [NSSet setWithArray:@[ @"description", @"entity", @"objectID", @"managedObjectContext", @"isDeleted",
		                                  @"isInserted", @"isUpdated", @"isFault", @"hash", @"class", @"superclass",
		                                  @"self", @"changedValues", @"faultingState", @"hasChanges", @"type",
		                                  @"properties", @"debugDescription", @"zone", @"version" ]];
	}
	return reserved;
}

/* The root of an entity's inheritance tree, whose name set it shares. */
- (NSString *)rootOf:(ORMCDEntity *)entity
{
	ORMCDEntity *at = entity;
	NSMutableSet *seen = [NSMutableSet set];
	while (at.parentName != nil && ![seen containsObject:at.name]) {
		[seen addObject:at.name];
		ORMCDEntity *parent = [_out entityNamed:at.parentName];
		if (parent == nil) {
			break;
		}
		at = parent;
	}
	return at.name;
}

- (NSMutableSet *)namesOf:(ORMCDEntity *)entity
{
	NSString *root = [self rootOf:entity];
	NSMutableSet *names = [_names objectForKey:root];
	if (names == nil) {
		names = [NSMutableSet set];
		[_names setObject:names forKey:root];
	}
	return names;
}

/* A property name on the entity: the user's for the source when there is
 * one, else the first of the candidates no property of its tree has. */
- (NSString *)claimName:(NSArray<NSString *> *)candidates source:(NSString *)source on:(ORMCDEntity *)entity
{
	NSMutableSet *names = [self namesOf:entity];
	NSString *override = source != nil ? [self.mapping.nameOverrides objectForKey:source] : nil;
	NSMutableArray *tries = [NSMutableArray array];
	if (override != nil) {
		[tries addObject:override];
	}
	for (NSString *candidate in candidates) {
		if ([candidate length] > 0) {
			[tries addObject:[ORMReservedNames() containsObject:candidate]
			                     ? [candidate stringByAppendingString:@"Value"] : candidate];
		}
	}
	for (NSString *name in tries) {
		if (![names containsObject:name]) {
			[names addObject:name];
			return name;
		}
	}
	NSString *base = [tries lastObject] ?: @"property";
	for (NSUInteger i = 2;; i++) {
		NSString *name = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)i];
		if (![names containsObject:name]) {
			[names addObject:name];
			return name;
		}
	}
}

- (NSString *)claimEntityName:(NSString *)base source:(NSString *)source
{
	NSString *override = [self.mapping.nameOverrides objectForKey:source];
	NSString *name = override ?: [ORMCoreDataMapper entityNameFor:base];
	if ([_entityNames containsObject:name]) {
		for (NSUInteger i = 2;; i++) {
			NSString *candidate = [NSString stringWithFormat:@"%@%lu", name, (unsigned long)i];
			if (![_entityNames containsObject:candidate]) {
				name = candidate;
				break;
			}
		}
	}
	[_entityNames addObject:name];
	return name;
}

/* The words of a reading read from the role, the role itself left out
 * and every other player named: "{0} was born in {1}" from {0} is "was born
 * in Country". */
- (NSString *)phraseOf:(ORMFactType *)fact from:(ORMRole *)near
{
	ORMReadingOrder *order = [fact readingOrderStartingWithRole:near] ?: [[fact primaryReading] readingOrder];
	ORMReading *reading = [order.readings firstObject];
	if (reading == nil) {
		return @"";
	}
	ORMReadingText *text = [ORMReadingText readingTextWithString:reading.text arity:[order.roles count] reason:NULL];
	return [text expandWithNames:^NSString *(NSUInteger index, NSString *pre, NSString *post) {
		ORMRole *role = index < [order.roles count] ? [order.roles objectAtIndex:index] : nil;
		if (role == near) {
			return @"";
		}
		return [NSString stringWithFormat:@"%@%@%@", pre ?: @"", role.player.name ?: @"", post ?: @""];
	}];
}

#pragma mark Notes

- (void)note:(ORMMappingNoteKind)kind text:(NSString *)text element:(NSString *)elementId
{
	ORMMappingNote *note = [[ORMMappingNote alloc] init];
	note.kind = kind;
	note.text = text;
	note.elementId = elementId;
	[_notes addObject:note];
}

#pragma mark Classifying

- (BOOL)isInScope:(ORMObjectType *)type
{
	switch (self.mapping.scope) {
	case ORMScopeModel:
		return YES;
	case ORMScopeObjectTypes:
		return [self.mapping.scopeIds containsObject:type.identifier];
	case ORMScopeDiagram:
		for (NSString *diagramId in self.mapping.scopeIds) {
			ORMDiagram *diagram = [self.model elementWithId:diagramId];
			if ([diagram isKindOfClass:[ORMDiagram class]] && [diagram shapeForSubject:type.identifier] != nil) {
				return YES;
			}
		}
		/* A shown entity type's reference mode comes with it. */
		for (ORMObjectType *other in self.model.objectTypes) {
			if (other.referenceModeValueType == type && other != type && [self isInScope:other]) {
				return YES;
			}
		}
		return NO;
	}
	return YES;
}

/* Whether a value type plays a role of its own: a unary about the value
 * ("Some String is long"), or a fact type functional on the value with
 * another value at the far end. Rmap gives it a table keyed by the value;
 * here, an entity with the value as a unique attribute. */
- (BOOL)valueTypeHasRolesOfItsOwn:(ORMObjectType *)type
{
	for (ORMRole *role in type.playedRoles) {
		ORMFactType *fact = role.factType;
		if (fact.kind != ORMFactTypeOrdinary || fact.objectifyingType != nil) {
			continue;
		}
		NSArray *roles = [fact visibleRoles];
		if ([roles count] == 1) {
			return YES;
		}
		ORMRole *other = [role oppositeRole];
		if ([roles count] == 2 && role.isUnique && other.player.kind == ORMValueType && fact != other.player.referenceModeFactType) {
			return YES;
		}
	}
	return NO;
}

/* Whether an entity type is no more than its identifier: a reference
 * mode, and no fact type functional on it, no subtyping, no
 * independence, no objectification. */
- (BOOL)isIdentifierOnly:(ORMObjectType *)type
{
	if (type.referenceModeValueType == nil || type.nestedFactType != nil || type.isIndependent
	    || [type.subtypes count] > 0 || [type.supertypes count] > 0) {
		return NO;
	}
	/* A generated identifier (an auto counter, a row id) is made where
	 * the instance is: it cannot be the value of what refers to it. */
	NSString *dataType = type.referenceModeValueType.dataType.typeName;
	if ([dataType isEqualToString:@"AutoCounterNumericDataType"] || [dataType isEqualToString:@"RowIdOtherDataType"]
	    || [dataType isEqualToString:@"ObjectIdOtherDataType"]) {
		return NO;
	}
	for (ORMRole *role in type.playedRoles) {
		ORMFactType *fact = role.factType;
		if (fact == type.referenceModeFactType || fact.kind == ORMFactTypeImplied || role.proxiedRole != nil) {
			continue;
		}
		if (role.isUnique || [[fact visibleRoles] count] == 1) {
			return NO;
		}
	}
	return YES;
}

/* The roles an entity type is identified by when several fact types
 * identify it (an external uniqueness over the far roles of binaries it
 * plays): the far roles, in the constraint's order; nil otherwise. */
- (NSArray<ORMRole *> *)compositeIdentificationOf:(ORMObjectType *)type
{
	/* Its preferred identifier, or an alternate key: an Address with a
	 * generated id is still identified by its street, city and the rest. */
	NSMutableArray *candidates = [NSMutableArray array];
	if (type.preferredIdentifier != nil) {
		[candidates addObject:type.preferredIdentifier];
	}
	/* Rmap goes by the reference scheme alone. */
	for (ORMConstraint *constraint in self.mapping.style == ORMStyleRelational ? @[] : self.model.constraints) {
		if (constraint.kind == ORMUniquenessConstraint && !constraint.isInternal && constraint != type.preferredIdentifier) {
			[candidates addObject:constraint];
		}
	}
	for (ORMConstraint *identifier in candidates) {
		if (identifier.isInternal || [[identifier allRoles] count] < 2 || identifier.modality != ORMAlethic) {
			continue;
		}
		BOOL fits = YES;
		for (ORMRole *role in [identifier allRoles]) {
			fits = fits && [[role.factType visibleRoles] count] == 2 && [role oppositeRole].player == type;
		}
		if (fits) {
			return [identifier allRoles];
		}
	}
	return nil;
}

/* Whether an entity type is no more than its identifying values, several
 * of them (an Address): nothing functional on it beside them, no
 * subtyping, objectification or independence, and used only as the value
 * of what refers to it, never many of it. */
- (BOOL)isCompositeValue:(ORMObjectType *)type
{
	NSArray *identifying = [self compositeIdentificationOf:type];
	if (identifying == nil || type.nestedFactType != nil || type.isIndependent || [type.subtypes count] > 0
	    || [type.supertypes count] > 0) {
		return NO;
	}
	NSMutableSet *identifyingFacts = [NSMutableSet set];
	for (ORMRole *role in identifying) {
		[identifyingFacts addObject:[NSValue valueWithNonretainedObject:role.factType]];
	}
	NSUInteger uses = 0;
	for (ORMRole *role in type.playedRoles) {
		ORMFactType *fact = role.factType;
		if ([identifyingFacts containsObject:[NSValue valueWithNonretainedObject:fact]] || fact.kind == ORMFactTypeImplied
		    || role.proxiedRole != nil || fact == type.referenceModeFactType) {
			continue;
		}
		NSArray *roles = [fact visibleRoles];
		if (fact.kind != ORMFactTypeOrdinary || [roles count] == 1 || role.isUnique) {
			return NO;
		}
		/* The value of one instance at a time: the referring role is
		 * functional (or the fact type is an entity of its own, of which
		 * it is a column). */
		if ([roles count] == 2 && fact.objectifyingType == nil && ![[role oppositeRole] isUnique]) {
			return NO;
		}
		uses++;
	}
	/* Rmap, as ActiveFacts makes it, keeps a table for what more than
	 * one fact type refers to. */
	if (self.mapping.style == ORMStyleRelational && uses > 1) {
		return NO;
	}
	return uses > 0;
}

/* The role an objectification is one-to-one with: the fact type's single
 * role with a uniqueness of its own, played by an entity type; nil when
 * it is not so. */
- (ORMRole *)foldRoleOf:(ORMObjectType *)type
{
	ORMFactType *fact = type.nestedFactType;
	if (fact == nil || type.isIndependent || [type.subtypes count] > 0 || [type.supertypes count] > 0) {
		return nil;
	}
	NSArray *roles = [fact visibleRoles];
	if ([roles count] > 2) {
		return nil;
	}
	ORMRole *unique = nil;
	for (ORMRole *role in roles) {
		if (role.isUnique) {
			if (unique != nil) {
				return nil;
			}
			unique = role;
		}
	}
	if (unique == nil || unique.player.kind == ORMValueType || unique.player == type) {
		return nil;
	}
	return unique;
}

- (ORMObjectTypeMapping)automaticMappingOf:(ORMObjectType *)type
{
	if (type.kind == ORMValueType) {
		return [self valueTypeHasRolesOfItsOwn:type] ? ORMMapAsEntity : ORMMapAbsorbed;
	}
	if (self.mapping.absorbsIdentifierTypes && [self isIdentifierOnly:type]) {
		return ORMMapAbsorbed;
	}
	/* Identified by several values and no more: absorbed, as an address
	 * is part of the order it is on. */
	if (self.mapping.absorbsValueLikeTypes && ([self isCompositeValue:type] || [self foldRoleOf:type] != nil)) {
		return ORMMapAbsorbed;
	}
	/* An entity type is absorbed when it is no more than a measure: a
	 * value in a unit (Weight(kg:)), with no subtyping, objectification or
	 * independence, playing no role of its own beyond being the value of
	 * others' functional binary fact types. A thing with an id or a code
	 * (UnitOfMeasure(.Id)) stays an entity even with nothing else to say. */
	if (type.referenceModeKind != ORMReferenceModeUnitBased || type.nestedFactType != nil || type.isIndependent
	    || [type.subtypes count] > 0 || [type.supertypes count] > 0) {
		return ORMMapAsEntity;
	}
	NSUInteger uses = 0;
	for (ORMRole *role in type.playedRoles) {
		ORMFactType *fact = role.factType;
		if (fact == type.referenceModeFactType || fact.kind == ORMFactTypeImplied) {
			continue;
		}
		ORMRole *other = [role oppositeRole];
		if (fact.kind != ORMFactTypeOrdinary || [fact arity] != 2 || other == nil || !other.isUnique
		    || role.isUnique || fact.objectifyingType != nil) {
			return ORMMapAsEntity;
		}
		uses++;
	}
	/* Something that stands alone is a thing of its own. */
	return uses > 0 ? ORMMapAbsorbed : ORMMapAsEntity;
}

- (void)resolveObjectTypes
{
	for (ORMObjectType *type in self.model.objectTypes) {
		ORMResolved resolved;
		if (type.isImplicitBooleanValue || ![self isInScope:type]) {
			resolved = ORMResolvedOutOfScope;
		} else {
			ORMObjectTypeMapping mapping = [self.mapping mappingOfObjectType:type.identifier];
			if (mapping == ORMMapAutomatically) {
				mapping = [self automaticMappingOf:type];
			}
			BOOL composite = mapping == ORMMapAbsorbed && [self compositeIdentificationOf:type] != nil
				&& [self isCompositeValue:type];
			ORMRole *fold = mapping == ORMMapAbsorbed ? [self foldRoleOf:type] : nil;
			if (composite || fold != nil) {
				[_resolved setObject:@(composite ? ORMResolvedComposite : ORMResolvedFolded) forKey:type.identifier];
				if (fold != nil) {
					[_folds setObject:fold forKey:type.identifier];
				}
				[self note:ORMMappingAbsorbed
				      text:composite ? [NSString stringWithFormat:@"%@ is absorbed: its identifying values are "
				                                                   @"properties of whatever refers to it.", type.name]
				                     : [NSString stringWithFormat:@"%@ is folded into %@: one to one with it, its "
				                                                   @"properties are %@'s.", type.name, fold.player.name,
				                                                   fold.player.name]
				   element:type.identifier];
				continue;
			}
			if (mapping == ORMMapAbsorbed && type.isEntity && type.referenceModeValueType == nil) {
				[self note:ORMMappingWarning
				      text:[NSString stringWithFormat:@"%@ cannot be absorbed: it has no reference mode to be the "
				                                      @"value of. It is an entity.", type.name]
				   element:type.identifier];
				mapping = ORMMapAsEntity;
			}
			if (mapping == ORMMapTransformable && type.kind != ORMValueType) {
				[self note:ORMMappingWarning
				      text:[NSString stringWithFormat:@"%@ is an entity type; only a value type is Transformable.",
				                                      type.name]
				   element:type.identifier];
				mapping = ORMMapAsEntity;
			}
			resolved = mapping == ORMMapIgnored ? ORMResolvedIgnored
				: (mapping == ORMMapAbsorbed || mapping == ORMMapTransformable) ? ORMResolvedValue : ORMResolvedEntity;
			if (mapping == ORMMapAbsorbed && type.isEntity) {
				[self note:ORMMappingAbsorbed
				      text:[NSString stringWithFormat:@"%@ is absorbed: it is an attribute wherever it is used.",
				                                      type.name]
				   element:type.identifier];
			}
		}
		[_resolved setObject:@(resolved) forKey:type.identifier];
	}
}

- (ORMResolved)resolved:(ORMObjectType *)type
{
	if (type == nil) {
		return ORMResolvedOutOfScope;
	}
	NSNumber *resolved = [_resolved objectForKey:type.identifier];
	return resolved != nil ? [resolved integerValue] : ORMResolvedOutOfScope;
}

/* The value type that holds a value-ish object type's values: itself, or an
 * absorbed entity type's reference mode's. */
- (ORMObjectType *)valueTypeOf:(ORMObjectType *)type
{
	return type.kind == ORMValueType ? type : type.referenceModeValueType;
}

#pragma mark Entities

/* The supertype a subtype's entity inherits from: the one that identifies
 * it, else its first mapped one. */
- (ORMObjectType *)parentOf:(ORMObjectType *)type
{
	ORMObjectType *chosen = nil;
	for (ORMFactType *fact in type.supertypeFacts) {
		ORMObjectType *supertype = [[fact.roles lastObject] player];
		if ([self resolved:supertype] != ORMResolvedEntity) {
			continue;
		}
		if (chosen == nil || fact.providesPreferredIdentifier) {
			chosen = supertype;
		}
	}
	return chosen;
}

- (void)makeEntities
{
	/* Supertypes first, so a subentity finds its parent. */
	NSMutableArray *pending = [NSMutableArray array];
	for (ORMObjectType *type in self.model.objectTypes) {
		if ([self resolved:type] == ORMResolvedEntity) {
			[pending addObject:type];
		}
	}
	NSUInteger guard = [pending count] * [pending count] + 1;
	while ([pending count] > 0 && guard-- > 0) {
		ORMObjectType *type = [pending objectAtIndex:0];
		[pending removeObjectAtIndex:0];
		if (type.kind == ORMValueType) {
			/* A value type with roles of its own: keyed by its value. */
			[_entityOf setObject:[self valueEntityFor:type] forKey:type.identifier];
			continue;
		}
		ORMObjectType *parent = [self parentOf:type];
		if (parent != nil && [_entityOf objectForKey:parent.identifier] == nil) {
			[pending addObject:type];
			continue;
		}
		/* A subtype identified its own way is a thing of its own, as
		 * Rmap keeps it in its own table. */
		BOOL ownIdentification = NO;
		for (ORMFactType *fact in type.supertypeFacts) {
			ownIdentification = ownIdentification || !fact.providesPreferredIdentifier;
		}
		if (parent != nil && self.mapping.flattensSubtypes && !ownIdentification) {
			ORMCDEntity *root = [_entityOf objectForKey:parent.identifier];
			[_entityOf setObject:root forKey:type.identifier];
			[self note:ORMMappingWarning
			      text:[NSString stringWithFormat:@"%@ is flattened into %@: its properties are optional there.",
			                                      type.name, root.name]
			   element:type.identifier];
			continue;
		}
		ORMCDEntity *entity = [[ORMCDEntity alloc] init];
		entity.name = [self claimEntityName:type.name source:type.identifier];
		entity.source = type.identifier;
		entity.codeGenerationType = self.mapping.codeGenerationType;
		if (parent != nil) {
			entity.parentName = [[_entityOf objectForKey:parent.identifier] name];
			if ([type.supertypes count] > 1) {
				[self note:ORMMappingWarning
				      text:[NSString stringWithFormat:@"%@ has %lu supertypes; Core Data inherits from one, %@.",
				                                      type.name, (unsigned long)[type.supertypes count], parent.name]
				   element:type.identifier];
			}
		}
		[_out.entities addObject:entity];
		[_entityOf setObject:entity forKey:type.identifier];
	}
	/* A folded objectification's properties are its player's. */
	for (NSString *folded in _folds) {
		ORMCDEntity *player = [self entityOf:[[_folds objectForKey:folded] player]];
		if (player != nil) {
			[_entityOf setObject:player forKey:folded];
		}
	}
	/* A supertype its subtypes cover is abstract: an inclusive-or (or
	 * exclusive-or) mandatory over the supertype roles of every subtype
	 * fact says each instance is one of them. */
	if (!self.mapping.flattensSubtypes) {
		for (ORMConstraint *constraint in self.model.constraints) {
			if (constraint.kind != ORMMandatoryConstraint || constraint.isSimple || constraint.isImplied) {
				continue;
			}
			NSArray *roles = [constraint allRoles];
			ORMObjectType *supertype = [[roles firstObject] player];
			NSMutableSet *covered = [NSMutableSet set];
			BOOL allSupertypeRoles = YES;
			for (ORMRole *role in roles) {
				allSupertypeRoles = allSupertypeRoles && role.isSupertypeMetaRole && role.player == supertype;
				[covered addObject:[[role oppositeRole] player].identifier ?: @""];
			}
			NSMutableSet *subtypes = [NSMutableSet set];
			for (ORMObjectType *subtype in supertype.subtypes) {
				[subtypes addObject:subtype.identifier];
			}
			ORMCDEntity *entity = [_entityOf objectForKey:supertype.identifier];
			if (allSupertypeRoles && entity != nil && [covered isEqualToSet:subtypes]) {
				entity.isAbstract = YES;
			}
		}
	}
}

- (ORMCDEntity *)entityOf:(ORMObjectType *)type
{
	return type != nil ? [_entityOf objectForKey:type.identifier] : nil;
}

#pragma mark Attributes

+ (NSString *)attributeTypeFor:(ORMDataType *)dataType
{
	NSDictionary *types = @{
		@"SignedSmallIntegerNumericDataType": @"Integer 16",
		@"SignedIntegerNumericDataType": @"Integer 32",
		@"SignedLargeIntegerNumericDataType": @"Integer 64",
		@"UnsignedTinyIntegerNumericDataType": @"Integer 16",
		@"UnsignedSmallIntegerNumericDataType": @"Integer 32",
		@"UnsignedIntegerNumericDataType": @"Integer 64",
		@"UnsignedLargeIntegerNumericDataType": @"Integer 64",
		@"AutoCounterNumericDataType": @"Integer 64",
		@"FloatingPointNumericDataType": @"Double",
		@"SinglePrecisionFloatingPointNumericDataType": @"Float",
		@"DoublePrecisionFloatingPointNumericDataType": @"Double",
		@"DecimalNumericDataType": @"Decimal",
		@"MoneyNumericDataType": @"Decimal",
		@"RowIdOtherDataType": @"UUID",
		@"ObjectIdOtherDataType": @"UUID",
	};
	NSString *type = [types objectForKey:dataType.typeName];
	if (type != nil) {
		return type;
	}
	switch (dataType.family) {
	case ORMDataTypeTemporal:
		return @"Date";
	case ORMDataTypeLogical:
		return @"Boolean";
	case ORMDataTypeRawData:
		return @"Binary";
	default:
		return @"String";
	}
}

static NSString *
ORMRegexEscape(NSString *value)
{
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < [value length]; i++) {
		unichar c = [value characterAtIndex:i];
		if ([@"\\^$.|?*+()[]{}" rangeOfString:[NSString stringWithFormat:@"%C", c]].location != NSNotFound) {
			[out appendString:@"\\"];
		}
		[out appendFormat:@"%C", c];
	}
	return out;
}

/* The value constraint's bounds, as Core Data can hold them. */
- (void)constrain:(ORMCDAttribute *)attribute by:(ORMValueConstraint *)constraint element:(NSString *)elementId
{
	if (constraint == nil || [constraint.ranges count] == 0) {
		return;
	}
	BOOL text = [attribute.attributeType isEqualToString:@"String"];
	BOOL allSingle = YES;
	for (ORMValueRange *range in constraint.ranges) {
		allSingle = allSingle && [range.minValue isEqualToString:range.maxValue];
	}
	if (text && allSingle) {
		NSMutableArray *alternatives = [NSMutableArray array];
		for (ORMValueRange *range in constraint.ranges) {
			[alternatives addObject:ORMRegexEscape(range.minValue)];
		}
		attribute.regularExpression = [NSString stringWithFormat:@"^(?:%@)$", [alternatives componentsJoinedByString:@"|"]];
		return;
	}
	if (!text && [constraint.ranges count] == 1) {
		ORMValueRange *range = [constraint.ranges firstObject];
		if (![attribute.attributeType isEqualToString:@"Boolean"]) {
			attribute.minValue = [range.minValue length] > 0 ? range.minValue : attribute.minValue;
			attribute.maxValue = [range.maxValue length] > 0 ? range.maxValue : attribute.maxValue;
		}
		if (range.minInclusion == ORMRangeOpen || range.maxInclusion == ORMRangeOpen) {
			[self note:ORMMappingWarning
			      text:[NSString stringWithFormat:@"%@ allows its open bounds: Core Data's minimum and maximum are "
			                                      @"inclusive.", attribute.name]
			   element:elementId];
		}
		return;
	}
	if (!text && allSingle && [attribute.attributeType hasPrefix:@"Integer"]) {
		NSMutableArray *alternatives = [NSMutableArray array];
		for (ORMValueRange *range in constraint.ranges) {
			[alternatives addObject:ORMRegexEscape(range.minValue)];
		}
		[self note:ORMMappingUnenforced
		      text:[NSString stringWithFormat:@"%@ must be one of %@; Core Data cannot list allowed numbers.",
		                                      attribute.name, [constraint displayText]]
		   element:elementId];
		return;
	}
	[self note:ORMMappingUnenforced
	      text:[NSString stringWithFormat:@"The values of %@ are limited to %@, which Core Data cannot check.",
	                                      attribute.name, [constraint displayText]]
	   element:elementId];
}

/* An attribute holding the value type's values. */
- (ORMCDAttribute *)attributeFor:(ORMObjectType *)valueType
                            name:(NSString *)name
                          source:(NSString *)source
                        optional:(BOOL)optional
                  roleConstraint:(ORMValueConstraint *)roleConstraint
{
	ORMCDAttribute *attribute = [[ORMCDAttribute alloc] init];
	attribute.name = name;
	attribute.optional = optional;
	attribute.source = source;
	ORMDataType *dataType = valueType.dataType;
	attribute.attributeType = dataType != nil ? [ORMCoreDataMapper attributeTypeFor:dataType] : @"String";
	NSArray *transformable = [self.mapping.transformables objectForKey:valueType.identifier ?: @""];
	if (transformable != nil) {
		/* A class of its own, stored by its value transformer. */
		attribute.attributeType = @"Transformable";
		attribute.extraAttributes = @{ @"customClassName": [transformable firstObject],
		                               @"valueTransformerName": [transformable lastObject] };
		return attribute;
	}
	if (dataType == nil || dataType.family == ORMDataTypeUnspecified) {
		[self note:ORMMappingWarning
		      text:[NSString stringWithFormat:@"%@ has no data type; %@ is a String.", valueType.name, name]
		   element:valueType.identifier];
	}
	NSString *typeName = dataType.typeName;
	if ([typeName hasPrefix:@"Unsigned"]) {
		attribute.minValue = @"0";
	}
	if ([typeName isEqualToString:@"AutoCounterNumericDataType"]) {
		NSMutableDictionary *info = [attribute.userInfo mutableCopy];
		[info setObject:@"YES" forKey:@"ormkit.autoCounter"];
		attribute.userInfo = info;
	}
	if ([typeName isEqualToString:@"PictureRawDataDataType"] || [typeName isEqualToString:@"LargeLengthRawDataDataType"]) {
		attribute.allowsExternalStorage = YES;
	}
	if ([attribute.attributeType isEqualToString:@"String"] && valueType.dataTypeLength > 0) {
		attribute.maxValue = [NSString stringWithFormat:@"%ld", (long)valueType.dataTypeLength];
	}
	[self constrain:attribute by:roleConstraint ?: valueType.valueConstraint element:valueType.identifier];
	return attribute;
}

#pragma mark Identifiers

- (void)makeIdentifiers
{
	if (!self.mapping.materializesIdentifiers) {
		return;
	}
	for (ORMObjectType *type in self.model.objectTypes) {
		ORMCDEntity *entity = [self entityOf:type];
		if (entity == nil || ![entity.source isEqualToString:type.identifier] || type.referenceModeValueType == nil) {
			continue;
		}
		ORMFactType *fact = type.referenceModeFactType;
		ORMRole *valueRole = nil;
		ORMRole *ownRole = nil;
		for (ORMRole *role in fact.roles) {
			if (role.player == type) {
				ownRole = role;
			} else {
				valueRole = role;
			}
		}
		NSString *base = type.referenceModeKind == ORMReferenceModePopular
			? [ORMCoreDataMapper propertyNameFor:type.referenceMode]
			: [ORMCoreDataMapper propertyNameFor:type.referenceModeValueType.name];
		NSString *name = [self claimName:@[ valueRole.name ?: @"", base,
		                                    [ORMCoreDataMapper propertyNameFor:type.referenceModeValueType.name] ]
		                          source:valueRole.identifier on:entity];
		ORMCDAttribute *attribute = [self attributeFor:type.referenceModeValueType name:name source:valueRole.identifier
		                                      optional:!ownRole.isMandatory roleConstraint:valueRole.valueConstraint];
		[entity.attributes addObject:attribute];
		[entity.uniquenessConstraints addObject:@[ name ]];
	}
}

#pragma mark Fact types

/* The entity a many-valued use of a value type makes, made once. */
- (ORMCDEntity *)valueEntityFor:(ORMObjectType *)type
{
	ORMObjectType *valueType = [self valueTypeOf:type];
	ORMCDEntity *entity = [_valueEntities objectForKey:type.identifier];
	if (entity != nil) {
		return entity;
	}
	entity = [[ORMCDEntity alloc] init];
	entity.name = [self claimEntityName:type.name source:type.identifier];
	entity.source = type.identifier;
	entity.codeGenerationType = self.mapping.codeGenerationType;
	NSMutableDictionary *info = [entity.userInfo mutableCopy];
	[info setObject:@"YES" forKey:@"ormkit.valueEntity"];
	entity.userInfo = info;
	NSString *name = [self claimName:@[ @"value" ] source:[type.identifier stringByAppendingString:@".value"] on:entity];
	ORMCDAttribute *attribute = [self attributeFor:valueType name:name source:[type.identifier stringByAppendingString:@".value"]
	                                      optional:NO roleConstraint:nil];
	[entity.attributes addObject:attribute];
	[entity.uniquenessConstraints addObject:@[ name ]];
	[_out.entities addObject:entity];
	[_valueEntities setObject:entity forKey:type.identifier];
	return entity;
}

/* Whether the role is mandatory where its property goes: a folded
 * objectification's role is mandatory on its player only when the player
 * always plays the role it is one to one with. */
- (BOOL)mandatoryHere:(ORMRole *)role
{
	if (!role.isMandatory) {
		return NO;
	}
	ORMRole *fold = [_folds objectForKey:role.player.identifier ?: @""];
	return fold == nil || fold.isMandatory;
}

static NSString *
ORMCapitalized(NSString *name)
{
	return [name length] > 0 ? [[[name substringToIndex:1] uppercaseString] stringByAppendingString:[name substringFromIndex:1]]
	                         : name;
}

/* An absorbed composite's identifying values as properties of the entity
 * that refers to it: "shippingAddressStreet", "shippingAddressCity" (a
 * to-one relationship where the value is an entity). Their names. */
- (NSArray<NSString *> *)absorb:(ORMObjectType *)type
                           into:(ORMCDEntity *)entity
                         prefix:(NSString *)prefix
                         source:(NSString *)source
                       optional:(BOOL)optional
{
	NSMutableArray *names = [NSMutableArray array];
	for (ORMRole *component in [self compositeIdentificationOf:type]) {
		ORMObjectType *player = component.player;
		/* As the reading names it from the composite's side ("first
		 * StreetLine"), as a property for the role would be named. */
		NSString *base = [[self candidatesFor:component near:[component oppositeRole] toMany:NO] firstObject]
			?: [ORMCoreDataMapper propertyNameFor:player.name ?: @"value"];
		NSString *candidate = [prefix stringByAppendingString:ORMCapitalized(base)];
		NSString *componentSource = [source stringByAppendingFormat:@"/%@", component.identifier];
		ORMResolved resolved = [self resolved:player];
		if (resolved == ORMResolvedComposite) {
			[names addObjectsFromArray:[self absorb:player into:entity prefix:candidate source:componentSource
			                                optional:optional]];
		} else if (resolved == ORMResolvedValue) {
			NSString *name = [self claimName:@[ candidate ] source:componentSource on:entity];
			[entity.attributes addObject:[self attributeFor:[self valueTypeOf:player] name:name source:componentSource
			                                       optional:optional roleConstraint:component.valueConstraint]];
			[names addObject:name];
		} else if (resolved == ORMResolvedEntity || resolved == ORMResolvedFolded) {
			ORMCDEntity *target = [self entityOf:player];
			NSString *name = [self claimName:@[ candidate ] source:componentSource on:entity];
			NSString *plural = [ORMCoreDataMapper pluralOf:[ORMCoreDataMapper propertyNameFor:entity.name]];
			NSString *backwardName = [self claimName:@[ [plural stringByAppendingFormat:@"As%@", ORMCapitalized(candidate)],
			                                            plural ]
			                                  source:[componentSource stringByAppendingString:@".inverse"]
			                                      on:target];
			ORMCDRelationship *forward = [self relationshipNamed:name source:componentSource to:target toMany:NO near:nil];
			forward.optional = optional;
			ORMCDRelationship *backward = [self relationshipNamed:backwardName
			                                               source:[componentSource stringByAppendingString:@".inverse"]
			                                                   to:entity toMany:YES near:nil];
			forward.inverseName = backwardName;
			backward.inverseName = name;
			forward.deletionRule = @"Nullify";
			backward.deletionRule = @"Nullify";
			[entity.relationships addObject:forward];
			[target.relationships addObject:backward];
			[names addObject:name];
		}
	}
	return names;
}

/* A relationship from one entity to another, for the far role. */
- (ORMCDRelationship *)relationshipNamed:(NSString *)name
                                  source:(NSString *)source
                                      to:(ORMCDEntity *)destination
                                  toMany:(BOOL)toMany
                                    near:(ORMRole *)near
{
	ORMCDRelationship *relationship = [[ORMCDRelationship alloc] init];
	relationship.name = name;
	relationship.source = source;
	relationship.destination = destination.name;
	relationship.toMany = toMany;
	relationship.optional = near == nil || ![self mandatoryHere:near];
	if (toMany && [self mandatoryHere:near]) {
		relationship.minCount = 1;
	}
	/* A frequency on the near role bounds how many. */
	for (ORMConstraint *constraint in near.constraints) {
		if (constraint.kind == ORMFrequencyConstraint && [[constraint allRoles] count] == 1 && toMany) {
			relationship.minCount = MAX(relationship.minCount, constraint.minFrequency);
			relationship.maxCount = constraint.maxFrequency;
			if (constraint.minFrequency > 0 && ![self mandatoryHere:near]) {
				[self note:ORMMappingWarning
				      text:[NSString stringWithFormat:@"%@ holds at least %lu when it holds any; Core Data's "
				                                      @"minimum applies only when it is not empty.",
				                                      name, (unsigned long)constraint.minFrequency]
				   element:constraint.identifier];
			}
		}
	}
	return relationship;
}

/* The names a property for the far role could take, best first. */
/* The far role's player with the words a reading hyphen-binds to it
 * ("first- {1}": "first StreetLine"); nil without such words. */
- (NSString *)boundNameOf:(ORMRole *)far from:(ORMRole *)near
{
	ORMFactType *fact = far.factType;
	ORMReadingOrder *order = [fact readingOrderStartingWithRole:near] ?: [[fact primaryReading] readingOrder];
	ORMReading *reading = [order.readings firstObject];
	if (reading.text == nil) {
		return nil;
	}
	ORMReadingText *text = [ORMReadingText readingTextWithString:reading.text arity:[order.roles count] reason:NULL];
	for (ORMReadingPart *part in text.parts) {
		if (part.roleIndex < [order.roles count] && [order.roles objectAtIndex:part.roleIndex] == far
		    && ([part.preBoundText length] > 0 || [part.postBoundText length] > 0)) {
			return [NSString stringWithFormat:@"%@%@%@", part.preBoundText ?: @"", far.player.name ?: @"",
			                                  part.postBoundText ?: @""];
		}
	}
	return nil;
}

- (NSArray *)candidatesFor:(ORMRole *)far near:(ORMRole *)near toMany:(BOOL)toMany
{
	NSString *player = far.player.name ?: @"value";
	NSString *base = [ORMCoreDataMapper propertyNameFor:player];
	NSString *phrase = [ORMCoreDataMapper propertyNameFor:[self phraseOf:far.factType from:near]];
	NSMutableArray *candidates = [NSMutableArray array];
	if ([far.name length] > 0) {
		[candidates addObject:[ORMCoreDataMapper propertyNameFor:far.name]];
	}
	/* A name the reading binds to the player ("first StreetLine"). */
	NSString *bound = [self boundNameOf:far from:near];
	if (bound != nil) {
		[candidates addObject:[ORMCoreDataMapper propertyNameFor:bound]];
	}
	/* The way back along a named role says which: an Account's work
	 * orders as requestor and as assignee. */
	if ([far.name length] == 0 && [near.name length] > 0) {
		NSString *role = [ORMCoreDataMapper entityNameFor:near.name];
		[candidates addObject:[NSString stringWithFormat:@"%@As%@", toMany ? [ORMCoreDataMapper pluralOf:base] : base,
		                                                            role]];
	}
	[candidates addObject:toMany ? [ORMCoreDataMapper pluralOf:base] : base];
	[candidates addObject:toMany ? [ORMCoreDataMapper pluralOf:phrase] : phrase];
	return candidates;
}

/* Cascade when what is at the other end cannot be without this one: its
 * role is mandatory and unique, so it belongs to exactly one of these. */
static NSString *
ORMDeletionRule(ORMRole *far)
{
	return far.isMandatory && far.isUnique ? @"Cascade" : @"Nullify";
}

- (void)mapBinary:(ORMFactType *)fact
{
	NSArray *roles = [fact visibleRoles];
	ORMRole *first = [roles objectAtIndex:0];
	ORMRole *second = [roles objectAtIndex:1];
	/* A direction left out leaves the fact type out: a relationship
	 * without its inverse is not Core Data's way. */
	if ([self.mapping.excludedSources containsObject:first.identifier]
	    || [self.mapping.excludedSources containsObject:second.identifier]) {
		return;
	}
	ORMResolved a = [self resolved:first.player];
	ORMResolved b = [self resolved:second.player];
	/* A folded objectification is its player's entity. */
	a = a == ORMResolvedFolded ? ORMResolvedEntity : a;
	b = b == ORMResolvedFolded ? ORMResolvedEntity : b;
	if ((a == ORMResolvedEntity && b == ORMResolvedComposite) || (a == ORMResolvedComposite && b == ORMResolvedEntity)) {
		ORMRole *near = a == ORMResolvedEntity ? first : second;
		ORMRole *far = near == first ? second : first;
		ORMCDEntity *entity = [self entityOf:near.player];
		NSString *prefix = [[self candidatesFor:far near:near toMany:NO] firstObject]
			?: [ORMCoreDataMapper propertyNameFor:far.player.name ?: @"value"];
		NSArray *names = [self absorb:far.player into:entity prefix:prefix source:far.identifier
		                     optional:![self mandatoryHere:near]];
		if (far.isUnique && [names count] > 0) {
			[entity.uniquenessConstraints addObject:names];
		}
		return;
	}
	if (a == ORMResolvedEntity && b == ORMResolvedEntity) {
		[self mapEntity:first toEntity:second];
	} else if (a == ORMResolvedEntity && b == ORMResolvedValue) {
		[self mapEntity:first toValue:second];
	} else if (a == ORMResolvedValue && b == ORMResolvedEntity) {
		[self mapEntity:second toValue:first];
	} else if (a == ORMResolvedValue && b == ORMResolvedValue) {
		[self note:ORMMappingWarning
		      text:[NSString stringWithFormat:@"%@ relates two values and is not mapped.",
		                                      [[fact primaryReading] expandedText] ?: fact.name]
		   element:fact.identifier];
	}
}

- (void)mapEntity:(ORMRole *)first toEntity:(ORMRole *)second
{
	ORMCDEntity *from = [self entityOf:first.player];
	ORMCDEntity *to = [self entityOf:second.player];
	BOOL forwardMany = !first.isUnique;
	BOOL backwardMany = !second.isUnique;
	if (!first.isUnique && !second.isUnique && ![first.factType hasUniquenessOverRoles:@[ first, second ]]) {
		[self note:ORMMappingWarning
		      text:[NSString stringWithFormat:@"%@ has no uniqueness constraint; it is mapped as many to many.",
		                                      [[first.factType primaryReading] expandedText]]
		   element:first.factType.identifier];
	}
	NSString *forwardName = [self claimName:[self candidatesFor:second near:first toMany:forwardMany]
	                                 source:second.identifier on:from];
	NSString *backwardName = [self claimName:[self candidatesFor:first near:second toMany:backwardMany]
	                                  source:first.identifier on:to];
	ORMCDRelationship *forward = [self relationshipNamed:forwardName source:second.identifier to:to
	                                              toMany:forwardMany near:first];
	ORMCDRelationship *backward = [self relationshipNamed:backwardName source:first.identifier to:from
	                                               toMany:backwardMany near:second];
	forward.inverseName = backwardName;
	backward.inverseName = forwardName;
	forward.deletionRule = ORMDeletionRule(second);
	backward.deletionRule = ORMDeletionRule(first);
	[from.relationships addObject:forward];
	[to.relationships addObject:backward];
}

- (void)mapEntity:(ORMRole *)near toValue:(ORMRole *)far
{
	ORMCDEntity *entity = [self entityOf:near.player];
	ORMObjectType *valueType = [self valueTypeOf:far.player];
	ORMFactType *fact = near.factType;
	if (near.isUnique) {
		NSString *name = [self claimName:[self candidatesFor:far near:near toMany:NO] source:far.identifier on:entity];
		ORMCDAttribute *attribute = [self attributeFor:valueType name:name source:far.identifier
		                                      optional:![self mandatoryHere:near] roleConstraint:far.valueConstraint];
		[entity.attributes addObject:attribute];
		if (far.isUnique && ![self mandatoryHere:near]) {
			/* One to one with an optional value: unique where present,
			 * which a uniqueness constraint checks when it is set. */
			[entity.uniquenessConstraints addObject:@[ name ]];
		} else if (far.isUnique) {
			[entity.uniquenessConstraints addObject:@[ name ]];
		}
		return;
	}
	/* Many values for each instance. */
	if (!self.mapping.valueSetsAsEntities) {
		NSString *name = [self claimName:[self candidatesFor:far near:near toMany:YES] source:far.identifier on:entity];
		ORMCDAttribute *attribute = [[ORMCDAttribute alloc] init];
		attribute.name = name;
		attribute.source = far.identifier;
		attribute.attributeType = @"Transformable";
		attribute.optional = ![self mandatoryHere:near];
		attribute.extraAttributes = @{ @"valueTransformerName": @"NSSecureUnarchiveFromData", @"customClassName": @"NSArray" };
		[entity.attributes addObject:attribute];
		[self note:ORMMappingWarning
		      text:[NSString stringWithFormat:@"%@ is an array: Core Data cannot query or constrain its values.",
		                                      [[fact primaryReading] expandedText]]
		   element:fact.identifier];
		return;
	}
	ORMCDEntity *values = [self valueEntityFor:far.player];
	NSString *forwardName = [self claimName:[self candidatesFor:far near:near toMany:YES] source:far.identifier
	                                     on:entity];
	BOOL backwardMany = !far.isUnique;
	NSString *backwardName = [self claimName:[self candidatesFor:near near:far toMany:backwardMany]
	                                  source:near.identifier on:values];
	ORMCDRelationship *forward = [self relationshipNamed:forwardName source:far.identifier to:values toMany:YES
	                                                near:near];
	ORMCDRelationship *backward = [self relationshipNamed:backwardName source:near.identifier to:entity
	                                               toMany:backwardMany near:far];
	forward.inverseName = backwardName;
	backward.inverseName = forwardName;
	/* A value no one has any more is not worth keeping when it is only
	 * this instance's. */
	forward.deletionRule = backwardMany ? @"Nullify" : @"Cascade";
	[entity.relationships addObject:forward];
	[values.relationships addObject:backward];
}

- (void)mapUnary:(ORMFactType *)fact
{
	ORMRole *role = [[fact visibleRoles] firstObject];
	ORMRole *implicit = nil;
	for (ORMRole *each in fact.roles) {
		if (each != role) {
			implicit = each;
		}
	}
	ORMCDEntity *entity = [self entityOf:role.player];
	if (entity == nil || [self.mapping.excludedSources containsObject:implicit.identifier]) {
		return;
	}
	NSString *phrase = [ORMCoreDataMapper propertyNameFor:[self phraseOf:fact from:role]];
	NSMutableArray *candidates = [NSMutableArray array];
	if ([implicit.name length] > 0) {
		[candidates addObject:[ORMCoreDataMapper propertyNameFor:implicit.name]];
	}
	[candidates addObjectsFromArray:@[ phrase, [phrase stringByAppendingString:@"Flag"] ]];
	NSString *name = [self claimName:candidates source:implicit.identifier on:entity];
	ORMCDAttribute *attribute = [[ORMCDAttribute alloc] init];
	attribute.name = name;
	attribute.source = implicit.identifier;
	attribute.attributeType = @"Boolean";
	attribute.optional = NO;
	attribute.defaultValue = @"NO";
	[entity.attributes addObject:attribute];
}

/* A fact type with an entity of its own: an objectified one, or one of
 * three or more roles. A property per role, unique as its uniqueness
 * constraints say. */
- (void)mapAsEntity:(ORMFactType *)fact
{
	ORMCDEntity *entity = nil;
	if (fact.objectifyingType != nil) {
		entity = [self entityOf:fact.objectifyingType];
		if (entity == nil) {
			return;
		}
	} else {
		entity = [[ORMCDEntity alloc] init];
		entity.name = [self claimEntityName:[fact derivedName] source:fact.identifier];
		entity.source = fact.identifier;
		entity.codeGenerationType = self.mapping.codeGenerationType;
		[_out.entities addObject:entity];
	}
	NSMutableDictionary *names = [NSMutableDictionary dictionary];
	for (ORMRole *role in [fact visibleRoles]) {
		ORMResolved resolved = [self resolved:role.player];
		NSString *candidate = [ORMCoreDataMapper propertyNameFor:role.player.name ?: @"role"];
		NSArray *candidates = [role.name length] > 0 ? @[ [ORMCoreDataMapper propertyNameFor:role.name], candidate ]
		                                             : @[ candidate ];
		NSString *name = [self claimName:candidates source:role.identifier on:entity];
		[names setObject:name forKey:role.identifier];
		if (resolved == ORMResolvedComposite) {
			/* An absorbed composite's values, each a column of this one. */
			NSArray *parts = [self absorb:role.player into:entity prefix:name source:role.identifier optional:NO];
			[names setObject:parts forKey:role.identifier];
		} else if (resolved == ORMResolvedEntity || resolved == ORMResolvedFolded) {
			ORMCDEntity *player = [self entityOf:role.player];
			ORMCDRelationship *forward = [self relationshipNamed:name source:role.identifier to:player toMany:NO near:nil];
			forward.optional = NO;
			/* Unique by itself, the role is one to one: Core Data's inverse
			 * says so. */
			BOOL toMany = !role.isUnique;
			NSString *backwardStem = [ORMCoreDataMapper propertyNameFor:entity.name];
			NSString *backwardName = [self claimName:@[ toMany ? [ORMCoreDataMapper pluralOf:backwardStem] : backwardStem ]
			                                  source:[fact.identifier stringByAppendingFormat:@".%@", role.identifier]
			                                      on:player];
			ORMCDRelationship *backward = [[ORMCDRelationship alloc] init];
			backward.name = backwardName;
			backward.source = [fact.identifier stringByAppendingFormat:@".%@", role.identifier];
			backward.destination = entity.name;
			backward.toMany = toMany;
			backward.optional = ![self mandatoryHere:role];
			backward.minCount = toMany && [self mandatoryHere:role] ? 1 : 0;
			/* The fact cannot hold without its players. */
			backward.deletionRule = @"Cascade";
			forward.inverseName = backwardName;
			backward.inverseName = name;
			[entity.relationships addObject:forward];
			[player.relationships addObject:backward];
		} else if (resolved == ORMResolvedValue) {
			[entity.attributes addObject:[self attributeFor:[self valueTypeOf:role.player] name:name
			                                         source:role.identifier optional:NO
			                                 roleConstraint:role.valueConstraint]];
		}
	}
	for (ORMConstraint *constraint in [fact uniquenessConstraints]) {
		ORMRole *only = [[constraint allRoles] count] == 1 ? [[constraint allRoles] firstObject] : nil;
		if (only != nil && [[names objectForKey:only.identifier] isKindOfClass:[NSString class]]
		    && [self resolved:only.player] != ORMResolvedValue) {
			/* A to-one inverse already. */
			continue;
		}
		NSMutableArray *unique = [NSMutableArray array];
		NSUInteger covered = 0;
		for (ORMRole *role in [constraint allRoles]) {
			id name = [names objectForKey:role.identifier];
			if ([name isKindOfClass:[NSArray class]]) {
				[unique addObjectsFromArray:name];
				covered++;
			} else if (name != nil) {
				[unique addObject:name];
				covered++;
			}
		}
		if (covered == [[constraint allRoles] count]) {
			[entity.uniquenessConstraints addObject:unique];
		}
	}
}

- (BOOL)isMappable:(ORMFactType *)fact
{
	if (fact.kind != ORMFactTypeOrdinary || [self.mapping.excludedSources containsObject:fact.identifier]) {
		return NO;
	}
	for (ORMRole *role in [fact visibleRoles]) {
		ORMResolved resolved = [self resolved:role.player];
		if (resolved == ORMResolvedOutOfScope || resolved == ORMResolvedIgnored) {
			return NO;
		}
	}
	/* A composite's identifying fact types are its values, made where it
	 * is used. */
	for (ORMRole *role in [fact visibleRoles]) {
		if ([self resolved:role.player] == ORMResolvedComposite
		    && [[self compositeIdentificationOf:role.player] containsObject:[role oppositeRole]]) {
			return NO;
		}
	}
	/* Reference mode fact types are the identifiers of entities, and what
	 * an absorbed entity type's values are. */
	for (ORMRole *role in [fact visibleRoles]) {
		if (role.player.referenceModeFactType == fact) {
			return NO;
		}
	}
	return YES;
}

- (void)mapFactTypes
{
	for (ORMFactType *fact in self.model.factTypes) {
		if (![self isMappable:fact]) {
			continue;
		}
		NSUInteger arity = [fact arity];
		BOOL folded = fact.objectifyingType != nil && [self resolved:fact.objectifyingType] == ORMResolvedFolded;
		if ((fact.objectifyingType != nil && !folded) || arity > 2) {
			[self mapAsEntity:fact];
		} else if (arity == 2) {
			[self mapBinary:fact];
		} else if (arity == 1) {
			[self mapUnary:fact];
		}
	}
}

#pragma mark Constraints

/* The property, on the entity, that a role's fact type made there for
 * its far end. */
- (ORMCDProperty *)propertyOn:(ORMCDEntity *)entity forFarRole:(ORMRole *)role
{
	for (ORMCDEntity *at = entity; at != nil; at = at.parentName != nil ? [_out entityNamed:at.parentName] : nil) {
		for (ORMCDProperty *property in [at properties]) {
			if ([property.source isEqualToString:role.identifier]) {
				return property;
			}
		}
		if (at.parentName == nil) {
			break;
		}
	}
	return nil;
}

- (void)mapExternalUniqueness:(ORMConstraint *)constraint
{
	ORMObjectType *joined = nil;
	for (ORMRole *role in [constraint allRoles]) {
		ORMObjectType *player = [role oppositeRole].player;
		if (player == nil || (joined != nil && player != joined)) {
			joined = nil;
			break;
		}
		joined = player;
	}
	ORMCDEntity *entity = [self entityOf:joined];
	NSMutableArray *names = [NSMutableArray array];
	for (ORMRole *role in [constraint allRoles]) {
		ORMCDProperty *property = entity != nil ? [self propertyOn:entity forFarRole:role] : nil;
		if (property == nil || ([property isKindOfClass:[ORMCDRelationship class]] && [(ORMCDRelationship *)property toMany])) {
			names = nil;
			break;
		}
		[names addObject:property.name];
	}
	if (names != nil && [names count] > 0) {
		[entity.uniquenessConstraints addObject:names];
	} else {
		[self unenforced:constraint];
	}
}

/* A constraint Core Data cannot hold, kept as its verbalization on the
 * entity it is about and reported. */
- (void)unenforced:(ORMConstraint *)constraint
{
	NSArray *sentences = [[[ORMVerbalizer alloc] initWithModel:self.model] sentencesForElement:constraint.identifier];
	NSMutableArray *texts = [NSMutableArray array];
	for (ORMVerbalSentence *sentence in sentences) {
		[texts addObject:[sentence text]];
	}
	NSString *text = [texts count] > 0 ? [texts componentsJoinedByString:@" "] : constraint.name;
	ORMCDEntity *entity = nil;
	for (ORMRole *role in [constraint allRoles]) {
		entity = [self entityOf:role.player] ?: [self entityOf:[role oppositeRole].player];
		if (role.factType.objectifyingType != nil || [role.factType arity] > 2) {
			entity = [_out entityWithSource:role.factType.identifier] ?: [self entityOf:role.factType.objectifyingType]
				?: entity;
		}
		if (entity != nil) {
			break;
		}
	}
	if (entity != nil) {
		NSMutableDictionary *info = [entity.userInfo mutableCopy];
		[info setObject:text forKey:[@"ormkit.rule." stringByAppendingString:constraint.name ?: constraint.identifier]];
		entity.userInfo = info;
	}
	[self note:ORMMappingUnenforced text:text element:constraint.identifier];
}

- (BOOL)isConstraintInScope:(ORMConstraint *)constraint
{
	for (ORMRole *role in [constraint allRoles]) {
		ORMResolved resolved = [self resolved:role.player];
		if (resolved == ORMResolvedOutOfScope || resolved == ORMResolvedIgnored) {
			return NO;
		}
	}
	return [[constraint allRoles] count] > 0;
}

/* Whether the uniqueness is the identification of an absorbed
 * composite: its identity, gone with it. */
- (BOOL)identifiesComposite:(ORMConstraint *)constraint
{
	ORMObjectType *joined = [[[constraint allRoles] firstObject] oppositeRole].player;
	return [self resolved:joined] == ORMResolvedComposite
		&& [[self compositeIdentificationOf:joined] isEqualToArray:[constraint allRoles]];
}

- (void)mapConstraints
{
	for (ORMConstraint *constraint in self.model.constraints) {
		if (constraint.isImplied || ![self isConstraintInScope:constraint]) {
			continue;
		}
		BOOL subtyping = NO;
		for (ORMRole *role in [constraint allRoles]) {
			subtyping = subtyping || role.isSupertypeMetaRole || role.isSubtypeMetaRole;
		}
		switch (constraint.kind) {
		case ORMUniquenessConstraint:
			if (!constraint.isInternal && ![self identifiesComposite:constraint]) {
				[self mapExternalUniqueness:constraint];
			}
			break;
		case ORMMandatoryConstraint:
			if (!constraint.isSimple && !subtyping && constraint.exclusiveOrPartner == nil) {
				[self unenforced:constraint];
			}
			break;
		case ORMFrequencyConstraint:
			if ([[constraint allRoles] count] > 1 || [[[constraint allRoles] firstObject] oppositeRole] == nil) {
				[self unenforced:constraint];
			}
			break;
		case ORMExclusionConstraint:
			if (!subtyping) {
				[self unenforced:constraint];
			}
			break;
		case ORMRingConstraint:
		case ORMSubsetConstraint:
		case ORMEqualityConstraint:
		case ORMValueComparisonConstraint:
			[self unenforced:constraint];
			break;
		}
		if (constraint.modality == ORMDeontic && constraint.kind != ORMExclusionConstraint
		    && constraint.kind != ORMRingConstraint) {
			[self note:ORMMappingWarning
			      text:[NSString stringWithFormat:@"%@ is deontic, a rule to be told of rather than enforced; Core "
			                                      @"Data enforces it.", constraint.name]
			   element:constraint.identifier];
		}
	}
}

/* Core Data refuses uniqueness constraints on an entity that another
 * entity has a mandatory to-one relationship to: merging on a constraint
 * could leave the reference dangling. The constraint is what identifies
 * the entity, so it stays; the relationship is made optional, and its being
 * mandatory is kept in userInfo and reported. */
- (void)loosenMandatoryReferencesToUniqueEntities
{
	NSMutableSet *constrained = [NSMutableSet set];
	for (ORMCDEntity *entity in _out.entities) {
		if ([entity.uniquenessConstraints count] == 0) {
			continue;
		}
		/* The constraint applies through the inheritance tree. */
		NSMutableArray *pending = [NSMutableArray arrayWithObject:entity.name];
		while ([pending count] > 0) {
			NSString *name = [pending lastObject];
			[pending removeLastObject];
			if ([constrained containsObject:name]) {
				continue;
			}
			[constrained addObject:name];
			for (ORMCDEntity *subentity in [_out subentitiesOf:name]) {
				[pending addObject:subentity.name];
			}
		}
	}
	for (ORMCDEntity *entity in _out.entities) {
		for (ORMCDRelationship *relationship in entity.relationships) {
			if (relationship.toMany || relationship.optional || ![constrained containsObject:relationship.destination]) {
				continue;
			}
			relationship.optional = YES;
			NSMutableDictionary *info = [relationship.userInfo mutableCopy];
			[info setObject:@"YES" forKey:@"ormkit.mandatory"];
			relationship.userInfo = info;
			[self note:ORMMappingUnenforced
			      text:[NSString stringWithFormat:@"%@.%@ is mandatory, but optional in Core Data: %@ has a "
			                                      @"uniqueness constraint, and Core Data allows no mandatory "
			                                      @"to-one relationship to such an entity.",
			                                      entity.name, relationship.name, relationship.destination]
			   element:relationship.source];
		}
	}
}

#pragma mark Mapping

- (ORMCDModel *)map
{
	_out = [ORMCDModel model];
	_notes = [NSMutableArray array];
	_resolved = [NSMutableDictionary dictionary];
	_folds = [NSMutableDictionary dictionary];
	_entityOf = [NSMutableDictionary dictionary];
	_valueEntities = [NSMutableDictionary dictionary];
	_names = [NSMutableDictionary dictionary];
	_entityNames = [NSMutableSet set];
	[self resolveObjectTypes];
	[self makeEntities];
	[self makeIdentifiers];
	[self mapFactTypes];
	[self mapConstraints];
	[self loosenMandatoryReferencesToUniqueEntities];
	ORMCDModel *made = _out;
	_out = nil;
	return made;
}

- (NSArray<ORMMappingNote *> *)notes
{
	return _notes ?: @[];
}

@end
