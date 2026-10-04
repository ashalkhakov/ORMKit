/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMXML.h"

NSString * const ORMRootNamespace = @"http://schemas.neumont.edu/ORM/2006-04/ORMRoot";
NSString * const ORMCoreNamespace = @"http://schemas.neumont.edu/ORM/2006-04/ORMCore";
NSString * const ORMDiagramNamespace = @"http://schemas.neumont.edu/ORM/2006-04/ORMDiagram";
NSString * const ORMDiagramDisplayNamespace = @"http://schemas.neumont.edu/ORM/2008-11/DiagramDisplay";
NSString * const ORMCoreDataNamespace = @"http://schemas.ormkit.org/2026-10/CoreDataBridge";
NSString * const ORMQueryNamespace = @"http://schemas.ormkit.org/2026-10/Queries";

NSArray<NSString *> *
ORMKitNamespaces(void)
{
	return @[ ORMCoreDataNamespace, ORMQueryNamespace ];
}

const double ORMPointsPerInch = 72.0;

static void ORMCopyLayout(NSXMLDocument *from, NSXMLDocument *to);

NSArray<NSString *> *
ORMGeneratedNamespaces(void)
{
	return @[ @"http://schemas.neumont.edu/ORM/Abstraction/2007-06/Core",
	          @"http://schemas.neumont.edu/ORM/Abstraction/2007-06/DataTypes/Core",
	          @"http://schemas.neumont.edu/ORM/Relational/2007-06/ConceptualDatabase",
	          @"http://schemas.neumont.edu/ORM/Bridge/2007-06/ORMToORMAbstraction",
	          @"http://schemas.neumont.edu/ORM/Bridge/2007-06/ORMAbstractionToConceptualDatabase",
	          @"http://schemas.neumont.edu/ORM/2007-11/RelationalView" ];
}

#pragma mark Reading

BOOL
ORMIs(NSXMLNode *node, NSString *uri, NSString *local)
{
	return [node kind] == NSXMLElementKind && [[node URI] isEqualToString:uri]
		&& (local == nil || [[node localName] isEqualToString:local]);
}

NSArray<NSXMLElement *> *
ORMChildren(NSXMLElement *element, NSString *uri, NSString *local)
{
	NSMutableArray *found = [NSMutableArray array];
	for (NSXMLNode *child in [element children]) {
		if (ORMIs(child, uri, local)) {
			[found addObject:child];
		}
	}
	return found;
}

NSXMLElement *
ORMChild(NSXMLElement *element, NSString *uri, NSString *local)
{
	for (NSXMLNode *child in [element children]) {
		if (ORMIs(child, uri, local)) {
			return (NSXMLElement *)child;
		}
	}
	return nil;
}

NSArray<NSXMLElement *> *
ORMGrandchildren(NSXMLElement *element, NSString *uri, NSString *local, NSString *childURI, NSString *childLocal)
{
	NSMutableArray *found = [NSMutableArray array];
	for (NSXMLElement *child in ORMChildren(element, uri, local)) {
		[found addObjectsFromArray:ORMChildren(child, childURI, childLocal)];
	}
	return found;
}

static void
ORMCollect(NSXMLElement *element, NSString *uri, NSString *local, NSMutableArray *found)
{
	for (NSXMLNode *child in [element children]) {
		if ([child kind] != NSXMLElementKind) {
			continue;
		}
		if (ORMIs(child, uri, local)) {
			[found addObject:child];
		}
		ORMCollect((NSXMLElement *)child, uri, local, found);
	}
}

NSArray<NSXMLElement *> *
ORMDescendants(NSXMLElement *element, NSString *uri, NSString *local)
{
	NSMutableArray *found = [NSMutableArray array];
	ORMCollect(element, uri, local, found);
	return found;
}

NSString *
ORMAttribute(NSXMLElement *element, NSString *name)
{
	return [[element attributeForName:name] stringValue];
}

