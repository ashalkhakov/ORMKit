/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMPath.h"
#import "ORMModelPriv.h"
#import "ORMXML.h"

#define CORE ORMCoreNamespace

@interface ORMCardinality ()
@property (nonatomic, readwrite, copy) NSArray<NSArray<NSNumber *> *> *ranges;
@end

#pragma mark Implementations

@implementation ORMPathedRole
@end

@implementation ORMRolePath

- (ORMRolePath *)leadPath
{
	ORMRolePath *path = self;
	while (path.parent != nil) {
		path = path.parent;
	}
	return path;
}

@end

@implementation ORMPathSource

- (ORMObjectType *)objectType
{
	switch (self.kind) {
	case ORMPathSourceRoot:
		return self.root.rootObjectType;
	case ORMPathSourcePathedRole:
		return self.pathedRole.role.player;
	default:
		return nil;
	}
}

@end

@implementation ORMCalculation
@end

@implementation ORMRolePathOwner
@end

@implementation ORMDerivationRule
@end

@implementation ORMInstance

- (NSDictionary<NSString *, ORMInstance *> *)identifyingInstancesByRole
{
	NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
	NSDictionary *roleInstances = [self.model.extras objectForKey:@"roleInstances"];
	for (NSString *roleInstance in self.identifyingRoleInstances) {
		NSArray *pair = [roleInstances objectForKey:roleInstance];
		if (pair != nil && [pair lastObject] != self) {
			[byRole setObject:[pair lastObject] forKey:[[pair firstObject] identifier]];
		}
	}
	return byRole;
}

- (ORMFactInstance *)objectifiedInstance
{
	ORMFactInstance *fact = self.objectifiedInstanceId != nil ? [self.model elementWithId:self.objectifiedInstanceId] : nil;
	return [fact isKindOfClass:[ORMFactInstance class]] ? fact : nil;
}

- (ORMInstance *)supertypeInstance
{
	ORMInstance *supertype = self.supertypeInstanceId != nil ? [self.model elementWithId:self.supertypeInstanceId] : nil;
	return [supertype isKindOfClass:[ORMInstance class]] ? supertype : nil;
}

- (NSString *)displayText
{
	if (self.value != nil) {
		BOOL quotes = self.objectType.dataType.family == ORMDataTypeText
			|| self.objectType.dataType.family == ORMDataTypeUnspecified || self.objectType.dataType == nil;
		NSScanner *scanner = [NSScanner scannerWithString:self.value];
		double number;
		if ([scanner scanDouble:&number] && [scanner isAtEnd]) {
			quotes = NO;
		}
		return quotes ? [NSString stringWithFormat:@"'%@'", self.value] : self.value;
	}
	ORMModel *model = self.model;
	if (self.supertypeInstanceId != nil) {
		ORMInstance *supertype = [model elementWithId:self.supertypeInstanceId];
		return [supertype isKindOfClass:[ORMInstance class]] ? [supertype displayText] : @"?";
	}
	NSMutableArray *parts = [NSMutableArray array];
	ORMFactInstance *objectified = [self objectifiedInstance];
	if (objectified != nil) {
		/* The fact it is: its players, in the fact type's order. */
		for (ORMRole *role in objectified.factType.roles) {
			ORMInstance *player = [objectified.instancesByRole objectForKey:role.identifier];
			if (player != nil && !player.objectType.isImplicitBooleanValue) {
				[parts addObject:[player displayText]];
			}
		}
		return [NSString stringWithFormat:@"(%@)", [parts componentsJoinedByString:@", "]];
	}
	NSDictionary *roleInstances = [model.extras objectForKey:@"roleInstances"];
	for (NSString *roleInstance in self.identifyingRoleInstances) {
		ORMInstance *identifying = [[roleInstances objectForKey:roleInstance] lastObject];
		if (identifying != nil && identifying != self) {
			[parts addObject:[identifying displayText]];
		}
	}
	return [parts count] > 0 ? [parts componentsJoinedByString:@", "] : @"?";
}

@end

@implementation ORMFactInstance
@end

@implementation ORMCardinality
@end

#pragma mark Lookups

@implementation ORMRoleSequence (ORMPaths)

- (ORMRolePathOwner *)joinPath
{
	return [[self.model.extras objectForKey:@"joinPaths"] objectForKey:self.identifier ?: @""];
}

