/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMConstraintQueries.h"
#import "ORMLogic.h"

/* A fact of a sequence's relation: its fact type, each role's variable
 * (by key) or constant, and whether it is under "not". */
@interface ORMRuleAtom : NSObject
@property (nonatomic, strong) ORMFactType *factType;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *variables;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *constants;
@property (nonatomic) BOOL negated;
@property (nonatomic) BOOL used;
@end

@implementation ORMRuleAtom
@end

/* A query being made: its atoms, its variables' object types, and what
 * stands for each variable so far. */
@interface ORMRuleDraft : NSObject
@property (nonatomic, strong) NSMutableArray<ORMRuleAtom *> *atoms;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ORMObjectType *> *types;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *nodes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *labels;
@property (nonatomic, copy) NSString *queryId;
@end

@implementation ORMRuleDraft
@end

/* The operator that breaks a value comparison: "LessThanOrEqual" broken
 * by ">". */
static NSString *
ORMBrokenBy(NSString *comparison)
{
	NSDictionary *broken = @{ @"LessThan": @">=", @"LessThanOrEqual": @">", @"GreaterThan": @"<=",
		                      @"GreaterThanOrEqual": @"<", @"Equal": @"<>", @"NotEqual": @"=" };
	return [broken objectForKey:comparison ?: @""];
}

/* The subtype fact types from the supertype down to the type, each to
 * the next; nil where the type is none of the supertype's. */
static NSArray<ORMFactType *> *
ORMSubtypePath(ORMObjectType *from, ORMObjectType *to)
{
	if (from == to) {
		return @[];
	}
	for (ORMFactType *fact in to.supertypeFacts) {
		for (ORMRole *role in fact.roles) {
			NSArray *above = role.isSupertypeMetaRole ? ORMSubtypePath(from, role.player) : nil;
			if (above != nil) {
				return [above arrayByAddingObject:fact];
			}
		}
	}
	return nil;
}

@implementation ORMConstraintQueries
{
	NSUInteger _variableCount;
	NSUInteger _labelCount;
}

@synthesize editor = _editor;

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

#pragma mark Relations as atoms

/* The formula's facts, its conjunction flattened, into facts: NO where it
 * says more than facts and their conjunction. */
static BOOL
ORMCollectFacts(ORMFormula *formula, NSMutableArray<ORMFormula *> *facts)
{
	if (formula.kind == ORMFormulaAnd) {
		for (ORMFormula *child in formula.children) {
			if (!ORMCollectFacts(child, facts)) {
				return NO;
			}
		}
		return YES;
	}
	if (formula.kind != ORMFormulaFact || formula.isOptional) {
		return NO;
	}
	[facts addObject:formula];
	return YES;
}

/* The variable that stands for the variable: a subtype fact's two are one
 * object, so one of them stands for both. */
static ORMVariable *
ORMStandIn(NSMapTable *same, ORMVariable *variable)
{
	ORMVariable *at = variable;
	for (ORMVariable *next = [same objectForKey:at]; next != nil && next != at; next = [same objectForKey:at]) {
		at = next;
	}
	return at;
}

/* The sequence's relation into the draft's atoms, its columns the keys
 * given (or new ones): the keys of its columns, nil where it is not facts.
 * A subtype fact is no step: its subtype's variable and its supertype's
 * are one object, of the subtype, stepped down to where needed. */