void
ORMSetAttribute(NSXMLElement *element, NSString *name, NSString *value)
{
	if (value == nil) {
		[element removeAttributeForName:name];
		return;
	}
	NSXMLNode *attribute = [element attributeForName:name];
	if (attribute != nil) {
		if (![[attribute stringValue] isEqualToString:value]) {
			[attribute setStringValue:value];
		}
	} else {
		[element addAttribute:[NSXMLNode attributeWithName:name stringValue:value]];
	}
}

BOOL
ORMBoolAttribute(NSXMLElement *element, NSString *name, BOOL fallback)
{
	NSString *value = ORMAttribute(element, name);
	if (value == nil) {
		return fallback;
	}
	return [value caseInsensitiveCompare:@"true"] == NSOrderedSame || [value isEqualToString:@"1"];
}

void
ORMSetBoolAttribute(NSXMLElement *element, NSString *name, BOOL value, BOOL fallback)
{
	ORMSetAttribute(element, name, value == fallback ? nil : (value ? @"true" : @"false"));
}

NSString *
ORMRef(NSXMLElement *element)
{
	return ORMAttribute(element, @"ref");
}

#pragma mark Making

/* The prefix NORMA gives a namespace. */
static NSString *
ORMUsualPrefix(NSString *uri)
{
	NSDictionary *prefixes = @{ ORMRootNamespace: @"ormRoot", ORMCoreNamespace: @"orm",
	                            ORMDiagramNamespace: @"ormDiagram", ORMDiagramDisplayNamespace: @"diagramDisplay",
	                            ORMCoreDataNamespace: @"ormcd", ORMQueryNamespace: @"ormq" };
	return [prefixes objectForKey:uri] ?: @"ns";
}

/* The prefix the root gives the namespace; with declare, the usual one,
 * declared there, when it gives none. */
static NSString *
ORMPrefix(NSXMLDocument *document, NSString *uri, BOOL declare)
{
	NSXMLElement *root = [document rootElement];
	for (NSXMLNode *namespace in [root namespaces]) {
		if ([[namespace stringValue] isEqualToString:uri]) {
			return [namespace name] ?: @"";
		}
	}
	if (!declare) {
		return nil;
	}
	NSString *prefix = ORMUsualPrefix(uri);
	[root addNamespace:[NSXMLNode namespaceWithName:prefix stringValue:uri]];
	return prefix;
}

static NSString *
ORMQualify(NSString *prefix, NSString *local)
{
	return [prefix length] > 0 ? [NSString stringWithFormat:@"%@:%@", prefix, local] : local;
}

NSXMLElement *
ORMNewElement(NSXMLDocument *document, NSString *uri, NSString *local)
{
	return [[NSXMLElement alloc] initWithName:ORMQualify(ORMPrefix(document, uri, YES), local) URI:uri];
}

NSXMLElement *
ORMNewElementWithId(NSXMLDocument *document, NSString *uri, NSString *local, NSString *elementId)
{
	NSXMLElement *element = ORMNewElement(document, uri, local);
	ORMSetAttribute(element, @"id", elementId ?: ORMNewId());
	return element;
}

NSXMLElement *
ORMNewRef(NSXMLDocument *document, NSString *uri, NSString *local, NSString *target)
{
	NSXMLElement *element = ORMNewElement(document, uri, local);
	ORMSetAttribute(element, @"ref", target);
	return element;
}

/* Where a child goes among its siblings, by NORMA's schema: the order
 * NORMA writes them in. Unknown children keep their place after the
 * known ones. */
