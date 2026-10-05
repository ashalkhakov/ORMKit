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
 * in FORML, as the request to the OData service, as its plan, and as the
 * rows it reads from the model's sample population.
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
/* Building from the diagram: a role box clicked there adds a step from the
 * node selected through its fact type, entered by a role the node's object
 * type plays, and selects the node of the role clicked; the next click
 * goes on from there. Its id; nil, and why in the status line, when the
 * node plays no role of that fact type. */
- (NSString *)followRole:(ORMRole *)role;
/* Whether role boxes clicked on the diagram build the query. */
@property (nonatomic, readonly) BOOL buildsFromDiagram;
/* The FORML, as shown. */
- (NSString *)verbalizationText;
/* The OData request, and the plan with how the interpreter runs it against a
 * Core Data store, as the tabs show them. */
- (NSString *)requestText;
- (NSString *)fetchText;
/* The query run against the model's sample population, put in a store of
 * its mapping (ORMPopulationStore): the first page of rows the Results tab
 * shows; nil, and the tab says why, when there is no population or the
 * query reads nothing. */
- (ORMQueryResult *)result;
/* Replaces the sample population with one made up to meet the constraints
 * (ORMPopulationGenerator), as one change. */
- (IBAction)makeUpPopulation:(id)sender;
@end
