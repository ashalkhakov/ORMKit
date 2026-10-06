/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"
#import "ORMCoreDataMapping.h"

typedef NS_ENUM(NSInteger, ORMIssueSeverity) {
	ORMIssueError,
	ORMIssueWarning,
	ORMIssueNote,
};

/* Something wrong with a model, or worth knowing, and what it is about. */
@interface ORMIssue : NSObject
@property (nonatomic, readonly) ORMIssueSeverity severity;
/* Where it comes from: "Model", "Population", "Core Data". */
@property (nonatomic, readonly, copy) NSString *area;
@property (nonatomic, readonly, copy) NSString *text;
/* What it is about: an element of the model, or a query's id; nil for
 * nothing in particular. */
@property (nonatomic, readonly, copy) NSString *elementId;
@end

/* A model's issues, as an issue navigator lists them (docs/WINDOW.md):
 * - the model's own errors, as NORMA reports them: an entity type with no
 *   reference scheme, a fact type with no uniqueness constraint or with no
 *   reading; a reading that does not read: placeholders not the roles',
 *   an order not the fact type's roles, two fact types read the same way;
 * - what its sample population breaks (ORMPopulationChecker): constraints
 *   and constraint queries, alethic ones errors and deontic ones warnings;
 * - what the mapping to Core Data warns of, or does not enforce.
 * Errors first, then warnings, then notes, each in the model's order. */
@interface ORMIssueFinder : NSObject
/* The mapping's notes, or the defaults' for nil. */
- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;
- (NSArray<ORMIssue *> *)issues;
@end
