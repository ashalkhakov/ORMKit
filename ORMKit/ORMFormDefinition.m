/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFormDefinition.h"
#import "ORMModelPriv.h"
#import "ORMQueryPlanner.h"
#import "ORMQueryExpression.h"

@interface ORMFormProblem ()
@property (nonatomic, readwrite, copy) NSString *rule;
@property (nonatomic, readwrite, copy) NSString *partId;
@property (nonatomic, readwrite, copy) NSString *text;
@end

@implementation ORMFormProblem
@end

@interface ORMQuery (ORMFormDefinition)
+ (ORMQuery *)queryOf:(ORMStoredQuery *)stored model:(ORMModel *)model;
+ (ORMStoredQuery *)expansionOf:(ORMStoredQuery *)stored model:(ORMModel *)model notes:(NSMutableArray<NSString *> *)notes;
@end

/* What a node's steps are beneath: what the form makes or changes (the
 * anchor, an owned object, a part of either, a repeat's row), a choice, or
 * an object it only refers to. */
typedef NS_ENUM(NSInteger, ORMFormRegion) {
	ORMFormRegionOwn,
	ORMFormRegionChoice,
	ORMFormRegionReferred,
};

@implementation ORMFormDefinition
{
	ORMModel *_model;
	ORMQueryPlanner *_planner;
	ORMStoredQuery *_stored;
	NSMutableDictionary<NSString *, NSNumber *> *_places;
	NSMutableDictionary<NSString *, NSString *> *_rules;
	/* Why a rule is broken, said after the node: "under Vehicle, ...". */
	NSMutableDictionary<NSString *, NSString *> *_why;
	/* The choice each node is beneath, by its id. */
	NSMutableDictionary<NSString *, ORMQueryNode *> *_choices;
	NSMutableSet<NSString *> *_identifying;
	NSMutableSet<NSString *> *_repeats;
	NSMutableSet<NSString *> *_lists;
	/* The nodes a value node computes with. */
	NSMutableSet<NSString *> *_operands;
	NSMutableArray<ORMFormProblem *> *_problems;
}

+ (instancetype)definitionOfForm:(ORMQuery *)form model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	if (form.kind != ORMQueryForm || form.root == nil) {
		return nil;
	}
	ORMFormDefinition *definition = [[ORMFormDefinition alloc] init];
	[definition define:form model:model mapping:mapping];
	return definition;
}

- (void)define:(ORMQuery *)form model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	_form = form;
	_model = model;
	_planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:mapping];
	for (ORMStoredQuery *each in model.storedQueries) {
		_stored = [each.identifier isEqualToString:form.identifier] ? each : _stored;
	}
	_places = [NSMutableDictionary dictionary];
	_rules = [NSMutableDictionary dictionary];
	_why = [NSMutableDictionary dictionary];
	_choices = [NSMutableDictionary dictionary];
	_identifying = [NSMutableSet set];
	_repeats = [NSMutableSet set];
	_lists = [NSMutableSet set];
	_operands = [NSMutableSet set];
	_problems = [NSMutableArray array];
	for (ORMQueryNode *node in [form nodes]) {
		if (node.isValue) {
			[_operands addObjectsFromArray:[node.expression nodeIds]];
		}
	}
	[_places setObject:@(ORMFormPlaceAnchor) forKey:form.root.identifier];
	[_rules setObject:@"D1" forKey:form.root.identifier];
	[self visit:form.root region:ORMFormRegionOwn choice:nil many:NO];
	[self identifyChoices];
	[self defineValues];
	[self findUnplaced];
	[self collectProblems];
}

#pragma mark Places

- (BOOL)isToMany:(ORMQueryStep *)step
{
	return ![step isSubtyping] && ![step.factType isUnary] && !step.entryRole.isUnique;
}

/* An entity the mapping makes an entity of; else a value, absorbed where it
 * has parts or is an entity type kept in its owner's row. */
- (ORMFormPlace)placeOfType:(ORMQueryNode *)node
{
	ORMObjectType *type = node.objectType;
	if (node.isValue) {
		return ORMFormPlaceComputed;
	}
	if ([ORMQuery partRolesOf:type] != nil) {
		return ORMFormPlaceAbsorbed;
	}
	if (type.isEntity) {
		return [_planner entityNameOfType:type] != nil ? ORMFormPlaceReferenced : ORMFormPlaceAbsorbed;
	}
	return ORMFormPlaceValue;
}

- (ORMFormPlace)placeOfNode:(ORMQueryNode *)node
{
	NSNumber *place = [_places objectForKey:node.identifier ?: @""];
	return place != nil ? (ORMFormPlace)[place integerValue] : [self placeOfType:node];
}

