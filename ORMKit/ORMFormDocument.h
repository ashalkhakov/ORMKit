/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMQueryPlanner.h"

@class ORMFlow, ORMFlowScreen;

/* A form (docs/FORMS.md) as an XForms 1.1 document: what ormtool xforms
 * writes, generated and never edited.
 *
 *   Form RecordFillUp:                         <FillUp>           the instance (Fmap)
 *   FillUp                                       <id/>
 *     + is of Vehicle1 = ?                       <vehicle/>         a reference: its key
 *     + was at Moment (entered)                  <timestamp/>       typed by its bind
 *     + cost Money (entered)                     <totalAmount/>     a compound, as the
 *                                                <totalCurrency/>   mapping absorbs it
 *     + had driver User (entered)                <driver/>          a select1, its choices
 *       + drives Vehicle1                                           read for that vehicle
 *     PricePerUnit = Amount / Quantity (shown)   <pricePerUnit/>    calculated
 *
 * Each node is placed by the column the planner gives it in the form's read
 * (the form listed, each step a maybe, the steps under a reference left
 * out), so its elements are named as the mapping names the properties: the
 * entity's own representation, the same whether a store or the service
 * holds it. The binds come from the constraints over the form's roles, each
 * control's alert their verbalization; what the form cannot check alone is
 * listed as checked where it is submitted. Every id is the form's node's or
 * the constraint's, so a renamed role or a reordered outline keeps it.
 *
 * The document does not say where its data is: its instances and
 * submissions name what they are ("form:read", "form:choices/driver",
 * "form:save"), and the app that runs it resolves them, with the plans
 * below. */

extern NSString * const ORMFormNamespace;

/* A place in the instance: an element of the anchor's, what it holds, and
 * the form's node it is of. */
typedef NS_ENUM(NSInteger, ORMFormFieldKind) {
	/* An attribute's value. */
	ORMFormFieldValue,
	/* An entity's key: one of its choices. */
	ORMFormFieldReference,
	/* A value node's, calculated. */
	ORMFormFieldCalculated,
	/* Which of the form's subtypes the object is (+ is Trip, + is FillUp):
	 * its subentity's name, "" for none of them. */
	ORMFormFieldSubtype,
};

@interface ORMFormField : NSObject
@property (nonatomic, readonly, copy) NSString *nodeId;
/* Its element under the anchor's: the property's name. */
@property (nonatomic, readonly, copy) NSString *elementName;
@property (nonatomic, readonly) ORMFormFieldKind kind;
/* "xsd:decimal", "xsd:dateTime", ... */
@property (nonatomic, readonly, copy) NSString *schemaType;
/* A reference's: the entity referred to and its key's property. */
@property (nonatomic, readonly, copy) NSString *entityName;
@property (nonatomic, readonly, copy) NSString *keyName;
/* Of a compound's parts, its place among them (0 for others), and the
 * role it is the value of: the part's, or the node's. */
@property (nonatomic, readonly) NSUInteger partIndex;
@property (nonatomic, readonly, weak) ORMRole *role;
/* Beyond the anchor's own properties: the keys from the anchor to it
 * (contact, contactName); nil for the anchor's own, but one named for
 * another (a trip's moment, "tripMoment": moment). In an object the form
 * owns (a customer's contact, made and changed with it), its group, the
 * keys to the object ("contact", "contact/shippingAddress"), and its
 * element under it ("contact/contactName"); through an object it refers
 * to (an order's supplier's name), none, read and shown, never written
 * ("purchaseOrderSupplierContactContactName"). */
@property (nonatomic, readonly, copy) NSArray<NSString *> *keys;
@property (nonatomic, readonly, copy) NSString *groupName;
@property (nonatomic, readonly) BOOL isThrough;
/* In a subtype's part of the form (+ is Trip), the subentity it is a
 * property of: relevant where the object is one; nil for the anchor's. */
@property (nonatomic, readonly, copy) NSString *subtypeEntity;
/* Entered beneath a choice, one of the values of a key of its (D6): the
 * reference element it finds the object of (an order's customer by email);
 * nil for others. */
@property (nonatomic, readonly, copy) NSString *identifies;
/* Its id in the document: the node's, a part's index after it. */
- (NSString *)fieldId;
@end

@interface ORMFormDocument : NSObject
/* The form through the mapping (the defaults for nil). nil, and why, for a
 * query that is no form, or one the mapping cannot place. */
+ (instancetype)documentForForm:(ORMQuery *)form
                          model:(ORMModel *)model
                        mapping:(ORMCoreDataMapping *)mapping
                         reason:(NSString **)reason;
@property (nonatomic, readonly, strong) ORMQuery *form;
@property (nonatomic, readonly, copy) NSString *entityName;
/* The instance's elements, in outline order; the anchor's key first. */
@property (nonatomic, readonly, copy) NSArray<ORMFormField *> *fields;
- (ORMFormField *)fieldNamed:(NSString *)elementName;
/* The instance as the form opens on a new object: each element empty but
 * the given ones' (by element name). */
- (NSXMLElement *)instanceGiven:(NSDictionary<NSString *, NSString *> *)values;
/* The XForms document. */
- (NSXMLDocument *)document;
/* What the form's read is ("form:read"): the anchor, each element; of the
 * object with the key, nil for every one. */
