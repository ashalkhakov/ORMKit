/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* A document's conceptual queries (docs/QUERIES.md), built as ConQuer
 * builds them: start at an object type, pick the fact types to go on
 * through from each object type reached, tick what to list, add conditions,
 * negate a step or make it optional. The query is shown as its outline,
 * in FORML, and as the Core Data fetch request its mapping makes of it.
 *
 * Every change goes through the document's editor, so it is undone with
 * the model's own changes. */
@interface ORMQueryController : NSWindowController
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, strong) ORMEditor *editor;
/* The query shown. */
@property (nonatomic, copy) NSString *queryId;
/* The node or step selected in the outline. */
@property (nonatomic, readonly, copy) NSString *selectedId;

- (void)modelDidChange;
/* A new query from the object type, shown. */
- (NSString *)addQueryFrom:(NSString *)objectTypeId;
- (void)selectElement:(NSString *)nodeOrStepId;
/* The roles the selected node can go on through, and adding a step
 * through one of them. */
- (NSArray<ORMRole *> *)availableRoles;
- (NSString *)addStepThrough:(ORMRole *)role;
/* The FORML, as shown. */
- (NSString *)verbalizationText;
/* The OData request, and the Core Data fetch request, as the tabs show them. */
- (NSString *)requestText;
- (NSString *)fetchText;
@end
