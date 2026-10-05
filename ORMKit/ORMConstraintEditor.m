/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditorPriv.h"

@implementation ORMConstraintEditor

@synthesize editor = _editor;

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

/* A constraint drawn as a shape of its own (external, ring, frequency,
 * value comparison: placeElement: says which) shown on each diagram that
 * shows every fact type it constrains, as NORMA shows one it adds. Inside
 * the change that adds it, so it is undone with it. */
- (void)showOnDiagrams:(NSString *)constraintId
{
	ORMConstraint *constraint = constraintId != nil ? [_editor.model elementWithId:constraintId] : nil;
	if (![constraint isKindOfClass:[ORMConstraint class]] || ![constraint isExternal] || constraint.isImplied) {
		return;
	}
	NSArray *facts = [constraint factTypes];
	for (ORMDiagram *diagram in _editor.model.diagrams) {
		BOOL shows = [facts count] > 0;
		for (ORMFactType *fact in facts) {
			shows = shows && [diagram shapeForSubject:fact.identifier] != nil;
		}
		if (shows) {
			[_editor.diagramEditor placeElement:constraintId onDiagram:diagram.identifier at:ORMAutomaticPlacement];
		}
	}
}

/* Whether the roles are all in one fact type. */
static BOOL
ORMRolesShareFactType(NSArray<ORMRole *> *roles)
{
	ORMFactType *fact = [[roles firstObject] factType];
	for (ORMRole *role in roles) {
		if (role.factType != fact) {
			return NO;
		}
	}
	return YES;
}

- (NSArray *)idsOf:(NSArray<ORMRole *> *)roles
{
	NSMutableArray *ids = [NSMutableArray array];
	for (ORMRole *role in roles) {
		[ids addObject:role.identifier];
	}
	return ids;
}

- (NSString *)addUniquenessConstraintOverRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason
{
	NSArray *roles = [_editor rolesWithIds:roleIds reason:reason];
	if (roles == nil) {
		return nil;
	}
	BOOL internal = ORMRolesShareFactType(roles);
	if (internal) {
		ORMFactType *fact = [[roles firstObject] factType];
		if ([fact hasUniquenessOverRoles:roles]) {
			if (reason != NULL) {
				*reason = @"Those roles are already unique together.";
			}
			return nil;
		}
		/* ORM's n-1 rule: a uniqueness constraint over fewer than all but
		 * one of an n-ary fact type's roles would make it splittable. */
		if ([fact arity] > 2 && [roles count] < [fact arity] - 1) {
			if (reason != NULL) {
				*reason = [NSString stringWithFormat:@"A uniqueness constraint on a fact type of %lu roles spans "
				                                     @"at least %lu of them.",
				           (unsigned long)[fact arity], (unsigned long)[fact arity] - 1];
			}
			return nil;
		}
	} else if ([roles count] < 2) {
		if (reason != NULL) {
			*reason = @"An external uniqueness constraint spans roles of two or more fact types.";
		}
		return nil;
	}
	__block NSString *created = nil;
	[_editor group:internal ? @"Add Uniqueness Constraint" : @"Add External Uniqueness Constraint" with:^{
		[_editor change:internal ? @"Add Uniqueness Constraint" : @"Add External Uniqueness Constraint" with:^{
			NSXMLElement *constraint = nil;
			if (internal) {
				constraint = [self newInternalUniqueness:roleIds];
			} else {
				constraint = [_editor newConstraint:@"UniquenessConstraint" named:@"ExternalUniquenessConstraint"];
				[constraint addChild:[_editor newRoleSequence:roleIds withId:NO]];
			}
			created = ORMAttribute(constraint, @"id");
		}];
		[self showOnDiagrams:created];
	}];
	return created;
}

- (NSString *)addMandatoryConstraintOverRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason
{
	NSArray *roles = [_editor rolesWithIds:roleIds reason:reason];
	if (roles == nil) {
		return nil;
	}
	if ([roles count] == 1) {
		if ([[roles firstObject] isMandatory]) {
			if (reason != NULL) {
				*reason = @"The role is already mandatory.";
			}
			return nil;
		}
		__block NSString *created = nil;
		[_editor group:@"Add Mandatory Constraint" with:^{
			[_editor change:@"Add Mandatory Constraint" with:^{
				created = ORMAttribute([self newSimpleMandatory:[roleIds firstObject]], @"id");
			}];
			[self showOnDiagrams:created];
		}];
		return created;
	}
	/* An inclusive-or: every role played by one object type, or its
	 * supertypes. */
	ORMObjectType *player = [[roles firstObject] player];
	for (ORMRole *role in roles) {
		if (role.player != player && ![role.player isSubtypeOf:player] && ![player isSubtypeOf:role.player]) {
			if (reason != NULL) {
				*reason = @"An inclusive-or constraint spans roles played by the same object type.";
			}
			return nil;
		}
	}
	__block NSString *created = nil;
	[_editor group:@"Add Inclusive-Or Constraint" with:^{
		[_editor change:@"Add Inclusive-Or Constraint" with:^{
			NSXMLElement *constraint = [_editor newConstraint:@"MandatoryConstraint" named:@"InclusiveOrConstraint"];
			[constraint addChild:[_editor newRoleSequence:roleIds withId:NO]];
			created = ORMAttribute(constraint, @"id");
		}];
		[self showOnDiagrams:created];
	}];
	return created;
}

- (BOOL)setMandatory:(BOOL)mandatory role:(NSString *)roleId reason:(NSString **)reason
{
	ORMRole *role = [_editor.model elementWithId:roleId];
	if (![role isKindOfClass:[ORMRole class]]) {
		if (reason != NULL) {
			*reason = @"Pick a role.";
		}
		return NO;
	}
	if (role.isMandatory == mandatory) {
		return YES;
	}
	if (mandatory) {
		return [self addMandatoryConstraintOverRoles:@[ roleId ] reason:reason] != nil;
	}
	NSMutableArray *doomed = [NSMutableArray array];
	for (ORMConstraint *constraint in role.constraints) {
		if (constraint.kind == ORMMandatoryConstraint && constraint.isSimple) {
			[doomed addObject:constraint.identifier];
		}
	}
	[_editor.elementEditor deleteElements:doomed];
	return YES;
}

- (BOOL)setUnique:(BOOL)unique role:(NSString *)roleId reason:(NSString **)reason
{
	ORMRole *role = [_editor.model elementWithId:roleId];
	if (![role isKindOfClass:[ORMRole class]]) {
		if (reason != NULL) {
			*reason = @"Pick a role.";
		}
		return NO;
	}
	if (role.isUnique == unique) {
		return YES;
	}
	if (unique) {
		return [self addUniquenessConstraintOverRoles:@[ roleId ] reason:reason] != nil;
	}
	NSMutableArray *doomed = [NSMutableArray array];
	for (ORMConstraint *constraint in role.constraints) {
		if (constraint.kind == ORMUniquenessConstraint && constraint.isInternal && [[constraint allRoles] count] == 1) {
			if (constraint.preferredIdentifierFor != nil) {
				if (reason != NULL) {
					*reason = [NSString stringWithFormat:@"It identifies %@; give %@ another identifier first.",
					           constraint.preferredIdentifierFor.name, constraint.preferredIdentifierFor.name];
				}
				return NO;
			}
			[doomed addObject:constraint.identifier];
		}
	}
	[_editor.elementEditor deleteElements:doomed];
	return YES;
}

- (NSString *)addFrequencyConstraintOverRoles:(NSArray<NSString *> *)roleIds
                                          min:(NSUInteger)min
                                          max:(NSUInteger)max
                                       reason:(NSString **)reason
{
	NSArray *roles = [_editor rolesWithIds:roleIds reason:reason];
	if (roles == nil) {
		return nil;
	}
	if (min < 1 || (max != 0 && max < min) || (min == 1 && max == 1)) {
		if (reason != NULL) {
			*reason = min == 1 && max == 1 ? @"Exactly once is a uniqueness constraint."
			                                : @"A frequency is at least 1 and its maximum no less than its minimum.";
		}
		return nil;
	}
	__block NSString *created = nil;
	[_editor group:@"Add Frequency Constraint" with:^{
		[_editor change:@"Add Frequency Constraint" with:^{
			NSXMLElement *constraint = [_editor newConstraint:@"FrequencyConstraint" named:@"FrequencyConstraint"];
			ORMSetAttribute(constraint, @"MinFrequency", [NSString stringWithFormat:@"%lu", (unsigned long)min]);
			ORMSetAttribute(constraint, @"MaxFrequency", [NSString stringWithFormat:@"%lu", (unsigned long)max]);
			[constraint addChild:[_editor newRoleSequence:roleIds withId:NO]];
			created = ORMAttribute(constraint, @"id");
		}];
		[self showOnDiagrams:created];
	}];
	return created;
}

