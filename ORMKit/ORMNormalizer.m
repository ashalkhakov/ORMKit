/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"
#import "ORMReadingText.h"
#import "ORMPath.h"
#import "ORMQuery.h"
#import "ORMVerbalizer.h"

/* Whether the file is of the NORMA versions that write each reading's
 * <orm:ExpandedData>: one that has readings and none of it is older, and
 * stays as it is; one with none yet is written as NORMA writes now. */
static BOOL ORMWritesImpliedMandatories(ORMModel *model);

static BOOL
ORMWritesExpandedData(ORMModel *model)
{
	BOOL readings = NO;
	for (ORMFactType *fact in model.factTypes) {
		for (ORMReadingOrder *order in fact.readingOrders) {
			for (ORMReading *reading in order.readings) {
				if (ORMChild(reading.element, CORE, @"ExpandedData") != nil) {
					return YES;
				}
				readings = YES;
			}
		}
	}
	return !readings;
}

@implementation ORMNormalizer
{
	__weak ORMEditor *_editor;
	/* Each unary fact type's reading as the change found it: what tells
	 * normalize which implicit boolean value types to rename. */
	NSDictionary<NSString *, NSString *> *_unaryReadings;
}

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
		_writesExpandedData = ORMWritesExpandedData(editor.model);
		_writesImpliedMandatories = ORMWritesImpliedMandatories(editor.model);
	}
	return self;
}

- (NSDictionary<NSString *, NSString *> *)unaryReadingsOf:(ORMModel *)model
{
	NSMutableDictionary *readings = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in model.factTypes) {
		NSString *text = [fact isUnary] ? [[fact primaryReading] expandedText] : nil;
		if (text != nil && fact.identifier != nil) {
			[readings setObject:text forKey:fact.identifier];
		}
	}
	return readings;
}

- (void)rememberUnaryReadings
{
	_unaryReadings = [self unaryReadingsOf:_editor.model];
}

/* Rewrites a list of <prefix:local ref/> children to name exactly the
 * targets: those already listed keep their place, missing ones go at the
 * end, so a model NORMA wrote comes back unchanged. */
static void
ORMSyncRefs(NSXMLDocument *document, NSXMLElement *container, NSArray<NSArray *> *targets)
{
	/* targets: [local name, id] pairs. */
	NSMutableArray *wanted = [targets mutableCopy];
	for (NSXMLNode *child in [[container children] copy]) {
		if ([child kind] != NSXMLElementKind) {
			continue;
		}
		NSArray *pair = @[ [child localName], ORMRef((NSXMLElement *)child) ?: @"" ];
		NSUInteger index = [wanted indexOfObject:pair];
		if (index == NSNotFound) {
			[child detach];
		} else {
			[wanted removeObjectAtIndex:index];
		}
	}
	for (NSArray *pair in wanted) {
		[container addChild:ORMNewRef(document, [container URI], [pair objectAtIndex:0], [pair objectAtIndex:1])];
	}
}

static NSString *
ORMMultiplicityName(ORMMultiplicity multiplicity)
{
	switch (multiplicity) {
	case ORMMultiplicityZeroToOne: return @"ZeroToOne";
	case ORMMultiplicityZeroToMany: return @"ZeroToMany";
	case ORMMultiplicityExactlyOne: return @"ExactlyOne";
	case ORMMultiplicityOneToMany: return @"OneToMany";
	case ORMMultiplicityIndeterminate: return @"Indeterminate";
	case ORMMultiplicityUnspecified: break;
	}
	return @"Unspecified";
}

/* An element as a comparable value: its local name, its attributes and
 * its children, without the namespace declarations and prefixes the two
 * platforms' NSXML give a new element differently. */
static NSArray *
ORMShapeOf(NSXMLElement *element)
{
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
	for (NSXMLNode *attribute in [element attributes]) {
		[attributes setObject:[attribute stringValue] ?: @"" forKey:[attribute localName] ?: [attribute name]];
	}
	NSMutableArray *children = [NSMutableArray array];
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind) {
			[children addObject:ORMShapeOf((NSXMLElement *)child)];
		}
	}
	return @[ [element localName] ?: @"", attributes, children ];
}

