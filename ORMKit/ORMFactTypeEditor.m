/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMReadingText.h"

@implementation ORMFactTypeEditor

@synthesize editor = _editor;

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

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
		ORMObjectType *player = [_editor.model elementWithId:playerId];
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
	[_editor group:@"Add Fact Type" with:^{
		[_editor change:@"Add Fact Type" with:^{
			NSMutableArray *ids = [objectTypeIds mutableCopy];
			if ([players count] == 1) {
				/* NORMA's unary: a binary whose other role an implicit
				 * boolean value type plays, constrained to true. */
				ORMObjectType *subject = [players firstObject];
				ORMReadingText *parsed = [ORMReadingText readingTextWithString:text arity:1 reason:NULL];
				NSString *name = [_editor uniqueObjectTypeName:[parsed expandWithNames:^NSString *(NSUInteger index,
				                                                                               NSString *pre,
				                                                                               NSString *post) {
					return [NSString stringWithFormat:@"%@%@%@", pre ?: @"", subject.name, post ?: @""];
				}]];
				NSXMLElement *value = [_editor.objectTypeEditor newValueTypeNamed:name dataType:@"TrueOrFalseLogicalDataType"];
				ORMSetAttribute(value, @"IsImplicitBooleanValue", @"true");
				NSXMLElement *restriction = ORMEnsureChild(_editor.document, value, CORE, @"ValueRestriction");
				NSXMLElement *constraint = ORMNewElementWithId(_editor.document, CORE, @"ValueConstraint", nil);
				ORMSetAttribute(constraint, @"Name", [_editor nextName:@"ValueTypeValueConstraint"]);
				NSXMLElement *ranges = ORMNewElement(_editor.document, CORE, @"ValueRanges");
				NSXMLElement *range = ORMNewElementWithId(_editor.document, CORE, @"ValueRange", nil);
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
				[_editor.constraintEditor newInternalUniqueness:@[ [roles firstObject] ]];
			}
		}];
		if (diagramId != nil) {
			[_editor.diagramEditor showFactType:created onDiagram:diagramId at:point];
		}
	}];
	return created;
}

- (NSString *)addReading:(NSString *)text forRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason
{
	NSArray *roles = [_editor rolesWithIds:roleIds reason:reason];
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
	[_editor change:@"Add Reading" with:^{
		created = ORMAttribute([self appendReading:text to:fact.element roles:roleIds], @"id");
	}];
	return created;
}

