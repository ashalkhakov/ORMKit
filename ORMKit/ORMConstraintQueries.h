/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQuery.h"

/* A constraint over roles of more than one fact type, said as the rule
 * queries (docs/RULES.md) whose rows are what breaks it, so that what
 * checks rules checks it too: the validation code and the sample
 * population's checker, where the constraint's roles are no properties of
 * one entity.
 *
 *   If some Event had driver some User and that Event is of some Vehicle
 *   then that User drives that Vehicle.
 *
 * is the rule
 *
 *   It is impossible that:
 *   ✓User1
 *     + Event had driver that User
 *       + is of Vehicle1
 *     + not drives Vehicle1
 *
 * - a subset: its first sequence's facts, and not its second's, their
 *   columns the same objects;
 * - an equality: a subset each way;
 * - an exclusion: two of its sequences' facts at once, for each pair;
 * - a value comparison: the two values, compared the other way;
 * - an inclusive-or over roles of several fact types: none of them
 *   played.
 *
 * Each sequence is its join path's facts, or its fact types joined where
 * they share an object type (ORMLogic). The queries are made in the
 * editor's document: a copy's, for planning, as they are not the model's. */
@interface ORMConstraintQueries : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, strong) ORMEditor *editor;
/* The object types a query may read from, by id (those with an entity of
 * their own, say); nil for any. */
@property (nonatomic, copy) NSSet<NSString *> *readable;
/* The constraint's queries, made: their ids. nil, and why, where none
 * can say it (a join no tree of steps follows, a sequence that cannot be
 * read as facts). */
- (NSArray<NSString *> *)queriesFor:(ORMConstraint *)constraint reason:(NSString **)reason;
@end
