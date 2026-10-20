/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMSentenceEditor.h"
#import "ORMOutlineReader.h"
#import "ORMSchemaText.h"
#import "ORMQuery.h"
#import "ORMXML.h"
#import "ORMModelPriv.h"

static NSString *
ORMStatementTrimmed(NSString *text)
{
	return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/* The text as one object type's name: "[Order Line]", or a word of
 * letters, digits and underscores. nil when it is more than that. */
static NSString *
ORMStatementName(NSString *text)
{
	NSString *name = ORMStatementTrimmed(text);
	if ([name hasPrefix:@"["] && [name hasSuffix:@"]"] && [name length] > 2) {
		return ORMStatementTrimmed([name substringWithRange:NSMakeRange(1, [name length] - 2)]);
	}
	NSMutableCharacterSet *letters = [NSMutableCharacterSet alphanumericCharacterSet];
	[letters addCharactersInString:@"_"];
	if ([name length] == 0 || [name rangeOfCharacterFromSet:[letters invertedSet]].location != NSNotFound) {
		return nil;
	}
	return name;
}

/* "Numeric: Decimal(10, 2)": NORMA's element name for the data type, and
 * the length and scale; nil when no data type is called that. */
static NSString *
ORMStatementDataType(NSString *text, NSInteger *length, NSInteger *scale)
{
	NSString *display = ORMStatementTrimmed(text);
	*length = 0;
	*scale = 0;
	NSRange open = [display rangeOfString:@"("];
	if (open.location != NSNotFound && [display hasSuffix:@")"]) {
		NSString *inside = [display substringWithRange:NSMakeRange(NSMaxRange(open), [display length] - NSMaxRange(open) - 1)];
		NSArray *numbers = [inside componentsSeparatedByString:@","];
		*length = [ORMStatementTrimmed([numbers firstObject]) integerValue];
		*scale = [numbers count] > 1 ? [ORMStatementTrimmed([numbers objectAtIndex:1]) integerValue] : 0;
		display = ORMStatementTrimmed([display substringToIndex:open.location]);
	}
	for (NSString *typeName in [ORMDataType allTypeNames]) {
		if ([[ORMDataType displayNameOfTypeNamed:typeName] caseInsensitiveCompare:display] == NSOrderedSame) {
			return typeName;
		}
	}
	return nil;
}

@implementation ORMSentenceEditor (ORMStatements)

/* The object type of that name, made an entity type when the model has
 * none; its id, and in made when it was made. */
- (NSString *)objectTypeNamed:(NSString *)name
                    onDiagram:(NSString *)diagramId
                         made:(NSMutableArray *)made
                       reason:(NSString **)reason
{
	NSString *identifier = [[self.editor.model objectTypeNamed:name] identifier];
	if (identifier == nil) {
		identifier = [self.editor.objectTypeEditor addEntityTypeNamed:name referenceMode:nil kind:ORMReferenceModeNone
		                                                    onDiagram:diagramId at:ORMAutomaticPlacement reason:reason];
		if (identifier != nil) {
			[made addObject:identifier];
		}
	}
	return identifier;
}

/* "Person is an entity type", "Rating is a value type"; an entity type
 * with its reference mode as a fact sentence writes it after the name:
 * "Vehicle(.id)" (popular), "Mass(kg:)" (unit-based), "Country(Code)"
 * (general). */
- (NSArray<NSString *> *)addObjectType:(NSString *)text onDiagram:(NSString *)diagramId reason:(NSString **)reason
{
	BOOL value = [text hasSuffix:@" is a value type"];
	NSString *suffix = value ? @" is a value type" : @" is an entity type";
	NSString *head = ORMStatementTrimmed([text substringToIndex:[text length] - [suffix length]]);
	NSString *mode = nil;
	ORMReferenceModeKind kind = ORMReferenceModeNone;
	NSRange open = [head rangeOfString:@"(" options:NSBackwardsSearch];
	if ([head hasSuffix:@")"] && open.location != NSNotFound && open.location > 0) {
		NSString *inside = ORMStatementTrimmed([head substringWithRange:NSMakeRange(open.location + 1,
		                                                                            [head length] - open.location - 2)]);
		head = [head substringToIndex:open.location];
		if ([inside length] == 0 || value) {
			*reason = value ? @"A value type has no reference mode: an entity type does."
			                : @"Name() is a value type: say \"is a value type\".";
			return nil;
		}
		mode = [inside hasPrefix:@"."] ? [inside substringFromIndex:1]
			: [inside hasSuffix:@":"] ? [inside substringToIndex:[inside length] - 1] : inside;
		kind = [inside hasPrefix:@"."] ? ORMReferenceModePopular
			: [inside hasSuffix:@":"] ? ORMReferenceModeUnitBased : ORMReferenceModeGeneral;
	}
	NSString *name = ORMStatementName(head);
	if (name == nil) {
		return nil;
	}
	ORMObjectType *existing = [self.editor.model objectTypeNamed:name];
	if (existing != nil) {
		if (existing.isEntity == value) {
			*reason = [NSString stringWithFormat:@"%@ is already %@.", name, value ? @"an entity type" : @"a value type"];
			return nil;
		}
		return @[ existing.identifier ];
	}
	NSString *made = value ? [self.editor.objectTypeEditor addValueTypeNamed:name dataType:nil onDiagram:diagramId
	                                                                       at:ORMAutomaticPlacement reason:reason]
	                       : [self.editor.objectTypeEditor addEntityTypeNamed:name referenceMode:mode kind:kind
	                                                                onDiagram:diagramId at:ORMAutomaticPlacement
	                                                                   reason:reason];
	return made != nil ? @[ made ] : nil;
}

/* "Each Male is a Person"; "Each Male is by definition a Person who ...".
 * nil, with no reason, when the names are not one each. */
- (NSArray<NSString *> *)addSubtype:(NSString *)text onDiagram:(NSString *)diagramId reason:(NSString **)reason
{
	NSString *rest = [text substringFromIndex:[@"Each " length]];
	NSString *subtypeName = nil;
	NSString *supertypeName = nil;
	NSString *rule = nil;
	for (NSString *verb in @[ @" is by definition an ", @" is by definition a ", @" is an ", @" is a " ]) {
		NSRange at = [rest rangeOfString:verb];
		if (at.location == NSNotFound) {
			continue;
		}
		subtypeName = ORMStatementName([rest substringToIndex:at.location]);
		NSString *after = [rest substringFromIndex:NSMaxRange(at)];
		if ([verb hasPrefix:@" is by definition"]) {
			NSRange space = [after rangeOfString:@" "];
			supertypeName = ORMStatementName(space.location != NSNotFound ? [after substringToIndex:space.location] : after);
			/* "a Person who is of Gender 'M'": its words, after "by definition". */
			rule = [[verb substringFromIndex:[@" is by definition " length]] stringByAppendingString:after];
		} else {
			supertypeName = ORMStatementName(after);
		}
		break;
	}
	if (subtypeName == nil || supertypeName == nil) {
		return nil;
	}
	NSMutableArray *made = [NSMutableArray array];
	__block NSString *failure = nil;
	[self.editor group:@"Add Subtype" with:^{
		NSString *subtype = [self objectTypeNamed:subtypeName onDiagram:diagramId made:made reason:&failure];
		NSString *supertype = subtype != nil ? [self objectTypeNamed:supertypeName onDiagram:diagramId made:made
		                                                      reason:&failure]
		                                     : nil;
		NSString *fact = supertype != nil ? [self.editor.objectTypeEditor addSubtype:subtype of:supertype reason:&failure]
		                                  : nil;
		if (fact == nil) {
			return;
		}
		[made addObject:fact];
		if (rule != nil) {
			[self.editor.objectTypeEditor setDerivationNote:rule ofSubtype:subtype reason:&failure];
		}
	}];
	if (failure != nil) {
		*reason = failure;
		return nil;
	}
	return made;
}

/* "Enrolment is where Student enrolled in Course": the fact type made
 * and objectified. */
- (NSArray<NSString *> *)addObjectification:(NSString *)text
                                  onDiagram:(NSString *)diagramId
                                         at:(NSPoint)point
                                     reason:(NSString **)reason
{
	NSRange where = [text rangeOfString:@" is where "];
	NSString *name = ORMStatementName([text substringToIndex:where.location]);
	if (name == nil) {
		return nil;
	}
	if ([self.editor.model objectTypeNamed:name] != nil) {
		*reason = [NSString stringWithFormat:@"%@ is already an object type.", name];
		return nil;
	}
	NSMutableArray *made = [NSMutableArray array];
	__block NSString *failure = nil;
	[self.editor group:@"Add Objectified Fact Type" with:^{
		NSString *fact = [self addFactTypeFromSentence:[text substringFromIndex:NSMaxRange(where)] onDiagram:diagramId
		                                            at:point reason:&failure];
		NSString *type = fact != nil ? [self.editor.factTypeEditor objectifyFactType:fact named:name reason:&failure] : nil;
		if (type != nil) {
			[made addObjectsFromArray:@[ fact, type ]];
		}
	}];
	if (failure != nil) {
		*reason = failure;
		return nil;
	}
	return made;
}

/* "This association with Amount and Currency provides the preferred
 * identification scheme for Money": the uniqueness constraint over the
 * roles those play opposite Money. */
- (NSArray<NSString *> *)addIdentification:(NSString *)text reason:(NSString **)reason
{
	NSString *rest = [text substringFromIndex:[@"This association with " length]];
	NSRange provides = [rest rangeOfString:@" provides the preferred identification scheme for "];
	if (provides.location == NSNotFound) {
		*reason = @"Say which object type the association identifies.";
		return nil;
	}
	ORMObjectType *identified = [self.editor.model objectTypeNamed:ORMStatementName([rest substringFromIndex:NSMaxRange(provides)])];
	NSMutableSet *names = [NSMutableSet set];
	for (NSString *name in [[[rest substringToIndex:provides.location] stringByReplacingOccurrencesOfString:@" and "
	                                                                                          withString:@", "]
	                           componentsSeparatedByString:@", "]) {
		[names addObject:ORMStatementName(name) ?: name];
	}
	if (identified == nil) {
		*reason = @"No object type is named so.";
		return nil;
	}
	for (ORMConstraint *constraint in self.editor.model.constraints) {
		if (constraint.kind != ORMUniquenessConstraint) {
			continue;
		}
		NSMutableSet *players = [NSMutableSet set];
		BOOL opposite = YES;
		for (ORMRole *role in [constraint allRoles]) {
			[players addObject:role.player.name ?: @""];
			opposite = opposite && [role oppositeRole].player == identified;
		}
		if (opposite && [players isEqualToSet:names]) {
			if (![self.editor.constraintEditor setPreferredIdentifier:constraint.identifier reason:reason]) {
				return nil;
			}
			return @[ constraint.identifier ];
		}
	}
	*reason = [NSString stringWithFormat:@"No uniqueness constraint over %@ opposite %@: say it first.",
	                                     [[names allObjects] componentsJoinedByString:@" and "], identified.name];
	return nil;
}

/* "The possible values of VIN match the pattern '[A-HJ-NPR-Z0-9]{17}'". */
- (NSArray<NSString *> *)addPattern:(NSString *)text reason:(NSString **)reason
{
	NSRange match = [text rangeOfString:@" match the pattern '"];
	NSString *name = ORMStatementName([text substringWithRange:NSMakeRange([@"The possible values of " length],
	                                                                       match.location - [@"The possible values of " length])]);
	NSString *quoted = [text substringFromIndex:NSMaxRange(match)];
	if (![quoted hasSuffix:@"'"]) {
		*reason = @"Quote the pattern: '...'.";
		return nil;
	}
	ORMObjectType *type = name != nil ? [self.editor.model objectTypeNamed:name] : nil;
	if (type == nil) {
		*reason = [NSString stringWithFormat:@"No object type is named %@.", name];
		return nil;
	}
	if (![self.editor.objectTypeEditor setValuePattern:[quoted substringToIndex:[quoted length] - 1] of:type.identifier
	                                            reason:reason]) {
		return nil;
	}
	return @[ type.identifier ];
}

- (NSArray<NSString *> *)addStatement:(NSString *)input
                            onDiagram:(NSString *)diagramId
                                   at:(NSPoint)point
                               reason:(NSString **)reason
{
	NSString *why = nil;
	NSString *text = ORMStatementTrimmed(input ?: @"");
	while ([text hasSuffix:@"."]) {
		text = ORMStatementTrimmed([text substringToIndex:[text length] - 1]);
	}
	NSArray *made = nil;
	if ([text hasSuffix:@" is an entity type"] || [text hasSuffix:@" is a value type"]) {
		made = [self addObjectType:text onDiagram:diagramId reason:&why];
	} else if ([text hasPrefix:@"Each "]) {
		made = [self addSubtype:text onDiagram:diagramId reason:&why];
	} else if ([text hasPrefix:@"The possible values of "] && [text rangeOfString:@" match the pattern '"].location != NSNotFound) {
		made = [self addPattern:text reason:&why];
	} else if ([text hasPrefix:@"This association with "]) {
		made = [self addIdentification:text reason:&why];
	} else if ([text rangeOfString:@" is where "].location != NSNotFound) {
		made = [self addObjectification:text onDiagram:diagramId at:point reason:&why];
	}
	if (made == nil && reason != NULL) {
		*reason = why;
	}
	return made;
}

#pragma mark A schema as text

/* "Reference Mode: .id" and "Portable data type: ...", of the object type. */
- (BOOL)setDetail:(NSString *)line of:(ORMObjectType *)type reason:(NSString **)reason
{
	if (type == nil) {
		*reason = @"Say first which object type, as \"Person is an entity type.\"";
		return NO;
	}
	if ([line hasPrefix:@"Reference Mode: "]) {
		NSString *mode = ORMStatementTrimmed([line substringFromIndex:[@"Reference Mode: " length]]);
		ORMReferenceModeKind kind = ORMReferenceModeGeneral;
		if ([mode hasPrefix:@"."]) {
			mode = [mode substringFromIndex:1];
			kind = ORMReferenceModePopular;
		} else if ([mode hasSuffix:@":"]) {
			mode = [mode substringToIndex:[mode length] - 1];
			kind = ORMReferenceModeUnitBased;
		}
		return [self.editor.objectTypeEditor setReferenceMode:mode kind:kind ofEntity:type.identifier reason:reason];
	}
	NSInteger length = 0;
	NSInteger scale = 0;
	NSString *typeName = ORMStatementDataType([line substringFromIndex:[@"Portable data type: " length]], &length, &scale);
	if (typeName == nil) {
		*reason = @"No data type is called that.";
		return NO;
	}
	return [self.editor.objectTypeEditor setDataType:typeName length:length scale:scale of:type.identifier reason:reason];
}

/* "* rule", "** rule", "+ rule", "++ rule", of the fact type. */
- (BOOL)setDerivation:(NSString *)line of:(ORMFactType *)fact reason:(NSString **)reason
{
	if (fact == nil) {
		*reason = @"A derivation goes after the fact type it derives.";
		return NO;
	}
	NSRange space = [line rangeOfString:@" "];
	NSString *mark = [line substringToIndex:space.location];
	BOOL partial = [mark hasPrefix:@"+"];
	BOOL stored = [mark length] == 2;
	if (![self.editor.factTypeEditor setDerivationNote:ORMStatementTrimmed([line substringFromIndex:space.location])
	                                                of:fact.identifier reason:reason]) {
		return NO;
	}
	return (!partial && !stored) || [self.editor.factTypeEditor setDerivationPartial:partial stored:stored
	                                                                              of:fact.identifier reason:reason];
}

/* The diagram of that name: the model's, or a new one, which goes in
 * made to be arranged; the first takes over an empty one a new model
 * starts with. */
- (NSString *)diagramNamed:(NSString *)name first:(BOOL)first made:(NSMutableArray *)made
{
	NSArray *existing = self.editor.model.diagrams;
	for (ORMDiagram *diagram in existing) {
		if ([diagram.name isEqualToString:name]) {
			return diagram.identifier;
		}
	}
	ORMDiagram *empty = [existing count] == 1 && [[[existing firstObject] shapes] count] == 0 ? [existing firstObject] : nil;
	NSString *identifier = nil;
	if (first && empty != nil && [self.editor.elementEditor rename:empty.identifier to:name reason:NULL]) {
		identifier = empty.identifier;
	} else {
		identifier = [self.editor.diagramEditor addDiagramNamed:name];
	}
	if (identifier != nil && ![made containsObject:identifier]) {
		[made addObject:identifier];
	}
	return identifier;
}

/* The text split at its commas outside quotes and parentheses, each part
 * trimmed: "'gal (US)', 3.785411784" is two. */
static NSArray<NSString *> *
ORMStatementParts(NSString *text)
{
	NSMutableArray *parts = [NSMutableArray array];
	NSUInteger start = 0;
	NSInteger depth = 0;
	BOOL quoted = NO;
	for (NSUInteger i = 0; i < [text length]; i++) {
		unichar c = [text characterAtIndex:i];
		if (c == '\'') {
			quoted = !quoted;
		} else if (!quoted && c == '(') {
			depth++;
		} else if (!quoted && c == ')') {
			depth--;
		} else if (!quoted && depth == 0 && c == ',') {
			[parts addObject:ORMStatementTrimmed([text substringWithRange:NSMakeRange(start, i - start)])];
			start = i + 1;
		}
	}
	[parts addObject:ORMStatementTrimmed([text substringFromIndex:start])];
	return parts;
}

/* "Reference data: km, 1" after a fact type: it is reference data, and
 * this a fact of it, each role's player named as the population table
 * names it, in the order of its first reading's roles. */
- (BOOL)addReferenceFact:(NSString *)text of:(ORMFactType *)fact reason:(NSString **)reason
{
	if (fact == nil) {
		if (reason != NULL) {
			*reason = @"Reference data goes after its fact type.";
		}
		return NO;
	}
	NSMutableArray *roles = [NSMutableArray array];
	NSArray *visible = [fact visibleRoles];
	for (ORMRole *role in [(ORMReadingOrder *)[fact.readingOrders firstObject] roles] ?: visible) {
		if ([visible containsObject:role]) {
			[roles addObject:role];
		}
	}
	NSArray *parts = ORMStatementParts(text);
	if ([parts count] != [roles count]) {
		if (reason != NULL) {
			*reason = [NSString stringWithFormat:@"A fact of it names %lu players, by commas.", (unsigned long)[roles count]];
		}
		return NO;
	}
	if (![self.editor.factTypeEditor setReferenceData:YES of:fact.identifier reason:reason]) {
		return NO;
	}
	NSMutableDictionary *named = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < [roles count]; i++) {
		/* A player named by several values, in parentheses: "(10, km)". */
		NSString *part = [parts objectAtIndex:i];
		if ([part hasPrefix:@"("] && [part hasSuffix:@")"]) {
			part = [part substringWithRange:NSMakeRange(1, [part length] - 2)];
		} else if ([part hasPrefix:@"'"] && [part hasSuffix:@"'"] && [part length] >= 2) {
			/* One value, quoted for its comma, parenthesis or quote. */
			part = [[part substringWithRange:NSMakeRange(1, [part length] - 2)] stringByReplacingOccurrencesOfString:@"''"
			                                                                                              withString:@"'"];
		}
		[named setObject:part forKey:[[roles objectAtIndex:i] identifier]];
	}
	return [self.editor.populationEditor addFactOf:fact.identifier named:named reason:reason] != nil;
}

