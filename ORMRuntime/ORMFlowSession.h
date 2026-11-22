/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* A screen of a flow opened: the form it shows (or the list), what it was
 * given, and the object it is on. */
@interface ORMFlowStep : NSObject
/* The screen's id in the flow, and its name. */
@property (nonatomic, readonly, copy) NSString *screen;
@property (nonatomic, readonly, copy) NSString *name;
/* Its form's name (an ORMForm's), or its list's (a query's); one of them. */
@property (nonatomic, readonly, copy) NSString *formName;
@property (nonatomic, readonly, copy) NSString *listName;
/* What the way to it gave its form's inputs, by element. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *given;
/* The object the form is on (its anchor given: an order to confirm); nil
 * for a new one. */
@property (nonatomic, readonly, copy) NSString *key;
/* Opened over the screen before it (a modal form, returning what it
 * made), not in its place. */
@property (nonatomic, readonly, getter=isOverlay) BOOL overlay;
/* An overlay's closed over it: what it gave back, by element of this
 * screen's form (the expense kind just made). Empty otherwise. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *returned;
@end

/* A way on from a screen: on an action ("SubmitDone", "SubmitError",
 * "Cancel", "RowChosen", "Trigger" a control), of a kind ("Navigate",
 * "Overlay", "Back", "Close"), to a screen (nil for Back and Close). */
@interface ORMFlowWay : NSObject
@property (nonatomic, readonly, copy) NSString *on;
@property (nonatomic, readonly, copy) NSString *control;
@property (nonatomic, readonly, copy) NSString *kind;
@property (nonatomic, readonly, copy) NSString *to;
@end

/* A flow being gone through (docs/FORMS.md, Flows), whatever shows its
 * screens: an app's views of the forms (a window, a sheet over it, a list),
 * or a task's (a process's user task done with a flow's entry,
 * ormkit:flow:Purchasing.flow#Confirm). Begun at an entry, it says the
 * screen to show and what its form is given; each way taken (a row chosen,
 * a control triggered, a form saved or refused or cancelled) says the next,
 * its values worked out from the row, the result, or what a screen before
 * had. It opens no view and saves nothing: those are the app's.
 *
 *   ORMFlowSession *flow = [ORMFlowSession flowNamed:@"Purchasing" error:&error];
 *   ORMFlowStep *step = [flow beginAt:@"Confirm" key:orderKey error:&error];
 *   ... the app opens step.formName on step.key, the user submits ...
 *   ORMFlowWay *way = [flow wayOn:@"SubmitDone" control:nil];
 *   step = way != nil ? [flow take:way row:nil result:savedKey values:session.values] : nil;
 *   if (flow.ended) ... the flow is done: the task's form submitted ...
 *
 * Read from what ormtool xforms --flow writes (<Flow>.ormflow), beside the
 * forms' own. */
@interface ORMFlowSession : NSObject
/* <name>.ormflow from the main bundle or a framework or bundle loaded. */
+ (instancetype)flowNamed:(NSString *)name error:(NSError **)error;
- (instancetype)initWithPropertyList:(id)list error:(NSError **)error;

@property (nonatomic, readonly, copy) NSString *name;
/* Its entries' names, in its order. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *entryNames;

/* Begun again at the entry of the name (nil: the first), its form on the
 * object of the key (nil: a new one) and given these. nil, and why, where
 * the flow has no such entry. */
- (ORMFlowStep *)beginAt:(NSString *)entryName key:(NSString *)key error:(NSError **)error;
- (ORMFlowStep *)beginAt:(NSString *)entryName key:(NSString *)key given:(NSDictionary<NSString *, NSString *> *)given
                   error:(NSError **)error;

/* The screen it is at: the last opened; nil once it has gone back past
 * the first, or closed it (ended). */
@property (nonatomic, readonly, strong) ORMFlowStep *step;
/* Those open, the first first: each an overlay's under it. */
@property (nonatomic, readonly, copy) NSArray<ORMFlowStep *> *steps;
@property (nonatomic, readonly, getter=hasEnded) BOOL ended;

/* The ways on from where it is, in the flow's order. */
- (NSArray<ORMFlowWay *> *)ways;
/* The way on the action (a trigger's of the control); nil where the flow
 * has none from here. */
- (ORMFlowWay *)wayOn:(NSString *)on control:(NSString *)control;

/* The way taken from where it is: what it gives worked out from the row
 * chosen's key (a list's), the key the screen saved (result) and the
 * values it has (by element, kept for a screen after to give on); then the
 * next screen opened on top of this one (Back comes back to it; an
 * overlay's shown over it), this one left (Back), or the overlay closed
 * and what it gives returned to the one under it (Close). The step it is
 * at now; nil where it has ended. */
- (ORMFlowStep *)take:(ORMFlowWay *)way row:(NSString *)rowKey result:(NSString *)result
               values:(NSDictionary<NSString *, id> *)values;
@end
