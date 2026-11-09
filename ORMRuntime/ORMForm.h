/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlan.h"

@class NSManagedObject, NSManagedObjectContext, NSManagedObjectModel, ORMQueryOData;

/* A form as an app runs it (docs/FORMS.md, In and out): the table ormtool
 * xforms writes beside the form's XForms document, <Form>.ormform, and
 * what its abstract names stand for.
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
/* The references with choices, by element name. */
- (NSArray<NSString *> *)choiceNames;
/* The elements a reference's choices depend on. */
- (NSArray<NSString *> *)elementsChoicesDependOn:(NSString *)name;
/* Its choices' plan for the instance's values: by what it depends on where
 * each has a value, else every one. nil, and why, for no reference. */
- (ORMQueryPlan *)choicesPlanNamed:(NSString *)name values:(NSDictionary<NSString *, NSString *> *)values error:(NSError **)error;
/* The rules the form cannot check, said: the store or the service does. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *checkedWhereSubmitted;

/* An instance as the form opens on a new object: each element empty, but
 * the values given (the vehicle it is for). */
- (NSDictionary<NSString *, NSString *> *)instanceGiven:(NSDictionary<NSString *, NSString *> *)values;
/* A row of the read, from the store or the service, as the instance: each
 * element's text from its column (a compound's from its part, a reference's
 * key), xsd's lexical forms ("2026-11-10T08:30:00Z", "true", "40.5"). */
- (NSDictionary<NSString *, NSString *> *)instanceOfRow:(NSArray *)row;

#pragma mark The store

/* The object of the key read in the context, as the instance; nil, and why,
 * where there is none or it cannot be read. */
- (NSDictionary<NSString *, NSString *> *)readKey:(NSString *)key
                                        inContext:(NSManagedObjectContext *)context
                                            error:(NSError **)error;
/* A reference's choices for the instance's values: their keys, in order. */
- (NSArray<NSString *> *)choicesNamed:(NSString *)name
                               values:(NSDictionary<NSString *, NSString *> *)values
                            inContext:(NSManagedObjectContext *)context
                                error:(NSError **)error;
/* The instance written into its object, found by its key or made (a key
 * given it where it has none), each reference found by its key, and the
 * context saved: the object saved. nil where it is refused, and what was
 * done to the object undone: errors then each element's message, by name
 * (what the store's validation, the model's rules at save among them, says
 * of its property), "" for what is said of no element. */
- (NSManagedObject *)save:(NSDictionary<NSString *, NSString *> *)instance
                inContext:(NSManagedObjectContext *)context
                   errors:(NSDictionary<NSString *, NSString *> **)errors
                    error:(NSError **)error;
/* What a failed save's error says of each element, "" for the rest. */
- (NSDictionary<NSString *, NSString *> *)elementErrorsOf:(NSError *)error;

#pragma mark The service

/* The read of the key as requests to the model's service, and a choices
 * plan's; their rows go through -instanceOfRow: and the choice's key. */
- (ORMQueryOData *)readRequestForKey:(NSString *)key model:(NSManagedObjectModel *)model error:(NSError **)error;
- (ORMQueryOData *)choicesRequestNamed:(NSString *)name
                                values:(NSDictionary<NSString *, NSString *> *)values
                                 model:(NSManagedObjectModel *)model
                                 error:(NSError **)error;
/* What saves the instance: a POST of each element written that has a
 * value, where it has no key or no original; else a PATCH of those that differ from the original,
 * with the ETag read (If-Match). A reference is bound
 * ("Vehicle@odata.bind": "Vehicles(7)"); names are the service's. nil, and
 * why, where a value is not of its type. */
- (ORMFormRequest *)saveRequestFor:(NSDictionary<NSString *, NSString *> *)instance
                          original:(NSDictionary<NSString *, NSString *> *)original
                              etag:(NSString *)etag
                             model:(NSManagedObjectModel *)model
                             error:(NSError **)error;
/* What the service's error body (JSON) says of each element: a detail's or
 * the error's target, a property's name on the wire, by its element; the
 * rest under "". */
- (NSDictionary<NSString *, NSString *> *)elementErrorsOfResponse:(NSData *)body model:(NSManagedObjectModel *)model;
@end
