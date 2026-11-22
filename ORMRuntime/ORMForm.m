/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMForm.h"
#import "ORMQueryInterpreter.h"
#import "ORMQueryOData.h"
#import <CoreData/CoreData.h>
#import <ODataKit/ODataPropertyMapper.h>
#import <ODataKit/ODataValue.h>

const NSUInteger ORMFormFormat = 1;
NSString * const ORMFormErrorDomain = @"ORMFormErrorDomain";

static NSError *
ORMFormError(NSString *text)
{
	return [NSError errorWithDomain:ORMFormErrorDomain code:1 userInfo:@{ NSLocalizedDescriptionKey: text }];
}

@interface ORMFormElement ()
@property (nonatomic, readwrite, copy) NSString *name;
@property (nonatomic, readwrite, copy) NSString *kind;
@property (nonatomic, readwrite, copy) NSString *schemaType;
@property (nonatomic, readwrite) NSUInteger column;
@property (nonatomic, readwrite) NSUInteger part;
@property (nonatomic, readwrite, copy) NSString *entityName;
@property (nonatomic, readwrite, copy) NSString *keyName;
@property (nonatomic, readwrite) BOOL written;
@property (nonatomic, readwrite) BOOL many;
@property (nonatomic, readwrite, copy) NSString *role;
@property (nonatomic, readwrite) BOOL given;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *items;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *itemLabels;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *path;
@property (nonatomic, readwrite, copy) NSString *group;
@property (nonatomic, readwrite, copy) NSString *subtype;
@property (nonatomic, readwrite, copy) NSString *identifies;
@property (nonatomic, readwrite, copy) NSDictionary *aggregate;
@property (nonatomic, readwrite, strong) ORMQueryPlan *read;
@property (nonatomic, readwrite) NSUInteger readColumn;
@property (nonatomic, readwrite, copy) NSString *label;
@end

@implementation ORMFormElement

- (NSString *)labelOfItem:(NSString *)item
{
	NSUInteger index = item != nil ? [self.items indexOfObject:item] : NSNotFound;
	return index != NSNotFound && index < [self.itemLabels count] ? [self.itemLabels objectAtIndex:index] : item;
}

@end

@interface ORMFormRequest ()
@property (nonatomic, readwrite, copy) NSString *method;
@property (nonatomic, readwrite, copy) NSString *path;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, NSString *> *headers;
@property (nonatomic, readwrite, copy) NSDictionary<NSString *, id> *body;
@end

@implementation ORMFormRequest

- (NSData *)bodyData
{
	return [NSJSONSerialization dataWithJSONObject:self.body ?: @{} options:0 error:NULL];
}

@end

#pragma mark Values as XForms has them

/* xsd's lexical forms of a date, in UTC. */
static NSDateFormatter *
ORMFormDateFormatter(NSString *format)
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
	[formatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	[formatter setDateFormat:format];
	return formatter;
}

/* A value as the instance holds it: an object by its key's value, a date
 * as xsd's dateTime (date), a flag "true" or "false", a number as written;
 * "" for none. */
static NSString *
ORMFormText(id value, NSString *schemaType, NSString *keyName)
{
	if (value == nil || value == [NSNull null]) {
		return @"";
	}
	if ([value isKindOfClass:[NSManagedObject class]]) {
		return keyName != nil ? ORMFormText([value valueForKey:keyName], nil, nil) : @"";
	}
	if ([value isKindOfClass:[NSArray class]]) {
		return ORMFormText([value firstObject], schemaType, keyName);
	}
	if ([value isKindOfClass:[NSDate class]]) {
		return [ORMFormDateFormatter([schemaType isEqualToString:@"xsd:date"] ? @"yyyy-MM-dd" : @"yyyy-MM-dd'T'HH:mm:ss'Z'")
		           stringFromDate:value];
	}
	if ([value isKindOfClass:[NSNumber class]] && [schemaType isEqualToString:@"xsd:boolean"]) {
		return [value boolValue] ? @"true" : @"false";
	}
	if ([value isKindOfClass:[NSNumber class]]) {
		return [value stringValue];
	}
	if ([value isKindOfClass:[NSUUID class]]) {
		return [value UUIDString];
	}
	return [value isKindOfClass:[NSString class]] ? value : [value description];
}

/* The instance's text as the attribute's value: nil for "", and why not
 * where it is no value of the attribute's type. */
static id
ORMFormValue(NSString *text, NSAttributeDescription *attribute, NSString **problem)
{
	if ([text length] == 0) {
		return nil;
	}
	NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSScanner *scanner = [NSScanner scannerWithString:trimmed];
	switch ([attribute attributeType]) {
	case NSInteger16AttributeType:
	case NSInteger32AttributeType:
	case NSInteger64AttributeType: {
		long long number = 0;
		if ([scanner scanLongLong:&number] && [scanner isAtEnd]) {
			return [NSNumber numberWithLongLong:number];
		}
		*problem = @"Not a whole number.";
		return nil;
	}
	case NSDecimalAttributeType: {
		NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:trimmed
		                                                            locale:@{ NSLocaleDecimalSeparator: @"." }];
		if ([number isEqualToNumber:[NSDecimalNumber notANumber]]) {
			*problem = @"Not a number.";
			return nil;
		}
		return number;
	}
	case NSDoubleAttributeType:
	case NSFloatAttributeType: {
		double number = 0;
		if ([scanner scanDouble:&number] && [scanner isAtEnd]) {
			return [NSNumber numberWithDouble:number];
		}
		*problem = @"Not a number.";
		return nil;
	}
	case NSBooleanAttributeType:
		if ([trimmed isEqualToString:@"true"] || [trimmed isEqualToString:@"1"]) {
			return [NSNumber numberWithBool:YES];
		}
		if ([trimmed isEqualToString:@"false"] || [trimmed isEqualToString:@"0"]) {
			return [NSNumber numberWithBool:NO];
		}
		*problem = @"Neither true nor false.";
		return nil;
	case NSUUIDAttributeType: {
		NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:trimmed];
		if (uuid == nil) {
			*problem = @"Not a UUID.";
		}
		return uuid;
	}
	case NSDateAttributeType:
		for (NSString *format in @[ @"yyyy-MM-dd'T'HH:mm:ssXXXXX", @"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", @"yyyy-MM-dd'T'HH:mm:ss",
		                            @"yyyy-MM-dd'T'HH:mm", @"yyyy-MM-dd" ]) {
			NSDate *date = [ORMFormDateFormatter(format) dateFromString:trimmed];
			if (date != nil) {
				return date;
			}
		}
		*problem = @"Not a date.";
		return nil;
	default:
		return text;
	}
}

static NSManagedObject *ORMFormFind(NSEntityDescription *entity, NSString *key, id value, NSManagedObjectContext *context);

/* A set of choices' keys as its element holds them: in order, space
 * separated; and its text as the keys, none for "". */
