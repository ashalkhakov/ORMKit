/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMEditor.h"

/* A query read back from its outline, as -[ORMQuery outlineText] writes one
 * (docs/QUERIES.md, Outline):
 *
 *   ✓Employee
 *     + lives in City
 *       + is location of Branch = 52
 *
 * The first line is the root: ✓ ticks it, digits after the name are a
 * label, then a condition and ↑ or ↓. Each "+" line indented under a node
 * is a step from it: a reading of a fact type from the role the node's
 * object type plays, each other role's node written in its place, as the
 * outline writes it, after "or", "not" or "maybe". Under a step, "+ count(X)
 * for Y > n" (or total, avg, max, min, compared with a value or another
 * aggregate) is its aggregate, and "X:" turns to the steps of its node of
 * X (the first node's need none). A constraint's or calculation's first
 * line ("It is impossible that:", "Total of each Branch is total(Salary)
 * of:") says what the query is for. */
@interface ORMOutlineReader : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, strong) ORMEditor *editor;

/* The query the outline says, made as one change: its id. nil, with the
 * line it could not read and why, where it cannot be. name nil: the
 * calculation's, or the root's object type's. */
- (NSString *)addQueryNamed:(NSString *)name outline:(NSString *)text reason:(NSString **)reason;
@end
