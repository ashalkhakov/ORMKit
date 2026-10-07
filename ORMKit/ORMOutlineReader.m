/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMOutlineReader.h"
#import "ORMQuery.h"

/* What a node says in the outline: ✓, its label, its condition, its sort. */
@interface ORMOutlineNode : NSObject
@property (nonatomic) BOOL projected;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *comparison;
@property (nonatomic, copy) NSString *value;
@property (nonatomic) ORMQuerySort sort;
@end

@implementation ORMOutlineNode
@end

/* A line: its depth (two spaces each) and what it says. */
@interface ORMOutlineLine : NSObject
@property (nonatomic) NSUInteger number;
@property (nonatomic) NSUInteger depth;
@property (nonatomic, copy) NSString *text;
@end

@implementation ORMOutlineLine
@end

/* What the first line says the query is for, where it says. */
@interface ORMOutlineHeader : NSObject
@property (nonatomic) ORMQueryKind kind;
@property (nonatomic) BOOL deontic;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *function;
@property (nonatomic, copy) NSString *calculated;
@property (nonatomic, strong) ORMFactType *derived;
@property (nonatomic, strong) ORMOutlineLine *line;
@end

@implementation ORMOutlineHeader
@end

static NSString *const ORMComparisons = @"<>|<=|>=|=|<|>";

/* What follows a node's name: label, condition, sort. */
static NSString *
ORMNodeTail(void)
{
	return [NSString stringWithFormat:@"(\\d*)(?: (%@) ('(?:[^']|'')*'|[^ ]+))?(?: ([↑↓]))?", ORMComparisons];
}

static NSString *
ORMNodePattern(NSString *name)
{
	return [NSString stringWithFormat:@"(✓)?%@%@", [NSRegularExpression escapedPatternForString:name], ORMNodeTail()];
}

/* What a match's group at the index matched, nil when it matched nothing. */
static NSString *
ORMGroup(NSTextCheckingResult *match, NSString *text, NSUInteger index)
{
	NSRange range = [match rangeAtIndex:index];
	return range.location == NSNotFound ? nil : [text substringWithRange:range];
}

/* The node from a match's five groups at the index. */
static ORMOutlineNode *
ORMNodeOf(NSTextCheckingResult *match, NSString *text, NSUInteger first)
{
	ORMOutlineNode *node = [[ORMOutlineNode alloc] init];
	node.projected = ORMGroup(match, text, first) != nil;
	NSString *label = ORMGroup(match, text, first + 1);
	node.label = [label length] > 0 ? label : nil;
	node.comparison = ORMGroup(match, text, first + 2);
	node.value = ORMGroup(match, text, first + 3);
	NSString *sort = ORMGroup(match, text, first + 4);
	node.sort = [sort isEqualToString:@"↑"] ? ORMQueryAscending : [sort isEqualToString:@"↓"] ? ORMQueryDescending
	                                                                                           : ORMQueryUnsorted;
	return node;
}

static NSArray<NSString *> *
ORMAggregateNames(void)
{
	return @[ @"count", @"total", @"avg", @"max", @"min" ];
}

@implementation ORMOutlineReader
{
	ORMQueryEditor *_queries;
	NSString *_query;
	NSArray<ORMOutlineLine *> *_lines;
	NSString *_failure;
	/* Conditions comparing with another node, once every node is made:
	 * @[ node id, comparison, designation, line ]. */
	NSMutableArray<NSArray *> *_comparisons;
	ORMOutlineHeader *_header;
}

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
		_queries = [[ORMQueryEditor alloc] initWithEditor:editor];
	}
	return self;
}

- (BOOL)fail:(NSString *)why line:(ORMOutlineLine *)line
{
	if (_failure == nil) {
		_failure = line != nil ? [NSString stringWithFormat:@"Line %lu, \"%@\": %@", (unsigned long)line.number, line.text, why]
		                       : why;
	}
	return NO;
}

- (ORMQuery *)query
{
	return [ORMQuery queryWithId:_query inModel:_editor.model];
}