static NSInteger
ORMRank(NSString *local)
{
	static NSDictionary *ranks;
	if (ranks == nil) {
		NSArray *order = @[
			/* An ORMModel's sections. */
			@"Objects", @"Facts", @"Constraints", @"DataTypes", @"CustomReferenceModes", @"ModelNotes",
			@"ModelErrors", @"ReferenceModeKinds", @"RecognizedPhrases", @"Extensions",
			/* An object type's. */
			@"Definitions", @"Notes", @"Abbreviations", @"PlayedRoles", @"PreferredIdentifier",
			@"NestedPredicate", @"ConceptualDataType", @"ValueRestriction", @"Instances",
			/* A fact type's. */
			@"FactRoles", @"ReadingOrders", @"InternalConstraints", @"DerivationRule",
			/* A role's. */
			@"RolePlayer",
			/* A shape's. */
			@"RelativeShapes", @"Subject", @"RoleDisplayOrder",
		];
		NSMutableDictionary *built = [NSMutableDictionary dictionary];
		[order enumerateObjectsUsingBlock:^(NSString *name, NSUInteger i, BOOL *stop) {
			if ([built objectForKey:name] == nil) {
				[built setObject:@(i) forKey:name];
			}
		}];
		ranks = built;
	}
	NSNumber *rank = [ranks objectForKey:local];
	return rank != nil ? [rank integerValue] : NSIntegerMax;
}

/* The rank among the parent's children: a fact type's Instances come last,
 * after its DerivationRule, where an object type's come before what is a
 * fact type's. */
static NSInteger
ORMRankIn(NSXMLElement *parent, NSString *local)
{
	if ([local isEqualToString:@"Instances"] && [[parent localName] hasSuffix:@"Fact"]) {
		return ORMRank(@"DerivationRule") + 1;
	}
	return ORMRank(local);
}

void
ORMInsertChild(NSXMLElement *parent, NSXMLElement *child)
{
	NSInteger rank = ORMRankIn(parent, [child localName]);
	NSArray *children = [parent children];
	NSUInteger index = [children count];
	if (rank != NSIntegerMax) {
		for (NSUInteger i = 0; i < [children count]; i++) {
			NSXMLNode *sibling = [children objectAtIndex:i];
			if ([sibling kind] == NSXMLElementKind && ORMRankIn(parent, [sibling localName]) > rank) {
				index = i;
				break;
			}
		}
	}
	[parent insertChild:child atIndex:index];
}

NSXMLElement *
ORMEnsureChild(NSXMLDocument *document, NSXMLElement *parent, NSString *uri, NSString *local)
{
	NSXMLElement *child = ORMChild(parent, uri, local);
	if (child != nil) {
		return child;
	}
	child = ORMNewElement(document, uri, local);
	ORMInsertChild(parent, child);
	return child;
}

NSString *
ORMChildText(NSXMLElement *parent, NSString *uri, NSString *local)
{
	NSXMLElement *child = ORMChild(parent, uri, local);
	return child != nil ? [child stringValue] : nil;
}

NSXMLElement *
ORMSetChildText(NSXMLDocument *document, NSXMLElement *parent, NSString *uri, NSString *local, NSString *text)
{
	if ([text length] == 0) {
		[ORMChild(parent, uri, local) detach];
		return nil;
	}
	NSXMLElement *child = ORMEnsureChild(document, parent, uri, local);
	if (![[child stringValue] isEqualToString:text]) {
		[child setStringValue:text];
	}
	return child;
}

void
ORMPruneIfEmpty(NSXMLElement *element)
{
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind) {
			return;
		}
	}
	[element detach];
}

#pragma mark Identifiers

NSString *
ORMNewId(void)
{
	return [@"_" stringByAppendingString:[[[NSUUID UUID] UUIDString] uppercaseString]];
}

NSXMLElement *
ORMElementWithId(NSXMLDocument *document, NSString *elementId)
{
	if (elementId == nil) {
		return nil;
	}
	NSMutableArray *pending = [NSMutableArray arrayWithObject:[document rootElement]];
	while ([pending count] > 0) {
		NSXMLElement *element = [pending lastObject];
		[pending removeLastObject];
		if ([ORMAttribute(element, @"id") isEqualToString:elementId]) {
			return element;
		}
		for (NSXMLNode *child in [element children]) {
			if ([child kind] == NSXMLElementKind) {
				[pending addObject:child];
			}
		}
	}
	return nil;
}