/* Whether the two object types are compatible: the same, or one a
 * subtype of the other, as set comparison and ring constraints require. */
static BOOL
ORMCompatible(ORMObjectType *a, ORMObjectType *b)
{
	return a == b || [a isSubtypeOf:b] || [b isSubtypeOf:a];
}

- (NSString *)addRingConstraint:(ORMRingType)type overRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason
{
	NSArray *roles = [_editor rolesWithIds:roleIds reason:reason];
	if (roles == nil) {
		return nil;
	}
	if ([roles count] != 2 || !ORMCompatible([[roles firstObject] player], [[roles lastObject] player])) {
		if (reason != NULL) {
			*reason = @"A ring constraint spans two roles played by the same object type.";
		}
		return nil;
	}
	if ([[ORMConstraint nameOfRingType:type] isEqualToString:@"Undefined"]) {
		if (reason != NULL) {
			*reason = @"That combination of ring properties is not one ORM has.";
		}
		return nil;
	}
	__block NSString *created = nil;
	[_editor group:@"Add Ring Constraint" with:^{
		[_editor change:@"Add Ring Constraint" with:^{
			NSXMLElement *constraint = [_editor newConstraint:@"RingConstraint" named:@"RingConstraint"];
			ORMSetAttribute(constraint, @"Type", [ORMConstraint nameOfRingType:type]);
			[constraint addChild:[_editor newRoleSequence:roleIds withId:NO]];
			created = ORMAttribute(constraint, @"id");
		}];
		[self showOnDiagrams:created];
	}];
	return created;
}

- (BOOL)checkSequences:(NSArray<NSArray<NSString *> *> *)roleIds reason:(NSString **)reason
{
	if ([roleIds count] < 2) {
		if (reason != NULL) {
			*reason = @"A set comparison compares two or more role sequences.";
		}
		return NO;
	}
	NSArray *first = nil;
	for (NSArray *sequence in roleIds) {
		NSArray *roles = [_editor rolesWithIds:sequence reason:reason];
		if (roles == nil) {
			return NO;
		}
		if (first == nil) {
			first = roles;
			continue;
		}
		if ([roles count] != [first count]) {
			if (reason != NULL) {
				*reason = @"The role sequences compared must be equally long.";
			}
			return NO;
		}
		for (NSUInteger i = 0; i < [roles count]; i++) {
			if (!ORMCompatible([[roles objectAtIndex:i] player], [[first objectAtIndex:i] player])) {
				if (reason != NULL) {
					*reason = [NSString stringWithFormat:@"The roles at place %lu are played by incompatible "
					                                     @"object types.", (unsigned long)i + 1];
				}
				return NO;
			}
		}
	}
	return YES;
}

- (NSXMLElement *)newSetComparison:(NSString *)local named:(NSString *)prefix sequences:(NSArray *)roleIds
{
	NSXMLElement *constraint = [_editor newConstraint:local named:prefix];
	NSXMLElement *sequences = ORMNewElement(_editor.document, CORE, @"RoleSequences");
	for (NSArray *sequence in roleIds) {
		[sequences addChild:[_editor newRoleSequence:sequence withId:YES]];
	}
	[constraint addChild:sequences];
	return constraint;
}

- (NSString *)addSetComparisonConstraint:(ORMConstraintKind)kind
                               sequences:(NSArray<NSArray<NSString *> *> *)roleIds
                                  reason:(NSString **)reason
{
	NSDictionary *names = @{ @(ORMSubsetConstraint): @"SubsetConstraint",
	                         @(ORMEqualityConstraint): @"EqualityConstraint",
	                         @(ORMExclusionConstraint): @"ExclusionConstraint" };
	NSString *local = [names objectForKey:@(kind)];
	if (local == nil) {
		if (reason != NULL) {
			*reason = @"Subset, equality and exclusion are set comparisons.";
		}
		return nil;
	}
	if (![self checkSequences:roleIds reason:reason]) {
		return nil;
	}
	if (kind == ORMSubsetConstraint && [roleIds count] != 2) {
		if (reason != NULL) {
			*reason = @"A subset constraint compares exactly two sequences.";
		}
		return nil;
	}
	__block NSString *created = nil;
	[_editor group:[NSString stringWithFormat:@"Add %@", local] with:^{
		[_editor change:[NSString stringWithFormat:@"Add %@", local] with:^{
			created = ORMAttribute([self newSetComparison:local named:local sequences:roleIds], @"id");
		}];
		[self showOnDiagrams:created];
	}];
	return created;
}