- (NSArray<NSString *> *)addSequence:(ORMRoleSequence *)sequence
                             columns:(NSArray<NSString *> *)columns
                             negated:(BOOL)negated
                               draft:(ORMRuleDraft *)draft
{
	ORMRelation *relation = [ORMLogic relationForSequence:sequence];
	NSMutableArray<ORMFormula *> *facts = [NSMutableArray array];
	if (relation == nil || relation.isIncomplete || !ORMCollectFacts(relation.formula, facts)) {
		return nil;
	}
	NSMapTable *same = [NSMapTable strongToStrongObjectsMapTable];
	for (ORMFormula *fact in facts) {
		if (fact.factType.kind != ORMFactTypeSubtype) {
			continue;
		}
		NSArray *terms = [fact.terms allValues];
		ORMTerm *first = [terms firstObject];
		ORMTerm *last = [terms lastObject];
		ORMVariable *a = [terms count] == 2 && first.variable != nil ? ORMStandIn(same, first.variable) : nil;
		ORMVariable *b = [terms count] == 2 && last.variable != nil ? ORMStandIn(same, last.variable) : nil;
		if (a == nil || b == nil) {
			return nil;
		}
		if (a != b) {
			/* The subtype's stands for both. */
			BOOL aBelow = [a.objectType isSubtypeOf:b.objectType];
			[same setObject:aBelow ? a : b forKey:aBelow ? b : a];
		}
	}
	NSMapTable *keys = [NSMapTable strongToStrongObjectsMapTable];
	NSMutableArray *columnKeys = [NSMutableArray array];
	for (NSUInteger i = 0; i < [relation.columns count]; i++) {
		ORMVariable *column = ORMStandIn(same, [relation.columns objectAtIndex:i]);
		NSString *key = i < [columns count] ? [columns objectAtIndex:i] : [keys objectForKey:column];
		if (key == nil) {
			key = [NSString stringWithFormat:@"v%lu", (unsigned long)++_variableCount];
		}
		[keys setObject:key forKey:column];
		[columnKeys addObject:key];
		[self note:column.objectType as:key in:draft];
	}
	for (ORMFormula *fact in facts) {
		if (fact.factType.kind == ORMFactTypeSubtype) {
			continue;
		}
		ORMRuleAtom *atom = [[ORMRuleAtom alloc] init];
		atom.factType = fact.factType;
		atom.negated = negated;
		NSMutableDictionary *variables = [NSMutableDictionary dictionary];
		NSMutableDictionary *constants = [NSMutableDictionary dictionary];
		for (NSString *roleId in fact.terms) {
			ORMTerm *term = [fact.terms objectForKey:roleId];
			if (term.variable != nil) {
				ORMVariable *variable = ORMStandIn(same, term.variable);
				NSString *key = [keys objectForKey:variable];
				if (key == nil) {
					key = [NSString stringWithFormat:@"v%lu", (unsigned long)++_variableCount];
					[keys setObject:key forKey:variable];
				}
				[variables setObject:key forKey:roleId];
				[self note:variable.objectType as:key in:draft];
			} else if (term.constant != nil) {
				[constants setObject:term.constant forKey:roleId];
			} else {
				return nil;
			}
		}
		atom.variables = variables;
		atom.constants = constants;
		[draft.atoms addObject:atom];
	}
	return columnKeys;
}

/* The variable's type: the most specific it is met as. */
- (void)note:(ORMObjectType *)type as:(NSString *)key in:(ORMRuleDraft *)draft
{
	ORMObjectType *known = [draft.types objectForKey:key];
	if (type != nil && (known == nil || [type isSubtypeOf:known])) {
		[draft.types setObject:type forKey:key];
	}
}

#pragma mark Steps

- (ORMQuery *)queryOf:(ORMRuleDraft *)draft
{
	return [ORMQuery queryWithId:draft.queryId inModel:_editor.model];
}

- (ORMQueryStep *)stepWithId:(NSString *)stepId in:(ORMRuleDraft *)draft
{
	for (ORMQueryNode *node in [[self queryOf:draft] nodes]) {
		for (ORMQueryStep *step in node.steps) {
			if ([step.identifier isEqualToString:stepId]) {
				return step;
			}
		}
	}
	return nil;
}

/* The variable's node is this one too: the first and this labelled the
 * same, so that they are one object. NO where they are of other types. */
- (BOOL)node:(ORMQueryNode *)node is:(NSString *)key in:(ORMRuleDraft *)draft reason:(NSString **)reason
{
	NSString *first = [draft.nodes objectForKey:key];
	if (first == nil) {
		[draft.nodes setObject:node.identifier forKey:key];
		return YES;
	}
	ORMQueryNode *earlier = nil;
	for (ORMQueryNode *each in [[self queryOf:draft] nodes]) {
		earlier = [each.identifier isEqualToString:first] ? each : earlier;
	}
	if (earlier.objectType != node.objectType) {
		*reason = [NSString stringWithFormat:@"%@ and %@ would have to be one object", earlier.objectType.name,
		                                     node.objectType.name];
		return NO;
	}
	NSString *label = [draft.labels objectForKey:key];
	if (label == nil) {
		label = [NSString stringWithFormat:@"%lu", (unsigned long)++_labelCount];
		[draft.labels setObject:label forKey:key];
		[[[ORMQueryEditor alloc] initWithEditor:_editor] setLabel:label ofNode:first];
	}
	[[[ORMQueryEditor alloc] initWithEditor:_editor] setLabel:label ofNode:node.identifier];
	return YES;
}

