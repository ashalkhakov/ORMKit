/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

@class ORMFlow, ORMFlowScreen, ORMFlowTransition, ORMModel, ORMCoreDataMapping, ORMFormSession;

/* A flow walked through over the model's sample population (docs/FORMS.md,
 * Flows): its screens opened one after another, as an app opens them, in a
 * store holding the population (ORMPopulationStore). A list's rows are its
 * query's over the population; a form opens with what the way to it gave,
 * its choices are the population's, and its save is checked as the app's
 * would be: a refusal says the rule in its own words, before anything is
 * built. An overlay returns what it made to the form it was opened over.
 *
 *   ORMFlowWalk *walk = [[ORMFlowWalk alloc] initWithFlow:flow model:model mapping:nil];
 *   [walk beginAt:@"Start" error:&error];          // Vehicles: 2 rows
 *   [walk take:rowChosen row:0 error:&error];      // RecordFillUp, its vehicle given
 *   [walk.session setValue:@"40" forElement:@"volumeQuantity"];
 *   [walk submit:&error];                          // refused, or saved and on to the next
 *   walk.log                                       // what happened, a line a step */
@interface ORMFlowWalk : NSObject
- (instancetype)initWithFlow:(ORMFlow *)flow model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping;
@property (nonatomic, readonly, strong) ORMFlow *flow;

/* Begun at the entry of the name (nil: the first), in a new store of the
 * population. NO, and why, where the population cannot be stored or the
 * entry's screen opened. */
- (BOOL)beginAt:(NSString *)entryName error:(NSError **)error;

/* The screen it is at; nil before it begins, or once it has gone back past
 * the first. */
@property (nonatomic, readonly, strong) ORMFlowScreen *screen;
/* A list's: its rows over the population, each its columns' text by title,
 * and its anchor's key; nil for a form. */
@property (nonatomic, readonly, copy) NSArray<NSDictionary<NSString *, NSString *> *> *rows;
@property (nonatomic, readonly, copy) NSArray<NSString *> *rowKeys;
/* A form's: its session, open on the population's store; nil for a list. */
@property (nonatomic, readonly, strong) ORMFormSession *session;
/* A reference's value as a reader knows what it refers to, the form's
 * element named: the object's other identifier (a van's plate, a
 * station's name), else its first text, else the key itself; a kind's
 * as a reader says it ("Fill up"). */
- (NSString *)labelOfKey:(NSString *)key element:(NSString *)name;
/* The ways on from here, in the flow's order. */
- (NSArray<ORMFlowTransition *> *)transitions;

/* The transition taken: the row of the list chosen for RowChosen (ignored
 * for the others), what it gives worked out, the next screen opened (over
 * this one, for an overlay; this one left, for Back; the one it is over
 * given what the overlay made, for Close). */
- (BOOL)take:(ORMFlowTransition *)transition row:(NSUInteger)row error:(NSError **)error;
/* The form saved, then the way on its outcome taken, where the flow has
 * one: SubmitDone, or SubmitError with the refusal. YES where it saved. */
- (BOOL)submit:(NSError **)error;

/* What happened, a line a step:
 *
 *   ▶ Start: Vehicles, 2 rows: Car 7 | Car 8
 *   Vehicles —RowChosen (Car 7)→ RecordFillUp, given vehicle = car-7
 *   RecordFillUp refused: timestamp: Each FillUp was at some Moment.
 *   RecordFillUp saved: 6F1C...
 *   RecordFillUp —SubmitDone→ back: Vehicles */
@property (nonatomic, readonly, copy) NSArray<NSString *> *log;

/* Walked on its own from the entry, each way taken once: a list's first
 * row chosen, a form submitted as it opens (each reference's first choice
 * taken where it is empty), its triggers taken before its Cancel, until no
 * way is left from where it is. The log, or nil and why. */
- (NSString *)walkFrom:(NSString *)entryName error:(NSError **)error;
@end
