/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFormSession.h"
#import "ORMForm.h"
#import "ORMQueryOData.h"
#import <CoreData/CoreData.h>
#import <ODataKit/ODataTransport.h>

/* Until done says so, the current run loop turning meanwhile. */
static void
ORMFormWait(BOOL (^done)(void))
{
	while (!done()) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
	}
}

/* A value of the service's JSON, or the store's, as the values have it: an
 * object's (a reference's) by its key. */
static NSString *
ORMFormText(id value, NSString *keyName)
{
	if ([value isKindOfClass:[NSArray class]]) {
		return ORMFormText([value firstObject], keyName);
	}
	if ([value isKindOfClass:[NSDictionary class]]) {
		for (NSString *name in value) {
			if ([name caseInsensitiveCompare:keyName ?: @""] == NSOrderedSame) {
				return ORMFormText([value objectForKey:name], nil);
			}
		}
		return @"";
	}
	if ([value isKindOfClass:[NSString class]]) {
		return value;
	}
	if ([value isKindOfClass:[NSUUID class]]) {
		return [value UUIDString];
	}
	if ([value respondsToSelector:@selector(stringValue)]) {
		return [value stringValue];
	}
	return @"";
}

static NSError *
ORMFormSessionError(NSString *text)
{
	return [NSError errorWithDomain:ORMFormErrorDomain code:2 userInfo:@{ NSLocalizedDescriptionKey : text }];
}

@implementation ORMFormSession {
	NSManagedObjectContext *_context;
	BOOL (^_saving)(NSManagedObjectContext *, NSError **);
	NSURL *_root;
	NSManagedObjectModel *_model;
	id<ODataTransport> _transport;
	NSMutableDictionary<NSString *, id> *_values;
	/* The object as the service gave it, to change no more of it than was
	 * changed, and its version (If-Match). */
	NSDictionary<NSString *, id> *_original;
	NSString *_etag;
	NSDictionary<NSString *, NSString *> *_errors;
	NSString *_savedKey;
	/* Each other anchor's, by its form's name. */
	NSMutableDictionary<NSString *, NSMutableDictionary *> *_partValues;
	NSMutableDictionary<NSString *, NSString *> *_partKeys;
	NSMutableDictionary<NSString *, NSDictionary *> *_partOriginals;
	NSMutableDictionary<NSString *, NSString *> *_partEtags;
	NSMutableDictionary<NSString *, NSString *> *_partSavedKeys;
}

- (instancetype)initWithForm:(ORMForm *)form given:(NSDictionary<NSString *, NSString *> *)given
{
	if ((self = [super init])) {
		_form = form;
		_given = [given copy] ?: @{};
		_values = [[form instanceGiven:_given] mutableCopy];
		_errors = @{};
		_partValues = [NSMutableDictionary dictionary];
		_partKeys = [NSMutableDictionary dictionary];
		_partOriginals = [NSMutableDictionary dictionary];
		_partEtags = [NSMutableDictionary dictionary];
		_partSavedKeys = [NSMutableDictionary dictionary];
		for (ORMForm *part in form.parts) {
			[_partValues setObject:[[part instanceGiven:_given] mutableCopy] forKey:part.name ?: @""];
		}
	}
	return self;
}

- (void)useContext:(NSManagedObjectContext *)context saving:(BOOL (^)(NSManagedObjectContext *, NSError **))saving
{
	_context = context;
	_saving = [saving copy];
	_root = nil;
}

- (void)useServiceRoot:(NSURL *)root model:(NSManagedObjectModel *)model transport:(id<ODataTransport>)transport
{
	_root = root;
	_model = model;
	_transport = transport ?: ODataDefaultTransport();
	_context = nil;
}

#pragma mark The values

- (NSDictionary<NSString *, id> *)values
{
	return [_values copy];
}

- (NSString *)valueForElement:(NSString *)name
{
	return [_values objectForKey:name] ?: @"";
}

