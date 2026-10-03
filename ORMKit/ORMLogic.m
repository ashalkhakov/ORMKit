/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMLogic.h"

@interface ORMVariable ()
@property (nonatomic, readwrite, weak) ORMObjectType *objectType;
@end

@implementation ORMVariable

+ (instancetype)variableOf:(ORMObjectType *)type
{
	ORMVariable *variable = [[self alloc] init];
	variable.objectType = type;
	return variable;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"%@%@", self.objectType.name ?: @"?",
	        self.ordinal > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)self.ordinal] : @""];
}

@end

@interface ORMTerm ()
@property (nonatomic, readwrite, strong) ORMVariable *variable;
@property (nonatomic, readwrite, copy) NSString *constant;
@property (nonatomic, readwrite, copy) NSString *functionName;
@property (nonatomic, readwrite, copy) NSArray<ORMTerm *> *arguments;
@property (nonatomic, readwrite) BOOL isAggregate;
@end

@implementation ORMTerm

+ (instancetype)termWithVariable:(ORMVariable *)variable
{
	ORMTerm *term = [[self alloc] init];
	term.variable = variable;
	return term;
}

+ (instancetype)termWithConstant:(NSString *)constant
{
	ORMTerm *term = [[self alloc] init];
	term.constant = constant;
	return term;
}

+ (instancetype)termWithFunction:(NSString *)name arguments:(NSArray<ORMTerm *> *)arguments aggregate:(BOOL)aggregate
{
	ORMTerm *term = [[self alloc] init];
	term.functionName = name;
	term.arguments = arguments;
	term.isAggregate = aggregate;
	return term;
}

- (NSString *)description
{
	if (self.variable != nil) {
		return [self.variable description];
	}
	if (self.constant != nil) {
		return self.constant;
	}
	return [NSString stringWithFormat:@"%@(%@)", self.functionName, [self.arguments componentsJoinedByString:@", "]];
}

@end

@interface ORMFormula ()
@property (nonatomic, readwrite) ORMFormulaKind kind;
@property (nonatomic, readwrite, weak) ORMFactType *factType;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, ORMTerm *> *terms;
@property (nonatomic, readwrite) BOOL isOptional;
@property (nonatomic, readwrite, strong) ORMVariable *variable;
@property (nonatomic, readwrite, strong) ORMValueConstraint *values;
@property (nonatomic, readwrite, copy) NSString *comparison;
@property (nonatomic, readwrite, copy) NSArray<ORMTerm *> *operands;
@property (nonatomic, readwrite, copy) NSArray<ORMFormula *> *children;
@end

@implementation ORMFormula

+ (instancetype)fact:(ORMFactType *)factType terms:(NSDictionary<NSString *, ORMTerm *> *)terms
{
	ORMFormula *formula = [[self alloc] init];
	formula.kind = ORMFormulaFact;
	formula.factType = factType;
	formula.terms = terms;
	return formula;
}

+ (instancetype)optionalFact:(ORMFactType *)factType terms:(NSDictionary<NSString *, ORMTerm *> *)terms
{
	ORMFormula *formula = [self fact:factType terms:terms];
	formula.isOptional = YES;
	return formula;
}

+ (instancetype)variable:(ORMVariable *)variable in:(ORMValueConstraint *)values
{
	ORMFormula *formula = [[self alloc] init];
	formula.kind = ORMFormulaValueIn;
	formula.variable = variable;
	formula.values = values;
	return formula;
}

+ (instancetype)compare:(NSString *)comparison operands:(NSArray<ORMTerm *> *)operands
{
	ORMFormula *formula = [[self alloc] init];
	formula.kind = ORMFormulaComparison;
	formula.comparison = comparison;
	formula.operands = operands;
	return formula;
}

+ (instancetype)combine:(ORMFormulaKind)kind children:(NSArray<ORMFormula *> *)children
{
	/* One child needs no and. */
	if ((kind == ORMFormulaAnd || kind == ORMFormulaOr) && [children count] == 1) {
		return [children firstObject];
	}
	ORMFormula *formula = [[self alloc] init];
	formula.kind = kind;
	formula.children = children;
	return formula;
}

+ (instancetype)not:(ORMFormula *)formula
{
	if (formula.kind == ORMFormulaNot) {
		return [formula.children firstObject];
	}
	return [self combine:ORMFormulaNot children:@[ formula ]];
}

