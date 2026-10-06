/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMIssueFinder.h"
#import "ORMCoreDataMapper.h"
#import "ORMPopulationChecker.h"
#import "ORMQuery.h"
#import "ORMReadingText.h"
#import "ORMXML.h"

@interface ORMIssue ()
@property (nonatomic, readwrite) ORMIssueSeverity severity;
@property (nonatomic, readwrite, copy) NSString *area;
@property (nonatomic, readwrite, copy) NSString *text;
@property (nonatomic, readwrite, copy) NSString *elementId;
@end

@implementation ORMIssue

- (NSString *)description
{
	return self.text;
}

@end

@implementation ORMIssueFinder
{
	ORMModel *_model;
	ORMCoreDataMapping *_mapping;
	NSMutableArray<ORMIssue *> *_issues;
}

- (instancetype)initWithModel:(ORMModel *)model mapping:(ORMCoreDataMapping *)mapping
{
	if ((self = [super init])) {
		_model = model;
		_mapping = mapping;
	}
	return self;
}

- (void)add:(ORMIssueSeverity)severity area:(NSString *)area text:(NSString *)text about:(NSString *)elementId
{
	ORMIssue *issue = [[ORMIssue alloc] init];
	issue.severity = severity;
	issue.area = area;
	issue.text = text;
	issue.elementId = elementId;
	[_issues addObject:issue];
}

- (NSArray<ORMIssue *> *)issues
{
	_issues = [NSMutableArray array];
	[self modelErrors];
	[self readings];
	[self population];
	[self mapping];
	/* Errors, then warnings, then notes; each kind as found. */
	NSMutableArray *sorted = [NSMutableArray array];
	for (NSNumber *severity in @[ @(ORMIssueError), @(ORMIssueWarning), @(ORMIssueNote) ]) {
		for (ORMIssue *issue in _issues) {
			if (issue.severity == (ORMIssueSeverity)[severity integerValue]) {
				[sorted addObject:issue];
			}
		}
	}
	return sorted;
}

/* What NORMA reports as errors of the model itself. */
- (void)modelErrors
{
	for (ORMObjectType *type in [_model visibleObjectTypes]) {
		if (type.kind == ORMEntityType && !type.isImplicitBooleanValue && type.preferredIdentifier == nil
		    && [type.supertypes count] == 0) {
			[self add:ORMIssueError area:@"Model"
			     text:[NSString stringWithFormat:@"%@ has no reference scheme: nothing identifies it.", type.name]
			    about:type.identifier];
		}
	}
	for (ORMFactType *fact in [_model ordinaryFactTypes]) {
		NSString *reading = [[fact primaryReading] expandedText];
		NSString *name = reading ?: fact.name;
		if (reading == nil) {
			[self add:ORMIssueError area:@"Model" text:[NSString stringWithFormat:@"%@ has no reading.", fact.name]
			    about:fact.identifier];
		}
		if ([[fact visibleRoles] count] > 1 && [[fact uniquenessConstraints] count] == 0) {
			[self add:ORMIssueError area:@"Model"
			     text:[NSString stringWithFormat:@"\"%@\" has no uniqueness constraint.", name]
			    about:fact.identifier];
		}
	}
}

/* Readings that do not read, as NORMA finds them: placeholders that are
 * not the roles' (TooFew/TooManyReadingRoles), an order that is not the
 * fact type's roles, two fact types read the same way
 * (DuplicateReadingSignature); and, a warning, no words but the players. */