- (void)setValue:(NSString *)value forElement:(NSString *)name
{
	[_values setObject:value ?: @"" forKey:name];
	/* A value that finds a reference's object (an order's customer, by
	 * email): found now, and what is shown through it read. */
	NSString *identifies = [_form elementNamed:name].identifies;
	if (identifies != nil) {
		NSString *key = [self identifiedKeyNamed:identifies error:NULL];
		[_values setObject:key ?: @"" forKey:identifies];
	}
	if ([[_form elementNamed:name].kind isEqualToString:@"reference"] || identifies != nil) {
		[self readThrough];
	}
}

/* The key of the object the values find, from the store or the service; ""
 * for none; nil, and why, where it cannot be read. */
- (NSString *)identifiedKeyNamed:(NSString *)name error:(NSError **)error
{
	return [self identifiedKeyNamed:name form:_form values:_values error:error];
}

/* The same for one of the anchors and its values. */
- (NSString *)identifiedKeyNamed:(NSString *)name form:(ORMForm *)form values:(NSDictionary *)values error:(NSError **)error
{
	if (_context != nil) {
		return [form identifiedKeyNamed:name values:values inContext:_context error:error];
	}
	BOOL none = YES;
	for (NSString *each in [form elementsIdentifying:name]) {
		none = none && [[[values objectForKey:each] description] length] == 0;
	}
	if (none) {
		return @"";
	}
	ORMQueryOData *request = [form identifyRequestNamed:name values:values model:_model error:error];
	NSArray *rows = request != nil ? [self rowsOf:request objects:NULL error:error] : nil;
	if (rows == nil) {
		return nil;
	}
	return ORMFormText([[rows firstObject] firstObject], [form elementNamed:name].keyName);
}

/* What is shown through the references (an order's supplier's name), as
 * their objects have it now; against the service, as it was read. */
- (void)readThrough
{
	if (_context == nil) {
		return;
	}
	[_values addEntriesFromDictionary:[_form throughValuesOf:_values inContext:_context]];
}

- (void)setValues:(NSDictionary<NSString *, id> *)values
{
	_values = [values mutableCopy] ?: [NSMutableDictionary dictionary];
}

- (NSDictionary<NSString *, NSString *> *)errors
{
	return _errors;
}

- (NSString *)savedKey
{
	return _savedKey;
}

- (BOOL)open:(NSError **)error
{
	_original = nil;
	_etag = nil;
	if ([_key length] == 0) {
		_values = [[_form instanceGiven:_given] mutableCopy];
		[self readThrough];
		return [self openParts:error];
	}
	NSDictionary *read = _context != nil ? [_form readKey:_key inContext:_context error:error] : [self readFromService:_key error:error];
	if (read == nil) {
		return NO;
	}
	_original = _context != nil ? nil : read;
	_values = [read mutableCopy];
	return [self openParts:error];
}

#pragma mark Its other anchors

- (ORMForm *)partNamed:(NSString *)name
{
	for (ORMForm *part in _form.parts) {
		if ([part.name isEqualToString:name]) {
			return part;
		}
	}
	return nil;
}

- (void)setKey:(NSString *)key ofForm:(NSString *)name
{
	if (key != nil) {
		[_partKeys setObject:[key copy] forKey:name];
	} else {
		[_partKeys removeObjectForKey:name];
	}
}

- (NSDictionary<NSString *, id> *)valuesOfForm:(NSString *)name
{
	return [[_partValues objectForKey:name] copy];
}

- (void)setValue:(NSString *)value forElement:(NSString *)element ofForm:(NSString *)name
{
	[[_partValues objectForKey:name] setObject:value ?: @"" forKey:element];
}

- (NSString *)savedKeyOfForm:(NSString *)name
{
	return [_partSavedKeys objectForKey:name];
}

/* Each other anchor's values read: its object's, or a new one's, the
 * inputs in it. */
