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
	NSMutableDictionary<NSString *, NSString *> *_values;
	/* The object as the service gave it, to change no more of it than was
	 * changed, and its version (If-Match). */
	NSDictionary<NSString *, NSString *> *_original;
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

- (NSDictionary<NSString *, NSString *> *)values
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
}

- (void)setValues:(NSDictionary<NSString *, NSString *> *)values
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

- (NSDictionary<NSString *, NSString *> *)readFromService:(NSString *)key error:(NSError **)error
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

- (BOOL)save:(NSError **)error
{
	_errors = @{};
	_savedKey = nil;
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