/* Steps from the node, the variable's, through each atom of that kind
 * not used yet that the variable plays a role in; on from each new node.
 * The first under not is a not step, the rest under it. NO, and why, where
 * a step cannot be made. */
- (BOOL)stepFrom:(NSString *)nodeId
        variable:(NSString *)key
         negated:(BOOL)negated
           first:(BOOL)first
           draft:(ORMRuleDraft *)draft
          reason:(NSString **)reason
{
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:_editor];
	for (ORMRuleAtom *atom in draft.atoms) {
		if (atom.used || atom.negated != negated) {
			continue;
		}
		NSString *entry = nil;
		for (NSString *roleId in atom.variables) {
			if ([[atom.variables objectForKey:roleId] isEqualToString:key]) {
				entry = roleId;
				break;
			}
		}
		if (entry == nil) {
			continue;
		}
		atom.used = YES;
		NSString *stepId = [queries addStepTo:nodeId through:entry reason:reason];
		if (stepId == nil) {
			return NO;
		}
		if (negated && first) {
			[queries setOperator:ORMQueryNot ofStep:stepId];
		}
		first = NO;
		ORMQueryStep *step = [self stepWithId:stepId in:draft];
		for (ORMQueryNode *stepNode in step.nodes) {
			ORMQueryNode *node = stepNode;
			NSString *roleId = node.role.identifier;
			NSString *constant = [atom.constants objectForKey:roleId];
			NSString *variable = [atom.variables objectForKey:roleId];
			if (constant != nil && ![queries setCondition:@"=" value:constant ofNode:node.identifier reason:reason]) {
				return NO;
			}
			if (variable == nil) {
				continue;
			}
			BOOL seen = [draft.nodes objectForKey:variable] != nil;
			/* A subtype's variable at its supertype's role: down to it. */
			ORMObjectType *type = [draft.types objectForKey:variable];
			for (ORMFactType *fact in ORMSubtypePath(node.objectType, type) ?: @[]) {
				ORMRole *from = nil;
				for (ORMRole *role in fact.roles) {
					from = role.isSupertypeMetaRole ? role : from;
				}
				NSString *down = [queries addStepTo:node.identifier through:from.identifier reason:reason];
				node = down != nil ? [[self stepWithId:down in:draft].nodes firstObject] : nil;
				if (node == nil) {
					return NO;
				}
			}
			if (![self node:node is:variable in:draft reason:reason]) {
				return NO;
			}
			if (!seen && ![self stepFrom:node.identifier variable:variable negated:negated first:NO draft:draft
			                     reason:reason]) {
				return NO;
			}
		}
	}
	return YES;
}

/* The draft as a query from the root's variable: its facts, then those
 * under not from the root. Its id; nil where it cannot be made so. */
- (NSString *)queryNamed:(NSString *)name
                    root:(NSString *)root
                   draft:(ORMRuleDraft *)draft
                 deontic:(BOOL)deontic
                  reason:(NSString **)reason
{
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:_editor];
	ORMObjectType *type = [draft.types objectForKey:root];
	draft.queryId = type != nil ? [queries addQueryNamed:name from:type.identifier reason:reason] : nil;
	if (draft.queryId == nil) {
		return nil;
	}
	NSString *rootNode = [self queryOf:draft].root.identifier;
	[draft.nodes setObject:rootNode forKey:root];
	[queries setProjected:YES ofNode:rootNode];
	if (![queries setKind:ORMQueryConstraint ofQuery:draft.queryId reason:reason]
	    || (deontic && ![queries setDeontic:YES ofQuery:draft.queryId reason:reason])
	    || ![self stepFrom:rootNode variable:root negated:NO first:YES draft:draft reason:reason]
	    || ![self stepFrom:rootNode variable:root negated:YES first:YES draft:draft reason:reason]) {
		return nil;
	}
	for (ORMRuleAtom *atom in draft.atoms) {
		if (!atom.used) {
			*reason = [NSString stringWithFormat:@"\"%@\" is not reached from %@ by its own facts",
			                                     [atom.factType displayText], type.name];
			return nil;
		}
	}
	return draft.queryId;
}