- (BOOL)setReadingText:(NSString *)text of:(NSString *)readingId reason:(NSString **)reason
{
	ORMReading *reading = [_editor.model elementWithId:readingId];
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
		[_editor change:@"Delete Reading" with:^{
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
	[_editor change:@"Edit Reading" with:^{
		ORMSetChildText(_editor.document, reading.element, CORE, @"Data", text);
	}];
	return YES;
}

- (BOOL)setPlayer:(NSString *)objectTypeId ofRole:(NSString *)roleId reason:(NSString **)reason
{
	ORMRole *role = [_editor.model elementWithId:roleId];
	ORMObjectType *player = [_editor.model elementWithId:objectTypeId];
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
	[_editor change:@"Connect Role" with:^{
		NSXMLElement *rolePlayer = ORMChild(role.element, CORE, @"RolePlayer");
		if (rolePlayer == nil) {
			[role.element insertChild:ORMNewRef(_editor.document, CORE, @"RolePlayer", objectTypeId) atIndex:0];
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
	ORMFactType *fact = [_editor.model elementWithId:factTypeId];
	if (![fact isKindOfClass:[ORMFactType class]] || fact.kind != ORMFactTypeOrdinary) {
		if (reason != NULL) {
			*reason = @"Pick a fact type.";
		}
		return NO;
	}
	[_editor change:@"Set Derivation" with:^{
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
			rule = ORMNewElement(_editor.document, CORE, @"DerivationRule");
			ORMInsertChild(fact.element, rule);
		}
		if (path == nil) {
			path = ORMNewElementWithId(_editor.document, CORE, @"FactTypeDerivationPath", nil);
			[rule addChild:path];
		}
		if (informal == nil) {
			informal = ORMNewElement(_editor.document, CORE, @"InformalRule");
			[path addChild:informal];
		}
		NSXMLElement *note = ORMChild(informal, CORE, @"DerivationNote");
		if (note == nil) {
			note = ORMNewElementWithId(_editor.document, CORE, @"DerivationNote", nil);
			[informal addChild:note];
		}
		ORMSetChildText(_editor.document, note, CORE, @"Body", text);
	}];
	return YES;
}


#pragma mark Objectification

- (NSString *)objectifyFactType:(NSString *)factTypeId named:(NSString *)name reason:(NSString **)reason
{
	ORMFactType *fact = [_editor.model elementWithId:factTypeId];
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
	if ([_editor.model objectTypeNamed:typeName] != nil) {
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
	[_editor change:@"Objectify Fact Type" with:^{
		NSString *identifierId = identifier.identifier;
		if (identifierId == nil) {
			NSMutableArray *all = [NSMutableArray array];
			for (ORMRole *role in fact.roles) {
				[all addObject:role.identifier];
			}
			identifierId = ORMAttribute([_editor.constraintEditor newInternalUniqueness:all], @"id");
		}
		NSXMLElement *type = ORMNewElementWithId(_editor.document, CORE, @"ObjectifiedType", nil);
		ORMSetAttribute(type, @"Name", typeName);
		ORMSetAttribute(type, @"IsIndependent", @"true");
		ORMSetAttribute(type, @"_ReferenceMode", @"");
		ORMInsertChild(type, ORMNewRef(_editor.document, CORE, @"PreferredIdentifier", identifierId));
		NSXMLElement *nested = ORMNewElementWithId(_editor.document, CORE, @"NestedPredicate", nil);
		ORMSetAttribute(nested, @"ref", factTypeId);
		ORMSetAttribute(nested, @"IsImplied", @"false");
		ORMInsertChild(type, nested);
		[[_editor section:@"Objects"] addChild:type];
		created = ORMAttribute(type, @"id");

		/* NORMA's link fact types: for each role, "{objectified} involves
		 * {player}", the objectified type's role unique and mandatory. */
		for (ORMRole *role in [fact visibleRoles]) {
			NSXMLElement *link = ORMNewElementWithId(_editor.document, CORE, @"ImpliedFact", nil);
			ORMSetAttribute(link, @"_Name", [NSString stringWithFormat:@"%@Involves%@", typeName, role.player.name]);
			NSXMLElement *roles = ORMEnsureChild(_editor.document, link, CORE, @"FactRoles");
			NSXMLElement *proxy = ORMNewElementWithId(_editor.document, CORE, @"RoleProxy", nil);
			[proxy addChild:ORMNewRef(_editor.document, CORE, @"Role", role.identifier)];
			[roles addChild:proxy];
			NSXMLElement *own = ORMNewElementWithId(_editor.document, CORE, @"Role", nil);
			ORMSetAttribute(own, @"_IsMandatory", @"true");
			ORMSetAttribute(own, @"_Multiplicity", @"ExactlyOne");
			ORMSetAttribute(own, @"Name", @"");
			[own addChild:ORMNewRef(_editor.document, CORE, @"RolePlayer", created)];
			[roles addChild:own];
			[[_editor section:@"Facts"] addChild:link];
			NSString *proxyId = ORMAttribute(proxy, @"id");
			NSString *ownId = ORMAttribute(own, @"id");
			[self appendReading:@"{0} involves {1}" to:link roles:@[ ownId, proxyId ]];
			[self appendReading:@"{0} is involved in {1}" to:link roles:@[ proxyId, ownId ]];
			NSXMLElement *unique = [_editor.constraintEditor newInternalUniqueness:@[ ownId ]];
			ORMSetAttribute(unique, @"IsImplied", @"true");
			NSXMLElement *mandatory = [_editor.constraintEditor newSimpleMandatory:ownId];
			ORMSetAttribute(mandatory, @"IsImplied", @"true");
			[link addChild:ORMNewRef(_editor.document, CORE, @"ImpliedByObjectification", ORMAttribute(nested, @"id"))];
		}
	}];
	return created;
}

- (BOOL)unobjectifyFactType:(NSString *)factTypeId reason:(NSString **)reason
{
	ORMFactType *fact = [_editor.model elementWithId:factTypeId];
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
	[_editor change:@"Unobjectify Fact Type" with:^{
		[_editor.elementEditor deleteElements:@[ type.identifier ]];
	}];
	return YES;
}

#pragma mark Building

/* A new <orm:Fact> over the players with one reading, roles' ids out. */
- (NSXMLElement *)newFactWithPlayers:(NSArray<NSString *> *)playerIds
                             reading:(NSString *)reading
                               roles:(NSMutableArray *)roleIds
{
	NSXMLElement *fact = ORMNewElementWithId(_editor.document, CORE, @"Fact", nil);
	NSXMLElement *roles = ORMEnsureChild(_editor.document, fact, CORE, @"FactRoles");
	for (NSString *playerId in playerIds) {
		NSXMLElement *role = ORMNewElementWithId(_editor.document, CORE, @"Role", nil);
		ORMSetAttribute(role, @"_IsMandatory", @"false");
		ORMSetAttribute(role, @"_Multiplicity", @"Unspecified");
		ORMSetAttribute(role, @"Name", @"");
		[role addChild:ORMNewRef(_editor.document, CORE, @"RolePlayer", playerId)];
		[roles addChild:role];
		[roleIds addObject:ORMAttribute(role, @"id")];
	}
	[[_editor section:@"Facts"] addChild:fact];
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
	NSXMLElement *orders = ORMEnsureChild(_editor.document, fact, CORE, @"ReadingOrders");
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
		order = ORMNewElementWithId(_editor.document, CORE, @"ReadingOrder", nil);
		[order addChild:ORMNewElement(_editor.document, CORE, @"Readings")];
		NSXMLElement *sequence = ORMNewElement(_editor.document, CORE, @"RoleSequence");
		for (NSString *roleId in roleIds) {
			[sequence addChild:ORMNewRef(_editor.document, CORE, @"Role", roleId)];
		}
		[order addChild:sequence];
		[orders addChild:order];
	}
	NSXMLElement *reading = ORMNewElementWithId(_editor.document, CORE, @"Reading", nil);
	NSXMLElement *data = ORMNewElement(_editor.document, CORE, @"Data");
	[data setStringValue:text];
	[reading addChild:data];
	[ORMChild(order, CORE, @"Readings") addChild:reading];
	return reading;
}

@end
