/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

@class ORMModel, ORMQuery;

/* A flow (docs/FORMS.md, Flows): an actor's way through the model's forms
 * and lists, kept in a .flow file of its own beside the .orm it names.
 * Its screens show a form or a list (a query whose rows lead somewhere),
 * each by the query's id, its name beside it for a reader; its transitions
 * go from a screen, on an action, to a screen, giving it values; its
 * entries are where an app, or a process's task, begins.
 *
 *   <flow:Flow xmlns:flow="http://schemas.ormkit.org/2026-10/Flows" Name="Records" Model="Logbook.orm">
 *     <flow:Entry Name="Start" Screen="_s1"/>
 *     <flow:Screen id="_s1" Query="_qVehicles" Name="Vehicles" X="0" Y="0" Width="390" Height="844"/>
 *     <flow:Screen id="_s3" Form="_fFillUp" Name="RecordFillUp" X="960" Y="0" Width="390" Height="844"/>
 *     <flow:Transition From="_s1" On="RowChosen" To="_s3">
 *       <flow:Give Node="_nVehicle" From="row"/>
 *     </flow:Transition>
 *     <flow:Transition From="_s3" On="SubmitDone" Kind="Back"/>
 *   </flow:Flow>
 *
 * What it gives is a given node of the next screen's form (its = ?), and
 * where it comes from: "row" (the list's row chosen, its anchor), "result"
 * (what the screen before saved), or "<screen id>.<node id>" (a value a
 * screen before had). It does not keep what is inside a screen: that is the
 * form's. A screen whose query the model no longer has, or a value given
 * to what is not one of its form's inputs, is a problem, reported. */

extern NSString * const ORMFlowNamespace;

/* "SubmitDone", "SubmitError", "Cancel", "RowChosen", "Trigger". */
extern NSString * const ORMFlowOnSubmitDone;
extern NSString * const ORMFlowOnSubmitError;
extern NSString * const ORMFlowOnCancel;
extern NSString * const ORMFlowOnRowChosen;
extern NSString * const ORMFlowOnTrigger;

/* "Navigate" (the default), "Overlay" (a modal form, returning with what
 * it made), "Back", "Close" (the overlay). */
extern NSString * const ORMFlowKindNavigate;
extern NSString * const ORMFlowKindOverlay;
extern NSString * const ORMFlowKindBack;
extern NSString * const ORMFlowKindClose;

@interface ORMFlowScreen : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
/* The form's query's id, or the list's: one of them; neither for a
 * placeholder, a screen not yet a form. */
@property (nonatomic, copy) NSString *formId;
@property (nonatomic, copy) NSString *queryId;
/* Its frame on the flow's canvas. */
@property (nonatomic) double x, y, width, height;
@end

@interface ORMFlowGive : NSObject
/* The given node of the next screen's form. */
@property (nonatomic, copy) NSString *nodeId;
/* "row", "result", or "<screen id>.<node id>". A Close's gives a node of
 * the form the overlay is over: what the overlay made, returned to it. */
@property (nonatomic, copy) NSString *from;
@end

@interface ORMFlowTransition : NSObject
@property (nonatomic, copy) NSString *fromScreen;
@property (nonatomic, copy) NSString *on;
/* A trigger's control, its id in the form; nil for the others. */
@property (nonatomic, copy) NSString *control;
/* nil for Back and Close. */
@property (nonatomic, copy) NSString *toScreen;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSArray<ORMFlowGive *> *gives;
@end

@interface ORMFlowEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *screen;
@end

@interface ORMFlow : NSObject
+ (instancetype)flowWithData:(NSData *)data error:(NSError **)error;
+ (instancetype)flowWithContentsOfURL:(NSURL *)url error:(NSError **)error;
/* The file's XML, as it is read back. */
- (NSData *)XMLData;

@property (nonatomic, copy) NSString *name;
/* The .orm it is of, relative to the flow's file. */
@property (nonatomic, copy) NSString *modelPath;
@property (nonatomic, copy) NSArray<ORMFlowScreen *> *screens;
@property (nonatomic, copy) NSArray<ORMFlowTransition *> *transitions;
@property (nonatomic, copy) NSArray<ORMFlowEntry *> *entries;

- (ORMFlowScreen *)screenWithId:(NSString *)identifier;
/* The screen's form, or its list's query; nil where it has neither, or
 * the model has none of the id. */
- (ORMQuery *)queryOf:(ORMFlowScreen *)screen inModel:(ORMModel *)model;
/* The screen an overlay is opened over: the first to open it so; nil for
 * one opened over nothing. */
- (ORMFlowScreen *)openerOf:(ORMFlowScreen *)overlay;
/* What is wrong of it against the model, each said: a screen's query gone
 * or of the wrong kind, a transition from or to no screen, an action its
 * screen has not (a row chosen in a form), a value given to what is not an
 * input of the next form, an entry to no screen. None: it holds. */
- (NSArray<NSString *> *)problemsInModel:(ORMModel *)model;
/* The next form's inputs a transition leaves to the app (who is signed
 * in), by node id: neither given by it nor problems. */
- (NSArray<NSString *> *)inputsLeftBy:(ORMFlowTransition *)transition inModel:(ORMModel *)model;
/* The flow as a reader reads it, a line a screen and a transition:
 *
 *   Flow Records (Logbook.orm)
 *   ▶ Start: Vehicles
 *   Vehicles (list) —RowChosen→ RecordFillUp (form): vehicle = row
 *   RecordFillUp (form) —SubmitDone→ back */
- (NSString *)textInModel:(ORMModel *)model;
@end
