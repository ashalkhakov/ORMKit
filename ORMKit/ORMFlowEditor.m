/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlowEditor.h"
#import "ORMModel.h"
#import "ORMQuery.h"

NSNotificationName const ORMFlowEditorDidChangeNotification = @"ORMFlowEditorDidChange";

/* A screen's frame as the canvas first draws it: a phone's. */
static const double ORMFlowScreenWidth = 240;
static const double ORMFlowScreenHeight = 320;

@implementation ORMFlowEditor {
	ORMFlow *_flow;
}

- (instancetype)initWithFlow:(ORMFlow *)flow model:(ORMModel *)model undoManager:(NSUndoManager *)undoManager
{
	if ((self = [super init])) {
		_flow = flow ?: [[ORMFlow alloc] init];
		_model = model;
		_undoManager = undoManager;
		if (_flow.screens == nil) {
			_flow.screens = @[];
		}
		if (_flow.transitions == nil) {
			_flow.transitions = @[];
		}
		if (_flow.entries == nil) {
			_flow.entries = @[];
		}
	}
	return self;
}

- (ORMFlow *)flow
{
	return _flow;
}

#pragma mark Changes

/* The flow put back as the data has it: what undoing and redoing do. */
- (void)restore:(NSData *)data
{
	NSData *now = [_flow XMLData];
	ORMFlow *read = [ORMFlow flowWithData:data error:NULL];
	if (read == nil) {
		return;
	}
	[self takeFlow:read];
	[_undoManager registerUndoWithTarget:self selector:@selector(restore:) object:now];
	[[NSNotificationCenter defaultCenter] postNotificationName:ORMFlowEditorDidChangeNotification object:self];
}

- (void)takeFlow:(ORMFlow *)read
{
	_flow.name = read.name;
	_flow.modelPath = read.modelPath;
	_flow.screens = read.screens ?: @[];
	_flow.transitions = read.transitions ?: @[];
	_flow.entries = read.entries ?: @[];
}

/* A change, one undo step named so; nothing registered where it changed
 * nothing. */
- (void)change:(NSString *)name with:(void (^)(void))change
{
	NSData *before = [_flow XMLData];
	change();
	if ([[_flow XMLData] isEqualToData:before]) {
		return;
	}
	[_undoManager registerUndoWithTarget:self selector:@selector(restore:) object:before];
	[_undoManager setActionName:name];
	[[NSNotificationCenter defaultCenter] postNotificationName:ORMFlowEditorDidChangeNotification object:self];
}

- (NSData *)XMLData
{
	return [_flow XMLData];
}

- (BOOL)readData:(NSData *)data error:(NSError **)error
{
	ORMFlow *read = [ORMFlow flowWithData:data error:error];
	if (read == nil) {
		return NO;
	}
	[self takeFlow:read];
	[[NSNotificationCenter defaultCenter] postNotificationName:ORMFlowEditorDidChangeNotification object:self];
	return YES;
}

#pragma mark The model

- (NSArray<ORMQuery *> *)queriesOfKind:(ORMQueryKind)kind
{
	NSMutableArray *found = [NSMutableArray array];
	for (ORMQuery *query in _model != nil ? [ORMQuery queriesInModel:_model] : @[]) {
		if (query.kind == kind && [query.name length] > 0) {
			[found addObject:query];
		}
	}
	[found sortUsingComparator:^NSComparisonResult(ORMQuery *a, ORMQuery *b) {
		return [a.name localizedStandardCompare:b.name];
	}];
	return found;
}

- (NSArray<ORMQuery *> *)forms
{
	return [self queriesOfKind:ORMQueryForm];
}

- (NSArray<ORMQuery *> *)lists
{
	return [self queriesOfKind:ORMQueryList];
}

- (ORMQuery *)queryOfScreen:(ORMFlowScreen *)screen
{
	NSString *identifier = screen.formId ?: screen.queryId;
	return identifier != nil && _model != nil ? [ORMQuery queryWithId:identifier inModel:_model] : nil;
}

- (NSArray<NSString *> *)inputsOfScreen:(ORMFlowScreen *)screen
{
	NSMutableArray *inputs = [NSMutableArray array];
	if (screen.formId == nil) {
		return inputs;
	}
	for (ORMQueryNode *node in [[self queryOfScreen:screen] nodes]) {
		if (node.isGiven && node.identifier != nil) {
			[inputs addObject:node.identifier];
		}
	}
	return inputs;
}

- (ORMQueryNode *)node:(NSString *)nodeId inScreen:(ORMFlowScreen *)screen
{
	for (ORMQueryNode *node in [[self queryOfScreen:screen] nodes]) {
		if ([node.identifier isEqualToString:nodeId]) {
			return node;
		}
	}
	return nil;
}

