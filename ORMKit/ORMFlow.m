/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlow.h"
#import "ORMModel.h"
#import "ORMQuery.h"

NSString * const ORMFlowNamespace = @"http://schemas.ormkit.org/2026-10/Flows";

NSString * const ORMFlowOnSubmitDone = @"SubmitDone";
NSString * const ORMFlowOnSubmitError = @"SubmitError";
NSString * const ORMFlowOnCancel = @"Cancel";
NSString * const ORMFlowOnRowChosen = @"RowChosen";
NSString * const ORMFlowOnTrigger = @"Trigger";

NSString * const ORMFlowKindNavigate = @"Navigate";
NSString * const ORMFlowKindOverlay = @"Overlay";
NSString * const ORMFlowKindBack = @"Back";
NSString * const ORMFlowKindClose = @"Close";

static NSError *
ORMFlowError(NSString *text)
{
	return [NSError errorWithDomain:@"ORMFlow" code:1 userInfo:@{ NSLocalizedDescriptionKey : text }];
}

static NSString *
ORMFlowAttribute(NSXMLElement *element, NSString *name)
{
	return [[element attributeForName:name] stringValue];
}

static void
ORMFlowSet(NSXMLElement *element, NSString *name, id value)
{
	if (value != nil) {
		[element addAttribute:[NSXMLNode attributeWithName:name stringValue:[value description]]];
	}
}

static NSArray<NSXMLElement *> *
ORMFlowChildren(NSXMLElement *element, NSString *name)
{
	return [element elementsForLocalName:name URI:ORMFlowNamespace];
}

/* A double's text as it is read back: "390", "12.5". */
static NSString *
ORMFlowNumber(double value)
{
	return value == floor(value) ? [NSString stringWithFormat:@"%.0f", value] : [NSString stringWithFormat:@"%g", value];
}

@implementation ORMFlowScreen
@end

@implementation ORMFlowGive
@end

@implementation ORMFlowTransition
@end

@implementation ORMFlowEntry
@end

@implementation ORMFlow

+ (instancetype)flowWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
	NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
	return data != nil ? [self flowWithData:data error:error] : nil;
}

+ (instancetype)flowWithData:(NSData *)data error:(NSError **)error
{
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:0 error:error];
	NSXMLElement *root = [document rootElement];
	if (root == nil) {
		return nil;
	}
	if (![[root localName] isEqualToString:@"Flow"] || ![[root URI] isEqualToString:ORMFlowNamespace]) {
		if (error != NULL) {
			*error = ORMFlowError([NSString stringWithFormat:@"Not a flow: its element is %@, not flow:Flow in %@.", [root name],
			                                                 ORMFlowNamespace]);
		}
		return nil;
	}
	ORMFlow *flow = [[self alloc] init];
	flow.name = ORMFlowAttribute(root, @"Name");
	flow.modelPath = ORMFlowAttribute(root, @"Model");
	NSMutableArray *entries = [NSMutableArray array], *screens = [NSMutableArray array], *transitions = [NSMutableArray array];
	for (NSXMLElement *element in ORMFlowChildren(root, @"Entry")) {
		ORMFlowEntry *entry = [[ORMFlowEntry alloc] init];
		entry.name = ORMFlowAttribute(element, @"Name");
		entry.screen = ORMFlowAttribute(element, @"Screen");
		[entries addObject:entry];
	}
	for (NSXMLElement *element in ORMFlowChildren(root, @"Screen")) {
		ORMFlowScreen *screen = [[ORMFlowScreen alloc] init];
		screen.identifier = ORMFlowAttribute(element, @"id");
		screen.name = ORMFlowAttribute(element, @"Name");
		screen.formId = ORMFlowAttribute(element, @"Form");
		screen.queryId = ORMFlowAttribute(element, @"Query");
		screen.x = [ORMFlowAttribute(element, @"X") doubleValue];
		screen.y = [ORMFlowAttribute(element, @"Y") doubleValue];
		screen.width = [ORMFlowAttribute(element, @"Width") doubleValue];
		screen.height = [ORMFlowAttribute(element, @"Height") doubleValue];
		[screens addObject:screen];
	}
	for (NSXMLElement *element in ORMFlowChildren(root, @"Transition")) {
		ORMFlowTransition *transition = [[ORMFlowTransition alloc] init];
		transition.fromScreen = ORMFlowAttribute(element, @"From");
		transition.on = ORMFlowAttribute(element, @"On");
		transition.control = ORMFlowAttribute(element, @"Control");
		transition.toScreen = ORMFlowAttribute(element, @"To");
		transition.kind = ORMFlowAttribute(element, @"Kind") ?: ORMFlowKindNavigate;
		NSMutableArray *gives = [NSMutableArray array];
		for (NSXMLElement *each in ORMFlowChildren(element, @"Give")) {
			ORMFlowGive *give = [[ORMFlowGive alloc] init];
			give.nodeId = ORMFlowAttribute(each, @"Node");
			give.from = ORMFlowAttribute(each, @"From");
			[gives addObject:give];
		}
		transition.gives = gives;
		[transitions addObject:transition];
	}
	flow.entries = entries;
	flow.screens = screens;
	flow.transitions = transitions;
	return flow;
}