- (NSArray<NSString *> *)roleUseIds
{
	NSMutableArray *ids = [NSMutableArray array];
	for (NSXMLElement *use in ORMChildren(self.element, CORE, @"Role")) {
		[ids addObject:ORMAttribute(use, @"id") ?: @""];
	}
	return ids;
}

@end

@implementation ORMRoleInstance

- (ORMInstance *)instance
{
	ORMInstance *instance = self.instanceId != nil ? [self.model elementWithId:self.instanceId] : nil;
	return [instance isKindOfClass:[ORMInstance class]] ? instance : nil;
}

@end

@implementation ORMFactType (ORMPaths)

- (ORMDerivationRule *)derivationRule
{
	return [[self.model.extras objectForKey:@"derivations"] objectForKey:self.identifier];
}

- (NSArray<ORMFactInstance *> *)instances
{
	return [[self.model.extras objectForKey:@"factInstances"] objectForKey:self.identifier] ?: @[];
}

@end

@implementation ORMObjectType (ORMPaths)

- (ORMDerivationRule *)derivationRule
{
	return [[self.model.extras objectForKey:@"derivations"] objectForKey:self.identifier];
}

- (NSArray<ORMInstance *> *)instances
{
	return [[self.model.extras objectForKey:@"instances"] objectForKey:self.identifier] ?: @[];
}

- (ORMCardinality *)cardinality
{
	return [[self.model.extras objectForKey:@"cardinalities"] objectForKey:self.identifier];
}

- (NSString *)defaultValue
{
	return ORMChildText(self.element, CORE, @"DefaultValue");
}

@end

@implementation ORMRole (ORMPaths)

- (ORMCardinality *)cardinality
{
	return [[self.model.extras objectForKey:@"cardinalities"] objectForKey:self.identifier];
}

@end

#pragma mark Reading

@implementation ORMModel (ORMPathReading)

- (ORMValueConstraint *)conditionIn:(NSXMLElement *)restriction
{
	NSXMLElement *constraint = nil;
	for (NSXMLNode *node in [restriction children]) {
		if ([node kind] == NSXMLElementKind) {
			constraint = (NSXMLElement *)node;
		}
	}
	if (constraint == nil) {
		return nil;
	}
	ORMValueConstraint *value = [[ORMValueConstraint alloc] initWithElement:constraint model:self];
	NSMutableArray *ranges = [NSMutableArray array];
	for (NSXMLElement *rangeElement in ORMGrandchildren(constraint, CORE, @"ValueRanges", CORE, @"ValueRange")) {
		ORMValueRange *range = [[ORMValueRange alloc] initWithElement:rangeElement model:self];
		range.minValue = ORMAttribute(rangeElement, @"MinValue") ?: @"";
		range.maxValue = ORMAttribute(rangeElement, @"MaxValue") ?: @"";
		NSString *minInclusion = ORMAttribute(rangeElement, @"MinInclusion");
		NSString *maxInclusion = ORMAttribute(rangeElement, @"MaxInclusion");
		range.minInclusion = [minInclusion isEqualToString:@"Open"] ? ORMRangeOpen
			: [minInclusion isEqualToString:@"Closed"] ? ORMRangeClosed : ORMRangeInclusionNotSet;
		range.maxInclusion = [maxInclusion isEqualToString:@"Open"] ? ORMRangeOpen
			: [maxInclusion isEqualToString:@"Closed"] ? ORMRangeClosed : ORMRangeInclusionNotSet;
		range.constraint = value;
		[ranges addObject:range];
	}
	value.ranges = ranges;
	return value;
}

