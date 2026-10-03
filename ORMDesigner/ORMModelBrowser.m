/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModelBrowser.h"

/* A row: a group's title, or an element. */
@interface ORMBrowserItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *elementId;
@property (nonatomic, strong) NSMutableArray<ORMBrowserItem *> *children;
@end

@implementation ORMBrowserItem
@end

static ORMBrowserItem *
ORMItem(NSString *title, NSString *elementId)
{
	ORMBrowserItem *item = [[ORMBrowserItem alloc] init];
	item.title = title;
	item.elementId = elementId;
	item.children = [NSMutableArray array];
	return item;
}

@implementation ORMModelBrowser
{
	NSMutableArray<ORMBrowserItem *> *_groups;
	/* The groups expanded before a filter expanded them all. */
	NSMutableSet<NSString *> *_expanded;
	BOOL _filtered;
	BOOL _revealing;
}

- (instancetype)initWithOutlineView:(NSOutlineView *)outlineView
{
	if ((self = [super init])) {
		_outlineView = outlineView;
		_groups = [NSMutableArray array];
		[outlineView setDataSource:(id)self];
		[outlineView setDelegate:(id)self];
		[outlineView setTarget:self];
		[outlineView setDoubleAction:@selector(doubleClicked:)];
	}
	return self;
}

static NSString *
ORMConstraintTitle(ORMConstraint *constraint)
{
	NSString *kind = @[ @"Uniqueness", @"Mandatory", @"Frequency", @"Ring", @"Subset", @"Equality", @"Exclusion",
	                    @"Value Comparison" ][constraint.kind];
	if (constraint.kind == ORMMandatoryConstraint && constraint.exclusiveOrPartner != nil) {
		kind = @"Exclusive Or";
	} else if (constraint.kind == ORMMandatoryConstraint) {
		kind = @"Inclusive Or";
	}
	return [NSString stringWithFormat:@"%@ (%@)", constraint.name, kind];
}

- (void)setFilter:(NSString *)filter
{
	_filter = [filter copy];
	[self reload];
}

- (BOOL)isFiltering
{
	return [[self.filter stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] > 0;
}

- (void)reload
{
	BOOL filtering = [self isFiltering];
	if (!_filtered) {
		_expanded = [NSMutableSet set];
		for (ORMBrowserItem *group in _groups) {
			if ([self.outlineView isItemExpanded:group]) {
				[_expanded addObject:group.title];
			}
		}
	}
	BOOL first = [_groups count] == 0;
	[_groups removeAllObjects];
	ORMModel *model = self.editor.model;

	ORMBrowserItem *types = ORMItem(@"Object Types", nil);
	NSArray *sorted = [[model visibleObjectTypes] sortedArrayUsingComparator:^NSComparisonResult(ORMObjectType *a,
	                                                                                             ORMObjectType *b) {
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	for (ORMObjectType *type in sorted) {
		[types.children addObject:ORMItem([type displayName], type.identifier)];
	}
	ORMBrowserItem *facts = ORMItem(@"Fact Types", nil);
	for (ORMFactType *fact in [model ordinaryFactTypes]) {
		NSString *title = [[fact primaryReading] expandedText] ?: fact.name;
		[facts.children addObject:ORMItem(title, fact.identifier)];
	}
	ORMBrowserItem *constraints = ORMItem(@"External Constraints", nil);
	for (ORMConstraint *constraint in [model externalConstraints]) {
		[constraints.children addObject:ORMItem(ORMConstraintTitle(constraint), constraint.identifier)];
	}
	ORMBrowserItem *diagrams = ORMItem(@"Diagrams", nil);
	for (ORMDiagram *diagram in model.diagrams) {
		[diagrams.children addObject:ORMItem(diagram.name, diagram.identifier)];
	}
	[_groups addObjectsFromArray:@[ types, facts, constraints, diagrams ]];
	if (filtering) {
		NSString *filter = [self.filter stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		for (ORMBrowserItem *group in _groups) {
			NSIndexSet *misses = [group.children indexesOfObjectsPassingTest:^BOOL(ORMBrowserItem *item, NSUInteger i,
			                                                                     BOOL *stop) {
				(void)i;
				(void)stop;
				return [item.title rangeOfString:filter options:NSCaseInsensitiveSearch].location == NSNotFound;
			}];
			[group.children removeObjectsAtIndexes:misses];
		}
		[_groups filterUsingPredicate:[NSPredicate predicateWithFormat:@"children.@count > 0"]];
	}
	[self.outlineView reloadData];
	for (ORMBrowserItem *group in _groups) {
		BOOL expand = filtering || (first ? group != constraints : [_expanded containsObject:group.title]);
		if (expand) {
			[self.outlineView expandItem:group];
		}
	}
	_filtered = filtering;
}

- (void)reveal:(NSString *)elementId
{
	for (ORMBrowserItem *group in _groups) {
		for (ORMBrowserItem *item in group.children) {
			if ([item.elementId isEqualToString:elementId]) {
				[self.outlineView expandItem:group];
				NSInteger row = [self.outlineView rowForItem:item];
				if (row >= 0) {
					_revealing = YES;
					[self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
					              byExtendingSelection:NO];
					[self.outlineView scrollRowToVisible:row];
					_revealing = NO;
				}
				return;
			}
		}
	}
	_revealing = YES;
	[self.outlineView deselectAll:nil];
	_revealing = NO;
}

- (void)doubleClicked:(id)sender
{
	(void)sender;
	ORMBrowserItem *item = [self.outlineView itemAtRow:[self.outlineView clickedRow]];
	if ([[self.editor.model elementWithId:item.elementId] isKindOfClass:[ORMDiagram class]]) {
		[self.delegate browser:self openDiagram:item.elementId];
	}
}

#pragma mark Data source

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	(void)outlineView;
	return item == nil ? (NSInteger)[_groups count] : (NSInteger)[[(ORMBrowserItem *)item children] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	(void)outlineView;
	NSArray *children = item == nil ? _groups : [(ORMBrowserItem *)item children];
	return [children objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	(void)outlineView;
	return [[(ORMBrowserItem *)item children] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
	(void)outlineView;
	(void)column;
	ORMBrowserItem *row = item;
	if (row.elementId == nil) {
		return [NSString stringWithFormat:@"%@ (%lu)", row.title, (unsigned long)[row.children count]];
	}
	return row.title;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)column item:(id)item
{
	(void)outlineView;
	(void)column;
	(void)item;
	return NO;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	(void)notification;
	if (_revealing) {
		return;
	}
	ORMBrowserItem *item = [self.outlineView itemAtRow:[self.outlineView selectedRow]];
	if (item.elementId != nil) {
		[self.delegate browser:self didSelect:item.elementId];
	}
}

@end