static BOOL
ORMIsMarked(ORMQueryNode *node)
{
	return node.formPart != ORMFormPartNone || node.isGiven;
}

static BOOL ORMMarkedBeneath(ORMQueryNode *node);

/* Something beneath the step or node marked: a node entered, shown or
 * given, a unary marked, or (marked YES) a node a value computes with. */
- (BOOL)marksBeneathStep:(ORMQueryStep *)step entered:(BOOL)entered
{
	if ([step.factType isUnary]) {
		return entered ? step.formPart == ORMFormPartEntered : step.formPart != ORMFormPartNone;
	}
	for (ORMQueryNode *node in step.nodes) {
		if ([self marksAt:node entered:entered]) {
			return YES;
		}
	}
	return NO;
}

- (BOOL)marksAt:(ORMQueryNode *)node entered:(BOOL)entered
{
	if (entered ? node.formPart == ORMFormPartEntered : (ORMIsMarked(node) || [_operands containsObject:node.identifier])) {
		return YES;
	}
	for (ORMQueryStep *step in node.steps) {
		if ([self marksBeneathStep:step entered:entered]) {
			return YES;
		}
	}
	return NO;
}

#pragma mark Rules

- (void)rule:(NSString *)rule of:(NSString *)partId why:(NSString *)why
{
	[_rules setObject:rule forKey:partId];
	if (why != nil) {
		[_why setObject:why forKey:partId];
	}
}

/* Each step from the node and what it reaches, in the region the node's
 * steps are in: beneath the choice, if any; many, past a step to many. */
- (void)visit:(ORMQueryNode *)node region:(ORMFormRegion)region choice:(ORMQueryNode *)choice many:(BOOL)many
{
	for (ORMQueryStep *step in node.steps) {
		if ([step.factType isUnary]) {
			[self unary:step region:region choice:choice];
			continue;
		}
		BOOL toMany = [self isToMany:step];
		BOOL entered = [self marksBeneathStep:step entered:YES];
		BOOL marked = [self marksBeneathStep:step entered:NO];
		ORMFormRegion beneath = region;
		if (toMany && marked) {
			if (entered && region == ORMFormRegionOwn) {
				/* D8: rows the form writes, each item made, changed or deleted. */
				[_repeats addObject:step.identifier];
				[self rule:@"D8" of:step.identifier why:nil];
			} else if (!entered) {
				/* D9: rows read, never written. */
				[_lists addObject:step.identifier];
				[self rule:@"D9" of:step.identifier why:nil];
				beneath = region == ORMFormRegionChoice ? region : ORMFormRegionReferred;
			} else {
				beneath = region == ORMFormRegionChoice ? region : ORMFormRegionReferred;
			}
		}
		for (ORMQueryNode *child in step.nodes) {
			[self node:child step:step region:beneath choice:choice many:many || toMany above:node];
		}
	}
}

/* D10: a flag on what the form makes or changes; shown, read anywhere; a
 * unary unmarked a condition on a choice. */
- (void)unary:(ORMQueryStep *)step region:(ORMFormRegion)region choice:(ORMQueryNode *)choice
{
	if (step.formPart == ORMFormPartEntered) {
		if (region == ORMFormRegionOwn) {
			[self rule:@"D10" of:step.identifier why:nil];
		} else {
			[self rule:@"E2" of:step.identifier
			       why:[NSString stringWithFormat:@"entered on %@, an object the form refers to and does not make or change",
			                                      [step.parent designation]]];
		}
	} else if (step.formPart == ORMFormPartShown) {
		[self rule:region == ORMFormRegionOwn ? @"D10" : @"D7" of:step.identifier why:nil];
	} else if (region == ORMFormRegionChoice) {
		[self rule:@"D5" of:step.identifier why:nil];
	} else {
		[self rule:@"E6" of:step.identifier why:@"neither entered nor shown, and no condition on a choice"];
	}
}

