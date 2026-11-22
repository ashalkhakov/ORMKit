/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlowSession.h"
#import "ORMForm.h"

static NSError *
ORMFlowSessionError(NSString *text)
{
	return [NSError errorWithDomain:ORMFormErrorDomain code:2 userInfo:@{ NSLocalizedDescriptionKey : text }];
}

static NSString *
ORMFlowText(id value)
{
	if (value == nil || value == [NSNull null]) {
		return nil;
	}
	return [value isKindOfClass:[NSString class]] ? value : [value description];
}

@interface ORMFlowStep ()
@property (nonatomic, copy) NSString *screen;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *formName;
@property (nonatomic, copy) NSString *listName;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *given;
@property (nonatomic, copy) NSString *key;
@property (nonatomic) BOOL overlay;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *returned;
@end

@implementation ORMFlowStep
@end

@interface ORMFlowWay ()
@property (nonatomic, copy) NSString *from;
@property (nonatomic, copy) NSString *on;
@property (nonatomic, copy) NSString *control;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, copy) NSString *to;
/* Each {element, from, anchor}. */
@property (nonatomic, copy) NSArray<NSDictionary *> *gives;
@end

@implementation ORMFlowWay
@end

@implementation ORMFlowSession {
	NSDictionary<NSString *, NSDictionary *> *_screens;
	NSArray<NSDictionary *> *_entries;
	NSArray<ORMFlowWay *> *_ways;
	NSMutableArray<ORMFlowStep *> *_steps;
	/* What each screen had, by element, when it was left. */
	NSMutableDictionary<NSString *, NSDictionary *> *_known;
}

+ (instancetype)flowNamed:(NSString *)name error:(NSError **)error
{
	NSMutableArray *bundles = [NSMutableArray arrayWithObject:[NSBundle mainBundle]];
	[bundles addObjectsFromArray:[NSBundle allFrameworks]];
	[bundles addObjectsFromArray:[NSBundle allBundles]];
	NSString *path = nil;
	for (NSBundle *bundle in bundles) {
		path = path ?: [bundle pathForResource:name ofType:@"ormflow"];
	}
	NSData *data = path != nil ? [NSData dataWithContentsOfFile:path] : nil;
	if (data == nil) {
		if (error != NULL) {
			*error = ORMFlowSessionError([NSString stringWithFormat:@"No bundle has %@.ormflow.", name]);
		}
		return nil;
	}
	id list = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:error];
	return list != nil ? [[self alloc] initWithPropertyList:list error:error] : nil;
}

