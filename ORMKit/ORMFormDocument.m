/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFormDocument.h"
#import "ORMModelPriv.h"
#import "ORMVerbalizer.h"
#import "ORMFlow.h"
#import "ORMFormDefinition.h"

NSString * const ORMFormNamespace = @"urn:ormkit:forms";

static NSString * const ORMXFormsNamespace = @"http://www.w3.org/2002/xforms";
static NSString * const ORMXHTMLNamespace = @"http://www.w3.org/1999/xhtml";
static NSString * const ORMEventsNamespace = @"http://www.w3.org/2001/xml-events";
/* XFormsKit's extensions: a warning, shown and never invalid. */
static NSString * const ORMXFormsKitNamespace = @"urn:xformskit:extensions";
static NSString * const ORMSchemaNamespace = @"http://www.w3.org/2001/XMLSchema";

@interface ORMFormField ()
@property (nonatomic, readwrite, copy) NSString *nodeId;
@property (nonatomic, readwrite, copy) NSString *elementName;
@property (nonatomic, readwrite) ORMFormFieldKind kind;
@property (nonatomic, readwrite, copy) NSString *schemaType;
@property (nonatomic, readwrite, copy) NSString *entityName;
@property (nonatomic, readwrite, copy) NSString *keyName;
@property (nonatomic, readwrite) NSUInteger partIndex;
@property (nonatomic, readwrite, weak) ORMRole *role;
/* A reference's object type, whose objects are its choices. */
@property (nonatomic, weak) ORMObjectType *referredType;
/* One of a compound's parts; the compound's role, for its label. */
@property (nonatomic) BOOL isPart;
/* Listed only for a value node to compute with: no control. */
@property (nonatomic) BOOL isHidden;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *keys;
@property (nonatomic, readwrite, copy) NSString *groupName;
@property (nonatomic, readwrite) BOOL isThrough;
@property (nonatomic, readwrite, copy) NSString *subtypeEntity;
@property (nonatomic, readwrite, copy) NSString *identifies;
@property (nonatomic, readwrite) BOOL isMany;
@end

@implementation ORMFormField

- (NSString *)fieldId
{
	return self.isPart ? [NSString stringWithFormat:@"%@-%lu", self.nodeId, (unsigned long)self.partIndex] : self.nodeId;
}

@end

/* What a bind says of one element, built up from each constraint that
 * applies: each property its own conditions, combined as XForms wants one
 * of each (required or'ed, relevant and constraint and'ed). */
@interface ORMFormBind : NSObject
@property (nonatomic, strong) ORMFormField *field;
@property (nonatomic, strong) NSMutableArray<NSString *> *required;
@property (nonatomic, strong) NSMutableArray<NSString *> *relevant;
@property (nonatomic, strong) NSMutableArray<NSString *> *constraint;
@property (nonatomic, copy) NSString *calculate;
@property (nonatomic) BOOL readonly;
/* The constraints it comes from, by id, and what they say. */
@property (nonatomic, strong) NSMutableArray<NSString *> *sources;
@property (nonatomic, strong) NSMutableArray<NSString *> *alerts;
/* Each alert's source, by the text: what the app's words replace. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *sourceOfAlert;
@end

@implementation ORMFormBind

- (instancetype)init
{
	if ((self = [super init])) {
		_required = [NSMutableArray array];
		_relevant = [NSMutableArray array];
		_constraint = [NSMutableArray array];
		_sources = [NSMutableArray array];
		_alerts = [NSMutableArray array];
		_sourceOfAlert = [NSMutableDictionary dictionary];
	}
	return self;
}

@end

/* A deontic constraint over the form's elements: shown, never refused. */
@interface ORMFormWarning : NSObject
@property (nonatomic, copy) NSString *constraintId;
@property (nonatomic, copy) NSString *elementName;
@property (nonatomic, copy) NSString *test;
@property (nonatomic, copy) NSString *text;
@end

@implementation ORMFormWarning
@end

@interface ORMQuery (ORMFormDocument)
+ (ORMQuery *)queryOf:(ORMStoredQuery *)stored model:(ORMModel *)model;
+ (ORMStoredQuery *)expansionOf:(ORMStoredQuery *)stored model:(ORMModel *)model notes:(NSMutableArray<NSString *> *)notes;
@end

@interface ORMStoredQuery (ORMFormDocument)
- (ORMQueryPart *)partWithId:(NSString *)identifier step:(BOOL)isStep;
@end

@implementation ORMFormDocument
{
	ORMModel *_model;
	ORMQueryPlanner *_planner;
	ORMStoredQuery *_stored;
	NSMutableArray<ORMFormField *> *_fields;
	NSMutableArray<NSString *> *_notes;
	NSMutableArray<NSString *> *_checked;
	NSMutableDictionary<NSString *, ORMFormBind *> *_binds;
	NSMutableArray<ORMFormWarning *> *_warnings;
	/* Each placed node's element, by its id: a part's node its part's. */
	NSMutableDictionary<NSString *, NSString *> *_elementOfNode;
	/* The steps under an entered reference: its choices' conditions, by id. */
	NSMutableSet<NSString *> *_conditionSteps;
	ORMVerbalizer *_verbalizer;
	/* The anchor's unary steps entered or shown, by id: a flag each. */
	NSMutableDictionary<NSString *, ORMQueryStep *> *_unarySteps;
	NSMutableArray<NSString *> *_missing;
	NSMutableSet<NSString *> *_missingIds;
	/* -definingSteps, worked out once. */
	NSArray<NSArray *> *_definingSteps;
	/* The steps from the anchor to many (an order's lines), by id, and the
	 * element each is (its relationship's name): a repeat each, a form of
	 * its own over the objects it reaches. */
	NSMutableDictionary<NSString *, NSString *> *_repeatSteps;
	NSMutableDictionary<NSString *, ORMFormDocument *> *_repeats;
	/* A repeat's own: its given node that is the anchor of the form it is
	 * in, by id; its read is of every object linked to it. */
	NSString *_linkNodeId;
	/* While the read is planned by the link's value, not the key's. */
	BOOL _linkValue;
	ORMCoreDataMapping *_mapping;
	/* The objects it owns, by group ("contact", "contact/shippingAddress"),
	 * each its node; their names in outline order. */
	NSMutableDictionary<NSString *, ORMQueryNode *> *_groupNodes;
	NSMutableArray<NSString *> *_groupNames;
	/* The flow's screen it is shown as: its transitions, its actions. */
	ORMFlow *_flow;
	ORMFlowScreen *_screen;
	/* What each node is (docs/FORMS.md, The definition); a repeat's is the
	 * form's it is in. */
	ORMFormDefinition *_definition;
	/* A repeat's place in the outermost form's instance: its rows' path
	 * ("purchaseLines", "purchaseLines/serials"); nil for that form. */
	NSString *_repeatPath;
	/* The value nodes that are aggregates (D14): worked out over rows, by
	 * the document and by the app, not read. */
	NSMutableSet<NSString *> *_aggregateNodes;
	/* Each aggregate's element: its function and the path to its values. */
	NSMutableDictionary<NSString *, NSDictionary *> *_aggregateOf;
	/* A repeat's own: its rows only read (D9), and where the key they are
	 * linked to is in the form it is in: an element's value (a list of what
	 * the form refers to), or an owned object (its group); the anchor's key
	 * for neither. */
	BOOL _isList;
	NSString *_from;
	NSString *_fromGroup;
	/* A repeat's in a subtype part (+ is Service: its lines): the subentity
	 * its rows are of the object only where it is one of. */
	NSString *_subtype;
	/* What each text of _checked is of, by the text. */
	NSMutableDictionary<NSString *, NSString *> *_sourceOfCheck;
	/* The forms it is made with, and, where it is one of several anchors,
	 * its form's name: what its instance's element, its choices and reads
	 * are named by. */
	NSArray<ORMFormDocument *> *_parts;
	NSString *_partName;
	/* The steps through a derived fact type whose derivation branches (a
	 * unit price, of a cost and a volume), by id: a maybe the planner
	 * cannot take, so each read of its own, by the key. */
	NSMutableSet<NSString *> *_ownReads;
	/* The steps to the objects a set of choices picks (D17), by id: read
	 * each on its own, by the key, as the rows of the facts. */
	NSMutableSet<NSString *> *_choiceSets;
}

#pragma mark The form's parts

/* The form as the document keeps it; nil for one not there. */
static ORMStoredQuery *
ORMStoredForm(ORMModel *model, NSString *identifier)
{
	for (ORMStoredQuery *each in model.storedQueries) {
		if ([each.identifier isEqualToString:identifier]) {
			return each;
		}
	}
	return nil;
}

/* The roles of a compound's parts (Money: its amount's, its currency's),
 * where the node's type is one; nil otherwise. */
static NSArray<ORMRole *> *
ORMPartsOf(ORMQueryNode *node)
{
	return node.isValue || node.objectType == nil ? nil : [ORMQuery partRolesOf:node.objectType];
}

/* Whether a step from the node goes to one of its parts. */
static BOOL
ORMIsPartStep(ORMQueryStep *step, NSArray<ORMRole *> *parts)
{
	for (ORMRole *part in parts) {
		if (part.factType == step.factType) {
			return YES;
		}
	}
	return NO;
}

/* The entity's property of the name, its parents' too. */
static ORMCDProperty *
ORMPropertyOf(ORMCDModel *coreData, NSString *entityName, NSString *name)
{
	for (ORMCDEntity *entity = [coreData entityNamed:entityName ?: @""]; entity != nil;
	     entity = [coreData entityNamed:entity.parentName ?: @""]) {
		ORMCDProperty *property = [entity propertyNamed:name];
		if (property != nil) {
			return property;
		}
	}
	return nil;
}

/* The schema type of an attribute, a value type's temporal type telling a
 * date from a moment. */
static NSString *
ORMSchemaTypeOf(ORMCDAttribute *attribute, ORMObjectType *valueType)
{
	NSString *typeName = valueType.dataType.typeName ?: @"";
	if ([typeName hasPrefix:@"DateAndTime"] || [typeName hasPrefix:@"AutoTimestamp"]) {
		return @"xsd:dateTime";
	}
	if ([typeName hasPrefix:@"Date"]) {
		return @"xsd:date";
	}
	if ([typeName hasPrefix:@"Time"]) {
		return @"xsd:time";
	}
	NSDictionary *types = @{
		@"Integer 16" : @"xsd:integer", @"Integer 32" : @"xsd:integer", @"Integer 64" : @"xsd:integer",
		@"Decimal" : @"xsd:decimal", @"Double" : @"xsd:double", @"Float" : @"xsd:double",
		@"Boolean" : @"xsd:boolean", @"Date" : @"xsd:dateTime", @"Binary" : @"xsd:base64Binary",
	};
	return [types objectForKey:attribute.attributeType ?: @""] ?: @"xsd:string";
}

/* A node's label: its role's name, else its type's. */
/* The anchor's own steps: its, and its subtype parts' (+ is FillUp). */
static NSArray<ORMQueryStep *> *
ORMAnchorsOwnSteps(ORMQuery *form)
{
	NSMutableArray *steps = [NSMutableArray array];
	NSMutableArray *nodes = [NSMutableArray arrayWithObject:form.root];
	while ([nodes count] > 0) {
		ORMQueryNode *node = [nodes firstObject];
		[nodes removeObjectAtIndex:0];
		for (ORMQueryStep *step in node.steps) {
			[steps addObject:step];
			if ([step isSubtyping]) {
				[nodes addObjectsFromArray:step.nodes];
			}
		}
	}
	return steps;
}

static NSString *
ORMLabelOf(ORMRole *role, ORMObjectType *type)
{
	return [role.name length] > 0 ? role.name : (type.name ?: @"");
}

/* "drives Vehicle1" in "had driver User / drives Vehicle1": the nodes
 * below the node that are the same object as one outside it, with that one. */
static NSArray<NSArray<ORMQueryNode *> *> *
ORMSharedNodes(ORMQuery *form, ORMQueryNode *node)
{
	NSMutableSet *inside = [NSMutableSet set];
	NSMutableArray *stack = [NSMutableArray arrayWithObject:node];
	while ([stack count] > 0) {
		ORMQueryNode *each = [stack lastObject];
		[stack removeLastObject];
		[inside addObject:each.identifier];
		for (ORMQueryStep *step in each.steps) {
			[stack addObjectsFromArray:step.nodes];
		}
	}
	NSMutableArray *shared = [NSMutableArray array];
	for (ORMQueryNode *each in [form nodes]) {
		if (![inside containsObject:each.identifier] || each == node || each.label == nil) {
			continue;
		}
		for (ORMQueryNode *other in [form nodes]) {
			if (![inside containsObject:other.identifier] && other.objectType == each.objectType
			    && [other.label isEqualToString:each.label]) {
				[shared addObject:@[ each, other ]];
				break;
			}
		}
	}
	return shared;
}

#pragma mark Making it

+ (instancetype)documentForForm:(ORMQuery *)form
                          model:(ORMModel *)model
                        mapping:(ORMCoreDataMapping *)mapping
                         reason:(NSString **)reason
{
	ORMFormDocument *document = [[ORMFormDocument alloc] init];
	NSString *why = [document makeForm:form model:model mapping:mapping];
	if (why != nil) {
		if (reason != NULL) {
			*reason = why;
		}
		return nil;
	}
	return document;
}

- (NSString *)makeForm:(ORMQuery *)form model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	if (form.kind != ORMQueryForm || form.root == nil) {
		return @"It is no form.";
	}
	ORMStoredQuery *stored = ORMStoredForm(model, form.identifier);
	if (stored == nil) {
		return @"The form is not in the model.";
	}
	/* An outline that breaks a rule of the definition is no form: never
	 * generated, each rule broken said. */
	_definition = [ORMFormDefinition definitionOfForm:form model:model mapping:mapping];
	if ([_definition.problems count] > 0) {
		return [@"The outline is no form. " stringByAppendingString:[[_definition.problems valueForKey:@"text"]
		                                                                componentsJoinedByString:@" "]];
	}
	NSString *why = [self makeForm:form stored:stored model:model mapping:mapping];
	if (why != nil) {
		return why;
	}
	/* Each form it is made with: a document of its own, what it misses
	 * this one's. */
	NSMutableArray *parts = [NSMutableArray array];
	for (NSString *formId in form.withFormIds) {
		ORMQuery *other = [ORMQuery queryWithId:formId inModel:model];
		NSString *partWhy = nil;
		ORMFormDocument *part = other != nil ? [ORMFormDocument documentForForm:other model:model mapping:mapping reason:&partWhy] : nil;
		if (part == nil) {
			return [NSString stringWithFormat:@"%@, a form it is made with: %@", other.name ?: formId, partWhy ?: @"not in the model."];
		}
		for (NSString *each in part.missing) {
			[_missing addObject:[NSString stringWithFormat:@"%@: %@", other.name, each]];
		}
		[_missingIds unionSet:part.missingIds];
		[part namePart:other.name];
		[parts addObject:part];
	}
	_parts = parts;
	if ([parts count] > 0) {
		[self namePart:form.name];
	}
	return nil;
}

- (NSString *)makeForm:(ORMQuery *)form stored:(ORMStoredQuery *)stored model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	_form = form;
	_model = model;
	_stored = stored;
	_mapping = mapping;
	_repeatSteps = [NSMutableDictionary dictionary];
	_repeats = [NSMutableDictionary dictionary];
	_planner = [[ORMQueryPlanner alloc] initWithModel:model mapping:mapping];
	/* A form reads and saves a store's objects, each with its own key. */
	_planner.identifiesByOwnKeys = YES;
	_verbalizer = [[ORMVerbalizer alloc] initWithModel:model];
	_fields = [NSMutableArray array];
	_notes = [NSMutableArray array];
	_missing = [NSMutableArray array];
	_missingIds = [NSMutableSet set];
	_checked = [NSMutableArray array];
	_binds = [NSMutableDictionary dictionary];
	_warnings = [NSMutableArray array];
	_conditionSteps = [NSMutableSet set];
	_groupNodes = [NSMutableDictionary dictionary];
	_groupNames = [NSMutableArray array];
	_elementOfNode = [NSMutableDictionary dictionary];
	_sourceOfCheck = [NSMutableDictionary dictionary];
	_ownReads = [NSMutableSet set];
	for (ORMQueryNode *node in [form nodes]) {
		for (ORMQueryStep *step in node.steps) {
			ORMQuery *derivation = [ORMQuery derivationOf:step.factType inModel:model];
			BOOL branches = NO;
			for (ORMQueryNode *each in [derivation nodes]) {
				branches = branches || [each.steps count] > 1;
			}
			/* Shown: one entered is the form's to assert (a semiderived
			 * cost, worked out for others), read with the anchor. Not
			 * stored: one stored is in its column, read with the anchor
			 * (a service's total, worked out as it is saved). */
			if (branches && node == form.root && ![step.factType isUnary]
			    && [[step.nodes firstObject] formPart] == ORMFormPartShown && ![step.factType derivationRule].isStored) {
				[_ownReads addObject:step.identifier];
			}
		}
	}
	_choiceSets = [NSMutableSet set];
	for (ORMQueryNode *node in [form nodes]) {
		for (ORMQueryStep *step in node.steps) {
			if ([_definition isChoiceSet:step] && node == form.root) {
				[_choiceSets addObject:step.identifier];
			}
		}
	}
	_aggregateNodes = [NSMutableSet set];
	_aggregateOf = [NSMutableDictionary dictionary];
	for (ORMQueryNode *node in [form nodes]) {
		if (node.isValue && node.expression.kind == ORMQueryExpressionAggregate) {
			[_aggregateNodes addObject:node.identifier];
		}
	}
	_unarySteps = [NSMutableDictionary dictionary];
	for (ORMQueryStep *step in [self flagSteps]) {
		if (step.formPart != ORMFormPartNone && [step.factType isUnary]) {
			[_unarySteps setObject:step forKey:step.identifier];
		}
	}
	/* A choice's conditions (D5); its other steps are read, its key
	 * entered (D6) or what is shown through it (D7). */
	for (ORMQueryNode *node in [form nodes]) {
		if (node != form.root && !node.isValue && node.formPart == ORMFormPartEntered && ORMPartsOf(node) == nil) {
			for (ORMQueryStep *step in node.steps) {
				if ([self isCondition:step]) {
					[_conditionSteps addObject:step.identifier];
				}
			}
		}
	}
	ORMQueryPlan *plan = [self readPlanForKey:nil];
	if (plan.entityName == nil) {
		return [plan.notes count] > 0 ? [NSString stringWithFormat:@"The form's read cannot be planned: %@", [plan.notes componentsJoinedByString:@" "]]
		                              : [NSString stringWithFormat:@"The mapping places no entity for %@.", form.root.objectType.name];
	}
	_entityName = [plan.entityName copy];
	[_notes addObjectsFromArray:plan.notes];
	[self placeNodesIn:plan];
	[self placeUnariesIn:plan];
	[self bindValues];
	[self bindConstraints];
	[self bindIdentifications];
	[self makeRepeats];
	[self bindAggregates];
	[self findMissing];
	return nil;
}

/* The unary steps the form has flags of, in outline order: entered or shown
 * on what it makes or changes (D10), shown through what it refers to (D7);
 * without a definition, the anchor's own. */
- (NSArray<ORMQueryStep *> *)flagSteps
{
	NSMutableArray *steps = [NSMutableArray array];
	for (ORMQueryNode *node in [_form nodes]) {
		for (ORMQueryStep *step in node.steps) {
			NSString *rule = [_definition ruleOf:step.identifier];
			BOOL flag = _definition != nil ? [rule isEqualToString:@"D10"] || [rule isEqualToString:@"D7"]
			                               : [ORMAnchorsOwnSteps(_form) containsObject:step];
			if ([step.factType isUnary] && step.formPart != ORMFormPartNone && flag) {
				[steps addObject:step];
			}
		}
	}
	return steps;
}

/* The keys from the anchor to the node's object, its subtype steps none:
 * as a read of the anchor and the node, by the steps between them alone,
 * has them. @[] for the anchor and its parts; nil where none such reads. */