NSDictionary<NSString *, NSXMLElement *> *
ORMIndexIds(NSXMLDocument *document)
{
	NSMutableDictionary *index = [NSMutableDictionary dictionary];
	NSMutableArray *pending = [NSMutableArray arrayWithObject:[document rootElement]];
	while ([pending count] > 0) {
		NSXMLElement *element = [pending lastObject];
		[pending removeLastObject];
		NSString *elementId = ORMAttribute(element, @"id");
		if (elementId != nil) {
			[index setObject:element forKey:elementId];
		}
		for (NSXMLNode *child in [element children]) {
			if ([child kind] == NSXMLElementKind) {
				[pending addObject:child];
			}
		}
	}
	return index;
}

NSXMLDocument *
ORMCopyDocument(NSXMLDocument *document)
{
#if defined(__APPLE__)
	NSXMLDocument *copy = [document copy];
#else
	/* gnustep-base's -[NSXMLDocument copyWithZone:] gives the copy a URI
	 * without its terminating NUL, and copying that copy reads past it
	 * (AddressSanitizer: heap-buffer-overflow in xmlCopyDoc). Undo copies
	 * copies, so the root is copied into a new document instead. */
	NSXMLDocument *copy = [[NSXMLDocument alloc] initWithRootElement:[[document rootElement] copy]];
	[copy setVersion:[document version] ?: @"1.0"];
	[copy setCharacterEncoding:[document characterEncoding] ?: @"utf-8"];
#endif
	if ([copy isStandalone] != [document isStandalone]) {
		[copy setStandalone:[document isStandalone]];
	}
	if ([document version] != nil && ![[copy version] isEqualToString:[document version]]) {
		[copy setVersion:[document version]];
	}
	if ([document characterEncoding] != nil
	    && ![[copy characterEncoding] isEqualToString:[document characterEncoding]]) {
		[copy setCharacterEncoding:[document characterEncoding]];
	}
	ORMCopyLayout(document, copy);
	return copy;
}

#pragma mark Geometry

