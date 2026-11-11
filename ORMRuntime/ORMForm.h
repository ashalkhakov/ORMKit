/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlan.h"

@class NSManagedObject, NSManagedObjectContext, NSManagedObjectModel, ORMQueryOData;

/* A form as an app runs it (docs/FORMS.md, In and out): the table ormtool
 * xforms writes beside the form's XForms document, <Form>.ormform, and
 * what its abstract names stand for. It is the form's contract, whatever
 * shows it: what it is given (its inputs), what is entered and shown, the
 * choices it offers, and what a save writes, its result the object saved.
 * The XForms document generated is one view of it; a view of the app's own
 * (a XIB's) runs the same contract through ORMFormSession.
 *
 *   form:read              the object read, its row put into the instance
 *   form:choices/<name>    a reference's choices: their keys
 *   form:save              the instance written into the object
 *
 * The instance is a dictionary here, each element's text by its name, as
 * XForms holds it: the XML is the host's (XFormsKit's transports), and
 * this runs on iOS too, which has no NSXML. Each name is two ways: against
 * the app's own store (Core Data, offline), or as requests to the model's
 * OData service, which the host sends. Either way a refusal comes back as
 * messages by element, to be shown at their controls.
 *
 *   {
 *     format = 1;
 *     form = RecordFillUp;
 *     entity = FillUp;
 *     key = id;                                 the anchor's key's element
 *     elements = ( { name = mileageQuantity; kind = value;     value,
 *                    type = "xsd:decimal";      reference or calculated
 *                    column = 3; part = 0;      the read's column, a part
 *                    written = YES; }, ... );   of a compound's list
 *     read = { ... };                           its parameter the key's
 *     choices = { driver = { all = {...};       with nothing to go by
 *                            plan = {...};      by what it depends on,
 *                            dependsOn = ( vehicle ); }; };   parameters
 *     checkedWhereSubmitted = ( "..." );
 *   } */

extern const NSUInteger ORMFormFormat;
extern NSString * const ORMFormErrorDomain;

/* An element of the instance: its name (the property's), what it holds, its
 * XML Schema type, where the read has it, and whether a save writes it. A
 * reference holds the key (the attribute keyName) of an object of entity. */
@interface ORMFormElement : NSObject
@property (nonatomic, readonly, copy) NSString *name;
/* "value", "reference", "calculated". */
@property (nonatomic, readonly, copy) NSString *kind;
@property (nonatomic, readonly, copy) NSString *schemaType;
/* NSNotFound where the read has none. */
@property (nonatomic, readonly) NSUInteger column;
/* Its place among a compound's parts, its column's list; NSNotFound for none. */
@property (nonatomic, readonly) NSUInteger part;
@property (nonatomic, readonly, copy) NSString *entityName;
@property (nonatomic, readonly, copy) NSString *keyName;
@property (nonatomic, readonly) BOOL written;
/* What it is to whoever opens the form: "key" (the object's own), "given"
 * (it comes in, and is not entered), "entered", "shown", "calculated", or
 * "hidden" (read only to compute with). */
@property (nonatomic, readonly, copy) NSString *role;
/* It comes in as the form opens (the vehicle it is for): one of the form's
 * inputs, entered or not. */
@property (nonatomic, readonly) BOOL given;
/* What the model calls it ("filled the tank", "driver"); its name in a
 * table from before labels. */
@property (nonatomic, readonly, copy) NSString *label;
/* The values it may have, where the model lists them (a fuel, a
 * currency): its choices, whatever the store holds; nil for others. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *items;
/* Each item as a reader says it, where it is not the value itself (a
 * kind's: "Fill up" for FillUp); nil where they are. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *itemLabels;
/* The item's label: its itemLabels', else the item itself. */
- (NSString *)labelOfItem:(NSString *)item;
/* Beyond the anchor's own properties, the keys to it from the anchor
 * (purchaseOrder, supplier, contact, contactName); nil for its own, but
 * one named for another (a trip's moment, "tripMoment": moment). In an
 * object the form owns, the group of it (its keys: "contact"); through
 * one it refers to, none: shown as read, and as the reference's object
 * has it once that is chosen. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *path;
@property (nonatomic, readonly, copy) NSString *group;
/* In a subtype's part (+ is Trip), its subentity: written, and relevant,
 * where the object is one. The form's kind element ("isA", kind
 * "subtype") says which the object is, its items the subentities; a new
 * one is made of it, one read is of it, and stays so. */
@property (nonatomic, readonly, copy) NSString *subtype;
/* Entered to find the object of a reference (an order's customer, by its
 * email: docs/FORMS.md, D6): that reference's element; nil for others.
 * The reference's role is then "identified": the app finds it. */
