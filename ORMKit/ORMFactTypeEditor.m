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
		[_editor modelChange:@"Add Fact Type" with:^{
			NSMutableArray *rolePlayers = [players mutableCopy];
			if ([players count] == 1) {
				/* NORMA's unary: a binary whose other role an implicit
				 * boolean value type plays, constrained to true. */
				[rolePlayers addObject:[self implicitBooleanFor:[players firstObject] reading:text]];
			}
			ORMFactType *fact = [self addFactWithPlayers:rolePlayers reading:text];
			created = fact.identifier;
			if ([players count] == 1) {
				/* Each instance is or is not: the subject's role unique. */
				[_editor.constraintEditor addInternalUniqueness:@[ [fact.roles firstObject] ]];
			}
		}];
		if (diagramId != nil) {
			[_editor.diagramEditor showFactType:created onDiagram:diagramId at:point];
		}
	}];
	return created;
}

/* A unary's reading as it reads with its players' names; nil for a fact
 * type that is not unary. */
- (NSString *)unaryReadingOf:(ORMFactType *)fact
{
	return [fact isUnary] ? [[fact primaryReading] expandedText] ?: @"" : nil;
}

/* A unary's implicit value type is named by its reading, when the reading
 * changed, as NORMA names it (the normalizer's rule): an older name
 * ("Person isDead"), or one another type has, is left as it is. */
- (void)renameImplicitBooleanOf:(ORMFactType *)fact was:(NSString *)was
{
	if (was == nil) {
		return;
	}
	NSString *name = [[fact primaryReading] expandedText];
	ORMObjectType *implicit = [fact implicitRole].player;
	NSString *older = [name stringByReplacingOccurrencesOfString:@"-" withString:@" "];
	if ([was isEqualToString:name ?: @""] || implicit == nil || [name length] == 0 || [implicit.name isEqualToString:name]
	    || [implicit.name isEqualToString:older] || [_editor.model objectTypeNamed:name] != nil) {
		return;
	}
	implicit.name = name;
	[_editor wrote:implicit];
}

/* A unary's implicit value type, named as its reading reads of the
 * subject: true only. */
