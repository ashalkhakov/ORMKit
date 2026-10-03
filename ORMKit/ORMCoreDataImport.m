/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataImport.h"
#import "ORMEditorPriv.h"

static NSString *
ORMCapitalizedName(NSString *name)
{
	return [name length] > 0 ? [[[name substringToIndex:1] uppercaseString] stringByAppendingString:[name substringFromIndex:1]]
	                         : name;
}

/* "isActive" to @[ "is", "active" ]: a property name's words. */
static NSArray<NSString *> *
ORMWordsOf(NSString *name)
{
	NSMutableArray *words = [NSMutableArray array];
	NSMutableString *word = [NSMutableString string];
	for (NSUInteger i = 0; i < [name length]; i++) {
		unichar c = [name characterAtIndex:i];
		BOOL upper = [[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c];
		BOOL separator = c == '_' || c == ' ';
		if ((upper || separator) && [word length] > 0) {
			[words addObject:[word lowercaseString]];
			[word setString:@""];
		}
		if (!separator) {
			[word appendFormat:@"%C", c];
		}
	}
	if ([word length] > 0) {
		[words addObject:[word lowercaseString]];
	}
	return words;
}

/* A unary reading for a Boolean: "isActive" is "{0} is active", "flattens"
 * "{0} flattens", "deleted" "{0} is deleted". */
static NSString *
ORMUnaryReadingFor(NSString *name)
{
	NSArray *words = ORMWordsOf(name);
	NSSet *verbs = [NSSet setWithArray:@[ @"is", @"has", @"was", @"can", @"does", @"may", @"must", @"uses", @"allows" ]];
	BOOL verb = [words count] > 0 && ([verbs containsObject:[words firstObject]] || [[words firstObject] hasSuffix:@"s"]);
	return [NSString stringWithFormat:@"{0} %@%@", verb ? @"" : @"is ", [words componentsJoinedByString:@" "]];
}

/* Required, or required in ORM and loosened for Core Data, which allows no
 * required to-one to an entity with a uniqueness constraint. */
static BOOL
ORMRequired(ORMCDRelationship *relationship)
{
	return !relationship.optional || [[relationship.userInfo objectForKey:@"ormkit.mandatory"] isEqualToString:@"YES"];
}

/* What an import keeps track of. */
@interface ORMImportState : NSObject
@property (nonatomic, copy) NSString *mapping;
@property (nonatomic, copy) NSString *diagram;
/* Entity name -> object type id. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *types;
/* "Entity.property" -> the role whose property it is (a value's, a
 * relationship's far one). */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *roles;
@property (nonatomic, strong) NSMutableArray<NSString *> *notes;
@end

@implementation ORMImportState
@end

@implementation ORMEditor (ORMCoreDataImport)

/* An entity that only joins others: to-one relationships, two or more,
 * required and unique together, no other relationships. */
- (NSArray<ORMCDRelationship *> *)joinedBy:(ORMCDEntity *)entity in:(ORMCDModel *)model
{
	/* A supertype or subtype is a thing, not a join. */
	if (entity.parentName != nil || [[model subentitiesOf:entity.name] count] > 0) {
		return nil;
	}
	NSMutableArray *toOne = [NSMutableArray array];
	for (ORMCDRelationship *relationship in entity.relationships) {
		if (relationship.toMany) {
			return nil;
		}
		[toOne addObject:relationship];
	}
	if ([toOne count] < 2) {
		return nil;
	}
	NSSet *names = [NSSet setWithArray:[toOne valueForKey:@"name"]];
	for (NSArray *unique in entity.uniquenessConstraints) {
		if ([[NSSet setWithArray:unique] isEqualToSet:names]) {
			return toOne;
		}
	}
	return nil;
}

/* The value type for an attribute: one of its name and data type reused,
 * else a new one, named for the entity where the name is taken. */
- (NSString *)valueTypeFor:(ORMCDAttribute *)attribute of:(NSString *)entityName
{
	NSString *dataType = ORMDataTypeForAttributeType(attribute.attributeType);
	NSString *name = [ORMCoreDataMapper entityNameFor:attribute.name];
	ORMObjectType *existing = [self.model objectTypeNamed:name];
	if (existing != nil && existing.kind == ORMValueType && [existing.dataType.typeName isEqualToString:dataType]
	    && ![attribute.attributeType isEqualToString:@"Transformable"]) {
		return existing.identifier;
	}
	if (existing != nil) {
		name = [entityName stringByAppendingString:name];
	}
	name = [self uniqueObjectTypeName:name];
	NSString *made = [self addValueTypeNamed:name dataType:dataType onDiagram:nil at:NSZeroPoint reason:NULL];
	if (made != nil && [attribute.attributeType isEqualToString:@"String"] && [attribute.maxValue integerValue] > 0) {
		[self setDataType:dataType length:[attribute.maxValue integerValue] scale:0 of:made reason:NULL];
	}
	return made;
}

- (void)addAttribute:(ORMCDAttribute *)attribute of:(ORMCDEntity *)entity to:(NSString *)typeId state:(ORMImportState *)state
{
	NSString *path = [NSString stringWithFormat:@"%@.%@", entity.name, attribute.name];
	/* A required Boolean is a unary: absent means false. */
	if ([attribute.attributeType isEqualToString:@"Boolean"] && !attribute.optional) {
		NSString *fact = [self addFactTypeWithPlayers:@[ typeId ] reading:ORMUnaryReadingFor(attribute.name)
		                                    onDiagram:state.diagram at:ORMAutomaticPlacement reason:NULL];
		ORMFactType *made = [self.model elementWithId:fact];
		for (ORMRole *role in made.roles) {
			if (role.player.isImplicitBooleanValue) {
				[self setName:attribute.name forSource:role.identifier inMapping:state.mapping];
				[state.roles setObject:role.identifier forKey:path];
			}
		}
		return;
	}
	NSString *valueId = [self valueTypeFor:attribute of:entity.name];
	if (valueId == nil) {
		return;
	}
	NSString *fact = [self addFactTypeWithPlayers:@[ typeId, valueId ] reading:@"{0} has {1}" onDiagram:state.diagram
	                                           at:ORMAutomaticPlacement reason:NULL];
	ORMFactType *made = [self.model elementWithId:fact];
	ORMRole *near = [made.roles objectAtIndex:0];
	ORMRole *far = [made.roles objectAtIndex:1];
	[self setUnique:YES role:near.identifier reason:NULL];
	if (!attribute.optional) {
		[self setMandatory:YES role:near.identifier reason:NULL];
	}
	for (NSArray *names in entity.uniquenessConstraints) {
		if ([names isEqualToArray:@[ attribute.name ]]) {
			[self setUnique:YES role:far.identifier reason:NULL];
		}
	}
	NSString *values = ORMValueConstraintForAttribute(attribute);
	if ([values length] > 0) {
		[self setValueConstraint:values of:far.identifier reason:NULL];
	}
	if ([attribute.attributeType isEqualToString:@"Transformable"]) {
		[self setTransformableClass:[attribute.extraAttributes objectForKey:@"customClassName"]
		                transformer:[attribute.extraAttributes objectForKey:@"valueTransformerName"]
		               ofObjectType:valueId
		                  inMapping:state.mapping];
	}
	[self setName:attribute.name forSource:far.identifier inMapping:state.mapping];
	[state.roles setObject:far.identifier forKey:path];
}

/* "Order has billing- Address" for a billingAddress to an Address. */
- (NSString *)readingFor:(ORMCDRelationship *)relationship
{
	NSString *destination = [ORMCoreDataMapper propertyNameFor:relationship.destination];
	NSString *name = relationship.name;
	if (relationship.toMany) {
		/* "billingAddresses" is many of "billingAddress". */
		NSString *plural = [ORMCoreDataMapper pluralOf:destination];
		if ([name hasSuffix:ORMCapitalizedName(plural)]) {
			name = [[name substringToIndex:[name length] - [plural length]] stringByAppendingString:ORMCapitalizedName(destination)];
		}
	}
	NSString *suffix = ORMCapitalizedName(destination);
	if ([name length] > [suffix length] && [name hasSuffix:suffix]) {
		NSString *prefix = [[ORMWordsOf([name substringToIndex:[name length] - [suffix length]])
			componentsJoinedByString:@" "] lowercaseString];
		return [NSString stringWithFormat:@"{0} has %@- {1}", prefix];
	}
	return @"{0} has {1}";
}

- (void)addRelationship:(ORMCDRelationship *)relationship
                     of:(ORMCDEntity *)entity
                inverse:(ORMCDRelationship *)inverse
                  state:(ORMImportState *)state
{
	NSString *from = [state.types objectForKey:entity.name];
	NSString *to = [state.types objectForKey:relationship.destination];
	if (from == nil || to == nil) {
		return;
	}
	NSString *fact = [self addFactTypeWithPlayers:@[ from, to ] reading:[self readingFor:relationship]
	                                    onDiagram:state.diagram at:ORMAutomaticPlacement reason:NULL];
	ORMFactType *made = [self.model elementWithId:fact];
	ORMRole *near = [made.roles objectAtIndex:0];
	ORMRole *far = [made.roles objectAtIndex:1];
	BOOL manyBack = inverse == nil || inverse.toMany;
	if (!relationship.toMany) {
		[self setUnique:YES role:near.identifier reason:NULL];
	}
	if (!manyBack) {
		[self setUnique:YES role:far.identifier reason:NULL];
	}
	if (relationship.toMany && manyBack) {
		[self addUniquenessConstraintOverRoles:@[ near.identifier, far.identifier ] reason:NULL];
	}
	if (ORMRequired(relationship)) {
		[self setMandatory:YES role:near.identifier reason:NULL];
	}
	if (inverse != nil && ORMRequired(inverse)) {
		[self setMandatory:YES role:far.identifier reason:NULL];
	}
	/* How many, beyond "some": a frequency. */
	for (NSArray *pair in @[ @[ relationship, near ], @[ inverse ?: [NSNull null], far ] ]) {
		ORMCDRelationship *side = [pair firstObject];
		if ((id)side == [NSNull null] || !side.toMany || (side.minCount <= 1 && side.maxCount == 0)) {
			continue;
		}
		[self addFrequencyConstraintOverRoles:@[ [[pair lastObject] identifier] ] min:MAX(side.minCount, (NSUInteger)1)
		                                  max:side.maxCount reason:NULL];
	}
	[self setName:relationship.name forSource:far.identifier inMapping:state.mapping];
	[state.roles setObject:far.identifier forKey:[NSString stringWithFormat:@"%@.%@", entity.name, relationship.name]];
	if (inverse != nil) {
		[self setName:inverse.name forSource:near.identifier inMapping:state.mapping];
		[state.roles setObject:near.identifier forKey:[NSString stringWithFormat:@"%@.%@", relationship.destination,
		                                                                         inverse.name]];
	} else {
		[state.notes addObject:[NSString stringWithFormat:@"%@.%@ has no inverse; the fact type has both directions.",
		                                                  entity.name, relationship.name]];
	}
	if (relationship.ordered || inverse.ordered) {
		[state.notes addObject:[NSString stringWithFormat:@"%@.%@ is ordered; ORM keeps no order.", entity.name,
		                                                  relationship.name]];
	}
}

/* The attributes a join's uniqueness takes in with what it joins: each a
 * role of the fact type too ("SetComparisonRoles": a constraint's role
 * sequence at an ordinal, unique in either pair). */
- (NSArray<ORMCDAttribute *> *)attributesJoinedBy:(ORMCDEntity *)entity over:(NSArray<ORMCDRelationship *> *)relationships
{
	NSSet *joined = [NSSet setWithArray:[relationships valueForKey:@"name"]];
	NSMutableArray *attributes = [NSMutableArray array];
	for (NSArray *names in entity.uniquenessConstraints) {
		NSMutableArray *taken = [NSMutableArray array];
		BOOL within = YES;
		for (NSString *name in names) {
			ORMCDAttribute *attribute = [entity attributeNamed:name];
			if (attribute != nil && !attribute.optional && ![attribute.attributeType isEqualToString:@"Transformable"]) {
				[taken addObject:attribute];
			} else if (![joined containsObject:name]) {
				within = NO;
			}
		}
		if (within && [taken count] > 0 && [taken count] < [names count]) {
			for (ORMCDAttribute *attribute in taken) {
				if (![attributes containsObject:attribute]) {
					[attributes addObject:attribute];
				}
			}
		}
	}
	return attributes;
}

/* A join entity as an objectified fact type over what it joins. */
- (void)addJoin:(ORMCDEntity *)entity over:(NSArray<ORMCDRelationship *> *)relationships state:(ORMImportState *)state
{
	NSArray *attributes = [self attributesJoinedBy:entity over:relationships];
	NSMutableArray *players = [NSMutableArray array];
	NSMutableArray *places = [NSMutableArray array];
	NSMutableArray *properties = [NSMutableArray array];
	for (ORMCDRelationship *relationship in relationships) {
		NSString *player = [state.types objectForKey:relationship.destination];
		if (player == nil) {
			return;
		}
		[players addObject:player];
		[properties addObject:relationship.name];
		[places addObject:[NSString stringWithFormat:@"{%lu}", (unsigned long)[places count]]];
	}
	for (ORMCDAttribute *attribute in attributes) {
		NSString *player = [self valueTypeFor:attribute of:entity.name];
		if (player == nil) {
			return;
		}
		[players addObject:player];
		[properties addObject:attribute.name];
		[places addObject:[NSString stringWithFormat:@"{%lu}", (unsigned long)[places count]]];
	}
	NSString *reading = [players count] == 2 ? @"{0} is with {1}"
		: [NSString stringWithFormat:@"%@ with %@", [[places subarrayWithRange:NSMakeRange(0, [places count] - 1)]
		                                                componentsJoinedByString:@", "], [places lastObject]];
	NSString *fact = [self addFactTypeWithPlayers:players reading:reading onDiagram:state.diagram
	                                           at:ORMAutomaticPlacement reason:NULL];
	ORMFactType *made = [self.model elementWithId:fact];
	NSArray *roles = [made visibleRoles];
	/* Each uniqueness over the fact type's roles, one of them over what
	 * it joins. */
	for (NSArray *names in entity.uniquenessConstraints) {
		NSMutableArray *spanned = [NSMutableArray array];
		for (NSString *name in names) {
			NSUInteger at = [properties indexOfObject:name];
			if (at != NSNotFound) {
				[spanned addObject:[[roles objectAtIndex:at] identifier]];
			}
		}
		if ([spanned count] == [names count]) {
			[self addUniquenessConstraintOverRoles:spanned reason:NULL];
		}
	}
	NSString *nested = [self objectifyFactType:fact named:entity.name reason:NULL];
	if (nested == nil) {
		return;
	}
	[state.types setObject:nested forKey:entity.name];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		NSString *property = [properties objectAtIndex:i];
		[self rename:role.identifier to:property reason:NULL];
		[self setName:property forSource:role.identifier inMapping:state.mapping];
		[state.roles setObject:role.identifier forKey:[NSString stringWithFormat:@"%@.%@", entity.name, property]];
	}
}

