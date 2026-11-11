/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFormCustomization.h"
#import "ORMQuery.h"

static NSString * const ORMCustomXForms = @"http://www.w3.org/2002/xforms";

/* An attribute's value by its local name, whatever its prefix. */
static NSString *
ORMCustomAttribute(NSXMLElement *element, NSString *localName)
{
	for (NSXMLNode *attribute in [element attributes]) {
		if ([[attribute localName] isEqualToString:localName]) {
			return [attribute stringValue];
		}
	}
	return nil;
}

/* The XForms elements of the local name beneath the node, in order. */
static NSArray<NSXMLElement *> *
ORMCustomXFormsElements(NSXMLNode *node, NSString *localName)
{
	NSMutableArray *found = [NSMutableArray array];
	for (NSXMLNode *child in [node children]) {
		if ([child kind] != NSXMLElementKind) {
			continue;
		}
		NSXMLElement *element = (NSXMLElement *)child;
		if ([[element localName] isEqualToString:localName] && [[element URI] isEqualToString:ORMCustomXForms]) {
			[found addObject:element];
		}
		[found addObjectsFromArray:ORMCustomXFormsElements(element, localName)];
	}
	return found;
}

static NSArray<NSXMLElement *> *
ORMCustomChildren(NSXMLElement *element)
{
	NSMutableArray *children = [NSMutableArray array];
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind) {
			[children addObject:child];
		}
	}
	return children;
}

/* The document's form instance's anchor element. */
static NSXMLElement *
ORMCustomInstanceRoot(NSXMLDocument *document)
{
	for (NSXMLElement *instance in ORMCustomXFormsElements(document, @"instance")) {
		if ([ORMCustomAttribute(instance, @"id") isEqualToString:@"form"]) {
			return [ORMCustomChildren(instance) firstObject];
		}
	}
	return nil;
}

/* Each bind's ref (its path, within the binds above it), and the bind. */
static NSDictionary<NSString *, NSXMLElement *> *
ORMCustomBinds(NSXMLDocument *document)
{
	NSMutableDictionary *binds = [NSMutableDictionary dictionary];
	for (NSXMLElement *bind in ORMCustomXFormsElements(document, @"bind")) {
		NSString *ref = ORMCustomAttribute(bind, @"ref") ?: ORMCustomAttribute(bind, @"nodeset");
		if (ref != nil) {
			[binds setObject:bind forKey:ref];
		}
	}
	return binds;
}

/* "UnitNote" for "unitNote"; "urgent" stays a reading's word. */
static NSString *
ORMCustomTypeName(NSString *element)
{
	return [element length] > 0 ? [[[element substringToIndex:1] uppercaseString] stringByAppendingString:[element substringFromIndex:1]]
	                            : element;
}

/* "needs a lift" for "needsALift": a flag as a reading says it. */
static NSString *
ORMCustomReading(NSString *element)
{
	NSMutableString *reading = [NSMutableString string];
	for (NSUInteger i = 0; i < [element length]; i++) {
		unichar c = [element characterAtIndex:i];
		if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:c] && i > 0) {
			[reading appendString:@" "];
		}
		[reading appendString:[[NSString stringWithCharacters:&c length:1] lowercaseString]];
	}
	return [reading hasPrefix:@"is "] ? reading : [@"is " stringByAppendingString:reading];
}

@implementation ORMFormCustomization
{
	NSXMLDocument *_copy;
	NSMutableArray<NSString *> *_errors;
	NSMutableArray<NSString *> *_warnings;
	NSMutableArray<NSString *> *_provisional;
	/* Each provisional element's object: the anchor's type, or an owned
	 * one's entity. */
	NSMutableDictionary<NSString *, NSString *> *_ownerOf;
}

+ (instancetype)customization:(NSXMLDocument *)copy ofForm:(ORMFormDocument *)form
{
	ORMFormCustomization *customization = [[ORMFormCustomization alloc] init];
	[customization check:copy ofForm:form];
	return customization;
}