- (void)collectFacts:(NSMutableArray *)facts
{
	if (self.kind == ORMFormulaFact) {
		[facts addObject:self];
	}
	for (ORMFormula *child in self.children) {
		[child collectFacts:facts];
	}
}

- (NSArray<ORMFormula *> *)facts
{
	NSMutableArray *facts = [NSMutableArray array];
	[self collectFacts:facts];
	return facts;
}

static void
ORMAddTermVariables(ORMTerm *term, NSMutableArray *variables)
{
	if (term.variable != nil && [variables indexOfObjectIdenticalTo:term.variable] == NSNotFound) {
		[variables addObject:term.variable];
	}
	for (ORMTerm *argument in term.arguments) {
		ORMAddTermVariables(argument, variables);
	}
}

- (void)collectVariables:(NSMutableArray *)variables
{
	switch (self.kind) {
	case ORMFormulaFact:
		for (ORMRole *role in self.factType.roles) {
			ORMTerm *term = [self.terms objectForKey:role.identifier];
			if (term != nil) {
				ORMAddTermVariables(term, variables);
			}
		}
		break;
	case ORMFormulaValueIn:
		if ([variables indexOfObjectIdenticalTo:self.variable] == NSNotFound) {
			[variables addObject:self.variable];
		}
		break;
	case ORMFormulaComparison:
		for (ORMTerm *term in self.operands) {
			ORMAddTermVariables(term, variables);
		}
		break;
	default:
		for (ORMFormula *child in self.children) {
			[child collectVariables:variables];
		}
		break;
	}
}

- (NSArray<ORMVariable *> *)variables
{
	NSMutableArray *variables = [NSMutableArray array];
	[self collectVariables:variables];
	return variables;
}

- (ORMVariable *)variableForRole:(ORMRole *)role
{
	return [[self.terms objectForKey:role.identifier] variable];
}

- (NSString *)description
{
	switch (self.kind) {
	case ORMFormulaFact: {
		NSMutableArray *parts = [NSMutableArray array];
		for (ORMRole *role in [self.factType visibleRoles]) {
			[parts addObject:[[self.terms objectForKey:role.identifier] description] ?: @"_"];
		}
		return [NSString stringWithFormat:@"%@%@(%@)", self.isOptional ? @"?" : @"", self.factType.name,
		        [parts componentsJoinedByString:@", "]];
	}
	case ORMFormulaValueIn:
		return [NSString stringWithFormat:@"%@ in %@", self.variable, [self.values displayText]];
	case ORMFormulaComparison:
		return [NSString stringWithFormat:@"%@(%@)", self.comparison, [self.operands componentsJoinedByString:@", "]];
	case ORMFormulaIdentity:
		return [NSString stringWithFormat:@"=(%@)", [self.operands componentsJoinedByString:@", "]];
	case ORMFormulaNot:
		return [NSString stringWithFormat:@"not %@", [self.children firstObject]];
	default: {
		NSString *joiner = self.kind == ORMFormulaAnd ? @" and " : self.kind == ORMFormulaOr ? @" or " : @" xor ";
		return [NSString stringWithFormat:@"(%@)", [self.children componentsJoinedByString:joiner]];
	}
	}
}

@end

@interface ORMRelation ()
@property (nonatomic, readwrite, strong) ORMFormula *formula;
@property (nonatomic, readwrite, copy) NSArray<ORMVariable *> *columns;
@property (nonatomic, readwrite) BOOL isIncomplete;
@end

@implementation ORMRelation

+ (instancetype)relationWithFormula:(ORMFormula *)formula columns:(NSArray<ORMVariable *> *)columns
{
	ORMRelation *relation = [[self alloc] init];
	relation.formula = formula;
	relation.columns = columns;
	return relation;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"[%@] %@%@", [self.columns componentsJoinedByString:@", "], self.formula,
	        self.isIncomplete ? @" (incomplete)" : @""];
}

@end

/* What building a path keeps track of: the variable each point of the
 * path stands for, by the id of the root or pathed role. */
@interface ORMPathBuilder : NSObject
@property (nonatomic, strong) NSMutableDictionary<NSString *, ORMVariable *> *variables;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ORMTerm *> *calculations;
@end

@implementation ORMPathBuilder