static NSString *
ORMFormKeysText(NSArray<NSString *> *keys)
{
	return [[keys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@" "];
}

static NSArray<NSString *> *
ORMFormKeysOf(NSString *text)
{
	NSMutableArray *keys = [NSMutableArray array];
	for (NSString *each in [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
		if ([each length] > 0 && ![keys containsObject:each]) {
			[keys addObject:each];
		}
	}
	return [keys sortedArrayUsingSelector:@selector(compare:)];
}

/* What an error says of a property, for the user (below). */
static NSString *ORMFormMessage(NSError *error);

/* What a form wrote into a context: its object, made or not, and what it
 * had; the objects it owns; its rows'; and what was wrong of its values,
 * by element. */
@interface ORMFormWriting : NSObject
@property (nonatomic, strong) ORMForm *form;
@property (nonatomic, strong) NSManagedObject *object;
@property (nonatomic) BOOL made;
@property (nonatomic, strong) NSMutableDictionary *before;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *owned;
@property (nonatomic, strong) NSMutableArray *rowObjects;
@property (nonatomic, strong) NSMutableArray *rowBefores;
@property (nonatomic, strong) NSMutableArray *rowMade;
@property (nonatomic, strong) NSMutableDictionary<NSValue *, NSString *> *rowPrefixes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *problems;
@end

@implementation ORMFormWriting
@end

#pragma mark The table

@implementation ORMForm
{
	NSDictionary *_list;
	NSDictionary<NSString *, ORMQueryPlan *> *_allChoices;
	NSDictionary<NSString *, ORMQueryPlan *> *_choicesBy;
	NSDictionary<NSString *, NSArray<NSString *> *> *_dependsOn;
	NSDictionary<NSString *, ORMForm *> *_repeats;
	NSDictionary<NSString *, ORMQueryPlan *> *_identify;
	/* A repeat's: the element its rows' key is in, and the owned object's
	 * group they are written into; nil for the anchor's. */
	NSString *_from;
	NSString *_fromGroup;
	/* A repeat's in a subtype part: written where the object is one. */
	NSString *_subtype;
	NSDictionary<NSString *, NSArray<NSString *> *> *_identifiedBy;
}

+ (instancetype)formWithPropertyList:(id)list error:(NSError **)error
{
	NSError *failure = nil;
	ORMForm *form = [[self alloc] init];
	if (![form read:list error:&failure]) {
		if (error != NULL) {
			*error = failure;
		}
		return nil;
	}
	return form;
}

- (BOOL)read:(id)list error:(NSError **)error
{
	if (![list isKindOfClass:[NSDictionary class]] || ![[list objectForKey:@"entity"] isKindOfClass:[NSString class]]
	    || ![[list objectForKey:@"elements"] isKindOfClass:[NSArray class]]) {
		*error = ORMFormError(@"Not a form's table: it names its entity and its elements.");
		return NO;
	}
	if ([[list objectForKey:@"format"] unsignedIntegerValue] > ORMFormFormat) {
		*error = ORMFormError(@"The form's table is of a later format.");
		return NO;
	}
	_list = [list copy];
	_name = [[list objectForKey:@"form"] copy];
	_entityName = [[list objectForKey:@"entity"] copy];
	_keyElement = [[list objectForKey:@"key"] copy];
	NSMutableArray *elements = [NSMutableArray array];
	for (NSDictionary *item in [list objectForKey:@"elements"]) {
		if (![item isKindOfClass:[NSDictionary class]] || ![[item objectForKey:@"name"] isKindOfClass:[NSString class]]) {
			*error = ORMFormError(@"An element has a name.");
			return NO;
		}
		ORMFormElement *element = [[ORMFormElement alloc] init];
		element.name = [item objectForKey:@"name"];
		element.kind = [item objectForKey:@"kind"] ?: @"value";
		element.schemaType = [item objectForKey:@"type"] ?: @"xsd:string";
		element.column = [item objectForKey:@"column"] != nil ? [[item objectForKey:@"column"] unsignedIntegerValue] : NSNotFound;
		element.part = [item objectForKey:@"part"] != nil ? [[item objectForKey:@"part"] unsignedIntegerValue] : NSNotFound;
		element.entityName = [item objectForKey:@"entity"];
		element.keyName = [item objectForKey:@"key"];
		element.written = [[item objectForKey:@"written"] boolValue];
		element.many = [[item objectForKey:@"many"] boolValue];
		element.given = [[item objectForKey:@"given"] boolValue];
		element.label = [item objectForKey:@"label"] ?: element.name;
		element.items = [[item objectForKey:@"items"] isKindOfClass:[NSArray class]] ? [item objectForKey:@"items"] : nil;
		NSArray *labels = [item objectForKey:@"itemLabels"];
		element.itemLabels = [labels isKindOfClass:[NSArray class]] && [labels count] == [element.items count] ? labels : nil;
		element.path = [[item objectForKey:@"path"] isKindOfClass:[NSArray class]] ? [item objectForKey:@"path"] : nil;
		element.group = [[item objectForKey:@"group"] isKindOfClass:[NSString class]] ? [item objectForKey:@"group"] : nil;
		element.subtype = [[item objectForKey:@"subtype"] isKindOfClass:[NSString class]] ? [item objectForKey:@"subtype"] : nil;
		element.identifies = [[item objectForKey:@"identifies"] isKindOfClass:[NSString class]] ? [item objectForKey:@"identifies"] : nil;
		element.aggregate = [[item objectForKey:@"aggregate"] isKindOfClass:[NSDictionary class]] ? [item objectForKey:@"aggregate"] : nil;
		if ([[item objectForKey:@"read"] isKindOfClass:[NSDictionary class]]) {
			element.read = [ORMQueryPlan planWithPropertyList:[item objectForKey:@"read"] error:error];
			if (element.read == nil) {
				return NO;
			}
			element.readColumn = [[item objectForKey:@"readColumn"] unsignedIntegerValue];
		}
		/* A table from before roles: what it writes entered, the rest shown. */
		element.role = [item objectForKey:@"role"]
		    ?: ([element.name isEqualToString:_keyElement ?: @""] ? @"key"
		        : [element.kind isEqualToString:@"calculated"] ? @"calculated"
		        : element.written ? @"entered" : @"shown");
		[elements addObject:element];
	}
	_elements = elements;
	if ([list objectForKey:@"read"] != nil) {
		_readPlan = [ORMQueryPlan planWithPropertyList:[list objectForKey:@"read"] error:error];
		if (_readPlan == nil) {
			return NO;
		}
	}
	NSMutableDictionary *all = [NSMutableDictionary dictionary], *by = [NSMutableDictionary dictionary];
	NSMutableDictionary *dependsOn = [NSMutableDictionary dictionary];
	NSMutableDictionary *identify = [NSMutableDictionary dictionary], *identifiedBy = [NSMutableDictionary dictionary];
	NSDictionary *choices = [list objectForKey:@"choices"] ?: @{};
	for (NSString *name in choices) {
		NSDictionary *choice = [choices objectForKey:name];
		/* Found by values entered: no choices. */
		if ([choice objectForKey:@"identify"] != nil) {
			ORMQueryPlan *plan = [ORMQueryPlan planWithPropertyList:[choice objectForKey:@"identify"] error:error];
			if (plan == nil) {
				return NO;
			}
			[identify setObject:plan forKey:name];
			[identifiedBy setObject:[choice objectForKey:@"identifiedBy"] ?: @[] forKey:name];
			continue;
		}
		ORMQueryPlan *plan = [ORMQueryPlan planWithPropertyList:[choice objectForKey:@"all"] error:error];
		if (plan == nil) {
			return NO;
		}
		[all setObject:plan forKey:name];
		if ([choice objectForKey:@"plan"] != nil) {
			plan = [ORMQueryPlan planWithPropertyList:[choice objectForKey:@"plan"] error:error];
			if (plan == nil) {
				return NO;
			}
			[by setObject:plan forKey:name];
			[dependsOn setObject:[choice objectForKey:@"dependsOn"] ?: @[] forKey:name];
		}
	}
	_allChoices = all;
	_choicesBy = by;
	_identify = identify;
	_identifiedBy = identifiedBy;
	_dependsOn = dependsOn;
	_checkedWhereSubmitted = [[list objectForKey:@"checkedWhereSubmitted"] copy] ?: @[];
	_action = [[list objectForKey:@"action"] isKindOfClass:[NSString class]] ? [[list objectForKey:@"action"] copy] : nil;
	_messages = [[list objectForKey:@"messages"] isKindOfClass:[NSDictionary class]] ? [[list objectForKey:@"messages"] copy] : nil;
	NSMutableArray *parts = [NSMutableArray array];
	for (id table in [[list objectForKey:@"with"] isKindOfClass:[NSArray class]] ? [list objectForKey:@"with"] : @[]) {
		ORMForm *part = [[ORMForm alloc] init];
		if (![part read:table error:error]) {
			return NO;
		}
		[parts addObject:part];
	}
	_parts = parts;
	_linkElement = [[list objectForKey:@"link"] copy];
	_isList = [[list objectForKey:@"list"] boolValue];
	_from = [[list objectForKey:@"from"] isKindOfClass:[NSString class]] ? [[list objectForKey:@"from"] copy] : nil;
	_fromGroup = [[list objectForKey:@"fromGroup"] isKindOfClass:[NSString class]] ? [[list objectForKey:@"fromGroup"] copy] : nil;
	_subtype = [[list objectForKey:@"subtype"] isKindOfClass:[NSString class]] ? [[list objectForKey:@"subtype"] copy] : nil;
	NSMutableDictionary *repeats = [NSMutableDictionary dictionary];
	NSDictionary *tables = [list objectForKey:@"repeats"] ?: @{};
	for (NSString *name in tables) {
		ORMForm *repeat = [[ORMForm alloc] init];
		if (![repeat read:[tables objectForKey:name] error:error]) {
			return NO;
		}
		if (repeat.linkElement == nil) {
			*error = ORMFormError([NSString stringWithFormat:@"The repeat %@ names no link to the form.", name]);
			return NO;
		}
		[repeats setObject:repeat forKey:name];
	}
	_repeats = repeats;
	return YES;
}

- (NSArray<NSString *> *)repeatNames
{
	return [[_repeats allKeys] sortedArrayUsingSelector:@selector(compare:)];
}

- (ORMForm *)repeatNamed:(NSString *)name
{
	return [_repeats objectForKey:name];
}

- (NSString *)repeatFrom:(NSString *)name
{
	ORMForm *repeat = [_repeats objectForKey:name];
	return repeat != nil ? repeat->_from : nil;
}

- (id)propertyList
{
	return _list;
}

static NSMutableDictionary<NSString *, ORMForm *> *
ORMRegisteredForms(void)
{
	static NSMutableDictionary *forms;
	if (forms == nil) {
		forms = [NSMutableDictionary dictionary];
	}
	return forms;
}

+ (void)registerForm:(ORMForm *)form named:(NSString *)name
{
	@synchronized(self) {
		if (form != nil) {
			[ORMRegisteredForms() setObject:form forKey:name];
		} else {
			[ORMRegisteredForms() removeObjectForKey:name];
		}
	}
}

+ (instancetype)formNamed:(NSString *)name error:(NSError **)error
{
	@synchronized(self) {
		ORMForm *form = [ORMRegisteredForms() objectForKey:name];
		if (form != nil) {
			return form;
		}
		NSMutableArray *bundles = [NSMutableArray arrayWithObject:[NSBundle mainBundle]];
		[bundles addObjectsFromArray:[NSBundle allFrameworks]];
		[bundles addObjectsFromArray:[NSBundle allBundles]];
		NSString *path = nil;
		for (NSBundle *bundle in bundles) {
			path = path ?: [bundle pathForResource:name ofType:@"ormform"];
		}
		NSData *data = path != nil ? [NSData dataWithContentsOfFile:path] : nil;
		if (data == nil) {
			if (error != NULL) {
				*error = ORMFormError([NSString stringWithFormat:@"No bundle has %@.ormform.", name]);
			}
			return nil;
		}
		id list = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:error];
		form = list != nil ? [self formWithPropertyList:list error:error] : nil;
		if (form != nil) {
			[ORMRegisteredForms() setObject:form forKey:name];
		}
		return form;
	}
}

- (ORMFormElement *)elementNamed:(NSString *)name
{
	for (ORMFormElement *element in _elements) {
		if ([element.name isEqualToString:name]) {
			return element;
		}
	}
	return nil;
}

- (NSArray<NSString *> *)inputNames
{
	NSMutableArray *names = [NSMutableArray array];
	for (ORMFormElement *element in _elements) {
		if (element.given) {
			[names addObject:element.name];
		}
	}
	return names;
}

- (NSArray<NSString *> *)choiceNames
{
	NSMutableArray *names = [NSMutableArray array];
	for (ORMFormElement *element in _elements) {
		if ([_allChoices objectForKey:element.name] != nil) {
			[names addObject:element.name];
		}
	}
	return names;
}

- (NSArray<NSString *> *)elementsChoicesDependOn:(NSString *)name
{
	return [_dependsOn objectForKey:name] ?: @[];
}

- (ORMQueryPlan *)choicesPlanNamed:(NSString *)name values:(NSDictionary<NSString *, id> *)values error:(NSError **)error
{
	ORMQueryPlan *all = [_allChoices objectForKey:name];
	if (all == nil) {
		if (error != NULL) {
			*error = ORMFormError([NSString stringWithFormat:@"%@ has no choices.", name]);
		}
		return nil;
	}
	ORMQueryPlan *by = [_choicesBy objectForKey:name];
	for (NSString *needed in [self elementsChoicesDependOn:name]) {
		by = [[values objectForKey:needed] length] > 0 ? by : nil;
	}
	return by != nil ? [by planBinding:values error:error] : all;
}

- (NSArray<NSString *> *)identifiedNames
{
	NSMutableArray *names = [NSMutableArray array];
	for (ORMFormElement *element in _elements) {
		if ([_identify objectForKey:element.name] != nil) {
			[names addObject:element.name];
		}
	}
	return names;
}

- (NSArray<NSString *> *)elementsIdentifying:(NSString *)name
{
	return [_identifiedBy objectForKey:name] ?: @[];
}

- (ORMQueryPlan *)identifyPlanNamed:(NSString *)name values:(NSDictionary<NSString *, id> *)values error:(NSError **)error
{
	ORMQueryPlan *plan = [_identify objectForKey:name];
	if (plan == nil) {
		if (error != NULL) {
			*error = ORMFormError([NSString stringWithFormat:@"%@ is not found by values entered.", name]);
		}
		return nil;
	}
	return [plan planBinding:values error:error];
}

/* Whether nothing that finds the reference is entered. */
- (BOOL)noneIdentifying:(NSString *)name in:(NSDictionary<NSString *, id> *)values
{
	for (NSString *each in [self elementsIdentifying:name]) {
		if ([[[values objectForKey:each] description] length] > 0) {
			return NO;
		}
	}
	return YES;
}

- (NSString *)unfoundMessageNamed:(NSString *)name
{
	ORMFormElement *reference = [self elementNamed:name];
	NSMutableArray *labels = [NSMutableArray array];
	for (NSString *each in [self elementsIdentifying:name]) {
		[labels addObject:[self elementNamed:each].label ?: each];
	}
	return [NSString stringWithFormat:@"There is no %@ with that %@.", reference.entityName ?: name,
	                                  [labels componentsJoinedByString:@" and "]];
}

#pragma mark The instance

- (NSDictionary<NSString *, id> *)instanceGiven:(NSDictionary<NSString *, id> *)values
{
	NSMutableDictionary *instance = [NSMutableDictionary dictionary];
	for (ORMFormElement *element in _elements) {
		/* A flag entered and not yet set is not so: "filled the tank"
		 * unticked is false, not missing. */
		NSString *none = [element.role isEqualToString:@"entered"] && [element.schemaType hasSuffix:@"boolean"] ? @"false" : @"";
		[instance setObject:[values objectForKey:element.name] ?: none forKey:element.name];
	}
	for (NSString *name in _repeats) {
		[instance setObject:@[] forKey:name];
	}
	return [self instanceWithAggregates:instance];
}

- (NSDictionary<NSString *, id> *)instance:(NSDictionary<NSString *, id> *)instance withOwnReads:(NSDictionary<NSString *, NSArray *> *)rows
{
	NSMutableDictionary *read = [instance mutableCopy];
	for (ORMFormElement *element in _elements) {
		NSArray *row = [[rows objectForKey:element.name] firstObject];
		if (element.read == nil) {
			continue;
		}
		if (element.many) {
			/* A set of choices: each row's object picked, by its key. */
			NSMutableArray *keys = [NSMutableArray array];
			for (NSArray *each in [rows objectForKey:element.name]) {
				NSString *key = ORMFormText(element.readColumn < [each count] ? [each objectAtIndex:element.readColumn] : nil, nil,
				                            element.keyName);
				if ([key length] > 0 && ![keys containsObject:key]) {
					[keys addObject:key];
				}
			}
			[read setObject:ORMFormKeysText(keys) forKey:element.name];
			continue;
		}
		id value = element.readColumn < [row count] ? [row objectAtIndex:element.readColumn] : nil;
		[read setObject:ORMFormText(value, element.schemaType, element.keyName) forKey:element.name];
	}
	return read;
}

/* The texts at the path through rows: each row's, each of its rows' in
 * turn. */
static void
ORMFormCollect(id value, NSArray<NSString *> *path, NSMutableArray<NSString *> *into)
{
	if ([path count] == 0) {
		NSString *text = [value description];
		if ([text length] > 0) {
			[into addObject:text];
		}
		return;
	}
	if ([value isKindOfClass:[NSArray class]]) {
		for (id row in value) {
			ORMFormCollect(row, path, into);
		}
		return;
	}
	if ([value isKindOfClass:[NSDictionary class]]) {
		ORMFormCollect([value objectForKey:[path firstObject]], [path subarrayWithRange:NSMakeRange(1, [path count] - 1)], into);
	}
}

- (NSDictionary<NSString *, id> *)instanceWithAggregates:(NSDictionary<NSString *, id> *)instance
{
	NSMutableDictionary *worked = [instance mutableCopy];
	for (ORMFormElement *element in _elements) {
		NSArray *path = [element.aggregate objectForKey:@"path"];
		NSString *function = [element.aggregate objectForKey:@"function"];
		if (![path isKindOfClass:[NSArray class]] || ![function isKindOfClass:[NSString class]]) {
			continue;
		}
		NSMutableArray *texts = [NSMutableArray array];
		ORMFormCollect(instance, path, texts);
		NSDecimalNumber *sum = [NSDecimalNumber zero], *most = nil, *least = nil;
		NSUInteger count = 0;
		for (NSString *text in texts) {
			NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:text locale:@{ NSLocaleDecimalSeparator : @"." }];
			if ([number isEqualToNumber:[NSDecimalNumber notANumber]]) {
				continue;
			}
			count++;
			sum = [sum decimalNumberByAdding:number];
			most = most == nil || [number compare:most] == NSOrderedDescending ? number : most;
			least = least == nil || [number compare:least] == NSOrderedAscending ? number : least;
		}
		NSString *value = @"";
		if ([function isEqualToString:@"count"]) {
			value = [NSString stringWithFormat:@"%lu", (unsigned long)count];
		} else if ([function isEqualToString:@"total"]) {
			value = [sum stringValue];
		} else if (count > 0 && [function isEqualToString:@"avg"]) {
			value = [[sum decimalNumberByDividingBy:[NSDecimalNumber decimalNumberWithMantissa:count exponent:0 isNegative:NO]] stringValue];
		} else if (count > 0) {
			value = [([function isEqualToString:@"max"] ? most : least) stringValue] ?: @"";
		}
		[worked setObject:value forKey:element.name];
	}
	return worked;
}