- (void)node:(ORMQueryNode *)child
        step:(ORMQueryStep *)step
      region:(ORMFormRegion)region
      choice:(ORMQueryNode *)choice
        many:(BOOL)many
       above:(ORMQueryNode *)above
{
	if (choice != nil) {
		[_choices setObject:choice forKey:child.identifier];
	}
	ORMFormPlace place = [step isSubtyping] ? ORMFormPlacePart : [self placeOfType:child];
	BOOL entity = place == ORMFormPlaceReferenced;
	BOOL entered = child.formPart == ORMFormPartEntered;
	if (entity && region == ORMFormRegionOwn && !ORMIsMarked(child) && [self marksAt:child entered:YES]) {
		place = ORMFormPlaceOwned;
	}
	[_places setObject:@(place) forKey:child.identifier];
	ORMFormRegion beneath = region;
	ORMQueryNode *beneathChoice = choice;
	if (place == ORMFormPlaceReferenced && region != ORMFormRegionChoice) {
		/* A choice's steps are its conditions, its identification and its
		 * reads; any other referenced object's, reads. */
		beneath = entered && region == ORMFormRegionOwn ? ORMFormRegionChoice : ORMFormRegionReferred;
		beneathChoice = beneath == ORMFormRegionChoice ? child : nil;
	}
	if (place == ORMFormPlacePart) {
		[self rule:@"D12" of:child.identifier why:nil];
	} else if (child.isGiven) {
		if (many) {
			[self rule:@"E3" of:child.identifier why:@"given beneath a step to many: a parameter is one value, not one per row"];
		} else {
			[self rule:@"D2" of:child.identifier why:nil];
		}
	} else if (entered) {
		if (region == ORMFormRegionOwn) {
			[self rule:entity ? @"D4" : place == ORMFormPlaceAbsorbed ? @"D11" : @"D3" of:child.identifier why:nil];
		} else if (region == ORMFormRegionChoice && above == choice && !entity && ![self isToMany:step]) {
			/* D6 or E1, once the choice's entered values are all known. */
			[_identifying addObject:child.identifier];
		} else if (region == ORMFormRegionChoice) {
			[self rule:@"E1" of:child.identifier
			       why:[NSString stringWithFormat:@"entered beneath %@, the object chosen, but none of its own values: "
			                                      @"it identifies no %@", [choice designation], choice.objectType.name]];
		} else {
			[self rule:@"E2" of:child.identifier
			       why:[NSString stringWithFormat:@"entered beneath %@, an object the form refers to and does not make or change",
			                                      [[self referencedAbove:child] designation]]];
		}
	} else if (child.formPart == ORMFormPartShown) {
		[self rule:place == ORMFormPlaceAbsorbed ? @"D11" : @"D7" of:child.identifier why:nil];
	} else if (place == ORMFormPlaceOwned || [self marksAt:child entered:NO]) {
		[self rule:@"path" of:child.identifier why:nil];
	} else if (region == ORMFormRegionChoice) {
		[self rule:@"D5" of:child.identifier why:nil];
	} else {
		[self rule:@"E6" of:child.identifier
		       why:@"neither entered, shown nor given, leading to nothing that is, and no condition on a choice"];
	}
	[self visit:child region:beneath choice:beneathChoice many:many];
}

/* The nearest object above the node the form only refers to. */
- (ORMQueryNode *)referencedAbove:(ORMQueryNode *)node
{
	for (ORMQueryNode *each = node.step.parent; each != nil; each = each.step.parent) {
		if ([self placeOfNode:each] == ORMFormPlaceReferenced) {
			return each;
		}
	}
	return node.step.parent;
}

/* D6: a choice's entered values, exactly the roles of one of its
 * uniqueness constraints (its reference scheme or another), identify it;
 * else E1: a set of objects at best. */
- (void)identifyChoices
{
	NSMutableDictionary<NSString *, NSMutableArray<ORMQueryNode *> *> *byChoice = [NSMutableDictionary dictionary];
	for (ORMQueryNode *node in [_form nodes]) {
		if ([_identifying containsObject:node.identifier]) {
			ORMQueryNode *choice = [_choices objectForKey:node.identifier];
			NSMutableArray *values = [byChoice objectForKey:choice.identifier] ?: [NSMutableArray array];
			[values addObject:node];
			[byChoice setObject:values forKey:choice.identifier];
		}
	}
	for (NSString *choiceId in byChoice) {
		NSArray<ORMQueryNode *> *values = [byChoice objectForKey:choiceId];
		NSMutableSet *roles = [NSMutableSet set];
		for (ORMQueryNode *value in values) {
			[roles addObject:value.role.identifier ?: @""];
		}
		BOOL identifies = NO;
		for (ORMQueryNode *value in values) {
			for (ORMConstraint *constraint in value.role.constraints) {
				if (constraint.kind == ORMUniquenessConstraint
				    && [[NSSet setWithArray:[[constraint allRoles] valueForKey:@"identifier"]] isEqualToSet:roles]) {
					identifies = YES;
				}
			}
		}
		ORMQueryNode *choice = [_choices objectForKey:[[values firstObject] identifier]];
		for (ORMQueryNode *value in values) {
			if (identifies) {
				[self rule:@"D6" of:value.identifier why:nil];
			} else {
				[self rule:@"E1" of:value.identifier
				       why:[NSString stringWithFormat:@"entered beneath %@, the object chosen, but not exactly the values of "
				                                      @"one of its uniqueness constraints: they identify a set of %@ at best, "
				                                      @"not one",
				                                      [choice designation], choice.objectType.name]];
				[_identifying removeObject:value.identifier];
			}
		}
	}
}