- (BOOL)openParts:(NSError **)error
{
	for (ORMForm *part in _form.parts) {
		NSString *key = [_partKeys objectForKey:part.name ?: @""];
		NSDictionary *read = [key length] == 0 ? [part instanceGiven:_given]
			: _context != nil ? [part readKey:key inContext:_context error:error] : [self readFromService:key form:part error:error];
		if (read == nil) {
			return NO;
		}
		if (_context == nil && [key length] > 0) {
			[_partOriginals setObject:read forKey:part.name ?: @""];
		}
		[_partValues setObject:[read mutableCopy] forKey:part.name ?: @""];
	}
	return YES;
}

/* Every anchor saved as one to the service: a $batch of one change set,
 * each anchor's request in it; refused, by each one's elements. */
- (BOOL)saveAnchorsToService:(NSError **)error
{
	NSArray<ORMForm *> *forms = [@[ _form ] arrayByAddingObjectsFromArray:_form.parts];
	NSMutableArray *requests = [NSMutableArray array];
	NSMutableDictionary *unfound = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [forms count]; i++) {
		ORMForm *form = [forms objectAtIndex:i];
		NSMutableDictionary *values = i == 0 ? _values : [_partValues objectForKey:form.name ?: @""];
		/* What values entered find, asked of the service first. */
		for (NSString *name in [form identifiedNames]) {
			NSString *key = [self identifiedKeyNamed:name form:form values:values error:error];
			if (key == nil) {
				return NO;
			}
			[values setObject:key forKey:name];
			NSString *first = [[form elementsIdentifying:name] firstObject];
			if ([key length] == 0 && first != nil && [[[values objectForKey:first] description] length] > 0) {
				[unfound setObject:[form unfoundMessageNamed:name] forKey:i == 0 ? first : [NSString stringWithFormat:@"%@/%@", form.name, first]];
			}
		}
	}
	if ([unfound count] > 0) {
		_errors = unfound;
		return NO;
	}
	for (NSUInteger i = 0; i < [forms count]; i++) {
		ORMForm *form = [forms objectAtIndex:i];
		NSDictionary *values = i == 0 ? _values : [_partValues objectForKey:form.name ?: @""];
		NSDictionary *original = i == 0 ? _original : [_partOriginals objectForKey:form.name ?: @""];
		NSString *etag = i == 0 ? _etag : [_partEtags objectForKey:form.name ?: @""];
		ORMFormRequest *request = [form saveRequestFor:values original:original etag:etag model:_model error:error];
		if (request == nil) {
			return NO;
		}
		[requests addObject:@{ @"id" : [NSString stringWithFormat:@"%lu", (unsigned long)i + 1], @"atomicityGroup" : @"anchors",
		                       @"method" : request.method, @"url" : request.path, @"headers" : request.headers,
		                       @"body" : request.body }];
	}
	NSMutableURLRequest *http = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"$batch" relativeToURL:_root]];
	http.HTTPMethod = @"POST";
	http.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{ @"requests" : requests } options:0 error:NULL];
	[http setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[http setValue:@"application/json" forHTTPHeaderField:@"Accept"];
	ODataExchange *exchange = [[ODataExchange alloc] initWithRequest:http target:nil action:NULL];
	[_transport startExchange:exchange];
	ORMFormWait(^BOOL { return exchange.isFinished; });
	NSInteger status = [(NSHTTPURLResponse *)exchange.URLResponse statusCode];
	id answer = exchange.data != nil ? [NSJSONSerialization JSONObjectWithData:exchange.data options:0 error:NULL] : nil;
	NSArray *responses = [answer isKindOfClass:[NSDictionary class]] ? [answer objectForKey:@"responses"] : nil;
	if (exchange.error != nil || status == 0 || (status >= 400 && ![responses isKindOfClass:[NSArray class]])) {
		if (status >= 400) {
			_errors = [_form elementErrorsOfResponse:exchange.data ?: [NSData data] model:_model];
			return NO;
		}
		if (error != NULL) {
			*error = exchange.error ?: ORMFormSessionError(@"The service did not answer.");
		}
		return NO;
	}
	NSMutableDictionary *errors = [NSMutableDictionary dictionary];
	NSMutableArray *keys = [NSMutableArray array];
	for (NSUInteger i = 0; i < [forms count]; i++) {
		ORMForm *form = [forms objectAtIndex:i];
		NSDictionary *response = nil;
		for (NSDictionary *each in [responses isKindOfClass:[NSArray class]] ? responses : @[]) {
			response = [[[each objectForKey:@"id"] description] isEqualToString:[NSString stringWithFormat:@"%lu", (unsigned long)i + 1]] ? each : response;
		}
		NSInteger code = [[response objectForKey:@"status"] integerValue];
		id body = [response objectForKey:@"body"];
		if (code >= 400 || response == nil) {
			NSData *data = body != nil ? [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL] : nil;
			NSDictionary *said = data != nil ? [form elementErrorsOfResponse:data model:_model]
			                                 : @{ @"" : @"The service refused it." };
			[said enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *text, BOOL *stop) {
				[errors setObject:text forKey:i == 0 ? key : [NSString stringWithFormat:@"%@/%@", form.name ?: @"", key]];
			}];
			[keys addObject:@""];
			continue;
		}
		NSDictionary *values = i == 0 ? _values : [_partValues objectForKey:form.name ?: @""];
		NSString *key = [values objectForKey:form.keyElement];
		if ([key length] == 0 && body != nil) {
			key = ORMFormText(body, form.keyElement);
		}
		[keys addObject:key ?: @""];
	}
	if ([errors count] > 0) {
		_errors = errors;
		return NO;
	}
	for (NSUInteger i = 0; i < [forms count]; i++) {
		ORMForm *form = [forms objectAtIndex:i];
		NSString *key = [keys objectAtIndex:i];
		NSDictionary *read = [key length] > 0 ? [self readFromService:key form:form error:NULL] : nil;
		if (i == 0) {
			_savedKey = key;
			_original = read;
			if (read != nil) {
				_values = [read mutableCopy];
			}
		} else {
			[_partSavedKeys setObject:key forKey:form.name ?: @""];
			if (read != nil) {
				[_partOriginals setObject:read forKey:form.name ?: @""];
				[_partValues setObject:[read mutableCopy] forKey:form.name ?: @""];
			}
		}
	}
	return YES;
}