- (NSDictionary<NSString *, id> *)instanceOfRow:(NSArray *)row
{
	NSMutableDictionary *instance = [NSMutableDictionary dictionary];
	for (ORMFormElement *element in _elements) {
		id value = element.column < [row count] ? [row objectAtIndex:element.column] : nil;
		if (element.part != NSNotFound && [value isKindOfClass:[NSArray class]]) {
			value = element.part < [value count] ? [value objectAtIndex:element.part] : nil;
		}
		[instance setObject:ORMFormText(value, element.schemaType, element.keyName) forKey:element.name];
	}
	return instance;
}

#pragma mark The store

- (NSDictionary<NSString *, id> *)readKey:(NSString *)key
                                        inContext:(NSManagedObjectContext *)context
                                            error:(NSError **)error
{
	ORMQueryPlan *plan = [_readPlan planBinding:@{ _keyElement ?: @"": key ?: @"" } error:error];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[[context persistentStoreCoordinator] managedObjectModel]];
	ORMQueryResult *result = plan != nil ? [interpreter executePlan:plan inContext:context error:error] : nil;
	if (result == nil) {
		return nil;
	}
	if ([result.rows count] == 0) {
		if (error != NULL) {
			*error = ORMFormError([NSString stringWithFormat:@"There is no %@ %@.", _entityName, key]);
		}
		return nil;
	}
	NSMutableDictionary *instance = [[self instance:[self instanceOfRow:[result.rows firstObject]] readOwnOf:key
	                                     interpreter:interpreter inContext:context error:error] mutableCopy];
	if (instance == nil) {
		return nil;
	}
	ORMFormElement *kind = [self subtypeElement];
	if (kind != nil) {
		NSEntityDescription *entity = [NSEntityDescription entityForName:_entityName inManagedObjectContext:context];
		NSAttributeDescription *keyAttribute = [[entity attributesByName] objectForKey:_keyElement ?: @""];
		NSString *problem = nil;
		id typed = ORMFormValue(key ?: @"", keyAttribute, &problem);
		NSString *name = [[(typed != nil ? ORMFormFind(entity, _keyElement, typed, context) : nil) entity] name];
		[instance setObject:[kind.items containsObject:name ?: @""] ? name : @"" forKey:kind.name];
	}
	for (NSString *name in _repeats) {
		/* Linked to the anchor, or to what the form reads its key of (an
		 * owned contact, the driver): none where that has none. */
		ORMForm *repeat = [_repeats objectForKey:name];
		NSString *linked = repeat->_from != nil ? [[instance objectForKey:repeat->_from] description] : key;
		NSArray *rows = [linked length] > 0 ? [repeat rowsLinkedTo:linked inContext:context error:error] : @[];
		if (rows == nil) {
			return nil;
		}
		[instance setObject:rows forKey:name];
	}
	return [self instanceWithAggregates:instance];
}

/* The instance with what is read on its own, by the key: a derived value,
 * a set of choices. */