- (NSString *)nameOfNode:(NSString *)nodeId inScreen:(ORMFlowScreen *)screen
{
	ORMQueryNode *node = [self node:nodeId inScreen:screen];
	return node.objectType.name ?: node.name ?: nodeId;
}

- (NSArray<NSString *> *)problems
{
	return _model != nil ? [_flow problemsInModel:_model] : @[];
}

#pragma mark Screens

/* An id the flow has not: the name's letters, numbered where taken. */
- (NSString *)newScreenIdFor:(NSString *)name
{
	NSMutableString *base = [NSMutableString string];
	for (NSUInteger i = 0; i < [name length]; i++) {
		unichar c = [name characterAtIndex:i];
		if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:c]) {
			[base appendFormat:@"%C", c];
		}
	}
	if ([base length] == 0) {
		[base setString:@"screen"];
	}
	NSString *candidate = base;
	for (NSUInteger n = 2; [_flow screenWithId:candidate] != nil; n++) {
		candidate = [NSString stringWithFormat:@"%@%lu", base, (unsigned long)n];
	}
	return candidate;
}

- (ORMFlowScreen *)addScreenForQuery:(ORMQuery *)query at:(NSPoint)origin
{
	ORMFlowScreen *screen = [[ORMFlowScreen alloc] init];
	screen.name = query.name ?: @"Screen";
	screen.identifier = [self newScreenIdFor:screen.name];
	if (query.kind == ORMQueryForm) {
		screen.formId = query.identifier;
	} else if (query != nil) {
		screen.queryId = query.identifier;
	}
	screen.x = round(origin.x);
	screen.y = round(origin.y);
	screen.width = ORMFlowScreenWidth;
	screen.height = ORMFlowScreenHeight;
	[self change:[NSString stringWithFormat:@"Add %@", screen.name] with:^{
		self->_flow.screens = [self->_flow.screens arrayByAddingObject:screen];
		if ([self->_flow.entries count] == 0) {
			ORMFlowEntry *entry = [[ORMFlowEntry alloc] init];
			entry.name = @"Start";
			entry.screen = screen.identifier;
			self->_flow.entries = @[ entry ];
		}
	}];
	return screen;
}

- (void)moveScreens:(NSArray<NSString *> *)screenIds by:(NSSize)delta
{
	[self change:[screenIds count] == 1 ? @"Move Screen" : @"Move Screens" with:^{
		for (NSString *identifier in screenIds) {
			ORMFlowScreen *screen = [self->_flow screenWithId:identifier];
			screen.x += delta.width;
			screen.y += delta.height;
		}
	}];
}

- (void)renameScreen:(NSString *)screenId to:(NSString *)name
{
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed length] == 0) {
		return;
	}
	[self change:@"Rename Screen" with:^{
		[self->_flow screenWithId:screenId].name = trimmed;
	}];
}

- (void)removeScreens:(NSArray<NSString *> *)screenIds
{
	NSSet *gone = [NSSet setWithArray:screenIds];
	[self change:[screenIds count] == 1 ? @"Delete Screen" : @"Delete Screens" with:^{
		NSMutableArray *screens = [NSMutableArray array], *transitions = [NSMutableArray array], *entries = [NSMutableArray array];
		for (ORMFlowScreen *screen in self->_flow.screens) {
			if (![gone containsObject:screen.identifier]) {
				[screens addObject:screen];
			}
		}
		for (ORMFlowTransition *transition in self->_flow.transitions) {
			if (![gone containsObject:transition.fromScreen] && ![gone containsObject:transition.toScreen ?: @""]) {
				[transitions addObject:transition];
			}
		}
		for (ORMFlowEntry *entry in self->_flow.entries) {
			if (![gone containsObject:entry.screen]) {
				[entries addObject:entry];
			}
		}
		self->_flow.screens = screens;
		self->_flow.transitions = transitions;
		self->_flow.entries = entries;
	}];
}

#pragma mark Transitions

/* What a transition from the screen gives the next form: each input of
 * the form's of the type the list's anchor is, the row. */
- (NSArray<ORMFlowGive *> *)givesFrom:(ORMFlowScreen *)from to:(ORMFlowScreen *)to
{
	NSMutableArray *gives = [NSMutableArray array];
	ORMQuery *list = from.queryId != nil ? [self queryOfScreen:from] : nil;
	ORMObjectType *anchor = list.root.objectType;
	for (NSString *input in [self inputsOfScreen:to]) {
		ORMQueryNode *node = [self node:input inScreen:to];
		if (anchor != nil && node.objectType == anchor) {
			ORMFlowGive *give = [[ORMFlowGive alloc] init];
			give.nodeId = input;
			give.from = @"row";
			[gives addObject:give];
		}
	}
	return gives;
}