/* A node, of a query read for it: its links up are not to be followed. */
- (ORMQueryNode *)node:(NSString *)nodeId
{
	for (ORMQueryNode *node in [[self query] nodes]) {
		if ([node.identifier isEqualToString:nodeId]) {
			return node;
		}
	}
	return nil;
}

/* The nodes below the node, it included. */
- (NSArray<ORMQueryNode *> *)subtreeOf:(ORMQueryNode *)node
{
	NSMutableArray *all = [NSMutableArray arrayWithObject:node];
	for (ORMQueryStep *step in node.steps) {
		for (ORMQueryNode *child in step.nodes) {
			[all addObjectsFromArray:[self subtreeOf:child]];
		}
	}
	return all;
}

#pragma mark Nodes

/* What the outline says of the node, given it. */
- (BOOL)apply:(ORMOutlineNode *)said to:(NSString *)nodeId line:(ORMOutlineLine *)line
{
	[_queries setProjected:said.projected ofNode:nodeId];
	if (said.label != nil) {
		[_queries setLabel:said.label ofNode:nodeId];
	}
	if (said.sort != ORMQueryUnsorted) {
		[_queries setSortOrder:said.sort ofNode:nodeId];
	}
	if (said.comparison == nil) {
		return YES;
	}
	NSString *value = said.value;
	if ([value hasPrefix:@"'"] && [value hasSuffix:@"'"] && [value length] >= 2) {
		/* Quoted, a quote in it doubled: "'O''Brien'". */
		value = [[value substringWithRange:NSMakeRange(1, [value length] - 2)] stringByReplacingOccurrencesOfString:@"''"
		                                                                                                withString:@"'"];
	} else {
		/* Another node, its designation: "Country2 <> Country1". */
		ORMQueryNode *node = [self node:nodeId];
		NSString *name = node.objectType.name ?: @"";
		NSString *rest = [value hasPrefix:name] ? [value substringFromIndex:[name length]] : nil;
		if (rest != nil && [[rest stringByTrimmingCharactersInSet:[NSCharacterSet decimalDigitCharacterSet]] length] == 0) {
			[_comparisons addObject:@[ nodeId, said.comparison, value, line ]];
			return YES;
		}
	}
	NSString *why = nil;
	if (![_queries setCondition:said.comparison value:value ofNode:nodeId reason:&why]) {
		return [self fail:why ?: @"the condition cannot be set" line:line];
	}
	return YES;
}

#pragma mark Steps

/* The step the text reads, from the node: the role it enters by, and what
 * the outline says of each of its nodes. */
