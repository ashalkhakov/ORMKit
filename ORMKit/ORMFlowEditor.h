/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlow.h"

@class ORMModel, ORMQuery;

/* A flow being designed (docs/FORMS.md, Flows), over the model it names:
 * each change one undo step, named for what it does, its listeners told
 * (ORMFlowEditorDidChangeNotification) and its problems said again. What
 * the designer's canvas and inspector change it through; it is Foundation
 * only, and tested without a window. */

extern NSNotificationName const ORMFlowEditorDidChangeNotification;

@interface ORMFlowEditor : NSObject

/* undoManager may be nil: no undo. */
- (instancetype)initWithFlow:(ORMFlow *)flow model:(ORMModel *)model undoManager:(NSUndoManager *)undoManager;
@property (nonatomic, readonly, strong) ORMFlow *flow;
@property (nonatomic, strong) ORMModel *model;
@property (nonatomic, readonly, strong) NSUndoManager *undoManager;

/* What a screen may show: the model's forms, then its lists, by name. */
- (NSArray<ORMQuery *> *)forms;
- (NSArray<ORMQuery *> *)lists;
/* The query a screen shows; nil for a placeholder, or one gone. */
- (ORMQuery *)queryOfScreen:(ORMFlowScreen *)screen;
/* A form's inputs (its given nodes), by id, and what each is called. */
- (NSArray<NSString *> *)inputsOfScreen:(ORMFlowScreen *)screen;
- (NSString *)nameOfNode:(NSString *)nodeId inScreen:(ORMFlowScreen *)screen;
/* What the flow says wrong of it now (ORMFlow's -problemsInModel:). */
- (NSArray<NSString *> *)problems;

#pragma mark Screens

/* A screen showing the form or list, at the place, named as it is: its id
 * one of the flow's own. The first screen is the flow's entry, Start. */
- (ORMFlowScreen *)addScreenForQuery:(ORMQuery *)query at:(NSPoint)origin;
- (void)moveScreens:(NSArray<NSString *> *)screenIds by:(NSSize)delta;
- (void)renameScreen:(NSString *)screenId to:(NSString *)name;
/* The screens gone, with their transitions and entries. */
- (void)removeScreens:(NSArray<NSString *> *)screenIds;

#pragma mark Transitions

/* From one screen to another on the action its kind of screen has first: a
 * list's row chosen, a form's submission done. Going to a form, it gives
 * each input it can from what is before: the row's anchor where the list's
 * is of the input's type. nil where it cannot go so (the same screen). */
- (ORMFlowTransition *)addTransitionFrom:(NSString *)fromId to:(NSString *)toId;
/* Back (or Close) from a screen, on an action: a cancel. */
- (ORMFlowTransition *)addReturnFrom:(NSString *)fromId on:(NSString *)on kind:(NSString *)kind;
/* The transition at the index, changed. */
- (void)setOn:(NSString *)on control:(NSString *)control ofTransition:(NSUInteger)index;
- (void)setKind:(NSString *)kind ofTransition:(NSUInteger)index;
- (void)setTarget:(NSString *)toId ofTransition:(NSUInteger)index;
/* Its gives, all at once: what it gives each input. */
- (void)setGives:(NSArray<ORMFlowGive *> *)gives ofTransition:(NSUInteger)index;
- (void)removeTransitions:(NSIndexSet *)indexes;

#pragma mark Entries

- (void)addEntryNamed:(NSString *)name toScreen:(NSString *)screenId;
- (void)setEntries:(NSArray<ORMFlowEntry *> *)entries;

#pragma mark Reading and writing

/* The flow's file, as it is now. */
- (NSData *)XMLData;
/* The flow as it was read, kept as it is now: no undo, no change named. */
- (BOOL)readData:(NSData *)data error:(NSError **)error;

@end