NSRect
ORMParseBounds(NSString *text)
{
	NSArray *parts = [text componentsSeparatedByString:@","];
	if ([parts count] != 4) {
		return NSZeroRect;
	}
	double v[4];
	for (NSUInteger i = 0; i < 4; i++) {
		v[i] = [[[parts objectAtIndex:i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]
			doubleValue] * ORMPointsPerInch;
	}
	return NSMakeRect(v[0], v[1], v[2], v[3]);
}

/* As .NET writes a double: the shortest form that reads back the same. */
static NSString *
ORMFormatInches(double points)
{
	double inches = points / ORMPointsPerInch;
	for (int digits = 1; digits <= 17; digits++) {
		NSString *text = [NSString stringWithFormat:@"%.*g", digits, inches];
		if ([text doubleValue] == inches) {
			return text;
		}
	}
	return [NSString stringWithFormat:@"%.17g", inches];
}

NSString *
ORMFormatBounds(NSRect bounds)
{
	return [NSString stringWithFormat:@"%@, %@, %@, %@", ORMFormatInches(NSMinX(bounds)),
	        ORMFormatInches(NSMinY(bounds)), ORMFormatInches(NSWidth(bounds)), ORMFormatInches(NSHeight(bounds))];
}

NSPoint
ORMParsePoint(NSString *text)
{
	NSArray *parts = [text componentsSeparatedByString:@","];
	if ([parts count] != 2) {
		return NSZeroPoint;
	}
	return NSMakePoint([[parts objectAtIndex:0] doubleValue] * ORMPointsPerInch,
	                   [[parts objectAtIndex:1] doubleValue] * ORMPointsPerInch);
}

NSString *
ORMFormatPoint(NSPoint point)
{
	return [NSString stringWithFormat:@"%@, %@", ORMFormatInches(point.x), ORMFormatInches(point.y)];
}

#pragma mark Serializing

/* Text's newlines are written as the file's: parsing turned NORMA's
 * CRLF in a note into LF, and .NET writes it back as CRLF. */
static void
ORMEscape(NSMutableString *out, NSString *text, BOOL attribute, NSString *newline)
{
	NSUInteger length = [text length];
	NSUInteger start = 0;
	for (NSUInteger i = 0; i < length; i++) {
		unichar c = [text characterAtIndex:i];
		NSString *entity = nil;
		switch (c) {
		case '&': entity = @"&amp;"; break;
		case '<': entity = @"&lt;"; break;
		case '>': entity = @"&gt;"; break;
		case '"': entity = attribute ? @"&quot;" : nil; break;
		case '\r': entity = @"&#xD;"; break;
		case '\n': entity = attribute ? @"&#xA;" : ([newline isEqualToString:@"\n"] ? nil : newline); break;
		case '\t': entity = attribute ? @"&#x9;" : nil; break;
		default: break;
		}
		if (entity != nil) {
			if (i > start) {
				[out appendString:[text substringWithRange:NSMakeRange(start, i - start)]];
			}
			[out appendString:entity];
			start = i + 1;
		}
	}
	if (length > start) {
		[out appendString:[text substringFromIndex:start]];
	}
}

/* Whether the element holds elements: then it is laid out a child a line,
 * and the whitespace between them is the writer's, not the content's. */
static BOOL
ORMHasElementChildren(NSXMLElement *element)
{
	for (NSXMLNode *child in [element children]) {
		if ([child kind] == NSXMLElementKind) {
			return YES;
		}
	}
	return NO;
}

static void
ORMWriteNamespaces(NSMutableString *out, NSXMLElement *element)
{
	/* Below the root, only what the root does not already declare:
	 * gnustep-base gives an element made apart from the document a
	 * declaration of its own namespace, which the file need not repeat. */
	NSXMLElement *root = [[element rootDocument] rootElement];
	for (NSXMLNode *namespace in [element namespaces]) {
		NSString *prefix = [namespace name];
		if (root != nil && element != root) {
			BOOL declared = NO;
			for (NSXMLNode *rootNamespace in [root namespaces]) {
				if ([([rootNamespace name] ?: @"") isEqualToString:(prefix ?: @"")]
				    && [[rootNamespace stringValue] isEqualToString:[namespace stringValue]]) {
					declared = YES;
				}
			}
			if (declared) {
				continue;
			}
		}
		[out appendString:[prefix length] > 0 ? [NSString stringWithFormat:@" xmlns:%@=\"", prefix] : @" xmlns=\""];
		ORMEscape(out, [namespace stringValue], YES, nil);
		[out appendString:@"\""];
	}
}

static void
ORMWriteElement(NSMutableString *out, NSXMLElement *element, NSUInteger depth, NSString *indent, NSString *newline,
                BOOL attributesFirst)
{
	for (NSUInteger i = 0; i < depth; i++) {
		[out appendString:indent];
	}
	[out appendFormat:@"<%@", [element name]];
	if (!attributesFirst) {
		ORMWriteNamespaces(out, element);
	}
	for (NSXMLNode *attribute in [element attributes]) {
		NSString *name = [attribute name];
		/* GNUstep names a parsed attribute without its prefix; put it
		 * back from the attribute's namespace. */
		if ([[attribute URI] length] > 0 && [name rangeOfString:@":"].location == NSNotFound) {
			NSString *prefix = nil;
			for (NSXMLNode *namespace in [[[element rootDocument] rootElement] namespaces]) {
				if ([[namespace stringValue] isEqualToString:[attribute URI]]) {
					prefix = [namespace name];
				}
			}
			if ([[attribute URI] isEqualToString:@"http://www.w3.org/XML/1998/namespace"]) {
				prefix = @"xml";
			}
			name = ORMQualify(prefix, name);
		}
		[out appendFormat:@" %@=\"", name];
		ORMEscape(out, [attribute stringValue], YES, nil);
		[out appendString:@"\""];
	}
	if (attributesFirst) {
		ORMWriteNamespaces(out, element);
	}
	NSArray *children = [element children];
	if ([children count] == 0) {
		[out appendString:@" />"];
		[out appendString:newline];
		return;
	}
	if (!ORMHasElementChildren(element)) {
		[out appendString:@">"];
		for (NSXMLNode *child in children) {
			if ([child kind] == NSXMLTextKind) {
				ORMEscape(out, [child stringValue], NO, newline);
			} else {
				[out appendString:[child XMLString]];
			}
		}
		[out appendFormat:@"</%@>", [element name]];
		[out appendString:newline];
		return;
	}
	[out appendString:@">"];
	[out appendString:newline];
	for (NSXMLNode *child in children) {
		if ([child kind] == NSXMLElementKind) {
			ORMWriteElement(out, (NSXMLElement *)child, depth + 1, indent, newline, NO);
		} else if ([child kind] == NSXMLTextKind) {
			NSString *text = [[child stringValue]
				stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if ([text length] > 0) {
				for (NSUInteger i = 0; i <= depth; i++) {
					[out appendString:indent];
				}
				ORMEscape(out, text, NO, newline);
				[out appendString:newline];
			}
		} else if ([child kind] == NSXMLCommentKind) {
			for (NSUInteger i = 0; i <= depth; i++) {
				[out appendString:indent];
			}
			[out appendString:[child XMLString]];
			[out appendString:newline];
		}
	}
	for (NSUInteger i = 0; i < depth; i++) {
		[out appendString:indent];
	}
	[out appendFormat:@"</%@>", [element name]];
	[out appendString:newline];
}

/* The layout the bytes were written in: a byte-order mark, CRLF or LF,
 * and what one level of indentation is. */
static NSDictionary *
ORMLayoutOfData(NSData *data)
{
	const unsigned char *bytes = [data bytes];
	NSUInteger length = [data length];
	BOOL bom = length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF;
	BOOL crlf = NO;
	NSString *indent = @"\t";
	for (NSUInteger i = 0; i < length; i++) {
		if (bytes[i] == '\n') {
			crlf = i > 0 && bytes[i - 1] == '\r';
			/* The indentation of the first indented line after the root. */
			for (NSUInteger j = i + 1; j < length && bytes[j] != '<'; j++) {
				if (bytes[j] == '\n') {
					i = j;
					continue;
				}
				if (bytes[j] == ' ') {
					NSUInteger k = j;
					while (k < length && bytes[k] == ' ') {
						k++;
					}
					indent = [@"" stringByPaddingToLength:k - j withString:@" " startingAtIndex:0];
				} else if (bytes[j] != '\t' && bytes[j] != '\r') {
					indent = @"";
				}
				break;
			}
			break;
		}
	}
	/* Whether the root's start tag gives its attributes before its xmlns
	 * declarations: NSXML keeps the two apart. */
	BOOL attributesFirst = NO;
	NSString *head = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(length, (NSUInteger)8192))]
	                                        encoding:NSUTF8StringEncoding];
	NSRange root = [head rangeOfString:@"<" options:0 range:NSMakeRange(1, [head length] > 1 ? [head length] - 1 : 0)];
	while (root.location != NSNotFound && root.location + 1 < [head length]
	       && ([head characterAtIndex:root.location + 1] == '?' || [head characterAtIndex:root.location + 1] == '!')) {
		root = [head rangeOfString:@"<" options:0 range:NSMakeRange(root.location + 1, [head length] - root.location - 1)];
	}
	if (root.location != NSNotFound) {
		NSRange space = [head rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] options:0
		                                        range:NSMakeRange(root.location, [head length] - root.location)];
		if (space.location != NSNotFound) {
			NSScanner *scanner = [NSScanner scannerWithString:[head substringFromIndex:space.location]];
			NSString *firstName = nil;
			[scanner scanUpToString:@"=" intoString:&firstName];
			firstName = [firstName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			attributesFirst = [firstName length] > 0 && ![firstName hasPrefix:@"xmlns"];
		}
	}
	/* What comes before the root element (the XML declaration or not, a
	 * blank line) and after it, as the file has them. */
	NSUInteger start = bom ? 3 : 0;
	NSUInteger rootAt = start;
	while (rootAt + 1 < length && !(bytes[rootAt] == '<' && bytes[rootAt + 1] != '?' && bytes[rootAt + 1] != '!')) {
		rootAt++;
	}
	NSString *prolog = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(start, rootAt - start)]
	                                         encoding:NSUTF8StringEncoding] ?: @"";
	NSUInteger end = length;
	while (end > 0 && bytes[end - 1] != '>') {
		end--;
	}
	NSString *trailer = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(end, length - end)]
	                                          encoding:NSUTF8StringEncoding] ?: @"";
	return @{ @"bom": @(bom), @"newline": crlf ? @"\r\n" : @"\n", @"indent": indent,
	          @"attributesFirst": @(attributesFirst), @"prolog": prolog, @"trailer": trailer };
}