@property (nonatomic, readonly, copy) NSString *identifies;
/* An aggregate over a repeat's rows (docs/FORMS.md, D14): its function
 * ("count", "total", "avg", "max", "min") and the path to the values
 * (purchaseLines, quantity); nil for others. */
@property (nonatomic, readonly, copy) NSDictionary *aggregate;
@end

/* What to send the service to save the form: the method, the path under
 * the service root, the headers and the JSON body. */
@interface ORMFormRequest : NSObject
/* "POST" for a new object, "PATCH" for one changed. */
@property (nonatomic, readonly, copy) NSString *method;
/* "FillUps", "FillUps(42)". */
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *body;
- (NSData *)bodyData;
@end

@interface ORMForm : NSObject
+ (instancetype)formWithPropertyList:(id)list error:(NSError **)error;
- (id)propertyList;
/* <name>.ormform from the main bundle or a framework or bundle loaded, read
 * once, unless one was registered under the name. */
+ (instancetype)formNamed:(NSString *)name error:(NSError **)error;
+ (void)registerForm:(ORMForm *)form named:(NSString *)name;

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *entityName;
/* The element the anchor's key is in. */
@property (nonatomic, readonly, copy) NSString *keyElement;
@property (nonatomic, readonly, copy) NSArray<ORMFormElement *> *elements;
- (ORMFormElement *)elementNamed:(NSString *)name;
/* The read: its parameter the key's element. */
@property (nonatomic, readonly, strong) ORMQueryPlan *readPlan;
/* The form's inputs: the elements given as it opens, by name. */
- (NSArray<NSString *> *)inputNames;
/* The objects it owns (docs/FORMS.md: a customer's contact, the
 * contact's address), made and changed with the anchor, outer ones first:
 * each {name, path, entity, label, needed}, its elements those of the
 * group of its name. One not needed is made only where something of it is
 * entered. */
- (NSArray<NSDictionary *> *)groups;
/* Its repeats (docs/FORMS.md: a step from the anchor to many, an order's
 * lines), by the element each is: a form of its own each, over the objects
 * linked to this one by its link element (the line's order). In an
 * instance a repeat's value is its rows: an array of instances, each as
 * the repeat's form has them. */
- (NSArray<NSString *> *)repeatNames;
- (ORMForm *)repeatNamed:(NSString *)name;
/* A repeat's element that holds the key of the object of the form it is in;
 * nil for a form that is no repeat. */
@property (nonatomic, readonly, copy) NSString *linkElement;
/* A repeat that is a list (docs/FORMS.md, D9): its rows read, never written. */
@property (nonatomic, readonly) BOOL isList;
/* The element of the form whose value the repeat's rows are linked to (an
 * owned object's key, "contact/id"; a reference's, "driver"); nil for the
 * anchor's key. */
- (NSString *)repeatFrom:(NSString *)name;
/* A repeat's rows linked to the object of the key, read in the context. */
- (NSArray<NSDictionary *> *)rowsLinkedTo:(NSString *)key inContext:(NSManagedObjectContext *)context error:(NSError **)error;
/* The references with choices, by element name. */
- (NSArray<NSString *> *)choiceNames;
/* The elements a reference's choices depend on. */
- (NSArray<NSString *> *)elementsChoicesDependOn:(NSString *)name;
/* Its choices' plan for the instance's values: by what it depends on where
 * each has a value, else every one. nil, and why, for no reference. */
- (ORMQueryPlan *)choicesPlanNamed:(NSString *)name values:(NSDictionary<NSString *, id> *)values error:(NSError **)error;
/* The references found by values entered, and the elements that find each. */
- (NSArray<NSString *> *)identifiedNames;
- (NSArray<NSString *> *)elementsIdentifying:(NSString *)name;
/* What finds a reference's object for the instance's values: the objects of
 * its type whose key they are. nil, and why, for none such. */
- (ORMQueryPlan *)identifyPlanNamed:(NSString *)name values:(NSDictionary<NSString *, id> *)values error:(NSError **)error;
/* The rules the form cannot check, said: the store or the service does. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *checkedWhereSubmitted;

/* An instance as the form opens on a new object: each element empty, but
 * the values given (the vehicle it is for), a flag entered "false", and
 * each repeat no rows. */
- (NSDictionary<NSString *, id> *)instanceGiven:(NSDictionary<NSString *, id> *)values;
/* The instance with each aggregate worked out over its rows as they are:
 * a total and a count "0" over none, the others "". */
- (NSDictionary<NSString *, id> *)instanceWithAggregates:(NSDictionary<NSString *, id> *)instance;
/* A row of the read, from the store or the service, as the instance: each
 * element's text from its column (a compound's from its part, a reference's
 * key), xsd's lexical forms ("2026-11-10T08:30:00Z", "true", "40.5"). */
