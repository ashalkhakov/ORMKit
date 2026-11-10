/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlowWalk.h"
#import "ORMFlow.h"
#import "ORMFormDocument.h"
#import "ORMPopulationStore.h"
#import "ORMQueryPlanner.h"
#import "ORMForm.h"
#import "ORMFormSession.h"
#import "ORMQueryInterpreter.h"
#import <CoreData/CoreData.h>

static NSString * const ORMFlowWalkErrorDomain = @"ORMFlowWalk";

static NSError *
ORMFlowWalkError(NSString *text)
{
	return [NSError errorWithDomain:ORMFlowWalkErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey : text }];
}

/* A value read as the form's table has it: text. */
static NSString *
ORMFlowWalkText(id value)
{
	if (value == nil || value == [NSNull null]) {
		return @"";
	}
	if ([value isKindOfClass:[NSUUID class]]) {
		return [value UUIDString];
	}
	if ([value isKindOfClass:[NSDate class]]) {
		NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		[formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
		[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
		[formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
		return [formatter stringFromDate:value];
	}
	return [value description];
}

/* A screen open: what it shows, and what it had. */
@interface ORMFlowWalkFrame : NSObject
@property (nonatomic, strong) ORMFlowScreen *screen;
@property (nonatomic, strong) ORMFormDocument *document;
@property (nonatomic, strong) ORMFormSession *session;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *rows;
@property (nonatomic, copy) NSArray<NSString *> *rowKeys;
/* A list's rows by node id, each column of the query a node's. */
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *rowsByNode;
/* Opened over the frame below it, as an overlay. */
@property (nonatomic) BOOL overlay;
/* Walked: submitted once already. */
@property (nonatomic) BOOL submitted;
@end

@implementation ORMFlowWalkFrame
@end

@implementation ORMFlowWalk
{
	ORMModel *_model;
	ORMCoreDataMapping *_mapping;
	ORMQueryPlanner *_planner;
	ORMPopulationStore *_store;
	NSManagedObjectContext *_context;
	ORMQueryInterpreter *_interpreter;
	NSMutableArray<ORMFlowWalkFrame *> *_frames;
	/* What each screen had last, by its id: its nodes' values, by id. */
	NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSString *> *> *_known;
	NSMutableArray<NSString *> *_log;
}

- (instancetype)initWithFlow:(ORMFlow *)flow model:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	if ((self = [super init])) {
		_flow = flow;
		_model = model;
		_mapping = mapping;
		_frames = [NSMutableArray array];
		_known = [NSMutableDictionary dictionary];
		_log = [NSMutableArray array];
	}
	return self;
}

- (NSArray<NSString *> *)log
{
	return [_log copy];
}

- (ORMFlowWalkFrame *)frame
{
	return [_frames lastObject];
}

- (ORMFlowScreen *)screen
{
	return [self frame].screen;
}

- (NSArray<NSDictionary<NSString *, NSString *> *> *)rows
{
	return [self frame].rows;
}

- (NSArray<NSString *> *)rowKeys
{
	return [self frame].rowKeys;
}

- (ORMFormSession *)session
{
	return [self frame].session;
}

- (NSArray<ORMFlowTransition *> *)transitions
{
	NSMutableArray *ways = [NSMutableArray array];
	for (ORMFlowTransition *transition in _flow.transitions) {
		if ([transition.fromScreen isEqualToString:[self screen].identifier]) {
			[ways addObject:transition];
		}
	}
	return ways;
}

static NSString *
ORMFlowWalkName(ORMFlowScreen *screen)
{
	return screen.name ?: screen.identifier ?: @"?";
}

#pragma mark Opening

- (BOOL)beginAt:(NSString *)entryName error:(NSError **)error
{
	ORMFlowEntry *entry = nil;
	for (ORMFlowEntry *each in _flow.entries) {
		if (entryName == nil || [each.name isEqualToString:entryName]) {
			entry = each;
			break;
		}
	}
	ORMFlowScreen *screen = entry != nil ? [_flow screenWithId:entry.screen] : nil;
	if (screen == nil) {
		if (error != NULL) {
			*error = ORMFlowWalkError([NSString stringWithFormat:@"The flow has no entry %@.", entryName ?: @"at all"]);
		}
		return NO;
	}
	_planner = [[ORMQueryPlanner alloc] initWithModel:_model mapping:_mapping];
	_store = [[ORMPopulationStore alloc] initWithModel:_model coreData:_planner.coreData];
	_context = [_store newContextWithError:error];
	if (_context == nil) {
		return NO;
	}
	_interpreter = [[ORMQueryInterpreter alloc] initWithModel:_store.managedObjectModel];
	[_frames removeAllObjects];
	[_known removeAllObjects];
	[_log removeAllObjects];
	ORMFlowWalkFrame *frame = [self open:screen given:@{} error:error];
	if (frame == nil) {
		return NO;
	}
	[_frames addObject:frame];
	[_log addObject:[NSString stringWithFormat:@"▶ %@: %@", entry.name ?: @"?", [self said:frame]]];
	return YES;
}

/* A screen as it opens: a list's rows read, a form's session opened with
 * what it is given (its given nodes' values, by id). */
- (ORMFlowWalkFrame *)open:(ORMFlowScreen *)screen given:(NSDictionary<NSString *, NSString *> *)given error:(NSError **)error
{
	ORMFlowWalkFrame *frame = [[ORMFlowWalkFrame alloc] init];
	frame.screen = screen;
	ORMQuery *query = [_flow queryOf:screen inModel:_model];
	if (query == nil) {
		if (error != NULL) {
			*error = ORMFlowWalkError([NSString stringWithFormat:@"%@ shows nothing the model has.", ORMFlowWalkName(screen)]);
		}
		return nil;
	}
	if (screen.queryId != nil) {
		ORMQueryPlan *plan = [_planner planForQuery:query];
		__block ORMQueryResult *result = nil;
		__block NSError *failed = nil;
		[_context performBlockAndWait:^{
			result = [self->_interpreter executePlan:plan inContext:self->_context error:&failed];
		}];
		if (result == nil) {
			if (error != NULL) {
				*error = ORMFlowWalkError([NSString stringWithFormat:@"%@ cannot be listed: %@", ORMFlowWalkName(screen),
				                                                    failed.localizedDescription ?: [plan.notes componentsJoinedByString:@" "]]);
			}
			return nil;
		}
		ORMPlanColumn *anchor = [plan columnOfNode:query.root.identifier];
		NSUInteger keyAt = anchor != nil ? [plan.columns indexOfObject:anchor] : NSNotFound;
		NSMutableArray *rows = [NSMutableArray array], *keys = [NSMutableArray array], *byNode = [NSMutableArray array];
		for (NSArray *row in result.rows) {
			NSMutableDictionary *named = [NSMutableDictionary dictionary], *nodes = [NSMutableDictionary dictionary];
			for (NSUInteger i = 0; i < [row count] && i < [plan.columns count]; i++) {
				NSString *text = ORMFlowWalkText([row objectAtIndex:i]);
				ORMPlanColumn *column = [plan.columns objectAtIndex:i];
				NSString *title = i < [result.columnTitles count] ? [result.columnTitles objectAtIndex:i] : column.nodeId;
				[named setObject:text forKey:title ?: @""];
				if (column.nodeId != nil) {
					[nodes setObject:text forKey:column.nodeId];
				}
			}
			[rows addObject:named];
			[byNode addObject:nodes];
			[keys addObject:keyAt != NSNotFound && keyAt < [row count] ? ORMFlowWalkText([row objectAtIndex:keyAt]) : @""];
		}
		frame.rows = rows;
		frame.rowKeys = keys;
		frame.rowsByNode = byNode;
		return frame;
	}
	NSString *reason = nil;
	ORMFormDocument *document = [ORMFormDocument documentForForm:query model:_model mapping:_mapping reason:&reason];
	ORMForm *form = document != nil ? [ORMForm formWithPropertyList:[document tablePropertyList] error:error] : nil;
	if (form == nil) {
		if (error != NULL && reason != nil) {
			*error = ORMFlowWalkError([NSString stringWithFormat:@"%@ is no form to open: %@", ORMFlowWalkName(screen), reason]);
		}
		return nil;
	}
	NSMutableDictionary *elements = [NSMutableDictionary dictionary];
	for (NSString *nodeId in given) {
		NSString *element = [document elementOfNode:nodeId];
		if (element != nil) {
			[elements setObject:[given objectForKey:nodeId] forKey:element];
		}
	}
	ORMFormSession *session = [[ORMFormSession alloc] initWithForm:form given:elements];
	/* The population's store asks for nothing (a sample need not be
	 * whole), so what the form asks of each value is asked here, said in
	 * the constraint's own words at its element, as the form would say it
	 * before it submits; then saved. */
	NSDictionary *required = [document requiredElements];
	NSString *entityName = document.entityName;
	[session useContext:_context saving:^BOOL(NSManagedObjectContext *context, NSError **error) {
		NSMutableArray *missing = [NSMutableArray array];
		NSSet *changed = [[context insertedObjects] setByAddingObjectsFromSet:[context updatedObjects]];
		for (NSManagedObject *object in changed) {
			if (![[[object entity] name] isEqualToString:entityName]) {
				continue;
			}
			for (NSString *element in [[required allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
				if ([[[object entity] propertiesByName] objectForKey:element] == nil) {
					continue;
				}
				id value = [object valueForKey:element];
				if (value == nil || ([value isKindOfClass:[NSString class]] && [value length] == 0)) {
					[missing addObject:[NSError errorWithDomain:NSCocoaErrorDomain code:NSManagedObjectValidationError userInfo:@{
						NSLocalizedDescriptionKey : [required objectForKey:element], NSValidationObjectErrorKey : object,
						NSValidationKeyErrorKey : element,
					}]];
				}
			}
		}
		if ([missing count] > 0) {
			if (error != NULL) {
				*error = [missing count] == 1 ? [missing firstObject]
					: [NSError errorWithDomain:NSCocoaErrorDomain code:NSValidationMultipleErrorsError
					                  userInfo:@{ NSDetailedErrorsKey : missing, NSLocalizedDescriptionKey : @"Several values are wanting." }];
			}
			return NO;
		}
		return [context save:error];
	}];
	if (![session open:error]) {
		return nil;
	}
	frame.document = document;
	frame.session = session;
	return frame;
}

/* A list's row as a reader knows it: the first value it shows other than
 * its anchor's key (a van's plate), else the key. */
- (NSString *)labelOf:(ORMFlowWalkFrame *)frame row:(NSUInteger)row
{
	ORMQuery *query = [_flow queryOf:frame.screen inModel:_model];
	NSDictionary *values = [frame.rowsByNode objectAtIndex:row];
	for (ORMQueryNode *node in [query nodes]) {
		NSString *value = node != query.root && node.identifier != nil ? [values objectForKey:node.identifier] : nil;
		if ([value length] > 0) {
			return value;
		}
	}
	NSString *key = row < [frame.rowKeys count] ? [frame.rowKeys objectAtIndex:row] : nil;
	return [key length] > 0 ? key : @"?";
}

/* A screen as the log says it: a list's rows, a form's given values. */
- (NSString *)said:(ORMFlowWalkFrame *)frame
{
	NSString *name = ORMFlowWalkName(frame.screen);
	if (frame.session == nil) {
		NSMutableArray *labels = [NSMutableArray array];
		for (NSUInteger i = 0; i < [frame.rows count]; i++) {
			[labels addObject:[self labelOf:frame row:i]];
		}
		return [NSString stringWithFormat:@"%@, %lu row%@%@%@", name, (unsigned long)[frame.rows count],
		                                  [frame.rows count] == 1 ? @"" : @"s", [labels count] > 0 ? @": " : @"",
		                                  [labels componentsJoinedByString:@" | "]];
	}
	NSMutableArray *given = [NSMutableArray array];
	for (NSString *element in [[frame.session.given allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		[given addObject:[NSString stringWithFormat:@"%@ = %@", element, [frame.session.given objectForKey:element]]];
	}
	return [given count] > 0 ? [NSString stringWithFormat:@"%@, given %@", name, [given componentsJoinedByString:@", "]] : name;
}

#pragma mark Going on

/* What the screen has now, by node id: a form's values, a list's row. */
- (NSMutableDictionary<NSString *, NSString *> *)knownOf:(ORMFlowWalkFrame *)frame row:(NSUInteger)row
{
	NSMutableDictionary *known = [NSMutableDictionary dictionary];
	if (frame.session != nil) {
		ORMQuery *query = [_flow queryOf:frame.screen inModel:_model];
		for (ORMQueryNode *node in [query nodes]) {
			NSString *element = [frame.document elementOfNode:node.identifier];
			NSString *value = element != nil ? [frame.session valueForElement:element] : nil;
			if (node.identifier != nil && value != nil) {
				[known setObject:value forKey:node.identifier];
			}
		}
	} else if (row < [frame.rowsByNode count]) {
		[known addEntriesFromDictionary:[frame.rowsByNode objectAtIndex:row]];
	}
	return known;
}

/* What the transition gives, by node id: the row's anchor, what the screen
 * saved, or what a screen had. */
- (NSDictionary<NSString *, NSString *> *)givenBy:(ORMFlowTransition *)transition row:(NSUInteger)row
{
	ORMFlowWalkFrame *frame = [self frame];
	NSMutableDictionary *given = [NSMutableDictionary dictionary];
	for (ORMFlowGive *give in transition.gives) {
		NSString *value = nil;
		if ([give.from isEqualToString:@"row"]) {
			value = row < [frame.rowKeys count] ? [frame.rowKeys objectAtIndex:row] : nil;
		} else if ([give.from isEqualToString:@"result"]) {
			value = frame.session.savedKey;
		} else {
			NSRange dot = [give.from rangeOfString:@"."];
			if (dot.location != NSNotFound) {
				value = [[_known objectForKey:[give.from substringToIndex:dot.location]] objectForKey:[give.from substringFromIndex:NSMaxRange(dot)]];
			}
		}
		if (give.nodeId != nil && value != nil) {
			[given setObject:value forKey:give.nodeId];
		}
	}
	return given;
}

- (BOOL)take:(ORMFlowTransition *)transition row:(NSUInteger)row error:(NSError **)error
{
	ORMFlowWalkFrame *frame = [self frame];
	if (frame == nil || ![transition.fromScreen isEqualToString:frame.screen.identifier]) {
		if (error != NULL) {
			*error = ORMFlowWalkError(@"That way is not from where the walk is.");
		}
		return NO;
	}
	BOOL rowChosen = [transition.on isEqualToString:ORMFlowOnRowChosen];
	if (rowChosen && row >= [frame.rows count]) {
		if (error != NULL) {
			*error = ORMFlowWalkError([NSString stringWithFormat:@"%@ has no row %lu to choose.", ORMFlowWalkName(frame.screen),
			                                                    (unsigned long)row + 1]);
		}
		return NO;
	}
	[_known setObject:[self knownOf:frame row:row] forKey:frame.screen.identifier ?: @""];
	NSDictionary *given = [self givenBy:transition row:row];
	NSString *how = transition.on ?: @"?";
	if (rowChosen) {
		how = [NSString stringWithFormat:@"%@ (%@)", how, [self labelOf:frame row:row]];
	} else if (transition.control != nil) {
		how = [NSString stringWithFormat:@"%@ %@", how, transition.control];
	}
	NSString *from = ORMFlowWalkName(frame.screen);
	if ([transition.kind isEqualToString:ORMFlowKindBack] || [transition.kind isEqualToString:ORMFlowKindClose]) {
		BOOL close = [transition.kind isEqualToString:ORMFlowKindClose];
		[_frames removeLastObject];
		ORMFlowWalkFrame *under = [self frame];
		NSMutableArray *returned = [NSMutableArray array];
		if (close && under.session != nil) {
			/* What the overlay made, set in the form it was over. */
			for (NSString *nodeId in given) {
				NSString *element = [under.document elementOfNode:nodeId];
				if (element != nil) {
					[under.session setValue:[given objectForKey:nodeId] forElement:element];
					[returned addObject:[NSString stringWithFormat:@"%@ = %@", element, [given objectForKey:nodeId]]];
				}
			}
		}
		[_log addObject:[NSString stringWithFormat:@"%@ —%@→ %@: %@%@", from, how, close ? @"closed" : @"back",
		                                           under != nil ? ORMFlowWalkName(under.screen) : @"out of the flow",
		                                           [returned count] > 0 ? [@", given " stringByAppendingString:[returned componentsJoinedByString:@", "]] : @""]];
		return YES;
	}
	ORMFlowScreen *to = [_flow screenWithId:transition.toScreen];
	ORMFlowWalkFrame *next = to != nil ? [self open:to given:given error:error] : nil;
	if (next == nil) {
		if (to == nil && error != NULL) {
			*error = ORMFlowWalkError([NSString stringWithFormat:@"%@ goes to %@, no screen of the flow.", from, transition.toScreen ?: @"nothing"]);
		}
		[_log addObject:[NSString stringWithFormat:@"%@ —%@→ %@ cannot open: %@", from, how, to != nil ? ORMFlowWalkName(to) : @"?",
		                                           error != NULL ? (*error).localizedDescription : @"?"]];
		return NO;
	}
	/* On top of this one: Back, or an overlay's Close, comes back to it. */
	next.overlay = [transition.kind isEqualToString:ORMFlowKindOverlay];
	[_frames addObject:next];
	[_log addObject:[NSString stringWithFormat:@"%@ —%@→ %@%@", from, how, next.overlay ? @"over it: " : @"", [self said:next]]];
	return YES;
}

/* The ways on from the form on the save's outcome. */
- (ORMFlowTransition *)wayOnSaving:(BOOL)saved
{
	NSString *on = saved ? ORMFlowOnSubmitDone : ORMFlowOnSubmitError;
	for (ORMFlowTransition *transition in [self transitions]) {
		if ([transition.on isEqualToString:on]) {
			return transition;
		}
	}
	return nil;
}

- (BOOL)submit:(NSError **)error
{
	return [self submitTaking:nil error:error];
}

/* Submitted, and the way on its outcome taken where allowed says so (nil:
 * any). */
- (BOOL)submitTaking:(BOOL (^)(ORMFlowTransition *))allowed error:(NSError **)error
{
	ORMFlowWalkFrame *frame = [self frame];
	if (frame.session == nil) {
		if (error != NULL) {
			*error = ORMFlowWalkError([NSString stringWithFormat:@"%@ is a list: nothing is submitted.", ORMFlowWalkName(frame.screen)]);
		}
		return NO;
	}
	frame.submitted = YES;
	NSError *failed = nil;
	BOOL saved = [frame.session save:&failed];
	NSString *name = ORMFlowWalkName(frame.screen);
	if (saved) {
		[_log addObject:[NSString stringWithFormat:@"%@ saved: %@", name, frame.session.savedKey ?: @"?"]];
	} else if ([frame.session.errors count] > 0) {
		NSMutableArray *said = [NSMutableArray array];
		for (NSString *element in [[frame.session.errors allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
			[said addObject:[NSString stringWithFormat:@"%@: %@", [element length] > 0 ? element : @"the form",
			                                           [frame.session.errors objectForKey:element]]];
		}
		[_log addObject:[NSString stringWithFormat:@"%@ refused: %@", name, [said componentsJoinedByString:@"; "]]];
	} else {
		[_log addObject:[NSString stringWithFormat:@"%@ cannot be saved: %@", name, failed.localizedDescription ?: @"?"]];
		if (error != NULL) {
			*error = failed;
		}
		return NO;
	}
	ORMFlowTransition *way = [self wayOnSaving:saved];
	if (way != nil && (allowed == nil || allowed(way))) {
		[self take:way row:0 error:NULL];
	}
	return saved;
}

#pragma mark On its own

- (NSString *)walkFrom:(NSString *)entryName error:(NSError **)error
{
	if (![self beginAt:entryName error:error]) {
		return nil;
	}
	NSMutableSet *taken = [NSMutableSet set];
	BOOL (^untaken)(ORMFlowTransition *) = ^BOOL(ORMFlowTransition *way) {
		return ![taken containsObject:[NSValue valueWithNonretainedObject:way]];
	};
	for (NSUInteger steps = 0; steps < 100 && [self frame] != nil; steps++) {
		ORMFlowWalkFrame *frame = [self frame];
		if (frame.session != nil && !frame.submitted) {
			[self chooseFirstChoicesIn:frame.session];
			[self submitTaking:^BOOL(ORMFlowTransition *way) {
				if (!untaken(way)) {
					return NO;
				}
				[taken addObject:[NSValue valueWithNonretainedObject:way]];
				return YES;
			} error:NULL];
			continue;
		}
		/* Deeper first: a row chosen or a trigger before Cancel. */
		ORMFlowTransition *next = nil;
		for (ORMFlowTransition *way in [self transitions]) {
			if (![way.on hasPrefix:@"Submit"] && untaken(way) && (next == nil || [next.on isEqualToString:ORMFlowOnCancel])) {
				next = way;
			}
		}
		if (next == nil) {
			break;
		}
		[taken addObject:[NSValue valueWithNonretainedObject:next]];
		if (![self take:next row:0 error:NULL] && [next.on isEqualToString:ORMFlowOnRowChosen]) {
			[_log addObject:[NSString stringWithFormat:@"%@ has no row to choose.", ORMFlowWalkName(frame.screen)]];
		}
	}
	return [[_log componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
}

/* Each reference left empty given its first choice, as a user picks one. */
- (void)chooseFirstChoicesIn:(ORMFormSession *)session
{
	for (NSString *name in [session.form choiceNames]) {
		if ([[session valueForElement:name] length] > 0 || [session.given objectForKey:name] != nil) {
			continue;
		}
		NSArray *choices = [session choicesNamed:name error:NULL];
		if ([choices count] > 0) {
			[session setValue:[choices firstObject] forElement:name];
		}
	}
}

@end
