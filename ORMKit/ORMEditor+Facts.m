/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMReadingText.h"

@implementation ORMEditor (ORMFacts)

#pragma mark Fact types

- (NSString *)addFactTypeWithPlayers:(NSArray<NSString *> *)objectTypeIds
                             reading:(NSString *)reading
                           onDiagram:(NSString *)diagramId
                                  at:(NSPoint)point
                              reason:(NSString **)reason
{
	if ([objectTypeIds count] == 0) {
		if (reason != NULL) {
			*reason = @"A fact type needs at least one role player.";
		}
		return nil;
	}
	NSMutableArray *players = [NSMutableArray array];
	for (NSString *playerId in objectTypeIds) {
		ORMObjectType *player = [self.model elementWithId:playerId];
		if (![player isKindOfClass:[ORMObjectType class]] || player.isImplicitBooleanValue) {
			if (reason != NULL) {
				*reason = @"Roles are played by object types.";
			}
			return nil;
		}
		[players addObject:player];
	}
	NSString *text = reading;
	if ([text length] == 0) {
		/* "{0} ... {1}": a placeholder reading for the user to fill in. */
		NSMutableArray *parts = [NSMutableArray array];
		for (NSUInteger i = 0; i < [players count]; i++) {
			[parts addObject:[NSString stringWithFormat:@"{%lu}", (unsigned long)i]];
		}
		text = [players count] == 1 ? @"{0} exists" : [parts componentsJoinedByString:@" ... "];
	}
	if ([ORMReadingText readingTextWithString:text arity:[players count] reason:reason] == nil) {
		return nil;
	}
	__block NSString *created = nil;
	[self group:@"Add Fact Type" with:^{
		[self change:@"Add Fact Type" with:^{
			NSMutableArray *ids = [objectTypeIds mutableCopy];
			if ([players count] == 1) {
				/* NORMA's unary: a binary whose other role an implicit
				 * boolean value type plays, constrained to true. */
				ORMObjectType *subject = [players firstObject];
				ORMReadingText *parsed = [ORMReadingText readingTextWithString:text arity:1 reason:NULL];
				NSString *name = [self uniqueObjectTypeName:[parsed expandWithNames:^NSString *(NSUInteger index,
				                                                                               NSString *pre,
				                                                                               NSString *post) {
					return [NSString stringWithFormat:@"%@%@%@", pre ?: @"", subject.name, post ?: @""];
				}]];
				NSXMLElement *value = [self newValueTypeNamed:name dataType:@"TrueOrFalseLogicalDataType"];
				ORMSetAttribute(value, @"IsImplicitBooleanValue", @"true");
				NSXMLElement *restriction = ORMEnsureChild(self.document, value, CORE, @"ValueRestriction");
				NSXMLElement *constraint = ORMNewElementWithId(self.document, CORE, @"ValueConstraint", nil);
				ORMSetAttribute(constraint, @"Name", [self nextName:@"ValueTypeValueConstraint"]);
				NSXMLElement *ranges = ORMNewElement(self.document, CORE, @"ValueRanges");
				NSXMLElement *range = ORMNewElementWithId(self.document, CORE, @"ValueRange", nil);
				ORMSetAttribute(range, @"MinValue", @"True");
				ORMSetAttribute(range, @"MaxValue", @"True");
				ORMSetAttribute(range, @"MinInclusion", @"NotSet");
				ORMSetAttribute(range, @"MaxInclusion", @"NotSet");
				[ranges addChild:range];
				[constraint addChild:ranges];
				[restriction addChild:constraint];
				[ids addObject:ORMAttribute(value, @"id")];
			}
			NSMutableArray *roles = [NSMutableArray array];
			NSXMLElement *fact = [self newFactWithPlayers:ids reading:text roles:roles];
			created = ORMAttribute(fact, @"id");
			if ([players count] == 1) {
				/* Each instance is or is not: the subject's role unique. */
				[self newInternalUniqueness:@[ [roles firstObject] ]];
			}
		}];
		if (diagramId != nil) {
			[self showFactType:created onDiagram:diagramId at:point];
		}
	}];
	return created;
}

