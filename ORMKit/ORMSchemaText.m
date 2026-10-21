/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMSchemaText.h"
#import "ORMEditorPriv.h"
#import "ORMPath.h"
#import "ORMQuery.h"
#import "ORMVerbalizer.h"

@interface ORMSchemaLine ()
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite) ORMSchemaLineKind kind;
@property (nonatomic, readwrite, copy) NSArray<NSString *> *elementIds;
@end

@implementation ORMSchemaLine

- (NSString *)description
{
	return self.text;
}

@end

/* What is said together: an object type, a fact type and its constraints,
 * a constraint over several, a query. */
@interface ORMSchemaUnit : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, strong) id element;
/* The diagram that shows it first, and where among the shapes;
 * NSNotFound for what no diagram shows. */
@property (nonatomic) NSUInteger section;
@property (nonatomic) NSUInteger position;
/* The units said before it, by key. */
@property (nonatomic, strong) NSMutableOrderedSet<NSString *> *dependencies;
/* A constraint unit's constraints: an exclusive-or's two. */
@property (nonatomic, strong) NSMutableArray<NSString *> *constraintIds;
@end

@implementation ORMSchemaUnit
@end

static NSString *
ORMSchemaTrimmed(NSString *text)
{
	return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

/* Text of several lines (a name NORMA let have them) on one. */
static NSString *
ORMSchemaOneLine(NSString *text)
{
	NSString *joined = [[text ?: @"" stringByReplacingOccurrencesOfString:@"\r\n" withString:@" "]
		stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
	return [joined stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
}

/* A name as a sentence takes it: in brackets where it is more than a
 * word of letters, digits and underscores. */
static NSString *
ORMSchemaName(NSString *name)
{
	/* A name of several lines (NORMA allows one) on one. */
	name = ORMSchemaOneLine(name);
	NSMutableCharacterSet *letters = [NSMutableCharacterSet alphanumericCharacterSet];
	[letters addCharactersInString:@"_"];
	if ([name length] == 0 || [name rangeOfCharacterFromSet:[letters invertedSet]].location != NSNotFound) {
		return [NSString stringWithFormat:@"[%@]", name ?: @""];
	}
	return name;
}

/* The data type a new reference mode's value type gets
 * (ORMObjectTypeEditor): said only where the type has another. */
static NSString *
ORMSchemaDefaultDataType(NSString *mode, ORMReferenceModeKind kind)
{
	if (kind == ORMReferenceModeUnitBased) {
		return @"DecimalNumericDataType";
	}
	NSString *lower = [mode lowercaseString];
	if ([lower isEqualToString:@"id"]) {
		return @"AutoCounterNumericDataType";
	}
	if ([lower isEqualToString:@"nr"] || [lower isEqualToString:@"#"] || [lower isEqualToString:@"number"]) {
		return @"UnsignedIntegerNumericDataType";
	}
	return @"VariableLengthTextDataType";
}

/* "Numeric: Decimal(19, 4)". */
static NSString *
ORMSchemaDataType(ORMObjectType *valueType)
{
	NSMutableString *text = [[valueType.dataType displayName] mutableCopy];
	if (valueType.dataTypeLength > 0 && valueType.dataTypeScale > 0) {
		[text appendFormat:@"(%ld, %ld)", (long)valueType.dataTypeLength, (long)valueType.dataTypeScale];
	} else if (valueType.dataTypeLength > 0) {
		[text appendFormat:@"(%ld)", (long)valueType.dataTypeLength];
	}
	return text;
}

/* A part of a fact of reference data, as -addFromText: reads it back: in
 * parentheses when several values name it, quoted when it has a comma, a
 * parenthesis or a quote. */
static NSString *
ORMSchemaPart(NSString *name, BOOL composite)
{
	if (composite) {
		return [NSString stringWithFormat:@"(%@)", name];
	}
	if ([name rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@",()'"]].location != NSNotFound
	    || ![ORMSchemaTrimmed(name) isEqualToString:name] || [name length] == 0) {
		return [NSString stringWithFormat:@"'%@'", [name stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
	}
	return name;
}

/* The fact types a role path goes through. */
static void
ORMSchemaPathFacts(ORMRolePath *path, NSMutableArray<ORMFactType *> *facts)
{
	for (ORMPathedRole *pathed in path.pathedRoles) {
		if (pathed.role.factType != nil) {
			[facts addObject:pathed.role.factType];
		}
	}
	for (ORMRolePath *sub in path.subPaths) {
		ORMSchemaPathFacts(sub, facts);
	}
}

@implementation ORMSchemaText {
	ORMModel *_model;
	ORMVerbalizer *_verbalizer;
	/* Units by key, and what each element is said in. */
	NSMutableDictionary<NSString *, ORMSchemaUnit *> *_units;
	NSMutableArray<ORMSchemaUnit *> *_ordered;
	NSMutableDictionary<NSString *, NSString *> *_unitOf;
	/* The model's queries, by id; the fact types they derive, by the fact
	 * type's id. */
	NSMutableDictionary<NSString *, ORMQuery *> *_queries;
	NSMutableDictionary<NSString *, ORMQuery *> *_derivations;
	/* The lines being written. */
	NSMutableArray<ORMSchemaLine *> *_lines;
	BOOL _gap;
}

- (instancetype)initWithEditor:(ORMEditor *)editor
{
	if ((self = [super init])) {
		_editor = editor;
	}
	return self;
}

+ (NSString *)comparableLine:(NSString *)line
{
	NSString *text = ORMSchemaTrimmed(line ?: @"");
	while ([text hasSuffix:@"."]) {
		text = ORMSchemaTrimmed([text substringToIndex:[text length] - 1]);
	}
	NSMutableArray *words = [NSMutableArray array];
	for (NSString *word in [text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
		if ([word length] > 0) {
			[words addObject:word];
		}
	}
	return [words componentsJoinedByString:@" "];
}

#pragma mark Lines

- (void)gap
{
	_gap = [_lines count] > 0;
}

- (void)add:(NSString *)text kind:(ORMSchemaLineKind)kind ids:(NSArray<NSString *> *)ids
{
	if (_gap && [(ORMSchemaLine *)[_lines lastObject] kind] != ORMSchemaBlank) {
		ORMSchemaLine *blank = [[ORMSchemaLine alloc] init];
		blank.text = @"";
		blank.kind = ORMSchemaBlank;
		blank.elementIds = @[];
		[_lines addObject:blank];
	}
	_gap = NO;
	ORMSchemaLine *line = [[ORMSchemaLine alloc] init];
	line.text = ORMSchemaOneLine(text);
	line.kind = kind;
	line.elementIds = ids ?: @[];
	[_lines addObject:line];
}

/* An element's note, a comment line a line of it, just before what it
 * is the note of. */
- (void)addNote:(NSString *)note of:(NSString *)elementId
{
	if ([ORMSchemaTrimmed(note ?: @"") length] == 0) {
		return;
	}
	[self gap];
	NSString *lines = [[ORMSchemaTrimmed(note) stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
		stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
	for (NSString *line in [lines componentsSeparatedByString:@"\n"]) {
		NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		[self add:[trimmed length] > 0 ? [@"// " stringByAppendingString:trimmed] : @"//" kind:ORMSchemaComment
		      ids:@[ elementId ]];
	}
}

#pragma mark What is said

/* The reading as a line: each player by name, its role's name after it
 * in the first ("(as Owner)"); the other readings after " / ". */
- (NSString *)readingLineOf:(ORMFactType *)fact
{
	NSMutableArray *readings = [NSMutableArray array];
	for (ORMReadingOrder *order in fact.readingOrders) {
		for (ORMReading *reading in order.readings) {
			NSString *text = reading.text ?: @"";
			NSMutableString *line = [NSMutableString string];
			NSUInteger i = 0;
			while (i < [text length]) {
				unichar c = [text characterAtIndex:i];
				NSRange close = c == '{' ? [text rangeOfString:@"}" options:0 range:NSMakeRange(i, [text length] - i)]
				                         : NSMakeRange(NSNotFound, 0);
				NSString *digits = close.location != NSNotFound ? [text substringWithRange:NSMakeRange(i + 1, close.location - i - 1)]
				                                                 : nil;
				if ([digits length] > 0 && [digits rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound
				    && (NSUInteger)[digits integerValue] < [order.roles count]) {
					ORMRole *role = [order.roles objectAtIndex:(NSUInteger)[digits integerValue]];
					[line appendString:ORMSchemaName(role.player.name)];
					if ([readings count] == 0 && [role.name length] > 0) {
						[line appendFormat:@" (as %@)", role.name];
					}
					i = close.location + 1;
					continue;
				}
				[line appendFormat:@"%C", c];
				i++;
			}
			[readings addObject:line];
		}
	}
	return [readings count] > 0 ? [readings componentsJoinedByString:@" / "] : fact.name;
}

- (void)sayObjectType:(ORMObjectType *)type
{
	[self addNote:type.noteText of:type.identifier];
	NSArray *sentences = [_verbalizer sentencesForElement:type.identifier];
	NSMutableDictionary *definitions = [NSMutableDictionary dictionary];
	NSMutableArray *values = [NSMutableArray array];
	for (ORMVerbalSentence *sentence in sentences) {
		NSString *text = [sentence text];
		if (sentence.kind != ORMVerbalStatement || sentence.level > 0) {
			continue;
		}
		NSString *each = [NSString stringWithFormat:@"Each %@ is by definition ", type.name];
		if ([text hasPrefix:each]) {
			for (ORMObjectType *supertype in type.supertypes) {
				for (NSString *article in @[ @"a ", @"an " ]) {
					NSString *head = [NSString stringWithFormat:@"%@%@%@ ", each, article, supertype.name];
					if ([text hasPrefix:head] || [text isEqualToString:[[head substringToIndex:[head length] - 1] stringByAppendingString:@"."]]) {
						[definitions setObject:text forKey:supertype.identifier];
					}
				}
			}
		} else if ([text hasPrefix:@"The possible values of "]) {
			[values addObject:text];
		}
	}
	BOOL subtype = [type.supertypes count] > 0;
	/* A subtype is made by its subtyping; one with an identifier of its
	 * own, or a value type, is declared first. */
	if (!subtype || type.kind == ORMValueType || type.referenceMode != nil) {
		[self add:[NSString stringWithFormat:@"%@ %@.", ORMSchemaName(type.name),
		                                     type.kind == ORMValueType ? @"is a value type" : @"is an entity type"]
		     kind:ORMSchemaObjectType ids:@[ type.identifier ]];
	}
	if (type.kind == ORMValueType) {
		if (type.dataType != nil && ![type.dataType.typeName isEqualToString:@"UnspecifiedDataType"]) {
			[self add:[@"Portable data type: " stringByAppendingString:ORMSchemaDataType(type)] kind:ORMSchemaDetail
			      ids:@[ type.identifier ]];
		}
	} else if (type.referenceMode != nil) {
		NSString *mode = type.referenceModeKind == ORMReferenceModePopular ? [@"." stringByAppendingString:type.referenceMode]
			: type.referenceModeKind == ORMReferenceModeUnitBased ? [type.referenceMode stringByAppendingString:@":"]
			: type.referenceMode;
		[self add:[@"Reference Mode: " stringByAppendingString:mode] kind:ORMSchemaDetail ids:@[ type.identifier ]];
		ORMObjectType *valueType = type.referenceModeValueType;
		NSString *fallback = ORMSchemaDefaultDataType(type.referenceMode, type.referenceModeKind);
		if (valueType.dataType != nil
		    && (![valueType.dataType.typeName isEqualToString:fallback] || valueType.dataTypeLength > 0 || valueType.dataTypeScale > 0)) {
			[self add:[@"Portable data type: " stringByAppendingString:ORMSchemaDataType(valueType)] kind:ORMSchemaDetail
			      ids:@[ type.identifier ]];
		}
	}
	for (ORMFactType *fact in type.supertypeFacts) {
		ORMObjectType *supertype = [fact supertype];
		NSString *definition = [definitions objectForKey:supertype.identifier];
		BOOL vowel = [supertype.name length] > 0 && [@"AEIOU" rangeOfString:[supertype.name substringToIndex:1]].location != NSNotFound;
		[self add:definition ?: [NSString stringWithFormat:@"Each %@ is %@ %@.", ORMSchemaName(type.name), vowel ? @"an" : @"a",
		                                                   ORMSchemaName(supertype.name)]
		     kind:ORMSchemaObjectType ids:@[ fact.identifier ]];
	}
	if (type.isIndependent && type.nestedFactType == nil) {
		[self add:[NSString stringWithFormat:@"%@ is independent.", ORMSchemaName(type.name)] kind:ORMSchemaDetail
		      ids:@[ type.identifier ]];
	}
	for (NSString *text in values) {
		[self add:text kind:ORMSchemaValues ids:@[ type.identifier ]];
	}
	if (type.isReferenceData) {
		[self sayReferenceDataOfType:type];
	}
}

/* "Reference data: Fuel": each instance of an entity type whose
 * instances are reference data, named as the population table names it. */
- (void)sayReferenceDataOfType:(ORMObjectType *)type
{
	ORMPopulationEditor *population = _editor.populationEditor;
	BOOL composite = [[population compositeRolesOf:type.identifier] count] > 0;
	/* One a subtype's instance is, said there when that subtype's are
	 * reference data too. */
	NSMutableSet *saidBelow = [NSMutableSet set];
	for (ORMObjectType *subtype in _model.objectTypes) {
		BOOL below = subtype != type && [subtype isSubtypeOf:type] && subtype.isReferenceData;
		for (ORMInstance *each in below ? [subtype instances] : @[]) {
			for (ORMInstance *above = [each supertypeInstance]; above != nil; above = [above supertypeInstance]) {
				[saidBelow addObject:above.identifier];
			}
		}
	}
	for (ORMInstance *instance in [type instances]) {
		if ([saidBelow containsObject:instance.identifier]) {
			continue;
		}
		[self add:[@"Reference data: " stringByAppendingString:ORMSchemaPart([population nameOf:instance], composite)]
		     kind:ORMSchemaReferenceData ids:@[ instance.identifier ]];
	}
}

- (void)sayFactType:(ORMFactType *)fact
{
	ORMObjectType *objectifying = fact.objectifyingType;
	NSString *note = [fact.noteText length] > 0 ? fact.noteText : objectifying.noteText;
	[self addNote:note of:[fact.noteText length] > 0 || objectifying == nil ? fact.identifier : objectifying.identifier];
	NSString *reading = [self readingLineOf:fact];
	if (objectifying != nil) {
		[self add:[NSString stringWithFormat:@"%@ is where %@.", ORMSchemaName(objectifying.name), reading]
		     kind:ORMSchemaFactType ids:@[ fact.identifier, objectifying.identifier ]];
	} else {
		[self add:reading kind:ORMSchemaFactType ids:@[ fact.identifier ]];
	}
	if ([fact.explicitName length] > 0 && ![fact.explicitName isEqualToString:[fact derivedName]]) {
		[self add:[@"Fact Type Name: " stringByAppendingString:fact.explicitName] kind:ORMSchemaFactTypeName
		      ids:@[ fact.identifier ]];
	}
	/* Its derivation: the modeller's words, or, where a query derives it
	 * (whose words NORMA's note then has), the query's name. */
	ORMDerivationRule *rule = [fact derivationRule];
	ORMQuery *derivation = [_derivations objectForKey:fact.identifier];
	NSString *words = derivation != nil ? [NSString stringWithFormat:@"By query %@.", derivation.name]
	                                    : ORMSchemaTrimmed(rule.informalText ?: @"");
	if (rule != nil && [words length] > 0) {
		NSString *mark = rule.isPartial ? (rule.isStored ? @"++" : @"+") : (rule.isStored ? @"**" : @"*");
		[self add:[NSString stringWithFormat:@"%@ %@", mark, words] kind:ORMSchemaDerivation ids:@[ fact.identifier ]];
	}
	/* Its constraints, as the verbalizer says them under it. */
	NSString *objectification = objectifying != nil ? [objectifying.name stringByAppendingString:@" is where "] : nil;
	NSMutableArray *lines = [NSMutableArray array];
	NSMutableArray *ids = [NSMutableArray array];
	NSMutableSet *spoken = [NSMutableSet set];
	/* An objectification's uniqueness over every role is what "is where"
	 * makes. */
	ORMConstraint *spanning = objectifying.preferredIdentifier;
	if (spanning != nil && [[spanning allRoles] count] == [fact.roles count]) {
		[spoken addObject:spanning.identifier];
	}
	for (ORMVerbalSentence *sentence in [_verbalizer sentencesForElement:fact.identifier]) {
		NSString *text = [sentence text];
		if (sentence.kind != ORMVerbalStatement || sentence.level == 0
		    || (objectification != nil && [text hasPrefix:objectification])
		    || (sentence.sourceId != nil && [sentence.sourceId isEqualToString:spanning.identifier])) {
			continue;
		}
		NSUInteger same = [lines indexOfObject:text];
		NSString *source = sentence.sourceId;
		if (same != NSNotFound) {
			if (source != nil && ![[ids objectAtIndex:same] containsObject:source]) {
				[[ids objectAtIndex:same] addObject:source];
			}
		} else {
			[lines addObject:text];
			[ids addObject:source != nil ? [NSMutableArray arrayWithObject:source] : [NSMutableArray array]];
		}
		if (source != nil) {
			[spoken addObject:source];
		}
	}
	/* A constraint said with another ("exactly one" is a uniqueness and a
	 * mandatory) goes with the line of the one over its roles. */
	for (ORMConstraint *constraint in [self constraintsSaidWith:fact]) {
		if ([spoken containsObject:constraint.identifier]) {
			continue;
		}
		NSSet *roles = [NSSet setWithArray:[constraint allRoles]];
		for (NSMutableArray *each in ids) {
			ORMConstraint *other = [_model elementWithId:[each firstObject]];
			if ([other isKindOfClass:[ORMConstraint class]] && [roles isSubsetOfSet:[NSSet setWithArray:[other allRoles]]]) {
				[each addObject:constraint.identifier];
				[spoken addObject:constraint.identifier];
				break;
			}
		}
	}
	/* Each the fact type's too, last: what tells apart the same words
	 * said of two fact types read alike. */
	for (NSUInteger i = 0; i < [lines count]; i++) {
		[self add:[lines objectAtIndex:i] kind:ORMSchemaConstraint
		      ids:[[ids objectAtIndex:i] arrayByAddingObject:fact.identifier]];
	}
	if (fact.isReferenceData) {
		[self sayReferenceDataOf:fact];
	}
}

/* The internal constraints said under a fact type. */
- (NSArray<ORMConstraint *> *)constraintsSaidWith:(ORMFactType *)fact
{
	NSMutableArray *constraints = [NSMutableArray array];
	for (ORMConstraint *constraint in _model.constraints) {
		NSArray *facts = [constraint factTypes];
		if (!constraint.isImplied && [facts count] == 1 && [facts firstObject] == fact
		    && (constraint.isInternal || constraint.kind == ORMFrequencyConstraint || constraint.kind == ORMRingConstraint
		        || constraint.kind == ORMMandatoryConstraint || constraint.kind == ORMUniquenessConstraint)) {
			[constraints addObject:constraint];
		}
	}
	return constraints;
}

/* "Reference data: km, 1": each role's player named as the population
 * table names it, in the order of the first reading's roles. */
- (void)sayReferenceDataOf:(ORMFactType *)fact
{
	NSMutableArray *roles = [NSMutableArray array];
	NSArray *visible = [fact visibleRoles];
	for (ORMRole *role in [(ORMReadingOrder *)[fact.readingOrders firstObject] roles] ?: visible) {
		if ([visible containsObject:role]) {
			[roles addObject:role];
		}
	}
	ORMPopulationEditor *population = _editor.populationEditor;
	for (ORMFactInstance *instance in [fact instances]) {
		NSMutableArray *parts = [NSMutableArray array];
		for (ORMRole *role in roles) {
			ORMInstance *player = [instance.instancesByRole objectForKey:role.identifier];
			BOOL composite = [[population compositeRolesOf:role.player.identifier] count] > 0;
			[parts addObject:ORMSchemaPart([population nameOf:player], composite)];
		}
		[self add:[@"Reference data: " stringByAppendingString:[parts componentsJoinedByString:@", "]]
		     kind:ORMSchemaReferenceData ids:@[ instance.identifier ]];
	}
}

- (void)sayConstraint:(ORMSchemaUnit *)unit
{
	ORMConstraint *constraint = unit.element;
	[self addNote:constraint.noteText of:constraint.identifier];
	for (NSString *identifier in unit.constraintIds) {
		ORMConstraint *each = [_model elementWithId:identifier];
		if (each != constraint && [each.noteText length] > 0) {
			[self addNote:each.noteText of:each.identifier];
		}
	}
	NSMutableArray *said = [NSMutableArray array];
	for (NSString *identifier in unit.constraintIds) {
		for (ORMVerbalSentence *sentence in [_verbalizer sentencesForElement:identifier]) {
			NSString *text = [sentence text];
			BOOL identification = sentence.kind == ORMVerbalInformation && [text hasPrefix:@"This association with "];
			if ((sentence.kind != ORMVerbalStatement && !identification) || sentence.level > 0 || [said containsObject:text]
			    || (sentence.sourceId != nil && ![unit.constraintIds containsObject:sentence.sourceId])) {
				continue;
			}
			[said addObject:text];
			[self add:text kind:ORMSchemaConstraint ids:unit.constraintIds];
		}
	}
}

- (void)sayQuery:(ORMStoredQuery *)stored query:(ORMQuery *)query
{
	[self gap];
	[self addNote:stored.noteText of:stored.identifier];
	[self add:[NSString stringWithFormat:@"Query %@:", query.name ?: stored.name ?: @""] kind:ORMSchemaQuery
	      ids:@[ stored.identifier ]];
	for (NSString *line in [[query outlineText] componentsSeparatedByString:@"\n"]) {
		if ([ORMSchemaTrimmed(line) length] > 0) {
			[self add:line kind:ORMSchemaOutline ids:@[ stored.identifier ]];
		}
	}
	[self gap];
}

#pragma mark The units

- (ORMSchemaUnit *)unitFor:(id)element key:(NSString *)key
{
	ORMSchemaUnit *unit = [[ORMSchemaUnit alloc] init];
	unit.key = key;
	unit.element = element;
	unit.section = NSNotFound;
	unit.position = NSNotFound;
	unit.dependencies = [NSMutableOrderedSet orderedSet];
	[_units setObject:unit forKey:key];
	[_ordered addObject:unit];
	[_unitOf setObject:key forKey:key];
	return unit;
}

/* The key of the unit that says the element; nil for what none says. */
- (NSString *)keyOf:(ORMElement *)element
{
	return element.identifier != nil ? [_unitOf objectForKey:element.identifier] : nil;
}

- (void)depend:(ORMSchemaUnit *)unit on:(ORMElement *)element
{
	NSString *key = [self keyOf:element];
	if (key != nil && ![key isEqualToString:unit.key]) {
		[unit.dependencies addObject:key];
	}
}

- (void)makeUnits
{
	_units = [NSMutableDictionary dictionary];
	_ordered = [NSMutableArray array];
	_unitOf = [NSMutableDictionary dictionary];
	_queries = [NSMutableDictionary dictionary];
	_derivations = [NSMutableDictionary dictionary];
	NSMutableSet *modeTypes = [NSMutableSet set];
	NSMutableSet *modeFacts = [NSMutableSet set];
	for (ORMObjectType *type in _model.objectTypes) {
		if (type.referenceModeValueType != nil && type.referenceModeValueType != type) {
			[modeTypes addObject:type.referenceModeValueType.identifier];
		}
		if (type.referenceModeFactType != nil) {
			[modeFacts addObject:type.referenceModeFactType.identifier];
		}
	}
	/* Object types, then fact types, then constraints, then queries: the
	 * order what no diagram shows is said in. */
	NSMutableArray *objectified = [NSMutableArray array];
	for (ORMObjectType *type in _model.objectTypes) {
		if (type.isImplicitBooleanValue || [modeTypes containsObject:type.identifier]) {
			continue;
		}
		if (type.nestedFactType != nil) {
			[objectified addObject:type];
			continue;
		}
		[self unitFor:type key:type.identifier];
	}
	for (ORMFactType *fact in _model.factTypes) {
		if (fact.kind == ORMFactTypeOrdinary && ![modeFacts containsObject:fact.identifier]) {
			[self unitFor:fact key:fact.identifier];
		}
	}
	for (ORMObjectType *type in objectified) {
		if ([_units objectForKey:type.nestedFactType.identifier] != nil) {
			[_unitOf setObject:type.nestedFactType.identifier forKey:type.identifier];
		}
	}
	for (ORMObjectType *type in _model.objectTypes) {
		if ([modeTypes containsObject:type.identifier]) {
			continue;
		}
		ORMObjectType *mode = type.referenceModeValueType;
		if (mode != nil && mode != type && [self keyOf:type] != nil) {
			[_unitOf setObject:[self keyOf:type] forKey:mode.identifier];
		}
		if (type.referenceModeFactType != nil && [self keyOf:type] != nil) {
			[_unitOf setObject:[self keyOf:type] forKey:type.referenceModeFactType.identifier];
		}
		for (ORMFactType *fact in type.supertypeFacts) {
			if ([self keyOf:type] != nil) {
				[_unitOf setObject:[self keyOf:type] forKey:fact.identifier];
			}
		}
	}
	for (ORMFactType *fact in _model.factTypes) {
		if (fact.kind == ORMFactTypeImplied && fact.impliedByFactType != nil && [self keyOf:fact.impliedByFactType] != nil) {
			[_unitOf setObject:[self keyOf:fact.impliedByFactType] forKey:fact.identifier];
		}
	}
	/* What each says first. */
	for (ORMSchemaUnit *unit in [_ordered copy]) {
		if ([unit.element isKindOfClass:[ORMObjectType class]]) {
			for (ORMObjectType *supertype in [(ORMObjectType *)unit.element supertypes]) {
				[self depend:unit on:supertype];
			}
		} else {
			for (ORMRole *role in [(ORMFactType *)unit.element visibleRoles]) {
				[self depend:unit on:role.player];
			}
		}
	}
	/* The constraints said with a fact type are its. */
	for (ORMSchemaUnit *unit in [_ordered copy]) {
		if ([unit.element isKindOfClass:[ORMFactType class]]) {
			for (ORMConstraint *constraint in [self constraintsSaidWith:unit.element]) {
				[_unitOf setObject:unit.key forKey:constraint.identifier];
			}
		}
	}
	for (ORMConstraint *constraint in _model.constraints) {
		if (constraint.isImplied || [_unitOf objectForKey:constraint.identifier] != nil) {
			continue;
		}
		/* A reference mode's, a link fact type's or a subtyping's: said
		 * by what it is part of. */
		NSMutableArray *facts = [NSMutableArray arrayWithArray:[constraint factTypes]];
		BOOL own = NO;
		for (ORMFactType *fact in facts) {
			own = own || [_units objectForKey:fact.identifier] != nil;
		}
		BOOL subtyping = [facts count] > 0;
		for (ORMFactType *fact in facts) {
			subtyping = subtyping && fact.kind == ORMFactTypeSubtype;
		}
		if ((!own && !subtyping) || (subtyping && (constraint.isInternal || [facts count] == 1))) {
			continue;
		}
		/* An exclusive-or is one statement of two constraints. */
		ORMConstraint *partner = constraint.exclusiveOrPartner;
		ORMSchemaUnit *partnerUnit = partner != nil ? [_units objectForKey:partner.identifier] : nil;
		if (partnerUnit != nil) {
			[partnerUnit.constraintIds addObject:constraint.identifier];
			[_unitOf setObject:partnerUnit.key forKey:constraint.identifier];
			continue;
		}
		ORMSchemaUnit *unit = [self unitFor:constraint key:constraint.identifier];
		unit.constraintIds = [NSMutableArray arrayWithObject:constraint.identifier];
		for (ORMRoleSequence *sequence in constraint.roleSequences) {
			ORMRolePathOwner *join = [sequence joinPath];
			for (ORMRolePath *path in join.paths) {
				ORMSchemaPathFacts(path, facts);
			}
		}
		for (ORMFactType *fact in facts) {
			[self depend:unit on:fact];
		}
		if (constraint.preferredIdentifierFor != nil) {
			[self depend:unit on:constraint.preferredIdentifierFor];
		}
	}
	/* Queries: after what they go through and derive. */
	NSDictionary *stored = [NSDictionary dictionaryWithObjects:_model.storedQueries
	                                                   forKeys:[_model.storedQueries valueForKey:@"identifier"]];
	for (ORMQuery *query in [ORMQuery queriesInModel:_model]) {
		ORMStoredQuery *element = [stored objectForKey:query.identifier];
		[_queries setObject:query forKey:query.identifier];
		if (query.kind == ORMQueryDerivation && query.derivedFactType != nil && [query.name length] > 0) {
			[_derivations setObject:query forKey:query.derivedFactType.identifier];
		}
		if (element == nil) {
			continue;
		}
		ORMSchemaUnit *unit = [self unitFor:element key:element.identifier];
		for (ORMQueryNode *node in [query nodes]) {
			[self depend:unit on:node.objectType];
			for (ORMQueryStep *step in node.steps) {
				[self depend:unit on:step.factType];
			}
		}
		[self depend:unit on:query.derivedFactType];
		[self depend:unit on:query.derivedSubtype];
	}
	/* Where the diagrams show them first. */
	NSUInteger position = 0;
	NSArray *diagrams = _model.diagrams;
	for (NSUInteger d = 0; d < [diagrams count]; d++) {
		for (ORMShape *shape in [[diagrams objectAtIndex:d] shapes]) {
			NSString *key = shape.subjectId != nil ? [_unitOf objectForKey:shape.subjectId] : nil;
			ORMSchemaUnit *unit = key != nil ? [_units objectForKey:key] : nil;
			if (unit != nil && unit.position == NSNotFound) {
				unit.position = position++;
				unit.section = d;
			}
		}
	}
}

#pragma mark Writing

- (void)say:(ORMSchemaUnit *)unit
{
	BOOL type = [unit.element isKindOfClass:[ORMObjectType class]];
	ORMSchemaLine *last = [_lines lastObject];
	BOOL afterType = last.kind == ORMSchemaObjectType || last.kind == ORMSchemaDetail || last.kind == ORMSchemaValues
		|| (last.kind == ORMSchemaReferenceData
		    && [[_model elementWithId:[last.elementIds firstObject]] isKindOfClass:[ORMInstance class]]);
	if (last != nil && last.kind != ORMSchemaBlank && last.kind != ORMSchemaHeading && type != afterType) {
		[self gap];
	}
	if (type) {
		[self sayObjectType:unit.element];
	} else if ([unit.element isKindOfClass:[ORMFactType class]]) {
		[self sayFactType:unit.element];
	} else if ([unit.element isKindOfClass:[ORMConstraint class]]) {
		[self sayConstraint:unit];
	} else {
		ORMStoredQuery *stored = unit.element;
		ORMQuery *query = [_queries objectForKey:stored.identifier];
		if (query != nil) {
			[self sayQuery:stored query:query];
		}
	}
}

- (NSArray<ORMSchemaLine *> *)lines
{
	_model = _editor.model;
	_verbalizer = [[ORMVerbalizer alloc] initWithModel:_model];
	_verbalizer.verbalizesPossibilities = NO;
	_verbalizer.verbalizesExamples = NO;
	_lines = [NSMutableArray array];
	_gap = NO;
	[self makeUnits];

	/* What the diagrams place, in their order (each place is one unit's);
	 * what they do not, in the model's. */
	NSMutableArray *slots = [NSMutableArray array];
	NSMutableArray *waiting = [NSMutableArray array];
	for (ORMSchemaUnit *unit in _ordered) {
		if (unit.position == NSNotFound) {
			[waiting addObject:unit];
			continue;
		}
		while ([slots count] <= unit.position) {
			[slots addObject:[NSNull null]];
		}
		[slots replaceObjectAtIndex:unit.position withObject:unit];
	}
	NSMutableArray *placed = [NSMutableArray array];
	for (id slot in slots) {
		if (slot != [NSNull null]) {
			[placed addObject:slot];
		}
	}
	NSMutableSet *done = [NSMutableSet set];
	NSMutableSet *going = [NSMutableSet set];
	__block NSUInteger section = NSNotFound;
	NSArray *diagrams = _model.diagrams;
	for (ORMSchemaUnit *unit in placed) {
		if ([done containsObject:unit.key]) {
			continue;
		}
		if (unit.section != section) {
			section = unit.section;
			[self gap];
			[self add:[@"# " stringByAppendingString:[(ORMDiagram *)[diagrams objectAtIndex:section] name] ?: @""]
			     kind:ORMSchemaHeading ids:@[ [(ORMDiagram *)[diagrams objectAtIndex:section] identifier] ]];
			[self gap];
		}
		[self emit:unit done:done going:going waiting:waiting];
	}
	/* What nothing placed: said in the model's order once what it names is. */
	while ([waiting count] > 0) {
		ORMSchemaUnit *next = [waiting firstObject];
		[self emit:next done:done going:going waiting:waiting];
	}
	return _lines;
}

/* The unit, what it names first, and then what was waiting for it. */
- (void)emit:(ORMSchemaUnit *)unit done:(NSMutableSet *)done going:(NSMutableSet *)going waiting:(NSMutableArray *)waiting
{
	if ([done containsObject:unit.key] || [going containsObject:unit.key]) {
		return;
	}
	[going addObject:unit.key];
	for (NSString *key in unit.dependencies) {
		ORMSchemaUnit *dependency = [_units objectForKey:key];
		if (dependency != nil) {
			[self emit:dependency done:done going:going waiting:waiting];
		}
	}
	[going removeObject:unit.key];
	if ([done containsObject:unit.key]) {
		return;
	}
	[done addObject:unit.key];
	[waiting removeObject:unit];
	[self say:unit];
	BOOL more = YES;
	while (more) {
		more = NO;
		for (ORMSchemaUnit *candidate in [waiting copy]) {
			BOOL ready = YES;
			for (NSString *key in candidate.dependencies) {
				ready = ready && ([done containsObject:key] || [_units objectForKey:key] == nil);
			}
			if (ready && ![done containsObject:candidate.key]) {
				[done addObject:candidate.key];
				[waiting removeObject:candidate];
				[self say:candidate];
				more = YES;
				break;
			}
		}
	}
}

- (NSString *)textFromFile:(NSString *)fileName
{
	NSArray *lines = [self lines];
	NSString *name = _model.name ?: [[fileName lastPathComponent] stringByDeletingPathExtension];
	NSMutableString *text = [NSMutableString string];
	[text appendFormat:@"// %@, as the verbalizer says it, a statement a line: written from\n"
	                   @"// %@ by ormtool forml. The model is the .orm: change it there, in\n"
	                   @"// ORMDesigner or with ormtool apply and lines like these, not here.\n"
	                   @"//\n"
	                   @"// Each \"# heading\" is a diagram. A line starting \"*\" (derived), \"**\"\n"
	                   @"// (derived and stored), \"+\" (partly derived) or \"++\" (partly, and stored)\n"
	                   @"// is the rule of the fact type on the line before; a comment just before\n"
	                   @"// a line is the note of what the line says.\n\n",
	                   name, [fileName lastPathComponent] ?: @"the model"];
	for (ORMSchemaLine *line in lines) {
		[text appendString:line.text];
		[text appendString:@"\n"];
	}
	while ([text hasSuffix:@"\n\n"]) {
		[text deleteCharactersInRange:NSMakeRange([text length] - 1, 1)];
	}
	return text;
}

@end
