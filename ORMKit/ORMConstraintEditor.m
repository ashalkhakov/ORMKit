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
		[_editor modelChange:internal ? @"Add Uniqueness Constraint" : @"Add External Uniqueness Constraint" with:^{
			created = (internal ? [self addInternalUniqueness:roles]
			                    : [self addConstraint:ORMUniquenessConstraint named:@"ExternalUniquenessConstraint"
			                                     over:roles]).identifier;
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
			[_editor modelChange:@"Add Mandatory Constraint" with:^{
				created = [self addSimpleMandatory:[roles firstObject]].identifier;
			}];
			[self showOnDiagrams:created];
		}];
		return created;
	}
	/* An inclusive-or: every role played by one object type, or its
	 * supertypes. */
	ORMObjectType *player = [[roles firstObject] player];
	for (ORMRole *role in roles) {
		if (![role.player isCompatibleWith:player]) {
			if (reason != NULL) {
				*reason = @"An inclusive-or constraint spans roles played by the same object type.";
			}
			return nil;
		}
	}
	__block NSString *created = nil;
	[_editor group:@"Add Inclusive-Or Constraint" with:^{
		[_editor modelChange:@"Add Inclusive-Or Constraint" with:^{
			created = [self addConstraint:ORMMandatoryConstraint named:@"InclusiveOrConstraint" over:roles].identifier;
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
		[_editor modelChange:@"Add Frequency Constraint" with:^{
			ORMConstraint *constraint = [self addConstraint:ORMFrequencyConstraint named:@"FrequencyConstraint" over:roles];
			constraint.minFrequency = min;
			constraint.maxFrequency = max;
			created = constraint.identifier;
		}];
		[self showOnDiagrams:created];
	}];
	return created;
}

- (NSString *)addRingConstraint:(ORMRingType)type overRoles:(NSArray<NSString *> *)roleIds reason:(NSString **)reason
{
	NSArray *roles = [_editor rolesWithIds:roleIds reason:reason];
	if (roles == nil) {
		return nil;
	}
	if ([roles count] != 2 || ![[[roles firstObject] player] isCompatibleWith:[[roles lastObject] player]]) {
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
		[_editor modelChange:@"Add Ring Constraint" with:^{
			ORMConstraint *constraint = [self addConstraint:ORMRingConstraint named:@"RingConstraint" over:roles];
			constraint.ringType = type;
			created = constraint.identifier;
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
			if (![[[roles objectAtIndex:i] player] isCompatibleWith:[[first objectAtIndex:i] player]]) {
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
		[_editor modelChange:[NSString stringWithFormat:@"Add %@", local] with:^{
			created = [self addSetComparison:kind named:local sequences:roleIds].identifier;
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
		[_editor modelChange:@"Add Exclusive-Or Constraint" with:^{
			ORMConstraint *exclusion = [self addSetComparison:ORMExclusionConstraint named:@"ExclusionConstraint"
			                                        sequences:sequences];
			ORMConstraint *mandatory = [self addConstraint:ORMMandatoryConstraint named:@"ExclusiveOrConstraint"
			                                          over:[_editor rolesWithIds:roleIds reason:NULL]];
			exclusion.exclusiveOrPartner = mandatory;
			mandatory.exclusiveOrPartner = exclusion;
			created = exclusion.identifier;
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
		[_editor modelChange:@"Add Value Comparison Constraint" with:^{
			ORMConstraint *constraint = [self addConstraint:ORMValueComparisonConstraint named:@"ValueComparisonConstraint"
			                                           over:roles];
			constraint.comparisonOperator = comparisonOperator;
			created = constraint.identifier;
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
	[_editor modelChange:@"Set Frequency" with:^{
		constraint.minFrequency = min;
		constraint.maxFrequency = max;
		[_editor wrote:constraint];
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
	[_editor modelChange:@"Set Ring Type" with:^{
		constraint.ringType = type;
		[_editor wrote:constraint];
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
	[_editor modelChange:@"Set Modality" with:^{
		constraint.modality = modality;
		[_editor wrote:constraint];
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
	ORMConstraint *was = identified.preferredIdentifier;
	[_editor modelChange:@"Set Preferred Identifier" with:^{
		identified.preferredIdentifier = constraint;
		[_editor wrote:identified];
		/* No longer the identifier, it names nothing. */
		[_editor wrote:was];
	}];
	return YES;
}

/* An internal constraint over the roles: uniqueness or simple mandatory. */
/* A new constraint over one sequence of the roles, without an id, as
 * NORMA keeps a constraint of one sequence. */
- (ORMConstraint *)addConstraint:(ORMConstraintKind)kind named:(NSString *)prefix over:(NSArray<ORMRole *> *)roles
{
	ORMModel *model = _editor.model;
	ORMConstraint *constraint = [[ORMConstraint alloc] initWithModel:model];
	constraint.kind = kind;
	constraint.name = [_editor nextName:prefix];
	ORMRoleSequence *sequence = [[ORMRoleSequence alloc] initWithModel:model];
	sequence.identifier = nil;
	sequence.roles = roles;
	constraint.roleSequences = @[ sequence ];
	[model addElement:constraint];
	[_editor wrote:constraint];
	return constraint;
}

- (BOOL)keepImpliedMandatories
{
	if (!_editor.writesImpliedMandatories) {
		return NO;
	}
	ORMModel *model = _editor.model;
	BOOL changed = NO;
	NSMutableDictionary *existing = [NSMutableDictionary dictionary];
	for (ORMConstraint *constraint in model.constraints) {
		NSString *owner = constraint.impliedByObjectTypeId;
		if (constraint.kind == ORMMandatoryConstraint && constraint.isImplied && owner != nil) {
			if ([existing objectForKey:owner] != nil || [model elementWithId:owner] == nil) {
				[self removeConstraint:constraint];
				changed = YES;
			} else {
				[existing setObject:constraint forKey:owner];
			}
		}
	}
	NSDictionary *needed = ORMImpliedMandatoryRoles(model);
	for (ORMObjectType *type in model.objectTypes) {
		NSArray *roleIds = [needed objectForKey:type.identifier ?: @""];
		ORMConstraint *current = [existing objectForKey:type.identifier ?: @""];
		if (roleIds == nil) {
			if (current != nil) {
				[self removeConstraint:current];
				changed = YES;
			}
			continue;
		}
		NSArray *have = [[current allRoles] valueForKey:@"identifier"];
		NSXMLElement *written = ORMChild(current.element, CORE, @"RoleSequence");
		if (current != nil && [[NSSet setWithArray:have] isEqualToSet:[NSSet setWithArray:roleIds]]
		    && (written == nil || [have count] == [ORMChildren(written, CORE, @"Role") count])) {
			continue;
		}
		NSMutableArray *roles = [NSMutableArray array];
		for (NSString *roleId in roleIds) {
			[roles addObject:[model elementWithId:roleId]];
		}
		if (current == nil) {
			current = [self addConstraint:ORMMandatoryConstraint named:@"ImpliedMandatoryConstraint" over:roles];
			current.isImplied = YES;
			current.impliedByObjectTypeId = type.identifier;
		} else {
			ORMRoleSequence *sequence = [current.roleSequences firstObject];
			sequence.roles = roles;
			[_editor wrote:sequence];
		}
		changed = YES;
	}
	return changed;
}

/* A constraint out of the model, and its XML element with it. */
- (void)removeConstraint:(ORMConstraint *)constraint
{
	[_editor.model removeElement:constraint];
	[_editor deleted:constraint];
}

/* A set comparison over the role sequences (by ids), each with an id of
 * its own, as NORMA keeps a constraint of several. */
- (ORMConstraint *)addSetComparison:(ORMConstraintKind)kind
                              named:(NSString *)prefix
                          sequences:(NSArray<NSArray<NSString *> *> *)roleIds
{
	ORMModel *model = _editor.model;
	ORMConstraint *constraint = [[ORMConstraint alloc] initWithModel:model];
	constraint.kind = kind;
	constraint.name = [_editor nextName:prefix];
	NSMutableArray *sequences = [NSMutableArray array];
	for (NSArray *ids in roleIds) {
		ORMRoleSequence *sequence = [[ORMRoleSequence alloc] initWithModel:model];
		sequence.roles = [_editor rolesWithIds:ids reason:NULL];
		[model registerElement:sequence];
		[sequences addObject:sequence];
	}
	constraint.roleSequences = sequences;
	[model addElement:constraint];
	[_editor wrote:constraint];
	return constraint;
}

- (ORMConstraint *)addInternalUniqueness:(NSArray<ORMRole *> *)roles
{
	ORMConstraint *constraint = [self addConstraint:ORMUniquenessConstraint named:@"InternalUniquenessConstraint" over:roles];
	constraint.isInternal = YES;
	return constraint;
}

- (ORMConstraint *)addSimpleMandatory:(ORMRole *)role
{
	ORMConstraint *constraint = [self addConstraint:ORMMandatoryConstraint named:@"SimpleMandatoryConstraint" over:@[ role ]];
	constraint.isSimple = YES;
	return constraint;
}

@end