- (ORMFlowTransition *)addTransitionFrom:(NSString *)fromId to:(NSString *)toId
{
	ORMFlowScreen *from = [_flow screenWithId:fromId], *to = [_flow screenWithId:toId];
	if (from == nil || to == nil || from == to) {
		return nil;
	}
	ORMFlowTransition *transition = [[ORMFlowTransition alloc] init];
	transition.fromScreen = fromId;
	transition.toScreen = toId;
	transition.on = from.queryId != nil ? ORMFlowOnRowChosen : ORMFlowOnSubmitDone;
	transition.kind = ORMFlowKindNavigate;
	transition.gives = [self givesFrom:from to:to];
	[self change:@"Add Transition" with:^{
		self->_flow.transitions = [self->_flow.transitions arrayByAddingObject:transition];
	}];
	return transition;
}

- (ORMFlowTransition *)addReturnFrom:(NSString *)fromId on:(NSString *)on kind:(NSString *)kind
{
	if ([_flow screenWithId:fromId] == nil) {
		return nil;
	}
	ORMFlowTransition *transition = [[ORMFlowTransition alloc] init];
	transition.fromScreen = fromId;
	transition.on = on ?: ORMFlowOnCancel;
	transition.kind = kind ?: ORMFlowKindBack;
	transition.gives = @[];
	[self change:@"Add Return" with:^{
		self->_flow.transitions = [self->_flow.transitions arrayByAddingObject:transition];
	}];
	return transition;
}

- (ORMFlowTransition *)transitionAt:(NSUInteger)index
{
	return index < [_flow.transitions count] ? [_flow.transitions objectAtIndex:index] : nil;
}

- (void)setOn:(NSString *)on control:(NSString *)control ofTransition:(NSUInteger)index
{
	ORMFlowTransition *transition = [self transitionAt:index];
	[self change:@"Change Action" with:^{
		transition.on = on;
		transition.control = [on isEqualToString:ORMFlowOnTrigger] && [control length] > 0 ? control : nil;
	}];
}

- (void)setKind:(NSString *)kind ofTransition:(NSUInteger)index
{
	ORMFlowTransition *transition = [self transitionAt:index];
	[self change:@"Change Transition" with:^{
		transition.kind = kind;
		if ([kind isEqualToString:ORMFlowKindBack] || [kind isEqualToString:ORMFlowKindClose]) {
			transition.toScreen = nil;
			transition.gives = @[];
		}
	}];
}

- (void)setTarget:(NSString *)toId ofTransition:(NSUInteger)index
{
	ORMFlowTransition *transition = [self transitionAt:index];
	ORMFlowScreen *from = [_flow screenWithId:transition.fromScreen], *to = [_flow screenWithId:toId];
	if (transition == nil || to == nil) {
		return;
	}
	[self change:@"Change Transition" with:^{
		transition.toScreen = toId;
		if ([transition.kind isEqualToString:ORMFlowKindBack] || [transition.kind isEqualToString:ORMFlowKindClose]) {
			transition.kind = ORMFlowKindNavigate;
		}
		transition.gives = [self givesFrom:from to:to];
	}];
}

- (void)setGives:(NSArray<ORMFlowGive *> *)gives ofTransition:(NSUInteger)index
{
	ORMFlowTransition *transition = [self transitionAt:index];
	[self change:@"Change What It Gives" with:^{
		transition.gives = gives ?: @[];
	}];
}

- (void)removeTransitions:(NSIndexSet *)indexes
{
	[self change:[indexes count] == 1 ? @"Delete Transition" : @"Delete Transitions" with:^{
		NSMutableArray *kept = [self->_flow.transitions mutableCopy];
		[kept removeObjectsAtIndexes:indexes];
		self->_flow.transitions = kept;
	}];
}

#pragma mark Entries

- (void)addEntryNamed:(NSString *)name toScreen:(NSString *)screenId
{
	if ([_flow screenWithId:screenId] == nil || [name length] == 0) {
		return;
	}
	ORMFlowEntry *entry = [[ORMFlowEntry alloc] init];
	entry.name = name;
	entry.screen = screenId;
	[self change:@"Add Entry" with:^{
		self->_flow.entries = [self->_flow.entries arrayByAddingObject:entry];
	}];
}

- (void)setEntries:(NSArray<ORMFlowEntry *> *)entries
{
	[self change:@"Change Entries" with:^{
		self->_flow.entries = entries ?: @[];
	}];
}

@end