- (NSDictionary *)instance:(NSDictionary *)instance
                 readOwnOf:(NSString *)key
               interpreter:(ORMQueryInterpreter *)interpreter
                 inContext:(NSManagedObjectContext *)context
                     error:(NSError **)error
{
	NSMutableDictionary *own = [NSMutableDictionary dictionary];
	for (ORMFormElement *element in _elements) {
		ORMQueryPlan *plan = element.read != nil ? [element.read planBinding:@{ _keyElement ?: @"" : key ?: @"" } error:error] : nil;
		ORMQueryResult *read = plan != nil ? [interpreter executePlan:plan inContext:context error:error] : nil;
		if (element.read != nil && read == nil) {
			return nil;
		}
		if (read != nil) {
			[own setObject:read.rows forKey:element.name];
		}
	}
	return [self instance:instance withOwnReads:own];
}

- (NSArray<NSDictionary *> *)rowsLinkedTo:(NSString *)key inContext:(NSManagedObjectContext *)context error:(NSError **)error
{
	ORMQueryPlan *plan = [_readPlan planBinding:@{ _linkElement ?: @"": key ?: @"" } error:error];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[[context persistentStoreCoordinator] managedObjectModel]];
	ORMQueryResult *result = plan != nil ? [interpreter executePlan:plan inContext:context error:error] : nil;
	if (result == nil) {
		return nil;
	}
	NSMutableArray *rows = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	for (NSArray *row in result.rows) {
		NSDictionary *instance = [self instanceOfRow:row];
		NSString *rowKey = [instance objectForKey:_keyElement] ?: @"";
		if ([rowKey length] > 0 && [seen containsObject:rowKey]) {
			continue;
		}
		[seen addObject:rowKey];
		/* Each row's own reads, by its key (an answer's options). */
		instance = [self instance:instance readOwnOf:rowKey interpreter:interpreter inContext:context error:error];
		if (instance == nil) {
			return nil;
		}
		[rows addObject:instance];
	}
	return rows;
}

- (NSArray<NSString *> *)choicesNamed:(NSString *)name
                               values:(NSDictionary<NSString *, id> *)values
                            inContext:(NSManagedObjectContext *)context
                                error:(NSError **)error
{
	ORMQueryPlan *plan = [self choicesPlanNamed:name values:values error:error];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[[context persistentStoreCoordinator] managedObjectModel]];
	ORMQueryResult *result = plan != nil ? [interpreter executePlan:plan inContext:context error:error] : nil;
	if (result == nil) {
		return nil;
	}
	NSMutableArray *keys = [NSMutableArray array];
	for (NSArray *row in result.rows) {
		NSString *key = ORMFormText([row firstObject], nil, [self elementNamed:name].keyName);
		if ([key length] > 0 && ![keys containsObject:key]) {
			[keys addObject:key];
		}
	}
	return keys;
}

- (NSString *)identifiedKeyNamed:(NSString *)name
                          values:(NSDictionary<NSString *, id> *)values
                       inContext:(NSManagedObjectContext *)context
                           error:(NSError **)error
{
	if ([self noneIdentifying:name in:values]) {
		return @"";
	}
	ORMQueryPlan *plan = [self identifyPlanNamed:name values:values error:error];
	ORMQueryInterpreter *interpreter = [[ORMQueryInterpreter alloc] initWithModel:[[context persistentStoreCoordinator] managedObjectModel]];
	ORMQueryResult *result = plan != nil ? [interpreter executePlan:plan inContext:context error:error] : nil;
	if (result == nil) {
		return nil;
	}
	return ORMFormText([[result.rows firstObject] firstObject], nil, [self elementNamed:name].keyName);
}

/* The instance, each reference found by values entered set to the key of
 * the object they find; where none is, why, at the first of them. */
- (NSDictionary *)identified:(NSDictionary *)instance
                   inContext:(NSManagedObjectContext *)context
                    problems:(NSMutableDictionary<NSString *, NSString *> *)problems
                       error:(NSError **)error
{
	NSMutableDictionary *found = [instance mutableCopy];
	for (NSString *name in [self identifiedNames]) {
		NSString *key = [self identifiedKeyNamed:name values:instance inContext:context error:error];
		if (key == nil) {
			return nil;
		}
		if ([key length] == 0 && ![self noneIdentifying:name in:instance]) {
			[problems setObject:[self unfoundMessageNamed:name] forKey:[[self elementsIdentifying:name] firstObject]];
		}
		[found setObject:key forKey:name];
	}
	return found;
}

/* The object of the entity whose attribute has the value. */
static NSManagedObject *
ORMFormFind(NSEntityDescription *entity, NSString *key, id value, NSManagedObjectContext *context)
{
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	[request setEntity:entity];
	[request setPredicate:[NSPredicate predicateWithFormat:@"%K == %@", key, value]];
	[request setFetchLimit:1];
	return [[context executeFetchRequest:request error:NULL] firstObject];
}

- (NSDictionary<NSString *, NSString *> *)throughValuesOf:(NSDictionary<NSString *, id> *)instance
                                                inContext:(NSManagedObjectContext *)context
{
	NSEntityDescription *entity = [NSEntityDescription entityForName:_entityName inManagedObjectContext:context];
	NSMutableDictionary *values = [NSMutableDictionary dictionary];
	for (ORMFormElement *element in _elements) {
		/* What finds the reference is entered, not read through it. */
		ORMFormElement *reference = element.group == nil && element.identifies == nil && [element.path count] > 1
			? [self elementNamed:[element.path firstObject]] : nil;
		if (![reference.kind isEqualToString:@"reference"]) {
			continue;
		}
		NSEntityDescription *destination = [[[entity relationshipsByName] objectForKey:reference.name] destinationEntity];
		NSAttributeDescription *key = [[destination attributesByName] objectForKey:reference.keyName ?: @""];
		NSString *problem = nil;
		id typed = ORMFormValue([[instance objectForKey:reference.name] description] ?: @"", key, &problem);
		NSManagedObject *object = typed != nil ? ORMFormFind(destination, reference.keyName, typed, context) : nil;
		NSString *rest = [[element.path subarrayWithRange:NSMakeRange(1, [element.path count] - 1)] componentsJoinedByString:@"."];
		[values setObject:ORMFormText([object valueForKeyPath:rest], element.schemaType, element.keyName) forKey:element.name];
	}
	return values;
}

/* A new object's key, where it has none: a UUID's text, or one more than
 * the greatest whole number there is, as a service makes one. */
static id
ORMFormNewKey(NSEntityDescription *entity, NSAttributeDescription *key, NSManagedObjectContext *context)
{
	switch ([key attributeType]) {
	case NSStringAttributeType:
		return [[NSUUID UUID] UUIDString];
	case NSUUIDAttributeType:
		return [NSUUID UUID];
	case NSInteger16AttributeType:
	case NSInteger32AttributeType:
	case NSInteger64AttributeType: {
		NSFetchRequest *request = [[NSFetchRequest alloc] init];
		[request setEntity:entity];
		[request setPredicate:[NSPredicate predicateWithFormat:@"%K != nil", [key name]]];
		[request setSortDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:[key name] ascending:NO] ]];
		[request setFetchLimit:1];
		NSManagedObject *greatest = [[context executeFetchRequest:request error:NULL] firstObject];
		return [NSNumber numberWithLongLong:[[greatest valueForKey:[key name]] longLongValue] + 1];
	}
	default:
		return nil;
	}
}

- (NSManagedObject *)save:(NSDictionary<NSString *, id> *)instance
                inContext:(NSManagedObjectContext *)context
                   errors:(NSDictionary<NSString *, NSString *> **)errors
                    error:(NSError **)error
{
	return [self save:instance inContext:context saving:nil errors:errors error:error];
}

/* The instance written into its object, found by its key or made (a key
 * given it where it has none): what was wrong of each element said under
 * its name after the prefix ("purchaseLines[1]."), what the object had
 * before kept to put back, whether it was made. nil, and why, where the
 * store has no such entity. */
- (NSManagedObject *)write:(NSDictionary *)instance
                 inContext:(NSManagedObjectContext *)context
                  problems:(NSMutableDictionary<NSString *, NSString *> *)problems
                    prefix:(NSString *)prefix
                    before:(NSMutableDictionary *)before
                      made:(BOOL *)made
                     owned:(NSMutableArray<NSDictionary *> *)owned
                     error:(NSError **)error
{
	NSEntityDescription *entity = [NSEntityDescription entityForName:_entityName inManagedObjectContext:context];
	NSAttributeDescription *keyAttribute = [[entity attributesByName] objectForKey:_keyElement ?: @""];
	if (entity == nil) {
		if (error != NULL) {
			*error = ORMFormError([NSString stringWithFormat:@"The store has no %@.", _entityName]);
		}
		return nil;
	}
	NSString *problem = nil;
	id key = ORMFormValue([instance objectForKey:_keyElement] ?: @"", keyAttribute, &problem);
	NSManagedObject *object = key != nil ? ORMFormFind(entity, _keyElement, key, context) : nil;
	/* Of the subtype chosen, a subentity of the anchor's; one read stays
	 * what it is. */
	ORMFormElement *kind = [self subtypeElement];
	NSString *chosen = kind != nil ? [[instance objectForKey:kind.name] description] : nil;
	NSEntityDescription *subentity = [chosen length] > 0 ? [NSEntityDescription entityForName:chosen inManagedObjectContext:context] : nil;
	if ([chosen length] > 0 && (subentity == nil || ![subentity isKindOfEntity:entity] || ![kind.items containsObject:chosen])) {
		[problems setObject:[NSString stringWithFormat:@"%@ is no kind of %@ here.", chosen, _entityName]
		             forKey:[prefix stringByAppendingString:kind.name]];
		subentity = nil;
	}
	if (object != nil && kind != nil && [chosen length] > 0 && ![[[object entity] name] isEqualToString:chosen]) {
		[problems setObject:[NSString stringWithFormat:@"A %@ stays what it is.", [[object entity] name]]
		             forKey:[prefix stringByAppendingString:kind.name]];
	}
	*made = object == nil;
	if (*made) {
		object = [NSEntityDescription insertNewObjectForEntityForName:[subentity name] ?: _entityName inManagedObjectContext:context];
		if (keyAttribute != nil) {
			[object setValue:key ?: ORMFormNewKey(entity, keyAttribute, context) forKey:_keyElement];
		}
	}
	for (ORMFormElement *element in _elements) {
		/* A repeat's link is written by the form it is in; an owned
		 * object's elements into it, below; a subtype's only where the
		 * object is one; the kind is the object's entity. */
		if ((!element.written && ![element.name isEqualToString:_linkElement ?: @""]) || element.group != nil
		    || element == kind || ![self object:object isOf:element.subtype]) {
			continue;
		}
		NSString *refused = [self write:element text:[instance objectForKey:element.name] ?: @"" into:object
		                       property:[element.path lastObject] ?: element.name before:before context:context];
		if (refused != nil) {
			[problems setObject:refused forKey:[prefix stringByAppendingString:element.name]];
		}
	}
	[self writeGroupsOf:object instance:instance context:context problems:problems prefix:prefix owned:owned];
	return object;
}