- (void)check:(NSXMLDocument *)copy ofForm:(ORMFormDocument *)form
{
	_form = form;
	_copy = copy;
	_errors = [NSMutableArray array];
	_warnings = [NSMutableArray array];
	_provisional = [NSMutableArray array];
	_ownerOf = [NSMutableDictionary dictionary];
	NSXMLElement *root = ORMCustomInstanceRoot(copy);
	if (root == nil) {
		[_errors addObject:@"The copy has no form instance (xf:instance id=\"form\")."];
		return;
	}
	NSDictionary *table = [form tablePropertyList];
	NSMutableDictionary<NSString *, NSDictionary *> *elements = [NSMutableDictionary dictionary];
	for (NSDictionary *element in [table objectForKey:@"elements"]) {
		[elements setObject:element forKey:[element objectForKey:@"name"]];
	}
	NSMutableSet *groups = [NSMutableSet set];
	NSMutableDictionary *groupEntities = [NSMutableDictionary dictionary];
	for (NSDictionary *group in [table objectForKey:@"groups"] ?: @[]) {
		[groups addObject:[group objectForKey:@"name"]];
		[groupEntities setObject:[group objectForKey:@"entity"] ?: @"" forKey:[group objectForKey:@"name"]];
	}
	NSSet *repeats = [NSSet setWithArray:[[table objectForKey:@"repeats"] allKeys] ?: @[]];
	/* What it has: each element by its path, marked provisional or not. */
	NSMutableSet *has = [NSMutableSet set];
	[self walk:root prefix:nil groups:groups repeats:repeats contract:elements has:has entities:groupEntities];
	/* What it is given. */
	for (NSString *name in elements) {
		NSDictionary *element = [elements objectForKey:name];
		if ([[element objectForKey:@"given"] boolValue] && ![has containsObject:name]) {
			[_errors addObject:[NSString stringWithFormat:@"%@: the form is given it, and the copy takes no such input.", name]];
		}
	}
	/* What it enters, each bound by a control of the copy's. */
	NSSet *bound = [self boundPathsOf:copy];
	for (NSString *name in [[elements allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSDictionary *element = [elements objectForKey:name];
		if ([[element objectForKey:@"role"] isEqualToString:@"entered"] && ![bound containsObject:name]) {
			[_errors addObject:[NSString stringWithFormat:@"%@: the form enters it, and no control of the copy binds it.", name]];
		}
	}
	/* What the model's form requires or constrains, the copy's too: else
	 * refused where it is submitted, not as it is filled in. */
	NSDictionary *theirs = ORMCustomBinds([form document]);
	NSDictionary *ours = ORMCustomBinds(copy);
	for (NSString *ref in [[theirs allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
		NSXMLElement *model = [theirs objectForKey:ref], *mine = [ours objectForKey:ref];
		for (NSString *what in @[ @"required", @"constraint" ]) {
			if (ORMCustomAttribute(model, what) != nil && ORMCustomAttribute(mine, what) == nil) {
				[_warnings addObject:[NSString stringWithFormat:@"%@: the model's form has it %@, the copy not: checked where it is submitted only.",
				                                                ref, [what isEqualToString:@"required"] ? @"required" : @"constrained"]];
			}
		}
	}
	[_errors sortUsingSelector:@selector(compare:)];
}

/* Each element beneath the element: one the contract has, a group of
 * them, a repeat's rows, or one marked provisional; else an error. */
- (void)walk:(NSXMLElement *)element
      prefix:(NSString *)prefix
      groups:(NSSet *)groups
     repeats:(NSSet *)repeats
    contract:(NSDictionary *)elements
         has:(NSMutableSet *)has
    entities:(NSDictionary *)entities
{
	for (NSXMLElement *child in ORMCustomChildren(element)) {
		NSString *path = prefix != nil ? [NSString stringWithFormat:@"%@/%@", prefix, [child name]] : [child name];
		[has addObject:path];
		NSString *marked = ORMCustomAttribute(child, @"provisional");
		if ([marked isEqualToString:@"true"] && [elements objectForKey:path] == nil) {
			[_provisional addObject:path];
			[_ownerOf setObject:prefix != nil ? [entities objectForKey:prefix] ?: @"" : _form.form.root.objectType.name ?: @"" forKey:path];
			continue;
		}
		if ([elements objectForKey:path] != nil || [repeats containsObject:path]) {
			continue;
		}
		if ([groups containsObject:path]) {
			[self walk:child prefix:path groups:groups repeats:repeats contract:elements has:has entities:entities];
			continue;
		}
		[_errors addObject:[NSString stringWithFormat:@"%@: the form has no such element; one the model is to have is marked "
		                                             @"ormf:provisional=\"true\".", path]];
	}
}

/* The paths a control of the copy binds: by its bind's ref, or its own
 * within the groups' and repeats' above it. */
- (NSSet<NSString *> *)boundPathsOf:(NSXMLDocument *)copy
{
	NSMutableDictionary *refOfBind = [NSMutableDictionary dictionary];
	for (NSXMLElement *bind in ORMCustomXFormsElements(copy, @"bind")) {
		NSString *identifier = ORMCustomAttribute(bind, @"id"), *ref = ORMCustomAttribute(bind, @"ref");
		if (identifier != nil && ref != nil) {
			[refOfBind setObject:ref forKey:identifier];
		}
	}
	NSMutableSet *bound = [NSMutableSet set];
	for (NSString *kind in @[ @"input", @"select1", @"select", @"textarea", @"secret", @"range", @"upload" ]) {
		for (NSXMLElement *control in ORMCustomXFormsElements(copy, kind)) {
			NSString *bind = ORMCustomAttribute(control, @"bind");
			NSString *ref = bind != nil ? [refOfBind objectForKey:bind] : ORMCustomAttribute(control, @"ref");
			if (ref == nil) {
				continue;
			}
			if (bind == nil) {
				for (NSXMLNode *above = [control parent]; above != nil; above = [above parent]) {
					NSString *within = [above kind] == NSXMLElementKind
						? ORMCustomAttribute((NSXMLElement *)above, @"ref") ?: ORMCustomAttribute((NSXMLElement *)above, @"nodeset") : nil;
					ref = within != nil ? [NSString stringWithFormat:@"%@/%@", within, ref] : ref;
				}
			}
			[bound addObject:ref];
		}
	}
	return bound;
}

- (NSArray<NSString *> *)errors
{
	return [_errors copy];
}

- (NSArray<NSString *> *)warnings
{
	return [_warnings copy];
}

- (NSArray<NSString *> *)provisionalElements
{
	return [_provisional copy];
}

- (BOOL)isUnderConstruction
{
	return [_provisional count] > 0;
}

/* "xf:decimal" and the like as the portable data type it says; nil for
 * none. */
static NSString *
ORMCustomDataType(NSString *xformsType)
{
	NSString *type = [[xformsType componentsSeparatedByString:@":"] lastObject];
	NSDictionary *types = @{
		@"decimal" : @"Numeric: Decimal", @"double" : @"Numeric: Decimal", @"integer" : @"Numeric: Signed Integer",
		@"date" : @"Temporal: Date", @"dateTime" : @"Temporal: Date & Time", @"string" : @"Text: Variable Length",
		@"boolean" : @"boolean",
	};
	return type != nil ? [types objectForKey:type] : nil;
}

/* The type a sample's value is of: a number, a day, a moment, a flag, a
 * text. */
static NSString *
ORMCustomDataTypeOfValue(NSString *value)
{
	NSString *text = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([text length] == 0) {
		return nil;
	}
	if ([text isEqualToString:@"true"] || [text isEqualToString:@"false"]) {
		return @"boolean";
	}
	NSRegularExpression *(^pattern)(NSString *) = ^NSRegularExpression *(NSString *p) {
		return [NSRegularExpression regularExpressionWithPattern:p options:0 error:NULL];
	};
	NSRange all = NSMakeRange(0, [text length]);
	if ([pattern(@"^-?[0-9]+(\\.[0-9]+)?$") numberOfMatchesInString:text options:0 range:all] == 1) {
		return @"Numeric: Decimal";
	}
	if ([pattern(@"^[0-9]{4}-[0-9]{2}-[0-9]{2}$") numberOfMatchesInString:text options:0 range:all] == 1) {
		return @"Temporal: Date";
	}
	if ([pattern(@"^[0-9]{4}-[0-9]{2}-[0-9]{2}T") numberOfMatchesInString:text options:0 range:all] == 1) {
		return @"Temporal: Date & Time";
	}
	return @"Text: Variable Length";
}

/* The values a control of the copy's lists for the path (xf:item's). */
- (NSArray<NSString *> *)itemsOf:(NSString *)path
{
	NSMutableArray *items = [NSMutableArray array];
	NSDictionary *binds = ORMCustomBinds(_copy);
	for (NSString *kind in @[ @"select1", @"select" ]) {
		for (NSXMLElement *control in ORMCustomXFormsElements(_copy, kind)) {
			NSString *bind = ORMCustomAttribute(control, @"bind");
			NSString *ref = ORMCustomAttribute(control, @"ref");
			BOOL ofPath = [ref isEqualToString:path];
			for (NSString *each in binds) {
				ofPath = ofPath || ([each isEqualToString:path] && [ORMCustomAttribute([binds objectForKey:each], @"id") isEqualToString:bind ?: @""]);
			}
			for (NSXMLElement *value in ofPath ? ORMCustomXFormsElements(control, @"value") : @[]) {
				[items addObject:[value stringValue]];
			}
		}
	}
	return items;
}

- (NSString *)proposalGiven:(NSXMLDocument *)sample
{
	NSDictionary *binds = ORMCustomBinds(_copy);
	NSXMLElement *sampleRoot = [sample rootElement];
	NSMutableString *proposal = [NSMutableString string];
	for (NSString *path in _provisional) {
		NSString *owner = [_ownerOf objectForKey:path];
		NSString *element = [[path componentsSeparatedByString:@"/"] lastObject];
		NSXMLElement *bind = [binds objectForKey:path];
		NSString *type = ORMCustomDataType(ORMCustomAttribute(bind, @"type"));
		if (type == nil && sampleRoot != nil) {
			NSXMLElement *at = sampleRoot;
			for (NSString *step in [path componentsSeparatedByString:@"/"]) {
				at = [[at elementsForName:step] firstObject];
			}
			type = ORMCustomDataTypeOfValue([at stringValue]);
		}
		type = type ?: @"Text: Variable Length";
		BOOL required = [ORMCustomAttribute(bind, @"required") isEqualToString:@"true()"];
		if ([type isEqualToString:@"boolean"]) {
			NSString *reading = ORMCustomReading(element);
			[proposal appendFormat:@"%@ %@\n// in the form: + %@ (entered)\n\n", owner, reading, reading];
			continue;
		}
		NSString *name = ORMCustomTypeName(element);
		[proposal appendFormat:@"%@ is a value type.\nPortable data type: %@\n", name, type];
		NSArray *items = [self itemsOf:path];
		if ([items count] > 0) {
			NSMutableArray *quoted = [NSMutableArray array];
			for (NSString *item in items) {
				[quoted addObject:[NSString stringWithFormat:@"'%@'", [item stringByReplacingOccurrencesOfString:@"'" withString:@"''"]]];
			}
			[proposal appendFormat:@"The possible values of %@ are %@.\n", name, [quoted componentsJoinedByString:@", "]];
		}
		[proposal appendFormat:@"%@ has %@\nEach %@ has %@ one %@.\n// in the form: + has %@ (entered)\n\n", owner, name, owner,
		                       required ? @"exactly" : @"at most", name, name];
	}
	return proposal;
}

@end