- (ORMObjectType *)implicitBooleanFor:(ORMObjectType *)subject reading:(NSString *)text
{
	ORMReadingText *parsed = [ORMReadingText readingTextWithString:text arity:1 reason:NULL];
	NSString *name = [_editor uniqueObjectTypeName:[parsed expandWithNames:^NSString *(NSUInteger index, NSString *pre,
	                                                                                   NSString *post) {
		return [NSString stringWithFormat:@"%@%@%@", pre ?: @"", subject.name, post ?: @""];
	}]];
	ORMObjectType *value = [_editor.objectTypeEditor newObjectTypeNamed:name kind:ORMValueType
	                                                          dataType:@"TrueOrFalseLogicalDataType"];
	value.isImplicitBooleanValue = YES;
	[_editor.objectTypeEditor setRanges:@[ @{ @"min": @"True", @"max": @"True", @"minInclusion": @"NotSet",
	                                          @"maxInclusion": @"NotSet" } ]
	                                 of:value];
	return value;
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
	[_editor modelChange:@"Add Reading" with:^{
		created = [self addReading:text to:fact roles:roles].identifier;
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
		[_editor modelChange:@"Delete Reading" with:^{
			ORMModel *model = _editor.model;
			order.readings = ORMWithout(order.readings, reading);
			[model removeElement:reading];
			if ([order.readings count] == 0) {
				fact.readingOrders = ORMWithout(fact.readingOrders, order);
				[model removeElement:order];
			}
			[_editor wrote:fact];
		}];
		return YES;
	}
	if ([ORMReadingText readingTextWithString:text arity:[reading.readingOrder.roles count] reason:reason] == nil) {
		return NO;
	}
	if ([text isEqualToString:reading.text]) {
		return YES;
	}
	[_editor modelChange:@"Edit Reading" with:^{
		reading.text = text;
		[_editor wrote:reading];
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
	[_editor modelChange:@"Connect Role" with:^{
		role.player = player;
		[_editor wrote:role];
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


- (BOOL)setDerivationPartial:(BOOL)partial stored:(BOOL)stored of:(NSString *)factTypeId reason:(NSString **)reason
{
	ORMFactType *fact = [_editor.model elementWithId:factTypeId];
	NSXMLElement *path = [fact isKindOfClass:[ORMFactType class]]
		? ORMChild(ORMChild(fact.element, CORE, @"DerivationRule"), CORE, @"FactTypeDerivationPath") : nil;
	if (path == nil) {
		if (reason != NULL) {
			*reason = fact.isDerived ? @"Its rule is an older one, which says this itself." : @"It is not derived.";
		}
		return NO;
	}
	/* NORMA leaves out its defaults: fully derived, not stored. */
	NSString *completeness = partial ? @"PartiallyDerived" : nil;
	NSString *storage = stored ? @"Stored" : nil;
	if ([ORMAttribute(path, @"DerivationCompleteness") ?: @"" isEqualToString:completeness ?: @""]
	    && [ORMAttribute(path, @"DerivationStorage") ?: @"" isEqualToString:storage ?: @""]) {
		return YES;
	}
	[_editor change:@"Set Derivation" with:^{
		ORMSetAttribute(path, @"DerivationCompleteness", completeness);
		ORMSetAttribute(path, @"DerivationStorage", storage);
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
	[_editor modelChange:@"Objectify Fact Type" with:^{
		ORMModel *model = _editor.model;
		ORMConstraint *preferred = identifier ?: [_editor.constraintEditor addInternalUniqueness:fact.roles];
		ORMObjectType *type = [[ORMObjectType alloc] initWithModel:model];
		type.name = typeName;
		type.kind = ORMObjectifiedType;
		type.isIndependent = YES;
		type.savedReferenceMode = @"";
		type.preferredIdentifier = preferred;
		type.nestedFactType = fact;
		type.objectificationId = ORMNewId();
		[model addElement:type];
		[_editor wrote:type];
		created = type.identifier;

		/* NORMA's link fact types: for each role, "{objectified} involves
		 * {player}", the objectified type's role unique and mandatory. */
		for (ORMRole *role in [fact visibleRoles]) {
			ORMFactType *link = [[ORMFactType alloc] initWithModel:model];
			link.kind = ORMFactTypeImplied;
			link.savedDerivedName = [NSString stringWithFormat:@"%@Involves%@", typeName, role.player.name];
			link.impliedByFactType = fact;
			ORMRole *proxy = [[ORMRole alloc] initWithModel:model];
			proxy.factType = link;
			proxy.proxiedRole = role;
			ORMRole *own = [[ORMRole alloc] initWithModel:model];
			own.factType = link;
			own.index = 1;
			own.player = type;
			link.roles = @[ proxy, own ];
			link.readingOrders = @[];
			[model registerElement:proxy];
			[model registerElement:own];
			[model addElement:link];
			[_editor wrote:link];
			[self addReading:@"{0} involves {1}" to:link roles:@[ own, proxy ]];
			[self addReading:@"{0} is involved in {1}" to:link roles:@[ proxy, own ]];
			[_editor.constraintEditor addInternalUniqueness:@[ own ]].isImplied = YES;
			[_editor.constraintEditor addSimpleMandatory:own].isImplied = YES;
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
	[_editor group:@"Unobjectify Fact Type" with:^{
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

- (ORMFactType *)addFactWithPlayers:(NSArray<ORMObjectType *> *)players reading:(NSString *)reading
{
	ORMModel *model = _editor.model;
	ORMFactType *fact = [[ORMFactType alloc] initWithModel:model];
	fact.kind = ORMFactTypeOrdinary;
	NSMutableArray *roles = [NSMutableArray array];
	for (ORMObjectType *player in players) {
		ORMRole *role = [[ORMRole alloc] initWithModel:model];
		role.factType = fact;
		role.index = [roles count];
		role.player = player;
		[model registerElement:role];
		[roles addObject:role];
	}
	fact.roles = roles;
	fact.readingOrders = @[];
	[model addElement:fact];
	[_editor wrote:fact];
	if (reading != nil) {
		NSUInteger readable = [players count];
		/* A unary's reading names its one role, not the implicit one. */
		if (readable == 2 && [reading rangeOfString:@"{1}"].location == NSNotFound) {
			readable = 1;
		}
		[self addReading:reading to:fact roles:[roles subarrayWithRange:NSMakeRange(0, readable)]];
	}
	return fact;
}

- (ORMReading *)addReading:(NSString *)text to:(ORMFactType *)fact roles:(NSArray<ORMRole *> *)roles
{
	ORMModel *model = _editor.model;
	ORMReadingOrder *order = nil;
	for (ORMReadingOrder *existing in fact.readingOrders) {
		if ([existing.roles isEqualToArray:roles]) {
			order = existing;
			break;
		}
	}
	if (order == nil) {
		order = [[ORMReadingOrder alloc] initWithModel:model];
		order.factType = fact;
		order.roles = roles;
		order.readings = @[];
		[model registerElement:order];
		fact.readingOrders = [fact.readingOrders arrayByAddingObject:order];
	}
	ORMReading *reading = [[ORMReading alloc] initWithModel:model];
	reading.readingOrder = order;
	reading.text = text;
	[model registerElement:reading];
	order.readings = [order.readings arrayByAddingObject:reading];
	[_editor wrote:fact];
	return reading;
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