/* The element's text set as the object's property: a reference's object
 * found by its key. What it had kept in before; why not, where it cannot. */
- (NSString *)write:(ORMFormElement *)element
               text:(NSString *)text
               into:(NSManagedObject *)object
           property:(NSString *)property
             before:(NSMutableDictionary *)before
            context:(NSManagedObjectContext *)context
{
	NSEntityDescription *entity = [object entity];
	NSString *problem = nil;
	id value = nil;
	if (element.many) {
		/* A set of choices: the objects of its keys, the whole of the
		 * relationship. */
		NSRelationshipDescription *relationship = [[entity relationshipsByName] objectForKey:property];
		NSEntityDescription *destination = [relationship destinationEntity];
		NSAttributeDescription *destinationKey = [[destination attributesByName] objectForKey:element.keyName ?: @""];
		NSMutableSet *picked = [NSMutableSet set];
		for (NSString *key in ORMFormKeysOf(text)) {
			id typed = ORMFormValue(key, destinationKey, &problem);
			NSManagedObject *one = typed != nil ? ORMFormFind(destination, element.keyName, typed, context) : nil;
			if (one == nil) {
				problem = problem ?: [NSString stringWithFormat:@"There is no %@ %@.", [destination name] ?: element.entityName, key];
				break;
			}
			[picked addObject:one];
		}
		if (relationship == nil || ![relationship isToMany]) {
			problem = [NSString stringWithFormat:@"%@ has no %@.", [entity name], property];
		}
		if (problem != nil) {
			return problem;
		}
		[before setObject:[[object valueForKey:property] copy] ?: [NSNull null] forKey:property];
		[object setValue:picked forKey:property];
		return nil;
	}
	if ([element.kind isEqualToString:@"reference"]) {
		NSRelationshipDescription *relationship = [[entity relationshipsByName] objectForKey:property];
		NSEntityDescription *destination = [relationship destinationEntity];
		NSAttributeDescription *destinationKey = [[destination attributesByName] objectForKey:element.keyName ?: @""];
		id typed = ORMFormValue(text, destinationKey, &problem);
		value = typed != nil ? ORMFormFind(destination, element.keyName, typed, context) : nil;
		if (relationship == nil || (typed != nil && value == nil)) {
			problem = problem ?: [NSString stringWithFormat:@"There is no %@ %@.", [destination name] ?: element.entityName, text];
		}
	} else {
		NSAttributeDescription *attribute = [[entity attributesByName] objectForKey:property];
		value = attribute != nil ? ORMFormValue(text, attribute, &problem) : nil;
		problem = attribute == nil ? [NSString stringWithFormat:@"%@ has no %@.", [entity name], property] : problem;
	}
	if (problem != nil) {
		return problem;
	}
	[before setObject:[object valueForKey:property] ?: [NSNull null] forKey:property];
	[object setValue:value forKey:property];
	return nil;
}

/* The element that says which of its subtypes the object is; nil for a
 * form with no subtype parts. */
- (ORMFormElement *)subtypeElement
{
	for (ORMFormElement *element in _elements) {
		if ([element.kind isEqualToString:@"subtype"]) {
			return element;
		}
	}
	return nil;
}

/* Whether the object is of the subentity (nil: the anchor's own). */
- (BOOL)object:(NSManagedObject *)object isOf:(NSString *)subentity
{
	if (subentity == nil) {
		return YES;
	}
	NSEntityDescription *entity = [[[[object entity] managedObjectModel] entitiesByName] objectForKey:subentity];
	return entity != nil && [[object entity] isKindOfEntity:entity];
}

- (NSArray<NSDictionary *> *)groups
{
	NSArray *groups = [_list objectForKey:@"groups"];
	return [groups isKindOfClass:[NSArray class]] ? groups : @[];
}

/* Whether anything of the owned object is entered: its elements' or an
 * object's it owns in turn. */
- (BOOL)isEntered:(NSString *)group in:(NSDictionary *)instance
{
	NSString *within = [group stringByAppendingString:@"/"];
	for (ORMFormElement *element in _elements) {
		if (element.written && ([element.group isEqualToString:group] || [element.group hasPrefix:within])
		    && [[[instance objectForKey:element.name] description] length] > 0) {
			return YES;
		}
	}
	return NO;
}

/* The objects the form owns written (a customer's contact, its address),
 * outer ones first: each the one the object above has, else made where it
 * is needed or anything of it is entered (its key given it) and set there;
 * its elements written into it. Each one changed or made, and what it
 * had, kept in owned to put back. */
- (void)writeGroupsOf:(NSManagedObject *)anchor
             instance:(NSDictionary *)instance
              context:(NSManagedObjectContext *)context
             problems:(NSMutableDictionary<NSString *, NSString *> *)problems
               prefix:(NSString *)prefix
                owned:(NSMutableArray<NSDictionary *> *)owned
{
	NSMutableDictionary<NSString *, NSManagedObject *> *objects = [NSMutableDictionary dictionary];
	for (NSDictionary *group in [self groups]) {
		NSString *name = [group objectForKey:@"name"];
		NSArray *path = [group objectForKey:@"path"];
		if (![name isKindOfClass:[NSString class]] || ![path isKindOfClass:[NSArray class]] || [path count] == 0) {
			continue;
		}
		NSString *aboveName = [path count] > 1 ? [[path subarrayWithRange:NSMakeRange(0, [path count] - 1)] componentsJoinedByString:@"/"] : nil;
		NSManagedObject *above = aboveName != nil ? [objects objectForKey:aboveName] : anchor;
		NSString *link = [path lastObject];
		NSRelationshipDescription *relationship = [[[above entity] relationshipsByName] objectForKey:link];
		if (above == nil) {
			continue;
		}
		if (relationship == nil || [relationship isToMany]) {
			[problems setObject:[NSString stringWithFormat:@"%@ has no %@.", [[above entity] name], link]
			             forKey:[prefix stringByAppendingString:name]];
			continue;
		}
		NSManagedObject *object = [above valueForKey:link];
		if (object == nil && ![[group objectForKey:@"needed"] boolValue] && ![self isEntered:name in:instance]) {
			continue;
		}
		BOOL made = object == nil;
		if (made) {
			NSEntityDescription *entity = [relationship destinationEntity];
			object = [NSEntityDescription insertNewObjectForEntityForName:[entity name] inManagedObjectContext:context];
			NSAttributeDescription *key = [[entity attributesByName] objectForKey:[group objectForKey:@"key"] ?: @""];
			if (key != nil) {
				[object setValue:ORMFormNewKey(entity, key, context) forKey:[key name]];
			}
			[owned addObject:@{ @"object" : above, @"made" : @NO, @"before" : @{ link : [NSNull null] } }];
			[above setValue:object forKey:link];
		}
		NSMutableDictionary *before = [NSMutableDictionary dictionary];
		for (ORMFormElement *element in _elements) {
			if (!element.written || ![element.group isEqualToString:name]) {
				continue;
			}
			NSString *problem = [self write:element text:[instance objectForKey:element.name] ?: @"" into:object
			                       property:[element.path lastObject] before:before context:context];
			if (problem != nil) {
				[problems setObject:problem forKey:[prefix stringByAppendingString:element.name]];
			}
		}
		[owned addObject:@{ @"object" : object, @"made" : @(made), @"before" : before, @"group" : name }];
		[objects setObject:object forKey:name];
	}
}

/* The object as it was, where its save was refused: one made, gone. One
 * gone already (a new customer, with the new contact it cascades from) is
 * left so: it is no longer the context's to change. */
static void
ORMFormPutBack(NSManagedObject *object, BOOL made, NSDictionary *before, NSManagedObjectContext *context)
{
	if ([object managedObjectContext] == nil || [object isDeleted]) {
		return;
	}
	if (made) {
		[context deleteObject:object];
		/* Gone now, its relationships' other ends too, before anything else
		 * is done with the context (a rollback). */
		[context processPendingChanges];
		return;
	}
	for (NSString *name in before) {
		id value = [before objectForKey:name];
		[object setValue:value == [NSNull null] ? nil : value forKey:name];
	}
}


/* The instance written into the context, nothing saved: its object, its
 * owned objects, its rows (those the rows no longer have deleted). nil,
 * and why, where the store has no such entity or a value cannot be read. */