- (ORMRole *)readStep:(NSString *)text from:(ORMQueryNode *)node nodes:(NSArray<ORMOutlineNode *> **)said
{
	ORMRole *found = nil;
	NSArray *foundNodes = nil;
	for (ORMRole *entry in [ORMQuery rolesFrom:node.objectType]) {
		NSArray *roles = [ORMQuery nodeRolesFrom:entry];
		NSString *reading = [ORMQuery readingFrom:entry nodeRoles:roles];
		if ([reading length] == 0) {
			continue;
		}
		NSMutableString *pattern = [NSMutableString stringWithString:@"^"];
		NSMutableArray *places = [NSMutableArray array];
		NSScanner *scanner = [NSScanner scannerWithString:reading];
		[scanner setCharactersToBeSkipped:nil];
		while (![scanner isAtEnd]) {
			NSString *literal = nil;
			if ([scanner scanUpToString:@"{" intoString:&literal]) {
				[pattern appendString:[NSRegularExpression escapedPatternForString:literal]];
			}
			if ([scanner isAtEnd]) {
				break;
			}
			NSInteger index = 0;
			NSUInteger at = [scanner scanLocation];
			if ([scanner scanString:@"{" intoString:NULL] && [scanner scanInteger:&index] && [scanner scanString:@"}" intoString:NULL]) {
				if (index == 0) {
					[pattern appendString:[NSRegularExpression escapedPatternForString:
						[NSString stringWithFormat:@"that %@", node.objectType.name ?: @""]]];
				} else if ((NSUInteger)index <= [roles count]) {
					[pattern appendFormat:@"%@", ORMNodePattern([[roles objectAtIndex:(NSUInteger)index - 1] player].name ?: @"")];
					[places addObject:@(index)];
				}
			} else {
				[scanner setScanLocation:at + 1];
				[pattern appendString:@"\\{"];
			}
		}
		[pattern appendString:@"$"];
		NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
		NSTextCheckingResult *match = [expression firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
		if (match == nil) {
			continue;
		}
		NSMutableArray *nodes = [NSMutableArray array];
		for (NSUInteger i = 0; i < [roles count]; i++) {
			[nodes addObject:[[ORMOutlineNode alloc] init]];
		}
		for (NSUInteger k = 0; k < [places count]; k++) {
			NSUInteger index = [[places objectAtIndex:k] unsignedIntegerValue];
			[nodes replaceObjectAtIndex:index - 1 withObject:ORMNodeOf(match, text, 1 + k * 5)];
		}
		/* The longest reading that matches: "has" is less than "has as
		 * owner". */
		if (found == nil || [reading length] > [[ORMQuery readingFrom:found nodeRoles:[ORMQuery nodeRolesFrom:found]] length]) {
			found = entry;
			foundNodes = nodes;
		}
	}
	*said = foundNodes;
	return found;
}

/* A step line and what is under it; the line after them. */
- (NSUInteger)step:(NSUInteger)index from:(NSString *)nodeId first:(BOOL)first
{
	ORMOutlineLine *line = [_lines objectAtIndex:index];
	NSString *text = [line.text substringFromIndex:2];
	if ([text hasPrefix:@"or "]) {
		if (first) {
			[self fail:@"the first step is no alternative" line:line];
			return NSNotFound;
		}
		[_queries setCombinesWithOr:YES ofNode:nodeId];
		text = [text substringFromIndex:3];
	}
	ORMQueryOperator operatorKind = ORMQueryAnd;
	if ([text hasPrefix:@"not "]) {
		operatorKind = ORMQueryNot;
		text = [text substringFromIndex:4];
	} else if ([text hasPrefix:@"maybe "]) {
		operatorKind = ORMQueryMaybe;
		text = [text substringFromIndex:6];
	}
	ORMQuery *query = [self query];
	ORMQueryNode *node = nil;
	for (ORMQueryNode *each in [query nodes]) {
		node = [each.identifier isEqualToString:nodeId] ? each : node;
	}
	NSArray<ORMOutlineNode *> *said = nil;
	ORMRole *entry = [self readStep:text from:node nodes:&said];
	if (entry == nil) {
		[self fail:[NSString stringWithFormat:@"no fact type of %@ reads so", node.objectType.name ?: @"it"] line:line];
		return NSNotFound;
	}
	NSString *why = nil;
	NSString *stepId = [_queries addStepTo:nodeId through:entry.identifier reason:&why];
	if (stepId == nil) {
		[self fail:why ?: @"the step cannot be made" line:line];
		return NSNotFound;
	}
	if (operatorKind != ORMQueryAnd) {
		[_queries setOperator:operatorKind ofStep:stepId];
	}
	query = [self query];
	NSMutableArray *children = [NSMutableArray array];
	for (ORMQueryNode *each in [query nodes]) {
		if ([each.step.identifier isEqualToString:stepId]) {
			[children addObject:each];
		}
	}
	for (NSUInteger i = 0; i < [children count] && i < [said count]; i++) {
		if (![self apply:[said objectAtIndex:i] to:[[children objectAtIndex:i] identifier] line:line]) {
			return NSNotFound;
		}
	}
	/* Under it: its aggregate, its nodes' steps. */
	NSUInteger next = index + 1;
	NSString *current = [[children firstObject] identifier];
	NSMutableArray *aggregates = [NSMutableArray array];
	while (next < [_lines count] && [[_lines objectAtIndex:next] depth] == line.depth + 1) {
		ORMOutlineLine *under = [_lines objectAtIndex:next];
		NSString *names = [ORMAggregateNames() componentsJoinedByString:@"|"];
		if ([under.text rangeOfString:[NSString stringWithFormat:@"^\\+ (%@)\\(", names] options:NSRegularExpressionSearch]
		        .location != NSNotFound) {
			[aggregates addObject:under];
			next++;
		} else if ([under.text hasSuffix:@":"] && ![under.text hasPrefix:@"+ "]) {
			current = [self childNamed:[under.text substringToIndex:[under.text length] - 1] among:children];
			if (current == nil) {
				[self fail:@"the step has no such node" line:under];
				return NSNotFound;
			}
			next++;
		} else if ([under.text hasPrefix:@"+ "]) {
			next = [self steps:next from:current];
			if (next == NSNotFound) {
				return NSNotFound;
			}
		} else {
			[self fail:@"neither a step, an aggregate nor a node's name" line:under];
			return NSNotFound;
		}
	}
	for (ORMOutlineLine *aggregate in aggregates) {
		if (![self aggregate:aggregate ofStep:stepId]) {
			return NSNotFound;
		}
	}
	return next;
}

/* The step lines at the depth, from the node; the line after them. */
- (NSUInteger)steps:(NSUInteger)index from:(NSString *)nodeId
{
	NSUInteger depth = [[_lines objectAtIndex:index] depth];
	BOOL first = YES;
	while (index < [_lines count]) {
		ORMOutlineLine *line = [_lines objectAtIndex:index];
		if (line.depth != depth || ![line.text hasPrefix:@"+ "]
		    || [line.text rangeOfString:[NSString stringWithFormat:@"^\\+ (%@)\\(",
		                                                           [ORMAggregateNames() componentsJoinedByString:@"|"]]
		                        options:NSRegularExpressionSearch]
		           .location != NSNotFound) {
			break;
		}
		index = [self step:index from:nodeId first:first];
		if (index == NSNotFound) {
			return NSNotFound;
		}
		first = NO;
	}
	return index;
}

#pragma mark Aggregates

/* The node of the designation among those given. */
- (ORMQueryNode *)designated:(NSString *)designation among:(NSArray<ORMQueryNode *> *)nodes
{
	for (ORMQueryNode *node in nodes) {
		if ([[node designation] isEqualToString:designation]) {
			return node;
		}
	}
	return nil;
}

/* "+ count(Language) for Branch > 1", "+ max(Salary) for Employee > avg(Salary) for Branch". */
- (BOOL)aggregate:(ORMOutlineLine *)line ofStep:(NSString *)stepId
{
	NSString *names = [ORMAggregateNames() componentsJoinedByString:@"|"];
	NSString *pattern = [NSString stringWithFormat:@"^\\+ (%@)\\((.+?)\\) for (.+?) (%@) (.+)$", names, ORMComparisons];
	NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
	NSTextCheckingResult *match = [expression firstMatchInString:line.text options:0 range:NSMakeRange(0, [line.text length])];
	if (match == nil) {
		return [self fail:@"an aggregate is \"count(X) for Y > n\"" line:line];
	}
	/* Held while its nodes are walked: their links up are weak. */
	ORMQuery *query = [self query];
	ORMQueryStep *step = nil;
	for (ORMQueryNode *node in [query nodes]) {
		for (ORMQueryStep *each in node.steps) {
			step = [each.identifier isEqualToString:stepId] ? each : step;
		}
	}
	NSMutableArray *below = [NSMutableArray array];
	for (ORMQueryNode *child in step.nodes) {
		[below addObjectsFromArray:[self subtreeOf:child]];
	}
	NSMutableArray *above = [NSMutableArray array];
	for (ORMQueryNode *at = step.parent; at != nil; at = at.step.parent) {
		[above addObject:at];
	}
	NSString *function = ORMGroup(match, line.text, 1);
	NSString *ofName = ORMGroup(match, line.text, 2);
	NSString *comparison = ORMGroup(match, line.text, 4);
	NSString *rest = ORMGroup(match, line.text, 5);
	ORMQueryNode *of = [self designated:ofName among:below];
	ORMQueryNode *group3 = [self designated:ORMGroup(match, line.text, 3) among:above];
	if (of == nil || group3 == nil) {
		return [self fail:@"what it aggregates is not below the step, or what it is for not above it" line:line];
	}
	ORMQueryAggregate aggregate = (ORMQueryAggregate)[ORMAggregateNames() indexOfObject:function];
	NSString *pattern2 = [NSString stringWithFormat:@"^(%@)\\((.+?)\\) for (.+)$", names];
	NSTextCheckingResult *compared = [[NSRegularExpression regularExpressionWithPattern:pattern2 options:0 error:NULL]
		firstMatchInString:rest options:0 range:NSMakeRange(0, [rest length])];
	NSString *why = nil;
	if (![_queries setAggregate:aggregate ofNode:of.identifier comparison:comparison value:compared != nil ? @"0" : rest
	                     ofStep:stepId reason:&why]) {
		return [self fail:why ?: @"the aggregate cannot be set" line:line];
	}
	if (group3 != step.parent && ![_queries setGroupNode:group3.identifier ofStep:stepId reason:&why]) {
		return [self fail:why ?: @"the aggregate cannot be for that" line:line];
	}
	if (compared != nil) {
		NSString *otherName = [rest substringWithRange:[compared rangeAtIndex:1]];
		ORMQueryNode *otherGroup = [self designated:[rest substringWithRange:[compared rangeAtIndex:3]] among:above];
		if (otherGroup == nil || ![[rest substringWithRange:[compared rangeAtIndex:2]] isEqualToString:ofName]) {
			return [self fail:@"an aggregate is compared with one of the same node, for a node above" line:line];
		}
		if (![_queries setComparedAggregate:(ORMQueryAggregate)[ORMAggregateNames() indexOfObject:otherName]
		                              group:otherGroup.identifier ofStep:stepId reason:&why]) {
			return [self fail:why ?: @"the aggregates cannot be compared" line:line];
		}
	}
	return YES;
}

/* The step's node the outline names: "Employee", or "Employee (2)" the
 * second of its type. nil where there is none. */
- (NSString *)childNamed:(NSString *)text among:(NSArray<ORMQueryNode *> *)children
{
	NSString *name = text;
	NSUInteger which = 1;
	NSRegularExpression *numbered = [NSRegularExpression regularExpressionWithPattern:@"^(.+) \\((\\d+)\\)$" options:0
	                                                                            error:NULL];
	NSTextCheckingResult *match = [numbered firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
	if (match != nil) {
		name = ORMGroup(match, text, 1);
		which = (NSUInteger)[ORMGroup(match, text, 2) integerValue];
	}
	NSUInteger seen = 0;
	for (ORMQueryNode *child in children) {
		if ([child.objectType.name isEqualToString:name] && ++seen == which) {
			return child.identifier;
		}
	}
	return nil;
}

#pragma mark The query

- (NSString *)addQueryNamed:(NSString *)name outline:(NSString *)text reason:(NSString **)reason
{
	_failure = nil;
	_comparisons = [NSMutableArray array];
	NSMutableArray *lines = [NSMutableArray array];
	NSUInteger number = 0;
	for (NSString *raw in [text componentsSeparatedByString:@"\n"]) {
		number++;
		NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([trimmed length] == 0) {
			continue;
		}
		NSUInteger spaces = 0;
		while (spaces < [raw length] && [raw characterAtIndex:spaces] == ' ') {
			spaces++;
		}
		ORMOutlineLine *line = [[ORMOutlineLine alloc] init];
		line.number = number;
		line.depth = spaces / 2;
		line.text = trimmed;
		[lines addObject:line];
	}
	_lines = lines;
	/* What it is for. */
	_header = [self headerOf:[lines firstObject]];
	if (_header == nil) {
		if (reason != NULL) {
			*reason = _failure;
		}
		return nil;
	}
	name = name ?: _header.name;
	NSUInteger index = _header.line != nil ? 1 : 0;
	ORMOutlineLine *rootLine = index < [lines count] ? [lines objectAtIndex:index] : nil;
	if (rootLine == nil || rootLine.depth != 0) {
		if (reason != NULL) {
			*reason = @"An outline starts at an object type, unindented.";
		}
		return nil;
	}
	/* The root: the longest object type name it starts with, as a node. */
	NSString *rootText = [rootLine.text hasPrefix:@"✓"] ? [rootLine.text substringFromIndex:1] : rootLine.text;
	ORMObjectType *rootType = nil;
	ORMOutlineNode *rootSaid = nil;
	for (ORMObjectType *type in _editor.model.objectTypes) {
		if (![rootText hasPrefix:type.name ?: @"\n"] || [type.name length] <= [rootType.name length]) {
			continue;
		}
		NSRegularExpression *expression = [NSRegularExpression
			regularExpressionWithPattern:[NSString stringWithFormat:@"^%@$", ORMNodePattern(type.name)] options:0 error:NULL];
		NSTextCheckingResult *match = [expression firstMatchInString:rootLine.text options:0
		                                                       range:NSMakeRange(0, [rootLine.text length])];
		if (match != nil) {
			rootType = type;
			rootSaid = ORMNodeOf(match, rootLine.text, 1);
		}
	}
	if (rootType == nil) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"Line %lu, \"%@\": no object type of the model is named so.",
			                                     (unsigned long)rootLine.number, rootLine.text];
		}
		return nil;
	}
	BOOL done = [_editor group:@"Add Query from Outline" trying:^BOOL {
		return [self makeQueryNamed:name ?: [NSString stringWithFormat:@"%@ Query", rootType.name] root:rootType
		                       said:rootSaid line:rootLine];
	}];
	if (!done) {
		if (reason != NULL) {
			*reason = _failure ?: @"The outline cannot be read.";
		}
		return nil;
	}
	return _query;
}