- (NSData *)XMLData
{
	NSXMLElement *root = [NSXMLElement elementWithName:@"flow:Flow" URI:ORMFlowNamespace];
	[root addNamespace:[NSXMLNode namespaceWithName:@"flow" stringValue:ORMFlowNamespace]];
	ORMFlowSet(root, @"Name", _name);
	ORMFlowSet(root, @"Model", _modelPath);
	for (ORMFlowEntry *entry in _entries) {
		NSXMLElement *element = [NSXMLElement elementWithName:@"flow:Entry" URI:ORMFlowNamespace];
		ORMFlowSet(element, @"Name", entry.name);
		ORMFlowSet(element, @"Screen", entry.screen);
		[root addChild:element];
	}
	for (ORMFlowScreen *screen in _screens) {
		NSXMLElement *element = [NSXMLElement elementWithName:@"flow:Screen" URI:ORMFlowNamespace];
		ORMFlowSet(element, @"id", screen.identifier);
		ORMFlowSet(element, @"Form", screen.formId);
		ORMFlowSet(element, @"Query", screen.queryId);
		ORMFlowSet(element, @"Name", screen.name);
		ORMFlowSet(element, @"X", ORMFlowNumber(screen.x));
		ORMFlowSet(element, @"Y", ORMFlowNumber(screen.y));
		ORMFlowSet(element, @"Width", ORMFlowNumber(screen.width));
		ORMFlowSet(element, @"Height", ORMFlowNumber(screen.height));
		[root addChild:element];
	}
	for (ORMFlowTransition *transition in _transitions) {
		NSXMLElement *element = [NSXMLElement elementWithName:@"flow:Transition" URI:ORMFlowNamespace];
		ORMFlowSet(element, @"From", transition.fromScreen);
		ORMFlowSet(element, @"On", transition.on);
		ORMFlowSet(element, @"Control", transition.control);
		ORMFlowSet(element, @"To", transition.toScreen);
		if (![transition.kind isEqualToString:ORMFlowKindNavigate]) {
			ORMFlowSet(element, @"Kind", transition.kind);
		}
		for (ORMFlowGive *give in transition.gives) {
			NSXMLElement *each = [NSXMLElement elementWithName:@"flow:Give" URI:ORMFlowNamespace];
			ORMFlowSet(each, @"Node", give.nodeId);
			ORMFlowSet(each, @"From", give.from);
			[element addChild:each];
		}
		[root addChild:element];
	}
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithRootElement:root];
	[document setVersion:@"1.0"];
	[document setCharacterEncoding:@"UTF-8"];
	return [document XMLDataWithOptions:NSXMLNodePrettyPrint];
}