- (NSArray<NSString *> *)keysToObject:(ORMQueryNode *)node
{
	ORMQueryNode *object = node;
	while (object.step != nil && [object.step isSubtyping]) {
		object = object.step.parent;
	}
	if (object == _form.root || object == nil) {
		return @[];
	}
	ORMStoredQuery *copy = [_stored copy];
	copy.identifier = [_stored.identifier stringByAppendingString:@"-to"];
	copy.kind = nil;
	ORMQueryPart *target = nil;
	for (ORMQueryPart *part in [copy.root tree]) {
		target = !part.isStep && [part.identifier isEqualToString:object.identifier] ? part : target;
	}
	NSMutableSet *path = [NSMutableSet set];
	for (ORMQueryPart *each = target; each != nil; each = [each parent]) {
		[path addObject:[NSValue valueWithNonretainedObject:each]];
	}
	NSMutableArray *off = [NSMutableArray array];
	for (ORMQueryPart *part in [copy.root tree]) {
		if ((part.isStep || part.isValue) && ![path containsObject:[NSValue valueWithNonretainedObject:part]]
		    && ![path containsObject:[NSValue valueWithNonretainedObject:[part parent]]]) {
			[off addObject:part];
		}
		part.projected = part == target || part == copy.root ? @"true" : nil;
		part.part = nil;
		part.given = nil;
		part.label = nil;
		part.comparison = nil;
		part.value = nil;
		part.compareTo = nil;
		part.operatorName = nil;
	}
	for (ORMQueryPart *part in off) {
		[part detach];
	}
	if (target == nil) {
		return nil;
	}
	ORMQueryPlan *plan = [self plan:copy];
	ORMPlanColumn *column = [plan columnOfNode:object.identifier];
	return column != nil ? [plan trailOfColumn:column] : nil;
}

/* Whether the objects between the anchor and the node, and the node's own
 * where it is one, are all the form's to make or change. */
- (BOOL)ownsAllAbove:(ORMQueryNode *)node including:(BOOL)itself
{
	NSMutableArray *objects = [[self objectsAbove:node] mutableCopy];
	ORMQueryNode *object = node;
	while (object.step != nil && [object.step isSubtyping]) {
		object = object.step.parent;
	}
	if (itself && object != _form.root) {
		[objects addObject:object];
	}
	for (ORMQueryNode *each in objects) {
		if (![self ownsNode:each]) {
			return NO;
		}
	}
	return YES;
}

/* Each owned object up to the keys' end its group ("contact",
 * "contact/shippingAddress"), the objects in the same order. */
- (void)addGroups:(NSArray<NSString *> *)toObject objects:(NSArray<ORMQueryNode *> *)objects
{
	for (NSUInteger i = 0; i < [objects count] && i < [toObject count]; i++) {
		NSString *group = [[toObject subarrayWithRange:NSMakeRange(0, i + 1)] componentsJoinedByString:@"/"];
		if ([_groupNodes objectForKey:group] == nil) {
			[_groupNodes setObject:[objects objectAtIndex:i] forKey:group];
			[_groupNames addObject:group];
		}
	}
}

/* "purchaseOrderSupplierTaxNumber": keys as one name, read through. */
static NSString *
ORMThroughName(NSArray<NSString *> *keys)
{
	NSMutableString *name = [NSMutableString stringWithString:[keys firstObject] ?: @""];
	for (NSString *each in [keys subarrayWithRange:NSMakeRange(1, [keys count] > 0 ? [keys count] - 1 : 0)]) {
		[name appendString:[[[each substringToIndex:1] uppercaseString] stringByAppendingString:[each substringFromIndex:1]]];
	}
	return name;
}

/* Whether a step from a choice is one of its conditions: the definition
 * says each node it reaches is (D5). */
- (BOOL)isCondition:(ORMQueryStep *)step
{
	if (_definition == nil) {
		return YES;
	}
	if ([step.factType isUnary]) {
		return [[_definition ruleOf:step.identifier] isEqualToString:@"D5"];
	}
	for (ORMQueryNode *node in step.nodes) {
		if (![[_definition ruleOf:node.identifier] isEqualToString:@"D5"]) {
			return NO;
		}
	}
	return [step.nodes count] > 0;
}

/* What the model marks for the form (entered, shown, given, computed) and
 * no element is placed as, its own or a repeat's: the form leaves out what
 * the model says it has, why in the notes. */
- (void)findMissing
{
	for (ORMQueryNode *node in [_form nodes]) {
		BOOL marked = node.formPart != ORMFormPartNone || node.isGiven || node.isValue;
		/* A repeat's link to the form it is in is the app's, said there. */
		if (!marked || node == _form.root || [self elementOfNode:node.identifier] != nil || [self isInRepeat:node]
		    || [node.identifier isEqualToString:_linkNodeId ?: @""]) {
			continue;
		}
		[_missing addObject:[NSString stringWithFormat:@"%@: the model has it in the form, and no element is made for it.",
		                                               [node designation]]];
		[_missingIds addObject:node.identifier];
	}
	for (ORMQueryNode *node in [_form nodes]) {
		for (ORMQueryStep *step in node.steps) {
			if (![step.factType isUnary] || step.formPart == ORMFormPartNone || [self elementOfNode:step.identifier] != nil
			    || [self isInRepeat:node]) {
				continue;
			}
			[_missing addObject:[NSString stringWithFormat:@"\"%@\": the model has it in the form, and no element is made for it.",
			                                               [step.factType displayText]]];
			[_missingIds addObject:step.identifier];
		}
	}
	[_missing sortUsingSelector:@selector(compare:)];
}

/* Whether a node hangs from a step to many whose repeat is made: placed
 * there, and what that misses said of it. */
- (BOOL)isInRepeat:(ORMQueryNode *)node
{
	for (ORMQueryStep *step = node.step; step != nil; step = step.parent.step) {
		NSString *name = [_repeatSteps objectForKey:step.identifier];
		if (name != nil && [_repeats objectForKey:name] != nil) {
			return YES;
		}
	}
	return NO;
}

- (NSArray<NSString *> *)missing
{
	return [_missing copy];
}

- (NSSet<NSString *> *)missingIds
{
	return [_missingIds copy];
}

/* The step to many nearest the anchor the node hangs from; nil for none. */
- (ORMQueryStep *)outermostToManyAbove:(ORMQueryNode *)node
{
	ORMQueryStep *found = nil;
	for (ORMQueryStep *step = node.step; step != nil; step = step.parent.step) {
		found = [_definition isToMany:step] ? step : found;
	}
	return found;
}

/* The form's step of the id, wherever it is. */
- (ORMQueryStep *)stepWithId:(NSString *)identifier
{
	for (ORMQueryNode *node in [_form nodes]) {
		for (ORMQueryStep *step in node.steps) {
			if ([step.identifier isEqualToString:identifier]) {
				return step;
			}
		}
	}
	return nil;
}

/* The step under the anchor the node hangs from; nil for the anchor. */
- (ORMQueryStep *)topStepOf:(ORMQueryNode *)node
{
	ORMQueryStep *step = node.step;
	while (step != nil && step.parent != _form.root) {
		step = step.parent.step;
	}
	return step;
}

/* Each step from the anchor to many, a form of its own: anchored on what
 * the step reaches (an order's line), its steps the step's, and given the
 * anchor by the same fact type the other way round, which its read is of
 * (every line of the order). */