#pragma mark Values

/* The row a node is in: the nearest node at or above it reached by a step
 * to many, else the anchor. */
- (ORMQueryNode *)rowOf:(ORMQueryNode *)node
{
	ORMQueryNode *each = node.isValue ? node.valueOf : node;
	for (; each != nil && each.step != nil; each = each.step.parent) {
		if ([self isToMany:each.step]) {
			return each;
		}
	}
	return _form.root;
}

static BOOL
ORMIsAtOrAbove(ORMQueryNode *above, ORMQueryNode *node)
{
	for (ORMQueryNode *each = node; each != nil; each = each.isValue ? each.valueOf : each.step.parent) {
		if (each == above) {
			return YES;
		}
	}
	return NO;
}

/* D13: computed from its own row and those above; D14: an aggregate over
 * rows beneath; E4 one of many without an aggregate; E5 a choice's
 * condition, which is not read. */
- (void)defineValues
{
	for (ORMQueryNode *value in [_form nodes]) {
		if (!value.isValue) {
			continue;
		}
		[_places setObject:@(ORMFormPlaceComputed) forKey:value.identifier];
		ORMQueryNode *row = [self rowOf:value];
		BOOL aggregate = value.expression.kind == ORMQueryExpressionAggregate;
		NSString *rule = aggregate ? @"D14" : @"D13", *why = nil;
		for (NSString *operandId in [value.expression nodeIds]) {
			ORMQueryNode *operand = nil;
			for (ORMQueryNode *each in [_form nodes]) {
				operand = [each.identifier isEqualToString:operandId] ? each : operand;
			}
			if (operand == nil) {
				continue;
			}
			ORMQueryNode *choice = [_choices objectForKey:operand.identifier];
			if ([self isConditionOfChoice:operand]) {
				rule = @"E5";
				why = [NSString stringWithFormat:@"computed with %@, a condition on the choice %@, which is not read",
				                                 [operand designation], [choice designation]];
				break;
			}
			if (!aggregate && !ORMIsAtOrAbove([self rowOf:operand], row)) {
				rule = @"E4";
				why = [NSString stringWithFormat:@"computed with %@, one of many, outside an aggregate (count, total, avg, max, min)",
				                                 [operand designation]];
				break;
			}
		}
		[self rule:rule of:value.identifier why:why];
	}
}

/* Beneath a choice, unmarked, not its identification, nothing shown on
 * the way down from the choice nor beneath it: one of its conditions (D5),
 * however a value computes with it. */
- (BOOL)isConditionOfChoice:(ORMQueryNode *)node
{
	ORMQueryNode *choice = [_choices objectForKey:node.identifier];
	if (choice == nil || ORMIsMarked(node) || [_identifying containsObject:node.identifier]) {
		return NO;
	}
	for (ORMQueryNode *each = node.step.parent; each != nil && each != choice; each = each.step.parent) {
		if (ORMIsMarked(each)) {
			return NO;
		}
	}
	return !ORMMarkedBeneath(node);
}

/* A node entered, shown or given beneath the node, or a unary marked. */
static BOOL
ORMMarkedBeneath(ORMQueryNode *node)
{
	for (ORMQueryStep *step in node.steps) {
		if ([step.factType isUnary] ? step.formPart != ORMFormPartNone : NO) {
			return YES;
		}
		for (ORMQueryNode *each in step.nodes) {
			if (ORMIsMarked(each) || ORMMarkedBeneath(each)) {
				return YES;
			}
		}
	}
	return NO;
}

#pragma mark E7

/* E7: a node the form has, which a read of its own path cannot place: the
 * mapping keeps it nowhere (no entity, attribute or relationship). */