- (ORMFlowScreen *)screenWithId:(NSString *)identifier
{
	for (ORMFlowScreen *screen in _screens) {
		if ([screen.identifier isEqualToString:identifier]) {
			return screen;
		}
	}
	return nil;
}

- (ORMQuery *)queryOf:(ORMFlowScreen *)screen inModel:(ORMModel *)model
{
	NSString *identifier = screen.formId ?: screen.queryId;
	return identifier != nil ? [ORMQuery queryWithId:identifier inModel:model] : nil;
}

static NSString *
ORMFlowScreenName(ORMFlowScreen *screen)
{
	return screen.name ?: screen.identifier ?: @"?";
}

/* The form's given nodes, by id. */
static NSDictionary<NSString *, ORMQueryNode *> *
ORMFlowInputs(ORMQuery *form)
{
	NSMutableDictionary *inputs = [NSMutableDictionary dictionary];
	for (ORMQueryNode *node in [form nodes]) {
		if (node.isGiven && node.identifier != nil) {
			[inputs setObject:node forKey:node.identifier];
		}
	}
	return inputs;
}

- (ORMFlowScreen *)openerOf:(ORMFlowScreen *)overlay
{
	for (ORMFlowTransition *transition in _transitions) {
		if ([transition.kind isEqualToString:ORMFlowKindOverlay] && [transition.toScreen isEqualToString:overlay.identifier]) {
			return [self screenWithId:transition.fromScreen];
		}
	}
	return nil;
}