- (instancetype)init
{
	if ((self = [super init])) {
		_variables = [NSMutableDictionary dictionary];
		_calculations = [NSMutableDictionary dictionary];
	}
	return self;
}

/* A fact formula with the given terms, every other role a fresh variable
 * (but a unary's implicit role, which says nothing). */
- (ORMFormula *)completeFact:(ORMFactType *)fact terms:(NSMutableDictionary *)terms
{
	for (ORMRole *role in fact.roles) {
		if ([terms objectForKey:role.identifier] == nil && !role.player.isImplicitBooleanValue) {
			[terms setObject:[ORMTerm termWithVariable:[ORMVariable variableOf:role.player]] forKey:role.identifier];
		}
	}
	return [ORMFormula fact:fact terms:terms];
}

/* A path from the variable it goes on from: each join opens a fact formula
 * on the current variable; the fact type's other roles bring new
 * variables; sub-paths go on from where the path ends. */
- (ORMFormula *)build:(ORMRolePath *)path from:(ORMVariable *)start
{
	NSMutableArray *parts = [NSMutableArray array];
	ORMVariable *current = start;
	if (path.rootObjectType != nil) {
		current = [ORMVariable variableOf:path.rootObjectType];
		if (path.rootId != nil) {
			[self.variables setObject:current forKey:path.rootId];
		}
		if (path.rootValueConstraint != nil) {
			[parts addObject:[ORMFormula variable:current in:path.rootValueConstraint]];
		}
	}
	__block ORMFactType *fact = nil;
	__block NSMutableDictionary *terms = nil;
	__block BOOL negated = NO;
	__block BOOL optional = NO;
	/* The pathed role the open fact type was entered by. */
	ORMPathedRole *entered = nil;
	void (^close)(void) = ^{
		if (fact == nil) {
			return;
		}
		ORMFormula *formula = [self completeFact:fact terms:terms];
		formula.isOptional = optional;
		[parts addObject:negated ? [ORMFormula not:formula] : formula];
	};
	for (ORMPathedRole *pathed in path.pathedRoles) {
		ORMRole *role = pathed.role;
		if (role == nil) {
			continue;
		}
		ORMVariable *variable = nil;
		/* Into an objectification's link fact type: NORMA names the
		 * objectified role just entered, then the link fact type's other
		 * role. The fact entered is the link fact type, on the proxy. */
		/* And within one, NORMA names the objectified role a proxy
		 * stands for rather than the proxy. */
		if (pathed.purpose == ORMPathSameFactType && role.factType != fact) {
			for (ORMRole *proxy in fact.roles) {
				if (proxy.proxiedRole == role) {
					role = proxy;
				}
			}
		}
		if (pathed.purpose == ORMPathSameFactType && role.factType != fact && entered != nil && [terms count] == 1) {
			for (ORMRole *proxy in role.factType.roles) {
				if (proxy.proxiedRole == entered.role) {
					ORMTerm *at = [terms objectForKey:entered.role.identifier];
					fact = role.factType;
					terms = [NSMutableDictionary dictionaryWithObject:at forKey:proxy.identifier];
				}
			}
		}
		if (pathed.purpose == ORMPathSameFactType && role.factType == fact) {
			variable = [self.variables objectForKey:pathed.correlatedWith.identifier ?: @""]
				?: [ORMVariable variableOf:role.player];
		} else {
			close();
			fact = role.factType;
			terms = [NSMutableDictionary dictionary];
			entered = pathed;
			negated = pathed.isNegated;
			optional = pathed.purpose == ORMPathOuterJoin;
			/* Entered on what the path is at: the same instance. */
			variable = current ?: [ORMVariable variableOf:role.player];
		}
		negated = negated || pathed.isNegated;
		[terms setObject:[ORMTerm termWithVariable:variable] forKey:role.identifier];
		if (pathed.identifier != nil) {
			[self.variables setObject:variable forKey:pathed.identifier];
		}
		if (pathed.valueConstraint != nil) {
			[parts addObject:[ORMFormula variable:variable in:pathed.valueConstraint]];
		}
		current = variable;
	}
	close();
	if ([path.subPaths count] > 0) {
		NSMutableArray *branches = [NSMutableArray array];
		for (ORMRolePath *sub in path.subPaths) {
			[branches addObject:[self build:sub from:current]];
		}
		ORMFormulaKind kind = path.split == ORMPathSplitOr ? ORMFormulaOr
			: path.split == ORMPathSplitXor ? ORMFormulaXor : ORMFormulaAnd;
		ORMFormula *split = [ORMFormula combine:kind children:branches];
		[parts addObject:path.splitIsNegated ? [ORMFormula not:split] : split];
	}
	return [ORMFormula combine:ORMFormulaAnd children:parts];
}