/* The variable to read from: a column under not only through one fact,
 * so that one not step holds them; else the first entity's column. */
- (NSString *)rootOf:(ORMRuleDraft *)draft columns:(NSArray<NSString *> *)columns
{
	BOOL negated = NO;
	for (ORMRuleAtom *atom in draft.atoms) {
		negated = negated || atom.negated;
	}
	NSString *fallback = nil;
	for (NSString *key in columns) {
		NSUInteger under = 0;
		for (ORMRuleAtom *atom in draft.atoms) {
			under += atom.negated && [[atom.variables allValues] containsObject:key] ? 1 : 0;
		}
		ORMObjectType *type = [draft.types objectForKey:key];
		BOOL readable = _readable == nil || [_readable containsObject:type.identifier ?: @""];
		if (readable && (negated ? under == 1 : type.isEntity)) {
			return key;
		}
		fallback = fallback ?: (negated || !readable ? nil : key);
	}
	return fallback;
}

- (ORMRuleDraft *)newDraft
{
	ORMRuleDraft *draft = [[ORMRuleDraft alloc] init];
	draft.atoms = [NSMutableArray array];
	draft.types = [NSMutableDictionary dictionary];
	draft.nodes = [NSMutableDictionary dictionary];
	draft.labels = [NSMutableDictionary dictionary];
	return draft;
}

#pragma mark The kinds

/* The first sequence's facts, the second's under not (or both, for an
 * exclusion), their columns the same. */
- (NSString *)queryNamed:(NSString *)name
                    over:(ORMRoleSequence *)first
                     and:(ORMRoleSequence *)second
             secondUnder:(BOOL)negated
                 deontic:(BOOL)deontic
                  reason:(NSString **)reason
{
	ORMRuleDraft *draft = [self newDraft];
	NSArray *columns = [self addSequence:first columns:nil negated:NO draft:draft];
	if (columns == nil || [self addSequence:second columns:columns negated:negated draft:draft] == nil) {
		*reason = @"a sequence is not its facts alone";
		return nil;
	}
	NSString *root = [self rootOf:draft columns:columns];
	if (root == nil) {
		*reason = @"no column reaches the second sequence's facts by one of them";
		return nil;
	}
	return [self queryNamed:name root:root draft:draft deontic:deontic reason:reason];
}

/* The two values and what they are of, compared the way that breaks it. */
- (NSString *)comparisonQuery:(ORMConstraint *)constraint reason:(NSString **)reason
{
	NSString *broken = ORMBrokenBy(constraint.comparisonOperator);
	ORMRuleDraft *draft = [self newDraft];
	NSArray *columns = [constraint.roleSequences count] == 1
		? [self addSequence:[constraint.roleSequences firstObject] columns:nil negated:NO draft:draft] : nil;
	if (broken == nil || [columns count] != 2) {
		*reason = @"it compares no two values of a sequence of its facts";
		return nil;
	}
	/* From what the values are of: a variable that is no column. */
	NSString *root = nil;
	for (ORMRuleAtom *atom in draft.atoms) {
		for (NSString *key in [atom.variables allValues]) {
			root = root ?: ([columns containsObject:key] ? nil : key);
		}
	}
	NSString *made = [self queryNamed:constraint.name ?: @"Comparison" root:root ?: [columns firstObject] draft:draft
	                          deontic:constraint.modality == ORMDeontic
	                           reason:reason];
	if (made == nil) {
		return nil;
	}
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:_editor];
	/* Labelled apart, so that the outline says which is which. */
	for (NSString *key in columns) {
		if ([draft.labels objectForKey:key] == nil) {
			NSString *label = [NSString stringWithFormat:@"%lu", (unsigned long)++_labelCount];
			[draft.labels setObject:label forKey:key];
			[queries setLabel:label ofNode:[draft.nodes objectForKey:key]];
		}
	}
	if (![queries setCondition:broken toNode:[draft.nodes objectForKey:[columns lastObject]]
	                    ofNode:[draft.nodes objectForKey:[columns firstObject]] reason:reason]) {
		return nil;
	}
	return made;
}