- (void)findUnplaced
{
	for (ORMQueryNode *node in [_form nodes]) {
		NSString *rule = [_rules objectForKey:node.identifier];
		BOOL kept = ORMIsMarked(node) || [_operands containsObject:node.identifier];
		/* A compound's part (a volume's quantity) is placed with it. */
		ORMQueryNode *placed = node;
		while (placed.step.parent != nil && [self placeOfNode:placed.step.parent] == ORMFormPlaceAbsorbed) {
			placed = placed.step.parent;
		}
		if (node.isValue || node == _form.root || !kept || [rule hasPrefix:@"E"] || [self placesNode:placed]) {
			continue;
		}
		[self rule:@"E7" of:node.identifier
		       why:@"the mapping places it nowhere: no entity, attribute or relationship holds it"];
	}
	for (ORMQueryNode *node in [_form nodes]) {
		for (ORMQueryStep *step in node.steps) {
			NSString *rule = [_rules objectForKey:step.identifier];
			if ([step.factType isUnary] && step.formPart != ORMFormPartNone && ![rule hasPrefix:@"E"]
			    && [_planner attributeOfUnaryStep:step] == nil) {
				[self rule:@"E7" of:step.identifier why:@"the mapping keeps it in no attribute"];
			}
		}
	}
}

/* Whether a read of the anchor and the node, by the steps between them
 * alone, nothing else said of either, has a column for it. */
- (BOOL)placesNode:(ORMQueryNode *)node
{
	if (_stored == nil) {
		return YES;
	}
	ORMStoredQuery *copy = [_stored copy];
	copy.identifier = [_stored.identifier stringByAppendingString:@"-placed"];
	copy.kind = nil;
	ORMQueryPart *target = nil;
	for (ORMQueryPart *part in [copy.root tree]) {
		target = !part.isStep && [part.identifier isEqualToString:node.identifier] ? part : target;
	}
	if (target == nil) {
		return YES;
	}
	NSMutableSet *onPath = [NSMutableSet set];
	for (ORMQueryPart *each = target; each != nil; each = [each parent]) {
		[onPath addObject:[NSValue valueWithNonretainedObject:each]];
	}
	NSMutableArray *off = [NSMutableArray array];
	for (ORMQueryPart *part in [copy.root tree]) {
		BOOL kept = [onPath containsObject:[NSValue valueWithNonretainedObject:part]]
		            || (!part.isStep && [onPath containsObject:[NSValue valueWithNonretainedObject:[part parent]]]);
		if ((part.isStep || part.isValue) && !kept) {
			[off addObject:part];
		}
		part.projected = part == target || part == copy.root ? @"true" : nil;
		part.part = nil;
		part.given = nil;
		part.label = nil;
		part.comparison = nil;
		part.value = nil;
		part.compareTo = nil;
		part.operatorName = nil;
		part.countComparison = nil;
	}
	for (ORMQueryPart *part in off) {
		[part detach];
	}
	NSMutableArray *notes = [NSMutableArray array];
	ORMStoredQuery *expanded = [ORMQuery expansionOf:copy model:_model notes:notes];
	ORMQuery *query = expanded != nil ? [ORMQuery queryOf:expanded model:_model] : nil;
	if (query == nil) {
		return NO;
	}
	return [[_planner planForQuery:query] columnOfNode:node.identifier] != nil;
}

#pragma mark What it says

- (NSString *)ruleOf:(NSString *)partId
{
	return partId != nil ? [_rules objectForKey:partId] : nil;
}

- (void)collectProblems
{
	for (ORMQueryNode *node in [_form nodes]) {
		[self problemAt:node.identifier named:[node designation]];
		for (ORMQueryStep *step in node.steps) {
			if ([step.factType isUnary]) {
				[self problemAt:step.identifier named:[NSString stringWithFormat:@"\"%@\"", [step.factType displayText]]];
			}
		}
	}
}

- (void)problemAt:(NSString *)partId named:(NSString *)name
{
	NSString *rule = [_rules objectForKey:partId];
	if (![rule hasPrefix:@"E"]) {
		return;
	}
	ORMFormProblem *problem = [[ORMFormProblem alloc] init];
	problem.rule = rule;
	problem.partId = partId;
	problem.text = [NSString stringWithFormat:@"%@: %@: %@.", rule, name, [_why objectForKey:partId] ?: @"no form"];
	[_problems addObject:problem];
}

- (NSArray<ORMFormProblem *> *)problems
{
	return [_problems copy];
}

- (NSSet<NSString *> *)problemIds
{
	return [NSSet setWithArray:[_problems valueForKey:@"partId"]];
}

- (ORMQueryNode *)choiceAbove:(ORMQueryNode *)node
{
	return [_choices objectForKey:node.identifier ?: @""];
}

- (BOOL)identifiesChoice:(ORMQueryNode *)node
{
	return [[_rules objectForKey:node.identifier ?: @""] isEqualToString:@"D6"];
}

- (BOOL)isRepeat:(ORMQueryStep *)step
{
	return [_repeats containsObject:step.identifier ?: @""];
}

- (BOOL)isList:(ORMQueryStep *)step
{
	return [_lists containsObject:step.identifier ?: @""];
}

@end