- (ORMTerm *)termFor:(ORMPathSource *)source
{
	switch (source.kind) {
	case ORMPathSourceRoot: {
		ORMVariable *variable = [self.variables objectForKey:source.root.rootId ?: @""];
		return variable != nil ? [ORMTerm termWithVariable:variable] : nil;
	}
	case ORMPathSourcePathedRole: {
		ORMVariable *variable = [self.variables objectForKey:source.pathedRole.identifier ?: @""];
		return variable != nil ? [ORMTerm termWithVariable:variable] : nil;
	}
	case ORMPathSourceConstant:
		return [ORMTerm termWithConstant:source.constant ?: @""];
	case ORMPathSourceCalculation:
		return [self termForCalculation:source.calculation];
	}
	return nil;
}

- (ORMTerm *)termForCalculation:(ORMCalculation *)calculation
{
	if (calculation == nil) {
		return nil;
	}
	ORMTerm *made = [self.calculations objectForKey:calculation.identifier ?: @""];
	if (made != nil) {
		return made;
	}
	NSMutableArray *arguments = [NSMutableArray array];
	for (ORMPathSource *input in calculation.inputs) {
		ORMTerm *term = [self termFor:input];
		if (term != nil) {
			[arguments addObject:term];
		}
	}
	made = [ORMTerm termWithFunction:calculation.functionName arguments:arguments aggregate:calculation.isAggregate];
	if (calculation.identifier != nil) {
		[self.calculations setObject:made forKey:calculation.identifier];
	}
	return made;
}

/* An owner's paths and conditions as one formula, and the columns its
 * projections give the targets, in order. */
- (ORMRelation *)relationFor:(ORMRolePathOwner *)owner targets:(NSArray<NSString *> *)targets players:(NSArray *)players
{
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMRolePath *path in owner.paths) {
		[parts addObject:[self build:path from:nil]];
	}
	for (ORMCalculation *condition in owner.conditions) {
		ORMTerm *term = [self termForCalculation:condition];
		[parts addObject:[ORMFormula compare:term.functionName operands:term.arguments ?: @[]]];
	}
	ORMRelation *relation = [[ORMRelation alloc] init];
	relation.formula = [ORMFormula combine:ORMFormulaAnd children:parts];
	NSMutableArray *columns = [NSMutableArray array];
	for (NSUInteger i = 0; i < [targets count]; i++) {
		ORMTerm *term = [self termFor:[owner.projections objectForKey:[targets objectAtIndex:i]]];
		ORMVariable *variable = term.variable;
		if (variable == nil) {
			relation.isIncomplete = YES;
			variable = [ORMVariable variableOf:[players objectAtIndex:i]];
		}
		[columns addObject:variable];
	}
	relation.columns = columns;
	return relation;
}

@end

@implementation ORMLogic

+ (ORMRelation *)relationForFactType:(ORMFactType *)factType
{
	NSMutableDictionary *terms = [NSMutableDictionary dictionary];
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMRole *role in [factType visibleRoles]) {
		ORMVariable *variable = [ORMVariable variableOf:role.player];
		[terms setObject:[ORMTerm termWithVariable:variable] forKey:role.identifier];
		[columns addObject:variable];
	}
	ORMRelation *relation = [[ORMRelation alloc] init];
	relation.formula = [ORMFormula fact:factType terms:terms];
	relation.columns = columns;
	return relation;
}