- (ORMFormWriting *)writing:(NSDictionary *)instance inContext:(NSManagedObjectContext *)context error:(NSError **)error
{
	ORMFormWriting *w = [[ORMFormWriting alloc] init];
	w.form = self;
	w.problems = [NSMutableDictionary dictionary];
	w.before = [NSMutableDictionary dictionary];
	w.owned = [NSMutableArray array];
	w.rowObjects = [NSMutableArray array];
	w.rowBefores = [NSMutableArray array];
	w.rowMade = [NSMutableArray array];
	w.rowPrefixes = [NSMutableDictionary dictionary];
	/* What values entered find (an order's customer, by email). */
	instance = [self identified:instance inContext:context problems:w.problems error:error];
	if (instance == nil) {
		return nil;
	}
	BOOL made = NO;
	w.object = [self write:instance inContext:context problems:w.problems prefix:@"" before:w.before made:&made owned:w.owned error:error];
	w.made = made;
	if (w.object == nil) {
		return nil;
	}
	/* Each repeat's rows written into their objects, linked to this one;
	 * those it had and the rows no longer have, gone. A row's problem is
	 * said under "<repeat>[<index>].<element>". */
	NSString *keyText = ORMFormText([w.object valueForKey:_keyElement ?: @""], nil, nil);
	for (NSString *name in [self repeatNames]) {
		NSArray *rows = (NSArray *)[(NSDictionary *)instance objectForKey:name];
		ORMForm *repeat = [_repeats objectForKey:name];
		if (![rows isKindOfClass:[NSArray class]] || repeat.isList || ![self object:w.object isOf:repeat->_subtype]) {
			continue;
		}
		/* Linked to the anchor, or to the owned object they are of (a
		 * contact's phones), as written above. */
		NSManagedObject *of = w.object;
		NSString *ofKey = keyText;
		if (repeat->_fromGroup != nil) {
			of = nil;
			for (NSDictionary *each in w.owned) {
				of = [[each objectForKey:@"group"] isEqualToString:repeat->_fromGroup] ? [each objectForKey:@"object"] : of;
			}
			NSString *groupKey = nil;
			for (NSDictionary *group in [self groups]) {
				groupKey = [[group objectForKey:@"name"] isEqualToString:repeat->_fromGroup] ? [group objectForKey:@"key"] : groupKey;
			}
			if (of == nil) {
				continue;
			}
			ofKey = ORMFormText([of valueForKey:groupKey ?: @""], nil, nil);
		}
		NSMutableSet *kept = [NSMutableSet set];
		for (NSUInteger i = 0; i < [rows count]; i++) {
			NSMutableDictionary *row = [[rows objectAtIndex:i] mutableCopy];
			[row setObject:ofKey forKey:repeat.linkElement];
			NSString *prefix = [NSString stringWithFormat:@"%@[%lu].", name, (unsigned long)i];
			NSMutableDictionary *was = [NSMutableDictionary dictionary];
			BOOL rowWasMade = NO;
			NSManagedObject *rowObject = [repeat write:row inContext:context problems:w.problems prefix:prefix before:was
			                                     made:&rowWasMade owned:w.owned error:error];
			if (rowObject == nil) {
				return nil;
			}
			[kept addObject:rowObject];
			[w.rowObjects addObject:rowObject];
			[w.rowBefores addObject:was];
			[w.rowMade addObject:@(rowWasMade)];
			[w.rowPrefixes setObject:prefix forKey:[NSValue valueWithNonretainedObject:rowObject]];
		}
		NSFetchRequest *linked = [NSFetchRequest fetchRequestWithEntityName:repeat.entityName];
		[linked setPredicate:[NSPredicate predicateWithFormat:@"%K == %@", repeat.linkElement, of]];
		for (NSManagedObject *gone in [context executeFetchRequest:linked error:NULL]) {
			if (![kept containsObject:gone]) {
				[context deleteObject:gone];
			}
		}
	}
	return w;
}

/* What the store's error says of the writing's objects, by its elements:
 * a row's under its prefix, an owned object's at its group's element, the
 * anchor's as the form says it. NO where it is of none of them. */
- (BOOL)says:(NSError *)one of:(ORMFormWriting *)w
{
	id about = [[one userInfo] objectForKey:NSValidationObjectErrorKey];
	NSString *prefix = about != nil ? [w.rowPrefixes objectForKey:[NSValue valueWithNonretainedObject:about]] : nil;
	NSString *group = nil;
	BOOL owned = NO;
	for (NSDictionary *each in w.owned) {
		if ([each objectForKey:@"object"] == about) {
			owned = YES;
			group = [each objectForKey:@"group"] ?: group;
		}
	}
	if (about != nil && about != w.object && prefix == nil && !owned) {
		return NO;
	}
	NSString *at = nil;
	if (prefix == nil && group != nil) {
		NSString *key = [[one userInfo] objectForKey:NSValidationKeyErrorKey];
		NSString *element = key != nil ? [NSString stringWithFormat:@"%@/%@", group, key] : @"";
		at = [self elementNamed:element] != nil ? element : @"";
	} else if (prefix == nil) {
		at = [self elementOfError:one];
	} else {
		ORMForm *repeat = nil;
		for (NSString *name in _repeats) {
			if ([prefix hasPrefix:[name stringByAppendingString:@"["]]) {
				repeat = [_repeats objectForKey:name];
			}
		}
		NSString *element = [repeat elementOfError:one];
		at = [element length] > 0 ? [prefix stringByAppendingString:element] : @"";
	}
	NSString *said = [w.problems objectForKey:at];
	NSString *message = [self messageOf:one];
	[w.problems setObject:said != nil ? [NSString stringWithFormat:@"%@ %@", said, message] : message forKey:at];
	return YES;
}

/* Refused: what the writing changed, as it was. */
static void
ORMFormPutBackWriting(ORMFormWriting *w, NSManagedObjectContext *context)
{
	for (NSUInteger i = [w.rowObjects count]; i > 0; i--) {
		ORMFormPutBack([w.rowObjects objectAtIndex:i - 1], [[w.rowMade objectAtIndex:i - 1] boolValue], [w.rowBefores objectAtIndex:i - 1], context);
	}
	for (NSUInteger i = [w.owned count]; i > 0; i--) {
		NSDictionary *each = [w.owned objectAtIndex:i - 1];
		ORMFormPutBack([each objectForKey:@"object"], [[each objectForKey:@"made"] boolValue], [each objectForKey:@"before"], context);
	}
	ORMFormPutBack(w.object, w.made, w.before, context);
}

- (NSManagedObject *)save:(NSDictionary<NSString *, id> *)instance
                inContext:(NSManagedObjectContext *)context
                   saving:(BOOL (^)(NSManagedObjectContext *context, NSError **error))saving
                   errors:(NSDictionary<NSString *, NSString *> **)errors
                    error:(NSError **)error
{
	NSArray *saved = [ORMForm saveForms:@[ self ] instances:@[ instance ] inContext:context saving:saving errors:errors error:error];
	return [saved firstObject];
}

+ (NSArray<NSManagedObject *> *)saveForms:(NSArray<ORMForm *> *)forms
                                instances:(NSArray<NSDictionary *> *)instances
                                inContext:(NSManagedObjectContext *)context
                                   saving:(BOOL (^)(NSManagedObjectContext *context, NSError **error))saving
                                   errors:(NSDictionary<NSString *, NSString *> **)errors
                                    error:(NSError **)error
{
	NSMutableArray<ORMFormWriting *> *writings = [NSMutableArray array];
	BOOL wrong = NO;
	for (NSUInteger i = 0; i < [forms count] && i < [instances count]; i++) {
		ORMFormWriting *w = [[forms objectAtIndex:i] writing:[instances objectAtIndex:i] inContext:context error:error];
		if (w == nil) {
			for (ORMFormWriting *each in [writings reverseObjectEnumerator]) {
				ORMFormPutBackWriting(each, context);
			}
			return nil;
		}
		[writings addObject:w];
		wrong = wrong || [w.problems count] > 0;
	}
	NSError *failure = nil;
	if (!wrong && (saving != nil ? saving(context, &failure) : [context save:&failure])) {
		return [writings valueForKey:@"object"];
	}
	if (!wrong) {
		NSArray *each = [[failure userInfo] objectForKey:NSDetailedErrorsKey] ?: (failure != nil ? @[ failure ] : @[]);
		for (NSError *one in each) {
			BOOL said = NO;
			for (ORMFormWriting *w in writings) {
				said = said || [w.form says:one of:w];
			}
			if (!said) {
				[[writings firstObject].form addErrorsOf:one to:[writings firstObject].problems];
			}
		}
	}
	/* Refused: the objects as they were, the last written first. */
	for (ORMFormWriting *w in [writings reverseObjectEnumerator]) {
		ORMFormPutBackWriting(w, context);
	}
	if (errors != NULL) {
		/* The first form's by its elements; each other's by its name before
		 * them ("NewSupplier/contact/contactName"). */
		NSMutableDictionary *problems = [NSMutableDictionary dictionary];
		for (NSUInteger i = 0; i < [writings count]; i++) {
			ORMFormWriting *w = [writings objectAtIndex:i];
			[w.problems enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *text, BOOL *stop) {
				[problems setObject:text forKey:i == 0 ? key : [NSString stringWithFormat:@"%@/%@", w.form.name ?: @"", key]];
			}];
		}
		*errors = problems;
	}
	if (error != NULL) {
		*error = failure ?: ORMFormError(@"The form's values are not all of their types.");
	}
	return nil;
}

/* What the store says of a property, for the user. */
static NSString *
ORMFormMessage(NSError *error)
{
	if ([[error domain] isEqualToString:NSCocoaErrorDomain] && [error code] == NSValidationMissingMandatoryPropertyError) {
		return @"A value is required.";
	}
	return [error localizedDescription] ?: @"";
}

/* What the error says, in the app's words where it is of a rule they say. */
- (NSString *)messageOf:(NSError *)error
{
	NSString *rule = [[error userInfo] objectForKey:@"ORMConstraint"];
	return ([rule isKindOfClass:[NSString class]] ? [_messages objectForKey:rule] : nil) ?: ORMFormMessage(error);
}

/* Whether the entity, or one it is a kind of, is the form's anchor's. */
- (BOOL)isAnchor:(NSEntityDescription *)entity
{
	for (NSEntityDescription *each = entity; each != nil; each = [each superentity]) {
		if ([[each name] isEqualToString:_entityName]) {
			return YES;
		}
	}
	return entity == nil;
}