- (NSString *)addReading:(NSString *)text forRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason
{
	NSArray *roles = [self rolesWithIds:roleIds reason:reason];
	if (roles == nil) {
		return nil;
	}
	ORMFactType *fact = [(ORMRole *)[roles firstObject] factType];
	for (ORMRole *role in roles) {
		if (role.factType != fact) {
			if (reason != NULL) {
				*reason = @"A reading reads the roles of one fact type.";
			}
			return nil;
		}
	}
	if ([roles count] != [fact arity]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"A reading orders all %lu roles.", (unsigned long)[fact arity]];
		}
		return nil;
	}
	if ([ORMReadingText readingTextWithString:text arity:[roles count] reason:reason] == nil) {
		return nil;
	}
	__block NSString *created = nil;
	[self change:@"Add Reading" with:^{
		created = ORMAttribute([self appendReading:text to:fact.element roles:roleIds], @"id");
	}];
	return created;
}

- (BOOL)setReadingText:(NSString *)text of:(NSString *)readingId reason:(NSString **)reason
{
	ORMReading *reading = [self.model elementWithId:readingId];
	if (![reading isKindOfClass:[ORMReading class]]) {
		if (reason != NULL) {
			*reason = @"Pick a reading.";
		}
		return NO;
	}
	if ([text length] == 0) {
		ORMReadingOrder *order = reading.readingOrder;
		ORMFactType *fact = order.factType;
		NSUInteger readings = 0;
		for (ORMReadingOrder *each in fact.readingOrders) {
			readings += [each.readings count];
		}
		if (readings <= 1) {
			if (reason != NULL) {
				*reason = @"A fact type keeps at least one reading.";
			}
			return NO;
		}
		[self change:@"Delete Reading" with:^{
			[reading.element detach];
			if ([order.readings count] <= 1) {
				[order.element detach];
			}
		}];
		return YES;
	}
	if ([ORMReadingText readingTextWithString:text arity:[reading.readingOrder.roles count] reason:reason] == nil) {
		return NO;
	}
	if ([text isEqualToString:reading.text]) {
		return YES;
	}
	[self change:@"Edit Reading" with:^{
		ORMSetChildText(self.document, reading.element, CORE, @"Data", text);
	}];
	return YES;
}

- (BOOL)setPlayer:(NSString *)objectTypeId ofRole:(NSString *)roleId reason:(NSString **)reason
{
	ORMRole *role = [self.model elementWithId:roleId];
	ORMObjectType *player = [self.model elementWithId:objectTypeId];
	if (![role isKindOfClass:[ORMRole class]] || ![player isKindOfClass:[ORMObjectType class]]) {
		if (reason != NULL) {
			*reason = @"Connect a role to an object type.";
		}
		return NO;
	}
	if (role.factType.kind != ORMFactTypeOrdinary || role.player.isImplicitBooleanValue) {
		if (reason != NULL) {
			*reason = @"That role's player is fixed.";
		}
		return NO;
	}
	if (role.player == player) {
		return YES;
	}
	[self change:@"Connect Role" with:^{
		NSXMLElement *rolePlayer = ORMChild(role.element, CORE, @"RolePlayer");
		if (rolePlayer == nil) {
			[role.element insertChild:ORMNewRef(self.document, CORE, @"RolePlayer", objectTypeId) atIndex:0];
		} else {
			ORMSetAttribute(rolePlayer, @"ref", objectTypeId);
		}
	}];
	return YES;
}

/* NORMA keeps the informal rule under the derivation path:
 * DerivationRule > FactTypeDerivationPath > InformalRule > DerivationNote >
 * Body. A rule with nothing but the note goes when the note does. */