- (NSString *)addExclusiveOrConstraintOverRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason
{
	NSMutableArray *sequences = [NSMutableArray array];
	for (NSString *roleId in roleIds) {
		[sequences addObject:@[ roleId ]];
	}
	if (![self checkSequences:sequences reason:reason]) {
		return nil;
	}
	__block NSString *created = nil;
	[_editor group:@"Add Exclusive-Or Constraint" with:^{
		[_editor change:@"Add Exclusive-Or Constraint" with:^{
			NSXMLElement *exclusion = [self newSetComparison:@"ExclusionConstraint" named:@"ExclusionConstraint"
			                                        sequences:sequences];
			NSXMLElement *mandatory = [_editor newConstraint:@"MandatoryConstraint" named:@"ExclusiveOrConstraint"];
			[mandatory addChild:[_editor newRoleSequence:roleIds withId:NO]];
			[exclusion addChild:ORMNewRef(_editor.document, CORE, @"ExclusiveOrMandatoryConstraint",
			                              ORMAttribute(mandatory, @"id"))];
			[mandatory addChild:ORMNewRef(_editor.document, CORE, @"ExclusiveOrExclusionConstraint",
			                              ORMAttribute(exclusion, @"id"))];
			created = ORMAttribute(exclusion, @"id");
		}];
		[self showOnDiagrams:created];
	}];
	return created;
}

- (NSString *)addValueComparisonConstraint:(NSString *)comparisonOperator
                                 overRoles:(NSArray<NSString *> *)roleIds
                                    reason:(NSString **)reason
{
	NSArray *operators = @[ @"Equal", @"NotEqual", @"LessThan", @"LessThanOrEqual", @"GreaterThan",
	                        @"GreaterThanOrEqual" ];
	if (![operators containsObject:comparisonOperator]) {
		if (reason != NULL) {
			*reason = @"Compare with =, <>, <, <=, > or >=.";
		}
		return nil;
	}
	NSArray *roles = [_editor rolesWithIds:roleIds reason:reason];
	if (roles == nil) {
		return nil;
	}
	if ([roles count] != 2) {
		if (reason != NULL) {
			*reason = @"A value comparison compares two roles.";
		}
		return nil;
	}
	__block NSString *created = nil;
	[_editor group:@"Add Value Comparison Constraint" with:^{
		[_editor change:@"Add Value Comparison Constraint" with:^{
			NSXMLElement *constraint = [_editor newConstraint:@"ValueComparisonConstraint" named:@"ValueComparisonConstraint"];
			ORMSetAttribute(constraint, @"Operator", comparisonOperator);
			[constraint addChild:[_editor newRoleSequence:roleIds withId:NO]];
			created = ORMAttribute(constraint, @"id");
		}];
		[self showOnDiagrams:created];
	}];
	return created;
}

- (ORMConstraint *)constraint:(NSString *)constraintId kind:(ORMConstraintKind)kind reason:(NSString **)reason
{
	ORMConstraint *constraint = [_editor.model elementWithId:constraintId];
	if (![constraint isKindOfClass:[ORMConstraint class]] || (kind != (ORMConstraintKind)-1 && constraint.kind != kind)) {
		if (reason != NULL) {
			*reason = @"Pick a constraint of that kind.";
		}
		return nil;
	}
	return constraint;
}

- (BOOL)setFrequencyMin:(NSUInteger)min max:(NSUInteger)max of:(NSString *)constraintId reason:(NSString **)reason
{
	ORMConstraint *constraint = [self constraint:constraintId kind:ORMFrequencyConstraint reason:reason];
	if (constraint == nil) {
		return NO;
	}
	if (min < 1 || (max != 0 && max < min)) {
		if (reason != NULL) {
			*reason = @"A frequency is at least 1 and its maximum no less than its minimum.";
		}
		return NO;
	}
	[_editor change:@"Set Frequency" with:^{
		ORMSetAttribute(constraint.element, @"MinFrequency", [NSString stringWithFormat:@"%lu", (unsigned long)min]);
		ORMSetAttribute(constraint.element, @"MaxFrequency", [NSString stringWithFormat:@"%lu", (unsigned long)max]);
	}];
	return YES;
}