/* Where what an error says is said: of a rule over several of the anchor's
 * properties (ORMKeys: a driver who does not drive the vehicle), at the
 * first of them the form enters, not at what it is given, which the user
 * cannot change; at its one property (NSValidationKeyErrorKey) where that
 * is an element; else of the form, "". */
- (NSString *)elementOfError:(NSError *)error
{
	NSDictionary *info = [error userInfo];
	id object = [info objectForKey:NSValidationObjectErrorKey];
	if ([object respondsToSelector:@selector(entity)] && ![self isAnchor:[object entity]]) {
		return @"";
	}
	NSArray *keys = [info objectForKey:@"ORMKeys"];
	for (NSString *key in [keys isKindOfClass:[NSArray class]] ? keys : @[]) {
		ORMFormElement *element = [self elementNamed:key];
		if ([element.role isEqualToString:@"entered"]) {
			return key;
		}
	}
	NSString *key = [info objectForKey:NSValidationKeyErrorKey];
	ORMFormElement *element = key != nil ? [self elementNamed:key] : nil;
	return element != nil && ![element.role isEqualToString:@"given"] && ![element.role isEqualToString:@"key"] ? key : @"";
}

- (NSDictionary<NSString *, NSString *> *)elementErrorsOf:(NSError *)error
{
	NSMutableDictionary *errors = [NSMutableDictionary dictionary];
	NSArray *each = [[error userInfo] objectForKey:NSDetailedErrorsKey] ?: (error != nil ? @[ error ] : @[]);
	for (NSError *one in each) {
		[self addErrorsOf:one to:errors];
	}
	return errors;
}

- (void)addErrorsOf:(NSError *)one to:(NSMutableDictionary<NSString *, NSString *> *)errors
{
	NSString *name = [self elementOfError:one];
	NSString *said = [errors objectForKey:name];
	NSString *message = [self messageOf:one];
	[errors setObject:said != nil ? [NSString stringWithFormat:@"%@ %@", said, message] : message forKey:name];
}

#pragma mark The service

- (ORMQueryOData *)readRequestForKey:(NSString *)key model:(NSManagedObjectModel *)model error:(NSError **)error
{
	ORMQueryPlan *plan = [_readPlan planBinding:@{ _keyElement ?: @"": key ?: @"" } error:error];
	return plan != nil ? [ORMQueryOData requestForPlan:plan model:model error:error] : nil;
}

- (ORMQueryOData *)rowsRequestOfRepeat:(NSString *)name
                              linkedTo:(NSString *)key
                                 model:(NSManagedObjectModel *)model
                                 error:(NSError **)error
{
	ORMForm *repeat = [_repeats objectForKey:name];
	ORMQueryPlan *plan = [repeat.readPlan planBinding:@{ repeat.linkElement ?: @"" : key ?: @"" } error:error];
	return plan != nil ? [ORMQueryOData requestForPlan:plan model:model error:error] : nil;
}

- (ORMQueryOData *)identifyRequestNamed:(NSString *)name
                                 values:(NSDictionary<NSString *, id> *)values
                                  model:(NSManagedObjectModel *)model
                                  error:(NSError **)error
{
	ORMQueryPlan *plan = [self identifyPlanNamed:name values:values error:error];
	return plan != nil ? [ORMQueryOData requestForPlan:plan model:model error:error] : nil;
}

- (ORMQueryOData *)choicesRequestNamed:(NSString *)name
                                values:(NSDictionary<NSString *, id> *)values
                                 model:(NSManagedObjectModel *)model
                                 error:(NSError **)error
{
	ORMQueryPlan *plan = [self choicesPlanNamed:name values:values error:error];
	return plan != nil ? [ORMQueryOData requestForPlan:plan model:model error:error] : nil;
}

- (ORMFormRequest *)saveRequestFor:(NSDictionary<NSString *, id> *)instance
                          original:(NSDictionary<NSString *, id> *)original
                              etag:(NSString *)etag
                             model:(NSManagedObjectModel *)model
                             error:(NSError **)error
{
	NSEntityDescription *entity = [[model entitiesByName] objectForKey:_entityName];
	if (entity == nil) {
		if (error != NULL) {
			*error = ORMFormError([NSString stringWithFormat:@"The model has no %@.", _entityName]);
		}
		return nil;
	}
	ODataPropertyMapper *mapper = [[ODataPropertyMapper alloc] init];
	ODataValueCoder *coder = mapper.values ?: [[ODataValueCoder alloc] init];
	NSString *keyText = [instance objectForKey:_keyElement ?: @""] ?: @"";
	BOOL isNew = original == nil || [keyText length] == 0;
	NSMutableDictionary *body = [NSMutableDictionary dictionary];
	NSString *problem = nil;
	NSAttributeDescription *keyAttribute = [[entity attributesByName] objectForKey:_keyElement ?: @""];
	id key = ORMFormValue(keyText, keyAttribute, &problem);
	if (isNew && key != nil) {
		[body setObject:[coder JSONForCoreDataValue:key attribute:keyAttribute] forKey:[mapper propertyForAttribute:keyAttribute]];
	}
	/* Of the subtype chosen (a Trip among the events): its properties. */
	ORMFormElement *kind = [self subtypeElement];
	NSString *chosen = kind != nil ? [[instance objectForKey:kind.name] description] : nil;
	NSEntityDescription *subentity = [chosen length] > 0 ? [[model entitiesByName] objectForKey:chosen] : nil;
	NSEntityDescription *objectEntity = subentity != nil && [subentity isKindOfEntity:entity] ? subentity : entity;
	/* One type of several in its set (a FillUp among the Records): named, so
	 * that the service knows whose properties these are. */
	NSString *type = [mapper entityIsDerivedInItsSet:objectEntity] ? [mapper qualifiedTypeForEntity:objectEntity] : nil;
	if (type != nil) {
		[body setObject:[@"#" stringByAppendingString:type] forKey:@"@odata.type"];
	}
	/* The anchor's own; an owned object's nested in it (a deep insert, a
	 * deep update), outer ones first, each where anything of it is sent. */
	NSMutableDictionary<NSString *, NSMutableDictionary *> *bodies = [NSMutableDictionary dictionaryWithObject:body forKey:@""];
	NSMutableDictionary<NSString *, NSEntityDescription *> *entities = [NSMutableDictionary dictionaryWithObject:objectEntity forKey:@""];
	for (NSDictionary *group in [self groups]) {
		NSArray *path = [group objectForKey:@"path"];
		NSString *above = [path count] > 1 ? [[path subarrayWithRange:NSMakeRange(0, [path count] - 1)] componentsJoinedByString:@"/"] : @"";
		NSRelationshipDescription *relationship = [[[entities objectForKey:above] relationshipsByName] objectForKey:[path lastObject]];
		if (relationship != nil && [group objectForKey:@"name"] != nil) {
			[bodies setObject:[NSMutableDictionary dictionary] forKey:[group objectForKey:@"name"]];
			[entities setObject:[relationship destinationEntity] forKey:[group objectForKey:@"name"]];
		}
	}
	for (ORMFormElement *element in _elements) {
		NSString *text = [instance objectForKey:element.name] ?: @"";
		/* New: what it has; changed: what differs, an emptied one as null. */
		NSEntityDescription *part = element.subtype != nil ? [[model entitiesByName] objectForKey:element.subtype] : nil;
		if (!element.written || element == kind || (element.subtype != nil && (part == nil || ![objectEntity isKindOfEntity:part]))
		    || (isNew && [text length] == 0) || (!isNew && [text isEqualToString:[original objectForKey:element.name] ?: @""])) {
			continue;
		}
		NSMutableDictionary *into = [bodies objectForKey:element.group ?: @""];
		NSEntityDescription *of = [entities objectForKey:element.group ?: @""];
		NSString *property = [element.path lastObject] ?: element.name;
		if (into == nil) {
			problem = [NSString stringWithFormat:@"%@ has no %@.", _entityName, element.group];
			break;
		}
		if (element.many) {
			/* A set of choices: new, each object bound; changed, a delta of
			 * those picked and those no longer. */
			NSRelationshipDescription *relationship = [[of relationshipsByName] objectForKey:property];
			NSEntityDescription *destination = [relationship destinationEntity];
			NSAttributeDescription *destinationKey = [[destination attributesByName] objectForKey:element.keyName ?: @""];
			if (relationship == nil || ![relationship isToMany]) {
				problem = [NSString stringWithFormat:@"%@ has no %@.", [of name], property];
				break;
			}
			NSArray *now = ORMFormKeysOf(text);
			NSArray *had = isNew ? @[] : ORMFormKeysOf([[original objectForKey:element.name] description]);
			NSMutableArray *bound = [NSMutableArray array];
			NSMutableArray *delta = [NSMutableArray array];
			for (NSString *key in [now arrayByAddingObjectsFromArray:had]) {
				id typed = ORMFormValue(key, destinationKey, &problem);
				if (problem != nil) {
					break;
				}
				NSString *path = [NSString stringWithFormat:@"%@(%@)", [mapper entitySetForEntity:destination],
				                                              [coder literalForValue:typed attribute:destinationKey]];
				BOOL picked = [now containsObject:key], was = [had containsObject:key];
				if (isNew && picked) {
					[bound addObject:path];
				} else if (picked && !was) {
					[delta addObject:@{ @"@id" : path }];
				} else if (!picked && was) {
					[delta addObject:@{ @"@removed" : @{ @"reason" : @"changed" }, @"@id" : path }];
				}
			}
			if (problem != nil) {
				break;
			}
			NSString *wire = [mapper propertyForRelationship:relationship];
			if (isNew) {
				[into setObject:bound forKey:[wire stringByAppendingString:@"@odata.bind"]];
			} else if ([delta count] > 0) {
				[into setObject:delta forKey:[wire stringByAppendingString:@"@delta"]];
			}
			continue;
		}
		if ([element.kind isEqualToString:@"reference"]) {
			NSRelationshipDescription *relationship = [[of relationshipsByName] objectForKey:property];
			NSEntityDescription *destination = [relationship destinationEntity];
			NSAttributeDescription *destinationKey = [[destination attributesByName] objectForKey:element.keyName ?: @""];
			id typed = ORMFormValue(text, destinationKey, &problem);
			if (relationship == nil || problem != nil) {
				problem = problem ?: [NSString stringWithFormat:@"%@ has no %@.", [of name], property];
				break;
			}
			NSString *bind = [[mapper propertyForRelationship:relationship] stringByAppendingString:@"@odata.bind"];
			[into setObject:typed != nil ? [NSString stringWithFormat:@"%@(%@)", [mapper entitySetForEntity:destination],
			                                                         [coder literalForValue:typed attribute:destinationKey]]
			                             : [NSNull null]
			         forKey:bind];
			continue;
		}
		NSAttributeDescription *attribute = [[of attributesByName] objectForKey:property];
		id typed = ORMFormValue(text, attribute, &problem);
		if (attribute == nil || problem != nil) {
			problem = problem ?: [NSString stringWithFormat:@"%@ has no %@.", [of name], property];
			break;
		}
		[into setObject:typed != nil ? [coder JSONForCoreDataValue:typed attribute:attribute] : [NSNull null]
		         forKey:[mapper propertyForAttribute:attribute]];
	}
	/* Each repeat's rows under its navigation property, in the body of what
	 * they are of (the anchor, an owned object). */
	for (NSString *name in [self repeatNames]) {
		ORMForm *repeat = [_repeats objectForKey:name];
		NSArray *rows = [[instance objectForKey:name] isKindOfClass:[NSArray class]] ? [instance objectForKey:name] : nil;
		NSEntityDescription *part = repeat->_subtype != nil ? [[model entitiesByName] objectForKey:repeat->_subtype] : nil;
		if (repeat.isList || rows == nil || problem != nil || (repeat->_subtype != nil && (part == nil || ![objectEntity isKindOfEntity:part]))) {
			continue;
		}
		NSString *within = repeat->_fromGroup ?: @"";
		NSRelationshipDescription *relationship = [[[entities objectForKey:within] relationshipsByName]
			objectForKey:[[name componentsSeparatedByString:@"/"] lastObject]];
		NSMutableDictionary *into = [bodies objectForKey:within];
		if (relationship == nil || into == nil) {
			problem = [NSString stringWithFormat:@"%@ has no %@.", _entityName, name];
			break;
		}
		NSArray *was = isNew || ![[original objectForKey:name] isKindOfClass:[NSArray class]] ? @[] : [original objectForKey:name];
		NSArray *sent = [repeat rowBodiesOf:rows was:was model:model new:isNew error:error];
		if (sent == nil) {
			return nil;
		}
		if (isNew) {
			[into setObject:sent forKey:[mapper propertyForRelationship:relationship]];
		} else if ([sent count] > 0) {
			[into setObject:sent forKey:[[mapper propertyForRelationship:relationship] stringByAppendingString:@"@delta"]];
		}
	}
	/* Inner ones into outer ones, the innermost first. */
	for (NSDictionary *group in [[self groups] reverseObjectEnumerator]) {
		NSString *name = [group objectForKey:@"name"];
		NSArray *path = [group objectForKey:@"path"];
		NSString *above = [path count] > 1 ? [[path subarrayWithRange:NSMakeRange(0, [path count] - 1)] componentsJoinedByString:@"/"] : @"";
		NSMutableDictionary *inner = name != nil ? [bodies objectForKey:name] : nil;
		NSRelationshipDescription *relationship = [[[entities objectForKey:above] relationshipsByName] objectForKey:[path lastObject]];
		if ([inner count] > 0 && relationship != nil) {
			[[bodies objectForKey:above] setObject:inner forKey:[mapper propertyForRelationship:relationship]];
		}
	}
	if (problem != nil) {
		if (error != NULL) {
			*error = ORMFormError(problem);
		}
		return nil;
	}
	ORMFormRequest *request = [[ORMFormRequest alloc] init];
	NSString *set = [mapper entitySetForEntity:entity];
	request.method = isNew ? @"POST" : @"PATCH";
	request.path = isNew ? set : [NSString stringWithFormat:@"%@(%@)", set, [coder literalForValue:key attribute:keyAttribute]];
	NSMutableDictionary *headers = [NSMutableDictionary dictionaryWithObject:@"application/json" forKey:@"Content-Type"];
	if (!isNew && [etag length] > 0) {
		[headers setObject:etag forKey:@"If-Match"];
	}
	request.headers = headers;
	request.body = body;
	return request;
}