/* What the first line says the query is for: a constraint, a
 * calculation, a derivation; a list where it says none of them, and no
 * line of its own. nil, and why, where it names what the model has not. */
- (ORMOutlineHeader *)headerOf:(ORMOutlineLine *)line
{
	ORMOutlineHeader *header = [[ORMOutlineHeader alloc] init];
	header.kind = ORMQueryList;
	NSString *text = line.text ?: @"";
	NSRange all = NSMakeRange(0, [text length]);
	NSRegularExpression *calculation = [NSRegularExpression
		regularExpressionWithPattern:@"^(.+) of each (.+) is (value|count|total|avg|max|min)\\((.+)\\) of:$" options:0
		                       error:NULL];
	NSRegularExpression *derivation = [NSRegularExpression regularExpressionWithPattern:@"^Derivation of \"(.+)\":$"
	                                                                            options:0
	                                                                              error:NULL];
	NSTextCheckingResult *calculated = [calculation firstMatchInString:text options:0 range:all];
	NSTextCheckingResult *derived = [derivation firstMatchInString:text options:0 range:all];
	if ([text isEqualToString:@"It is impossible that:"] || [text isEqualToString:@"It is forbidden that:"]) {
		header.kind = ORMQueryConstraint;
		header.deontic = [text isEqualToString:@"It is forbidden that:"];
	} else if (calculated != nil) {
		header.kind = ORMQueryCalculation;
		header.name = ORMGroup(calculated, text, 1);
		header.function = ORMGroup(calculated, text, 3);
		header.calculated = ORMGroup(calculated, text, 4);
	} else if ([text isEqualToString:@"Derivation:"]) {
		header.kind = ORMQueryDerivation;
	} else if (derived != nil) {
		header.kind = ORMQueryDerivation;
		NSString *reading = ORMGroup(derived, text, 1);
		for (ORMFactType *fact in _editor.model.factTypes) {
			if ([[[fact primaryReading] expandedText] isEqualToString:reading]) {
				header.derived = fact;
			}
		}
		if (header.derived == nil) {
			_failure = [NSString stringWithFormat:@"Line %lu, \"%@\": no fact type of the model reads so.",
			                                      (unsigned long)line.number, text];
			return nil;
		}
	} else {
		return header;
	}
	header.line = line;
	return header;
}