- (BOOL)setDerivationNote:(NSString *)text of:(NSString *)factTypeId reason:(NSString **)reason
{
	ORMFactType *fact = [self.model elementWithId:factTypeId];
	if (![fact isKindOfClass:[ORMFactType class]] || fact.kind != ORMFactTypeOrdinary) {
		if (reason != NULL) {
			*reason = @"Pick a fact type.";
		}
		return NO;
	}
	[self change:@"Set Derivation" with:^{
		NSXMLElement *rule = ORMChild(fact.element, CORE, @"DerivationRule");
		NSXMLElement *path = ORMChild(rule, CORE, @"FactTypeDerivationPath");
		NSXMLElement *informal = ORMChild(path, CORE, @"InformalRule");
		if ([text length] == 0) {
			[informal detach];
			if (path != nil && ORMChild(path, CORE, @"PathComponents") == nil && ORMChild(path, CORE, @"PathComponent") == nil) {
				[rule detach];
			}
			return;
		}
		if (rule == nil) {
			rule = ORMNewElement(self.document, CORE, @"DerivationRule");
			ORMInsertChild(fact.element, rule);
		}
		if (path == nil) {
			path = ORMNewElementWithId(self.document, CORE, @"FactTypeDerivationPath", nil);
			[rule addChild:path];
		}
		if (informal == nil) {
			informal = ORMNewElement(self.document, CORE, @"InformalRule");
			[path addChild:informal];
		}
		NSXMLElement *note = ORMChild(informal, CORE, @"DerivationNote");
		if (note == nil) {
			note = ORMNewElementWithId(self.document, CORE, @"DerivationNote", nil);
			[informal addChild:note];
		}
		ORMSetChildText(self.document, note, CORE, @"Body", text);
	}];
	return YES;
}

@end

@implementation ORMEditor (ORMStructure)

#pragma mark Subtyping

- (NSString *)addSubtype:(NSString *)subtypeId of:(NSString *)supertypeId reason:(NSString **)reason
{
	ORMObjectType *sub = [self.model elementWithId:subtypeId];
	ORMObjectType *sup = [self.model elementWithId:supertypeId];
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
	[self change:@"Add Subtype" with:^{
		NSXMLElement *fact = ORMNewElementWithId(self.document, CORE, @"SubtypeFact", nil);
		ORMSetAttribute(fact, @"_Name", [NSString stringWithFormat:@"%@IsSubtypeOf%@", sub.name, sup.name]);
		/* The first supertype identifies a subtype with no identifier. */
		if ([sub.supertypes count] == 0 && sub.preferredIdentifier == nil) {
			ORMSetAttribute(fact, @"PreferredIdentificationPath", @"true");
		}
		NSXMLElement *roles = ORMEnsureChild(self.document, fact, CORE, @"FactRoles");
		NSMutableArray *roleIds = [NSMutableArray array];
		for (NSArray *pair in @[ @[ @"SubtypeMetaRole", subtypeId ], @[ @"SupertypeMetaRole", supertypeId ] ]) {
			NSXMLElement *role = ORMNewElementWithId(self.document, CORE, [pair objectAtIndex:0], nil);
			ORMSetAttribute(role, @"_IsMandatory", @"false");
			ORMSetAttribute(role, @"_Multiplicity", @"Unspecified");
			ORMSetAttribute(role, @"Name", @"");
			[role addChild:ORMNewRef(self.document, CORE, @"RolePlayer", [pair objectAtIndex:1])];
			[roles addChild:role];
			[roleIds addObject:ORMAttribute(role, @"id")];
		}
		[[self section:@"Facts"] addChild:fact];
		/* Each subtype instance is exactly one supertype instance, and
		 * the other way round at most one. */
		[self newSimpleMandatory:[roleIds firstObject]];
		[self newInternalUniqueness:@[ [roleIds firstObject] ]];
		[self newInternalUniqueness:@[ [roleIds lastObject] ]];
		created = ORMAttribute(fact, @"id");
	}];
	return created;
}

#pragma mark Objectification