+ (ORMRelation *)relationForSequence:(ORMRoleSequence *)sequence
{
	NSArray *roles = sequence.roles;
	ORMRolePathOwner *joinPath = [sequence joinPath];
	if (joinPath != nil && [joinPath.paths count] > 0) {
		NSMutableArray *players = [NSMutableArray array];
		for (ORMRole *role in roles) {
			[players addObject:role.player ?: [NSNull null]];
		}
		return [[[ORMPathBuilder alloc] init] relationFor:joinPath targets:[sequence roleUseIds] players:players];
	}
	/* Without a path: each role's fact type, the role a column; the fact
	 * types joined where another of their roles is played by an object
	 * type a column or an earlier join already has. */
	ORMRelation *relation = [[ORMRelation alloc] init];
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMRole *role in roles) {
		[columns addObject:[ORMVariable variableOf:role.player]];
	}
	NSMutableArray *facts = [NSMutableArray array];
	NSMutableDictionary *termsByFact = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		ORMRole *role = [roles objectAtIndex:i];
		ORMFactType *fact = role.factType;
		NSMutableDictionary *terms = [termsByFact objectForKey:fact.identifier];
		if (terms == nil) {
			terms = [NSMutableDictionary dictionary];
			[termsByFact setObject:terms forKey:fact.identifier];
			[facts addObject:fact];
		}
		[terms setObject:[ORMTerm termWithVariable:[columns objectAtIndex:i]] forKey:role.identifier];
	}
	NSMutableArray *joins = [NSMutableArray array];
	BOOL joined = [facts count] <= 1;
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMFactType *fact in facts) {
		NSMutableDictionary *terms = [termsByFact objectForKey:fact.identifier];
		for (ORMRole *role in [fact visibleRoles]) {
			if ([terms objectForKey:role.identifier] != nil) {
				continue;
			}
			ORMVariable *shared = nil;
			if ([facts count] > 1) {
				/* A column of this type from another fact type, else a
				 * join variable an earlier fact type made. */
				for (NSUInteger i = 0; i < [roles count] && shared == nil; i++) {
					ORMRole *columnRole = [roles objectAtIndex:i];
					if (columnRole.factType != fact && columnRole.player == role.player) {
						shared = [columns objectAtIndex:i];
					}
				}
				for (ORMVariable *join in joins) {
					if (shared == nil && join.objectType == role.player) {
						shared = join;
					}
				}
			}
			if (shared != nil) {
				joined = YES;
			} else {
				shared = [ORMVariable variableOf:role.player];
				[joins addObject:shared];
			}
			[terms setObject:[ORMTerm termWithVariable:shared] forKey:role.identifier];
		}
		[parts addObject:[ORMFormula fact:fact terms:terms]];
	}
	relation.formula = [ORMFormula combine:ORMFormulaAnd children:parts];
	relation.columns = columns;
	relation.isIncomplete = !joined;
	return relation;
}

+ (ORMRelation *)relationForDerivation:(ORMDerivationRule *)rule of:(ORMElement *)derived
{
	NSMutableArray *targets = [NSMutableArray array];
	NSMutableArray *players = [NSMutableArray array];
	if ([derived isKindOfClass:[ORMFactType class]]) {
		for (ORMRole *role in [(ORMFactType *)derived visibleRoles]) {
			[targets addObject:role.identifier];
			[players addObject:role.player ?: [NSNull null]];
		}
	} else if ([derived isKindOfClass:[ORMObjectType class]]) {
		/* A subtype's rule projects nothing: the path's root is the
		 * subtype's instance. */
		ORMPathBuilder *builder = [[ORMPathBuilder alloc] init];
		ORMRelation *relation = [builder relationFor:rule targets:@[] players:@[]];
		ORMRolePath *lead = [rule.paths firstObject];
		ORMVariable *root = [builder.variables objectForKey:lead.rootId ?: @""];
		relation.columns = root != nil ? @[ root ] : @[];
		relation.isIncomplete = root == nil;
		return relation;
	}
	return [[[ORMPathBuilder alloc] init] relationFor:rule targets:targets players:players];
}

+ (void)numberVariables:(NSArray<ORMVariable *> *)variables
{
	NSCountedSet *counts = [[NSCountedSet alloc] init];
	for (ORMVariable *variable in variables) {
		[counts addObject:[NSValue valueWithNonretainedObject:variable.objectType]];
	}
	NSMutableDictionary *next = [NSMutableDictionary dictionary];
	for (ORMVariable *variable in variables) {
		NSValue *key = [NSValue valueWithNonretainedObject:variable.objectType];
		if ([counts countForObject:key] > 1) {
			NSUInteger ordinal = [[next objectForKey:key] unsignedIntegerValue] + 1;
			[next setObject:@(ordinal) forKey:key];
			variable.ordinal = ordinal;
		} else {
			variable.ordinal = 0;
		}
	}
}

@end