- (instancetype)initWithPropertyList:(id)list error:(NSError **)error
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	NSDictionary *screens = [list isKindOfClass:[NSDictionary class]] ? [list objectForKey:@"screens"] : nil;
	NSArray *entries = [list isKindOfClass:[NSDictionary class]] ? [list objectForKey:@"entries"] : nil;
	NSArray *transitions = [list isKindOfClass:[NSDictionary class]] ? [list objectForKey:@"transitions"] : nil;
	if (![[list objectForKey:@"format"] isEqual:@1] || ![screens isKindOfClass:[NSDictionary class]] || ![entries isKindOfClass:[NSArray class]]
	    || ![transitions isKindOfClass:[NSArray class]]) {
		if (error != NULL) {
			*error = ORMFlowSessionError(@"Not a flow's contract (format 1: entries, screens, transitions), as ormtool xforms --flow writes it.");
		}
		return nil;
	}
	_name = [[list objectForKey:@"flow"] copy];
	_screens = [screens copy];
	_entries = [entries copy];
	NSMutableArray *ways = [NSMutableArray array];
	for (NSDictionary *each in transitions) {
		if (![each isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		ORMFlowWay *way = [[ORMFlowWay alloc] init];
		way.from = [each objectForKey:@"from"];
		way.on = [each objectForKey:@"on"];
		way.control = [each objectForKey:@"control"];
		way.kind = [each objectForKey:@"kind"] ?: @"Navigate";
		way.to = [each objectForKey:@"to"];
		way.gives = [[each objectForKey:@"gives"] isKindOfClass:[NSArray class]] ? [each objectForKey:@"gives"] : @[];
		if (way.to != nil && [_screens objectForKey:way.to] == nil) {
			if (error != NULL) {
				*error = ORMFlowSessionError([NSString stringWithFormat:@"A way from %@ goes to %@, no screen of the flow.", way.from, way.to]);
			}
			return nil;
		}
		[ways addObject:way];
	}
	_ways = ways;
	_steps = [NSMutableArray array];
	_known = [NSMutableDictionary dictionary];
	return self;
}

- (NSArray<NSString *> *)entryNames
{
	NSMutableArray *names = [NSMutableArray array];
	for (NSDictionary *entry in _entries) {
		[names addObject:[entry objectForKey:@"name"] ?: @""];
	}
	return names;
}

- (ORMFlowStep *)stepOfScreen:(NSString *)screen given:(NSDictionary *)given key:(NSString *)key
{
	NSDictionary *said = [_screens objectForKey:screen];
	ORMFlowStep *step = [[ORMFlowStep alloc] init];
	step.screen = screen;
	step.name = [said objectForKey:@"name"] ?: screen;
	step.formName = [said objectForKey:@"form"];
	step.listName = [said objectForKey:@"list"];
	step.given = given ?: @{};
	step.key = key;
	step.returned = @{};
	return step;
}

- (ORMFlowStep *)beginAt:(NSString *)entryName key:(NSString *)key error:(NSError **)error
{
	return [self beginAt:entryName key:key given:nil error:error];
}

- (ORMFlowStep *)beginAt:(NSString *)entryName key:(NSString *)key given:(NSDictionary<NSString *, NSString *> *)given
                   error:(NSError **)error
{
	NSDictionary *entry = nil;
	for (NSDictionary *each in _entries) {
		if (entryName == nil || [[each objectForKey:@"name"] isEqual:entryName]) {
			entry = each;
			break;
		}
	}
	NSString *screen = [entry objectForKey:@"screen"];
	if (screen == nil || [_screens objectForKey:screen] == nil) {
		if (error != NULL) {
			*error = ORMFlowSessionError(entry == nil ? [NSString stringWithFormat:@"The flow %@ has no entry %@.", _name ?: @"?", entryName ?: @"at all"]
			                                          : [NSString stringWithFormat:@"The entry %@ is to no screen of the flow.", entryName]);
		}
		return nil;
	}
	[_steps removeAllObjects];
	[_known removeAllObjects];
	ORMFlowStep *step = [self stepOfScreen:screen given:given key:key];
	[_steps addObject:step];
	return step;
}

- (ORMFlowStep *)step
{
	return [_steps lastObject];
}

- (NSArray<ORMFlowStep *> *)steps
{
	return [_steps copy];
}

- (BOOL)hasEnded
{
	return [_steps count] == 0;
}

- (NSArray<ORMFlowWay *> *)ways
{
	NSString *screen = [self step].screen;
	NSMutableArray *found = [NSMutableArray array];
	for (ORMFlowWay *way in _ways) {
		if (screen != nil && [way.from isEqualToString:screen]) {
			[found addObject:way];
		}
	}
	return found;
}

- (ORMFlowWay *)wayOn:(NSString *)on control:(NSString *)control
{
	for (ORMFlowWay *way in [self ways]) {
		if ([way.on isEqualToString:on] && (control == nil || [way.control isEqualToString:control])) {
			return way;
		}
	}
	return nil;
}

- (ORMFlowStep *)take:(ORMFlowWay *)way row:(NSString *)rowKey result:(NSString *)result values:(NSDictionary<NSString *, id> *)values
{
	ORMFlowStep *from = [self step];
	if (from == nil || ![way.from isEqualToString:from.screen]) {
		return from;
	}
	NSMutableDictionary *had = [NSMutableDictionary dictionary];
	for (NSString *element in values) {
		NSString *text = ORMFlowText([values objectForKey:element]);
		if (text != nil) {
			[had setObject:text forKey:element];
		}
	}
	if (result != nil) {
		[had setObject:result forKey:@""];
	}
	[_known setObject:had forKey:from.screen];
	/* What it gives: by element of the form it gives to, the anchor apart. */
	NSMutableDictionary *given = [NSMutableDictionary dictionary];
	NSString *anchor = nil;
	for (NSDictionary *give in way.gives) {
		NSString *source = [give objectForKey:@"from"];
		NSString *value = nil;
		if ([source isEqualToString:@"row"]) {
			value = rowKey;
		} else if ([source isEqualToString:@"result"]) {
			value = result;
		} else {
			NSRange dot = [source rangeOfString:@"."];
			if (dot.location != NSNotFound) {
				value = [[_known objectForKey:[source substringToIndex:dot.location]] objectForKey:[source substringFromIndex:NSMaxRange(dot)]];
			}
		}
		if (value == nil) {
			continue;
		}
		if ([[give objectForKey:@"anchor"] boolValue]) {
			anchor = value;
		} else if ([give objectForKey:@"element"] != nil) {
			[given setObject:value forKey:[give objectForKey:@"element"]];
		}
	}
	if ([way.kind isEqualToString:@"Back"] || [way.kind isEqualToString:@"Close"]) {
		[_steps removeLastObject];
		ORMFlowStep *under = [self step];
		if (under != nil) {
			/* Come back to: what a Close gives returned, nothing else. */
			ORMFlowStep *back = [self stepOfScreen:under.screen given:under.given key:under.key];
			back.overlay = under.overlay;
			back.returned = [way.kind isEqualToString:@"Close"] ? given : @{};
			[_steps replaceObjectAtIndex:[_steps count] - 1 withObject:back];
		}
		return [self step];
	}
	ORMFlowStep *next = [self stepOfScreen:way.to given:given key:anchor];
	next.overlay = [way.kind isEqualToString:@"Overlay"];
	[_steps addObject:next];
	return next;
}

@end