- (BOOL)setRingType:(ORMRingType)type of:(NSString *)constraintId reason:(NSString **)reason
{
	ORMConstraint *constraint = [self constraint:constraintId kind:ORMRingConstraint reason:reason];
	if (constraint == nil) {
		return NO;
	}
	NSString *name = [ORMConstraint nameOfRingType:type];
	if ([name isEqualToString:@"Undefined"]) {
		if (reason != NULL) {
			*reason = @"That combination of ring properties is not one ORM has.";
		}
		return NO;
	}
	[_editor change:@"Set Ring Type" with:^{
		ORMSetAttribute(constraint.element, @"Type", name);
	}];
	return YES;
}

- (BOOL)setModality:(ORMModality)modality of:(NSString *)constraintId reason:(NSString **)reason
{
	ORMConstraint *constraint = [self constraint:constraintId kind:(ORMConstraintKind)-1 reason:reason];
	if (constraint == nil) {
		return NO;
	}
	if (constraint.modality == modality) {
		return YES;
	}
	[_editor change:@"Set Modality" with:^{
		ORMSetAttribute(constraint.element, @"Modality", modality == ORMDeontic ? @"Deontic" : nil);
	}];
	return YES;
}

/* The entity type a uniqueness constraint can identify: the one that
 * plays every role opposite its roles in their binary fact types. */
static ORMObjectType *
ORMIdentifiedBy(ORMConstraint *constraint)
{
	ORMObjectType *identified = nil;
	NSArray *roles = [constraint allRoles];
	if ([roles count] == 0) {
		return nil;
	}
	/* An objectified fact type's spanning (or n-1) constraint identifies
	 * the objectified type. */
	ORMFactType *fact = [[roles firstObject] factType];
	if (constraint.isInternal && fact.objectifyingType != nil) {
		return fact.objectifyingType;
	}
	for (ORMRole *role in roles) {
		ORMRole *opposite = [role oppositeRole];
		if (opposite == nil || opposite.player == nil || (identified != nil && opposite.player != identified)) {
			return nil;
		}
		identified = opposite.player;
	}
	return identified.isEntity ? identified : nil;
}

- (BOOL)setPreferredIdentifier:(NSString *)constraintId reason:(NSString **)reason
{
	ORMConstraint *constraint = [self constraint:constraintId kind:ORMUniquenessConstraint reason:reason];
	if (constraint == nil) {
		return NO;
	}
	ORMObjectType *identified = ORMIdentifiedBy(constraint);
	if (identified == nil) {
		if (reason != NULL) {
			*reason = @"The constraint does not identify an entity type: its roles must be opposite roles one "
			          @"entity type plays.";
		}
		return NO;
	}
	if (identified.preferredIdentifier == constraint) {
		return YES;
	}
	[_editor change:@"Set Preferred Identifier" with:^{
		NSXMLElement *preferred = ORMChild(identified.element, CORE, @"PreferredIdentifier");
		if (preferred == nil) {
			ORMInsertChild(identified.element, ORMNewRef(_editor.document, CORE, @"PreferredIdentifier", constraintId));
		} else {
			ORMSetAttribute(preferred, @"ref", constraintId);
		}
	}];
	return YES;
}

/* An internal constraint over the roles: uniqueness or simple mandatory. */
- (NSXMLElement *)newInternalUniqueness:(NSArray<NSString *> *)roleIds
{
	NSXMLElement *constraint = [_editor newConstraint:@"UniquenessConstraint" named:@"InternalUniquenessConstraint"];
	ORMSetAttribute(constraint, @"IsInternal", @"true");
	[constraint addChild:[_editor newRoleSequence:roleIds withId:NO]];
	return constraint;
}

- (NSXMLElement *)newSimpleMandatory:(NSString *)roleId
{
	NSXMLElement *constraint = [_editor newConstraint:@"MandatoryConstraint" named:@"SimpleMandatoryConstraint"];
	ORMSetAttribute(constraint, @"IsSimple", @"true");
	[constraint addChild:[_editor newRoleSequence:@[ roleId ] withId:NO]];
	return constraint;
}

@end