/* The query the lines say, from its root: what the root says, its steps,
 * the conditions comparing nodes, what the header says it is for. NO,
 * with why in _failure, where a line cannot be read. */
- (BOOL)makeQueryNamed:(NSString *)name root:(ORMObjectType *)rootType said:(ORMOutlineNode *)rootSaid
                  line:(ORMOutlineLine *)rootLine
{
	NSString *why = nil;
	_query = [_queries addQueryNamed:name from:rootType.identifier reason:&why];
	if (_query == nil) {
		return [self fail:why ?: @"the query cannot be made" line:rootLine];
	}
	NSString *root = [self query].root.identifier;
	if (![self apply:rootSaid to:root line:rootLine]) {
		return NO;
	}
	NSUInteger next = [_lines indexOfObjectIdenticalTo:rootLine] + 1;
	if (next < [_lines count]) {
		ORMOutlineLine *first = [_lines objectAtIndex:next];
		if (first.depth != 1 || ![first.text hasPrefix:@"+ "]) {
			return [self fail:@"a step from the root is indented once, after \"+\"" line:first];
		}
		next = [self steps:next from:root];
		if (next == NSNotFound) {
			return NO;
		}
		if (next < [_lines count]) {
			return [self fail:@"it is under nothing it can be read under" line:[_lines objectAtIndex:next]];
		}
	}
	/* Conditions comparing nodes, now there are all of them. */
	for (NSArray *comparison in _comparisons) {
		ORMQueryNode *other = [self designated:[comparison objectAtIndex:2] among:[[self query] nodes]];
		if (other == nil
		    || ![_queries setCondition:[comparison objectAtIndex:1] toNode:other.identifier ofNode:[comparison firstObject]
		                        reason:&why]) {
			return [self fail:why ?: @"no node of the query is designated so" line:[comparison lastObject]];
		}
	}
	return [self makeQueryWhatItIsFor];
}

