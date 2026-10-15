/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEntityMerger.h"
#import "ORMCoreDataMapper.h"
#import "ORMCoreDataSync.h"
#import "ORMFactTypeEditor.h"
#import "ORMObjectTypeEditor.h"
#import "ORMConstraintEditor.h"
#import "ORMElementEditor.h"

@interface ORMMergeCandidate ()
@property (nonatomic, readwrite, strong) ORMObjectType *kept;
@property (nonatomic, readwrite, strong) ORMRole *keptRole;
@property (nonatomic, readwrite, strong) ORMObjectType *absorbed;
@property (nonatomic, readwrite, strong) ORMRole *absorbedRole;
/* The value's name, as both have it. */
@property (nonatomic, copy) NSString *valueName;
@end

@implementation ORMMergeCandidate

- (NSString *)text
{
	return [NSString stringWithFormat:@"%@ and %@ may be one entity type: both have %@.", self.kept.name,
	                                  self.absorbed.name, self.valueName];
}

@end

/* The value role of a one-to-one binary fact type the type plays the other
 * role of; nil for another role. */
static ORMRole *
ORMOneToOneValue(ORMRole *own)
{
	ORMRole *far = [own oppositeRole];
	if (far == nil || [[own.factType roles] count] != 2 || own.factType.kind != ORMFactTypeOrdinary
	    || far.player.kind != ORMValueType || !own.isUnique || !far.isUnique) {
		return nil;
	}
	return far;
}

/* What the value is called, as the table had it: a popular reference
 * mode's mode, else its value type's name. */
static NSString *
ORMValueNameOf(ORMObjectType *type, ORMRole *far)
{
	if (far.factType == type.referenceModeFactType && type.referenceModeKind == ORMReferenceModePopular
	    && [type.referenceMode length] > 0) {
		return type.referenceMode;
	}
	return far.player.name;
}

/* Whether the value role is the type's preferred identifier's. */
static BOOL
ORMIdentifies(ORMObjectType *type, ORMRole *far)
{
	NSArray *roles = [type.preferredIdentifier allRoles];
	return [roles count] == 1 && [roles firstObject] == far;
}

@implementation ORMEntityMerger

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

/* An entity type that can be one of the two: no subtype or supertype. */
- (BOOL)mergeable:(ORMObjectType *)type
{
	return [type isKindOfClass:[ORMObjectType class]] && type.isEntity && [type.supertypes count] == 0
	       && [type.subtypes count] == 0 && type.nestedFactType == nil;
}

- (NSArray<ORMMergeCandidate *> *)candidates
{
	ORMModel *model = _editor.model;
	/* Each type's one-to-one values, by their name and data type. */
	NSMutableArray *values = [NSMutableArray array];
	for (ORMObjectType *type in model.objectTypes) {
		if (![self mergeable:type]) {
			continue;
		}
		for (ORMRole *own in type.playedRoles) {
			ORMRole *far = ORMOneToOneValue(own);
			if (far == nil) {
				continue;
			}
			NSString *key = [NSString stringWithFormat:@"%@ %@", [ORMValueNameOf(type, far) lowercaseString],
			                                           far.player.dataType.typeName ?: @""];
			[values addObject:@[ key, type, far ]];
		}
	}
	NSMutableArray *candidates = [NSMutableArray array];
	NSMutableSet *pairs = [NSMutableSet set];
	for (NSUInteger i = 0; i < [values count]; i++) {
		for (NSUInteger j = i + 1; j < [values count]; j++) {
			NSArray *a = [values objectAtIndex:i];
			NSArray *b = [values objectAtIndex:j];
			ORMObjectType *first = [a objectAtIndex:1];
			ORMObjectType *second = [b objectAtIndex:1];
			if (first == second || ![[a firstObject] isEqualToString:[b firstObject]]) {
				continue;
			}
			NSString *pair = [@[ first.identifier, second.identifier ] componentsJoinedByString:@" "];
			NSString *back = [@[ second.identifier, first.identifier ] componentsJoinedByString:@" "];
			if ([pairs containsObject:pair] || [pairs containsObject:back]) {
				continue;
			}
			[pairs addObject:pair];
			/* Kept: the one the value identifies, where only one is. */
			BOOL swap = !ORMIdentifies(first, [a lastObject]) && ORMIdentifies(second, [b lastObject]);
			ORMMergeCandidate *candidate = [[ORMMergeCandidate alloc] init];
			candidate.kept = swap ? second : first;
			candidate.keptRole = swap ? [b lastObject] : [a lastObject];
			candidate.absorbed = swap ? first : second;
			candidate.absorbedRole = swap ? [a lastObject] : [b lastObject];
			candidate.valueName = ORMValueNameOf(candidate.kept, candidate.keptRole);
			[candidates addObject:candidate];
		}
	}
	return candidates;
}

