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
@end

@implementation ORMFormElement
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

#pragma mark The table

@implementation ORMForm
{
	NSDictionary *_list;
	NSDictionary<NSString *, ORMQueryPlan *> *_allChoices;
	NSDictionary<NSString *, ORMQueryPlan *> *_choicesBy;
	NSDictionary<NSString *, NSArray<NSString *> *> *_dependsOn;
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
	return YES;
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

- (ORMQueryPlan *)choicesPlanNamed:(NSString *)name values:(NSDictionary<NSString *, NSString *> *)values error:(NSError **)error
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

- (NSDictionary<NSString *, NSString *> *)instanceGiven:(NSDictionary<NSString *, NSString *> *)values
{
	NSMutableDictionary *instance = [NSMutableDictionary dictionary];
	for (ORMFormElement *element in _elements) {
		[instance setObject:[values objectForKey:element.name] ?: @"" forKey:element.name];
	}
	return instance;
}

- (NSDictionary<NSString *, NSString *> *)instanceOfRow:(NSArray *)row
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

- (NSDictionary<NSString *, NSString *> *)readKey:(NSString *)key
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
	return [self instanceOfRow:[result.rows firstObject]];
}

- (NSArray<NSString *> *)choicesNamed:(NSString *)name
                               values:(NSDictionary<NSString *, NSString *> *)values
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

- (NSManagedObject *)save:(NSDictionary<NSString *, NSString *> *)instance
                inContext:(NSManagedObjectContext *)context
                   errors:(NSDictionary<NSString *, NSString *> **)errors
                    error:(NSError **)error
{
	return [self save:instance inContext:context saving:nil errors:errors error:error];
}

- (NSManagedObject *)save:(NSDictionary<NSString *, NSString *> *)instance
                inContext:(NSManagedObjectContext *)context
                   saving:(BOOL (^)(NSManagedObjectContext *context, NSError **error))saving
                   errors:(NSDictionary<NSString *, NSString *> **)errors
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
	NSMutableDictionary *problems = [NSMutableDictionary dictionary];
	NSString *problem = nil;
	id key = ORMFormValue([instance objectForKey:_keyElement] ?: @"", keyAttribute, &problem);
	NSManagedObject *object = key != nil ? ORMFormFind(entity, _keyElement, key, context) : nil;
	BOOL made = object == nil;
	if (made) {
		object = [NSEntityDescription insertNewObjectForEntityForName:_entityName inManagedObjectContext:context];
		if (keyAttribute != nil) {
			[object setValue:key ?: ORMFormNewKey(entity, keyAttribute, context) forKey:_keyElement];
		}
	}
	/* What it had, to put back where it is refused. */
	NSMutableDictionary *before = [NSMutableDictionary dictionary];
	for (ORMFormElement *element in _elements) {
		if (!element.written) {
			continue;
		}
		NSString *text = [instance objectForKey:element.name] ?: @"";
		id value = nil;
		problem = nil;
		if ([element.kind isEqualToString:@"reference"]) {
			NSRelationshipDescription *relationship = [[entity relationshipsByName] objectForKey:element.name];
			NSEntityDescription *destination = [relationship destinationEntity];
			NSAttributeDescription *destinationKey = [[destination attributesByName] objectForKey:element.keyName ?: @""];
			id typed = ORMFormValue(text, destinationKey, &problem);
			value = typed != nil ? ORMFormFind(destination, element.keyName, typed, context) : nil;
			if (relationship == nil || (typed != nil && value == nil)) {
				problem = problem ?: [NSString stringWithFormat:@"There is no %@ %@.", [destination name] ?: element.entityName, text];
			}
		} else {
			NSAttributeDescription *attribute = [[entity attributesByName] objectForKey:element.name];
			value = attribute != nil ? ORMFormValue(text, attribute, &problem) : nil;
			problem = attribute == nil ? [NSString stringWithFormat:@"%@ has no %@.", _entityName, element.name] : problem;
		}
		if (problem != nil) {
			[problems setObject:problem forKey:element.name];
			continue;
		}
		[before setObject:[object valueForKey:element.name] ?: [NSNull null] forKey:element.name];
		[object setValue:value forKey:element.name];
	}
	NSError *failure = nil;
	if ([problems count] == 0 && (saving != nil ? saving(context, &failure) : [context save:&failure])) {
		return object;
	}
	if ([problems count] == 0) {
		[problems addEntriesFromDictionary:[self elementErrorsOf:failure]];
	}
	/* Refused: the object as it was. */
	if (made) {
		[context deleteObject:object];
		/* Gone now, its relationships' other ends too, before anything else
		 * is done with the context (a rollback). */
		[context processPendingChanges];
	} else {
		for (NSString *name in before) {
			id value = [before objectForKey:name];
			[object setValue:value == [NSNull null] ? nil : value forKey:name];
		}
	}
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