- (ORMQueryPlan *)readPlanForKey:(NSString *)key;
/* A reference's choices ("form:choices/<name>"), by its element's name:
 * the objects of its type its conditions hold of (the users who drive that
 * vehicle), each node they share with the form compared with that
 * element's value where values has one. nil for no reference. */
- (ORMQueryPlan *)choicesPlanNamed:(NSString *)elementName given:(NSDictionary<NSString *, NSString *> *)values;
/* The references with choices, by element name, in order. */
- (NSArray<NSString *> *)choiceNames;
/* The references found by values entered (D6), by element name, in
 * order: no choices of theirs; and the elements that find each. */
- (NSArray<NSString *> *)identifiedNames;
- (NSArray<NSString *> *)elementsIdentifying:(NSString *)elementName;
/* What finds a reference's object ("form:identify/<name>"): the objects of
 * its type whose key is the values, a parameter for each element that
 * finds it, named so. */
- (ORMQueryPlan *)identifyPlanNamed:(NSString *)elementName;
/* The elements whose values a reference's choices depend on. */
- (NSArray<NSString *> *)elementsChoicesDependOn:(NSString *)elementName;
/* The same as an app runs them (ORMRuntime's ORMForm): the read of the
 * object whose key is the parameter named as the key's element; each
 * reference's choices, a parameter for each element they depend on, named
 * so, and nil where they depend on none. */
- (ORMQueryPlan *)readPlan;
- (ORMQueryPlan *)choicesPlanNamed:(NSString *)elementName;
/* What an app needs to run the form (ORMRuntime's ORMForm, docs/RUNTIME.md):
 * its elements and the read's columns they are of, the plans that answer
 * "form:read" and "form:choices/<name>", and what "form:save" writes; as
 * ormtool xforms writes it, <Form>.ormform beside the document. */
- (id)tablePropertyList;
/* The constraints, and the rules, the form cannot check alone, as their
 * verbalizations: checked where it is submitted. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *checkedWhereSubmitted;
/* What the form says that the document leaves out, and why. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *notes;
/* What the model has in the form (entered, shown, given, computed) that
 * the document has no element for: a form that is not the model's, which
 * ormtool xforms refuses to write. Empty for a whole one. */
@property (nonatomic, readonly, copy) NSArray<NSString *> *missing;
/* Their nodes' ids, and the unary steps': where the designer marks them. */
@property (nonatomic, readonly, copy) NSSet<NSString *> *missingIds;
/* The steps from the anchor to many (an order's lines), each a form of its
 * own by the element it is (its relationship's name): anchored on what the
 * step reaches, given the anchor back, read for every object linked to
 * it. A repeat's link is that element (the line's order). */
- (NSDictionary<NSString *, ORMFormDocument *> *)repeats;
- (NSString *)linkElement;
/* The element a node of the form is placed as; nil for one not placed. */
- (NSString *)elementOfNode:(NSString *)nodeId;
/* The elements the form asks a value of before it is submitted, whatever
 * else is entered (its binds' required "true()"), each with what the
 * constraints it comes from say: "Each FillUp was at some Moment." An
 * owned object's (its group's, "contact/contactName") only once anything
 * of that object is entered. */
- (NSDictionary<NSString *, NSString *> *)requiredElements;

/* The screen of a flow the document is shown as (docs/FORMS.md, Flows),
 * set before -document: the flow's transitions from it generated into the
 * document's actions, the save done or refused loading what comes next,
 * Cancel and each trigger's control a trigger that does. What comes next
 * is a resource the app resolves, as it does the form's own:
 *
 *   form:open/<Form>?<element>=<value>&...  the next screen's form, its
 *                                           given elements; over this one
 *                                           for an overlay (show="new")
 *   form:list/<Query>                       the next screen's list
 *   form:back                               the screen before
 *   form:close?<element>=<value>&...        the overlay closed, the values
 *                                           given to the form it is over
 *
 * A value is one of this form's elements (its key, for "result"), or
 * "{<screen id>.<node id>}" for a screen's before it, which the app keeps.
 * The next form's elements are named as its document names them. */
- (void)setFlow:(ORMFlow *)flow screen:(ORMFlowScreen *)screen;
/* The service's action the form is submitted to, not saved (a procedure:
 * goods received, given the order as the form has it), set before
 * -document: its save "form:submit/<Action>", and the table says it, so
 * that ORMFormSession calls it. nil to save. */
@property (nonatomic, copy) NSString *action;
/* The app's words for its constraints and rules, by id or name ("TooMuch":
 * "No tank holds that much."): said in the document's alerts and what it
 * checks where submitted instead of their verbalizations, and in the
 * table, for what the store refuses. */
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *messages;
/* The forms it is made or changed with, one change set (docs/FORMS.md):
 * a document each, in order; empty for one anchor. The XForms document of
 * several anchors has them all: its instance an element of each, named as
 * its form, read each by its key ("form:read/<Form>"), saved as one. */
@property (nonatomic, readonly, copy) NSArray<ORMFormDocument *> *parts;
@end