- (NSString *)objectifyFactType:(NSString *)factTypeId named:(NSString *)name reason:(NSString **)reason
{
	ORMFactType *fact = [self.model elementWithId:factTypeId];
	if (![fact isKindOfClass:[ORMFactType class]] || fact.kind != ORMFactTypeOrdinary) {
		if (reason != NULL) {
			*reason = @"Only a fact type can be objectified.";
		}
		return nil;
	}
	if (fact.objectifyingType != nil) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"It is already objectified as %@.", fact.objectifyingType.name];
		}
		return nil;
	}
	NSString *typeName = [name length] > 0 ? name : [fact derivedName];
	if ([self.model objectTypeNamed:typeName] != nil) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"The model already has an object type named '%@'.", typeName];
		}
		return nil;
	}
	/* The objectified type is identified by a uniqueness constraint over
	 * the fact type's roles: the spanning one, or the n-1 one NORMA would
	 * pick. An objectified fact type with none gets a spanning one. */
	ORMConstraint *identifier = nil;
	for (ORMConstraint *constraint in [fact uniquenessConstraints]) {
		if (identifier == nil || [[constraint allRoles] count] > [[identifier allRoles] count]) {
			identifier = constraint;
		}
	}
	__block NSString *created = nil;
	[self change:@"Objectify Fact Type" with:^{
		NSString *identifierId = identifier.identifier;
		if (identifierId == nil) {
			NSMutableArray *all = [NSMutableArray array];
			for (ORMRole *role in fact.roles) {
				[all addObject:role.identifier];
			}
			identifierId = ORMAttribute([self newInternalUniqueness:all], @"id");
		}
		NSXMLElement *type = ORMNewElementWithId(self.document, CORE, @"ObjectifiedType", nil);
		ORMSetAttribute(type, @"Name", typeName);
		ORMSetAttribute(type, @"IsIndependent", @"true");
		ORMSetAttribute(type, @"_ReferenceMode", @"");
		ORMInsertChild(type, ORMNewRef(self.document, CORE, @"PreferredIdentifier", identifierId));
		NSXMLElement *nested = ORMNewElementWithId(self.document, CORE, @"NestedPredicate", nil);
		ORMSetAttribute(nested, @"ref", factTypeId);
		ORMSetAttribute(nested, @"IsImplied", @"false");
		ORMInsertChild(type, nested);
		[[self section:@"Objects"] addChild:type];
		created = ORMAttribute(type, @"id");

		/* NORMA's link fact types: for each role, "{objectified} involves
		 * {player}", the objectified type's role unique and mandatory. */
		for (ORMRole *role in [fact visibleRoles]) {
			NSXMLElement *link = ORMNewElementWithId(self.document, CORE, @"ImpliedFact", nil);
			ORMSetAttribute(link, @"_Name", [NSString stringWithFormat:@"%@Involves%@", typeName, role.player.name]);
			NSXMLElement *roles = ORMEnsureChild(self.document, link, CORE, @"FactRoles");
			NSXMLElement *proxy = ORMNewElementWithId(self.document, CORE, @"RoleProxy", nil);
			[proxy addChild:ORMNewRef(self.document, CORE, @"Role", role.identifier)];
			[roles addChild:proxy];
			NSXMLElement *own = ORMNewElementWithId(self.document, CORE, @"Role", nil);
			ORMSetAttribute(own, @"_IsMandatory", @"true");
			ORMSetAttribute(own, @"_Multiplicity", @"ExactlyOne");
			ORMSetAttribute(own, @"Name", @"");
			[own addChild:ORMNewRef(self.document, CORE, @"RolePlayer", created)];
			[roles addChild:own];
			[[self section:@"Facts"] addChild:link];
			NSString *proxyId = ORMAttribute(proxy, @"id");
			NSString *ownId = ORMAttribute(own, @"id");
			[self appendReading:@"{0} involves {1}" to:link roles:@[ ownId, proxyId ]];
			[self appendReading:@"{0} is involved in {1}" to:link roles:@[ proxyId, ownId ]];
			NSXMLElement *unique = [self newInternalUniqueness:@[ ownId ]];
			ORMSetAttribute(unique, @"IsImplied", @"true");
			NSXMLElement *mandatory = [self newSimpleMandatory:ownId];
			ORMSetAttribute(mandatory, @"IsImplied", @"true");
			[link addChild:ORMNewRef(self.document, CORE, @"ImpliedByObjectification", ORMAttribute(nested, @"id"))];
		}
	}];
	return created;
}