- (ORMRolePath *)readPath:(NSXMLElement *)element parent:(ORMRolePath *)parent pending:(NSMutableArray *)pending
{
	ORMRolePath *path = [[ORMRolePath alloc] initWithElement:element model:self];
	path.parent = parent;
	NSString *split = ORMAttribute(element, @"SplitCombinationOperator");
	path.split = [split isEqualToString:@"Or"] ? ORMPathSplitOr : [split isEqualToString:@"Xor"] ? ORMPathSplitXor
	                                                                                              : ORMPathSplitAnd;
	path.splitIsNegated = ORMBoolAttribute(element, @"SplitIsNegated", NO);
	NSXMLElement *root = ORMChild(element, CORE, @"RootObjectType");
	if (root != nil) {
		path.rootObjectType = [self elementWithId:ORMRef(root)];
		path.rootId = ORMAttribute(root, @"id");
		path.rootIsNegated = ORMBoolAttribute(root, @"IsNegated", NO);
		path.rootValueConstraint = [self conditionIn:ORMChild(root, CORE, @"ValueRestriction")];
		if (path.rootId != nil) {
			[[self.extras objectForKey:@"roots"] setObject:path forKey:path.rootId];
		}
	}
	NSMutableArray *pathedRoles = [NSMutableArray array];
	for (NSXMLElement *pathedElement in ORMGrandchildren(element, CORE, @"PathedRoles", CORE, @"PathedRole")) {
		ORMPathedRole *pathed = [[ORMPathedRole alloc] initWithElement:pathedElement model:self];
		pathed.path = path;
		pathed.role = [self elementWithId:ORMRef(pathedElement)];
		NSString *purpose = ORMAttribute(pathedElement, @"Purpose");
		pathed.purpose = [purpose isEqualToString:@"StartRole"] ? ORMPathStartRole
			: [purpose isEqualToString:@"SameFactType"] ? ORMPathSameFactType
			: [purpose isEqualToString:@"PostOuterJoin"] ? ORMPathOuterJoin : ORMPathInnerJoin;
		pathed.isNegated = ORMBoolAttribute(pathedElement, @"IsNegated", NO);
		pathed.valueConstraint = [self conditionIn:ORMChild(pathedElement, CORE, @"ValueRestriction")];
		NSString *correlated = ORMRef(ORMChild(pathedElement, CORE, @"CorrelatedWith"));
		if (correlated != nil) {
			[pending addObject:@[ pathed, correlated ]];
		}
		[self registerElement:pathed];
		[pathedRoles addObject:pathed];
	}
	path.pathedRoles = pathedRoles;
	NSMutableArray *subPaths = [NSMutableArray array];
	for (NSXMLElement *sub in ORMGrandchildren(element, CORE, @"SubPaths", CORE, @"SubPath")) {
		[subPaths addObject:[self readPath:sub parent:path pending:pending]];
	}
	path.subPaths = subPaths;
	[self registerElement:path];
	return path;
}

/* A source element: <PathRoot ref/>, <PathedRole ref/>, <CalculatedValue
 * ref/> or <Constant><Value>…</Value></Constant>, resolved later. */
