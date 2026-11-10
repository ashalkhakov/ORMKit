/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

@class NSManagedObjectContext, NSManagedObjectModel, ORMForm;
@protocol ODataTransport;

/* A form being filled in (docs/FORMS.md, In and out), whatever shows it:
 * the XForms document ormtool generates (a host answering its form:read,
 * form:choices/<name> and form:save from here), or a view of the app's own,
 * a XIB's controls bound to its values. Opened with the form's inputs, it
 * holds the values by element, as the form's table names them; offers each
 * reference's choices for the values as they are; and saves, against the
 * app's store or the model's OData service. A save refused says why by
 * element, to be shown at the controls of each, and "" for the form's own;
 * a save done gives its result, the object's key.
 *
 *   ORMFormSession *session = [[ORMFormSession alloc] initWithForm:[ORMForm formNamed:@"RecordFillUp" error:NULL]
 *                                                             given:@{ @"vehicle" : vehicleKey, @"enteredBy" : email }];
 *   [session useContext:context saving:nil];
 *   [session open:&error];
 *   [session setValue:@"12345" forElement:@"mileageQuantity"];
 *   NSArray *drivers = [session choicesNamed:@"driver" error:&error];
 *   if (![session save:&error]) ... session.errors ...
 *
 * Against the service each call waits for its answer, the current run loop
 * turning meanwhile (an answer finished on it, a sign-in's, arrives). */
@interface ORMFormSession : NSObject

- (instancetype)initWithForm:(ORMForm *)form given:(NSDictionary<NSString *, NSString *> *)given;
@property (nonatomic, readonly, strong) ORMForm *form;
/* The form's inputs, as it was opened with them. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *given;

/* Against a context, on its queue, saved by saving (the app's way: its
 * keys, derivations and rules first), or by the context's -save: where it
 * is nil. A refused save puts the object back as it was; the rest of the
 * context is its owner's, a window's own to roll back, the main window's
 * other changes kept. */
- (void)useContext:(NSManagedObjectContext *)context
            saving:(BOOL (^)(NSManagedObjectContext *context, NSError **error))saving;
/* Against the service at the root, its names the model's, its requests sent
 * by the transport (a sign-in's, with its credentials). */
- (void)useServiceRoot:(NSURL *)root model:(NSManagedObjectModel *)model transport:(id<ODataTransport>)transport;

/* The object the form edits, by its key; nil for a new one. */
@property (nonatomic, copy) NSString *key;

/* The values read: the object of the key, or a new one's, its inputs in
 * it. NO, and why, where it cannot be read. */
- (BOOL)open:(NSError **)error;
/* The values, by element: each element's text, as the form's table has it
 * (xsd's lexical forms: "2026-11-10T08:30:00Z", "true", "40.5"). */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *values;
- (NSString *)valueForElement:(NSString *)name;
- (void)setValue:(NSString *)value forElement:(NSString *)name;
/* All of them, as a view (XForms' instance) has them after its own edits. */
- (void)setValues:(NSDictionary<NSString *, id> *)values;

/* A reference's choices for the values as they are (the vehicle's
 * drivers): their keys, in order; an element's the model lists the values
 * of (a fuel, a currency), the list. nil, and why, where they cannot be
 * read. */
- (NSArray<NSString *> *)choicesNamed:(NSString *)name error:(NSError **)error;

/* A repeat's rows (an order's lines), each its elements' text as the
 * repeat's form has them; set all at once, as a view's table has them. */
- (NSArray<NSDictionary<NSString *, NSString *> *> *)rowsOfRepeat:(NSString *)name;
- (void)setRows:(NSArray<NSDictionary<NSString *, NSString *> *> *)rows forRepeat:(NSString *)name;
/* A reference's choices in a repeat's row, for its values as they are. */
- (NSArray<NSString *> *)choicesNamed:(NSString *)name inRepeat:(NSString *)repeat row:(NSUInteger)row error:(NSError **)error;

/* Submitted, not saved: what a process's task is done with (its form
 * handler carries out the procedure the form stands for). Given, -save:
 * hands the values to it instead of writing them; it answers what it
 * refuses by element ("" for the form's own; a row's "lines[1].quantity"),
 * none when done, and what it made, by its key. */
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *(^submitting)(NSDictionary<NSString *, id> *values, NSString **savedKey);

/* The values written into the object and saved: YES, its key the result.
 * NO where it is refused (errors) or cannot be sent (error). */
- (BOOL)save:(NSError **)error;
/* What the last save refused, by element, "" for what is of none. */
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *errors;
/* What the last save saved: the object's key; nil before one is done. */
@property (nonatomic, readonly, copy) NSString *savedKey;
@end