- (NSString *)importCoreDataModel:(ORMCDModel *)model
                             path:(NSString *)path
                            notes:(NSArray<NSString *> **)notes
                           reason:(NSString **)reason
{
	if ([model.entities count] == 0) {
		if (reason != NULL) {
			*reason = @"The Core Data model has no entities.";
		}
		return nil;
	}
	ORMImportState *state = [[ORMImportState alloc] init];
	state.types = [NSMutableDictionary dictionary];
	state.roles = [NSMutableDictionary dictionary];
	state.notes = [NSMutableArray array];
	NSString *name = [[[path lastPathComponent] stringByDeletingPathExtension] length] > 0
		? [[path lastPathComponent] stringByDeletingPathExtension] : @"Core Data";
	[self group:@"Import Core Data Model" with:^{
		state.mapping = [self addCoreDataMappingNamed:name path:path];
		/* Nothing absorbed: the model maps back as it came. */
		[self setStyle:ORMStyleEntities ofMapping:state.mapping];
		/* A new model's empty diagram, else one of its own. */
		ORMDiagram *only = [self.model.diagrams count] == 1 ? [self.model.diagrams firstObject] : nil;
		state.diagram = only != nil && [[only allShapes] count] == 0 ? only.identifier : [self addDiagramNamed:name];

		/* Entity types first, but for the entities that only join. */
		NSMutableDictionary *joins = [NSMutableDictionary dictionary];
		for (ORMCDEntity *entity in model.entities) {
			NSArray *joined = [self joinedBy:entity in:model];
			if (joined != nil) {
				[joins setObject:joined forKey:entity.name];
				continue;
			}
			NSString *type = [self addEntityTypeNamed:[self uniqueObjectTypeName:entity.name] referenceMode:nil
			                                     kind:ORMReferenceModeNone onDiagram:state.diagram
			                                       at:ORMAutomaticPlacement reason:NULL];
			if (type == nil) {
				continue;
			}
			[state.types setObject:type forKey:entity.name];
			[self setName:entity.name forSource:type inMapping:state.mapping];
		}
		/* Subtyping, so subtypes take their supertype's identification. */
		for (ORMCDEntity *entity in model.entities) {
			NSString *sub = [state.types objectForKey:entity.name];
			NSString *sup = entity.parentName != nil ? [state.types objectForKey:entity.parentName] : nil;
			if (sub != nil && sup != nil) {
				[self addSubtype:sub of:sup reason:NULL];
			}
		}
		/* Identification: a required, unique attribute is a reference
		 * mode. */
		NSMutableDictionary *identifiers = [NSMutableDictionary dictionary];
		for (ORMCDEntity *entity in model.entities) {
			NSString *type = [state.types objectForKey:entity.name];
			if (type == nil || entity.parentName != nil) {
				continue;
			}
			ORMCDAttribute *identifier = nil;
			for (NSArray *names in entity.uniquenessConstraints) {
				ORMCDAttribute *attribute = [names count] == 1 ? [entity attributeNamed:[names firstObject]] : nil;
				if (attribute != nil && !attribute.optional && identifier == nil
				    && ![attribute.attributeType isEqualToString:@"Transformable"]) {
					identifier = attribute;
				}
			}
			if (identifier == nil) {
				continue;
			}
			if (![self setReferenceMode:identifier.name kind:ORMReferenceModePopular ofEntity:type reason:NULL]) {
				continue;
			}
			ORMObjectType *entityType = [self.model elementWithId:type];
			ORMObjectType *value = entityType.referenceModeValueType;
			[self setDataType:ORMDataTypeForAttributeType(identifier.attributeType)
			           length:[identifier.attributeType isEqualToString:@"String"] ? [identifier.maxValue integerValue] : 0
			            scale:0
			               of:value.identifier
			           reason:NULL];
			/* The model is rebuilt: what it held is gone. */
			entityType = [self.model elementWithId:type];
			value = entityType.referenceModeValueType;
			for (ORMRole *role in entityType.referenceModeFactType.roles) {
				if (role.player == value) {
					[self setName:identifier.name forSource:role.identifier inMapping:state.mapping];
					[state.roles setObject:role.identifier forKey:[NSString stringWithFormat:@"%@.%@", entity.name,
					                                                                       identifier.name]];
				}
			}
			[identifiers setObject:identifier.name forKey:entity.name];
		}
		/* The joins, now that what they join exists. */
		for (ORMCDEntity *entity in model.entities) {
			NSArray *joined = [joins objectForKey:entity.name];
			if (joined != nil) {
				[self addJoin:entity over:joined state:state];
			}
		}
		/* Attributes. */
		for (ORMCDEntity *entity in model.entities) {
			NSString *type = [state.types objectForKey:entity.name];
			for (ORMCDAttribute *attribute in entity.attributes) {
				/* An identifier's, or a role of the fact a join is. */
				if (type != nil && ![[identifiers objectForKey:entity.name] isEqualToString:attribute.name]
				    && [state.roles objectForKey:[NSString stringWithFormat:@"%@.%@", entity.name, attribute.name]] == nil) {
					[self addAttribute:attribute of:entity to:type state:state];
				}
			}
		}
		/* Relationships, a pair once; a join's are its roles. */
		NSMutableSet *done = [NSMutableSet set];
		for (ORMCDEntity *entity in model.entities) {
			for (ORMCDRelationship *relationship in entity.relationships) {
				NSString *key = [NSString stringWithFormat:@"%@.%@", entity.name, relationship.name];
				if ([done containsObject:key] || [joins objectForKey:entity.name] != nil) {
					continue;
				}
				ORMCDRelationship *inverse = [[model entityNamed:relationship.destination]
					relationshipNamed:relationship.inverseName];
				if ([joins objectForKey:relationship.destination] != nil) {
					/* The way back from a join: the objectification's role. */
					NSString *role = [state.roles objectForKey:[NSString stringWithFormat:@"%@.%@", relationship.destination,
					                                                                       relationship.inverseName]];
					ORMRole *joinRole = [self.model elementWithId:role];
					if (joinRole != nil) {
						[self setName:relationship.name
						    forSource:[joinRole.factType.identifier stringByAppendingFormat:@".%@", joinRole.identifier]
						    inMapping:state.mapping];
						if (ORMRequired(relationship)) {
							[self setMandatory:YES role:joinRole.identifier reason:NULL];
						}
						if (!relationship.toMany) {
							[self setUnique:YES role:joinRole.identifier reason:NULL];
						}
					}
					[done addObject:key];
					continue;
				}
				[done addObject:key];
				if (inverse != nil) {
					[done addObject:[NSString stringWithFormat:@"%@.%@", relationship.destination, inverse.name]];
				}
				[self addRelationship:relationship of:entity inverse:inverse state:state];
			}
		}
		/* Uniqueness over more than one property: an external uniqueness,
		 * the identifier of what has none. */
		for (ORMCDEntity *entity in model.entities) {
			NSString *type = [state.types objectForKey:entity.name];
			if (type == nil || [joins objectForKey:entity.name] != nil) {
				continue;
			}
			for (NSArray *names in entity.uniquenessConstraints) {
				if ([names count] < 2) {
					continue;
				}
				NSMutableArray *roles = [NSMutableArray array];
				for (NSString *property in names) {
					NSString *role = [state.roles objectForKey:[NSString stringWithFormat:@"%@.%@", entity.name, property]];
					if (role != nil) {
						[roles addObject:role];
					}
				}
				if ([roles count] != [names count]) {
					NSMutableArray *missing = [NSMutableArray array];
					for (NSString *property in names) {
						if ([state.roles objectForKey:[NSString stringWithFormat:@"%@.%@", entity.name, property]] == nil) {
							[missing addObject:property];
						}
					}
					[state.notes addObject:[NSString stringWithFormat:@"%@'s uniqueness over %@ is not said in ORM: %@ "
					                                                  @"is no role of it.",
					                                                  entity.name, [names componentsJoinedByString:@", "],
					                                                  [missing componentsJoinedByString:@", "]]];
					continue;
				}
				NSString *unique = [self addUniquenessConstraintOverRoles:roles reason:NULL];
				ORMObjectType *entityType = [self.model elementWithId:type];
				if (unique != nil && entityType.preferredIdentifier == nil && entity.parentName == nil) {
					[self setPreferredIdentifier:unique reason:NULL];
				}
			}
		}
		/* An abstract entity is covered by its subentities. */
		for (ORMCDEntity *entity in model.entities) {
			ORMObjectType *supertype = [self.model elementWithId:[state.types objectForKey:entity.name] ?: @""];
			if (!entity.isAbstract || supertype == nil || [supertype.subtypes count] == 0) {
				continue;
			}
			NSMutableArray *roles = [NSMutableArray array];
			for (ORMRole *role in supertype.playedRoles) {
				if (role.isSupertypeMetaRole) {
					[roles addObject:role.identifier];
				}
			}
			if ([roles count] > 1) {
				[self addMandatoryConstraintOverRoles:roles reason:NULL];
			} else if ([roles count] == 1) {
				[self setMandatory:YES role:[roles firstObject] reason:NULL];
			}
		}
		/* An entity without a way to be told apart. */
		for (ORMCDEntity *entity in model.entities) {
			ORMObjectType *type = [self.model elementWithId:[state.types objectForKey:entity.name] ?: @""];
			if (type != nil && type.preferredIdentifier == nil && [type.supertypes count] == 0 && type.nestedFactType == nil) {
				[state.notes addObject:[NSString stringWithFormat:@"%@ has no uniqueness constraint to identify it by; "
				                                                  @"ORM wants a reference scheme.", entity.name]];
			}
		}
		[self setBaseline:model ofMapping:state.mapping];
		[self arrangeDiagram:state.diagram];
	}];
	if (notes != NULL) {
		*notes = state.notes;
	}
	return state.mapping;
}

@end
