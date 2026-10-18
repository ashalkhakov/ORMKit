/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* What a value node of a query computes (docs/EXPRESSIONS.md): another
 * node's value, a constant, or a function of expressions.
 *
 * Written two ways:
 * - as the file keeps it, each node by its id: subtract(#_n2, #_n1);
 * - as the outline says it, each node by its designation, arithmetic infix:
 *   Quantity2 - Quantity1, (Amount - Discount) * 2, round(Litres / Kilometres * 100, 2).
 *
 * The functions, by name: add, subtract, multiply, divide, negate (said
 * +, -, *, / and a leading -; also −, ×, ÷), round(a, n), abs(a), min(a, b),
 * max(a, b), coalesce(a, b). */

typedef NS_ENUM(NSInteger, ORMQueryExpressionKind) {
	ORMQueryExpressionNode,
	ORMQueryExpressionConstant,
	ORMQueryExpressionFunction,
};

@interface ORMQueryExpression : NSObject <NSCopying>
@property (nonatomic, readonly) ORMQueryExpressionKind kind;
/* A node's: its id. */
@property (nonatomic, readonly, copy) NSString *nodeId;
/* A constant's: as written, a number, or text quoted ('a''b'). */
@property (nonatomic, readonly, copy) NSString *constant;
/* A function's: its name and arguments. */
@property (nonatomic, readonly, copy) NSString *function;
@property (nonatomic, readonly, copy) NSArray<ORMQueryExpression *> *arguments;

+ (instancetype)node:(NSString *)nodeId;
+ (instancetype)constant:(NSString *)text;
+ (instancetype)function:(NSString *)name arguments:(NSArray<ORMQueryExpression *> *)arguments;

/* The functions there are, by name, and how many arguments each takes. */
+ (NSDictionary<NSString *, NSNumber *> *)functionArities;

/* As the file keeps it; nil, and why, where it is not one. */
+ (instancetype)expressionWithCanonicalText:(NSString *)text reason:(NSString **)reason;
- (NSString *)canonicalText;
/* As the outline says it, each node by a designation the map has (to its
 * id); nil, and why, where it is not one. */
+ (instancetype)expressionWithText:(NSString *)text
                      designations:(NSDictionary<NSString *, NSString *> *)nodeIds
                            reason:(NSString **)reason;
/* As the outline says it, each node by its designation (from its id). */
- (NSString *)textWithDesignations:(NSDictionary<NSString *, NSString *> *)designations;

/* The nodes it uses, by id, each once, in the order met. */
- (NSArray<NSString *> *)nodeIds;
/* The same, a node's id another. */
- (ORMQueryExpression *)expressionRenaming:(NSString *)from to:(NSString *)to;
/* Whether its value is a number: a number, a node of those given (by
 * id), or arithmetic. */
- (BOOL)isNumericGivenNumericNodes:(NSSet<NSString *> *)numeric;
@end