/* What a property of the role is traced by: a binary's other role, a
 * unary's implicit one, an n-ary or objectified fact type's inverse. */
static NSString *
ORMTraceOf(ORMRole *role)
{
	ORMFactType *fact = role.factType;
	if ([fact.roles count] == 2 && fact.objectifyingType == nil) {
		return [[role oppositeRole] identifier];
	}
	return [fact.identifier stringByAppendingFormat:@".%@", role.identifier];
}

/* An entity's name in a mapping, as it maps now. */
static NSString *
ORMEntityNameIn(ORMCDModel *mapped, ORMObjectType *type)
{
	return [mapped entityWithSource:type.identifier].name ?: [ORMCoreDataMapper entityNameFor:type.name];
}

- (BOOL)merge:(NSString *)absorbedId
         into:(NSString *)keptId
     matching:(NSString *)absorbedRoleId
         with:(NSString *)keptRoleId
       reason:(NSString **)reason
{
	ORMModel *model = _editor.model;
	ORMObjectType *kept = [model elementWithId:keptId];
	ORMObjectType *absorbed = [model elementWithId:absorbedId];
	ORMRole *keptFar = [model elementWithId:keptRoleId];
	ORMRole *absorbedFar = [model elementWithId:absorbedRoleId];
	NSString *why = nil;
	if (![self mergeable:kept] || ![self mergeable:absorbed] || kept == absorbed) {
		why = @"Two entity types are merged, neither a subtype, a supertype or an objectification.";
	} else if (![keptFar isKindOfClass:[ORMRole class]] || ![absorbedFar isKindOfClass:[ORMRole class]]
	           || [keptFar oppositeRole].player != kept || [absorbedFar oppositeRole].player != absorbed
	           || keptFar.player.kind != ORMValueType || absorbedFar.player.kind != ORMValueType) {
		why = @"Each is matched by a value it has.";
	} else if (ORMOneToOneValue([absorbedFar oppositeRole]) == nil || ![keptFar oppositeRole].isUnique) {
		why = [NSString stringWithFormat:@"%@ has one %@, and each %@ is one %@'s.", absorbed.name, absorbedFar.player.name,
		                                 absorbedFar.player.name, absorbed.name];
	} else if (![keptFar.player.dataType.typeName isEqualToString:absorbedFar.player.dataType.typeName ?: @""]) {
		why = [NSString stringWithFormat:@"%@ and %@ are of different data types.", keptFar.player.name,
		                                 absorbedFar.player.name];
	} else if ([[absorbed.preferredIdentifier allRoles] count] > 1) {
		why = [NSString stringWithFormat:@"%@ is identified by several fact types: it is not merged yet.", absorbed.name];
	}
	if (why != nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return NO;
	}
	/* What the mappings have of the absorbed type, before it goes. */
	ORMFactType *matched = absorbedFar.factType;
	NSMutableArray *moved = [NSMutableArray array];
	NSMutableArray *traces = [NSMutableArray array];
	for (ORMRole *role in absorbed.playedRoles) {
		if (role.factType != matched && !role.isSubtypeMetaRole && !role.isSupertypeMetaRole) {
			[moved addObject:role.identifier];
			[traces addObject:ORMTraceOf(role)];
		}
	}
	NSArray *mappings = [ORMCoreDataMapping mappingsOfDocument:_editor.document];
	NSMutableArray *places = [NSMutableArray array];
	for (ORMCoreDataMapping *mapping in mappings) {
		/* As it maps now: the names the store has. */
		ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:model mapping:mapping] map];
		ORMCDEntity *written = [mapped entityWithSource:absorbed.identifier];
		NSString *valueName = nil;
		BOOL looseValue = NO;
		for (ORMCDAttribute *attribute in written.attributes) {
			if ([attribute.source isEqualToString:absorbedFar.identifier]) {
				valueName = attribute.name;
				looseValue = attribute.optional;
			}
		}
		/* Each property it had, named as written: the rules name it
		 * otherwise from the kept type. */
		NSMutableDictionary *names = [NSMutableDictionary dictionary];
		NSMutableArray *required = [NSMutableArray array];
		for (ORMCDProperty *property in [written properties]) {
			if (property.source != nil && [traces containsObject:property.source]
			    && [mapping.nameOverrides objectForKey:property.source] == nil) {
				[names setObject:property.name forKey:property.source];
			}
			if (property.source != nil && [traces containsObject:property.source] && !property.optional) {
				[required addObject:property.source];
			}
		}
		/* What it joins to: the member that holds the kept type's value,
		 * where an earlier merge put it in one; else the hub. */
		NSString *via = nil;
		NSArray *members = [mapping.joins objectForKey:kept.identifier];
		for (ORMJoinMember *member in members) {
			if (member != [members firstObject] && [member.heldRoleIds containsObject:keptRoleId]) {
				via = member.identifier;
			}
		}
		[places addObject:@[ mapping, ORMEntityNameIn(mapped, kept), ORMEntityNameIn(mapped, absorbed), names, required,
		                     @(looseValue), valueName ?: [NSNull null], via ?: [NSNull null] ]];
	}
	BOOL preferred = ORMIdentifies(kept, keptFar);
	ORMObjectType *valueTypeGone = absorbedFar.player;
	__block NSString *failed = nil;
	BOOL done = [_editor group:@"Merge Entity Types" trying:^BOOL {
		NSString *step = nil;
		/* Identified by another value: that one a plain fact type, to go
		 * with the rest. */
		if (absorbed.referenceModeFactType != nil && absorbed.referenceModeFactType != matched
		    && ![self->_editor.objectTypeEditor setReferenceMode:nil kind:ORMReferenceModeNone ofEntity:absorbed.identifier
		                                                  reason:&step]) {
			failed = step;
			return NO;
		}
		if (!keptFar.isUnique && ![self->_editor.constraintEditor setUnique:YES role:keptFar.identifier reason:&step]) {
			failed = step;
			return NO;
		}
		for (NSString *roleId in moved) {
			/* Not every one of the kept type has what the absorbed one had
			 * to: its rows in the member do (Required, below). */
			ORMRole *role = [self->_editor.model elementWithId:roleId];
			if (role.isMandatory) {
				[self->_editor.constraintEditor setMandatory:NO role:roleId reason:NULL];
			}
			if (![self->_editor.factTypeEditor setPlayer:kept.identifier ofRole:roleId reason:&step]) {
				failed = step;
				return NO;
			}
		}
		NSMutableArray *gone = [NSMutableArray arrayWithObjects:matched.identifier, absorbed.identifier, nil];
		ORMObjectType *value = [self->_editor.model elementWithId:valueTypeGone.identifier];
		NSUInteger others = 0;
		for (ORMRole *role in value.playedRoles) {
			others += role.factType.identifier != nil && ![role.factType.identifier isEqualToString:matched.identifier];
		}
		if (value != nil && others == 0) {
			[gone addObject:value.identifier];
		}
		[self->_editor.elementEditor deleteElements:gone];
		/* The mappings: the kept type joined, the absorbed one's entity a
		 * member of it. */
		ORMMappingEditor *mappingEditor = [[ORMMappingEditor alloc] initWithEditor:self->_editor];
		ORMRole *now = [self->_editor.model elementWithId:keptRoleId];
		NSString *by = nil;
		if (!preferred) {
			for (ORMConstraint *constraint in now.constraints) {
				if (constraint.kind == ORMUniquenessConstraint && [[constraint allRoles] count] == 1) {
					by = constraint.identifier;
				}
			}
		}
		for (NSArray *place in places) {
			ORMCoreDataMapping *mapping = [place firstObject];
			if ([[mapping.joins objectForKey:kept.identifier] count] == 0) {
				[mappingEditor addMemberNamed:[place objectAtIndex:1] by:nil via:nil outer:NO ofObjectType:kept.identifier
				                    inMapping:mapping.identifier];
			}
			NSString *via = [place objectAtIndex:7] != [NSNull null] ? [place objectAtIndex:7] : nil;
			NSString *member = [mappingEditor addMemberNamed:[place objectAtIndex:2] by:by via:via outer:YES
			                                    ofObjectType:kept.identifier inMapping:mapping.identifier];
			for (NSString *trace in traces) {
				[mappingEditor setHeld:YES role:trace byMember:member inMapping:mapping.identifier];
			}
			for (NSString *trace in [place objectAtIndex:4]) {
				[mappingEditor setRequired:YES role:trace byMember:member inMapping:mapping.identifier];
			}
			[mappingEditor setCorrelationOptional:[[place objectAtIndex:5] boolValue] ofMember:member
			                            inMapping:mapping.identifier];
			NSDictionary *names = [place objectAtIndex:3];
			for (NSString *source in names) {
				[mappingEditor setName:[names objectForKey:source] forSource:source inMapping:mapping.identifier];
			}
			if ([place objectAtIndex:6] != [NSNull null]) {
				[mappingEditor setName:[place objectAtIndex:6] forSource:[member stringByAppendingFormat:@"/%@", keptRoleId]
				             inMapping:mapping.identifier];
			}
			[mappingEditor setName:nil forSource:absorbed.identifier inMapping:mapping.identifier];
		}
		return YES;
	}];
	if (!done && reason != NULL) {
		*reason = failed ?: @"The entity types could not be merged.";
	}
	return done;
}

@end