- (NSDictionary<NSString *, NSString *> *)elementErrorsOf:(NSError *)error
{
	NSMutableDictionary *errors = [NSMutableDictionary dictionary];
	NSArray *each = [[error userInfo] objectForKey:NSDetailedErrorsKey] ?: (error != nil ? @[ error ] : @[]);
	for (NSError *one in each) {
		NSString *key = [[one userInfo] objectForKey:NSValidationKeyErrorKey];
		NSString *name = key != nil && [self elementNamed:key] != nil ? key : @"";
		NSString *said = [errors objectForKey:name];
		NSString *message = ORMFormMessage(one);
		[errors setObject:said != nil ? [NSString stringWithFormat:@"%@ %@", said, message] : message forKey:name];
	}
	return errors;
}

#pragma mark The service

- (ORMQueryOData *)readRequestForKey:(NSString *)key model:(NSManagedObjectModel *)model error:(NSError **)error
{
	ORMQueryPlan *plan = [_readPlan planBinding:@{ _keyElement ?: @"": key ?: @"" } error:error];
	return plan != nil ? [ORMQueryOData requestForPlan:plan model:model error:error] : nil;
}

- (ORMQueryOData *)choicesRequestNamed:(NSString *)name
                                values:(NSDictionary<NSString *, NSString *> *)values
                                 model:(NSManagedObjectModel *)model
                                 error:(NSError **)error
{
	ORMQueryPlan *plan = [self choicesPlanNamed:name values:values error:error];
	return plan != nil ? [ORMQueryOData requestForPlan:plan model:model error:error] : nil;
}

- (ORMFormRequest *)saveRequestFor:(NSDictionary<NSString *, NSString *> *)instance
                          original:(NSDictionary<NSString *, NSString *> *)original
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
	/* One type of several in its set (a FillUp among the Records): named, so
	 * that the service knows whose properties these are. */
	NSString *type = [mapper entityIsDerivedInItsSet:entity] ? [mapper qualifiedTypeForEntity:entity] : nil;
	if (type != nil) {
		[body setObject:[@"#" stringByAppendingString:type] forKey:@"@odata.type"];
	}
	for (ORMFormElement *element in _elements) {
		NSString *text = [instance objectForKey:element.name] ?: @"";
		/* New: what it has; changed: what differs, an emptied one as null. */
		if (!element.written || (isNew && [text length] == 0)
		    || (!isNew && [text isEqualToString:[original objectForKey:element.name] ?: @""])) {
			continue;
		}
		if ([element.kind isEqualToString:@"reference"]) {
			NSRelationshipDescription *relationship = [[entity relationshipsByName] objectForKey:element.name];
			NSEntityDescription *destination = [relationship destinationEntity];
			NSAttributeDescription *destinationKey = [[destination attributesByName] objectForKey:element.keyName ?: @""];
			id typed = ORMFormValue(text, destinationKey, &problem);
			if (relationship == nil || problem != nil) {
				problem = problem ?: [NSString stringWithFormat:@"%@ has no %@.", _entityName, element.name];
				break;
			}
			NSString *bind = [[mapper propertyForRelationship:relationship] stringByAppendingString:@"@odata.bind"];
			[body setObject:typed != nil ? [NSString stringWithFormat:@"%@(%@)", [mapper entitySetForEntity:destination],
			                                                         [coder literalForValue:typed attribute:destinationKey]]
			                             : [NSNull null]
			         forKey:bind];
			continue;
		}
		NSAttributeDescription *attribute = [[entity attributesByName] objectForKey:element.name];
		id typed = ORMFormValue(text, attribute, &problem);
		if (attribute == nil || problem != nil) {
			problem = problem ?: [NSString stringWithFormat:@"%@ has no %@.", _entityName, element.name];
			break;
		}
		[body setObject:typed != nil ? [coder JSONForCoreDataValue:typed attribute:attribute] : [NSNull null]
		         forKey:[mapper propertyForAttribute:attribute]];
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