- (ORMFormRequest *)actionRequestFor:(NSDictionary<NSString *, id> *)instance
                               model:(NSManagedObjectModel *)model
                               error:(NSError **)error
{
	if (_action == nil) {
		if (error != NULL) {
			*error = ORMFormError([NSString stringWithFormat:@"%@ is submitted to no action.", _name ?: @"The form"]);
		}
		return nil;
	}
	ORMFormRequest *whole = [self saveRequestFor:instance original:nil etag:nil model:model error:error];
	if (whole == nil) {
		return nil;
	}
	ORMFormRequest *request = [[ORMFormRequest alloc] init];
	request.method = @"POST";
	request.path = _action;
	request.headers = @{ @"Content-Type" : @"application/json" };
	request.body = @{ _entityName : whole.body };
	return request;
}

/* A repeat's rows as the service is sent them: in a deep insert, each;
 * in a deep update's delta, each new one (given a key where the key is a
 * UUID or text), each changed one with its key and what differs, and each
 * the rows no longer have, removed as deleted. */
- (NSArray *)rowBodiesOf:(NSArray *)rows was:(NSArray *)was model:(NSManagedObjectModel *)model new:(BOOL)allNew error:(NSError **)error
{
	NSEntityDescription *entity = [[model entitiesByName] objectForKey:_entityName];
	NSAttributeDescription *keyAttribute = [[entity attributesByName] objectForKey:_keyElement ?: @""];
	ODataPropertyMapper *mapper = [[ODataPropertyMapper alloc] init];
	ODataValueCoder *coder = mapper.values ?: [[ODataValueCoder alloc] init];
	NSMutableDictionary *before = [NSMutableDictionary dictionary];
	for (NSDictionary *row in was) {
		NSString *key = [[row objectForKey:_keyElement ?: @""] description];
		if ([key length] > 0) {
			[before setObject:row forKey:key];
		}
	}
	NSMutableArray *sent = [NSMutableArray array];
	NSMutableSet *kept = [NSMutableSet set];
	for (NSDictionary *each in rows) {
		NSMutableDictionary *row = [each mutableCopy];
		NSString *key = [[row objectForKey:_keyElement ?: @""] description];
		NSDictionary *original = [key length] > 0 && !allNew ? [before objectForKey:key] : nil;
		if ([key length] == 0 && ([keyAttribute attributeType] == NSUUIDAttributeType || [keyAttribute attributeType] == NSStringAttributeType)) {
			[row setObject:[[NSUUID UUID] UUIDString] forKey:_keyElement];
		}
		if (original != nil) {
			[kept addObject:key];
		}
		ORMFormRequest *request = [self saveRequestFor:row original:original etag:nil model:model error:error];
		if (request == nil) {
			return nil;
		}
		NSMutableDictionary *body = [request.body mutableCopy];
		if (original != nil) {
			/* Changed: named by its key; unchanged, not sent. */
			if ([body count] == 0) {
				continue;
			}
			NSString *problem = nil;
			id typed = ORMFormValue(key, keyAttribute, &problem);
			if (typed != nil) {
				[body setObject:[coder JSONForCoreDataValue:typed attribute:keyAttribute] forKey:[mapper propertyForAttribute:keyAttribute]];
			}
		}
		[sent addObject:body];
	}
	for (NSString *key in before) {
		if ([kept containsObject:key]) {
			continue;
		}
		NSString *problem = nil;
		id typed = ORMFormValue(key, keyAttribute, &problem);
		NSString *literal = typed != nil ? [coder literalForValue:typed attribute:keyAttribute] : key;
		[sent addObject:@{ @"@removed" : @{ @"reason" : @"deleted" },
		                   @"@id" : [NSString stringWithFormat:@"%@(%@)", [mapper entitySetForEntity:entity], literal] }];
	}
	return sent;
}

- (NSDictionary<NSString *, NSString *> *)elementErrorsOfResponse:(NSData *)body model:(NSManagedObjectModel *)model
{
	id json = body != nil ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
	NSDictionary *error = [json isKindOfClass:[NSDictionary class]] ? [json objectForKey:@"error"] : nil;
	if (![error isKindOfClass:[NSDictionary class]]) {
		return @{ @"": @"The service refused the form." };
	}
	NSEntityDescription *entity = [[model entitiesByName] objectForKey:_entityName];
	ODataPropertyMapper *mapper = [[ODataPropertyMapper alloc] init];
	NSMutableDictionary *errors = [NSMutableDictionary dictionary];
	NSArray *details = [[error objectForKey:@"details"] isKindOfClass:[NSArray class]] ? [error objectForKey:@"details"] : @[];
	/* The error's own message, where no detail names a target. */
	NSArray *each = [details count] > 0 ? details : @[ error ];
	for (NSDictionary *one in each) {
		if (![one isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		NSString *target = [[one objectForKey:@"target"] isKindOfClass:[NSString class]] ? [one objectForKey:@"target"] : nil;
		NSString *wire = [[target componentsSeparatedByString:@"/"] firstObject];
		NSPropertyDescription *property = wire != nil && entity != nil ? [mapper propertyForWireName:wire entity:entity] : nil;
		NSString *name = property != nil && [self elementNamed:[property name]] != nil ? [property name] : @"";
		NSString *message = [[one objectForKey:@"message"] isKindOfClass:[NSString class]] ? [one objectForKey:@"message"] : @"";
		NSString *said = [errors objectForKey:name];
		[errors setObject:said != nil ? [NSString stringWithFormat:@"%@ %@", said, message] : message forKey:name];
	}
	return errors;
}

@end
