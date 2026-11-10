/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFormDocument.h"
#import "ORMModelPriv.h"
#import "ORMVerbalizer.h"
#import "ORMFlow.h"

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
	/* The flow's screen it is shown as: its transitions, its actions. */
	ORMFlow *_flow;
	ORMFlowScreen *_screen;
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
	return [self makeForm:form stored:stored model:model mapping:mapping];
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
	_verbalizer = [[ORMVerbalizer alloc] initWithModel:model];
	_fields = [NSMutableArray array];
	_notes = [NSMutableArray array];
	_checked = [NSMutableArray array];
	_binds = [NSMutableDictionary dictionary];
	_warnings = [NSMutableArray array];
	_conditionSteps = [NSMutableSet set];
	_elementOfNode = [NSMutableDictionary dictionary];
	_unarySteps = [NSMutableDictionary dictionary];
	for (ORMQueryStep *step in form.root.steps) {
		if (step.formPart != ORMFormPartNone && [step.factType isUnary]) {
			[_unarySteps setObject:step forKey:step.identifier];
		}
	}
	for (ORMQueryNode *node in [form nodes]) {
		if (node != form.root && !node.isValue && node.formPart == ORMFormPartEntered && ORMPartsOf(node) == nil) {
			for (ORMQueryStep *step in node.steps) {
				[_conditionSteps addObject:step.identifier];
			}
		}
	}
	ORMQueryPlan *plan = [self readPlanForKey:nil];
	if (plan.entityName == nil) {
		return [NSString stringWithFormat:@"The mapping places no entity for %@.", form.root.objectType.name];
	}
	_entityName = [plan.entityName copy];
	[_notes addObjectsFromArray:plan.notes];
	[self placeNodesIn:plan];
	[self placeUnariesIn:plan];
	[self bindValues];
	[self bindConstraints];
	[self makeRepeats];
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
		ORMQueryStep *formStep = nil;
		for (ORMQueryStep *each in _form.root.steps) {
			if ([each.identifier isEqualToString:stepId]) {
				formStep = each;
			}
		}
		ORMQueryNode *reachedNode = [formStep.nodes firstObject];
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
		anchor.identifier = [_form.root.identifier stringByAppendingString:@"-of"];
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
		NSString *why = query != nil ? [repeat makeForm:query stored:stored model:_model mapping:_mapping] : @"it cannot be read";
		if (why != nil) {
			[_notes addObject:[NSString stringWithFormat:@"%@: a repeat not made: %@", name, why]];
			continue;
		}
		[_notes addObjectsFromArray:repeat.notes];
		[_repeats setObject:repeat forKey:name];
	}
}