- (NSArray<NSString *> *)problemsInModel:(ORMModel *)model
{
	NSMutableArray *problems = [NSMutableArray array];
	NSMutableSet *ids = [NSMutableSet set];
	for (ORMFlowScreen *screen in _screens) {
		NSString *name = ORMFlowScreenName(screen);
		if (screen.identifier == nil || [ids containsObject:screen.identifier]) {
			[problems addObject:[NSString stringWithFormat:@"The screen %@ has no id of its own.", name]];
		}
		if (screen.identifier != nil) {
			[ids addObject:screen.identifier];
		}
		if (screen.formId != nil && screen.queryId != nil) {
			[problems addObject:[NSString stringWithFormat:@"The screen %@ shows a form and a list: one of them.", name]];
			continue;
		}
		if (screen.formId == nil && screen.queryId == nil) {
			continue;
		}
		ORMQuery *query = [self queryOf:screen inModel:model];
		if (query == nil) {
			[problems addObject:[NSString stringWithFormat:@"The screen %@ shows %@, which the model no longer has.", name,
			                                               screen.formId ?: screen.queryId]];
		} else if (screen.formId != nil && query.kind != ORMQueryForm) {
			[problems addObject:[NSString stringWithFormat:@"The screen %@ shows %@ as a form, which is not one.", name,
			                                               query.name ?: screen.formId]];
		} else if (screen.queryId != nil && query.kind != ORMQueryList) {
			[problems addObject:[NSString stringWithFormat:@"The screen %@ lists %@, which is not a list.", name,
			                                               query.name ?: screen.queryId]];
		}
	}
	NSArray *ons = @[ ORMFlowOnSubmitDone, ORMFlowOnSubmitError, ORMFlowOnCancel, ORMFlowOnRowChosen, ORMFlowOnTrigger ];
	NSArray *kinds = @[ ORMFlowKindNavigate, ORMFlowKindOverlay, ORMFlowKindBack, ORMFlowKindClose ];
	for (ORMFlowTransition *transition in _transitions) {
		ORMFlowScreen *from = [self screenWithId:transition.fromScreen];
		ORMFlowScreen *to = transition.toScreen != nil ? [self screenWithId:transition.toScreen] : nil;
		NSString *said = [NSString stringWithFormat:@"%@ on %@", from != nil ? ORMFlowScreenName(from) : transition.fromScreen ?: @"?",
		                                            transition.on ?: @"?"];
		if (from == nil) {
			[problems addObject:[NSString stringWithFormat:@"A transition is from %@, no screen of the flow.", transition.fromScreen ?: @"nothing"]];
			continue;
		}
		if (![ons containsObject:transition.on ?: @""]) {
			[problems addObject:[NSString stringWithFormat:@"%@: no action is %@.", said, transition.on ?: @"nothing"]];
		} else if (from.formId != nil && [transition.on isEqualToString:ORMFlowOnRowChosen]) {
			[problems addObject:[NSString stringWithFormat:@"%@: a form has no rows to choose.", said]];
		} else if (from.queryId != nil
		           && ([transition.on hasPrefix:@"Submit"] || [transition.on isEqualToString:ORMFlowOnCancel])) {
			[problems addObject:[NSString stringWithFormat:@"%@: a list is not submitted.", said]];
		} else if ([transition.on isEqualToString:ORMFlowOnTrigger] && transition.control == nil) {
			[problems addObject:[NSString stringWithFormat:@"%@: a trigger names its control.", said]];
		}
		if (![kinds containsObject:transition.kind ?: @""]) {
			[problems addObject:[NSString stringWithFormat:@"%@: no transition is of the kind %@.", said, transition.kind]];
		}
		BOOL goes = [transition.kind isEqualToString:ORMFlowKindNavigate] || [transition.kind isEqualToString:ORMFlowKindOverlay];
		if (goes && to == nil) {
			[problems addObject:[NSString stringWithFormat:@"%@ goes to %@, no screen of the flow.", said, transition.toScreen ?: @"nothing"]];
			continue;
		}
		if (!goes && transition.toScreen != nil) {
			[problems addObject:[NSString stringWithFormat:@"%@ goes %@: to no screen of its own.", said,
			                                               [transition.kind lowercaseString]]];
		}
		ORMQuery *form = to.formId != nil ? [self queryOf:to inModel:model] : nil;
		NSDictionary *inputs = form != nil ? ORMFlowInputs(form) : @{};
		/* An overlay closed gives what it made to the form it was over:
		 * any of that form's nodes (the expense kind just made, chosen). */
		ORMFlowScreen *opener = [transition.kind isEqualToString:ORMFlowKindClose] ? [self openerOf:from] : nil;
		if (opener != nil) {
			to = opener;
			form = to.formId != nil ? [self queryOf:to inModel:model] : nil;
			NSMutableDictionary *nodes = [NSMutableDictionary dictionary];
			for (ORMQueryNode *node in [form nodes]) {
				if (node.identifier != nil) {
					[nodes setObject:node forKey:node.identifier];
				}
			}
			inputs = nodes;
		} else if ([transition.kind isEqualToString:ORMFlowKindClose] && [transition.gives count] > 0) {
			[problems addObject:[NSString stringWithFormat:@"%@ closes, but %@ is opened over nothing.", said, ORMFlowScreenName(from)]];
			continue;
		}
		for (ORMFlowGive *give in transition.gives) {
			if (to.formId == nil) {
				[problems addObject:[NSString stringWithFormat:@"%@ gives a value to %@, which is no form.", said, ORMFlowScreenName(to)]];
				break;
			}
			if (form != nil && [inputs objectForKey:give.nodeId ?: @""] == nil) {
				[problems addObject:[NSString stringWithFormat:@"%@ gives %@, which is not an input of %@.", said, give.nodeId ?: @"nothing",
				                                               form.name ?: ORMFlowScreenName(to)]];
			}
			NSString *source = give.from ?: @"";
			if ([source isEqualToString:@"row"] && from.queryId == nil) {
				[problems addObject:[NSString stringWithFormat:@"%@ gives the row chosen, but %@ is no list.", said, ORMFlowScreenName(from)]];
			} else if (![source isEqualToString:@"row"] && ![source isEqualToString:@"result"]) {
				NSRange dot = [source rangeOfString:@"."];
				if (dot.location == NSNotFound || [self screenWithId:[source substringToIndex:dot.location]] == nil) {
					[problems addObject:[NSString stringWithFormat:@"%@ gives %@ from %@: \"row\", \"result\" or a screen's node.", said,
					                                               give.nodeId ?: @"?", give.from ?: @"nothing"]];
				}
			}
		}
	}
	for (ORMFlowEntry *entry in _entries) {
		if ([self screenWithId:entry.screen] == nil) {
			[problems addObject:[NSString stringWithFormat:@"The entry %@ is to %@, no screen of the flow.", entry.name ?: @"?",
			                                               entry.screen ?: @"nothing"]];
		}
	}
	if ([_entries count] == 0) {
		[problems addObject:@"The flow has no entry: nowhere it begins."];
	}
	return problems;
}