- (void)readings
{
	NSMutableDictionary<NSString *, ORMFactType *> *signatures = [NSMutableDictionary dictionary];
	for (ORMFactType *fact in [_model ordinaryFactTypes]) {
		NSString *name = [[fact primaryReading] expandedText] ?: fact.name;
		NSSet *roles = [NSSet setWithArray:fact.roles];
		for (ORMReadingOrder *order in fact.readingOrders) {
			/* A role the file names that is not there is dropped from order.roles. */
			NSXMLElement *sequence = ORMChild(order.element, ORMCoreNamespace, @"RoleSequence");
			NSUInteger named = [ORMChildren(sequence, ORMCoreNamespace, @"Role") count];
			NSSet *placed = [NSSet setWithArray:order.roles];
			BOOL covers = [placed isSubsetOfSet:roles] && [[NSSet setWithArray:[fact visibleRoles]] isSubsetOfSet:placed]
			              && named == [order.roles count];
			if (!covers) {
				[self add:ORMIssueError area:@"Model"
				     text:[NSString stringWithFormat:@"A reading order of \"%@\" does not place its roles: one is missing or not the fact type's.", name]
				    about:fact.identifier];
				continue;
			}
			for (ORMReading *reading in order.readings) {
				NSString *why = nil;
				if ([ORMReadingText readingTextWithString:reading.text arity:[order.roles count] reason:&why] == nil) {
					[self add:ORMIssueError area:@"Model"
					     text:[NSString stringWithFormat:@"The reading \"%@\" of \"%@\" does not read: %@", reading.text, name, why]
					    about:fact.identifier];
					continue;
				}
				if (![self hasWords:reading.text]) {
					[self add:ORMIssueWarning area:@"Model"
					     text:[NSString stringWithFormat:@"The reading \"%@\" has no words but its object types.", [reading expandedText]]
					    about:fact.identifier];
				}
				NSString *signature = [self signatureOf:reading];
				ORMFactType *other = signatures[signature];
				if (other == nil) {
					signatures[signature] = fact;
				} else if (other != fact) {
					[self add:ORMIssueError area:@"Model"
					     text:[NSString stringWithFormat:@"\"%@\" reads the same as \"%@\", another fact type.",
					                                     [reading expandedText], [[other primaryReading] expandedText] ?: other.name]
					    about:fact.identifier];
				}
			}
		}
	}
}

/* Whether a reading has words besides its placeholders. */
- (BOOL)hasWords:(NSString *)text
{
	NSMutableString *words = [text mutableCopy];
	NSRegularExpression *placeholder = [NSRegularExpression regularExpressionWithPattern:@"\\{[0-9]+\\}" options:0 error:NULL];
	[placeholder replaceMatchesInString:words options:0 range:NSMakeRange(0, [words length]) withTemplate:@""];
	return [[words stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0;
}

/* What a reading says, whatever fact type it is of: its words, spaced and
 * cased alike, with each placeholder its role's player. */
- (NSString *)signatureOf:(ORMReading *)reading
{
	NSMutableString *text = [[reading.text lowercaseString] mutableCopy];
	NSArray *roles = reading.readingOrder.roles;
	for (NSUInteger i = 0; i < [roles count]; i++) {
		NSString *player = [[roles[i] player] identifier] ?: @"?";
		[text replaceOccurrencesOfString:[NSString stringWithFormat:@"{%lu}", (unsigned long)i]
		                      withString:[NSString stringWithFormat:@"{%@}", player]
		                         options:0 range:NSMakeRange(0, [text length])];
	}
	return [[[text componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
		filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@" "];
}

/* What the sample population breaks, its rules too. */
- (void)population
{
	for (ORMPopulationViolation *violation in [[[ORMPopulationChecker alloc] initWithModel:_model] violations]) {
		BOOL deontic = violation.rule != nil ? violation.rule.isDeontic : violation.constraint.modality == ORMDeontic;
		NSString *about = violation.constraint.identifier ?: violation.rule.identifier ?: violation.factType.identifier;
		[self add:deontic ? ORMIssueWarning : ORMIssueError area:@"Population" text:violation.text about:about];
	}
}

/* What the mapping to Core Data warns of, or leaves unenforced. */
- (void)mapping
{
	ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:_model mapping:_mapping];
	[mapper map];
	for (ORMMappingNote *note in mapper.notes) {
		if (note.kind == ORMMappingAbsorbed) {
			continue;
		}
		[self add:note.kind == ORMMappingWarning ? ORMIssueWarning : ORMIssueNote area:@"Core Data" text:note.text
		    about:note.elementId];
	}
}

@end