#pragma mark The service

/* Every row the request reads from the service, and its objects. */
- (NSArray<NSArray *> *)rowsOf:(ORMQueryOData *)request objects:(NSArray **)objects error:(NSError **)error
{
	ORMQueryODataCursor *cursor = [request cursorWithTransport:_transport serviceRoot:_root];
	NSMutableArray *rows = [NSMutableArray array], *read = [NSMutableArray array];
	__block NSError *failure = nil;
	while (!cursor.atEnd && failure == nil) {
		__block BOOL done = NO;
		[cursor nextPage:100 completion:^(ORMQueryResult *page, NSError *pageError) {
			[rows addObjectsFromArray:page.rows ?: @[]];
			[read addObjectsFromArray:page.objects ?: @[]];
			failure = page != nil ? nil : pageError;
			done = YES;
		}];
		ORMFormWait(^BOOL { return done; });
	}
	if (failure != nil) {
		if (error != NULL) {
			*error = failure;
		}
		return nil;
	}
	if (objects != NULL) {
		*objects = read;
	}
	return rows;
}

- (NSDictionary<NSString *, id> *)readFromService:(NSString *)key error:(NSError **)error
{
	return [self readFromService:key form:_form error:error];
}

/* The object of the key as the form reads it from the service: its row,
 * what is read on its own, its repeats' rows; the form's own ETag kept. */