/* <orm:ExpandedData> as NORMA writes it for the reading. */
static NSXMLElement *
ORMExpandedData(NSXMLDocument *document, NSString *text, NSUInteger arity)
{
	ORMReadingText *reading = [ORMReadingText readingTextWithString:text arity:arity reason:NULL];
	if (reading == nil) {
		return nil;
	}
	NSXMLElement *expanded = ORMNewElement(document, CORE, @"ExpandedData");
	if ([reading.frontText length] > 0) {
		ORMSetAttribute(expanded, @"FrontText", reading.frontText);
	}
	for (ORMReadingPart *part in reading.parts) {
		if ([part.preBoundText length] == 0 && [part.postBoundText length] == 0 && [part.followingText length] == 0) {
			continue;
		}
		NSXMLElement *roleText = ORMNewElement(document, CORE, @"RoleText");
		ORMSetAttribute(roleText, @"RoleIndex", [NSString stringWithFormat:@"%lu", (unsigned long)part.roleIndex]);
		if ([part.preBoundText length] > 0) {
			ORMSetAttribute(roleText, @"PreBoundText", part.preBoundText);
		}
		if ([part.postBoundText length] > 0) {
			ORMSetAttribute(roleText, @"PostBoundText", part.postBoundText);
		}
		if ([part.followingText length] > 0) {
			ORMSetAttribute(roleText, @"FollowingText", part.followingText);
		}
		[expanded addChild:roleText];
	}
	return expanded;
}

- (void)normalize
{
	/* The model as the change left it. */
	ORMModel *model = [ORMModel modelOfDocument:_editor.document reason:NULL];
	if (model == nil) {
		return;
	}

	for (ORMObjectType *type in model.objectTypes) {
		NSMutableArray *played = [NSMutableArray array];
		for (ORMRole *role in type.playedRoles) {
			/* A link fact type's proxy is played through the role it
			 * stands for, and NORMA does not list it. */
			if (role.proxiedRole != nil) {
				continue;
			}
			/* Older NORMA refers to a subtype fact's roles by their own
			 * element names, SubtypeMetaRole and SupertypeMetaRole. */
			NSString *local = [role.element localName];
			BOOL meta = [local isEqualToString:@"SubtypeMetaRole"] || [local isEqualToString:@"SupertypeMetaRole"];
			[played addObject:@[ meta ? local : @"Role", role.identifier ]];
		}
		NSXMLElement *container = ORMChild(type.element, CORE, @"PlayedRoles");
		if ([played count] > 0 || container != nil) {
			container = container ?: ORMEnsureChild(_editor.document, type.element, CORE, @"PlayedRoles");
			ORMSyncRefs(_editor.document, container, played);
			ORMPruneIfEmpty(container);
		}
		if (type.kind == ORMEntityType) {
			ORMSetAttribute(type.element, @"_ReferenceMode", type.referenceMode ?: @"");
		}
		/* A preferred identifier that is gone. */
		NSXMLElement *identifier = ORMChild(type.element, CORE, @"PreferredIdentifier");
		if (identifier != nil && type.preferredIdentifier == nil) {
			[identifier detach];
		}
	}

	for (ORMFactType *fact in model.factTypes) {
		/* A unary's implicit value type is named by its reading, when the
		 * reading changed: NORMA leaves an older name ("Person isDead")
		 * as it is. */
		NSString *was = [_unaryReadings objectForKey:fact.identifier ?: @""];
		if ([fact isUnary] && ![was isEqualToString:[[fact primaryReading] expandedText] ?: @""]) {
			ORMObjectType *implicit = nil;
			for (ORMRole *role in fact.roles) {
				if (role.player.isImplicitBooleanValue) {
					implicit = role.player;
				}
			}
			NSString *name = [[fact primaryReading] expandedText];
			/* Older NORMA spelled "is high-demand" "is high demand". */
			NSString *older = [name stringByReplacingOccurrencesOfString:@"-" withString:@" "];
			if (implicit != nil && [name length] > 0 && ![implicit.name isEqualToString:name]
			    && ![implicit.name isEqualToString:older]
			    && [model objectTypeNamed:name] == nil) {
				ORMSetAttribute(implicit.element, @"Name", name);
			}
		}
		if (ORMAttribute(fact.element, @"_Name") != nil || fact.kind == ORMFactTypeOrdinary) {
			ORMSetAttribute(fact.element, @"_Name", [fact derivedName]);
		}
		for (ORMRole *role in fact.roles) {
			NSString *local = [role.element localName];
			if ([local isEqualToString:@"Role"] || [local isEqualToString:@"SubtypeMetaRole"]
			    || [local isEqualToString:@"SupertypeMetaRole"]) {
				ORMSetAttribute(role.element, @"_IsMandatory", role.isMandatory ? @"true" : @"false");
				ORMSetAttribute(role.element, @"_Multiplicity", ORMMultiplicityName([role multiplicity]));
			}
		}
		NSMutableArray *internal = [NSMutableArray array];
		for (ORMConstraint *constraint in fact.internalConstraints) {
			[internal addObject:@[ [constraint.element localName], constraint.identifier ]];
		}
		NSXMLElement *container = ORMChild(fact.element, CORE, @"InternalConstraints");
		if ([internal count] > 0 || container != nil) {
			container = container ?: ORMEnsureChild(_editor.document, fact.element, CORE, @"InternalConstraints");
			ORMSyncRefs(_editor.document, container, internal);
			ORMPruneIfEmpty(container);
		}
		for (ORMReadingOrder *order in _writesExpandedData ? fact.readingOrders : @[]) {
			for (ORMReading *reading in order.readings) {
				NSXMLElement *expanded = ORMExpandedData(_editor.document, reading.text, [order.roles count]);
				NSXMLElement *existing = ORMChild(reading.element, CORE, @"ExpandedData");
				if (expanded == nil) {
					[existing detach];
				} else if (existing == nil) {
					NSUInteger index = [ORMChild(reading.element, CORE, @"Data") index] + 1;
					[reading.element insertChild:expanded atIndex:MIN(index, [reading.element childCount])];
				} else if (![ORMShapeOf(existing) isEqual:ORMShapeOf(expanded)]) {
					[reading.element replaceChildAtIndex:[existing index] withNode:expanded];
				}
			}
		}
	}

	[self normalizeImpliedMandatories:model];
	[self normalizeDerivations:model];

	/* Each preferred identifier names what it identifies. */
	NSMutableDictionary *identified = [NSMutableDictionary dictionary];
	for (ORMObjectType *type in model.objectTypes) {
		if (type.preferredIdentifier != nil) {
			[identified setObject:type.identifier forKey:type.preferredIdentifier.identifier];
		}
	}
	for (ORMConstraint *constraint in model.constraints) {
		if (constraint.kind != ORMUniquenessConstraint) {
			continue;
		}
		NSString *target = [identified objectForKey:constraint.identifier];
		NSXMLElement *existing = ORMChild(constraint.element, CORE, @"PreferredIdentifierFor");
		if (target == nil) {
			[existing detach];
		} else if (existing == nil) {
			[constraint.element addChild:ORMNewRef(_editor.document, CORE, @"PreferredIdentifierFor", target)];
		} else if (![ORMRef(existing) isEqualToString:target]) {
			ORMSetAttribute(existing, @"ref", target);
		}
	}

	/* Shapes whose subject is gone, and role orders naming roles that are. */
	for (ORMDiagram *diagram in model.diagrams) {
		for (ORMShape *shape in [diagram allShapes]) {
			if (shape.subject == nil && shape.subjectId != nil && [shape.element rootDocument] == _editor.document) {
				[shape.element detach];
				continue;
			}
			if (shape.kind == ORMShapeFactType) {
				NSXMLElement *order = ORMChild(shape.element, DIAGRAM, @"RoleDisplayOrder");
				NSArray *refs = ORMChildren(order, DIAGRAM, @"Role");
				BOOL stale = order != nil && [refs count] != [shape.roleDisplayOrder count];
				for (NSXMLElement *ref in refs) {
					if (![[model elementWithId:ORMRef(ref)] isKindOfClass:[ORMRole class]]) {
						stale = YES;
					}
				}
				if (stale) {
					NSMutableArray *pairs = [NSMutableArray array];
					for (ORMRole *role in shape.factType.roles) {
						[pairs addObject:@[ @"Role", role.identifier ]];
					}
					ORMSyncRefs(_editor.document, order, pairs);
				}
			}
		}
	}
}