/* How the file a document came from was laid out, by its root, so it
 * goes back the same way; a new document is laid out as NORMA does it. */
static NSMapTable *
ORMLayouts(void)
{
	static NSMapTable *layouts;
	if (layouts == nil) {
		layouts = [NSMapTable weakToStrongObjectsMapTable];
	}
	return layouts;
}

NSXMLDocument *
ORMParseDocument(NSData *data, NSString **reason)
{
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:0 error:&error];
	if (document == nil || [document rootElement] == nil) {
		if (reason != NULL) {
			*reason = [error localizedDescription] ?: @"The file is not XML.";
		}
		return nil;
	}
	@synchronized (ORMLayouts()) {
		[ORMLayouts() setObject:ORMLayoutOfData(data) forKey:[document rootElement]];
	}
	return document;
}

NSData *
ORMDataOfDocument(NSXMLDocument *document)
{
	NSDictionary *layout = nil;
	@synchronized (ORMLayouts()) {
		layout = [ORMLayouts() objectForKey:[document rootElement]];
	}
	if (layout == nil) {
		layout = @{ @"bom": @YES, @"newline": @"\r\n", @"indent": @"\t" };
	}
	NSString *newline = [layout objectForKey:@"newline"];
	NSMutableString *out = [NSMutableString string];
	NSString *prolog = [layout objectForKey:@"prolog"];
	if (prolog != nil) {
		[out appendString:prolog];
	} else {
		[out appendFormat:@"<?xml version=\"%@\" encoding=\"utf-8\"?>", [document version] ?: @"1.0"];
		[out appendString:newline];
	}
	ORMWriteElement(out, [document rootElement], 0, [layout objectForKey:@"indent"], newline,
	                [[layout objectForKey:@"attributesFirst"] boolValue]);
	/* NORMA ends the file without a newline, older ones with one. */
	if ([out hasSuffix:newline]) {
		[out deleteCharactersInRange:NSMakeRange([out length] - [newline length], [newline length])];
	}
	[out appendString:[layout objectForKey:@"trailer"] ?: @""];
	NSMutableData *data = [NSMutableData data];
	if ([[layout objectForKey:@"bom"] boolValue]) {
		static const unsigned char bom[] = { 0xEF, 0xBB, 0xBF };
		[data appendBytes:bom length:3];
	}
	[data appendData:[out dataUsingEncoding:NSUTF8StringEncoding]];
	return data;
}

/* Carries the layout of the document a copy was made from. Undo's
 * snapshots are copies, and a restored one should write as the file did. */
static void
ORMCopyLayout(NSXMLDocument *from, NSXMLDocument *to)
{
	@synchronized (ORMLayouts()) {
		NSDictionary *layout = [ORMLayouts() objectForKey:[from rootElement]];
		if (layout != nil && [to rootElement] != nil) {
			[ORMLayouts() setObject:layout forKey:[to rootElement]];
		}
	}
}