- (NSDictionary<NSString *, id> *)readFromService:(NSString *)key form:(ORMForm *)theForm error:(NSError **)error
{
	ORMQueryOData *request = [theForm readRequestForKey:key model:_model error:error];
	NSArray *objects = nil;
	NSArray *rows = request != nil ? [self rowsOf:request objects:&objects error:error] : nil;
	if (rows == nil) {
		return nil;
	}
	if ([rows count] == 0) {
		if (error != NULL) {
			*error = ORMFormSessionError([NSString stringWithFormat:@"There is no %@ %@.", theForm.entityName, key]);
		}
		return nil;
	}
	id object = [objects firstObject];
	NSString *etag = [object isKindOfClass:[NSDictionary class]] ? [object objectForKey:@"@odata.etag"] : nil;
	if (theForm == _form) {
		_etag = etag;
	} else if (etag != nil) {
		[_partEtags setObject:etag forKey:theForm.name ?: @""];
	}
	NSMutableDictionary *instance = [[theForm instanceOfRow:[rows firstObject]] mutableCopy];
	/* What is read on its own, by the key. */
	NSMutableDictionary *own = [NSMutableDictionary dictionary];
	for (ORMFormElement *element in theForm.elements) {
		if (element.read == nil) {
			continue;
		}
		ORMQueryPlan *plan = [element.read planBinding:@{ theForm.keyElement ?: @"" : key ?: @"" } error:error];
		ORMQueryOData *ownRequest = plan != nil ? [ORMQueryOData requestForPlan:plan model:_model error:error] : nil;
		NSArray *ownRows = ownRequest != nil ? [self rowsOf:ownRequest objects:NULL error:error] : nil;
		if (ownRows == nil) {
			return nil;
		}
		[own setObject:ownRows forKey:element.name];
	}
	instance = [[theForm instance:instance withOwnReads:own] mutableCopy];
	/* Each repeat's rows, linked to the anchor or to what the form reads
	 * the key of. */
	for (NSString *name in [theForm repeatNames]) {
		ORMForm *repeat = [theForm repeatNamed:name];
		NSString *linked = [theForm repeatFrom:name] != nil ? [[instance objectForKey:[theForm repeatFrom:name]] description] : key;
		NSMutableArray *found = [NSMutableArray array];
		if ([linked length] > 0) {
			ORMQueryOData *rowsRequest = [theForm rowsRequestOfRepeat:name linkedTo:linked model:_model error:error];
			NSArray *rowsRead = rowsRequest != nil ? [self rowsOf:rowsRequest objects:NULL error:error] : nil;
			if (rowsRead == nil) {
				return nil;
			}
			NSMutableSet *seen = [NSMutableSet set];
			for (NSArray *row in rowsRead) {
				NSDictionary *each = [repeat instanceOfRow:row];
				NSString *rowKey = [[each objectForKey:repeat.keyElement ?: @""] description] ?: @"";
				if ([rowKey length] == 0 || ![seen containsObject:rowKey]) {
					[seen addObject:rowKey];
					[found addObject:each];
				}
			}
		}
		[instance setObject:found forKey:name];
	}
	return [theForm instanceWithAggregates:instance];
}

#pragma mark Choices

- (NSArray<NSString *> *)choicesNamed:(NSString *)name error:(NSError **)error
{
	if ([_form elementNamed:name].items != nil) {
		return [_form elementNamed:name].items;
	}
	if (_context != nil) {
		return [_form choicesNamed:name values:_values inContext:_context error:error];
	}
	ORMQueryOData *request = [_form choicesRequestNamed:name values:_values model:_model error:error];
	NSArray *rows = request != nil ? [self rowsOf:request objects:NULL error:error] : nil;
	if (rows == nil) {
		return nil;
	}
	NSMutableArray *keys = [NSMutableArray array];
	for (NSArray *row in rows) {
		NSString *key = ORMFormText([row firstObject], [_form elementNamed:name].keyName);
		if ([key length] > 0 && ![keys containsObject:key]) {
			[keys addObject:key];
		}
	}
	return keys;
}

