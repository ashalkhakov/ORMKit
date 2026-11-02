/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMSearchNavigator.h"

/* A row: an element whose sentences hold the text, or one of them. */
@interface ORMSearchHit : NSObject
@property (nonatomic, copy) NSString *elementId;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<ORMSearchHit *> *sentences;
@end

@implementation ORMSearchHit
@end

@implementation ORMSearchNavigator
{
	NSString *_text;
	NSArray<ORMSearchHit *> *_groups;
	BOOL _reloading;
}

- (instancetype)initWithFrame:(NSRect)frame
{
	if ((self = [super initWithFrame:frame])) {
		if (!ORMLoadPaneNib(self, @"ORMSearchNavigator")) {
			return nil;
		}
		ORMFillHost(self, _content);
		_groups = @[];
	}
	return self;
}

- (IBAction)searchChanged:(id)sender
{
	[self searchFor:[sender stringValue]];
}

- (void)searchFor:(NSString *)text
{
	_text = [text copy];
	if (![[_field stringValue] isEqualToString:text ?: @""]) {
		[_field setStringValue:text ?: @""];
	}
	[self reload];
}

- (void)reload
{
	NSMutableArray *groups = [NSMutableArray array];
	if ([_text length] > 0 && self.editor != nil) {
		NSMutableDictionary *byElement = [NSMutableDictionary dictionary];
		for (ORMVerbalSentence *sentence in [[[ORMVerbalizer alloc] initWithModel:self.editor.model] sentencesForModel]) {
			NSString *said = [sentence text];
			if ([said rangeOfString:_text options:NSCaseInsensitiveSearch].location == NSNotFound) {
				continue;
			}
			/* Under what it is about; chosen, what says it. */
			NSString *about = sentence.subjectId ?: sentence.sourceId;
			ORMSearchHit *group = about != nil ? [byElement objectForKey:about] : nil;
			if (group == nil && about != nil) {
				group = [[ORMSearchHit alloc] init];
				group.elementId = about;
				ORMElement *element = [self.editor.model elementWithId:about];
				group.text = [element respondsToSelector:@selector(name)] ? [(id)element name] : about;
				group.sentences = @[];
				[byElement setObject:group forKey:about];
				[groups addObject:group];
			}
			ORMSearchHit *hit = [[ORMSearchHit alloc] init];
			hit.elementId = sentence.sourceId ?: about;
			hit.text = said;
			group.sentences = [group.sentences arrayByAddingObject:hit];
		}
	}
	_groups = groups;
	_reloading = YES;
	[_outline reloadData];
	for (ORMSearchHit *group in _groups) {
		[_outline expandItem:group];
	}
	_reloading = NO;
	NSUInteger sentences = 0;
	for (ORMSearchHit *group in _groups) {
		sentences += [group.sentences count];
	}
	[_summary setStringValue:[_text length] == 0 ? @""
	                                              : [NSString stringWithFormat:@"%lu %@ in %lu %@", (unsigned long)sentences,
	                                                                           sentences == 1 ? @"sentence" : @"sentences",
	                                                                           (unsigned long)[_groups count],
	                                                                           [_groups count] == 1 ? @"element" : @"elements"]];
}

- (NSArray<NSArray *> *)found
{
	NSMutableArray *found = [NSMutableArray array];
	for (ORMSearchHit *group in _groups) {
		[found addObject:@[ group.elementId, [group.sentences valueForKey:@"text"] ]];
	}
	return found;
}

#pragma mark The outline

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	(void)outlineView;
	return item == nil ? (NSInteger)[_groups count] : (NSInteger)[[(ORMSearchHit *)item sentences] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	(void)outlineView;
	return item == nil ? [_groups objectAtIndex:(NSUInteger)index]
	                   : [[(ORMSearchHit *)item sentences] objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	(void)outlineView;
	return [[(ORMSearchHit *)item sentences] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
	(void)outlineView;
	(void)column;
	return [(ORMSearchHit *)item text];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
	(void)notification;
	NSInteger row = [_outline selectedRow];
	if (_reloading || row < 0) {
		return;
	}
	NSString *element = [(ORMSearchHit *)[_outline itemAtRow:row] elementId];
	if (element != nil) {
		[self.delegate navigatorDidChooseElement:element];
	}
}

@end