- (NSDictionary<NSString *, id> *)instanceOfRow:(NSArray *)row;

#pragma mark The store

/* The object of the key read in the context, as the instance; nil, and why,
 * where there is none or it cannot be read. */
- (NSDictionary<NSString *, id> *)readKey:(NSString *)key
                                        inContext:(NSManagedObjectContext *)context
                                            error:(NSError **)error;
/* A reference's choices for the instance's values: their keys, in order. */
- (NSArray<NSString *> *)choicesNamed:(NSString *)name
                               values:(NSDictionary<NSString *, id> *)values
                            inContext:(NSManagedObjectContext *)context
                                error:(NSError **)error;
/* The key of the object the instance's values find, in the context: "" where
 * no object has them, or none is entered; nil, and why, where it cannot be
 * read. */
- (NSString *)identifiedKeyNamed:(NSString *)name
                          values:(NSDictionary<NSString *, id> *)values
                       inContext:(NSManagedObjectContext *)context
                           error:(NSError **)error;
/* Each element through a reference of the instance's (an order's
 * supplier's name), as the object the reference is to has it, in the
 * context: "" where it has none, or the reference none. */
- (NSDictionary<NSString *, NSString *> *)throughValuesOf:(NSDictionary<NSString *, id> *)instance
                                                inContext:(NSManagedObjectContext *)context;
/* The instance written into its object, found by its key or made (a key
 * given it where it has none), each reference found by its key, each
 * repeat's rows written into their objects linked to it (those it had and
 * the rows have not, deleted), and the context saved: the object saved. nil where it is refused, and what was
 * done to the object undone: errors then each element's message, by name
 * (what the store's validation, the model's rules at save among them, says
 * of its property), "" for what is said of no element. */
- (NSManagedObject *)save:(NSDictionary<NSString *, id> *)instance
                inContext:(NSManagedObjectContext *)context
                   errors:(NSDictionary<NSString *, NSString *> **)errors
                    error:(NSError **)error;
/* The same, saved as the app saves (its keys, derivations and rules first,
 * its own store's way): saving instead of the context's -save:. */
- (NSManagedObject *)save:(NSDictionary<NSString *, id> *)instance
                inContext:(NSManagedObjectContext *)context
                   saving:(BOOL (^)(NSManagedObjectContext *context, NSError **error))saving
                   errors:(NSDictionary<NSString *, NSString *> **)errors
                    error:(NSError **)error;
/* What a failed save's error says of each element, "" for the rest: a
 * rule's said at the first of its properties (ORMKeys) the form enters, so
 * that one the user cannot change (the vehicle given) is not where it is
 * said; a rule of another object of the form's. */
- (NSDictionary<NSString *, NSString *> *)elementErrorsOf:(NSError *)error;

#pragma mark The service

/* The read of the key as requests to the model's service, and a choices
 * plan's; their rows go through -instanceOfRow: and the choice's key. */
- (ORMQueryOData *)readRequestForKey:(NSString *)key model:(NSManagedObjectModel *)model error:(NSError **)error;
- (ORMQueryOData *)identifyRequestNamed:(NSString *)name
                                 values:(NSDictionary<NSString *, id> *)values
                                  model:(NSManagedObjectModel *)model
                                  error:(NSError **)error;
/* What a save is refused for where values entered find no object: "There
 * is no Customer with that Email.", at the first element that finds it. */
- (NSString *)unfoundMessageNamed:(NSString *)name;
- (ORMQueryOData *)choicesRequestNamed:(NSString *)name
                                values:(NSDictionary<NSString *, id> *)values
                                 model:(NSManagedObjectModel *)model
                                 error:(NSError **)error;
/* What saves the instance: a POST of each element written that has a
 * value, where it has no key or no original; else a PATCH of those that differ from the original,
 * with the ETag read (If-Match). A reference is bound
 * ("Vehicle@odata.bind": "Vehicles(7)"); names are the service's. nil, and
 * why, where a value is not of its type. */
- (ORMFormRequest *)saveRequestFor:(NSDictionary<NSString *, id> *)instance
                          original:(NSDictionary<NSString *, id> *)original
                              etag:(NSString *)etag
                             model:(NSManagedObjectModel *)model
                             error:(NSError **)error;
/* What the service's error body (JSON) says of each element: a detail's or
 * the error's target, a property's name on the wire, by its element; the
 * rest under "". */
- (NSDictionary<NSString *, NSString *> *)elementErrorsOfResponse:(NSData *)body model:(NSManagedObjectModel *)model;
@end