- (NSArray<NSString *> *)inputsLeftBy:(ORMFlowTransition *)transition inModel:(ORMModel *)model
{
	ORMFlowScreen *to = transition.toScreen != nil ? [self screenWithId:transition.toScreen] : nil;
	ORMQuery *form = to.formId != nil ? [self queryOf:to inModel:model] : nil;
	NSMutableArray *left = [[ORMFlowInputs(form) allKeys] mutableCopy] ?: [NSMutableArray array];
	for (ORMFlowGive *give in transition.gives) {
		[left removeObject:give.nodeId ?: @""];
	}
	[left sortUsingSelector:@selector(compare:)];
	return left;
}

- (NSString *)textInModel:(ORMModel *)model
{
	NSMutableString *out = [NSMutableString stringWithFormat:@"Flow %@ (%@)\n", _name ?: @"?", _modelPath ?: @"no model"];
	NSString *(^named)(ORMFlowScreen *) = ^NSString *(ORMFlowScreen *screen) {
		NSString *kind = screen.formId != nil ? @"form" : screen.queryId != nil ? @"list" : @"placeholder";
		return [NSString stringWithFormat:@"%@ (%@)", ORMFlowScreenName(screen), kind];
	};
	for (ORMFlowEntry *entry in _entries) {
		ORMFlowScreen *screen = [self screenWithId:entry.screen];
		[out appendFormat:@"▶ %@: %@\n", entry.name ?: @"?", screen != nil ? ORMFlowScreenName(screen) : entry.screen ?: @"?"];
	}
	for (ORMFlowTransition *transition in _transitions) {
		ORMFlowScreen *from = [self screenWithId:transition.fromScreen];
		ORMFlowScreen *to = transition.toScreen != nil ? [self screenWithId:transition.toScreen] : nil;
		NSString *on = transition.control != nil ? [NSString stringWithFormat:@"%@ %@", transition.on, transition.control] : transition.on;
		NSString *target = to != nil ? named(to) : [transition.kind lowercaseString];
		if ([transition.kind isEqualToString:ORMFlowKindOverlay]) {
			target = [target stringByAppendingString:@" over it"];
		}
		ORMQuery *form = to.formId != nil ? [self queryOf:to inModel:model] : nil;
		NSMutableArray *gives = [NSMutableArray array];
		for (ORMFlowGive *give in transition.gives) {
			ORMQueryNode *node = nil;
			for (ORMQueryNode *each in [form nodes]) {
				if ([each.identifier isEqualToString:give.nodeId]) {
					node = each;
				}
			}
			NSString *nodeName = node.objectType.name ?: node.name ?: give.nodeId ?: @"?";
			[gives addObject:[NSString stringWithFormat:@"%@ = %@", nodeName, give.from ?: @"?"]];
		}
		[out appendFormat:@"%@ —%@→ %@%@\n", from != nil ? named(from) : transition.fromScreen ?: @"?", on ?: @"?", target,
		                  [gives count] > 0 ? [@": " stringByAppendingString:[gives componentsJoinedByString:@", "]] : @""];
	}
	return out;
}

@end