#pragma mark Saving

- (NSArray<NSDictionary<NSString *, NSString *> *> *)rowsOfRepeat:(NSString *)name
{
	NSArray *rows = [_values objectForKey:name];
	return [rows isKindOfClass:[NSArray class]] ? rows : @[];
}

- (void)setRows:(NSArray<NSDictionary<NSString *, NSString *> *> *)rows forRepeat:(NSString *)name
{
	[_values setObject:[rows copy] ?: @[] forKey:name];
	/* What is worked out over them (a total of the lines), again. */
	_values = [[_form instanceWithAggregates:_values] mutableCopy];
}

- (NSArray<NSString *> *)choicesNamed:(NSString *)name inRepeat:(NSString *)repeat row:(NSUInteger)row error:(NSError **)error
{
	ORMForm *form = [_form repeatNamed:repeat];
	if ([form elementNamed:name].items != nil) {
		return [form elementNamed:name].items;
	}
	NSArray *rows = [self rowsOfRepeat:repeat];
	NSDictionary *values = row < [rows count] ? [rows objectAtIndex:row] : @{};
	if (form == nil) {
		if (error != NULL) {
			*error = ORMFormSessionError([NSString stringWithFormat:@"The form has no repeat %@.", repeat]);
		}
		return nil;
	}
	if (_context != nil) {
		return [form choicesNamed:name values:values inContext:_context error:error];
	}
	ORMQueryOData *request = [form choicesRequestNamed:name values:values model:_model error:error];
	NSArray *rowsRead = request != nil ? [self rowsOf:request objects:NULL error:error] : nil;
	if (rowsRead == nil) {
		return nil;
	}
	NSMutableArray *keys = [NSMutableArray array];
	for (NSArray *each in rowsRead) {
		NSString *key = ORMFormText([each firstObject], [form elementNamed:name].keyName);
		if ([key length] > 0 && ![keys containsObject:key]) {
			[keys addObject:key];
		}
	}
	return keys;
}

