/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMIssueFinder.h"
#import "ORMCoreDataMapper.h"
#import "ORMPopulationChecker.h"
#import "ORMQuery.h"

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
