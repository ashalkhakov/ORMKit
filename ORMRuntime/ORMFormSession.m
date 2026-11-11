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
}

- (instancetype)initWithForm:(ORMForm *)form given:(NSDictionary<NSString *, NSString *> *)given
{
	if ((self = [super init])) {
		_form = form;
		_given = [given copy] ?: @{};
		_values = [[form instanceGiven:_given] mutableCopy];
		_errors = @{};
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
	if (_context != nil) {
		return [_form identifiedKeyNamed:name values:_values inContext:_context error:error];
	}
	BOOL none = YES;
	for (NSString *each in [_form elementsIdentifying:name]) {
		none = none && [[[_values objectForKey:each] description] length] == 0;
	}
	if (none) {
		return @"";
	}
	ORMQueryOData *request = [_form identifyRequestNamed:name values:_values model:_model error:error];
	NSArray *rows = request != nil ? [self rowsOf:request objects:NULL error:error] : nil;
	if (rows == nil) {
		return nil;
	}
	return ORMFormText([[rows firstObject] firstObject], [_form elementNamed:name].keyName);
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
		return YES;
	}
	NSDictionary *read = _context != nil ? [_form readKey:_key inContext:_context error:error] : [self readFromService:_key error:error];
	if (read == nil) {
		return NO;
	}
	_original = _context != nil ? nil : read;
	_values = [read mutableCopy];
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
	ORMQueryOData *request = [_form readRequestForKey:key model:_model error:error];
	NSArray *objects = nil;
	NSArray *rows = request != nil ? [self rowsOf:request objects:&objects error:error] : nil;
	if (rows == nil) {
		return nil;
	}
	if ([rows count] == 0) {
		if (error != NULL) {
			*error = ORMFormSessionError([NSString stringWithFormat:@"There is no %@ %@.", _form.entityName, key]);
		}
		return nil;
	}
	id object = [objects firstObject];
	_etag = [object isKindOfClass:[NSDictionary class]] ? [object objectForKey:@"@odata.etag"] : nil;
	return [_form instanceOfRow:[rows firstObject]];
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
}

- (NSArray<NSString *> *)choicesNamed:(NSString *)name inRepeat:(NSString *)repeat row:(NSUInteger)row error:(NSError **)error
{
	ORMForm *form = [_form repeatNamed:repeat];
	if ([form elementNamed:name].items != nil) {
		return [form elementNamed:name].items;
	}
	NSArray *rows = [self rowsOfRepeat:repeat];
	NSDictionary *values = row < [rows count] ? [rows objectAtIndex:row] : @{};
	if (form == nil || _context == nil) {
		if (error != NULL) {
			*error = ORMFormSessionError(form == nil ? [NSString stringWithFormat:@"The form has no repeat %@.", repeat]
			                                         : @"A repeat's choices are read from a store.");
		}
		return nil;
	}
	return [form choicesNamed:name values:values inContext:_context error:error];
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
	ORMFormRequest *save = [_form saveRequestFor:_values original:_original etag:_etag model:_model error:error];
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
	if ([key length] == 0 && exchange.data != nil) {
		key = ORMFormText([NSJSONSerialization JSONObjectWithData:exchange.data options:0 error:NULL], _form.keyElement);
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
