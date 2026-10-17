/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMSentenceEditor.h"
#import "ORMOutlineReader.h"
#import "ORMXML.h"

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

/* "Person is an entity type", "Rating is a value type". */
- (NSArray<NSString *> *)addObjectType:(NSString *)text onDiagram:(NSString *)diagramId reason:(NSString **)reason
{
	BOOL value = [text hasSuffix:@" is a value type"];
	NSString *suffix = value ? @" is a value type" : @" is an entity type";
	NSString *name = ORMStatementName([text substringToIndex:[text length] - [suffix length]]);
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
	                       : [self.editor.objectTypeEditor addEntityTypeNamed:name referenceMode:nil kind:ORMReferenceModeNone
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
			rule = [text stringByAppendingString:@"."];
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
			[self.editor.elementEditor setDefinition:rule of:subtype reason:&failure];
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

/* A new diagram of that name; the first takes over an empty one a new
 * model starts with. */
- (NSString *)diagramNamed:(NSString *)name first:(BOOL)first
{
	NSArray *existing = self.editor.model.diagrams;
	ORMDiagram *empty = [existing count] == 1 && [[[existing firstObject] shapes] count] == 0 ? [existing firstObject] : nil;
	if (first && empty != nil && [self.editor.elementEditor rename:empty.identifier to:name reason:NULL]) {
		return empty.identifier;
	}
	return [self.editor.diagramEditor addDiagramNamed:name];
}

- (BOOL)addFromText:(NSString *)text failures:(NSArray<NSString *> **)failures
{
	NSMutableArray *failed = [NSMutableArray array];
	NSMutableArray *diagrams = [NSMutableArray array];
	NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	NSSet *marks = [NSSet setWithObjects:@"*", @"**", @"+", @"++", nil];
	[self.editor group:@"Add from Text" with:^{
		NSString *diagram = nil;
		ORMObjectType *lastType = nil;
		ORMFactType *lastFact = nil;
		for (NSUInteger n = 0; n < [lines count]; n++) {
			NSString *line = ORMStatementTrimmed([lines objectAtIndex:n]);
			if ([line length] == 0 || [line hasPrefix:@"//"]) {
				continue;
			}
			NSString *why = nil;
			BOOL read = YES;
			NSUInteger number = n + 1;
			NSRange space = [line rangeOfString:@" "];
			if ([line hasPrefix:@"# "]) {
				diagram = [self diagramNamed:ORMStatementTrimmed([line substringFromIndex:2]) first:diagram == nil];
				[diagrams addObject:diagram];
				continue;
			}
			if (diagram == nil) {
				diagram = [self diagramNamed:self.editor.model.name first:YES];
				[diagrams addObject:diagram];
			}
			if ([line hasPrefix:@"Query "] && [line hasSuffix:@":"]) {
				/* A query: its outline, the lines up to a blank one, as
				 * -[ORMQuery outlineText] writes it. */
				NSString *name = ORMStatementTrimmed([line substringWithRange:NSMakeRange([@"Query " length],
				                                                                          [line length] - [@"Query " length] - 1)]);
				NSMutableArray *outline = [NSMutableArray array];
				while (n + 1 < [lines count] && [ORMStatementTrimmed([lines objectAtIndex:n + 1]) length] > 0) {
					[outline addObject:[lines objectAtIndex:++n]];
				}
				NSString *made = [[[ORMOutlineReader alloc] initWithEditor:self.editor]
					addQueryNamed:[name length] > 0 ? name : nil outline:[outline componentsJoinedByString:@"\n"] reason:&why];
				read = made != nil;
				lastFact = nil;
			} else if ([line hasPrefix:@"Reference Mode: "] || [line hasPrefix:@"Portable data type: "]) {
				read = [self setDetail:line of:lastType reason:&why];
			} else if ([line hasPrefix:@"Fact Type Name: "]) {
				why = lastFact == nil ? @"A fact type's name goes after the fact type." : nil;
				read = lastFact != nil
					&& [self.editor.elementEditor rename:lastFact.identifier
					                                  to:[line substringFromIndex:[@"Fact Type Name: " length]] reason:&why];
			} else if (space.location != NSNotFound && [marks containsObject:[line substringToIndex:space.location]]) {
				read = [self setDerivation:line of:lastFact reason:&why];
			} else {
				NSArray *made = [self addFromSentence:line onDiagram:diagram at:ORMAutomaticPlacement reason:&why];
				read = made != nil;
				/* What the next lines go on from: the object type a
				 * statement names, the fact type a line made. */
				lastFact = nil;
				for (NSString *identifier in made) {
					id element = [self.editor.model elementWithId:identifier];
					if ([element isKindOfClass:[ORMFactType class]] && ((ORMFactType *)element).kind == ORMFactTypeOrdinary) {
						lastFact = element;
					} else if ([element isKindOfClass:[ORMObjectType class]] && [made count] == 1) {
						lastType = element;
					}
				}
			}
			if (!read) {
				[failed addObject:[NSString stringWithFormat:@"%lu: %@", (unsigned long)number,
				                                             why ?: @"The sentence says nothing the model can take."]];
			}
		}
		for (NSString *each in diagrams) {
			[self.editor.diagramEditor arrangeDiagram:each];
		}
	}];
	if (failures != NULL) {
		*failures = failed;
	}
	return [failed count] == 0;
}

@end