#pragma mark What the model says already

/* A note as comment lines say it: each line trimmed. */
static NSString *
ORMStatementNoteLines(NSString *note)
{
	NSMutableArray *lines = [NSMutableArray array];
	NSString *text = [[ORMStatementTrimmed(note ?: @"") stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
		stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
	for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
		[lines addObject:ORMStatementTrimmed(line)];
	}
	return [lines componentsJoinedByString:@"\n"];
}

/* A line as compared with the model's own (ORMSchemaText), its role names
 * left out. */
static NSString *
ORMStatementComparable(NSString *line)
{
	NSMutableString *text = [[ORMSchemaText comparableLine:line] mutableCopy];
	NSRange as = [text rangeOfString:@" (as "];
	while (as.location != NSNotFound) {
		NSRange close = [text rangeOfString:@")" options:0 range:NSMakeRange(as.location, [text length] - as.location)];
		if (close.location == NSNotFound) {
			break;
		}
		[text deleteCharactersInRange:NSMakeRange(as.location, NSMaxRange(close) - as.location)];
		as = [text rangeOfString:@" (as "];
	}
	return text;
}

/* The lines the model says, by their text as compared: what a line of
 * text names that the model has, and what a "- " line takes away. Each
 * reading of a fact type is one of its lines. */
- (NSDictionary<NSString *, NSArray<ORMSchemaLine *> *> *)saidLines
{
	NSMutableDictionary *said = [NSMutableDictionary dictionary];
	for (ORMSchemaLine *line in [[[ORMSchemaText alloc] initWithEditor:self.editor] lines]) {
		if (line.kind == ORMSchemaBlank || line.kind == ORMSchemaOutline) {
			continue;
		}
		/* As it is, role names and all; and without them. */
		NSMutableArray *keys = [NSMutableArray arrayWithObject:line.kind == ORMSchemaComment ? line.text
		                                                                                     : [ORMSchemaText comparableLine:line.text]];
		if (line.kind != ORMSchemaComment) {
			[keys addObject:ORMStatementComparable(line.text)];
		}
		if (line.kind == ORMSchemaFactType) {
			ORMFactType *fact = [self.editor.model elementWithId:[line.elementIds firstObject]];
			for (ORMReadingOrder *order in fact.readingOrders) {
				for (ORMReading *reading in order.readings) {
					[keys addObject:ORMStatementComparable([reading expandedText] ?: @"")];
				}
			}
		}
		for (NSString *key in keys) {
			NSMutableArray *lines = [said objectForKey:key];
			if (lines == nil) {
				[said setObject:[NSMutableArray arrayWithObject:line] forKey:key];
			} else if (![lines containsObject:line]) {
				[lines addObject:line];
			}
		}
	}
	return said;
}

/* The model's line the text says, among those of its kinds; for a fact
 * type, a reading of it alone ("A / B" any of them). The one about the
 * element the lines before were about, where several are. */
- (ORMSchemaLine *)line:(NSString *)text
                     in:(NSDictionary<NSString *, NSArray<ORMSchemaLine *> *> *)said
                  kinds:(NSArray<NSNumber *> *)kinds
                  about:(NSArray<NSString *> *)context
{
	/* The line as it is first, its role names telling apart fact types
	 * read alike; then without them, a reading alone. */
	NSMutableArray *keys = [NSMutableArray arrayWithObject:[text hasPrefix:@"//"] ? ORMStatementTrimmed(text)
	                                                                            : [ORMSchemaText comparableLine:text]];
	[keys addObject:ORMStatementComparable(text)];
	for (NSString *part in [text componentsSeparatedByString:@" / "]) {
		[keys addObject:ORMStatementComparable(part)];
	}
	NSMutableArray *found = [NSMutableArray array];
	for (NSString *key in keys) {
		for (ORMSchemaLine *line in [said objectForKey:key]) {
			if ([kinds containsObject:@(line.kind)] && ![found containsObject:line]) {
				[found addObject:line];
			}
		}
		if ([found count] > 0) {
			break;
		}
	}
	for (ORMSchemaLine *line in found) {
		for (NSString *identifier in context) {
			if ([line.elementIds containsObject:identifier]) {
				return line;
			}
		}
	}
	return [found count] == 1 ? [found firstObject] : nil;
}

/* The same, any of several the text says alike: what is said already,
 * whichever it is said of. */
- (ORMSchemaLine *)anyLine:(NSString *)text
                        in:(NSDictionary<NSString *, NSArray<ORMSchemaLine *> *> *)said
                     kinds:(NSArray<NSNumber *> *)kinds
                     about:(NSArray<NSString *> *)context
{
	ORMSchemaLine *line = [self line:text in:said kinds:kinds about:context];
	if (line != nil) {
		return line;
	}
	for (ORMSchemaLine *each in [said objectForKey:[ORMSchemaText comparableLine:text]]) {
		if ([kinds containsObject:@(each.kind)]) {
			return each;
		}
	}
	return nil;
}

/* What a line says taken away: the element, or the part of it the line
 * is. */
- (BOOL)remove:(ORMSchemaLine *)line reason:(NSString **)reason
{
	ORMEditor *editor = self.editor;
	ORMModel *model = editor.model;
	id element = [model elementWithId:[line.elementIds firstObject]];
	switch (line.kind) {
	case ORMSchemaComment:
		return [editor.elementEditor setNote:nil of:[line.elementIds firstObject] reason:reason];
	case ORMSchemaObjectType:
	case ORMSchemaFactType:
		[editor.elementEditor deleteElements:line.elementIds];
		return YES;
	case ORMSchemaConstraint: {
		NSMutableArray *constraints = [NSMutableArray array];
		for (NSString *identifier in line.elementIds) {
			id each = [model elementWithId:identifier];
			if ([each isKindOfClass:[ORMConstraint class]]) {
				[constraints addObject:identifier];
				continue;
			}
			/* A role's possible values. */
			for (ORMFactType *fact in model.factTypes) {
				for (ORMRole *role in fact.roles) {
					if ([role.valueConstraint.identifier isEqualToString:identifier]
					    && ![editor.objectTypeEditor setValueConstraint:@"" of:role.identifier reason:reason]) {
						return NO;
					}
				}
			}
		}
		[editor.elementEditor deleteElements:constraints];
		return YES;
	}
	case ORMSchemaValues:
		if ([line.text rangeOfString:@" match the pattern '"].location != NSNotFound) {
			return [editor.objectTypeEditor setValuePattern:nil of:[line.elementIds firstObject] reason:reason];
		}
		return [editor.objectTypeEditor setValueConstraint:@"" of:[line.elementIds firstObject] reason:reason];
	case ORMSchemaDetail:
		if ([line.text hasPrefix:@"Reference Mode: "]) {
			return [editor.objectTypeEditor setReferenceMode:nil kind:ORMReferenceModeNone ofEntity:[line.elementIds firstObject]
			                                          reason:reason];
		}
		if ([line.text hasSuffix:@" is independent."]) {
			return [editor.objectTypeEditor setIndependent:NO of:[line.elementIds firstObject] reason:reason];
		}
		break;
	case ORMSchemaDerivation:
		if ([ORMQuery derivationOf:element inModel:model] != nil) {
			if (reason != NULL) {
				*reason = @"A query derives it: take the query away.";
			}
			return NO;
		}
		return [editor.factTypeEditor setDerivationNote:nil of:[line.elementIds firstObject] reason:reason];
	case ORMSchemaReferenceData:
		return [editor.populationEditor removeFact:[line.elementIds firstObject] reason:reason];
	case ORMSchemaQuery:
		[[[ORMQueryEditor alloc] initWithEditor:editor] removeQuery:[line.elementIds firstObject]];
		return YES;
	default:
		break;
	}
	if (reason != NULL) {
		*reason = @"That is not taken away: say what it is instead.";
	}
	return NO;
}

/* The element a comment before the line is the note of: the object type
 * a statement declares or subtypes, the fact type, the constraint. */
- (NSString *)notedOf:(NSArray<NSString *> *)ids
{
	ORMModel *model = self.editor.model;
	for (NSString *identifier in ids) {
		id element = [model elementWithId:identifier];
		if ([element isKindOfClass:[ORMStoredQuery class]]) {
			return identifier;
		}
		if ([element isKindOfClass:[ORMFactType class]] && [(ORMFactType *)element kind] == ORMFactTypeSubtype) {
			return [[(ORMFactType *)element subtype] identifier];
		}
		if ([element isKindOfClass:[ORMFactType class]] || [element isKindOfClass:[ORMConstraint class]]) {
			return identifier;
		}
	}
	for (NSString *identifier in ids) {
		if ([[model elementWithId:identifier] isKindOfClass:[ORMObjectType class]]) {
			return identifier;
		}
	}
	return nil;
}

/* The diagram that shows the first object type the sentence names: where
 * what it makes goes when no heading says. */
- (NSString *)diagramFor:(NSString *)line
{
	ORMFactSentence *sentence = [ORMFactSentence sentenceWithString:line model:self.editor.model reason:NULL];
	for (ORMFactSentencePlayer *player in sentence.players) {
		ORMObjectType *type = [self.editor.model objectTypeNamed:player.name];
		for (ORMDiagram *diagram in self.editor.model.diagrams) {
			if (type != nil && [diagram shapeForSubject:type.identifier] != nil) {
				return diagram.identifier;
			}
		}
	}
	return nil;
}

- (BOOL)addFromText:(NSString *)text failures:(NSArray<NSString *> **)failures
{
	NSMutableArray *failed = [NSMutableArray array];
	NSMutableArray *arranged = [NSMutableArray array];
	NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	NSSet *marks = [NSSet setWithObjects:@"*", @"**", @"+", @"++", nil];
	NSArray *statements = @[ @(ORMSchemaObjectType), @(ORMSchemaFactType), @(ORMSchemaConstraint), @(ORMSchemaValues) ];
	NSArray *removable = @[ @(ORMSchemaComment), @(ORMSchemaObjectType), @(ORMSchemaDetail), @(ORMSchemaValues),
		                    @(ORMSchemaFactType), @(ORMSchemaFactTypeName), @(ORMSchemaDerivation), @(ORMSchemaConstraint),
		                    @(ORMSchemaReferenceData), @(ORMSchemaQuery) ];
	[self.editor group:@"Add from Text" with:^{
		NSString *diagram = nil;
		ORMObjectType *lastType = nil;
		ORMFactType *lastFact = nil;
		/* The last fact type made, past the constraints said of it. */
		ORMFactType *lastMade = nil;
		/* What the model says, worked out again after something is taken
		 * away; and the comment lines just before a line. */
		NSDictionary *said = nil;
		NSMutableArray *comment = [NSMutableArray array];
		for (NSUInteger n = 0; n < [lines count]; n++) {
			NSString *line = ORMStatementTrimmed([lines objectAtIndex:n]);
			if ([line length] == 0) {
				[comment removeAllObjects];
				continue;
			}
			if ([line hasPrefix:@"//"]) {
				[comment addObject:ORMStatementTrimmed([line substringFromIndex:2])];
				continue;
			}
			NSString *note = [comment count] > 0 ? [comment componentsJoinedByString:@"\n"] : nil;
			[comment removeAllObjects];
			NSString *why = nil;
			BOOL read = YES;
			NSUInteger number = n + 1;
			NSRange space = [line rangeOfString:@" "];
			/* The elements the line was about, for its comment. */
			NSArray *about = nil;
			said = said ?: [self saidLines];
			NSMutableArray *context = [NSMutableArray array];
			for (ORMElement *each in @[ lastFact ?: (id)[NSNull null], lastType ?: (id)[NSNull null], lastMade ?: (id)[NSNull null] ]) {
				if ([each isKindOfClass:[ORMElement class]]) {
					[context addObject:each.identifier];
				}
			}
			/* A line of what the last statement named that the model says
			 * of it already: a detail, its name, its derivation. */
			ORMSchemaLine *same = [self line:line in:said
			                           kinds:@[ @(ORMSchemaDetail), @(ORMSchemaFactTypeName), @(ORMSchemaDerivation) ]
			                           about:context];
			BOOL sameOfContext = NO;
			for (NSString *identifier in same.elementIds) {
				sameOfContext = sameOfContext || [context containsObject:identifier];
			}
			if (sameOfContext && ![line hasPrefix:@"- "]) {
				continue;
			}
			if ([line hasPrefix:@"- "]) {
				/* What the model says, taken away. */
				NSString *gone = ORMStatementTrimmed([line substringFromIndex:2]);
				ORMSchemaLine *found = [self line:gone in:said kinds:removable about:context];
				read = found != nil && [self remove:found reason:&why];
				why = found == nil ? @"The model says no such thing, or says it of several: say which first." : why;
				said = nil;
				lastFact = nil;
				lastType = nil;
				lastMade = nil;
			} else if ([line hasPrefix:@"# "]) {
				diagram = [self diagramNamed:ORMStatementTrimmed([line substringFromIndex:2]) first:diagram == nil
				                        made:arranged];
				continue;
			} else if ([line hasPrefix:@"Query "] && [line hasSuffix:@":"]) {
				/* A query: its outline, the lines up to a blank one, as
				 * -[ORMQuery outlineText] writes it. One the model has of
				 * that name is replaced, unless it is the same. */
				NSString *name = ORMStatementTrimmed([line substringWithRange:NSMakeRange([@"Query " length],
				                                                                          [line length] - [@"Query " length] - 1)]);
				NSMutableArray *outline = [NSMutableArray array];
				while (n + 1 < [lines count] && [ORMStatementTrimmed([lines objectAtIndex:n + 1]) length] > 0) {
					[outline addObject:[lines objectAtIndex:++n]];
				}
				NSString *body = [outline componentsJoinedByString:@"\n"];
				ORMQuery *existing = nil;
				for (ORMQuery *query in [ORMQuery queriesInModel:self.editor.model]) {
					existing = [name length] > 0 && [query.name isEqualToString:name] ? query : existing;
				}
				if (existing != nil && [ORMStatementTrimmed([existing outlineText]) isEqualToString:ORMStatementTrimmed(body)]) {
					about = @[ existing.identifier ];
				} else {
					if (existing != nil) {
						[[[ORMQueryEditor alloc] initWithEditor:self.editor] removeQuery:existing.identifier];
						said = nil;
					}
					NSString *made = [[[ORMOutlineReader alloc] initWithEditor:self.editor]
						addQueryNamed:[name length] > 0 ? name : nil outline:body reason:&why];
					read = made != nil;
					about = made != nil ? @[ made ] : nil;
				}
				lastFact = nil;
			} else if ([line hasPrefix:@"Reference Mode: "] || [line hasPrefix:@"Portable data type: "]) {
				read = [self setDetail:line of:lastType reason:&why];
			} else if ([line hasPrefix:@"Reference data: "]) {
				ORMSchemaLine *found = [self line:line in:said kinds:@[ @(ORMSchemaReferenceData) ] about:@[]];
				ORMFactInstance *fact = [self.editor.model elementWithId:[found.elementIds firstObject]];
				read = (lastMade != nil && fact.factType == lastMade)
					|| [self addReferenceFact:[line substringFromIndex:[@"Reference data: " length]] of:lastMade reason:&why];
			} else if ([line hasPrefix:@"Fact Type Name: "]) {
				why = lastFact == nil ? @"A fact type's name goes after the fact type." : nil;
				read = lastFact != nil
					&& [self.editor.elementEditor rename:lastFact.identifier
					                                  to:[line substringFromIndex:[@"Fact Type Name: " length]] reason:&why];
			} else if (space.location != NSNotFound && [marks containsObject:[line substringToIndex:space.location]]) {
				ORMQuery *derivation = lastFact != nil ? [ORMQuery derivationOf:lastFact inModel:self.editor.model] : nil;
				NSString *byQuery = [NSString stringWithFormat:@"By query %@.", derivation.name];
				read = (derivation != nil && [ORMStatementTrimmed([line substringFromIndex:space.location]) isEqualToString:byQuery])
					|| [self setDerivation:line of:lastFact reason:&why];
			} else if ([self anyLine:line in:said kinds:statements about:context] != nil) {
				/* What the model says already: the lines after go on from it. */
				ORMSchemaLine *found = [self anyLine:line in:said kinds:statements about:context];
				about = found.elementIds;
				lastFact = nil;
				for (NSString *identifier in found.elementIds) {
					id element = [self.editor.model elementWithId:identifier];
					if ([element isKindOfClass:[ORMFactType class]] && ((ORMFactType *)element).kind == ORMFactTypeOrdinary) {
						lastFact = element;
						lastMade = element;
					} else if ([element isKindOfClass:[ORMObjectType class]] && found.kind == ORMSchemaObjectType) {
						lastType = element;
					}
				}
			} else if ([line hasSuffix:@" is independent"] || [line hasSuffix:@" is independent."]) {
				NSString *name = [line substringToIndex:[line rangeOfString:@" is independent" options:NSBackwardsSearch].location];
				ORMObjectType *type = [self.editor.model objectTypeNamed:ORMStatementName(name) ?: name];
				why = type == nil ? @"No object type is named so." : nil;
				read = type != nil && [self.editor.objectTypeEditor setIndependent:YES of:type.identifier reason:&why];
			} else {
				/* A diagram for what the sentence makes, when no heading gave
				 * one: one that shows what it names, else the model's. */
				NSString *target = diagram ?: [self diagramFor:line];
				if (target == nil) {
					diagram = [self diagramNamed:self.editor.model.name first:YES made:arranged];
					target = diagram;
				}
				NSArray *made = [self addFromSentence:line onDiagram:target at:ORMAutomaticPlacement reason:&why];
				read = made != nil;
				about = made;
				/* What the next lines go on from: the object type a
				 * statement names, the fact type a line made. */
				lastFact = nil;
				for (NSString *identifier in made) {
					id element = [self.editor.model elementWithId:identifier];
					if ([element isKindOfClass:[ORMFactType class]] && ((ORMFactType *)element).kind == ORMFactTypeOrdinary) {
						lastFact = element;
						lastMade = element;
					} else if ([element isKindOfClass:[ORMObjectType class]] && [made count] == 1) {
						lastType = element;
					}
				}
			}
			/* The comment before it is the note of what it says; one that
			 * says the note as the listing does is the note already. */
			NSString *noted = read && note != nil ? [self notedOf:about] : nil;
			if (noted != nil && ![ORMStatementNoteLines([[self.editor.model elementWithId:noted] noteText]) isEqualToString:note]) {
				read = [self.editor.elementEditor setNote:note of:noted reason:&why];
			}
			if (!read) {
				[failed addObject:[NSString stringWithFormat:@"%lu: %@", (unsigned long)number,
				                                             why ?: @"The sentence says nothing the model can take."]];
			}
		}
		for (NSString *each in arranged) {
			[self.editor.diagramEditor arrangeDiagram:each];
		}
	}];
	if (failures != NULL) {
		*failures = failed;
	}
	return [failed count] == 0;
}

@end