- (NSDictionary<NSString *, ORMFormDocument *> *)repeats
{
	return _repeats;
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
	}
	return listed;
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
			    || [_repeatSteps objectForKey:part.identifier] != nil) {
				[conditions addObject:part];
			} else if (part.operatorName == nil && part.parent == copy.root
			           && !(_linkNodeId != nil && [[[part nodes] firstObject].identifier isEqualToString:_linkNodeId])) {
				/* What is not given yet leaves no object out. */
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
	for (ORMQueryStep *step in [_form.root.steps copy]) {
		NSString *attribute = [_unarySteps objectForKey:step.identifier] != nil ? [_planner attributeOfUnaryStep:step] : nil;
		if (attribute != nil) {
			[columns addObject:[ORMPlanColumn columnTitled:[step.factType displayText]
			                                          node:step.identifier
			                                          path:[ORMPlanPath pathFrom:nil keys:@[ attribute ]]
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
		if (column == nil) {
			[_notes addObject:[NSString stringWithFormat:@"%@: the mapping places it nowhere.", name]];
			continue;
		}
		BOOL hidden = node.formPart == ORMFormPartNone && !node.isGiven && node != _form.root;
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
		NSString *entity = _entityName;
		BOOL toOnes = YES;
		for (NSString *key in keys) {
			ORMCDRelationship *relationship = (ORMCDRelationship *)ORMPropertyOf(coreData, entity, key);
			if ([relationship isKindOfClass:[ORMCDRelationship class]]) {
				toOnes = toOnes && !relationship.toMany;
				entity = relationship.destination;
			}
		}
		if (!toOnes) {
			/* Under a step from the anchor to many: a repeat's. */
			ORMQueryStep *top = [self topStepOf:node];
			ORMCDRelationship *first = (ORMCDRelationship *)ORMPropertyOf(coreData, _entityName, [keys firstObject]);
			if (top != nil && [first isKindOfClass:[ORMCDRelationship class]] && first.toMany) {
				[_repeatSteps setObject:[keys firstObject] forKey:top.identifier];
			} else {
				[_notes addObject:[NSString stringWithFormat:@"%@: one of many, not reached by one step from the anchor.", name]];
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
			if ([keys count] > 0) {
				[_notes addObject:[NSString stringWithFormat:@"%@: a compound not the anchor's own.", name]];
				continue;
			}
			NSArray *parts = ORMPartsOf(node);
			NSUInteger index = 0;
			for (NSArray<NSString *> *partKeys in column.identifierParts) {
				ORMRole *partRole = index < [parts count] ? [parts objectAtIndex:index] : nil;
				ORMFormField *field = [self fieldFor:node keys:partKeys key:[partKeys count] == 2 ? [partKeys lastObject] : nil
				                               type:partRole.player];
				if (![field.nodeId isEqualToString:node.identifier]) {
					index++;
					continue;
				}
				field.isPart = YES;
				field.partIndex = index++;
				field.role = partRole;
				field.isHidden = hidden;
			}
			continue;
		}
		if ([keys count] != 1) {
			[_notes addObject:[NSString stringWithFormat:@"%@: not one of the anchor's own properties.", name]];
			continue;
		}
		ORMFormField *field = [self fieldFor:node keys:keys key:column.identifierKey type:node.objectType];
		if ([field.nodeId isEqualToString:node.identifier]) {
			field.isHidden = hidden;
		}
	}
}

/* Each unary's flag: an element of its attribute's, a boolean. */
- (void)placeUnariesIn:(ORMQueryPlan *)plan
{
	for (ORMQueryStep *step in _form.root.steps) {
		if ([_unarySteps objectForKey:step.identifier] == nil) {
			continue;
		}
		ORMPlanColumn *column = [plan columnOfNode:step.identifier];
		NSString *name = [column.path.keys firstObject];
		if (name == nil) {
			[_notes addObject:[NSString stringWithFormat:@"\"%@\": the mapping keeps it in no attribute.",
			                                             [step.factType displayText]]];
			continue;
		}
		[self addField:step.identifier name:name kind:ORMFormFieldValue type:@"xsd:boolean"];
	}
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
	ORMCDModel *coreData = _planner.coreData;
	NSString *name = [keys firstObject];
	if (key == nil) {
		ORMCDAttribute *attribute = (ORMCDAttribute *)ORMPropertyOf(coreData, _entityName, name);
		NSString *schemaType = [attribute isKindOfClass:[ORMCDAttribute class]] ? ORMSchemaTypeOf(attribute, [type valueType])
		                                                                        : @"xsd:string";
		ORMFormField *field = [self addField:node.identifier name:name kind:ORMFormFieldValue type:schemaType];
		if ([field.nodeId isEqualToString:node.identifier]) {
			field.role = node.role;
		}
		return field;
	}
	ORMCDRelationship *relationship = (ORMCDRelationship *)ORMPropertyOf(coreData, _entityName, name);
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

#pragma mark Binds

/* "../totalAmount": an element from a sibling's context. */
static NSString *
ORMSibling(NSString *elementName)
{
	return [@"../" stringByAppendingString:elementName];
}

/* The expression in XPath over the elements its nodes are at; nil where it
 * uses what XPath cannot say (a function of moments, an aggregate). */
static NSString *
ORMXPathOf(ORMQueryExpression *expression, NSDictionary<NSString *, NSString *> *elements)
{
	switch (expression.kind) {
	case ORMQueryExpressionNode: {
		NSString *element = [elements objectForKey:expression.nodeId];
		return element != nil ? [NSString stringWithFormat:@"number(%@)", ORMSibling(element)] : nil;
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
		NSString *said = ORMXPathOf(argument, elements);
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
		if (unary != nil) {
			bind.readonly = unary.formPart == ORMFormPartShown;
			continue;
		}
		if (field.kind == ORMFormFieldCalculated) {
			bind.calculate = ORMXPathOf(node.expression, elements);
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
		if (node.formPart == ORMFormPartEntered && entry.isMandatory && node.step.parent == _form.root) {
			for (ORMConstraint *constraint in entry.constraints) {
				if (constraint.kind == ORMMandatoryConstraint && constraint.isSimple) {
					[self apply:constraint to:field];
					if (constraint.modality == ORMAlethic) {
						[bind.required addObject:@"true()"];
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
					[bind.alerts addObject:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
					[bind.required addObject:@"true()"];
				}
			}
		}
		/* A compound is whole or not given: each part where another is. */
		if (field.isPart && node.formPart == ORMFormPartEntered) {
			NSMutableArray *others = [NSMutableArray array];
			for (ORMFormField *other in [self fieldsOfNode:node.identifier]) {
				if (other != field) {
					[others addObject:[NSString stringWithFormat:@"%@ != ''", ORMSibling(other.elementName)]];
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
				[bind.alerts addObject:[NSString stringWithFormat:@"The possible values of %@ are %@.",
				                                                  ORMLabelOf(field.role, field.role.player),
				                                                  [values displayText]]];
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
		[bind.alerts addObject:[self sayElement:constraint.identifier]];
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
		if (node.isValue || node.step.parent != _form.root || field.kind == ORMFormFieldCalculated) {
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

/* "../a = '' and ../b = ''": none of the fields given. */
static NSString *
ORMNoneGiven(NSArray<ORMFormField *> *fields)
{
	NSMutableArray *tests = [NSMutableArray array];
	for (ORMFormField *field in fields) {
		[tests addObject:[NSString stringWithFormat:@"%@ = ''", ORMSibling(field.elementName)]];
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
			[_checked addObject:[self sayElement:constraint.identifier]];
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
			[_checked addObject:[text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
		}
	}
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
			NSString *test = ORMNoneGiven(ORMWithout(all, field));
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
					[self warn:constraint at:field test:[NSString stringWithFormat:@". = '' or (%@)", ORMNoneGiven(others)]];
				} else {
					[[self bindOf:field].relevant addObject:ORMNoneGiven(others)];
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
			NSString *given = [NSString stringWithFormat:@"not(%@)", ORMNoneGiven(those)];
			for (ORMFormField *field in these) {
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
		NSString *a = numeric ? @"number(.)" : @".", *b = ORMSibling(second.elementName);
		if (numeric) {
			b = [NSString stringWithFormat:@"number(%@)", b];
		}
		NSString *test = [NSString stringWithFormat:@". = '' or %@ = '' or %@ %@ %@", ORMSibling(second.elementName), a,
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
		    && ORMItemsOf(field.referredType.valueConstraint) == nil) {
			[names addObject:field.elementName];
		}
	}
	return names;
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
	NSString *name = [self linkElement] ?: [self keyField].elementName;
	if (name == nil) {
		return nil;
	}
	_linkValue = [self linkElement] != nil;
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

static NSString *
ORMFieldKindName(ORMFormFieldKind kind)
{
	return kind == ORMFormFieldReference ? @"reference" : kind == ORMFormFieldCalculated ? @"calculated" : @"value";
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
		if (field.kind == ORMFormFieldReference) {
			[element setObject:field.entityName ?: @"" forKey:@"entity"];
			[element setObject:field.keyName ?: @"" forKey:@"key"];
		}
		/* What a save writes: what the user enters, and what the form is
		 * given; never what it shows or computes. */
		ORMQueryFormPart part = unary != nil ? unary.formPart : node.formPart;
		BOOL written = node != _form.root && field.kind != ORMFormFieldCalculated && !field.isHidden
		               && (part == ORMFormPartEntered || (node.isGiven && part != ORMFormPartShown));
		[element setObject:@(written) forKey:@"written"];
		/* What it is to whoever opens the form, and what it is called. */
		[element setObject:[self roleOfField:field] forKey:@"role"];
		if (node.isGiven) {
			[element setObject:@YES forKey:@"given"];
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
	[list setObject:[self checkedWhereSubmitted] forKey:@"checkedWhereSubmitted"];
	/* A repeat's link; the repeats, each a table of its own. */
	if ([self linkElement] != nil) {
		[list setObject:[self linkElement] forKey:@"link"];
	}
	if ([_repeats count] > 0) {
		NSMutableDictionary *repeats = [NSMutableDictionary dictionary];
		[_repeats enumerateKeysAndObjectsUsingBlock:^(NSString *name, ORMFormDocument *repeat, BOOL *stop) {
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
		[instance addChild:[NSXMLElement elementWithName:field.elementName stringValue:[values objectForKey:field.elementName] ?: @""]];
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
	[head addChild:[self model]];
	if ([_checked count] > 0) {
		NSXMLElement *checks = ORMXElement(@"ormf:checks", @{});
		for (NSString *text in _checked) {
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
		NSXMLElement *list = ORMXElement(@"xf:instance", @{ @"id" : [@"choices-" stringByAppendingString:name] });
		NSXMLElement *empty = [NSXMLElement elementWithName:@"choices"];
		[empty addNamespace:[NSXMLNode namespaceWithName:@"" stringValue:@""]];
		[list addChild:empty];
		[model addChild:list];
	}
	for (ORMFormField *field in _fields) {
		[model addChild:[self bindElement:[self bindOf:field]]];
	}
	/* What ought to hold: XFormsKit shows each at its element, the form
	 * valid all the same. */
	for (ORMFormWarning *warning in _warnings) {
		NSXMLElement *element = ORMXElement(@"xfk:warning", @{
			@"ref" : warning.elementName, @"test" : warning.test, @"ormf:constraint" : warning.constraintId,
		});
		[element setStringValue:warning.text];
		[model addChild:element];
	}
	/* Reads are not validated: a new form's required fields are empty
	 * until the user enters them. */
	[model addChild:ORMXElement(@"xf:submission", @{
		@"id" : @"read", @"resource" : @"form:read", @"method" : @"get", @"ref" : @"instance('form')",
		@"replace" : @"instance", @"instance" : @"form", @"validate" : @"false",
	})];
	for (NSString *name in choices) {
		[model addChild:ORMXElement(@"xf:submission", @{
			@"id" : [@"choices-" stringByAppendingString:name], @"resource" : [@"form:choices/" stringByAppendingString:name],
			@"method" : @"get", @"ref" : @"instance('form')", @"replace" : @"instance",
			@"instance" : [@"choices-" stringByAppendingString:name], @"validate" : @"false",
		})];
	}
	NSXMLElement *save = ORMXElement(@"xf:submission", @{
		@"id" : @"save", @"resource" : @"form:save", @"method" : @"post", @"ref" : @"instance('form')",
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
		[ready addChild:ORMXElement(@"xf:send", @{ @"submission" : [@"choices-" stringByAppendingString:name] })];
	}
	[model addChild:ready];
	return model;
}

- (NSXMLElement *)bindElement:(ORMFormBind *)bind
{
	ORMFormField *field = bind.field;
	NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
	[attributes setObject:[@"bind-" stringByAppendingString:[field fieldId]] forKey:@"id"];
	[attributes setObject:field.elementName forKey:@"ref"];
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
	return ORMXElement(@"xf:bind", attributes);
}

/* What a field is called, in the document's controls and the form's table:
 * a unary's reading ("filled the tank"), a part's role, a value's node, a
 * reference's role or its type. */
- (NSString *)labelOfField:(ORMFormField *)field
{
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
	ORMQueryNode *node = [self nodeWithId:field.nodeId];
	ORMQueryStep *unary = [_unarySteps objectForKey:field.nodeId];
	ORMQueryFormPart part = unary != nil ? unary.formPart : node.formPart;
	if (node == _form.root) {
		return @"key";
	}
	if (field.kind == ORMFormFieldCalculated) {
		return @"calculated";
	}
	if (part == ORMFormPartEntered) {
		return @"entered";
	}
	if (part == ORMFormPartShown) {
		return @"shown";
	}
	return node.isGiven ? @"given" : @"hidden";
}

- (void)addControlsTo:(NSXMLElement *)body
{
	NSMutableSet *done = [NSMutableSet set];
	for (ORMFormField *field in _fields) {
		ORMQueryNode *node = [self nodeWithId:field.nodeId];
		ORMQueryStep *unary = [_unarySteps objectForKey:field.nodeId];
		if (unary != nil) {
			[body addChild:[self controlOf:field node:nil label:[self labelOfField:field]]];
			continue;
		}
		if (field.isHidden || node == _form.root || [done containsObject:field.nodeId]
		    || (node.formPart == ORMFormPartNone && field.kind != ORMFormFieldCalculated)) {
			continue;
		}
		NSArray *fields = [self fieldsOfNode:field.nodeId];
		if (field.isPart) {
			[done addObject:field.nodeId];
			NSXMLElement *group = ORMXElement(@"xf:group", @{ @"id" : [@"control-" stringByAppendingString:field.nodeId] });
			[group addChild:ORMXText(@"xf:label", ORMLabelOf(node.role, node.objectType))];
			for (ORMFormField *part in fields) {
				[group addChild:[self controlOf:part node:node label:[self labelOfField:part]]];
			}
			[body addChild:group];
			continue;
		}
		[body addChild:[self controlOf:field node:node label:[self labelOfField:field]]];
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
		if ([bind.required containsObject:@"true()"] && bind.field.elementName != nil) {
			NSString *said = [bind.alerts componentsJoinedByString:@" "];
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
	NSString *kind = shown ? @"xf:output"
		: field.kind == ORMFormFieldReference || items != nil ? @"xf:select1" : @"xf:input";
	NSXMLElement *control = ORMXElement(kind, @{ @"id" : identifier, @"bind" : bind });
	[control addChild:ORMXText(@"xf:label", label)];
	NSString *note = (unary ?: node.step).factType.noteText;
	if ([note length] > 0 && !shown && field.partIndex == 0) {
		[control addChild:ORMXText(@"xf:hint", note)];
	}
	if (!shown && field.kind == ORMFormFieldReference && items == nil) {
		NSString *instance = [NSString stringWithFormat:@"instance('choices-%@')/*", field.elementName];
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
		[control addChild:ORMXText(@"xf:alert", [formBind.alerts componentsJoinedByString:@" "])];
	}
	/* A reference whose choices depend on this one: read again as it
	 * changes. */
	if (!shown) {
		for (NSString *name in [self choiceNames]) {
			if ([[self elementsChoicesDependOn:name] containsObject:field.elementName]) {
				NSXMLElement *action = ORMXElement(@"xf:action", @{ @"ev:event" : @"xforms-value-changed" });
				[action addChild:ORMXElement(@"xf:send", @{ @"submission" : [@"choices-" stringByAppendingString:name] })];
				[control addChild:action];
			}
		}
	}
	return control;
}

- (NSArray<NSString *> *)checkedWhereSubmitted
{
	return [_checked copy];
}

- (NSArray<NSString *> *)notes
{
	return [_notes copy];
}

@end
