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
@property (nonatomic, readwrite, copy) NSString *role;
@property (nonatomic, readwrite) BOOL given;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *items;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *itemLabels;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *path;
@property (nonatomic, readwrite, copy) NSString *group;
@property (nonatomic, readwrite, copy) NSString *subtype;
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

/* What an error says of a property, for the user (below). */
static NSString *ORMFormMessage(NSError *error);

#pragma mark The table

@implementation ORMForm
{
	NSDictionary *_list;
	NSDictionary<NSString *, ORMQueryPlan *> *_allChoices;
	NSDictionary<NSString *, ORMQueryPlan *> *_choicesBy;
	NSDictionary<NSString *, NSArray<NSString *> *> *_dependsOn;
	NSDictionary<NSString *, ORMForm *> *_repeats;
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
		element.given = [[item objectForKey:@"given"] boolValue];
		element.label = [item objectForKey:@"label"] ?: element.name;
		element.items = [[item objectForKey:@"items"] isKindOfClass:[NSArray class]] ? [item objectForKey:@"items"] : nil;
		NSArray *labels = [item objectForKey:@"itemLabels"];
		element.itemLabels = [labels isKindOfClass:[NSArray class]] && [labels count] == [element.items count] ? labels : nil;
		element.path = [[item objectForKey:@"path"] isKindOfClass:[NSArray class]] ? [item objectForKey:@"path"] : nil;
		element.group = [[item objectForKey:@"group"] isKindOfClass:[NSString class]] ? [item objectForKey:@"group"] : nil;
		element.subtype = [[item objectForKey:@"subtype"] isKindOfClass:[NSString class]] ? [item objectForKey:@"subtype"] : nil;
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
	NSDictionary *choices = [list objectForKey:@"choices"] ?: @{};
	for (NSString *name in choices) {
		NSDictionary *choice = [choices objectForKey:name];
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
	_dependsOn = dependsOn;
	_checkedWhereSubmitted = [[list objectForKey:@"checkedWhereSubmitted"] copy] ?: @[];
	_linkElement = [[list objectForKey:@"link"] copy];
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
	return instance;
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
	NSMutableDictionary *instance = [[self instanceOfRow:[result.rows firstObject]] mutableCopy];
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
		NSArray *rows = [[_repeats objectForKey:name] rowsLinkedTo:key inContext:context error:error];
		if (rows == nil) {
			return nil;
		}
		[instance setObject:rows forKey:name];
	}
	return instance;
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
		ORMFormElement *reference = element.group == nil && [element.path count] > 1 ? [self elementNamed:[element.path firstObject]] : nil;
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

- (NSManagedObject *)save:(NSDictionary<NSString *, id> *)instance
                inContext:(NSManagedObjectContext *)context
                   saving:(BOOL (^)(NSManagedObjectContext *context, NSError **error))saving
                   errors:(NSDictionary<NSString *, NSString *> **)errors
                    error:(NSError **)error
{
	NSMutableDictionary *problems = [NSMutableDictionary dictionary];
	NSMutableDictionary *before = [NSMutableDictionary dictionary];
	BOOL made = NO;
	NSMutableArray<NSDictionary *> *owned = [NSMutableArray array];
	NSManagedObject *object = [self write:instance inContext:context problems:problems prefix:@"" before:before made:&made
	                                owned:owned error:error];
	if (object == nil) {
		return nil;
	}
	/* Each repeat's rows written into their objects, linked to this one;
	 * those it had and the rows no longer have, gone. A row's problem is
	 * said under "<repeat>[<index>].<element>". */
	NSString *keyText = ORMFormText([object valueForKey:_keyElement ?: @""], nil, nil);
	NSMutableArray *rowObjects = [NSMutableArray array], *rowBefores = [NSMutableArray array], *rowMade = [NSMutableArray array];
	NSMutableDictionary<NSValue *, NSString *> *rowPrefixes = [NSMutableDictionary dictionary];
	for (NSString *name in [self repeatNames]) {
		NSArray *rows = (NSArray *)[(NSDictionary *)instance objectForKey:name];
		if (![rows isKindOfClass:[NSArray class]]) {
			continue;
		}
		ORMForm *repeat = [_repeats objectForKey:name];
		NSMutableSet *kept = [NSMutableSet set];
		for (NSUInteger i = 0; i < [rows count]; i++) {
			NSMutableDictionary *row = [[rows objectAtIndex:i] mutableCopy];
			[row setObject:keyText forKey:repeat.linkElement];
			NSString *prefix = [NSString stringWithFormat:@"%@[%lu].", name, (unsigned long)i];
			NSMutableDictionary *was = [NSMutableDictionary dictionary];
			BOOL rowWasMade = NO;
			NSManagedObject *rowObject = [repeat write:row inContext:context problems:problems prefix:prefix before:was
			                                     made:&rowWasMade owned:owned error:error];
			if (rowObject == nil) {
				return nil;
			}
			[kept addObject:rowObject];
			[rowObjects addObject:rowObject];
			[rowBefores addObject:was];
			[rowMade addObject:@(rowWasMade)];
			[rowPrefixes setObject:prefix forKey:[NSValue valueWithNonretainedObject:rowObject]];
		}
		NSFetchRequest *linked = [NSFetchRequest fetchRequestWithEntityName:repeat.entityName];
		[linked setPredicate:[NSPredicate predicateWithFormat:@"%K == %@", repeat.linkElement, object]];
		for (NSManagedObject *gone in [context executeFetchRequest:linked error:NULL]) {
			if (![kept containsObject:gone]) {
				[context deleteObject:gone];
			}
		}
	}
	NSError *failure = nil;
	if ([problems count] == 0 && (saving != nil ? saving(context, &failure) : [context save:&failure])) {
		return object;
	}
	if ([problems count] == 0) {
		NSArray *each = [[failure userInfo] objectForKey:NSDetailedErrorsKey] ?: (failure != nil ? @[ failure ] : @[]);
		for (NSError *one in each) {
			id about = [[one userInfo] objectForKey:NSValidationObjectErrorKey];
			NSString *prefix = about != nil ? [rowPrefixes objectForKey:[NSValue valueWithNonretainedObject:about]] : nil;
			/* An owned object's, at its group's element of the property. */
			NSString *group = nil;
			for (NSDictionary *each in owned) {
				group = [each objectForKey:@"object"] == about ? [each objectForKey:@"group"] ?: group : group;
			}
			if (prefix == nil && group != nil) {
				NSString *key = [[one userInfo] objectForKey:NSValidationKeyErrorKey];
				NSString *element = key != nil ? [NSString stringWithFormat:@"%@/%@", group, key] : @"";
				element = [self elementNamed:element] != nil ? element : @"";
				NSString *said = [problems objectForKey:element];
				NSString *message = ORMFormMessage(one);
				[problems setObject:said != nil ? [NSString stringWithFormat:@"%@ %@", said, message] : message forKey:element];
				continue;
			}
			if (prefix == nil) {
				[self addErrorsOf:one to:problems];
				continue;
			}
			ORMForm *repeat = nil;
			for (NSString *name in _repeats) {
				if ([prefix hasPrefix:[name stringByAppendingString:@"["]]) {
					repeat = [_repeats objectForKey:name];
				}
			}
			NSString *element = [repeat elementOfError:one];
			NSString *at = [element length] > 0 ? [prefix stringByAppendingString:element] : @"";
			NSString *said = [problems objectForKey:at];
			NSString *message = ORMFormMessage(one);
			[problems setObject:said != nil ? [NSString stringWithFormat:@"%@ %@", said, message] : message forKey:at];
		}
	}
	/* Refused: the objects as they were. */
	for (NSUInteger i = [rowObjects count]; i > 0; i--) {
		ORMFormPutBack([rowObjects objectAtIndex:i - 1], [[rowMade objectAtIndex:i - 1] boolValue], [rowBefores objectAtIndex:i - 1], context);
	}
	for (NSUInteger i = [owned count]; i > 0; i--) {
		NSDictionary *each = [owned objectAtIndex:i - 1];
		ORMFormPutBack([each objectForKey:@"object"], [[each objectForKey:@"made"] boolValue], [each objectForKey:@"before"], context);
	}
	ORMFormPutBack(object, made, before, context);
	if (errors != NULL) {
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
	NSString *message = ORMFormMessage(one);
	[errors setObject:said != nil ? [NSString stringWithFormat:@"%@ %@", said, message] : message forKey:name];
}

#pragma mark The service

- (ORMQueryOData *)readRequestForKey:(NSString *)key model:(NSManagedObjectModel *)model error:(NSError **)error
{
	ORMQueryPlan *plan = [_readPlan planBinding:@{ _keyElement ?: @"": key ?: @"" } error:error];
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