- (BOOL)unobjectifyFactType:(NSString *)factTypeId reason:(NSString **)reason
{
	ORMFactType *fact = [self.model elementWithId:factTypeId];
	ORMObjectType *type = fact.objectifyingType;
	if (type == nil) {
		if (reason != NULL) {
			*reason = @"The fact type is not objectified.";
		}
		return NO;
	}
	if ([type.playedRoles count] > [[fact visibleRoles] count]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"%@ plays roles of its own; delete them first.", type.name];
		}
		return NO;
	}
	[self change:@"Unobjectify Fact Type" with:^{
		[self deleteElements:@[ type.identifier ]];
	}];
	return YES;
}

#pragma mark Notes

- (NSString *)addNote:(NSString *)text
            attachedTo:(NSArray<NSString *> *)elementIds
             onDiagram:(NSString *)diagramId
                    at:(NSPoint)point
                reason:(NSString **)reason
{
	__block NSString *created = nil;
	[self group:@"Add Note" with:^{
		[self change:@"Add Note" with:^{
			NSXMLElement *note = ORMNewElementWithId(self.document, CORE, @"ModelNote", nil);
			ORMSetChildText(self.document, note, CORE, @"Text", [text length] > 0 ? text : @"Note");
			if ([elementIds count] > 0) {
				NSXMLElement *references = ORMNewElement(self.document, CORE, @"ReferencedBy");
				for (NSString *elementId in elementIds) {
					id element = [self.model elementWithId:elementId];
					NSString *local = [element isKindOfClass:[ORMObjectType class]] ? @"ObjectType"
						: [element isKindOfClass:[ORMFactType class]] ? @"FactType" : @"Constraint";
					[references addChild:ORMNewRef(self.document, CORE, local, elementId)];
				}
				[note addChild:references];
			}
			[[self section:@"ModelNotes"] addChild:note];
			created = ORMAttribute(note, @"id");
		}];
		if (diagramId != nil) {
			[self placeElement:created onDiagram:diagramId at:point];
		}
	}];
	return created;
}

- (BOOL)setNoteText:(NSString *)text of:(NSString *)noteId reason:(NSString **)reason
{
	ORMModelNote *note = [self.model elementWithId:noteId];
	if (![note isKindOfClass:[ORMModelNote class]]) {
		if (reason != NULL) {
			*reason = @"Pick a note.";
		}
		return NO;
	}
	[self change:@"Edit Note" with:^{
		ORMSetChildText(self.document, note.element, CORE, @"Text", text);
	}];
	return YES;
}

#pragma mark Deleting

/* What goes with the elements: closes the set of ids over what cannot
 * stand without what is in it. */