/* An inclusive-or: an object of the roles' player playing none of them. */
- (NSString *)noneOf:(ORMConstraint *)constraint reason:(NSString **)reason
{
	NSArray *roles = [constraint allRoles];
	ORMObjectType *player = nil;
	for (ORMRole *role in roles) {
		player = player == nil || [role.player isSubtypeOf:player] ? role.player : player;
	}
	if (player == nil || [roles count] < 2) {
		*reason = @"it is no inclusive-or of roles";
		return nil;
	}
	ORMQueryEditor *queries = [[ORMQueryEditor alloc] initWithEditor:_editor];
	NSString *queryId = [queries addQueryNamed:constraint.name ?: @"Constraint" from:player.identifier reason:reason];
	if (queryId == nil || ![queries setKind:ORMQueryConstraint ofQuery:queryId reason:reason]
	    || (constraint.modality == ORMDeontic && ![queries setDeontic:YES ofQuery:queryId reason:reason])) {
		return nil;
	}
	NSString *root = [ORMQuery queryWithId:queryId inModel:_editor.model].root.identifier;
	[queries setProjected:YES ofNode:root];
	for (ORMRole *role in roles) {
		NSString *step = [queries addStepTo:root through:role.identifier reason:reason];
		if (step == nil) {
			return nil;
		}
		[queries setOperator:ORMQueryNot ofStep:step];
	}
	return queryId;
}

- (NSArray<NSString *> *)queriesFor:(ORMConstraint *)constraint reason:(NSString **)reason
{
	NSString *why = nil;
	NSMutableArray *made = [NSMutableArray array];
	NSString *name = constraint.name ?: @"Constraint";
	BOOL deontic = constraint.modality == ORMDeontic;
	NSArray *sequences = constraint.roleSequences;
	switch (constraint.kind) {
	case ORMSubsetConstraint:
	case ORMEqualityConstraint:
		for (NSUInteger i = 0; i + 1 < [sequences count] && why == nil; i++) {
			NSString *subset = [self queryNamed:name over:[sequences objectAtIndex:i] and:[sequences objectAtIndex:i + 1]
			                        secondUnder:YES deontic:deontic reason:&why];
			NSString *back = constraint.kind == ORMEqualityConstraint && subset != nil
				? [self queryNamed:name over:[sequences objectAtIndex:i + 1] and:[sequences objectAtIndex:i]
				       secondUnder:YES deontic:deontic reason:&why]
				: subset;
			if (subset != nil && back != nil) {
				[made addObject:subset];
				if (back != subset) {
					[made addObject:back];
				}
			}
		}
		break;
	case ORMExclusionConstraint:
		for (NSUInteger i = 0; i < [sequences count] && why == nil; i++) {
			for (NSUInteger j = i + 1; j < [sequences count] && why == nil; j++) {
				NSString *both = [self queryNamed:name over:[sequences objectAtIndex:i] and:[sequences objectAtIndex:j]
				                      secondUnder:NO deontic:deontic reason:&why];
				if (both != nil) {
					[made addObject:both];
				}
			}
		}
		break;
	case ORMMandatoryConstraint: {
		NSString *none = [self noneOf:constraint reason:&why];
		if (none != nil) {
			[made addObject:none];
		}
		break;
	}
	case ORMValueComparisonConstraint: {
		NSString *compared = [self comparisonQuery:constraint reason:&why];
		if (compared != nil) {
			[made addObject:compared];
		}
		break;
	}
	default:
		why = @"no rule says it yet";
		break;
	}
	if (why != nil || [made count] == 0) {
		if (reason != NULL) {
			*reason = why ?: @"no rule says it";
		}
		return nil;
	}
	return made;
}

@end