- (ORMPathSource *)sourceIn:(NSXMLElement *)container
{
	for (NSXMLNode *node in [container children]) {
		if ([node kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *element = (NSXMLElement *)node;
		NSString *local = [element localName];
		ORMPathSource *source = [[ORMPathSource alloc] init];
		if ([local isEqualToString:@"PathRoot"]) {
			source.kind = ORMPathSourceRoot;
		} else if ([local isEqualToString:@"PathedRole"]) {
			source.kind = ORMPathSourcePathedRole;
		} else if ([local isEqualToString:@"CalculatedValue"]) {
			source.kind = ORMPathSourceCalculation;
		} else if ([local isEqualToString:@"Constant"]) {
			source.kind = ORMPathSourceConstant;
			source.constant = ORMChildText(element, CORE, @"Value") ?: [element stringValue];
			return source;
		} else {
			continue;
		}
		source.reference = ORMRef(element);
		return source;
	}
	return nil;
}

- (void)resolve:(ORMPathSource *)source
{
	if (source.reference == nil) {
		return;
	}
	switch (source.kind) {
	case ORMPathSourceRoot:
		source.root = [[self.extras objectForKey:@"roots"] objectForKey:source.reference];
		break;
	case ORMPathSourcePathedRole: {
		id element = [self elementWithId:source.reference];
		source.pathedRole = [element isKindOfClass:[ORMPathedRole class]] ? element : nil;
		break;
	}
	case ORMPathSourceCalculation: {
		id element = [self elementWithId:source.reference];
		source.calculation = [element isKindOfClass:[ORMCalculation class]] ? element : nil;
		break;
	}
	case ORMPathSourceConstant:
		break;
	}
}

- (ORMCalculation *)readCalculation:(NSXMLElement *)element sources:(NSMutableArray *)sources
{
	ORMCalculation *calculation = [[ORMCalculation alloc] initWithElement:element model:self];
	NSXMLElement *function = ORMElementWithId(self.document, ORMRef(ORMChild(element, CORE, @"Function")));
	calculation.functionName = ORMAttribute(function, @"Name") ?: @"function";
	calculation.isBoolean = ORMBoolAttribute(function, @"IsBoolean", NO);
	calculation.isAggregate = ORMChild(element, CORE, @"AggregationContext") != nil
		|| ORMBoolAttribute(element, @"UniversalAggregationContext", NO);
	NSMutableArray *inputs = [NSMutableArray array];
	NSMutableArray *names = [NSMutableArray array];
	for (NSXMLElement *input in ORMGrandchildren(element, CORE, @"Inputs", CORE, @"Input")) {
		ORMPathSource *source = [self sourceIn:ORMChild(input, CORE, @"Source")];
		if (source == nil) {
			continue;
		}
		[sources addObject:source];
		[inputs addObject:source];
		NSXMLElement *parameter = ORMElementWithId(self.document, ORMRef(ORMChild(input, CORE, @"Parameter")));
		[names addObject:ORMAttribute(parameter, @"Name") ?: @""];
	}
	calculation.inputs = inputs;
	calculation.parameterNames = names;
	ORMPathSource *context = [self sourceIn:ORMChild(element, CORE, @"AggregationContext")];
	if (context != nil) {
		[sources addObject:context];
		calculation.aggregationContext = @[ context ];
	} else {
		calculation.aggregationContext = @[];
	}
	[self registerElement:calculation];
	return calculation;
}

/* A role path owner's paths, calculations and projections, under the
 * element that holds PathComponents. */
- (void)readOwner:(ORMRolePathOwner *)owner from:(NSXMLElement *)element projections:(NSArray *)projectionPath
{
	NSMutableArray *pending = [NSMutableArray array];
	NSMutableArray *sources = [NSMutableArray array];
	NSMutableArray *paths = [NSMutableArray array];
	NSMutableArray *calculationElements = [NSMutableArray array];
	NSMutableArray *conditionRefs = [NSMutableArray array];
	NSMutableArray *leadElements = [NSMutableArray array];
	[leadElements addObjectsFromArray:ORMGrandchildren(element, CORE, @"PathComponents", CORE, @"RolePath")];
	[leadElements addObjectsFromArray:ORMGrandchildren(element, CORE, @"PathComponent", CORE, @"RolePath")];
	for (NSXMLElement *lead in leadElements) {
		[paths addObject:[self readPath:lead parent:nil pending:pending]];
		[calculationElements addObjectsFromArray:ORMGrandchildren(lead, CORE, @"CalculatedValues", CORE,
		                                                          @"CalculatedValue")];
		for (NSXMLElement *condition in ORMGrandchildren(lead, CORE, @"Conditions", CORE, @"CalculatedCondition")) {
			[conditionRefs addObject:ORMRef(condition) ?: @""];
		}
	}
	for (NSXMLElement *shared in ORMGrandchildren(element, CORE, @"PathComponents", CORE, @"SharedRolePath")) {
		ORMRolePath *path = [self elementWithId:ORMRef(shared)];
		if ([path isKindOfClass:[ORMRolePath class]]) {
			[paths addObject:path];
		}
	}
	[calculationElements addObjectsFromArray:ORMGrandchildren(element, CORE, @"CalculatedValues", CORE,
	                                                          @"CalculatedValue")];
	NSMutableArray *calculations = [NSMutableArray array];
	for (NSXMLElement *calculationElement in calculationElements) {
		[calculations addObject:[self readCalculation:calculationElement sources:sources]];
	}
	owner.paths = paths;
	owner.calculations = calculations;
	/* Projections: <container><projection><item ref=target><source …/>. */
	NSMutableDictionary *projections = [NSMutableDictionary dictionary];
	NSXMLElement *container = ORMChild(element, CORE, [projectionPath objectAtIndex:0]);
	if (container == nil && [element parent] != nil) {
		container = ORMChild((NSXMLElement *)[element parent], CORE, [projectionPath objectAtIndex:0]);
	}
	NSMutableDictionary *projectionIds = [NSMutableDictionary dictionary];
	for (NSXMLElement *projection in ORMChildren(container, CORE, [projectionPath objectAtIndex:1])) {
		owner.projectionId = owner.projectionId ?: ORMAttribute(projection, @"id");
		for (NSXMLElement *item in ORMChildren(projection, CORE, [projectionPath objectAtIndex:2])) {
			ORMPathSource *source = [self sourceIn:ORMChild(item, CORE, [projectionPath objectAtIndex:3])];
			NSString *target = ORMRef(item);
			if (source != nil && target != nil && [projections objectForKey:target] == nil) {
				[projections setObject:source forKey:target];
				[sources addObject:source];
				if (ORMAttribute(item, @"id") != nil) {
					[projectionIds setObject:ORMAttribute(item, @"id") forKey:target];
				}
			}
		}
	}
	owner.projectionIds = projectionIds;
	for (ORMPathSource *source in sources) {
		[self resolve:source];
	}
	for (NSArray *link in pending) {
		ORMPathedRole *pathed = [link objectAtIndex:0];
		id target = [self elementWithId:[link objectAtIndex:1]];
		pathed.correlatedWith = [target isKindOfClass:[ORMPathedRole class]] ? target : nil;
	}
	NSMutableArray *conditions = [NSMutableArray array];
	for (NSString *reference in conditionRefs) {
		ORMCalculation *calculation = [self elementWithId:reference];
		if ([calculation isKindOfClass:[ORMCalculation class]]) {
			[conditions addObject:calculation];
		}
	}
	owner.conditions = conditions;
	owner.projections = projections;
	[self registerElement:owner];
}

/* A derivation rule: <DerivationRule> (or <SubtypeDerivationRule>) holding
 * the path (<FactTypeDerivationPath>, <SubtypeDerivationPath>), which
 * carries completeness and storage and the modeller's informal rule; or,
 * in older files, a DerivationExpression with its text. */
- (ORMDerivationRule *)readDerivation:(NSXMLElement *)element subtype:(BOOL)subtype
{
	ORMDerivationRule *rule = [[ORMDerivationRule alloc] initWithElement:element model:self];
	rule.isSubtypeRule = subtype;
	NSXMLElement *path = ORMChild(element, CORE, subtype ? @"SubtypeDerivationPath" : @"FactTypeDerivationPath");
	NSString *completeness = ORMAttribute(path, @"DerivationCompleteness") ?: ORMAttribute(element, @"DerivationCompleteness");
	NSString *storage = ORMAttribute(path, @"DerivationStorage") ?: ORMAttribute(element, @"DerivationStorage");
	NSXMLElement *expression = ORMChild(element, CORE, subtype ? @"SubtypeDerivationExpression" : @"DerivationExpression");
	NSString *legacy = ORMAttribute(expression, @"DerivationStorage");
	rule.isPartial = [completeness isEqualToString:@"PartiallyDerived"] || [legacy hasPrefix:@"PartiallyDerived"];
	rule.isStored = [storage isEqualToString:@"Stored"] || [legacy hasSuffix:@"AndStored"];
	NSXMLElement *note = ORMChild(ORMChild(path, CORE, @"InformalRule"), CORE, @"DerivationNote");
	NSString *text = ORMChildText(note, CORE, @"Body") ?: ORMChildText(expression, CORE, @"Body");
	rule.informalText = [text length] > 0 ? text : nil;
	rule.pathId = ORMAttribute(path, @"id");
	rule.pathName = [ORMAttribute(path, @"Name") length] > 0 ? ORMAttribute(path, @"Name") : nil;
	rule.noteId = ORMAttribute(note, @"id");
	rule.hasRolePath = ORMChild(path, CORE, @"PathComponents") != nil || ORMChild(path, CORE, @"PathComponent") != nil;
	rule.hasExpression = expression != nil;
	if (path != nil) {
		[self readOwner:rule from:path
		    projections:@[ @"DerivationProjections", @"DerivationProjection", @"RoleProjection", @"DerivationSource" ]];
	} else {
		rule.paths = @[];
		rule.calculations = @[];
		rule.conditions = @[];
		rule.projections = @{};
	}
	return rule;
}

- (ORMCardinality *)cardinalityIn:(NSXMLElement *)restriction
{
	NSXMLElement *constraint = nil;
	for (NSXMLNode *node in [restriction children]) {
		if ([node kind] == NSXMLElementKind) {
			constraint = (NSXMLElement *)node;
		}
	}
	if (constraint == nil) {
		return nil;
	}
	ORMCardinality *cardinality = [[ORMCardinality alloc] initWithElement:constraint model:self];
	NSMutableArray *ranges = [NSMutableArray array];
	for (NSXMLElement *range in ORMGrandchildren(constraint, CORE, @"Ranges", CORE, @"CardinalityRange")) {
		[ranges addObject:@[ @([ORMAttribute(range, @"From") integerValue]), @([ORMAttribute(range, @"To") integerValue]) ]];
	}
	cardinality.ranges = ranges;
	return cardinality;
}

- (void)readInstances
{
	NSMutableDictionary *instances = [self.extras objectForKey:@"instances"];
	for (ORMObjectType *type in self.objectTypes) {
		NSMutableArray *list = [NSMutableArray array];
		NSXMLElement *container = ORMChild(type.element, CORE, @"Instances");
		for (NSXMLNode *node in [container children]) {
			if ([node kind] != NSXMLElementKind) {
				continue;
			}
			NSXMLElement *element = (NSXMLElement *)node;
			ORMInstance *instance = [[ORMInstance alloc] initWithElement:element model:self];
			instance.objectType = type;
			NSString *local = [element localName];
			instance.elementName = local;
			if ([local isEqualToString:@"ValueTypeInstance"]) {
				instance.value = ORMChildText(element, CORE, @"Value") ?: @"";
				instance.invariantValue = ORMChildText(element, CORE, @"InvariantValue");
			} else if ([local isEqualToString:@"EntityTypeSubtypeInstance"]) {
				instance.supertypeInstanceId = ORMRef(ORMChild(element, CORE, @"SupertypeInstance"));
				instance.objectifiedInstanceId = ORMRef(ORMChild(element, CORE, @"ObjectifiedInstance"));
			} else {
				instance.objectifiedInstanceId = ORMRef(ORMChild(element, CORE, @"ObjectifiedInstance"));
				NSMutableArray *identifying = [NSMutableArray array];
				for (NSXMLElement *ref in ORMChildren(ORMChild(element, CORE, @"RoleInstances"), CORE,
				                                      @"EntityTypeRoleInstance")) {
					[identifying addObject:ORMRef(ref) ?: @""];
				}
				instance.identifyingRoleInstances = identifying;
				/* Unary facts as newer NORMA writes them, under the entity
				 * instance playing the role. */
				NSMutableArray *unaries = [NSMutableArray array];
				for (NSXMLElement *ref in ORMChildren(ORMChild(element, CORE, @"RoleInstances"), CORE,
				                                      @"EntityTypeUnaryRoleInstance")) {
					if (ORMRef(ref) != nil) {
						[unaries addObject:ORMRef(ref)];
					}
				}
				instance.unaryRoleIds = unaries;
			}
			[self registerElement:instance];
			[list addObject:instance];
		}
		if ([list count] > 0) {
			[instances setObject:list forKey:type.identifier];
		}
	}
	/* Role instances: under each role, an id for each instance playing it. */
	for (ORMFactType *fact in self.factTypes) {
		for (ORMRole *role in fact.roles) {
			NSMutableArray *list = [NSMutableArray array];
			for (NSXMLNode *node in [ORMChild(role.element, CORE, @"RoleInstances") children]) {
				if ([node kind] != NSXMLElementKind) {
					continue;
				}
				ORMRoleInstance *roleInstance = [[ORMRoleInstance alloc] initWithElement:(NSXMLElement *)node model:self];
				roleInstance.elementName = [node localName];
				roleInstance.role = role;
				roleInstance.instanceId = ORMRef((NSXMLElement *)node);
				[self registerElement:roleInstance];
				[list addObject:roleInstance];
			}
			role.roleInstances = [list count] > 0 ? list : nil;
		}
	}
	NSMutableDictionary *facts = [self.extras objectForKey:@"factInstanceElements"];
	for (ORMFactType *fact in self.factTypes) {
		NSMutableArray *list = [NSMutableArray array];
		for (NSXMLElement *element in ORMGrandchildren(fact.element, CORE, @"Instances", CORE, @"FactTypeInstance")) {
			ORMFactInstance *instance = [[ORMFactInstance alloc] initWithElement:element model:self];
			instance.factType = fact;
			NSMutableArray *ids = [NSMutableArray array];
			for (NSXMLElement *ref in ORMChildren(ORMChild(element, CORE, @"RoleInstances"), CORE,
			                                      @"FactTypeRoleInstance")) {
				[ids addObject:ORMRef(ref) ?: @""];
			}
			instance.roleInstanceIds = ids;
			[self registerElement:instance];
			[list addObject:instance];
		}
		if ([list count] > 0) {
			[facts setObject:list forKey:fact.identifier];
		}
	}
}

- (void)readPathsAndPopulations
{
	for (NSString *key in @[ @"roots", @"joinPaths", @"derivations", @"instances", @"roleInstances", @"factInstances",
	                         @"factInstanceElements", @"cardinalities" ]) {
		[self.extras setObject:[NSMutableDictionary dictionary] forKey:key];
	}
	/* Join paths, on the sequences of the constraints. */
	for (ORMConstraint *constraint in self.constraints) {
		for (ORMRoleSequence *sequence in constraint.roleSequences) {
			NSXMLElement *joinPath = ORMChild(ORMChild(sequence.element, CORE, @"JoinRule"), CORE, @"JoinPath");
			if (joinPath == nil) {
				continue;
			}
			ORMRolePathOwner *owner = [[ORMRolePathOwner alloc] initWithElement:joinPath model:self];
			[self readOwner:owner from:joinPath
			    projections:@[ @"JoinPathProjections", @"JoinPathProjection", @"ConstraintRoleProjection",
			                   @"ProjectedFrom" ]];
			if (sequence.identifier != nil) {
				[[self.extras objectForKey:@"joinPaths"] setObject:owner forKey:sequence.identifier];
			}
		}
	}
	NSMutableDictionary *derivations = [self.extras objectForKey:@"derivations"];
	NSMutableDictionary *cardinalities = [self.extras objectForKey:@"cardinalities"];
	for (ORMFactType *fact in self.factTypes) {
		NSXMLElement *rule = ORMChild(fact.element, CORE, @"DerivationRule");
		if (rule != nil) {
			[derivations setObject:[self readDerivation:rule subtype:NO] forKey:fact.identifier];
		}
		for (ORMRole *role in fact.roles) {
			ORMCardinality *cardinality = [self cardinalityIn:ORMChild(role.element, CORE, @"CardinalityRestriction")];
			if (cardinality != nil) {
				[cardinalities setObject:cardinality forKey:role.identifier];
			}
		}
	}
	for (ORMObjectType *type in self.objectTypes) {
		NSXMLElement *rule = ORMChild(type.element, CORE, @"SubtypeDerivationRule");
		if (rule != nil) {
			[derivations setObject:[self readDerivation:rule subtype:YES] forKey:type.identifier];
		}
		ORMCardinality *cardinality = [self cardinalityIn:ORMChild(type.element, CORE, @"CardinalityRestriction")];
		if (cardinality != nil) {
			[cardinalities setObject:cardinality forKey:type.identifier];
		}
	}
	[self readInstances];
	[self derivePopulations];
}

@end

#pragma mark The sample population

@implementation ORMModel (ORMPopulations)

- (void)derivePopulations
{
	/* Each role instance's role and player, by its id. */
	NSMutableDictionary *roleInstances = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in self.factTypes) {
		for (ORMRole *role in fact.roles) {
			for (ORMRoleInstance *roleInstance in role.roleInstances) {
				ORMInstance *instance = [roleInstance instance];
				if (roleInstance.identifier != nil && instance != nil) {
					[roleInstances setObject:@[ role, instance ] forKey:roleInstance.identifier];
				}
			}
		}
	}
	[self.extras setObject:roleInstances forKey:@"roleInstances"];
	NSMutableDictionary *factInstances = [NSMutableDictionary dictionary];
	NSDictionary *elements = [self.extras objectForKey:@"factInstanceElements"];
	for (NSString *factId in elements) {
		for (ORMFactInstance *instance in [elements objectForKey:factId]) {
			NSMutableDictionary *byRole = [NSMutableDictionary dictionary];
			for (NSString *roleInstanceId in instance.roleInstanceIds) {
				NSArray *pair = [roleInstances objectForKey:roleInstanceId];
				if (pair != nil) {
					[byRole setObject:[pair objectAtIndex:1] forKey:[[pair objectAtIndex:0] identifier]];
				}
			}
			instance.instancesByRole = byRole;
		}
		[factInstances setObject:[[elements objectForKey:factId] mutableCopy] forKey:factId];
	}
	/* A unary fact NORMA keeps on its player: a fact of the unary fact
	 * type, its instance's own, named by the instance and the role (no
	 * element of the file is it, to be found by id). */
	for (ORMObjectType *type in self.objectTypes) {
		for (ORMInstance *player in [type instances]) {
			for (NSString *roleId in player.unaryRoleIds) {
				ORMRole *role = [self elementWithId:roleId];
				if (![role isKindOfClass:[ORMRole class]] || [role.factType.roles count] > 2) {
					continue;
				}
				ORMFactInstance *fact = [[ORMFactInstance alloc] initWithModel:self];
				fact.identifier = [NSString stringWithFormat:@"%@.%@", player.identifier, role.identifier];
				fact.factType = role.factType;
				fact.instancesByRole = @{ role.identifier: player };
				NSMutableArray *list = [factInstances objectForKey:role.factType.identifier];
				if (list == nil) {
					list = [NSMutableArray array];
					[factInstances setObject:list forKey:role.factType.identifier];
				}
				[list addObject:fact];
			}
		}
	}
	[self.extras setObject:factInstances forKey:@"factInstances"];
}

/* The list an element of the population is kept in, by what it is of. */
- (NSMutableArray *)populationListOf:(ORMElement *)element
{
	NSString *key = nil;
	NSString *owner = nil;
	if ([element isKindOfClass:[ORMInstance class]]) {
		key = @"instances";
		owner = [(ORMInstance *)element objectType].identifier;
	} else if ([element isKindOfClass:[ORMFactInstance class]]) {
		key = @"factInstanceElements";
		owner = [(ORMFactInstance *)element factType].identifier;
	}
	if (key == nil || owner == nil) {
		return nil;
	}
	NSMutableDictionary *lists = [self.extras objectForKey:key];
	NSMutableArray *list = [lists objectForKey:owner];
	if (list == nil) {
		list = [NSMutableArray array];
		[lists setObject:list forKey:owner];
	}
	return list;
}

- (void)addPopulationElement:(ORMElement *)element
{
	if ([element isKindOfClass:[ORMRoleInstance class]]) {
		ORMRole *role = [(ORMRoleInstance *)element role];
		role.roleInstances = [role.roleInstances ?: @[] arrayByAddingObject:element];
	} else {
		[[self populationListOf:element] addObject:element];
	}
	[self registerElement:element];
}

- (void)removePopulationElement:(ORMElement *)element
{
	if ([element isKindOfClass:[ORMRoleInstance class]]) {
		ORMRole *role = [(ORMRoleInstance *)element role];
		role.roleInstances = ORMWithout(role.roleInstances, element);
	} else {
		NSMutableArray *list = [self populationListOf:element];
		[list removeObjectIdenticalTo:element];
		if ([list count] == 0) {
			NSString *key = [element isKindOfClass:[ORMInstance class]] ? @"instances" : @"factInstanceElements";
			NSMutableDictionary *lists = [self.extras objectForKey:key];
			for (NSString *owner in [lists allKeys]) {
				if ([lists objectForKey:owner] == list) {
					[lists removeObjectForKey:owner];
				}
			}
		}
	}
	[self removeElement:element];
}

@end

@implementation ORMModel (ORMDerivationRules)

- (NSDictionary<NSString *, ORMDerivationRule *> *)derivationRules
{
	return [self.extras objectForKey:@"derivations"] ?: @{};
}

- (void)setDerivationRule:(ORMDerivationRule *)rule ofFactType:(ORMFactType *)fact
{
	NSMutableDictionary *rules = [self.extras objectForKey:@"derivations"];
	if (rule != nil) {
		[rules setObject:rule forKey:fact.identifier];
	} else {
		[rules removeObjectForKey:fact.identifier];
	}
	fact.isDerived = rule != nil && (rule.pathId != nil || rule.hasExpression);
}

@end

@implementation ORMModel (ORMJoinPaths)

- (void)registerPath:(ORMRolePath *)path
{
	[self registerElement:path];
	if (path.rootId != nil) {
		[[self.extras objectForKey:@"roots"] setObject:path forKey:path.rootId];
	}
	for (ORMPathedRole *pathed in path.pathedRoles) {
		[self registerElement:pathed];
	}
	for (ORMRolePath *sub in path.subPaths) {
		[self registerPath:sub];
	}
}

- (void)setJoinPath:(ORMRolePathOwner *)joinPath ofSequence:(ORMRoleSequence *)sequence
{
	for (ORMRolePath *path in joinPath.paths) {
		[self registerPath:path];
	}
	[self registerElement:joinPath];
	[[self.extras objectForKey:@"joinPaths"] setObject:joinPath forKey:sequence.identifier];
	sequence.hasJoinPath = YES;
}

@end

