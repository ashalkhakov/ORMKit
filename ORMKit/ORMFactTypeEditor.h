/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* Fact types: their players, readings and derivation notes, and
 * objectification. Usually reached as an editor's factTypeEditor. */
@interface ORMFactTypeEditor : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, weak) ORMEditor *editor;

/* A fact type over the players, in order, read as the reading says
 * ("{0} was born in {1}"); one player makes a unary fact type. Its id. */
- (NSString *)addFactTypeWithPlayers:(NSArray<NSString *> *)objectTypeIds
                             reading:(NSString *)reading
                           onDiagram:(NSString *)diagramId
                                  at:(NSPoint)point
                              reason:(NSString **)reason;
/* A reading for the roles in this order. Its id. */
- (NSString *)addReading:(NSString *)text
                forRoles:(NSArray<NSString *> *)roleIds
                  reason:(NSString **)reason;
- (BOOL)setReadingText:(NSString *)text of:(NSString *)readingId reason:(NSString **)reason;
/* Another player for the role. */
- (BOOL)setPlayer:(NSString *)objectTypeId ofRole:(NSString *)roleId reason:(NSString **)reason;
/* Derived fact types keep their rule as NORMA's DerivationRule; ORMKit
 * edits only its free-text description. */
- (BOOL)setDerivationNote:(NSString *)text of:(NSString *)factTypeId reason:(NSString **)reason;
/* A derived fact type's completeness and storage, as NORMA keeps them on
 * its rule (docs/DERIVATION.md): partly derived, some of its facts
 * asserted; stored, its facts kept once derived. NO for a fact type with
 * no rule, or only an older one (a DerivationExpression). */
- (BOOL)setDerivationPartial:(BOOL)partial stored:(BOOL)stored of:(NSString *)factTypeId reason:(NSString **)reason;
/* An objectified type nesting the fact type, and the link fact types
 * NORMA implies for it. Its id. */
- (NSString *)objectifyFactType:(NSString *)factTypeId named:(NSString *)name reason:(NSString **)reason;
- (BOOL)unobjectifyFactType:(NSString *)factTypeId reason:(NSString **)reason;

@end