- (NSMutableSet *)closureOf:(NSArray<NSString *> *)elementIds
{
	ORMModel *model = self.model;
	NSMutableSet *doomed = [NSMutableSet set];
	NSMutableArray *pending = [elementIds mutableCopy];
	while ([pending count] > 0) {
		NSString *elementId = [pending lastObject];
		[pending removeLastObject];
		if ([doomed containsObject:elementId]) {
			continue;
		}
		id element = [model elementWithId:elementId];
		if (element == nil || [element isKindOfClass:[ORMShape class]]) {
			continue;
		}
		[doomed addObject:elementId];
		if ([element isKindOfClass:[ORMObjectType class]]) {
			ORMObjectType *type = element;
			for (ORMRole *role in type.playedRoles) {
				[pending addObject:role.factType.identifier];
			}
			if (type.nestedFactType != nil) {
				for (ORMFactType *fact in model.factTypes) {
					if (fact.impliedByFactType == type.nestedFactType) {
						[pending addObject:fact.identifier];
					}
				}
			}
			/* Its reference mode's value type, when nothing else uses it. */
			ORMObjectType *value = type.referenceModeValueType;
			if (value != nil && [value.playedRoles count] == 1) {
				[pending addObject:value.identifier];
			}
		} else if ([element isKindOfClass:[ORMFactType class]]) {
			ORMFactType *fact = element;
			for (ORMRole *role in fact.roles) {
				[doomed addObject:role.identifier];
				if (role.player.isImplicitBooleanValue) {
					[pending addObject:role.player.identifier];
				}
				/* Link fact types stand for the roles. */
				for (ORMFactType *link in model.factTypes) {
					for (ORMRole *linkRole in link.roles) {
						if (linkRole.proxiedRole == role) {
							[pending addObject:link.identifier];
						}
					}
				}
			}
			if (fact.objectifyingType != nil) {
				[pending addObject:fact.objectifyingType.identifier];
			}
		} else if ([element isKindOfClass:[ORMReading class]]) {
			ORMReading *reading = element;
			if ([reading.readingOrder.readings count] == 1) {
				[doomed addObject:reading.readingOrder.identifier];
			}
		}
	}
	return doomed;
}

- (void)deleteElements:(NSArray<NSString *> *)elementIds
{
	NSMutableArray *shapes = [NSMutableArray array];
	NSMutableArray *rest = [NSMutableArray array];
	for (NSString *elementId in elementIds) {
		id element = [self.model elementWithId:elementId];
		if ([element isKindOfClass:[ORMShape class]]) {
			[shapes addObject:element];
		} else if (element != nil) {
			[rest addObject:elementId];
		}
	}
	if ([shapes count] == 0 && [rest count] == 0) {
		return;
	}
	NSMutableSet *doomed = [self closureOf:rest];
	ORMModel *model = self.model;
	[self change:@"Delete" with:^{
		for (ORMShape *shape in shapes) {
			[shape.element detach];
		}
		/* Constraint arguments over doomed roles go; a constraint left
		 * without what it needs goes with them. */
		for (ORMConstraint *constraint in model.constraints) {
			if ([doomed containsObject:constraint.identifier]) {
				continue;
			}
			BOOL touched = NO;
			for (ORMRoleSequence *sequence in constraint.roleSequences) {
				for (NSXMLElement *ref in ORMChildren(sequence.element, CORE, @"Role")) {
					if ([doomed containsObject:ORMRef(ref) ?: @""]) {
						[ref detach];
						touched = YES;
					}
				}
			}
			if (!touched) {
				continue;
			}
			NSMutableArray *lengths = [NSMutableArray array];
			for (ORMRoleSequence *sequence in constraint.roleSequences) {
				[lengths addObject:@([ORMChildren(sequence.element, CORE, @"Role") count])];
			}
			BOOL setComparison = constraint.kind == ORMSubsetConstraint || constraint.kind == ORMEqualityConstraint
				|| constraint.kind == ORMExclusionConstraint;
			BOOL broken = [lengths containsObject:@0] || [[NSSet setWithArray:lengths] count] > 1;
			if (!setComparison) {
				broken = [lengths containsObject:@0];
			}
			if (constraint.kind == ORMRingConstraint && [[lengths firstObject] integerValue] < 2) {
				broken = YES;
			}
			if (broken) {
				[doomed addObject:constraint.identifier];
			}
		}
		for (NSString *elementId in doomed) {
			ORMElement *element = [model elementWithId:elementId];
			if ([element isKindOfClass:[ORMRole class]]) {
				continue;
			}
			/* Partners of an exclusive-or lose the link. */
			if ([element isKindOfClass:[ORMConstraint class]]) {
				ORMConstraint *partner = [(ORMConstraint *)element exclusiveOrPartner];
				[ORMChild(partner.element, CORE, @"ExclusiveOrExclusionConstraint") detach];
				[ORMChild(partner.element, CORE, @"ExclusiveOrMandatoryConstraint") detach];
			}
			[element.element detach];
		}
		[self removeShapesOfSubjects:doomed];
	}];
}

@end