- (void)makeRepeats
{
	for (NSString *stepId in [[_repeatSteps allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSString *name = [_repeatSteps objectForKey:stepId];
		ORMQueryPart *step = [_stored partWithId:stepId step:YES];
		ORMQueryPart *reached = [[step nodes] firstObject];
		ORMQueryStep *formStep = [self stepWithId:stepId];
		ORMQueryNode *reachedNode = [formStep.nodes firstObject];
		/* The object the rows are of: the anchor, an owned object, or one
		 * the form refers to. */
		ORMQueryNode *of = formStep.parent;
		while (of.step != nil && [of.step isSubtyping]) {
			of = of.step.parent;
		}
		if (step == nil || reached == nil || reachedNode.objectType == nil) {
			[_notes addObject:[NSString stringWithFormat:@"%@: a repeat of nothing the model has.", name]];
			continue;
		}
		ORMQueryPart *root = [reached copy];
		root.ref = reachedNode.objectType.identifier;
		root.roleId = nil;
		root.part = nil;
		root.given = nil;
		ORMQueryPart *back = [[ORMQueryPart alloc] init];
		back.identifier = [stepId stringByAppendingString:@"-of"];
		back.isStep = YES;
		back.ref = step.ref;
		back.roleId = reached.roleId;
		ORMQueryPart *anchor = [[ORMQueryPart alloc] init];
		anchor.identifier = [(of ?: _form.root).identifier stringByAppendingString:@"-of"];
		anchor.roleId = step.roleId;
		anchor.given = @"true";
		[back addPart:anchor];
		[root insertPart:back atIndex:0];
		ORMStoredQuery *stored = [[ORMStoredQuery alloc] init];
		stored.identifier = [NSString stringWithFormat:@"%@-%@", _stored.identifier, stepId];
		stored.name = [NSString stringWithFormat:@"%@.%@", _form.name ?: @"Form", name];
		stored.kind = @"Form";
		stored.root = root;
		ORMQuery *query = [ORMQuery queryOf:stored model:_model];
		ORMFormDocument *repeat = [[ORMFormDocument alloc] init];
		repeat->_linkNodeId = anchor.identifier;
		repeat->_definition = _definition;
		repeat->_isList = [_definition isList:formStep];
		if (of != nil && ![self isAnchorsOwn:of]) {
			if ([self ownsNode:of]) {
				repeat->_fromGroup = [[name componentsSeparatedByString:@"/"] count] > 1
					? [[[name componentsSeparatedByString:@"/"] subarrayWithRange:NSMakeRange(0, [[name componentsSeparatedByString:@"/"] count] - 1)]
					      componentsJoinedByString:@"/"] : nil;
			}
			repeat->_from = [self elementOfNode:of.identifier];
		}
		repeat->_repeatPath = _repeatPath != nil ? [NSString stringWithFormat:@"%@/%@", _repeatPath, name] : name;
		repeat->_subtype = [self subtypeEntityOf:reachedNode];
		NSString *why = query != nil ? [repeat makeForm:query stored:stored model:_model mapping:_mapping] : @"it cannot be read";
		if (why != nil) {
			[_notes addObject:[NSString stringWithFormat:@"%@: a repeat not made: %@", name, why]];
			continue;
		}
		/* Its rows relevant where the object is of the part they are in. */
		for (ORMFormField *field in repeat->_subtype != nil ? repeat.fields : @[]) {
			NSUInteger depth = [[name componentsSeparatedByString:@"/"] count] + [[field.elementName componentsSeparatedByString:@"/"] count];
			[[repeat bindOf:field].relevant addObject:[self kindTestOf:repeat->_subtype up:depth]];
		}
		[_notes addObjectsFromArray:repeat.notes];
		for (NSString *each in repeat.missing) {
			[_missing addObject:[NSString stringWithFormat:@"%@: %@", name, each]];
		}
		/* Rows written are each of one object of the form's, linked to it
		 * by its key; rows of a fact of many (a driver's vehicles) are not. */
		if (!repeat->_isList && repeat.linkElement == nil) {
			[_missing addObject:[NSString stringWithFormat:@"%@: rows entered that are not each of one %@, but facts of many: "
			                                               @"not written by a repeat.", name, of.objectType.name ?: @"object"]];
			[_missingIds addObject:stepId];
		}
		[_missingIds unionSet:repeat.missingIds];
		[_repeats setObject:repeat forKey:name];
	}
}

- (NSDictionary<NSString *, ORMFormDocument *> *)repeats
{
	return _repeats;
}

- (NSArray<ORMFormDocument *> *)parts
{
	return _parts ?: @[];
}

/* One of several anchors: named so, its repeats with it. */
- (void)namePart:(NSString *)name
{
	_partName = [name copy];
	for (ORMFormDocument *repeat in [_repeats allValues]) {
		[repeat namePart:name];
	}
}

/* A repeat's element that holds the key of the object of the form it is in
 * (an order's line's order); nil for a form that is no repeat. */
- (NSString *)linkElement
{
	return _linkNodeId != nil ? [_elementOfNode objectForKey:_linkNodeId] : nil;
}

/* The nodes the read lists: the anchor, what is entered, shown or given,
 * and what a value node computes with. */
- (NSSet<NSString *> *)listedNodes
{
	NSMutableSet *listed = [NSMutableSet setWithObject:_form.root.identifier];
	for (ORMQueryNode *node in [_form nodes]) {
		if (node.formPart != ORMFormPartNone || node.isGiven) {
			[listed addObject:node.identifier];
		}
		if (node.isValue) {
			[listed addObjectsFromArray:[node.expression nodeIds]];
		}
		/* What rows beyond the anchor are of: its key read, to link them. */
		for (ORMQueryStep *step in node.steps) {
			if (([_definition isRepeat:step] || [_definition isList:step]) && ![self isAnchorsOwn:node]) {
				[listed addObject:node.identifier];
			}
		}
	}
	return listed;
}

/* Whether a node the read lists is beneath the part. */
static BOOL
ORMListsBeneath(ORMQueryPart *part, NSSet<NSString *> *listed)
{
	for (ORMQueryPart *each in part.parts) {
		if ((!each.isStep && [listed containsObject:each.identifier]) || ORMListsBeneath(each, listed)) {
			return YES;
		}
	}
	return NO;
}

/* Whether the step leads on, from an object (owned, passed through,
 * chosen, given, a subtype's), to something listed: what is not there
 * leaves the row, the anchor's, in. Not from one absorbed into the row
 * above it (a volume's quantity): no object of its own to be missing. */
- (BOOL)passesOn:(ORMQueryPart *)step listed:(NSSet<NSString *> *)listed
{
	ORMQueryNode *from = [self nodeWithId:step.parent.identifier];
	return from != nil && ORMListsBeneath(step, listed)
	       && (from == _form.root || [_planner entityNameOfType:from.objectType] != nil);
}

- (ORMQueryPlan *)readPlanForKey:(NSString *)key
{
	ORMStoredQuery *copy = [_stored copy];
	copy.identifier = [_stored.identifier stringByAppendingString:@"-read"];
	copy.kind = nil;
	NSSet *listed = [self listedNodes];
	NSMutableArray *conditions = [NSMutableArray array];
	for (ORMQueryPart *part in [copy.root tree]) {
		if (part.isStep) {
			/* A unary entered or shown is read, not asked for. */
			/* A repeat's step is read by the repeat, row by row. */
			if ([_conditionSteps containsObject:part.identifier] || [_unarySteps objectForKey:part.identifier] != nil
			    || [_repeatSteps objectForKey:part.identifier] != nil || [_ownReads containsObject:part.identifier]
			    || [_choiceSets containsObject:part.identifier]) {
				[conditions addObject:part];
			} else if (part.operatorName == nil && (part.parent == copy.root || [self passesOn:part listed:listed])
			           && !(_linkNodeId != nil && [[[part nodes] firstObject].identifier isEqualToString:_linkNodeId])) {
				/* What is not given yet leaves no object out: the anchor's
				 * own, and what is listed further on (a contact's name, an
				 * order's supplier's). */
				part.operatorName = @"Maybe";
			}
			continue;
		}
		part.projected = [listed containsObject:part.identifier] ? @"true" : nil;
		part.part = nil;
		part.given = nil;
	}
	for (ORMQueryPart *step in conditions) {
		[step detach];
	}
	/* An aggregate is worked out over the rows, not read. */
	NSMutableArray *aggregates = [NSMutableArray array];
	for (ORMQueryPart *part in [copy.root tree]) {
		if (part.isValue && [_aggregateNodes containsObject:part.identifier]) {
			[aggregates addObject:part];
		}
	}
	for (ORMQueryPart *part in aggregates) {
		[part detach];
	}
	if (key != nil && _linkNodeId != nil && _linkValue) {
		/* A repeat's: every object linked to the one of the key. */
		ORMQueryPart *link = [copy partWithId:_linkNodeId step:NO];
		link.comparison = @"=";
		link.value = key;
	} else if (key != nil) {
		copy.root.comparison = @"=";
		copy.root.value = key;
	}
	ORMQueryPlan *plan = [self plan:copy];
	/* Each unary's flag, a column of its own. */
	NSMutableArray *columns = [NSMutableArray array];
	for (ORMQueryStep *step in [self flagSteps]) {
		NSString *attribute = [_unarySteps objectForKey:step.identifier] != nil ? [_planner attributeOfUnaryStep:step] : nil;
		NSArray *keys = attribute != nil ? [self keysToObject:step.parent] : nil;
		if (keys != nil) {
			/* A subtype part's (a fill-up's "filled the tank" in a record's
			 * form): read as that subtype, nothing where it is not one. An
			 * object's beyond the anchor, by the keys to it. */
			NSString *subtype = [keys count] == 0 ? [self subtypeEntityOfStep:step] : nil;
			ORMPlanPath *path = subtype != nil ? [ORMPlanPath pathFrom:nil steps:@[ [ORMPlanStep stepAsEntity:subtype], [ORMPlanStep stepWithKey:attribute] ]]
			                                   : [ORMPlanPath pathFrom:nil keys:[keys arrayByAddingObject:attribute]];
			[columns addObject:[ORMPlanColumn columnTitled:[step.factType displayText]
			                                          node:step.identifier
			                                          path:path
			                                    identifier:nil]];
		}
	}
	if ([columns count] == 0 || plan.entityName == nil) {
		return plan;
	}
	ORMQueryPlan *flagged = [ORMQueryPlan planReading:plan.entityName
	                                            where:plan.condition
	                                          columns:[plan.columns arrayByAddingObjectsFromArray:columns]
	                                            sorts:plan.sorts
	                                            notes:plan.notes
	                                      definitions:plan.definitions];
	flagged.rowSorts = plan.rowSorts;
	return flagged;
}

/* What reads a derived value on its own (a unit price): the anchor of the
 * key, the one step to it, the node listed; nil for none such. */
- (ORMQueryPlan *)ownReadOf:(NSString *)nodeId key:(NSString *)key
{
	ORMQueryNode *node = [self nodeWithId:nodeId];
	BOOL picked = node.step != nil && [_choiceSets containsObject:node.step.identifier];
	if (node.step == nil || !([_ownReads containsObject:node.step.identifier] || picked)) {
		return nil;
	}
	ORMStoredQuery *copy = [_stored copy];
	copy.identifier = [NSString stringWithFormat:@"%@-read-%@", _stored.identifier, nodeId];
	copy.kind = nil;
	NSMutableArray *off = [NSMutableArray array];
	for (ORMQueryPart *part in [copy.root tree]) {
		if (part.isStep && part.parent == copy.root && ![part.identifier isEqualToString:node.step.identifier]) {
			[off addObject:part];
		}
		if (part.isValue && part.parent == copy.root) {
			[off addObject:part];
		}
		/* A set of choices': the objects picked, not their conditions. */
		if (picked && part.isStep && [part.parent.identifier isEqualToString:nodeId]) {
			[off addObject:part];
		}
		part.projected = !part.isStep && ([part.identifier isEqualToString:nodeId] || part == copy.root) ? @"true" : nil;
		part.part = nil;
		part.given = nil;
	}
	for (ORMQueryPart *part in off) {
		[part detach];
	}
	copy.root.comparison = @"=";
	copy.root.value = key;
	return [self plan:copy];
}

/* A query not in the model, planned as the planner plans one that is: each
 * step through a derived fact type expanded first. */
- (ORMQueryPlan *)plan:(ORMStoredQuery *)stored
{
	NSMutableArray *notes = [NSMutableArray array];
	ORMStoredQuery *expanded = [ORMQuery expansionOf:stored model:_model notes:notes];
	if (expanded == nil) {
		return [ORMQueryPlan planReading:nil where:nil columns:@[] sorts:@[] notes:notes];
	}
	return [_planner planForQuery:[ORMQuery queryOf:expanded model:_model]];
}

/* Each listed node's elements, from its column: a value, a reference's
 * key, a compound's parts as the mapping absorbs them. */
- (void)placeNodesIn:(ORMQueryPlan *)plan
{
	NSSet *listed = [self listedNodes];
	ORMCDModel *coreData = _planner.coreData;
	for (ORMQueryNode *node in [_form nodes]) {
		if (![listed containsObject:node.identifier]) {
			continue;
		}
		ORMPlanColumn *column = [plan columnOfNode:node.identifier];
		NSString *name = [node designation];
		if ([_aggregateNodes containsObject:node.identifier]) {
			[self addField:node.identifier name:[self elementNameOfValue:node] kind:ORMFormFieldCalculated type:@"xsd:decimal"];
			continue;
		}
		/* A set of choices (D17): the objects picked, by the relationship
		 * to them, each one's key; read on its own. */
		if (node.step != nil && [_choiceSets containsObject:node.step.identifier]) {
			ORMQueryPlan *own = [self ownReadOf:node.identifier key:@""];
			ORMPlanColumn *picked = [own columnOfNode:node.identifier];
			NSArray *keys = picked != nil ? [own trailOfColumn:picked] : nil;
			if ([keys count] != 1 || picked.identifierKey == nil) {
				[_notes addObject:[NSString stringWithFormat:@"%@: the mapping places it nowhere.", name]];
				continue;
			}
			ORMFormField *field = [self fieldFor:node keys:keys key:picked.identifierKey type:node.objectType];
			field.isMany = YES;
			field.schemaType = @"xsd:string";
			continue;
		}
		/* A derived value read on its own: calculated, its own read. */
		if (node.step != nil && [_ownReads containsObject:node.step.identifier]) {
			[self addField:node.identifier name:[self elementNameOfValue:node] kind:ORMFormFieldCalculated
			          type:[node isNumeric] ? @"xsd:decimal" : @"xsd:string"];
			continue;
		}
		if (column == nil) {
			[_notes addObject:[NSString stringWithFormat:@"%@: the mapping places it nowhere.", name]];
			continue;
		}
		BOOL hidden = node.formPart == ORMFormPartNone && !node.isGiven && node != _form.root;
		/* An owned object rows are of (a contact's phones): its key, in its
		 * group, read to link them. */
		if (node != _form.root && [self ownsNode:node] && column.identifierKey != nil && [plan trailOfColumn:column] != nil) {
			NSArray *toObject = [plan trailOfColumn:column];
			NSArray *path = [toObject arrayByAddingObject:column.identifierKey];
			ORMCDAttribute *attribute = (ORMCDAttribute *)ORMPropertyOf(coreData, [self entityAtKeys:toObject], column.identifierKey);
			ORMFormField *field = [self addField:node.identifier name:[path componentsJoinedByString:@"/"] kind:ORMFormFieldValue
			                                type:[attribute isKindOfClass:[ORMCDAttribute class]] ? ORMSchemaTypeOf(attribute, nil) : @"xsd:string"];
			field.keys = path;
			field.isHidden = YES;
			field.groupName = [toObject componentsJoinedByString:@"/"];
			[self addGroups:toObject objects:[[self objectsAbove:node] arrayByAddingObject:node]];
			continue;
		}
		if (column.value != nil || node.isValue) {
			ORMFormField *field = [self addField:node.identifier
			                                name:[self elementNameOfValue:node]
			                                kind:ORMFormFieldCalculated
			                                type:[node isNumeric] ? @"xsd:decimal" : @"xsd:string"];
			field.isHidden = hidden;
			continue;
		}
		/* From the object read: a maybe's step binds a variable on the way. */
		NSArray *keys = [plan trailOfColumn:column];
		if (keys == nil) {
			[_notes addObject:[NSString stringWithFormat:@"%@: not reached from the anchor alone.", name]];
			continue;
		}
		/* From a subtype part's subentity (+ is Service: its lines). */
		NSString *entity = [self subtypeEntityOf:node] ?: _entityName;
		NSUInteger firstMany = NSNotFound;
		for (NSUInteger k = 0; k < [keys count]; k++) {
			ORMCDRelationship *relationship = (ORMCDRelationship *)ORMPropertyOf(coreData, entity, [keys objectAtIndex:k]);
			if ([relationship isKindOfClass:[ORMCDRelationship class]]) {
				firstMany = firstMany == NSNotFound && relationship.toMany ? k : firstMany;
				entity = relationship.destination;
			}
		}
		if (firstMany != NSNotFound) {
			/* Under a step to many: a repeat's, or a list's (D8, D9), its
			 * rows named by the keys to them ("purchaseLines"); of an owned
			 * object, in its group ("contact/phones"); of what the form
			 * refers to, read through it ("driverVehicles"). */
			ORMQueryStep *many = [self outermostToManyAbove:node];
			ORMQueryNode *from = many.parent;
			NSArray *toFrom = [keys subarrayWithRange:NSMakeRange(0, firstMany)];
			NSString *relationship = [keys objectAtIndex:firstMany];
			if ([node.identifier isEqualToString:_linkNodeId ?: @""]) {
				/* A repeat's link back to what its rows are of, through a fact of
				 * many (a vehicle's drivers): no element, no repeat of its own. */
			} else if (many == nil || !([_definition isRepeat:many] || [_definition isList:many])) {
				[_notes addObject:[NSString stringWithFormat:@"%@: one of many, by no repeat or list.", name]];
			} else if ([self isAnchorsOwn:from]) {
				[_repeatSteps setObject:relationship forKey:many.identifier];
			} else if ([self ownsAllAbove:from including:YES]) {
				[_repeatSteps setObject:[[toFrom arrayByAddingObject:relationship] componentsJoinedByString:@"/"] forKey:many.identifier];
			} else {
				[_repeatSteps setObject:ORMThroughName([toFrom arrayByAddingObject:relationship]) forKey:many.identifier];
			}
			continue;
		}
		if (node == _form.root) {
			NSString *keyName = column.identifierKey ?: [[column.identifierParts firstObject] firstObject];
			if (keyName != nil) {
				ORMCDAttribute *attribute = (ORMCDAttribute *)ORMPropertyOf(coreData, _entityName, keyName);
				[self addField:node.identifier name:keyName kind:ORMFormFieldValue
				          type:[attribute isKindOfClass:[ORMCDAttribute class]] ? ORMSchemaTypeOf(attribute, nil) : @"xsd:string"];
			}
			continue;
		}
		if (column.identifierParts != nil) {
			/* The anchor's, its own properties; an owned object's (a
			 * contact's limit), its group's; else read through what the form
			 * refers to (an order's total). */
			NSArray *parts = ORMPartsOf(node);
			NSUInteger index = 0;
			NSString *subtype = [self subtypeEntityOf:node];
			NSArray *above = [self objectsAbove:node];
			NSString *entity = [self entityAtKeys:keys from:subtype ?: _entityName];
			if ([above count] != [keys count] || entity == nil) {
				[_notes addObject:[NSString stringWithFormat:@"%@: not reached from the anchor alone.", name]];
				continue;
			}
			BOOL owned = [self ownsAllAbove:node including:NO];
			for (NSArray<NSString *> *partKeys in column.identifierParts) {
				ORMRole *partRole = index < [parts count] ? [parts objectAtIndex:index] : nil;
				NSString *property = [partKeys firstObject];
				NSArray *path = [keys arrayByAddingObject:property];
				NSString *partName = [keys count] == 0 ? [self nameOf:property subtype:subtype]
				                     : owned ? [path componentsJoinedByString:@"/"] : ORMThroughName(path);
				ORMFormField *field = [self fieldFor:node entity:entity property:property name:partName
				                                 key:[partKeys count] == 2 ? [partKeys lastObject] : nil type:partRole.player];
				if (![field.nodeId isEqualToString:node.identifier]) {
					index++;
					continue;
				}
				field.isPart = YES;
				field.partIndex = index++;
				field.role = partRole;
				field.isHidden = hidden;
				field.subtypeEntity = subtype;
				if ([keys count] > 0) {
					field.keys = path;
					field.isThrough = !owned;
					field.groupName = owned ? [keys componentsJoinedByString:@"/"] : nil;
				}
			}
			if ([keys count] > 0 && owned) {
				[self addGroups:keys objects:above];
			}
			continue;
		}
		if ([keys count] > 1) {
			[self placeFarNode:node keys:keys key:column.identifierKey hidden:hidden];
			continue;
		}
		if ([keys count] != 1) {
			[_notes addObject:[NSString stringWithFormat:@"%@: not one of the anchor's own properties.", name]];
			continue;
		}
		NSString *subtype = [self subtypeEntityOf:node];
		ORMFormField *field = [self fieldFor:node entity:subtype ?: _entityName property:[keys firstObject]
		                                name:[self nameOf:[keys firstObject] subtype:subtype] key:column.identifierKey
		                                type:node.objectType];
		if ([field.nodeId isEqualToString:node.identifier]) {
			field.isHidden = hidden;
			field.subtypeEntity = subtype;
		}
	}
	[self placeSubtypeChoice];
}

/* A subtype's property's element: its name, unless the anchor's or
 * another subtype's has it (a trip's moment, "tripMoment"). */
- (NSString *)nameOf:(NSString *)property subtype:(NSString *)subtype
{
	ORMFormField *same = [self fieldNamed:property];
	if (subtype == nil || same == nil || [same.subtypeEntity isEqualToString:subtype]) {
		return property;
	}
	return [[[subtype substringToIndex:1] lowercaseString] stringByAppendingFormat:@"%@%@", [subtype substringFromIndex:1],
	                                                                                 [[[property substringToIndex:1] uppercaseString]
	                                                                                     stringByAppendingString:[property substringFromIndex:1]]];
}

/* The subtypes of its parts (+ is Trip, + is FillUp), in outline order. */
- (NSArray<NSString *> *)subtypeEntities
{
	NSMutableArray *subtypes = [NSMutableArray array];
	for (ORMFormField *field in _fields) {
		if (field.subtypeEntity != nil && ![subtypes containsObject:field.subtypeEntity]) {
			[subtypes addObject:field.subtypeEntity];
		}
	}
	return subtypes;
}

/* "Fill up" for FillUp: a subentity as a reader says its object type's
 * name, its words apart, the first capitalized (an acronym kept). */
- (NSString *)labelOfSubtype:(NSString *)entity
{
	NSString *name = entity;
	for (ORMObjectType *type in _model.objectTypes) {
		if ([[_planner entityNameOfType:type] isEqualToString:entity]) {
			name = type.name;
			break;
		}
	}
	NSMutableArray *words = [NSMutableArray array];
	NSMutableString *word = [NSMutableString string];
	NSCharacterSet *upper = [NSCharacterSet uppercaseLetterCharacterSet];
	for (NSUInteger i = 0; i < [name length]; i++) {
		unichar c = [name characterAtIndex:i];
		BOOL starts = [upper characterIsMember:c] && [word length] > 0
		              && (![upper characterIsMember:[word characterAtIndex:[word length] - 1]]
		                  || (i + 1 < [name length] && [[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:[name characterAtIndex:i + 1]]));
		if (starts || c == '_' || c == ' ') {
			if ([word length] > 0) {
				[words addObject:[word copy]];
			}
			[word setString:@""];
		}
		if (c != '_' && c != ' ') {
			[word appendFormat:@"%C", c];
		}
	}
	if ([word length] > 0) {
		[words addObject:word];
	}
	for (NSUInteger i = 1; i < [words count]; i++) {
		NSString *each = [words objectAtIndex:i];
		if (![[each uppercaseString] isEqualToString:each] || [each length] == 1) {
			[words replaceObjectAtIndex:i withObject:[each lowercaseString]];
		}
	}
	return [words count] > 0 ? [words componentsJoinedByString:@" "] : entity;
}

/* Where the form has subtype parts: which of them the object is, an
 * element after the key ("isA": "Trip"), entered. */
- (void)placeSubtypeChoice
{
	if ([[self subtypeEntities] count] == 0) {
		return;
	}
	NSString *name = [self fieldNamed:@"isA"] == nil ? @"isA" : @"isA_";
	ORMFormField *field = [[ORMFormField alloc] init];
	field.nodeId = [_form.root.identifier stringByAppendingString:@"-isA"];
	field.elementName = name;
	field.kind = ORMFormFieldSubtype;
	field.schemaType = @"xsd:string";
	[_fields insertObject:field atIndex:MIN((NSUInteger)1, [_fields count])];
}

- (ORMFormField *)subtypeField
{
	for (ORMFormField *field in _fields) {
		if (field.kind == ORMFormFieldSubtype) {
			return field;
		}
	}
	return nil;
}

/* Whether the form makes or changes the node's object along with the
 * anchor (a customer's contact, its address): an object reached by a step
 * that is no subtype's, neither entered, shown nor given (none to choose
 * it from), with something entered beneath it. */
- (BOOL)ownsNode:(ORMQueryNode *)node
{
	if (node == _form.root || node.isValue || node.isGiven || node.formPart != ORMFormPartNone || ORMPartsOf(node) != nil
	    || node.step == nil || [node.step isSubtyping] || !node.objectType.isEntity) {
		return NO;
	}
	return ORMEntersBeneath(node);
}

/* Something entered beneath the node, not under a reference entered. */
static BOOL
ORMEntersBeneath(ORMQueryNode *node)
{
	for (ORMQueryStep *step in node.steps) {
		if ([step.factType isUnary] && step.formPart == ORMFormPartEntered) {
			return YES;
		}
		for (ORMQueryNode *each in step.nodes) {
			if (each.formPart == ORMFormPartEntered
			    || (each.formPart == ORMFormPartNone && !each.isGiven && ORMEntersBeneath(each))) {
				return YES;
			}
		}
	}
	return NO;
}

/* The subentity of the subtype part the node is in (+ is Trip: Trip),
 * its steps down from the anchor all a subtype's; nil for the anchor's
 * own, and a subtype the mapping keeps in the anchor's entity. */
- (NSString *)subtypeEntityOf:(ORMQueryNode *)node
{
	NSMutableArray *chain = [NSMutableArray array];
	for (ORMQueryNode *each = node.step.parent; each != nil && each != _form.root; each = each.step.parent) {
		[chain insertObject:each atIndex:0];
	}
	NSString *found = nil;
	for (ORMQueryNode *each in chain) {
		if (![each.step isSubtyping]) {
			break;
		}
		NSString *entity = [_planner entityNameOfType:each.objectType];
		if ([self isSubentity:entity]) {
			found = entity;
		}
	}
	return found;
}

/* Whether the entity is one of the anchor's subentities (a Service of the
 * Records): a part to choose. A supertype of the anchor's (+ is Record from
 * a Document), or a subtype a rule derives and does not store (+ is Cost:
 * a record that cost money), is none: the same object, its facts the
 * anchor's. */
- (BOOL)isSubentity:(NSString *)entity
{
	if (entity == nil || [entity isEqualToString:_entityName ?: @""]) {
		return NO;
	}
	ORMCDModel *coreData = _planner.coreData;
	for (ORMCDEntity *each = [coreData entityNamed:entity]; each != nil; each = [coreData entityNamed:each.parentName ?: @""]) {
		if ([each.parentName isEqualToString:_entityName ?: @""]) {
			return YES;
		}
	}
	return NO;
}

/* Whether the node's facts are the anchor's own: it, or a subtype of it
 * the anchor is reached as (+ is Trip). */
- (BOOL)isAnchorsOwn:(ORMQueryNode *)node
{
	for (ORMQueryNode *each = node; each != nil; each = each.step.parent) {
		if (each == _form.root) {
			return YES;
		}
		if (![each.step isSubtyping]) {
			return NO;
		}
	}
	return NO;
}

/* The objects between the anchor and the node, the anchor's side first:
 * one a key each, a subtype's step none (the same object). */
- (NSArray<ORMQueryNode *> *)objectsAbove:(ORMQueryNode *)node
{
	NSMutableArray *above = [NSMutableArray array];
	for (ORMQueryNode *each = node.step.parent; each != nil && each != _form.root; each = each.step.parent) {
		if (![each.step isSubtyping]) {
			[above insertObject:each atIndex:0];
		}
	}
	return above;
}

/* The entity at the end of the keys from the anchor's. */
- (NSString *)entityAtKeys:(NSArray<NSString *> *)keys
{
	return [self entityAtKeys:keys from:_entityName];
}

- (NSString *)entityAtKeys:(NSArray<NSString *> *)keys from:(NSString *)base
{
	NSString *entity = base;
	for (NSString *key in keys) {
		ORMCDRelationship *relationship = (ORMCDRelationship *)ORMPropertyOf(_planner.coreData, entity, key);
		if (![relationship isKindOfClass:[ORMCDRelationship class]]) {
			return nil;
		}
		entity = relationship.destination;
	}
	return entity;
}

/* A node past the anchor's own properties, each step to one: in objects
 * the form owns (its contact's name), an element of their group, written
 * with the anchor; through an object it refers to (its order's supplier's
 * name), shown as it is read, never written. */
- (void)placeFarNode:(ORMQueryNode *)node keys:(NSArray<NSString *> *)keys key:(NSString *)key hidden:(BOOL)hidden
{
	NSArray *above = [self objectsAbove:node];
	NSArray *toObject = [keys subarrayWithRange:NSMakeRange(0, [keys count] - 1)];
	NSString *subtype = [self subtypeEntityOf:node];
	NSString *entity = [self entityAtKeys:toObject from:subtype ?: _entityName];
	if ([above count] != [toObject count] || entity == nil) {
		[_notes addObject:[NSString stringWithFormat:@"%@: not reached from the anchor alone.", [node designation]]];
		return;
	}
	BOOL owned = YES;
	for (ORMQueryNode *each in above) {
		owned = owned && [self ownsNode:each];
	}
	NSMutableString *name = [NSMutableString stringWithString:[keys firstObject]];
	for (NSString *each in [keys subarrayWithRange:NSMakeRange(1, [keys count] - 1)]) {
		if (owned) {
			[name appendFormat:@"/%@", each];
		} else {
			[name appendString:[[[each substringToIndex:1] uppercaseString] stringByAppendingString:[each substringFromIndex:1]]];
		}
	}
	/* A key of a choice's, entered: what finds the object chosen (D6). */
	NSString *identifies = !owned && [_definition identifiesChoice:node] ? [self elementOfNode:node.step.parent.identifier] : nil;
	ORMFormField *field = [self fieldFor:node entity:entity property:[keys lastObject] name:name key:key type:node.objectType];
	if (![field.nodeId isEqualToString:node.identifier]) {
		return;
	}
	field.keys = keys;
	field.isHidden = hidden;
	field.isThrough = !owned && identifies == nil;
	field.identifies = identifies;
	field.subtypeEntity = subtype;
	field.groupName = owned ? [toObject componentsJoinedByString:@"/"] : nil;
	for (NSUInteger i = 0; owned && i < [above count]; i++) {
		NSString *group = [[toObject subarrayWithRange:NSMakeRange(0, i + 1)] componentsJoinedByString:@"/"];
		if ([_groupNodes objectForKey:group] == nil) {
			[_groupNodes setObject:[above objectAtIndex:i] forKey:group];
			[_groupNames addObject:group];
		}
	}
}

/* Whether every object of the anchor's has the owned node's: each step
 * from the anchor to it a simple mandatory (a customer's contact). */
- (BOOL)needsObjectOf:(ORMQueryNode *)owned
{
	for (ORMQueryNode *each = owned; each != nil && each != _form.root; each = each.step.parent) {
		BOOL mandatory = NO;
		for (ORMConstraint *constraint in each.step.entryRole.constraints) {
			mandatory = mandatory || (constraint.kind == ORMMandatoryConstraint && constraint.isSimple && constraint.modality == ORMAlethic);
		}
		if (!mandatory && ![each.step isSubtyping]) {
			return NO;
		}
	}
	return YES;
}

- (NSArray<NSString *> *)groupNames
{
	return [_groupNames copy];
}

/* Each unary's flag: an element of its attribute's, a boolean. */
- (void)placeUnariesIn:(ORMQueryPlan *)plan
{
	for (ORMQueryStep *step in [self flagSteps]) {
		if ([_unarySteps objectForKey:step.identifier] == nil) {
			continue;
		}
		ORMPlanColumn *column = [plan columnOfNode:step.identifier];
		NSArray *keys = column.path.keys;
		if ([keys count] == 0) {
			[_notes addObject:[NSString stringWithFormat:@"\"%@\": the mapping keeps it in no attribute.",
			                                             [step.factType displayText]]];
			continue;
		}
		if ([keys count] == 1) {
			ORMFormField *field = [self addField:step.identifier name:[keys firstObject] kind:ORMFormFieldValue type:@"xsd:boolean"];
			field.subtypeEntity = [self subtypeEntityOfStep:step];
			continue;
		}
		/* An owned object's, in its group; else read through what the form
		 * refers to. */
		NSArray *toObject = [keys subarrayWithRange:NSMakeRange(0, [keys count] - 1)];
		BOOL owned = [self ownsAllAbove:step.parent including:YES];
		ORMFormField *field = [self addField:step.identifier name:owned ? [keys componentsJoinedByString:@"/"] : ORMThroughName(keys)
		                                kind:ORMFormFieldValue type:@"xsd:boolean"];
		field.keys = keys;
		field.isThrough = !owned;
		field.groupName = owned ? [toObject componentsJoinedByString:@"/"] : nil;
		if (owned) {
			NSMutableArray *objects = [[self objectsAbove:step.parent] mutableCopy];
			ORMQueryNode *object = step.parent;
			while (object.step != nil && [object.step isSubtyping]) {
				object = object.step.parent;
			}
			[objects addObject:object];
			[self addGroups:toObject objects:objects];
		}
	}
}

/* The subentity a step of a subtype part is from (+ is FillUp, + filled
 * the tank: FillUp); nil for the anchor's own. */
- (NSString *)subtypeEntityOfStep:(ORMQueryStep *)step
{
	if (step.parent == _form.root || step.parent == nil) {
		return nil;
	}
	NSString *entity = [_planner entityNameOfType:step.parent.objectType];
	return [self isSubentity:entity] ? entity : nil;
}

/* A value node's element: its name, as a property's is. */
- (NSString *)elementNameOfValue:(ORMQueryNode *)node
{
	NSString *name = node.name ?: [node designation];
	return [name length] > 0 ? [[[name substringToIndex:1] lowercaseString] stringByAppendingString:[name substringFromIndex:1]]
	                         : node.identifier;
}

/* The element at the key path from the anchor: a value, or (with a key) a
 * reference holding the key of the object at the path. */
- (ORMFormField *)fieldFor:(ORMQueryNode *)node keys:(NSArray<NSString *> *)keys key:(NSString *)key type:(ORMObjectType *)type
{
	return [self fieldFor:node entity:_entityName property:[keys firstObject] name:[keys firstObject] key:key type:type];
}

/* The element of the name for the entity's property: a value, or (with a
 * key) a reference holding the key of the object it refers to. */
- (ORMFormField *)fieldFor:(ORMQueryNode *)node
                    entity:(NSString *)entityName
                  property:(NSString *)property
                      name:(NSString *)name
                       key:(NSString *)key
                      type:(ORMObjectType *)type
{
	ORMCDModel *coreData = _planner.coreData;
	if (key == nil) {
		ORMCDAttribute *attribute = (ORMCDAttribute *)ORMPropertyOf(coreData, entityName, property);
		NSString *schemaType = [attribute isKindOfClass:[ORMCDAttribute class]] ? ORMSchemaTypeOf(attribute, [type valueType])
		                                                                        : @"xsd:string";
		ORMFormField *field = [self addField:node.identifier name:name kind:ORMFormFieldValue type:schemaType];
		if ([field.nodeId isEqualToString:node.identifier]) {
			field.role = node.role;
			field.keys = [name isEqualToString:property] ? nil : @[ property ];
		}
		return field;
	}
	ORMCDRelationship *relationship = (ORMCDRelationship *)ORMPropertyOf(coreData, entityName, property);
	NSString *destination = [relationship isKindOfClass:[ORMCDRelationship class]] ? relationship.destination : nil;
	ORMCDAttribute *keyAttribute = (ORMCDAttribute *)ORMPropertyOf(coreData, destination, key);
	NSString *schemaType = [keyAttribute isKindOfClass:[ORMCDAttribute class]] ? ORMSchemaTypeOf(keyAttribute, nil)
	                                                                           : @"xsd:string";
	ORMFormField *field = [self addField:node.identifier name:name kind:ORMFormFieldReference type:schemaType];
	if (![field.nodeId isEqualToString:node.identifier]) {
		return field;
	}
	field.entityName = destination;
	field.keyName = key;
	field.referredType = type;
	field.role = node.role;
	field.keys = [name isEqualToString:property] ? nil : @[ property ];
	return field;
}

- (ORMFormField *)addField:(NSString *)nodeId name:(NSString *)name kind:(ORMFormFieldKind)kind type:(NSString *)type
{
	if ([_elementOfNode objectForKey:nodeId] == nil) {
		[_elementOfNode setObject:name forKey:nodeId];
	}
	ORMFormField *existing = [self fieldNamed:name];
	if (existing != nil) {
		return existing;
	}
	ORMFormField *field = [[ORMFormField alloc] init];
	field.nodeId = nodeId;
	field.elementName = name;
	field.kind = kind;
	field.schemaType = type;
	[_fields addObject:field];
	return field;
}

- (NSArray<ORMFormField *> *)fields
{
	return [_fields copy];
}

- (ORMFormField *)fieldNamed:(NSString *)elementName
{
	for (ORMFormField *field in _fields) {
		if ([field.elementName isEqualToString:elementName]) {
			return field;
		}
	}
	return nil;
}

- (NSArray<ORMFormField *> *)fieldsOfNode:(NSString *)nodeId
{
	NSMutableArray *fields = [NSMutableArray array];
	for (ORMFormField *field in _fields) {
		if ([field.nodeId isEqualToString:nodeId]) {
			[fields addObject:field];
		}
	}
	return fields;
}

- (ORMFormBind *)bindOf:(ORMFormField *)field
{
	ORMFormBind *bind = [_binds objectForKey:field.elementName];
	if (bind == nil) {
		bind = [[ORMFormBind alloc] init];
		bind.field = field;
		[_binds setObject:bind forKey:field.elementName];
	}
	return bind;
}

/* What the element says: a constraint's own statement, not its fact
 * type's others. */
- (NSString *)sayElement:(NSString *)identifier
{
	NSArray *sentences = [_verbalizer sentencesForElement:identifier];
	NSMutableArray *own = [NSMutableArray array];
	for (ORMVerbalSentence *sentence in sentences) {
		if (sentence.kind == ORMVerbalStatement && [sentence.sourceId isEqualToString:identifier]) {
			[own addObject:[sentence text]];
		}
	}
	/* Said with another (a mandatory and a uniqueness as "exactly one"):
	 * the statements under the fact type's reading. */
	for (ORMVerbalSentence *sentence in [own count] == 0 ? sentences : @[]) {
		if (sentence.kind == ORMVerbalStatement && sentence.level > 0) {
			[own addObject:[sentence text]];
		}
	}
	if ([own count] > 0) {
		return [own componentsJoinedByString:@" "];
	}
	NSString *text = [ORMVerbalizer plainTextOfSentences:sentences];
	return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark What it says

/* An alert of a constraint's or rule's at the bind, its source kept: what
 * the app's words replace. */
- (void)alert:(NSString *)text of:(NSString *)source at:(ORMFormBind *)bind
{
	if (text == nil || [bind.alerts containsObject:text]) {
		return;
	}
	[bind.alerts addObject:text];
	if (source != nil) {
		[bind.sourceOfAlert setObject:source forKey:text];
	}
}

/* What the form cannot check, said, its source kept. */
- (void)check:(NSString *)text of:(NSString *)source
{
	if (text == nil || [_checked containsObject:text]) {
		return;
	}
	[_checked addObject:text];
	if (source != nil) {
		[_sourceOfCheck setObject:source forKey:text];
	}
}

/* The app's words for a constraint or rule, by its id or its name; nil for
 * none. */
- (NSString *)messageFor:(NSString *)source
{
	if (source == nil || [_messages count] == 0) {
		return nil;
	}
	NSString *said = [_messages objectForKey:source];
	if (said != nil) {
		return said;
	}
	id element = [_model elementWithId:source];
	NSString *name = [element respondsToSelector:@selector(name)] ? [element name] : nil;
	name = name ?: [ORMQuery queryWithId:source inModel:_model].name;
	return name != nil ? [_messages objectForKey:name] : nil;
}

/* A text as the app would say it: its source's message, else as it is. */
- (NSString *)say:(NSString *)text of:(NSString *)source
{
	return [self messageFor:source] ?: text;
}

- (NSString *)alertTextOf:(ORMFormBind *)bind
{
	NSMutableArray *said = [NSMutableArray array];
	for (NSString *alert in bind.alerts) {
		NSString *text = [self say:alert of:[bind.sourceOfAlert objectForKey:alert]];
		if (![said containsObject:text]) {
			[said addObject:text];
		}
	}
	return [said componentsJoinedByString:@" "];
}

#pragma mark Binds

/* "../totalAmount": an element from a sibling's context. */
static NSString *
ORMSibling(NSString *elementName)
{
	return [@"../" stringByAppendingString:elementName];
}

/* "../../address/city": an element from another's context, where either
 * may be in a group (an address's lines, its city). */
static NSString *
ORMPathFrom(NSString *from, NSString *to)
{
	NSMutableString *path = [NSMutableString string];
	for (NSUInteger i = [[from componentsSeparatedByString:@"/"] count]; i > 0; i--) {
		[path appendString:@"../"];
	}
	[path appendString:to];
	return path;
}

/* The expression in XPath over the paths to its nodes' elements; nil where
 * it uses what XPath cannot say (a function of moments, an aggregate). */
static NSString *
ORMXPathOfPaths(ORMQueryExpression *expression, NSDictionary<NSString *, NSString *> *paths)
{
	switch (expression.kind) {
	case ORMQueryExpressionNode: {
		NSString *path = [paths objectForKey:expression.nodeId];
		return path != nil ? [NSString stringWithFormat:@"number(%@)", path] : nil;
	}
	case ORMQueryExpressionConstant:
		return [expression.constant rangeOfString:@"''"].location == NSNotFound ? expression.constant : nil;
	case ORMQueryExpressionAggregate:
		return nil;
	case ORMQueryExpressionFunction:
		break;
	}
	NSMutableArray *arguments = [NSMutableArray array];
	for (ORMQueryExpression *argument in expression.arguments) {
		NSString *said = ORMXPathOfPaths(argument, paths);
		if (said == nil) {
			return nil;
		}
		[arguments addObject:said];
	}
	NSString *a = [arguments firstObject], *b = [arguments count] > 1 ? [arguments objectAtIndex:1] : nil;
	NSDictionary *infix = @{ @"add" : @"+", @"subtract" : @"-", @"multiply" : @"*", @"divide" : @"div" };
	NSString *operator= [infix objectForKey:expression.function];
	if (operator!= nil && b != nil) {
		return [NSString stringWithFormat:@"(%@ %@ %@)", a, operator, b];
	}
	if ([expression.function isEqualToString:@"negate"]) {
		return [NSString stringWithFormat:@"(-%@)", a];
	}
	if ([expression.function isEqualToString:@"round"] && b != nil) {
		ORMQueryExpression *places = [expression.arguments objectAtIndex:1];
		NSInteger n = places.kind == ORMQueryExpressionConstant ? [places.constant integerValue] : -1;
		if (n < 0 || n > 9) {
			return nil;
		}
		NSString *scale = [@"1" stringByPaddingToLength:(NSUInteger)n + 1 withString:@"0" startingAtIndex:0];
		return n == 0 ? [NSString stringWithFormat:@"round(%@)", a]
		              : [NSString stringWithFormat:@"(round(%@ * %@) div %@)", a, scale, scale];
	}
	if ([expression.function isEqualToString:@"abs"]) {
		return [NSString stringWithFormat:@"choose(%@ < 0, -%@, %@)", a, a, a];
	}
	if (([expression.function isEqualToString:@"min"] || [expression.function isEqualToString:@"max"]) && b != nil) {
		NSString *less = [expression.function isEqualToString:@"min"] ? @"<" : @">";
		return [NSString stringWithFormat:@"choose(%@ %@ %@, %@, %@)", a, less, b, a, b];
	}
	if ([expression.function isEqualToString:@"coalesce"] && b != nil) {
		return [NSString stringWithFormat:@"choose(string(%@) != 'NaN', %@, %@)", a, a, b];
	}
	return nil;
}

/* The same over the elements, from a sibling's context. */
static NSString *
ORMXPathOf(ORMQueryExpression *expression, NSDictionary<NSString *, NSString *> *elements)
{
	NSMutableDictionary *paths = [NSMutableDictionary dictionary];
	for (NSString *nodeId in elements) {
		[paths setObject:ORMSibling([elements objectForKey:nodeId]) forKey:nodeId];
	}
	return ORMXPathOfPaths(expression, paths);
}

/* "number(.) >= 0 and number(.) <= 100", ". = 'M' or . = 'F'": a value
 * constraint of a value at the context; nil for none it can say. */
static NSString *
ORMXPathOfValues(ORMValueConstraint *constraint)
{
	NSMutableArray *ranges = [NSMutableArray array];
	BOOL quoted = [constraint quotesValues];
	for (ORMValueRange *range in constraint.ranges) {
		NSString *min = range.minValue, *max = range.maxValue;
		if (quoted) {
			if ([min length] == 0 || ![min isEqualToString:max] || [min rangeOfString:@"'"].location != NSNotFound) {
				return nil;
			}
			[ranges addObject:[NSString stringWithFormat:@". = '%@'", min]];
			continue;
		}
		NSMutableArray *bounds = [NSMutableArray array];
		if ([min length] > 0) {
			[bounds addObject:[NSString stringWithFormat:@"number(.) %@ %@",
			                                             range.minInclusion == ORMRangeOpen ? @">" : @">=", min]];
		}
		if ([max length] > 0) {
			[bounds addObject:[NSString stringWithFormat:@"number(.) %@ %@",
			                                             range.maxInclusion == ORMRangeOpen ? @"<" : @"<=", max]];
		}
		if ([bounds count] == 0) {
			continue;
		}
		[ranges addObject:[bounds componentsJoinedByString:@" and "]];
	}
	if ([ranges count] == 0) {
		return nil;
	}
	return [ranges count] == 1 ? [ranges firstObject]
	                           : [NSString stringWithFormat:@"(%@)", [ranges componentsJoinedByString:@") or ("]];
}

/* A list of single text values: a select1's items; nil for others. */
static NSArray<NSString *> *
ORMItemsOf(ORMValueConstraint *values)
{
	if (![values quotesValues]) {
		return nil;
	}
	NSMutableArray *items = [NSMutableArray array];
	for (ORMValueRange *range in values.ranges) {
		if ([range.minValue length] == 0 || ![range.minValue isEqualToString:range.maxValue]) {
			return nil;
		}
		[items addObject:range.minValue];
	}
	return [items count] > 0 ? items : nil;
}

/* What each element's own facts say: its type, whether it must be given,
 * what values it may have, whether it is only shown, what computes it. */
- (void)bindValues
{
	NSDictionary *elements = _elementOfNode;
	for (ORMFormField *field in _fields) {
		ORMQueryNode *node = [self nodeWithId:field.nodeId];
		ORMFormBind *bind = [self bindOf:field];
		ORMQueryStep *unary = [_unarySteps objectForKey:field.nodeId];
		if (field.kind == ORMFormFieldSubtype) {
			/* One of them, where the anchor's own entity has no objects of
			 * its own. */
			if ([_planner.coreData entityNamed:_entityName].isAbstract) {
				[bind.required addObject:@"true()"];
			}
			continue;
		}
		if (field.subtypeEntity != nil) {
			[bind.relevant addObject:[self kindTestOf:field]];
		}
		if (unary != nil) {
			bind.readonly = unary.formPart == ORMFormPartShown;
			continue;
		}
		if (field.kind == ORMFormFieldCalculated && [_aggregateNodes containsObject:node.identifier]) {
			/* Over the rows, once they are made: -bindAggregates. */
			bind.readonly = YES;
			continue;
		}
		if (field.kind == ORMFormFieldCalculated) {
			bind.calculate = ORMXPathOf(node.expression, elements);
			/* A derived fact type's: as its derivation says, over the form's
			 * values. */
			ORMQuery *derivation = node.expression == nil && node.step != nil ? [ORMQuery derivationOf:node.step.factType inModel:_model]
			                                                                 : nil;
			if (derivation != nil) {
				bind.calculate = [self calculateOfDerivation:derivation at:field];
			}
			bind.readonly = YES;
			if (bind.calculate == nil) {
				[_notes addObject:[NSString stringWithFormat:@"%@: computed where it is read, not in the form.",
				                                             [node designation]]];
			} else {
				NSMutableArray *given = [NSMutableArray array];
				for (NSString *used in [node.expression nodeIds]) {
					[given addObject:[NSString stringWithFormat:@"%@ != ''", ORMSibling([elements objectForKey:used])]];
				}
				bind.calculate = [given count] == 0 ? bind.calculate
				                                    : [NSString stringWithFormat:@"choose(%@, %@, '')",
				                                                                 [given componentsJoinedByString:@" and "],
				                                                                 bind.calculate];
			}
			continue;
		}
		if (node == _form.root) {
			bind.readonly = YES;
			continue;
		}
		if (node.formPart == ORMFormPartShown || (node.isGiven && node.formPart == ORMFormPartNone)) {
			bind.readonly = YES;
		}
		ORMRole *entry = node.step.entryRole;
		/* An owned object's: needed where the object is (a customer's
		 * contact), else once it has anything (an address entered at all
		 * has its lines). */
		BOOL owned = field.groupName != nil && [self ownsNode:node.step.parent] && ![self needsObjectOf:node.step.parent];
		if (node.formPart == ORMFormPartEntered && entry.isMandatory
		    && ([self isAnchorsOwn:node.step.parent] || (field.groupName != nil && [self ownsNode:node.step.parent]))) {
			for (ORMConstraint *constraint in entry.constraints) {
				if (constraint.kind == ORMMandatoryConstraint && constraint.isSimple) {
					[self apply:constraint to:field];
					if (constraint.modality == ORMAlethic) {
						[bind.required addObject:owned ? @"../* != ''" : @"true()"];
					} else {
						[self warn:constraint at:field test:@". != ''"];
					}
				}
			}
		}
		/* What the definition of a subtype the anchor is of asks of each
		 * one: "Each MeteredEvent is by definition an Event that was at
		 * some Distance" makes a fill-up's distance needed. */
		if (node.formPart == ORMFormPartEntered && node.step.parent == _form.root) {
			for (NSArray *defining in [self definingSteps]) {
				ORMQuery *rule = [defining firstObject];
				ORMQueryStep *step = [defining lastObject];
				if (step.factType == node.step.factType && step.entryRole == entry
				    && ![bind.sources containsObject:rule.identifier]) {
					[bind.sources addObject:rule.identifier];
					NSString *text = [ORMVerbalizer plainTextOfSentences:[_verbalizer sentencesForQuery:rule]];
					[self alert:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] of:rule.identifier
					         at:bind];
					[bind.required addObject:@"true()"];
				}
			}
		}
		/* A compound is whole or not given: each part where another is. */
		if (field.isPart && node.formPart == ORMFormPartEntered) {
			NSMutableArray *others = [NSMutableArray array];
			for (ORMFormField *other in [self fieldsOfNode:node.identifier]) {
				if (other != field) {
					[others addObject:[NSString stringWithFormat:@"%@ != ''", ORMPathFrom(field.elementName, other.elementName)]];
				}
			}
			if ([others count] > 0) {
				[bind.required addObject:[others componentsJoinedByString:@" or "]];
			}
		}
		ORMValueConstraint *values = field.role.valueConstraint ?: [field.role.player valueType].valueConstraint;
		if (field.kind == ORMFormFieldValue && values != nil) {
			/* A list of values is the select1's items: none other chosen. */
			NSString *test = [ORMItemsOf(values) count] > 0 ? @"true()" : ORMXPathOfValues(values);
			if (test != nil) {
				if (![test isEqualToString:@"true()"]) {
					[bind.constraint addObject:[NSString stringWithFormat:@". = '' or %@", test]];
				}
				[bind.sources addObject:values.identifier ?: @""];
				[self alert:[NSString stringWithFormat:@"The possible values of %@ are %@.", ORMLabelOf(field.role, field.role.player),
				                                       [values displayText]]
				         of:values.identifier
				         at:bind];
			} else {
				[_checked addObject:[NSString stringWithFormat:@"The possible values of %@ are %@.",
				                                               ORMLabelOf(field.role, field.role.player), [values displayText]]];
			}
		}
		ORMObjectType *valueType = [field.role.player valueType];
		if (field.kind == ORMFormFieldValue && [valueType.dataType.typeName hasSuffix:@"TextDataType"]
		    && valueType.dataTypeLength > 0 && [ORMItemsOf(values) count] == 0) {
			[bind.constraint addObject:[NSString stringWithFormat:@"string-length(.) <= %ld", (long)valueType.dataTypeLength]];
		}
		if (field.kind == ORMFormFieldValue && [valueType.valuePattern length] > 0) {
			[_checked addObject:[NSString stringWithFormat:@"%@ matches the pattern '%@'.",
			                                               ORMLabelOf(field.role, valueType), valueType.valuePattern]];
		}
	}
}

/* Where a node is placed, from the anchor's element: its own element, or
 * in a repeat's rows ("purchaseLines/quantity"); nil for none. */
- (NSArray<NSString *> *)pathOfNode:(NSString *)nodeId
{
	NSString *own = [self elementOfNode:nodeId];
	if (own != nil) {
		return @[ own ];
	}
	for (NSString *name in [[_repeats allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSArray *inner = [[_repeats objectForKey:name] pathOfNode:nodeId];
		if (inner != nil) {
			return [@[ name ] arrayByAddingObjectsFromArray:inner];
		}
	}
	return nil;
}

/* D14: each aggregate (total, count, avg, max, min of a node) over the
 * rows it is of, as XForms 1.1 says them; an empty value none of them. */
- (void)bindAggregates
{
	for (NSString *nodeId in _aggregateNodes) {
		ORMQueryNode *node = [self nodeWithId:nodeId];
		ORMFormField *field = [[self fieldsOfNode:nodeId] firstObject];
		NSString *operand = [[node.expression nodeIds] firstObject];
		NSArray *path = operand != nil ? [self pathOfNode:operand] : nil;
		NSString *function = node.expression.function;
		if (field == nil || path == nil) {
			[_missing addObject:[NSString stringWithFormat:@"%@: the rows it is an aggregate of are not in the form.", [node designation]]];
			[_missingIds addObject:nodeId];
			continue;
		}
		NSString *values = [NSString stringWithFormat:@"%@[. != '']", ORMPathFrom(field.elementName, [path componentsJoinedByString:@"/"])];
		NSString *count = [NSString stringWithFormat:@"count(%@)", values], *sum = [NSString stringWithFormat:@"sum(%@)", values];
		NSDictionary *said = @{
			@"count" : count, @"total" : sum,
			@"avg" : [NSString stringWithFormat:@"choose(%@ > 0, %@ div %@, '')", count, sum, count],
			@"max" : [NSString stringWithFormat:@"choose(%@ > 0, max(%@), '')", count, values],
			@"min" : [NSString stringWithFormat:@"choose(%@ > 0, min(%@), '')", count, values],
		};
		[self bindOf:field].calculate = [said objectForKey:function ?: @""];
		[self bindOf:field].readonly = YES;
		[_aggregateOf setObject:@{ @"function" : function ?: @"", @"path" : path } forKey:field.elementName];
	}
}

/* A reference found by values entered (an order's customer, by email): it
 * is the app's to find, not the user's to enter, so what is required of it
 * is required of each value that finds it, said there. */
- (void)bindIdentifications
{
	for (ORMFormField *field in _fields) {
		ORMFormField *found = field.identifies != nil ? [self fieldNamed:field.identifies] : nil;
		ORMFormBind *of = found != nil ? [_binds objectForKey:found.elementName] : nil;
		if (of == nil || [of.required count] == 0) {
			continue;
		}
		ORMFormBind *bind = [self bindOf:field];
		[bind.required addObjectsFromArray:of.required];
		for (NSString *source in of.sources) {
			if (![bind.sources containsObject:source]) {
				[bind.sources addObject:source];
			}
		}
		for (NSString *alert in of.alerts) {
			if (![bind.alerts containsObject:alert]) {
				[self alert:alert of:[of.sourceOfAlert objectForKey:alert] at:bind];
			}
		}
	}
	for (NSString *name in [self identifiedNames]) {
		[[_binds objectForKey:name].required removeAllObjects];
	}
}

/* "../isA = 'Trip'": the object is of the field's subtype, or one of the
 * form's subtypes of it, from where the field is. */
- (NSString *)kindTestOf:(ORMFormField *)field
{
	return [self kindTestOf:field.subtypeEntity up:[[field.elementName componentsSeparatedByString:@"/"] count]];
}

/* The same of a subentity, from as many elements below the anchor's. */
- (NSString *)kindTestOf:(NSString *)subtypeEntity up:(NSUInteger)depth
{
	NSMutableString *up = [NSMutableString string];
	for (NSUInteger i = depth; i > 0; i--) {
		[up appendString:@"../"];
	}
	NSMutableArray *tests = [NSMutableArray array];
	for (NSString *subtype in [self subtypeEntities]) {
		BOOL kind = NO;
		for (ORMCDEntity *each = [_planner.coreData entityNamed:subtype]; each != nil && !kind;
		     each = [_planner.coreData entityNamed:each.parentName ?: @""]) {
			kind = [each.name isEqualToString:subtypeEntity];
		}
		if (kind) {
			[tests addObject:[NSString stringWithFormat:@"%@%@ = '%@'", up, [self subtypeField].elementName, subtype]];
		}
	}
	return [tests count] > 0 ? [tests componentsJoinedByString:@" or "] : @"false()";
}

/* The steps every object of the anchor's type has by the definitions of
 * the subtypes it is of (itself among them): @[ the derivation, its step ],
 * each a plain step from its root, with nothing said of its node. */
- (NSArray<NSArray *> *)definingSteps
{
	if (_definingSteps != nil) {
		return _definingSteps;
	}
	ORMObjectType *anchor = _form.root.objectType;
	NSMutableArray *defining = [NSMutableArray array];
	for (ORMObjectType *subtype in [@[ anchor ] arrayByAddingObjectsFromArray:[anchor allSupertypes]]) {
		ORMQuery *rule = [ORMQuery derivationOfSubtype:subtype inModel:_model];
		if (rule == nil || rule.root.combinesWithOr) {
			continue;
		}
		for (ORMQueryStep *step in rule.root.steps) {
			BOOL plain = step.operatorKind == ORMQueryAnd && step.countComparison == nil;
			for (ORMQueryNode *node in step.nodes) {
				plain = plain && node.comparison == nil && [node.steps count] == 0 && [node.values count] == 0;
			}
			if (plain) {
				[defining addObject:@[ rule, step ]];
			}
		}
	}
	_definingSteps = defining;
	return _definingSteps;
}

- (ORMQueryNode *)nodeWithId:(NSString *)identifier
{
	for (ORMQueryNode *node in [_form nodes]) {
		if ([node.identifier isEqualToString:identifier]) {
			return node;
		}
	}
	return nil;
}

/* The constraint said at the field: its verbalization the field's alert. */
- (void)apply:(ORMConstraint *)constraint to:(ORMFormField *)field
{
	ORMFormBind *bind = [self bindOf:field];
	if ([bind.sources containsObject:constraint.identifier]) {
		return;
	}
	[bind.sources addObject:constraint.identifier];
	if (constraint.modality == ORMAlethic) {
		[self alert:[self sayElement:constraint.identifier] of:constraint.identifier at:bind];
	}
}

- (void)warn:(ORMConstraint *)constraint at:(ORMFormField *)field test:(NSString *)test
{
	ORMFormWarning *warning = [[ORMFormWarning alloc] init];
	warning.constraintId = constraint.identifier;
	warning.elementName = field.elementName;
	warning.test = test;
	warning.text = [self sayElement:constraint.identifier];
	[_warnings addObject:warning];
}

/* The fields of the anchor's own facts each role is in: the anchor's role
 * in a step from it, and the role its node plays. */
- (NSDictionary<NSString *, NSArray<ORMFormField *> *> *)fieldsByRole
{
	NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
	for (ORMFormField *field in _fields) {
		ORMQueryNode *node = [self nodeWithId:field.nodeId];
		/* The anchor's own (a subtype part's among them) and an owned
		 * object's: what is written with it. */
		BOOL written = [self isAnchorsOwn:node.step.parent] || (field.groupName != nil && [self ownsNode:node.step.parent]);
		if (node.isValue || !written || field.kind == ORMFormFieldCalculated) {
			continue;
		}
		for (ORMRole *role in @[ node.step.entryRole ?: (id)[NSNull null], node.role ?: (id)[NSNull null] ]) {
			if (![role isKindOfClass:[ORMRole class]]) {
				continue;
			}
			NSMutableArray *fields = [byRole objectForKey:role.identifier] ?: [NSMutableArray array];
			[fields addObject:field];
			[byRole setObject:fields forKey:role.identifier];
		}
	}
	return byRole;
}

/* Whether the fact types can be about the anchor: none of them played by
 * another subtype of its supertypes (a trip's, in a fill-up's form, though
 * both are events at a moment). */
- (BOOL)concernsTheAnchor:(NSArray<ORMFactType *> *)facts
{
	ORMObjectType *anchor = _form.root.objectType;
	NSArray *family = anchor.family;
	for (ORMFactType *fact in facts) {
		for (ORMRole *role in fact.roles) {
			ORMObjectType *player = role.player;
			if (player != nil && player != anchor && [family containsObject:player] && ![anchor isSubtypeOf:player]
			    && ![player isSubtypeOf:anchor]) {
				return NO;
			}
		}
	}
	return YES;
}

/* "../a = '' and ../b = ''": none of the fields given, from the one's
 * context. */
static NSString *
ORMNoneGiven(ORMFormField *from, NSArray<ORMFormField *> *fields)
{
	NSMutableArray *tests = [NSMutableArray array];
	for (ORMFormField *field in fields) {
		[tests addObject:[NSString stringWithFormat:@"%@ = ''", ORMPathFrom(from.elementName, field.elementName)]];
	}
	return [tests componentsJoinedByString:@" and "];
}

/* What the constraints over the form's roles say, as binds; each one the
 * form cannot check alone (and each rule through its facts) listed as
 * checked where it is submitted. */
- (void)bindConstraints
{
	NSDictionary *byRole = [self fieldsByRole];
	NSMutableArray *constraints = [NSMutableArray array];
	NSMutableSet *compoundFacts = [NSMutableSet set];
	for (ORMQueryNode *node in [_form nodes]) {
		for (ORMRole *part in ORMPartsOf(node) ?: @[]) {
			[compoundFacts addObject:part.factType.identifier];
		}
	}
	NSMutableArray *roles = [NSMutableArray array];
	for (ORMQueryNode *node in [_form nodes]) {
		if (node.formPart == ORMFormPartEntered && node.step.entryRole != nil) {
			[roles addObject:node.step.entryRole];
			if (node.role != nil) {
				[roles addObject:node.role];
			}
		}
	}
	for (ORMRole *role in roles) {
		for (ORMConstraint *constraint in role.constraints) {
			if (![constraints containsObject:constraint]) {
				[constraints addObject:constraint];
			}
		}
	}
	for (ORMConstraint *constraint in constraints) {
		if (![self concernsTheAnchor:[constraint factTypes]]) {
			continue;
		}
		BOOL inCompound = YES;
		for (ORMFactType *fact in [constraint factTypes]) {
			inCompound = inCompound && [compoundFacts containsObject:fact.identifier];
		}
		/* What the instance's shape is already: one value each, an
		 * identifier, a part of a compound, a mandatory bound above. */
		if (inCompound || constraint.isImplied || constraint.preferredIdentifierFor != nil
		    || (constraint.kind == ORMUniquenessConstraint && constraint.isInternal && [[constraint allRoles] count] == 1)
		    || (constraint.kind == ORMMandatoryConstraint && constraint.isSimple)) {
			continue;
		}
		NSMutableArray *sequences = [NSMutableArray array];
		for (ORMRoleSequence *sequence in constraint.roleSequences) {
			NSMutableArray *fields = [NSMutableArray array];
			for (ORMRole *role in sequence.roles) {
				NSArray *placed = [byRole objectForKey:role.identifier];
				if (placed == nil) {
					fields = nil;
					break;
				}
				[fields addObjectsFromArray:placed];
			}
			if (fields == nil) {
				sequences = nil;
				break;
			}
			[sequences addObject:fields];
		}
		if (sequences == nil || ![self bind:constraint sequences:sequences]) {
			[self check:[self sayElement:constraint.identifier] of:constraint.identifier];
		}
	}
	/* The rules through the form's facts: their violations found where it
	 * is submitted. */
	NSSet *facts = [NSSet setWithArray:[[_form subschemaInModel:_model].factTypes valueForKey:@"identifier"]];
	for (ORMQuery *rule in [ORMQuery queriesInModel:_model]) {
		if (rule.kind != ORMQueryConstraint) {
			continue;
		}
		NSArray *ruleFacts = [rule subschemaInModel:_model].factTypes;
		NSSet *through = [NSSet setWithArray:[ruleFacts valueForKey:@"identifier"]];
		if ([through intersectsSet:facts] && [self concernsTheAnchor:ruleFacts]) {
			NSString *text = [ORMVerbalizer plainTextOfSentences:[_verbalizer sentencesForQuery:rule]];
			text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			/* Over the form's own values: a bind, checked as it is filled in;
			 * else where it is submitted. */
			if (![self bindRule:rule text:text]) {
				[self check:text of:rule.identifier];
			}
		}
	}
}

#pragma mark Rules and derivations

/* Whether the rule's root is of the anchor's type, or one it is a kind of. */
- (BOOL)isOfTheAnchor:(ORMQueryNode *)root
{
	ORMObjectType *anchor = _form.root.objectType;
	return root.objectType != nil && (root.objectType == anchor || [anchor isSubtypeOf:root.objectType]);
}

/* What the node's condition says of its value at the path ("number(p) >
 * 200", "(p = 'a' or p = 'b')"); "" for none; nil for one XPath cannot say
 * here. */
- (NSString *)conditionOf:(ORMQueryNode *)node at:(NSString *)path paths:(NSDictionary *)paths
{
	if (node.comparison == nil) {
		return @"";
	}
	NSDictionary *operators = @{ @"=" : @"=", @"<>" : @"!=", @"<" : @"<", @"<=" : @"<=", @">" : @">", @">=" : @">=" };
	BOOL numeric = [node isNumeric];
	NSString *subject = numeric ? [NSString stringWithFormat:@"number(%@)", path] : path;
	if (node.comparedNode != nil) {
		NSString *other = [paths objectForKey:node.comparedNode.identifier];
		NSString *operator = [operators objectForKey:node.comparison];
		return other != nil && operator != nil
			? [NSString stringWithFormat:@"%@ %@ %@", subject, operator, numeric ? [NSString stringWithFormat:@"number(%@)", other] : other]
			: nil;
	}
	NSArray *values = [node.comparison isEqualToString:@"in"] ? [node comparedValues] : @[ node.value ?: @"" ];
	NSString *operator = [node.comparison isEqualToString:@"in"] ? @"=" : [operators objectForKey:node.comparison];
	NSMutableArray *each = [NSMutableArray array];
	for (NSString *value in values) {
		if (operator == nil || [value rangeOfString:@"'"].location != NSNotFound) {
			return nil;
		}
		[each addObject:[NSString stringWithFormat:@"%@ %@ %@", subject, operator, numeric ? value : [NSString stringWithFormat:@"'%@'", value]]];
	}
	return [each count] == 1 ? [each firstObject] : [NSString stringWithFormat:@"(%@)", [each componentsJoinedByString:@" or "]];
}

/* The rule's node onto the form's: each of the rule's steps from it one of
 * the form's from that, through the same fact type and role, a compound's
 * part one of the form's compound's parts. The path of each node reached,
 * from the context's element, put in paths (by the rule's node), the
 * elements it is at in elements, and what each step and condition says in
 * tests. NO where any of it is not in the form. */
- (BOOL)mapRuleNode:(ORMQueryNode *)rule
              onto:(ORMQueryNode *)form
              from:(ORMFormField *)context
             paths:(NSMutableDictionary *)paths
             tests:(NSMutableArray *)tests
          elements:(NSMutableArray *)elements
{
	if (rule.combinesWithOr) {
		return NO;
	}
	for (ORMQueryStep *step in rule.steps) {
		if (step.countComparison != nil || [step.nodes count] > 1 || [step isSubtyping]) {
			return NO;
		}
		BOOL negated = step.operatorKind == ORMQueryNot, maybe = step.operatorKind == ORMQueryMaybe;
		ORMQueryStep *same = nil;
		for (ORMQueryStep *each in form.steps) {
			same = each.factType == step.factType && each.entryRole == step.entryRole ? each : same;
		}
		if ([step.factType isUnary]) {
			NSString *flag = same != nil ? [self elementOfNode:same.identifier] : nil;
			if (flag == nil) {
				return NO;
			}
			[elements addObject:flag];
			NSString *path = context != nil ? ORMPathFrom(context.elementName, flag) : flag;
			if (!maybe) {
				[tests addObject:[NSString stringWithFormat:negated ? @"%@ != 'true'" : @"%@ = 'true'", path]];
			}
			continue;
		}
		ORMQueryNode *reached = [step.nodes firstObject], *formReached = [same.nodes firstObject];
		NSString *element = formReached != nil ? [self elementOfNode:formReached.identifier] : nil;
		if (same == nil) {
			/* A compound's part the outline does not list (a cost's amount). */
			for (ORMFormField *field in [self fieldsOfNode:form.identifier]) {
				element = field.isPart && field.role == reached.role ? field.elementName : element;
			}
			if (element == nil) {
				return NO;
			}
		}
		NSString *path = element != nil ? (context != nil ? ORMPathFrom(context.elementName, element) : element) : nil;
		if (path != nil) {
			[paths setObject:path forKey:reached.identifier];
		}
		if ([reached.steps count] == 0 || negated) {
			if (path == nil) {
				return NO;
			}
			[elements addObject:element];
			if (!maybe) {
				[tests addObject:[NSString stringWithFormat:negated ? @"%@ = ''" : @"%@ != ''", path]];
			}
			NSString *condition = negated ? @"" : [self conditionOf:reached at:path paths:paths];
			if (condition == nil) {
				return NO;
			}
			if ([condition length] > 0) {
				[tests addObject:condition];
			}
			continue;
		}
		if (formReached == nil || reached.comparison != nil
		    || ![self mapRuleNode:reached onto:formReached from:context paths:paths tests:tests elements:elements]) {
			return NO;
		}
	}
	return YES;
}

/* The query onto the form, its root the anchor: its paths and tests; its
 * value nodes' conditions tests too. NO where any of it is not in the form. */
- (BOOL)mapQuery:(ORMQuery *)query
            from:(ORMFormField *)context
           paths:(NSMutableDictionary *)paths
           tests:(NSMutableArray *)tests
        elements:(NSMutableArray *)elements
{
	if (![self isOfTheAnchor:query.root] || query.root.comparison != nil
	    || ![self mapRuleNode:query.root onto:_form.root from:context paths:paths tests:tests elements:elements]) {
		return NO;
	}
	for (ORMQueryNode *value in [query nodes]) {
		if (!value.isValue) {
			continue;
		}
		NSString *said = ORMXPathOfPaths(value.expression, paths);
		if (said == nil) {
			return NO;
		}
		[paths setObject:said forKey:value.identifier];
		NSString *condition = [self conditionOf:value at:said paths:paths];
		if (condition == nil) {
			return NO;
		}
		if ([condition length] > 0) {
			[tests addObject:condition];
		}
	}
	return YES;
}

/* A rule over the form's own values, at the first of them the user enters:
 * what it forbids, a constraint ("not(...)"), said in its words; a deontic
 * one a warning. NO where any of it is not in the form, or nothing of it
 * is entered: checked where the form is submitted. */
- (BOOL)bindRule:(ORMQuery *)rule text:(NSString *)text
{
	NSMutableArray *elements = [NSMutableArray array];
	if (![self mapQuery:rule from:nil paths:[NSMutableDictionary dictionary] tests:[NSMutableArray array] elements:elements]) {
		return NO;
	}
	ORMFormField *context = nil;
	for (ORMFormField *field in _fields) {
		if (context == nil && [elements containsObject:field.elementName] && [[self roleOfField:field] isEqualToString:@"entered"]) {
			context = field;
		}
	}
	NSMutableArray *tests = [NSMutableArray array];
	if (context == nil || ![self mapQuery:rule from:context paths:[NSMutableDictionary dictionary] tests:tests elements:elements]
	    || [tests count] == 0) {
		return NO;
	}
	NSString *violation = [tests componentsJoinedByString:@" and "];
	ORMFormBind *bind = [self bindOf:context];
	if (rule.isDeontic) {
		ORMFormWarning *warning = [[ORMFormWarning alloc] init];
		warning.constraintId = rule.identifier;
		warning.elementName = context.elementName;
		warning.test = [NSString stringWithFormat:@"not(%@)", violation];
		warning.text = text;
		[_warnings addObject:warning];
		return YES;
	}
	[bind.sources addObject:rule.identifier];
	[bind.constraint addObject:[NSString stringWithFormat:@"not(%@)", violation]];
	[self alert:text of:rule.identifier at:bind];
	return YES;
}

/* A derived fact type's value at the field, as its derivation says, over
 * the form's values: where its path holds, its value node's expression or
 * the node it gives (a unary's "true"), else none ("" or "false"); nil
 * where any of it is not in the form. */
- (NSString *)calculateOfDerivation:(ORMQuery *)derivation at:(ORMFormField *)field
{
	NSMutableDictionary *paths = [NSMutableDictionary dictionary];
	NSMutableArray *tests = [NSMutableArray array];
	if (![self mapQuery:derivation from:field paths:paths tests:tests elements:[NSMutableArray array]]) {
		return nil;
	}
	ORMQueryNode *given = nil;
	for (ORMQueryNode *column in [derivation derivedColumns]) {
		given = column != derivation.root ? column : given;
	}
	BOOL unary = given == nil;
	NSString *value = unary ? @"'true'" : [paths objectForKey:given.identifier];
	if (value == nil) {
		return nil;
	}
	if ([tests count] == 0) {
		return unary ? @"'true'" : value;
	}
	return [NSString stringWithFormat:@"choose(%@, %@, %@)", [tests componentsJoinedByString:@" and "], value, unary ? @"'false'" : @"''"];
}

/* The constraint over the fields of each of its sequences, as binds (a
 * deontic one as warnings); NO for one a bind cannot say. */
- (BOOL)bind:(ORMConstraint *)constraint sequences:(NSArray<NSArray<ORMFormField *> *> *)sequences
{
	BOOL deontic = constraint.modality == ORMDeontic;
	NSMutableArray *all = [NSMutableArray array];
	for (NSArray *fields in sequences) {
		[all addObjectsFromArray:fields];
	}
	switch (constraint.kind) {
	case ORMMandatoryConstraint:
		/* Inclusive-or: each needed while the others are empty. */
		for (ORMFormField *field in all) {
			NSString *test = ORMNoneGiven(field, ORMWithout(all, field));
			/* An owned object's, where it need not be: once anything of it
			 * is entered (an address left out has none of its lines). */
			ORMQueryNode *object = [self nodeWithId:field.nodeId].step.parent;
			if (field.groupName != nil && [self ownsNode:object] && ![self needsObjectOf:object]) {
				test = [NSString stringWithFormat:@"(%@) and ../* != ''", test];
			}
			[self apply:constraint to:field];
			if (deontic) {
				[self warn:constraint at:field test:[NSString stringWithFormat:@". != '' or not(%@)", test]];
			} else {
				[[self bindOf:field].required addObject:test];
			}
		}
		return YES;
	case ORMExclusionConstraint:
		/* Each relevant while the others are empty. */
		for (NSArray *fields in sequences) {
			NSMutableArray *others = [all mutableCopy];
			[others removeObjectsInArray:fields];
			for (ORMFormField *field in fields) {
				[self apply:constraint to:field];
				if (deontic) {
					[self warn:constraint at:field test:[NSString stringWithFormat:@". = '' or (%@)", ORMNoneGiven(field, others)]];
				} else {
					[[self bindOf:field].relevant addObject:ORMNoneGiven(field, others)];
				}
			}
		}
		return YES;
	case ORMSubsetConstraint:
	case ORMEqualityConstraint: {
		if ([sequences count] != 2) {
			return NO;
		}
		/* A subset's first given only where its second is; equality both
		 * ways, each required where the other is given. */
		BOOL both = constraint.kind == ORMEqualityConstraint;
		for (NSUInteger i = 0; i < (both ? 2 : 1); i++) {
			NSArray *these = [sequences objectAtIndex:i], *those = [sequences objectAtIndex:1 - i];
			for (ORMFormField *field in these) {
				NSString *given = [NSString stringWithFormat:@"not(%@)", ORMNoneGiven(field, those)];
				[self apply:constraint to:field];
				if (deontic) {
					[self warn:constraint at:field test:[NSString stringWithFormat:@". = '' or %@", given]];
				} else if (both) {
					[[self bindOf:field].required addObject:given];
				} else {
					[[self bindOf:field].relevant addObject:given];
				}
			}
		}
		return YES;
	}
	case ORMValueComparisonConstraint: {
		NSArray *fields = [sequences firstObject];
		NSDictionary *operators = @{
			@"LessThan" : @"<", @"LessThanOrEqual" : @"<=", @"GreaterThan" : @">", @"GreaterThanOrEqual" : @">=",
			@"Equal" : @"=", @"NotEqual" : @"!=",
		};
		NSString *operator= [operators objectForKey:constraint.comparisonOperator ?: @""];
		if ([fields count] != 2 || operator== nil) {
			return NO;
		}
		ORMFormField *first = [fields firstObject], *second = [fields lastObject];
		BOOL numeric = ![first.schemaType isEqualToString:@"xsd:string"];
		NSString *a = numeric ? @"number(.)" : @".", *b = ORMPathFrom(first.elementName, second.elementName);
		if (numeric) {
			b = [NSString stringWithFormat:@"number(%@)", b];
		}
		NSString *test = [NSString stringWithFormat:@". = '' or %@ = '' or %@ %@ %@", ORMPathFrom(first.elementName, second.elementName), a,
		                                            operator, b];
		[self apply:constraint to:first];
		if (deontic) {
			[self warn:constraint at:first test:test];
		} else {
			[[self bindOf:first].constraint addObject:test];
		}
		return YES;
	}
	default:
		return NO;
	}
}

#pragma mark What it reads

- (NSArray<NSString *> *)choiceNames
{
	NSMutableArray *names = [NSMutableArray array];
	for (ORMFormField *field in _fields) {
		ORMQueryNode *node = [self nodeWithId:field.nodeId];
		if (field.kind == ORMFormFieldReference && node.formPart == ORMFormPartEntered
		    && ORMItemsOf(field.referredType.valueConstraint) == nil && [[self elementsIdentifying:field.elementName] count] == 0) {
			[names addObject:field.elementName];
		}
	}
	return names;
}

- (NSArray<NSString *> *)identifiedNames
{
	NSMutableArray *names = [NSMutableArray array];
	for (ORMFormField *field in _fields) {
		if (field.identifies != nil && ![names containsObject:field.identifies]) {
			[names addObject:field.identifies];
		}
	}
	return names;
}

- (NSArray<NSString *> *)elementsIdentifying:(NSString *)elementName
{
	NSMutableArray *names = [NSMutableArray array];
	for (ORMFormField *field in _fields) {
		if ([field.identifies isEqualToString:elementName]) {
			[names addObject:field.elementName];
		}
	}
	return names;
}

/* The objects of the reference's type whose values are the ones that find
 * it (a customer of the email), each compared with the element's value. */
- (ORMQueryPlan *)identifyPlanNamed:(NSString *)elementName given:(NSDictionary<NSString *, NSString *> *)values
{
	ORMFormField *field = [self fieldNamed:elementName];
	ORMQueryPart *stored = field.kind == ORMFormFieldReference ? [_stored partWithId:field.nodeId step:NO] : nil;
	if (stored == nil) {
		return nil;
	}
	NSMutableDictionary *byNode = [NSMutableDictionary dictionary];
	for (NSString *name in [self elementsIdentifying:elementName]) {
		[byNode setObject:[values objectForKey:name] ?: @"" forKey:[self fieldNamed:name].nodeId];
	}
	ORMQueryPart *root = [stored copy];
	root.roleId = nil;
	for (ORMQueryPart *step in [root steps]) {
		BOOL finds = NO;
		for (ORMQueryPart *node in [step nodes]) {
			finds = finds || [byNode objectForKey:node.identifier] != nil;
		}
		if (!finds) {
			[step detach];
		}
	}
	for (ORMQueryPart *each in [root tree]) {
		each.part = nil;
		each.given = nil;
		each.projected = nil;
		each.label = nil;
		NSString *value = each.isStep ? nil : [byNode objectForKey:each.identifier];
		if (value != nil) {
			each.comparison = @"=";
			each.value = value;
		}
	}
	root.ref = field.referredType.identifier;
	root.projected = @"true";
	ORMStoredQuery *query = [[ORMStoredQuery alloc] init];
	query.identifier = [@"identify-" stringByAppendingString:[field fieldId]];
	query.name = query.identifier;
	query.root = root;
	return [self plan:query];
}

- (NSArray<NSString *> *)elementsChoicesDependOn:(NSString *)elementName
{
	ORMFormField *field = [self fieldNamed:elementName];
	ORMQueryNode *node = field.isPart ? nil : [self nodeWithId:field.nodeId];
	NSMutableArray *names = [NSMutableArray array];
	for (NSArray *pair in node != nil ? ORMSharedNodes(_form, node) : @[]) {
		for (ORMFormField *outside in [self fieldsOfNode:[[pair lastObject] identifier]]) {
			if (![names containsObject:outside.elementName]) {
				[names addObject:outside.elementName];
			}
		}
	}
	return names;
}

- (ORMQueryPlan *)choicesPlanNamed:(NSString *)elementName given:(NSDictionary<NSString *, NSString *> *)values
{
	ORMFormField *field = [self fieldNamed:elementName];
	if (field.kind != ORMFormFieldReference || field.referredType == nil) {
		return nil;
	}
	ORMQueryPart *root = [[ORMQueryPart alloc] init];
	ORMQueryPart *stored = field.isPart ? nil : [_stored partWithId:field.nodeId step:NO];
	if (stored != nil) {
		root = [stored copy];
		root.roleId = nil;
		root.part = nil;
		root.given = nil;
		root.label = nil;
		for (ORMQueryPart *step in [root steps]) {
			if (![_conditionSteps containsObject:step.identifier]) {
				[step detach];
			}
		}
		/* A node it shares with the form: that one's value, where there is. */
		for (NSArray *pair in ORMSharedNodes(_form, [self nodeWithId:field.nodeId])) {
			ORMQueryPart *inside = nil;
			for (ORMQueryPart *each in [root tree]) {
				inside = !each.isStep && [each.identifier isEqualToString:[[pair firstObject] identifier]] ? each : inside;
			}
			NSString *value = nil;
			for (ORMFormField *outside in [self fieldsOfNode:[[pair lastObject] identifier]]) {
				value = value ?: [values objectForKey:outside.elementName];
			}
			inside.label = nil;
			if ([value length] > 0) {
				inside.comparison = @"=";
				inside.value = value;
			}
		}
		for (ORMQueryPart *each in [root tree]) {
			each.part = nil;
			each.given = nil;
			each.projected = nil;
		}
	} else {
		root.identifier = [field fieldId];
	}
	root.ref = field.referredType.identifier;
	root.projected = @"true";
	ORMStoredQuery *query = [[ORMStoredQuery alloc] init];
	query.identifier = [@"choices-" stringByAppendingString:[field fieldId]];
	query.name = query.identifier;
	query.root = root;
	return [self plan:query];
}

#pragma mark What an app runs

/* What stands for a parameter while the planner plans: a value no one
 * gives, put back as the parameter after. */
static NSString *
ORMParameterSentinel(NSString *name)
{
	return [@"ORMFormParameter_" stringByAppendingString:name];
}

/* The property list with each constant a sentinel's a parameter of its
 * name, of the constant's type. */
static id
ORMParameterized(id list, NSDictionary<NSString *, NSString *> *names)
{
	if ([list isKindOfClass:[NSDictionary class]]) {
		NSString *name = [names objectForKey:[list objectForKey:@"constant"] ?: @""];
		if (name != nil) {
			return @{ @"parameter": name, @"type": [list objectForKey:@"type"] ?: @"String" };
		}
		NSMutableDictionary *copy = [NSMutableDictionary dictionary];
		for (id key in list) {
			[copy setObject:ORMParameterized([list objectForKey:key], names) forKey:key];
		}
		return copy;
	}
	if ([list isKindOfClass:[NSArray class]]) {
		NSMutableArray *copy = [NSMutableArray array];
		for (id item in list) {
			[copy addObject:ORMParameterized(item, names)];
		}
		return copy;
	}
	return list;
}

static ORMQueryPlan *
ORMPlanWithParameters(ORMQueryPlan *plan, NSDictionary<NSString *, NSString *> *names)
{
	if (plan == nil) {
		return nil;
	}
	ORMQueryPlan *parameterized = [ORMQueryPlan planWithPropertyList:ORMParameterized([plan propertyList], names) error:NULL];
	return parameterized ?: plan;
}

/* The anchor's key: its first element. */
- (ORMFormField *)keyField
{
	ORMFormField *first = [_fields firstObject];
	return [first.nodeId isEqualToString:_form.root.identifier] ? first : nil;
}

- (ORMQueryPlan *)readPlan
{
	/* A repeat's is of the objects linked to the key of its link's element. */
	NSString *name = [self linkElement] ?: (_linkNodeId != nil ? @"link" : [self keyField].elementName);
	if (name == nil) {
		return nil;
	}
	_linkValue = _linkNodeId != nil;
	ORMQueryPlan *plan = ORMPlanWithParameters([self readPlanForKey:ORMParameterSentinel(name)], @{ ORMParameterSentinel(name): name });
	_linkValue = NO;
	return plan;
}

- (ORMQueryPlan *)choicesPlanNamed:(NSString *)elementName
{
	NSMutableDictionary *given = [NSMutableDictionary dictionary], *names = [NSMutableDictionary dictionary];
	for (NSString *name in [self elementsChoicesDependOn:elementName]) {
		[given setObject:ORMParameterSentinel(name) forKey:name];
		[names setObject:name forKey:ORMParameterSentinel(name)];
	}
	return [given count] > 0 ? ORMPlanWithParameters([self choicesPlanNamed:elementName given:given], names) : nil;
}

- (ORMQueryPlan *)identifyPlanNamed:(NSString *)elementName
{
	NSMutableDictionary *given = [NSMutableDictionary dictionary], *names = [NSMutableDictionary dictionary];
	for (NSString *name in [self elementsIdentifying:elementName]) {
		[given setObject:ORMParameterSentinel(name) forKey:name];
		[names setObject:name forKey:ORMParameterSentinel(name)];
	}
	return [given count] > 0 ? ORMPlanWithParameters([self identifyPlanNamed:elementName given:given], names) : nil;
}

static NSString *
ORMFieldKindName(ORMFormFieldKind kind)
{
	return kind == ORMFormFieldReference ? @"reference" : kind == ORMFormFieldCalculated ? @"calculated"
	     : kind == ORMFormFieldSubtype ? @"subtype" : @"value";
}

- (id)tablePropertyList
{
	ORMQueryPlan *read = [self readPlan];
	NSMutableArray *elements = [NSMutableArray array];
	for (ORMFormField *field in _fields) {
		ORMQueryNode *node = [self nodeWithId:field.nodeId];
		ORMQueryStep *unary = [_unarySteps objectForKey:field.nodeId];
		NSMutableDictionary *element = [NSMutableDictionary dictionary];
		[element setObject:field.elementName forKey:@"name"];
		[element setObject:ORMFieldKindName(field.kind) forKey:@"kind"];
		[element setObject:field.schemaType ?: @"xsd:string" forKey:@"type"];
		/* Where the read has it: its column, and a compound's part. */
		NSUInteger column = 0;
		for (ORMPlanColumn *each in read.columns) {
			if ([each.nodeId isEqualToString:field.nodeId]) {
				[element setObject:@(column) forKey:@"column"];
				break;
			}
			column++;
		}
		if (field.isPart) {
			[element setObject:@(field.partIndex) forKey:@"part"];
		}
		if (field.keys != nil) {
			[element setObject:field.keys forKey:@"path"];
		}
		if (field.groupName != nil) {
			[element setObject:field.groupName forKey:@"group"];
		}
		if (field.subtypeEntity != nil) {
			[element setObject:field.subtypeEntity forKey:@"subtype"];
		}
		if (field.kind == ORMFormFieldReference) {
			[element setObject:field.entityName ?: @"" forKey:@"entity"];
			[element setObject:field.keyName ?: @"" forKey:@"key"];
		}
		if (field.isMany) {
			[element setObject:@YES forKey:@"many"];
		}
		/* What a save writes: what the user enters, and what the form is
		 * given; never what it shows or computes. */
		ORMQueryFormPart part = unary != nil ? unary.formPart : node.formPart;
		BOOL written = (node != _form.root && field.kind != ORMFormFieldCalculated && !field.isHidden && !field.isThrough
		                && field.identifies == nil && (part == ORMFormPartEntered || (node.isGiven && part != ORMFormPartShown)))
		               || field.kind == ORMFormFieldSubtype;
		if (field.identifies != nil) {
			[element setObject:field.identifies forKey:@"identifies"];
		}
		if ([_aggregateOf objectForKey:field.elementName] != nil) {
			[element setObject:[_aggregateOf objectForKey:field.elementName] forKey:@"aggregate"];
		}
		/* Read on its own, by the key: the plan, and its column. */
		NSString *keyName = [self keyField].elementName;
		ORMQueryPlan *own = keyName != nil ? [self ownReadOf:field.nodeId key:ORMParameterSentinel(keyName)] : nil;
		if (own != nil) {
			own = ORMPlanWithParameters(own, @{ ORMParameterSentinel(keyName) : keyName });
			NSUInteger index = 0;
			for (ORMPlanColumn *each in own.columns) {
				if ([each.nodeId isEqualToString:field.nodeId]) {
					[element setObject:[own propertyList] forKey:@"read"];
					[element setObject:@(index) forKey:@"readColumn"];
				}
				index++;
			}
		}
		[element setObject:@(written) forKey:@"written"];
		/* What it is to whoever opens the form, and what it is called. */
		[element setObject:[self roleOfField:field] forKey:@"role"];
		if (node.isGiven) {
			[element setObject:@YES forKey:@"given"];
		}
		/* The model's list of its values (fuels, currencies), as the
		 * XForms document's items: what a view offers to choose from. */
		ORMValueConstraint *values = field.role.valueConstraint ?: [field.role.player valueType].valueConstraint;
		NSArray *items = field.kind == ORMFormFieldValue ? ORMItemsOf(values)
		               : field.kind == ORMFormFieldReference ? ORMItemsOf(field.referredType.valueConstraint)
		               : field.kind == ORMFormFieldSubtype ? [self subtypeEntities] : nil;
		if (items != nil) {
			[element setObject:items forKey:@"items"];
		}
		/* A kind's said as the reader does ("Fill up"), its value the subentity's. */
		if (field.kind == ORMFormFieldSubtype) {
			NSMutableArray *labels = [NSMutableArray array];
			for (NSString *subtype in items) {
				[labels addObject:[self labelOfSubtype:subtype]];
			}
			[element setObject:labels forKey:@"itemLabels"];
		}
		[element setObject:[self labelOfField:field] forKey:@"label"];
		[elements addObject:element];
	}
	NSMutableDictionary *choices = [NSMutableDictionary dictionary];
	for (NSString *name in [self choiceNames]) {
		NSMutableDictionary *choice = [NSMutableDictionary dictionary];
		ORMQueryPlan *all = [self choicesPlanNamed:name given:@{}];
		ORMQueryPlan *theirs = [self choicesPlanNamed:name];
		[choice setObject:[all propertyList] forKey:@"all"];
		if (theirs != nil) {
			[choice setObject:[theirs propertyList] forKey:@"plan"];
			[choice setObject:[self elementsChoicesDependOn:name] forKey:@"dependsOn"];
		}
		[choices setObject:choice forKey:name];
	}
	/* A reference found by values entered: what finds it, of them. */
	for (NSString *name in [self identifiedNames]) {
		ORMQueryPlan *identify = [self identifyPlanNamed:name];
		if (identify != nil) {
			[choices setObject:@{ @"identify" : [identify propertyList], @"identifiedBy" : [self elementsIdentifying:name] } forKey:name];
		}
	}
	NSMutableDictionary *list = [NSMutableDictionary dictionary];
	[list setObject:@1 forKey:@"format"];
	[list setObject:_form.name forKey:@"form"];
	[list setObject:_entityName forKey:@"entity"];
	[list setObject:[self keyField].elementName ?: @"" forKey:@"key"];
	[list setObject:elements forKey:@"elements"];
	if (read != nil) {
		[list setObject:[read propertyList] forKey:@"read"];
	}
	[list setObject:choices forKey:@"choices"];
	/* The objects it owns, made and changed with the anchor: each its keys
	 * from the anchor and its entity, outer ones first. */
	NSMutableArray *groups = [NSMutableArray array];
	for (NSString *name in _groupNames) {
		NSArray *keys = [name componentsSeparatedByString:@"/"];
		ORMQueryNode *node = [_groupNodes objectForKey:name];
		[groups addObject:@{
			@"name" : name, @"path" : keys, @"entity" : [self entityAtKeys:keys] ?: @"",
			@"label" : ORMLabelOf(node.role, node.objectType), @"needed" : @([self needsObjectOf:node]),
			@"key" : [_planner identifierKeyOfType:node.objectType] ?: @"",
		}];
	}
	if ([groups count] > 0) {
		[list setObject:groups forKey:@"groups"];
	}
	[list setObject:[self checkedWhereSubmitted] forKey:@"checkedWhereSubmitted"];
	if (_action != nil) {
		[list setObject:_action forKey:@"action"];
	}
	if ([_messages count] > 0) {
		[list setObject:_messages forKey:@"messages"];
	}
	/* The forms it is made with: a table each. */
	if ([_parts count] > 0) {
		NSMutableArray *with = [NSMutableArray array];
		for (ORMFormDocument *part in _parts) {
			part.messages = self.messages;
			[with addObject:[part tablePropertyList]];
		}
		[list setObject:with forKey:@"with"];
	}
	/* A repeat's link; the repeats, each a table of its own. */
	if (_linkNodeId != nil) {
		[list setObject:[self linkElement] ?: @"link" forKey:@"link"];
	}
	if (_isList) {
		[list setObject:@YES forKey:@"list"];
	}
	if (_from != nil) {
		[list setObject:_from forKey:@"from"];
	}
	if (_fromGroup != nil) {
		[list setObject:_fromGroup forKey:@"fromGroup"];
	}
	if (_subtype != nil) {
		[list setObject:_subtype forKey:@"subtype"];
	}
	if ([_repeats count] > 0) {
		NSMutableDictionary *repeats = [NSMutableDictionary dictionary];
		[_repeats enumerateKeysAndObjectsUsingBlock:^(NSString *name, ORMFormDocument *repeat, BOOL *stop) {
			repeat.messages = self.messages;
			[repeats setObject:[repeat tablePropertyList] forKey:name];
		}];
		[list setObject:repeats forKey:@"repeats"];
	}
	return list;
}

#pragma mark The document

- (NSXMLElement *)instanceGiven:(NSDictionary<NSString *, NSString *> *)values
{
	NSXMLElement *instance = [NSXMLElement elementWithName:_entityName];
	[instance addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:@""]];
	for (ORMFormField *field in _fields) {
		/* An owned object's elements under its own ("contact/contactName"). */
		NSArray *path = [field.elementName componentsSeparatedByString:@"/"];
		NSXMLElement *parent = instance;
		for (NSString *step in [path subarrayWithRange:NSMakeRange(0, [path count] - 1)]) {
			NSXMLElement *child = [[parent elementsForName:step] firstObject];
			if (child == nil) {
				child = [NSXMLElement elementWithName:step];
				[parent addChild:child];
			}
			parent = child;
		}
		[parent addChild:[NSXMLElement elementWithName:[path lastObject] stringValue:[values objectForKey:field.elementName] ?: @""]];
	}
	return instance;
}

static NSXMLElement *
ORMXElement(NSString *name, NSDictionary<NSString *, NSString *> *attributes)
{
	NSXMLElement *element = [NSXMLElement elementWithName:name];
	for (NSString *key in [[attributes allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		[element addAttribute:[NSXMLNode attributeWithName:key stringValue:[attributes objectForKey:key]]];
	}
	return element;
}

static NSXMLElement *
ORMXText(NSString *name, NSString *text)
{
	NSXMLElement *element = [NSXMLElement elementWithName:name];
	[element setStringValue:text ?: @""];
	return element;
}

- (NSXMLDocument *)document
{
	NSXMLElement *html = [NSXMLElement elementWithName:@"html"];
	[html addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:ORMXHTMLNamespace]];
	[html addNamespace:[NSXMLNode namespaceWithName:@"xf" stringValue:ORMXFormsNamespace]];
	[html addNamespace:[NSXMLNode namespaceWithName:@"ev" stringValue:ORMEventsNamespace]];
	[html addNamespace:[NSXMLNode namespaceWithName:@"xsd" stringValue:ORMSchemaNamespace]];
	[html addNamespace:[NSXMLNode namespaceWithName:@"ormf" stringValue:ORMFormNamespace]];
	if ([_warnings count] > 0) {
		[html addNamespace:[NSXMLNode namespaceWithName:@"xfk" stringValue:ORMXFormsKitNamespace]];
	}
	NSXMLElement *head = [NSXMLElement elementWithName:@"head"];
	[head addChild:ORMXText(@"title", _form.name)];
	[head addChild:[NSXMLNode commentWithStringValue:@" Generated by ormtool xforms from the model's form: never edited. "]];
	[head addChild:[_parts count] > 0 ? [self modelOfAnchors] : [self model]];
	if ([_checked count] > 0) {
		NSXMLElement *checks = ORMXElement(@"ormf:checks", @{});
		for (NSString *text in [self checkedWhereSubmitted]) {
			[checks addChild:ORMXText(@"ormf:checkedWhereSubmitted", text)];
		}
		[head addChild:checks];
	}
	[html addChild:head];
	NSXMLElement *body = [NSXMLElement elementWithName:@"body"];
	[self addControlsTo:body];
	[html addChild:body];
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithRootElement:html];
	[document setCharacterEncoding:@"UTF-8"];
	return document;
}

- (NSXMLElement *)model
{
	NSXMLElement *model = ORMXElement(@"xf:model", @{ @"id" : [@"form-" stringByAppendingString:_form.identifier] });
	NSXMLElement *instance = ORMXElement(@"xf:instance", @{ @"id" : @"form" });
	[instance addChild:[self instanceGiven:@{}]];
	[model addChild:instance];
	NSArray *choices = [self choiceNames];
	for (NSString *name in choices) {
		NSXMLElement *list = ORMXElement(@"xf:instance", @{ @"id" : [self choicesInstanceOf:name] });
		NSXMLElement *empty = [NSXMLElement elementWithName:@"choices"];
		[empty addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:@""]];
		[list addChild:empty];
		[model addChild:list];
	}
	for (ORMFormField *field in _fields) {
		[model addChild:[self bindElement:[self bindOf:field]]];
	}
	/* Each repeat's: a row to add, its binds under its rows, its choices. */
	NSMutableArray *repeatChoices = [NSMutableArray array];
	[self addRepeatsTo:model choices:repeatChoices];
	/* What ought to hold: XFormsKit shows each at its element, the form
	 * valid all the same. */
	for (ORMFormWarning *warning in _warnings) {
		NSXMLElement *element = ORMXElement(@"xfk:warning", @{
			@"ref" : warning.elementName, @"test" : warning.test, @"ormf:constraint" : warning.constraintId,
		});
		[element setStringValue:[self say:warning.text of:warning.constraintId]];
		[model addChild:element];
	}
	/* Reads are not validated: a new form's required fields are empty
	 * until the user enters them. */
	[model addChild:ORMXElement(@"xf:submission", @{
		@"id" : @"read", @"resource" : @"form:read", @"method" : @"get", @"ref" : @"instance('form')",
		@"replace" : @"instance", @"instance" : @"form", @"validate" : @"false",
	})];
	for (NSString *name in choices) {
		[model addChild:[self choicesSubmissionOf:name]];
	}
	NSXMLElement *save = ORMXElement(@"xf:submission", @{
		@"id" : @"save", @"resource" : _action != nil ? [@"form:submit/" stringByAppendingString:_action] : @"form:save",
		@"method" : @"post", @"ref" : @"instance('form')",
		@"replace" : @"instance", @"instance" : @"form",
	});
	/* What the flow does next, the save done or refused. */
	for (ORMFlowTransition *transition in [self transitionsOn:@[ ORMFlowOnSubmitDone, ORMFlowOnSubmitError ]]) {
		NSString *event = [transition.on isEqualToString:ORMFlowOnSubmitDone] ? @"xforms-submit-done" : @"xforms-submit-error";
		NSXMLElement *action = ORMXElement(@"xf:action", @{ @"ev:event" : event });
		[action addChild:[self loadOf:transition]];
		[save addChild:action];
	}
	[model addChild:save];
	/* Opened: the object read (or the new one made, its given values in
	 * it), then each reference's choices. */
	NSXMLElement *ready = ORMXElement(@"xf:action", @{ @"ev:event" : @"xforms-ready" });
	[ready addChild:ORMXElement(@"xf:send", @{ @"submission" : @"read" })];
	for (NSString *name in choices) {
		[ready addChild:ORMXElement(@"xf:send", @{ @"submission" : [self choicesInstanceOf:name] })];
	}
	for (NSString *submission in repeatChoices) {
		[ready addChild:ORMXElement(@"xf:send", @{ @"submission" : submission })];
	}
	[model addChild:ready];
	return model;
}

/* "choices-driver"; a repeat's, "choices-purchaseLines-stockItem". */
- (NSString *)choicesInstanceOf:(NSString *)name
{
	NSMutableArray *path = [NSMutableArray arrayWithObject:@"choices"];
	if (_partName != nil) {
		[path addObject:_partName];
	}
	if (_repeatPath != nil) {
		[path addObject:[_repeatPath stringByReplacingOccurrencesOfString:@"/" withString:@"-"]];
	}
	[path addObject:name];
	return [path componentsJoinedByString:@"-"];
}

/* What reads a reference's choices: "form:choices/driver"; a repeat's,
 * "form:choices/purchaseLines/stockItem". */
- (NSXMLElement *)choicesSubmissionOf:(NSString *)name
{
	NSMutableArray *path = [NSMutableArray array];
	if (_partName != nil) {
		[path addObject:_partName];
	}
	if (_repeatPath != nil) {
		[path addObject:_repeatPath];
	}
	[path addObject:name];
	NSString *resource = [@"form:choices/" stringByAppendingString:[path componentsJoinedByString:@"/"]];
	return ORMXElement(@"xf:submission", @{
		@"id" : [self choicesInstanceOf:name], @"resource" : resource, @"method" : @"get", @"ref" : @"instance('form')",
		@"replace" : @"instance", @"instance" : [self choicesInstanceOf:name], @"validate" : @"false",
	});
}

/* Each repeat, nested ones within: an instance of one empty row to add
 * ("row-purchaseLines"), its binds at its rows ("purchaseLines/quantity"),
 * its choices' instances and submissions (their ids put in choices). */
- (void)addRepeatsTo:(NSXMLElement *)model choices:(NSMutableArray<NSString *> *)choices
{
	[self addRepeatsTo:model binds:model choices:choices];
}

/* The same, the binds in a bind of their own (an anchor's of several). */
- (void)addRepeatsTo:(NSXMLElement *)model binds:(NSXMLElement *)binds choices:(NSMutableArray<NSString *> *)choices
{
	for (NSString *name in [[_repeats allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		ORMFormDocument *repeat = [_repeats objectForKey:name];
		NSXMLElement *template = ORMXElement(@"xf:instance", @{ @"id" : [repeat rowInstanceId] });
		NSXMLElement *row = [repeat instanceGiven:@{}];
		[row setName:[[name componentsSeparatedByString:@"/"] lastObject]];
		[template addChild:row];
		[model addChild:template];
		for (ORMFormField *field in repeat.fields) {
			[binds addChild:[repeat bindElement:[repeat bindOf:field]]];
		}
		for (NSString *choice in [repeat choiceNames]) {
			NSXMLElement *list = ORMXElement(@"xf:instance", @{ @"id" : [repeat choicesInstanceOf:choice] });
			NSXMLElement *empty = [NSXMLElement elementWithName:@"choices"];
			[empty addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:@""]];
			[list addChild:empty];
			[model addChild:list];
			[model addChild:[repeat choicesSubmissionOf:choice]];
			[choices addObject:[repeat choicesInstanceOf:choice]];
		}
		[repeat addRepeatsTo:model binds:binds choices:choices];
	}
}

/* A repeat's instance of one empty row: "row-purchaseLines". */
- (NSString *)rowInstanceId
{
	NSString *row = [@"row-" stringByAppendingString:[_repeatPath stringByReplacingOccurrencesOfString:@"/" withString:@"-"] ?: @""];
	return _partName != nil ? [NSString stringWithFormat:@"row-%@-%@", _partName, [row substringFromIndex:4]] : row;
}

/* The model of several anchors: one instance, an element of each anchor's
 * named as its form; each one's binds in a bind at it; each read by its
 * key, into its element; one save of them all. */
- (NSXMLElement *)modelOfAnchors
{
	NSArray<ORMFormDocument *> *all = [@[ self ] arrayByAddingObjectsFromArray:_parts];
	NSXMLElement *model = ORMXElement(@"xf:model", @{ @"id" : [@"form-" stringByAppendingString:_form.identifier] });
	NSXMLElement *instance = ORMXElement(@"xf:instance", @{ @"id" : @"form" });
	NSXMLElement *forms = [NSXMLElement elementWithName:@"forms"];
	[forms addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:@""]];
	for (ORMFormDocument *each in all) {
		NSXMLElement *anchor = [each instanceGiven:@{}];
		[anchor setName:each.form.name];
		[forms addChild:anchor];
	}
	[instance addChild:forms];
	[model addChild:instance];
	NSMutableArray *choices = [NSMutableArray array];
	for (ORMFormDocument *each in all) {
		for (NSString *name in [each choiceNames]) {
			NSXMLElement *list = ORMXElement(@"xf:instance", @{ @"id" : [each choicesInstanceOf:name] });
			NSXMLElement *empty = [NSXMLElement elementWithName:@"choices"];
			[empty addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:@""]];
			[list addChild:empty];
			[model addChild:list];
			[choices addObject:[each choicesInstanceOf:name]];
		}
		NSXMLElement *binds = ORMXElement(@"xf:bind", @{ @"id" : [@"bind-form-" stringByAppendingString:each.form.name ?: @""],
		                                                  @"nodeset" : each.form.name ?: @"" });
		for (ORMFormField *field in each.fields) {
			[binds addChild:[each bindElement:[each bindOf:field]]];
		}
		[each addRepeatsTo:model binds:binds choices:choices];
		[model addChild:binds];
		for (ORMFormWarning *warning in each->_warnings) {
			NSXMLElement *element = ORMXElement(@"xfk:warning", @{
				@"ref" : [NSString stringWithFormat:@"%@/%@", each.form.name, warning.elementName], @"test" : warning.test,
				@"ormf:constraint" : warning.constraintId,
			});
			[element setStringValue:[each say:warning.text of:warning.constraintId]];
			[model addChild:element];
		}
		[model addChild:ORMXElement(@"xf:submission", @{
			@"id" : [@"read-" stringByAppendingString:each.form.name ?: @""],
			@"resource" : [@"form:read/" stringByAppendingString:each.form.name ?: @""], @"method" : @"get",
			@"ref" : [NSString stringWithFormat:@"instance('form')/%@", each.form.name], @"replace" : @"instance",
			@"targetref" : [NSString stringWithFormat:@"instance('form')/%@", each.form.name], @"validate" : @"false",
		})];
	}
	for (ORMFormDocument *each in all) {
		for (NSString *name in [each choiceNames]) {
			[model addChild:[each choicesSubmissionOf:name]];
		}
	}
	NSXMLElement *save = ORMXElement(@"xf:submission", @{
		@"id" : @"save", @"resource" : _action != nil ? [@"form:submit/" stringByAppendingString:_action] : @"form:save",
		@"method" : @"post", @"ref" : @"instance('form')", @"replace" : @"instance", @"instance" : @"form",
	});
	for (ORMFlowTransition *transition in [self transitionsOn:@[ ORMFlowOnSubmitDone, ORMFlowOnSubmitError ]]) {
		NSString *event = [transition.on isEqualToString:ORMFlowOnSubmitDone] ? @"xforms-submit-done" : @"xforms-submit-error";
		NSXMLElement *action = ORMXElement(@"xf:action", @{ @"ev:event" : event });
		[action addChild:[self loadOf:transition]];
		[save addChild:action];
	}
	[model addChild:save];
	NSXMLElement *ready = ORMXElement(@"xf:action", @{ @"ev:event" : @"xforms-ready" });
	for (ORMFormDocument *each in all) {
		[ready addChild:ORMXElement(@"xf:send", @{ @"submission" : [@"read-" stringByAppendingString:each.form.name ?: @""] })];
	}
	for (NSString *submission in choices) {
		[ready addChild:ORMXElement(@"xf:send", @{ @"submission" : submission })];
	}
	[model addChild:ready];
	return model;
}

- (NSXMLElement *)bindElement:(ORMFormBind *)bind
{
	ORMFormField *field = bind.field;
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
	[attributes setObject:[@"bind-" stringByAppendingString:[field fieldId]] forKey:@"id"];
	/* A repeat's at its rows, from the outermost form's anchor. */
	[attributes setObject:_repeatPath != nil ? [NSString stringWithFormat:@"%@/%@", _repeatPath, field.elementName] : field.elementName
	               forKey:@"ref"];
	/* XForms' own datatypes: XML Schema's, but empty is one of their
	 * values, as an optional field's is until it is entered (required says
	 * whether it may stay so). */
	[attributes setObject:[field.schemaType stringByReplacingOccurrencesOfString:@"xsd:" withString:@"xf:"] forKey:@"type"];
	if ([bind.required count] > 0) {
		[attributes setObject:[bind.required containsObject:@"true()"] ? @"true()"
		                       : [NSString stringWithFormat:@"(%@)", [bind.required componentsJoinedByString:@") or ("]]
		               forKey:@"required"];
	}
	if ([bind.relevant count] > 0) {
		[attributes setObject:[NSString stringWithFormat:@"(%@)", [bind.relevant componentsJoinedByString:@") and ("]]
		               forKey:@"relevant"];
	}
	if ([bind.constraint count] > 0) {
		[attributes setObject:[NSString stringWithFormat:@"(%@)", [bind.constraint componentsJoinedByString:@") and ("]]
		               forKey:@"constraint"];
	}
	if (bind.readonly) {
		[attributes setObject:@"true()" forKey:@"readonly"];
	}
	if (bind.calculate != nil) {
		[attributes setObject:bind.calculate forKey:@"calculate"];
	}
	if ([bind.sources count] > 0) {
		[attributes setObject:[bind.sources componentsJoinedByString:@" "] forKey:@"ormf:constraints"];
	}
	/* What the element is to whoever opens the form, as its table says:
	 * "given" its inputs (a process's task fills them from its variables). */
	[attributes setObject:[self roleOfField:field] forKey:@"ormf:role"];
	return ORMXElement(@"xf:bind", attributes);
}

/* What a field is called, in the document's controls and the form's table:
 * a unary's reading ("filled the tank"), a part's role, a value's node, a
 * reference's role or its type. */
- (NSString *)labelOfField:(ORMFormField *)field
{
	if (field.kind == ORMFormFieldSubtype) {
		return @"Kind";
	}
	ORMQueryStep *unary = [_unarySteps objectForKey:field.nodeId];
	if (unary != nil) {
		NSString *reading = [[ORMQuery readingOfStep:unary] stringByReplacingOccurrencesOfString:@"{0}" withString:@""];
		return [reading stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	}
	if (field.isPart) {
		return ORMLabelOf(field.role, field.role.player);
	}
	ORMQueryNode *node = [self nodeWithId:field.nodeId];
	return node.isValue ? (node.name ?: @"") : ORMLabelOf(node.role, node.objectType);
}

/* What a field is to whoever opens the form: "key" (the anchor's), "given"
 * (it comes in, and is not entered), "entered", "shown", "calculated", or
 * "hidden" (kept only to compute with). */
- (NSString *)roleOfField:(ORMFormField *)field
{
	if (field.kind == ORMFormFieldSubtype) {
		return @"entered";
	}
	ORMQueryNode *node = [self nodeWithId:field.nodeId];
	ORMQueryStep *unary = [_unarySteps objectForKey:field.nodeId];
	ORMQueryFormPart part = unary != nil ? unary.formPart : node.formPart;
	if (node == _form.root) {
		return @"key";
	}
	if (field.kind == ORMFormFieldCalculated) {
		return @"calculated";
	}
	if (field.kind == ORMFormFieldReference && [[self elementsIdentifying:field.elementName] count] > 0) {
		return @"identified";
	}
	if (part == ORMFormPartEntered && !field.isThrough) {
		return @"entered";
	}
	if (part == ORMFormPartEntered) {
		return @"shown";
	}
	if (part == ORMFormPartShown) {
		return @"shown";
	}
	return node.isGiven ? @"given" : @"hidden";
}

/* The field's control: a compound's group of its parts' (once); nil for
 * one with none (the anchor's key, what is only computed with). */
- (NSXMLElement *)controlOfField:(ORMFormField *)field done:(NSMutableSet *)done
{
	ORMQueryNode *node = [self nodeWithId:field.nodeId];
	ORMQueryStep *unary = [_unarySteps objectForKey:field.nodeId];
	if (unary != nil) {
		return [self controlOf:field node:nil label:[self labelOfField:field]];
	}
	if (field.kind == ORMFormFieldSubtype) {
		NSXMLElement *control = ORMXElement(@"xf:select1", @{
			@"id" : [@"control-" stringByAppendingString:[field fieldId]], @"bind" : [@"bind-" stringByAppendingString:[field fieldId]],
		});
		[control addChild:ORMXText(@"xf:label", [self labelOfField:field])];
		for (NSString *subtype in [self subtypeEntities]) {
			NSXMLElement *item = [NSXMLElement elementWithName:@"xf:item"];
			[item addChild:ORMXText(@"xf:label", [self labelOfSubtype:subtype])];
			[item addChild:ORMXText(@"xf:value", subtype)];
			[control addChild:item];
		}
		return control;
	}
	/* A reference found by values entered: theirs are its controls. */
	if (field.isHidden || node == _form.root || [done containsObject:field.nodeId]
	    || (node.formPart == ORMFormPartNone && field.kind != ORMFormFieldCalculated)
	    || [[self elementsIdentifying:field.elementName] count] > 0) {
		return nil;
	}
	if (field.isPart) {
		[done addObject:field.nodeId];
		NSXMLElement *group = ORMXElement(@"xf:group", @{ @"id" : [@"control-" stringByAppendingString:field.nodeId] });
		[group addChild:ORMXText(@"xf:label", ORMLabelOf(node.role, node.objectType))];
		for (ORMFormField *part in [self fieldsOfNode:field.nodeId]) {
			[group addChild:[self controlOf:part node:node label:[self labelOfField:part]]];
		}
		return group;
	}
	return [self controlOf:field node:node label:[self labelOfField:field]];
}

/* An owned object's controls, in a group labelled as the form names it
 * (Contact; its Shipping Address within). */
- (NSXMLElement *)controlOfGroup:(NSString *)name done:(NSMutableSet *)done
{
	[done addObject:[@"group:" stringByAppendingString:name]];
	ORMQueryNode *owned = [_groupNodes objectForKey:name];
	NSXMLElement *group = ORMXElement(@"xf:group", @{
		@"id" : [@"control-" stringByAppendingString:[name stringByReplacingOccurrencesOfString:@"/" withString:@"-"]],
	});
	[group addChild:ORMXText(@"xf:label", ORMLabelOf(owned.role, owned.objectType))];
	NSString *within = [name stringByAppendingString:@"/"];
	for (ORMFormField *field in _fields) {
		NSXMLElement *control = nil;
		if ([field.groupName isEqualToString:name]) {
			control = [self controlOfField:field done:done];
		} else if ([field.groupName hasPrefix:within]) {
			NSString *inner = [within stringByAppendingString:[[[field.groupName substringFromIndex:[within length]]
			                                                       componentsSeparatedByString:@"/"] firstObject]];
			control = [done containsObject:[@"group:" stringByAppendingString:inner]] ? nil : [self controlOfGroup:inner done:done];
		}
		if (control != nil) {
			[group addChild:control];
		}
	}
	return group;
}

/* The fields' controls, in order, an owned object's in its group; then
 * each repeat's. */
- (void)addFieldControlsTo:(NSXMLElement *)parent
{
	NSMutableSet *done = [NSMutableSet set];
	for (ORMFormField *field in _fields) {
		NSXMLElement *control = nil;
		if (field.groupName != nil) {
			NSString *outer = [[field.groupName componentsSeparatedByString:@"/"] firstObject];
			control = [done containsObject:[@"group:" stringByAppendingString:outer]] ? nil : [self controlOfGroup:outer done:done];
		} else {
			control = [self controlOfField:field done:done];
		}
		if (control != nil) {
			[parent addChild:control];
		}
	}
	for (NSString *name in [[_repeats allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		ORMFormDocument *repeat = [_repeats objectForKey:name];
		NSXMLElement *control = [repeat repeatControlNamed:name];
		if (repeat->_subtype != nil) {
			/* Of a subtype part: shown where the object is one. */
			[control addAttribute:[NSXMLNode attributeWithName:@"ref"
			                                       stringValue:[NSString stringWithFormat:@"self::node()[%@]",
			                                                                              [self kindTestOf:repeat->_subtype up:0]]]];
		}
		[parent addChild:control];
	}
}

/* A repeat's group: its rows in an xf:repeat, each with its controls (the
 * link to the form it is in the app's) and, where the rows are written, a
 * trigger taking it away; after them one adding a row. A list's rows only
 * shown. */
- (NSXMLElement *)repeatControlNamed:(NSString *)name
{
	NSString *dashed = [_repeatPath stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
	NSXMLElement *group = ORMXElement(@"xf:group", @{ @"id" : [@"control-rows-" stringByAppendingString:dashed] });
	[group addChild:ORMXText(@"xf:label", ORMLabelOf(_form.root.role, _form.root.objectType))];
	NSXMLElement *repeat = ORMXElement(@"xf:repeat", @{ @"id" : [@"repeat-" stringByAppendingString:dashed], @"nodeset" : name });
	[self addFieldControlsTo:repeat];
	BOOL written = NO;
	for (ORMFormField *field in _fields) {
		written = written || [[self roleOfField:field] isEqualToString:@"entered"];
	}
	if (written) {
		NSXMLElement *remove = ORMXElement(@"xf:trigger", @{ @"id" : [@"control-remove-" stringByAppendingString:dashed] });
		[remove addChild:ORMXText(@"xf:label", @"Remove")];
		[remove addChild:ORMXElement(@"xf:delete", @{ @"ev:event" : @"DOMActivate", @"nodeset" : @"." })];
		[repeat addChild:remove];
	}
	[group addChild:repeat];
	if (written) {
		NSXMLElement *add = ORMXElement(@"xf:trigger", @{ @"id" : [@"control-add-" stringByAppendingString:dashed] });
		[add addChild:ORMXText(@"xf:label", @"Add")];
		/* Within the object the rows are of: an owned one's group. */
		NSArray *path = [name componentsSeparatedByString:@"/"];
		NSString *within = [path count] > 1 ? [[path subarrayWithRange:NSMakeRange(0, [path count] - 1)] componentsJoinedByString:@"/"] : @".";
		[add addChild:ORMXElement(@"xf:insert", @{
			@"ev:event" : @"DOMActivate", @"context" : within, @"nodeset" : [path lastObject], @"at" : @"last()", @"position" : @"after",
			@"origin" : [NSString stringWithFormat:@"instance('%@')/%@", [self rowInstanceId], [path lastObject]],
		})];
		[group addChild:add];
	}
	return group;
}

- (void)addControlsTo:(NSXMLElement *)body
{
	if ([_parts count] > 0) {
		/* Several anchors: a group of each's controls, at its element. */
		for (ORMFormDocument *each in [@[ self ] arrayByAddingObjectsFromArray:_parts]) {
			NSXMLElement *group = ORMXElement(@"xf:group", @{ @"id" : [@"control-form-" stringByAppendingString:each.form.name ?: @""],
			                                                   @"ref" : each.form.name ?: @"" });
			[group addChild:ORMXText(@"xf:label", each.form.name)];
			[each addFieldControlsTo:group];
			[body addChild:group];
		}
	} else {
		[self addFieldControlsTo:body];
	}
	NSXMLElement *submit = ORMXElement(@"xf:submit", @{ @"id" : @"control-save", @"submission" : @"save" });
	[submit addChild:ORMXText(@"xf:label", @"Save")];
	[body addChild:submit];
	/* The flow's ways on from here a user takes: Cancel, and the triggers. */
	for (ORMFlowTransition *transition in [self transitionsOn:@[ ORMFlowOnCancel, ORMFlowOnTrigger ]]) {
		BOOL cancel = [transition.on isEqualToString:ORMFlowOnCancel];
		NSString *control = cancel ? @"cancel" : transition.control;
		ORMFlowScreen *to = transition.toScreen != nil ? [_flow screenWithId:transition.toScreen] : nil;
		NSXMLElement *trigger = ORMXElement(@"xf:trigger", @{ @"id" : [@"control-" stringByAppendingString:control] });
		[trigger addChild:ORMXText(@"xf:label", cancel ? @"Cancel" : to.name ?: control)];
		NSXMLElement *action = ORMXElement(@"xf:action", @{ @"ev:event" : @"DOMActivate" });
		[action addChild:[self loadOf:transition]];
		[trigger addChild:action];
		[body addChild:trigger];
	}
}

#pragma mark Its flow

- (NSString *)elementOfNode:(NSString *)nodeId
{
	return nodeId != nil ? [_elementOfNode objectForKey:nodeId] : nil;
}

- (NSDictionary<NSString *, NSString *> *)requiredElements
{
	NSMutableDictionary *required = [NSMutableDictionary dictionary];
	for (ORMFormBind *bind in [_binds allValues]) {
		if (([bind.required containsObject:@"true()"] || [bind.required containsObject:@"../* != ''"]) && bind.field.elementName != nil) {
			NSString *said = [self alertTextOf:bind];
			[required setObject:[said length] > 0 ? said : @"A value is required." forKey:bind.field.elementName];
		}
	}
	return required;
}

- (void)setFlow:(ORMFlow *)flow screen:(ORMFlowScreen *)screen
{
	_flow = flow;
	_screen = screen;
}

/* The flow's transitions from the screen on these actions, in its order. */
- (NSArray<ORMFlowTransition *> *)transitionsOn:(NSArray<NSString *> *)actions
{
	NSMutableArray *found = [NSMutableArray array];
	for (ORMFlowTransition *transition in _flow.transitions) {
		if ([transition.fromScreen isEqualToString:_screen.identifier] && [actions containsObject:transition.on ?: @""]) {
			[found addObject:transition];
		}
	}
	return found;
}

/* The document of a screen's form; nil for a list's, or a form gone. */
- (ORMFormDocument *)documentOfScreen:(ORMFlowScreen *)screen
{
	ORMQuery *query = screen.formId != nil ? [_flow queryOf:screen inModel:_model] : nil;
	return query != nil ? [ORMFormDocument documentForForm:query model:_model mapping:_mapping reason:NULL] : nil;
}

/* An XPath string literal of the text. */
static NSString *
ORMXPathLiteral(NSString *text)
{
	return [text rangeOfString:@"'"].location == NSNotFound ? [NSString stringWithFormat:@"'%@'", text]
		: [NSString stringWithFormat:@"\"%@\"", text];
}

/* What a value given comes from, as an XPath expression of this form's
 * instance: its key for the result, its element for one of its nodes, the
 * app's "{<screen>.<node>}" for a screen's before it. */
- (NSString *)valueOf:(ORMFlowGive *)give
{
	if ([give.from isEqualToString:@"result"]) {
		return [NSString stringWithFormat:@"instance('form')/%@", [[_fields firstObject] elementName]];
	}
	NSRange dot = [give.from rangeOfString:@"."];
	if (dot.location != NSNotFound && [[give.from substringToIndex:dot.location] isEqualToString:_screen.identifier]) {
		NSString *element = [self elementOfNode:[give.from substringFromIndex:NSMaxRange(dot)]];
		if (element != nil) {
			return [NSString stringWithFormat:@"instance('form')/%@", element];
		}
	}
	return ORMXPathLiteral([NSString stringWithFormat:@"{%@}", give.from ?: @""]);
}

/* The xf:load a transition is: where it goes, and what it gives there. */
- (NSXMLElement *)loadOf:(ORMFlowTransition *)transition
{
	ORMFlowScreen *to = transition.toScreen != nil ? [_flow screenWithId:transition.toScreen] : nil;
	BOOL overlay = [transition.kind isEqualToString:ORMFlowKindOverlay];
	if ([transition.kind isEqualToString:ORMFlowKindBack]) {
		return ORMXElement(@"xf:load", @{ @"resource" : @"form:back" });
	}
	NSString *base = nil;
	ORMFormDocument *named = nil;
	if ([transition.kind isEqualToString:ORMFlowKindClose]) {
		base = @"form:close";
		/* The values go to the form it is over: an overlay's opener. */
		for (ORMFlowTransition *each in _flow.transitions) {
			if ([each.kind isEqualToString:ORMFlowKindOverlay] && [each.toScreen isEqualToString:_screen.identifier]) {
				named = [self documentOfScreen:[_flow screenWithId:each.fromScreen]];
				break;
			}
		}
	} else if (to.queryId != nil) {
		ORMQuery *list = [_flow queryOf:to inModel:_model];
		return ORMXElement(@"xf:load", @{ @"resource" : [@"form:list/" stringByAppendingString:list.name ?: to.queryId] });
	} else {
		named = [self documentOfScreen:to];
		base = [@"form:open/" stringByAppendingString:named.form.name ?: to.name ?: transition.toScreen ?: @""];
	}
	NSMutableArray *parts = [NSMutableArray array];
	NSString *separator = @"?";
	for (ORMFlowGive *give in transition.gives) {
		NSString *element = [named elementOfNode:give.nodeId] ?: give.nodeId;
		[parts addObject:ORMXPathLiteral([NSString stringWithFormat:@"%@%@=", separator, element])];
		[parts addObject:[self valueOf:give]];
		separator = @"&";
	}
	NSDictionary *show = @{ @"show" : overlay ? @"new" : @"replace" };
	if ([parts count] == 0) {
		NSMutableDictionary *attributes = [show mutableCopy];
		[attributes setObject:base forKey:@"resource"];
		return ORMXElement(@"xf:load", attributes);
	}
	NSXMLElement *load = ORMXElement(@"xf:load", show);
	NSString *value = [NSString stringWithFormat:@"concat(%@, %@)", ORMXPathLiteral(base), [parts componentsJoinedByString:@", "]];
	[load addChild:ORMXElement(@"xf:resource", @{ @"value" : value })];
	return load;
}

- (NSXMLElement *)controlOf:(ORMFormField *)field node:(ORMQueryNode *)node label:(NSString *)label
{
	NSString *identifier = [@"control-" stringByAppendingString:[field fieldId]];
	NSString *bind = [@"bind-" stringByAppendingString:[field fieldId]];
	ORMQueryStep *unary = [_unarySteps objectForKey:field.nodeId];
	BOOL shown = (unary != nil ? unary.formPart : node.formPart) == ORMFormPartShown || field.kind == ORMFormFieldCalculated;
	ORMValueConstraint *values = field.role.valueConstraint ?: [field.role.player valueType].valueConstraint;
	/* A value list, or the one of the type a reference is to (units). */
	NSArray *items = field.kind == ORMFormFieldValue ? ORMItemsOf(values) : ORMItemsOf(field.referredType.valueConstraint);
	/* A set of choices (D17): a select, each object picked or not. */
	NSString *kind = shown ? @"xf:output"
		: field.isMany ? @"xf:select"
		: field.kind == ORMFormFieldReference || items != nil ? @"xf:select1" : @"xf:input";
	NSXMLElement *control = ORMXElement(kind, @{ @"id" : identifier, @"bind" : bind });
	if (field.isMany && !shown) {
		[control addAttribute:[NSXMLNode attributeWithName:@"appearance" stringValue:@"full"]];
	}
	[control addChild:ORMXText(@"xf:label", label)];
	NSString *note = (unary ?: node.step).factType.noteText;
	if ([note length] > 0 && !shown && field.partIndex == 0) {
		[control addChild:ORMXText(@"xf:hint", note)];
	}
	if (!shown && field.kind == ORMFormFieldReference && items == nil) {
		NSString *instance = [NSString stringWithFormat:@"instance('%@')/*", [self choicesInstanceOf:field.elementName]];
		NSXMLElement *itemset = ORMXElement(@"xf:itemset", @{ @"nodeset" : instance });
		[itemset addChild:ORMXElement(@"xf:label", @{ @"ref" : @"*[1]" })];
		[itemset addChild:ORMXElement(@"xf:value", @{ @"ref" : @"*[1]" })];
		[control addChild:itemset];
	}
	for (NSString *item in items ?: @[]) {
		NSXMLElement *element = [NSXMLElement elementWithName:@"xf:item"];
		[element addChild:ORMXText(@"xf:label", item)];
		[element addChild:ORMXText(@"xf:value", item)];
		[control addChild:element];
	}
	ORMFormBind *formBind = [self bindOf:field];
	if ([formBind.alerts count] > 0 && !shown) {
		[control addChild:ORMXText(@"xf:alert", [self alertTextOf:formBind])];
	}
	/* A reference whose choices depend on this one: read again as it
	 * changes. */
	if (!shown) {
		for (NSString *name in [self choiceNames]) {
			if ([[self elementsChoicesDependOn:name] containsObject:field.elementName]) {
				NSXMLElement *action = ORMXElement(@"xf:action", @{ @"ev:event" : @"xforms-value-changed" });
				[action addChild:ORMXElement(@"xf:send", @{ @"submission" : [self choicesInstanceOf:name] })];
				[control addChild:action];
			}
		}
	}
	return control;
}

- (NSArray<NSString *> *)checkedWhereSubmitted
{
	NSMutableArray *said = [NSMutableArray array];
	for (NSString *text in _checked) {
		[said addObject:[self say:text of:[_sourceOfCheck objectForKey:text]]];
	}
	return said;
}

- (NSArray<NSString *> *)notes
{
	return [_notes copy];
}

@end