/* NORMA's implied disjunctive mandatory constraints: every instance of
 * an object type that is not independent plays some role. Roles opposite
 * its preferred identifier's roles (a link fact type's proxy stands for
 * the objectified role) and roles of fully derived fact types say nothing
 * of that. An object type that has a mandatory role (alone or in an
 * inclusive-or) among the others needs nothing more; one that has none
 * has an implied inclusive-or over them, its subtypes' roles too. Kept
 * as NORMA keeps them, one per object type, pointing at it with
 * ImpliedByObjectType. */
/* The roles each object type's implied inclusive-or covers, by the
 * type's id: only the types that need one. */
static NSDictionary<NSString *, NSArray<NSString *> *> *
ORMImpliedMandatoryRoles(ORMModel *model)
{
	NSMutableDictionary *needed = [NSMutableDictionary dictionary];
	for (ORMObjectType *type in model.objectTypes) {
		NSArray *identifierRoles = [type.preferredIdentifier allRoles] ?: @[];
		NSMutableArray *roles = [NSMutableArray array];
		BOOL mandatory = NO;
		for (ORMRole *role in type.playedRoles) {
			if (role.proxiedRole != nil) {
				continue;
			}
			ORMRole *opposite = [role oppositeRole];
			ORMRole *identifying = opposite.proxiedRole ?: opposite;
			ORMDerivationRule *derivation = [role.factType derivationRule];
			if ((identifying != nil && [identifierRoles containsObject:identifying])
			    || (derivation != nil && !derivation.isPartial)) {
				continue;
			}
			for (ORMConstraint *constraint in role.constraints) {
				if (constraint.kind == ORMMandatoryConstraint && !constraint.isImplied
				    && constraint.modality == ORMAlethic) {
					mandatory = YES;
				}
			}
			[roles addObject:role.identifier];
		}
		if (!type.isIndependent && !mandatory && [roles count] > 0 && type.identifier != nil) {
			[needed setObject:roles forKey:type.identifier];
		}
	}
	return needed;
}