- (BOOL)save:(NSError **)error
{
	_errors = @{};
	_savedKey = nil;
	if (_submitting != nil) {
		NSString *made = nil;
		NSDictionary *refused = _submitting([_values copy], &made);
		if ([refused count] > 0) {
			_errors = [refused copy];
			return NO;
		}
		_savedKey = [made copy] ?: [_values objectForKey:_form.keyElement];
		return YES;
	}
	if (_context != nil && [_form.parts count] > 0) {
		/* Every anchor, one save. */
		NSArray *forms = [@[ _form ] arrayByAddingObjectsFromArray:_form.parts];
		NSMutableArray *instances = [NSMutableArray arrayWithObject:_values];
		for (ORMForm *part in _form.parts) {
			[instances addObject:[_partValues objectForKey:part.name ?: @""] ?: @{}];
		}
		NSDictionary *errors = nil;
		NSError *failure = nil;
		NSArray *saved = [ORMForm saveForms:forms instances:instances inContext:_context saving:_saving errors:&errors error:&failure];
		if (saved == nil) {
			_errors = [errors count] > 0 ? errors : @{ @"" : failure.localizedDescription ?: @"Not saved." };
			return NO;
		}
		for (NSUInteger i = 0; i < [forms count]; i++) {
			ORMForm *form = [forms objectAtIndex:i];
			NSString *key = ORMFormText([[saved objectAtIndex:i] valueForKey:form.keyElement], nil);
			NSDictionary *read = [form readKey:key inContext:_context error:NULL];
			if (i == 0) {
				_savedKey = key;
				_values = read != nil ? [read mutableCopy] : _values;
			} else {
				[_partSavedKeys setObject:key forKey:form.name ?: @""];
				if (read != nil) {
					[_partValues setObject:[read mutableCopy] forKey:form.name ?: @""];
				}
			}
		}
		return YES;
	}
	if (_context == nil && [_form.parts count] > 0) {
		return [self saveAnchorsToService:error];
	}
	if (_context != nil) {
		NSDictionary *errors = nil;
		NSError *failure = nil;
		NSManagedObject *saved = [_form save:_values inContext:_context saving:_saving errors:&errors error:&failure];
		if (saved == nil) {
			_errors = [errors count] > 0 ? errors : @{ @"" : failure.localizedDescription ?: @"Not saved." };
			return NO;
		}
		_savedKey = ORMFormText([saved valueForKey:_form.keyElement], nil);
		NSDictionary *read = [_form readKey:_savedKey inContext:_context error:NULL];
		if (read != nil) {
			_values = [read mutableCopy];
		}
		return YES;
	}
	/* What values entered find, asked of the service first; none found,
	 * refused at the first of them. */
	NSMutableDictionary *unfound = [NSMutableDictionary dictionary];
	for (NSString *name in [_form identifiedNames]) {
		NSString *key = [self identifiedKeyNamed:name error:error];
		if (key == nil) {
			return NO;
		}
		[_values setObject:key forKey:name];
		NSString *first = [[_form elementsIdentifying:name] firstObject];
		if ([key length] == 0 && first != nil && [[[_values objectForKey:first] description] length] > 0) {
			[unfound setObject:[_form unfoundMessageNamed:name] forKey:first];
		}
	}
	if ([unfound count] > 0) {
		_errors = unfound;
		return NO;
	}
	/* Submitted to the form's action, or saved. */
	ORMFormRequest *save = _form.action != nil ? [_form actionRequestFor:_values model:_model error:error]
	                                           : [_form saveRequestFor:_values original:_original etag:_etag model:_model error:error];
	if (save == nil) {
		return NO;
	}
	NSMutableURLRequest *http = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:save.path relativeToURL:_root]];
	http.HTTPMethod = save.method;
	http.HTTPBody = [save bodyData];
	[save.headers enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSString *value, BOOL *stop) {
		[http setValue:value forHTTPHeaderField:name];
	}];
	[http setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	[http setValue:@"return=representation" forHTTPHeaderField:@"Prefer"];
	ODataExchange *exchange = [[ODataExchange alloc] initWithRequest:http target:nil action:NULL];
	[_transport startExchange:exchange];
	ORMFormWait(^BOOL { return exchange.isFinished; });
	NSInteger status = [(NSHTTPURLResponse *)exchange.URLResponse statusCode];
	if (exchange.error != nil || status == 0) {
		if (error != NULL) {
			*error = exchange.error ?: ORMFormSessionError(@"The service did not answer.");
		}
		return NO;
	}
	if (status >= 400) {
		NSDictionary *errors = [_form elementErrorsOfResponse:exchange.data ?: [NSData data] model:_model];
		_errors = [errors count] > 0 ? errors
		                             : @{ @"" : [NSString stringWithFormat:@"The service refused it (%ld).", (long)status] };
		return NO;
	}
	NSString *key = [_values objectForKey:_form.keyElement];
	id answer = exchange.data != nil ? [NSJSONSerialization JSONObjectWithData:exchange.data options:0 error:NULL] : nil;
	if (_form.action != nil) {
		/* The action's answer: the key of what it did, else the anchor's. */
		id value = [answer isKindOfClass:[NSDictionary class]] ? [answer objectForKey:@"value"] : nil;
		key = [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ? [value description] : key;
	} else if ([key length] == 0 && answer != nil) {
		key = ORMFormText(answer, _form.keyElement);
	}
	_savedKey = key;
	NSDictionary *read = [key length] > 0 ? [self readFromService:key error:NULL] : nil;
	_original = read;
	if (read != nil) {
		_values = [read mutableCopy];
	}
	return YES;
}

@end
