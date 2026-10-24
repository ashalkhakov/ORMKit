/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQuery.h"

/* A derivation query written as NORMA's role path (docs/DERIVATION.md), so
 * that NORMA has the rule itself and not only its words.
 *
 * The root is the path's root object type; each step a join by its entry
 * role (PostInnerJoin; PostOuterJoin for maybe), negated for not, and its
 * nodes the fact type's other roles (SameFactType), the one the path goes
 * on from last. Where it goes on from several, it splits: a sub-path for
 * each, and for each step of a node with several (Or where they are
 * alternatives). A not over more than one fact type is a negated split.
 * A node's condition on a value is a value restriction on its pathed role;
 * one with another node, a value node and an aggregate are calculated
 * values and conditions, on functions the model declares; nodes with a
 * label are unified. Each role is projected from its node.
 *
 * Ids are made from the query's, the same each time: the path is written
 * of the query again on each save, and the same query writes the same
 * path. */
@interface ORMDerivationPathWriter : NSObject
- (instancetype)initWithDocument:(NSXMLDocument *)document;
/* The query's path: PathComponents, then for a fact type's derivation
 * DerivationProjections, made in the document but not in it yet; nil, and
 * why, where NORMA's path does not say it. */
- (NSArray<NSXMLElement *> *)elementsOf:(ORMQuery *)query reason:(NSString **)reason;
/* The functions the path's calculations use, as the model declares them
 * (Function, with its Parameters), not yet in the document. */
- (NSArray<NSXMLElement *> *)functions;
@end