/* Whether the file is of the NORMA versions that keep implied mandatory
 * constraints: one that needs some and has none is older, and stays as it
 * is. */
static BOOL
ORMWritesImpliedMandatories(ORMModel *model)
{
	for (ORMConstraint *constraint in model.constraints) {
		if (constraint.kind == ORMMandatoryConstraint && constraint.isImplied
		    && ORMChild(constraint.element, CORE, @"ImpliedByObjectType") != nil) {
			return YES;
		}
	}
	return [ORMImpliedMandatoryRoles(model) count] == 0;
}

/* A derivation query's fact type keeps the query's words as its rule's,
 * which NORMA shows (docs/DERIVATION.md). Only where a query derives one:
 * a file without queries is left as it is. */
- (void)normalizeDerivations:(ORMModel *)model
{
	ORMVerbalizer *verbalizer = nil;
	for (ORMQuery *query in [ORMQuery queriesInModel:model]) {
		ORMFactType *fact = query.kind == ORMQueryDerivation ? query.derivedFactType : nil;
		NSXMLElement *note = ORMChild(ORMChild(ORMChild(ORMChild(fact.element, CORE, @"DerivationRule"), CORE,
		                                                 @"FactTypeDerivationPath"),
		                                         CORE, @"InformalRule"),
		                              CORE, @"DerivationNote");
		if (note == nil) {
			continue;
		}
		verbalizer = verbalizer ?: [[ORMVerbalizer alloc] initWithModel:model];
		NSString *text = [[ORMVerbalizer plainTextOfSentences:[verbalizer sentencesForQuery:query]]
			stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([text length] > 0 && ![ORMChildText(note, CORE, @"Body") isEqualToString:text]) {
			ORMSetChildText(_editor.document, note, CORE, @"Body", text);
		}
	}
}

- (void)normalizeImpliedMandatories:(ORMModel *)model
{
	if (!_writesImpliedMandatories) {
		return;
	}
	NSMutableDictionary *existing = [NSMutableDictionary dictionary];
	for (ORMConstraint *constraint in model.constraints) {
		NSString *owner = ORMRef(ORMChild(constraint.element, CORE, @"ImpliedByObjectType"));
		if (constraint.kind == ORMMandatoryConstraint && constraint.isImplied && owner != nil) {
			if ([existing objectForKey:owner] != nil || [model elementWithId:owner] == nil) {
				[constraint.element detach];
			} else {
				[existing setObject:constraint forKey:owner];
			}
		}
	}
	NSDictionary *needed = ORMImpliedMandatoryRoles(model);
	for (ORMObjectType *type in model.objectTypes) {
		NSArray *roles = [needed objectForKey:type.identifier ?: @""];
		ORMConstraint *current = [existing objectForKey:type.identifier ?: @""];
		if (roles == nil) {
			[current.element detach];
			continue;
		}
		NSMutableArray *have = [NSMutableArray array];
		for (ORMRole *role in [current allRoles]) {
			[have addObject:role.identifier];
		}
		if (current != nil && [[NSSet setWithArray:have] isEqualToSet:[NSSet setWithArray:roles]]
		    && [have count] == [ORMChildren(ORMChild(current.element, CORE, @"RoleSequence"), CORE, @"Role") count]) {
			continue;
		}
		NSXMLElement *constraint = current.element;
		if (constraint == nil) {
			constraint = [_editor newConstraint:@"MandatoryConstraint" named:@"ImpliedMandatoryConstraint"];
			ORMSetAttribute(constraint, @"IsImplied", @"true");
		}
		[ORMChild(constraint, CORE, @"RoleSequence") detach];
		[constraint insertChild:[_editor newRoleSequence:roles withId:NO] atIndex:0];
		if (ORMChild(constraint, CORE, @"ImpliedByObjectType") == nil) {
			[constraint addChild:ORMNewRef(_editor.document, CORE, @"ImpliedByObjectType", type.identifier)];
		}
	}
}

@end
