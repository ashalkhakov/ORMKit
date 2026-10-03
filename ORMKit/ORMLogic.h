/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMPath.h"

/* What a constraint's role sequence, a join path or a derivation rule says,
 * as logic: variables standing for object instances, fact atoms saying
 * which variables play which roles, conditions on values, comparisons and
 * calculations, put together with and, or, exactly one, and not.
 *
 * One form for everything that reads it: the verbalizer says it in FORML,
 * and code generation says it as Core Data validation. A role sequence's
 * columns are the variables its roles stand for, in the sequence's order,
 * so constraints that compare sequences compare columns. */

@class ORMFormula;

@interface ORMVariable : NSObject
@property (nonatomic, readonly, weak) ORMObjectType *objectType;
/* Its place among the variables of its object type in what it belongs
 * to, from 1: what tells Person1 from Person2. */
@property (nonatomic) NSUInteger ordinal;
+ (instancetype)variableOf:(ORMObjectType *)type;
@end

/* A value a formula speaks of: a variable, a constant, or a calculation
 * over terms. */
@interface ORMTerm : NSObject
@property (nonatomic, readonly, strong) ORMVariable *variable;
@property (nonatomic, readonly, copy) NSString *constant;
@property (nonatomic, readonly, copy) NSString *functionName;
@property (nonatomic, readonly, copy) NSArray<ORMTerm *> *arguments;
@property (nonatomic, readonly) BOOL isAggregate;
+ (instancetype)termWithVariable:(ORMVariable *)variable;
+ (instancetype)termWithConstant:(NSString *)constant;
+ (instancetype)termWithFunction:(NSString *)name arguments:(NSArray<ORMTerm *> *)arguments aggregate:(BOOL)aggregate;
@end

typedef NS_ENUM(NSInteger, ORMFormulaKind) {
	/* A fact type's roles played by variables (or terms). */
	ORMFormulaFact,
	/* A variable's value is in a value constraint's ranges. */
	ORMFormulaValueIn,
	/* Two terms compared ("LessThan", ...), or a boolean function. */
	ORMFormulaComparison,
	/* Two variables are the same instance. */
	ORMFormulaIdentity,
	ORMFormulaAnd,
	ORMFormulaOr,
	ORMFormulaXor,
	ORMFormulaNot,
};

@interface ORMFormula : NSObject
@property (nonatomic, readonly) ORMFormulaKind kind;
/* Fact: the fact type, and each role's term by role id. */
@property (nonatomic, readonly, weak) ORMFactType *factType;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, ORMTerm *> *terms;
/* An outer join's fact: it holds if it can, the path goes on if not. */
@property (nonatomic, readonly) BOOL isOptional;
/* ValueIn. */
@property (nonatomic, readonly, strong) ORMVariable *variable;
@property (nonatomic, readonly, strong) ORMValueConstraint *values;
/* Comparison: operator and operands; a boolean function's name. */
@property (nonatomic, readonly, copy) NSString *comparison;
@property (nonatomic, readonly, copy) NSArray<ORMTerm *> *operands;
/* And, Or, Xor, Not. */
@property (nonatomic, readonly, copy) NSArray<ORMFormula *> *children;

+ (instancetype)fact:(ORMFactType *)factType terms:(NSDictionary<NSString *, ORMTerm *> *)terms;
/* An outer join's fact: "maybe". */
+ (instancetype)optionalFact:(ORMFactType *)factType terms:(NSDictionary<NSString *, ORMTerm *> *)terms;
+ (instancetype)variable:(ORMVariable *)variable in:(ORMValueConstraint *)values;
+ (instancetype)compare:(NSString *)comparison operands:(NSArray<ORMTerm *> *)operands;
+ (instancetype)combine:(ORMFormulaKind)kind children:(NSArray<ORMFormula *> *)children;
+ (instancetype)not:(ORMFormula *)formula;

/* The fact formulas in it, depth first. */
- (NSArray<ORMFormula *> *)facts;
/* Every variable it mentions, in the order first mentioned. */
- (NSArray<ORMVariable *> *)variables;
/* The variable playing the role in a fact formula; nil for a constant. */
- (ORMVariable *)variableForRole:(ORMRole *)role;
@end

/* A relation: a formula and the variables it is about, in order. A role
 * sequence's columns; a derivation's head roles; a fact type's roles. */
@interface ORMRelation : NSObject
@property (nonatomic, readonly, strong) ORMFormula *formula;
@property (nonatomic, readonly, copy) NSArray<ORMVariable *> *columns;
/* Built from a join path that could not be followed, or a sequence that
 * needs one and has none: the formula says what it can. */
@property (nonatomic, readonly) BOOL isIncomplete;
+ (instancetype)relationWithFormula:(ORMFormula *)formula columns:(NSArray<ORMVariable *> *)columns;
@end

@interface ORMLogic : NSObject
/* A role sequence as a relation over its roles' players: its join path's
 * when it has one; its fact type's when its roles are in one; else its
 * fact types joined where they share an object type. */
+ (ORMRelation *)relationForSequence:(ORMRoleSequence *)sequence;
/* A fact type over all its roles, each a variable. */
+ (ORMRelation *)relationForFactType:(ORMFactType *)factType;
/* A derivation rule: the relation it derives, its columns in the order of
 * the fact type's roles (for a subtype, the one subtype instance). */
+ (ORMRelation *)relationForDerivation:(ORMDerivationRule *)rule of:(ORMElement *)derived;
/* Gives the variables of the same object type ordinals 1, 2, ... in the
 * order given, where more than one shares a type; 0 otherwise. */
+ (void)numberVariables:(NSArray<ORMVariable *> *)variables;
@end