/* The query made what the header says: a constraint and its modality, a
 * calculation and what it calculates, a derivation and, where no other
 * query derives it already, its fact type. */
- (BOOL)makeQueryWhatItIsFor
{
	ORMOutlineHeader *header = _header;
	NSString *why = nil;
	if (header.kind != ORMQueryList && ![_queries setKind:header.kind ofQuery:_query reason:&why]) {
		return [self fail:why ?: @"the query cannot be one" line:header.line];
	}
	if (header.kind == ORMQueryConstraint && ![_queries setDeontic:header.deontic ofQuery:_query reason:&why]) {
		return [self fail:why ?: @"the modality cannot be set" line:header.line];
	}
	if (header.kind == ORMQueryCalculation) {
		NSArray *functions = @[ @"value", @"count", @"total", @"avg", @"max", @"min" ];
		ORMQueryNode *of = [self designated:header.calculated among:[[self query] nodes]];
		if (of == nil
		    || ![_queries setCalculation:(ORMQueryCalculationFunction)[functions indexOfObject:header.function]
		                          ofNode:of.identifier inQuery:_query reason:&why]) {
			return [self fail:why ?: @"what it calculates is no node of the query" line:header.line];
		}
	}
	/* A copy of a derivation pasted: one derivation to a fact type. */
	if (header.kind == ORMQueryDerivation && header.derived != nil
	    && [ORMQuery derivationOf:header.derived inModel:_editor.model] == nil
	    && ![_queries setDerivedFactType:header.derived.identifier ofQuery:_query reason:&why]) {
		return [self fail:why ?: @"the fact type cannot be derived so" line:header.line];
	}
	return YES;
}


@end
