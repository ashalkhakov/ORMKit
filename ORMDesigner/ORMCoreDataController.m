/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMCoreDataController.h"

/* A preview row: an entity, or one of its properties. */
@interface ORMPreviewItem : NSObject
@property (nonatomic, strong) ORMCDEntity *entity;
@property (nonatomic, strong) ORMCDProperty *property;
@property (nonatomic, strong) NSArray<ORMPreviewItem *> *children;
@end

@implementation ORMPreviewItem
@end

static NSArray *
ORMMappingTitles(void)
{
	return @[ @"Automatic", @"Entity", @"Absorbed", @"Ignored" ];
}

static NSArray *
ORMActionTitles(void)
{
	return @[ @"Apply to the ORM model", @"Keep in the mapping only", @"Discard (ORM wins)" ];
}

@implementation ORMCoreDataController
{
	NSPopUpButton *_mappings;
	NSTextField *_path;
	NSButton *_identifiers;
	NSButton *_flatten;
	NSButton *_valueSets;
	NSPopUpButton *_codegen;
	NSTextField *_status;
	NSTabView *_tabs;
	NSOutlineView *_preview;
	NSTableView *_types;
	NSPopUpButton *_typeMapping;
	NSTextView *_report;
	NSTableView *_changesTable;
	NSPopUpButton *_changeAction;
	NSArray<ORMPreviewItem *> *_items;
	NSArray<ORMObjectType *> *_objectTypes;
	ORMCoreDataSync *_sync;
}

- (instancetype)initWithEditor:(ORMEditor *)editor documentURL:(NSURL *)documentURL
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(160, 120, 900, 640)
	                                               styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
	                                                         | NSWindowStyleMaskResizable
	                                                 backing:NSBackingStoreBuffered
	                                                   defer:YES];
	[window setTitle:@"Core Data Mappings"];
	[window setReleasedWhenClosed:NO];
	[window setMinSize:NSMakeSize(640, 420)];
	if ((self = [super initWithWindow:window])) {
		_editor = editor;
		_documentURL = [documentURL copy];
		[self build];
		[self modelDidChange];
	}
	return self;
}

#pragma mark Building

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	[label setStringValue:text];
	[label setEditable:NO];
	[label setBordered:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	return label;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame
{
	NSButton *button = [[NSButton alloc] initWithFrame:frame];
	[button setTitle:title];
	[button setBezelStyle:NSBezelStyleRounded];
	[button setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[button setTarget:self];
	[button setAction:action];
	return button;
}

- (NSButton *)check:(NSString *)title action:(SEL)action frame:(NSRect)frame
{
	NSButton *check = [self button:title action:action frame:frame];
	[check setButtonType:NSButtonTypeSwitch];
	return check;
}

- (NSScrollView *)scroll:(NSView *)view frame:(NSRect)frame
{
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
	[scroll setHasVerticalScroller:YES];
	[scroll setBorderType:NSBezelBorder];
	[scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[scroll setDocumentView:view];
	return scroll;
}

- (NSTableColumn *)column:(NSString *)identifier title:(NSString *)title width:(double)width
{
	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:identifier];
	[[column headerCell] setStringValue:title];
	[column setWidth:width];
	[column setEditable:NO];
	return column;
}

- (void)build
{
	NSView *content = [[self window] contentView];
	NSRect bounds = [content bounds];
	double top = NSHeight(bounds);
	double width = NSWidth(bounds);

	[content addSubview:[self label:@"Mapping:" frame:NSMakeRect(12, top - 32, 60, 18)]];
	_mappings = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(74, top - 36, 220, 24) pullsDown:NO];
	[_mappings setTarget:self];
	[_mappings setAction:@selector(chooseMapping:)];
	[_mappings setAutoresizingMask:NSViewMinYMargin];
	[content addSubview:_mappings];
	NSButton *add = [self button:@"+" action:@selector(addMapping:) frame:NSMakeRect(298, top - 36, 30, 24)];
	NSButton *remove = [self button:@"−" action:@selector(removeMapping:) frame:NSMakeRect(330, top - 36, 30, 24)];
	NSButton *sync = [self button:@"Synchronize" action:@selector(synchronize:) frame:NSMakeRect(width - 130, top - 36, 118, 24)];
	for (NSView *view in @[ add, remove ]) {
		[view setAutoresizingMask:NSViewMinYMargin];
		[content addSubview:view];
	}
	[sync setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin];
	[content addSubview:sync];

	[content addSubview:[self label:@"Model:" frame:NSMakeRect(12, top - 62, 60, 18)]];
	_path = [[NSTextField alloc] initWithFrame:NSMakeRect(74, top - 64, width - 200, 22)];
	[_path setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[[_path cell] setSendsActionOnEndEditing:YES];
	[_path setTarget:self];
	[_path setAction:@selector(pathChanged:)];
	[_path setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
	[content addSubview:_path];
	NSButton *choose = [self button:@"Choose…" action:@selector(choosePath:) frame:NSMakeRect(width - 120, top - 64, 108, 24)];
	[choose setAutoresizingMask:NSViewMinYMargin | NSViewMinXMargin];
	[content addSubview:choose];

	_identifiers = [self check:@"Reference modes as attributes" action:@selector(optionChanged:)
	                     frame:NSMakeRect(74, top - 90, 210, 20)];
	_flatten = [self check:@"Flatten subtypes" action:@selector(optionChanged:) frame:NSMakeRect(290, top - 90, 130, 20)];
	_valueSets = [self check:@"Value sets as entities" action:@selector(optionChanged:)
	                   frame:NSMakeRect(424, top - 90, 170, 20)];
	for (NSView *view in @[ _identifiers, _flatten, _valueSets ]) {
		[view setAutoresizingMask:NSViewMinYMargin];
		[content addSubview:view];
	}

	_tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(8, 30, width - 16, top - 126)];
	[_tabs setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	NSRect inner = NSMakeRect(0, 0, NSWidth([_tabs frame]) - 20, NSHeight([_tabs frame]) - 40);

	_preview = [[NSOutlineView alloc] initWithFrame:inner];
	NSTableColumn *name = [self column:@"name" title:@"Entity / Property" width:220];
	[name setEditable:YES];
	[_preview addTableColumn:name];
	[_preview addTableColumn:[self column:@"type" title:@"Type" width:170]];
	[_preview addTableColumn:[self column:@"source" title:@"From the ORM model" width:360]];
	[_preview setOutlineTableColumn:name];
	[_preview setDataSource:(id)self];
	[_preview setDelegate:(id)self];
	NSTabViewItem *previewTab = [[NSTabViewItem alloc] initWithIdentifier:@"preview"];
	[previewTab setLabel:@"Entities"];
	[previewTab setView:[self scroll:_preview frame:inner]];
	[_tabs addTabViewItem:previewTab];

	NSView *typesPane = [[NSView alloc] initWithFrame:inner];
	_types = [[NSTableView alloc] initWithFrame:inner];
	[_types addTableColumn:[self column:@"objectType" title:@"Object Type" width:260]];
	[_types addTableColumn:[self column:@"mapping" title:@"Maps As" width:200]];
	[_types setDataSource:(id)self];
	[_types setDelegate:(id)self];
	NSScrollView *typesScroll = [self scroll:_types frame:NSMakeRect(0, 34, NSWidth(inner), NSHeight(inner) - 34)];
	[typesPane addSubview:typesScroll];
	[typesPane addSubview:[self label:@"Map the selected object type as:" frame:NSMakeRect(4, 8, 200, 18)]];
	_typeMapping = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(206, 4, 160, 24) pullsDown:NO];
	[_typeMapping addItemsWithTitles:ORMMappingTitles()];
	[_typeMapping setTarget:self];
	[_typeMapping setAction:@selector(typeMappingChanged:)];
	[typesPane addSubview:_typeMapping];
	NSTabViewItem *typesTab = [[NSTabViewItem alloc] initWithIdentifier:@"types"];
	[typesTab setLabel:@"Object Types"];
	[typesTab setView:typesPane];
	[_tabs addTabViewItem:typesTab];

	_report = [[NSTextView alloc] initWithFrame:inner];
	[_report setEditable:NO];
	[_report setBackgroundColor:[NSColor textBackgroundColor]];
	[_report setTextColor:[NSColor textColor]];
	[_report setFont:[NSFont systemFontOfSize:12]];
	NSTabViewItem *reportTab = [[NSTabViewItem alloc] initWithIdentifier:@"report"];
	[reportTab setLabel:@"Report"];
	[reportTab setView:[self scroll:_report frame:inner]];
	[_tabs addTabViewItem:reportTab];

	NSView *changesPane = [[NSView alloc] initWithFrame:inner];
	_changesTable = [[NSTableView alloc] initWithFrame:inner];
	[_changesTable addTableColumn:[self column:@"change" title:@"Changed in Core Data" width:440]];
	[_changesTable addTableColumn:[self column:@"action" title:@"Action" width:220]];
	[_changesTable setDataSource:(id)self];
	[_changesTable setDelegate:(id)self];
	[changesPane addSubview:[self scroll:_changesTable frame:NSMakeRect(0, 34, NSWidth(inner), NSHeight(inner) - 34)]];
	[changesPane addSubview:[self label:@"Action for the selected change:" frame:NSMakeRect(4, 8, 190, 18)]];
	_changeAction = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(196, 4, 210, 24) pullsDown:NO];
	[_changeAction addItemsWithTitles:ORMActionTitles()];
	[_changeAction setTarget:self];
	[_changeAction setAction:@selector(changeActionChanged:)];
	[changesPane addSubview:_changeAction];
	NSButton *apply = [self button:@"Apply and Write" action:@selector(applyAndWrite:)
	                         frame:NSMakeRect(NSWidth(inner) - 140, 4, 136, 24)];
	[apply setAutoresizingMask:NSViewMinXMargin];
	[changesPane addSubview:apply];
	NSTabViewItem *changesTab = [[NSTabViewItem alloc] initWithIdentifier:@"changes"];
	[changesTab setLabel:@"Changes"];
	[changesTab setView:changesPane];
	[_tabs addTabViewItem:changesTab];
	[content addSubview:_tabs];

	_status = [self label:@"" frame:NSMakeRect(12, 6, width - 24, 18)];
	[_status setAutoresizingMask:NSViewWidthSizable];
	[content addSubview:_status];
}

#pragma mark The mapping

- (ORMCoreDataMapping *)mapping
{
	return self.mappingId != nil ? [ORMCoreDataMapping mappingWithId:self.mappingId inDocument:self.editor.document] : nil;
}

- (void)say:(NSString *)message
{
	[_status setStringValue:message ?: @""];
}

- (void)modelDidChange
{
	NSArray *mappings = [ORMCoreDataMapping mappingsOfDocument:self.editor.document];
	if (self.mappingId == nil || [self mapping] == nil) {
		self.mappingId = [[mappings firstObject] identifier];
	}
	[_mappings removeAllItems];
	for (ORMCoreDataMapping *mapping in mappings) {
		[_mappings addItemWithTitle:mapping.name ?: @"Mapping"];
		[[_mappings lastItem] setRepresentedObject:mapping.identifier];
		if ([mapping.identifier isEqualToString:self.mappingId]) {
			[_mappings selectItem:[_mappings lastItem]];
		}
	}
	ORMCoreDataMapping *mapping = [self mapping];
	BOOL enabled = mapping != nil;
	for (NSControl *control in @[ _path, _identifiers, _flatten, _valueSets ]) {
		[control setEnabled:enabled];
	}
	[_path setStringValue:mapping.path ?: @""];
	[_identifiers setState:mapping == nil || mapping.materializesIdentifiers ? NSControlStateValueOn : NSControlStateValueOff];
	[_flatten setState:mapping.flattensSubtypes ? NSControlStateValueOn : NSControlStateValueOff];
	[_valueSets setState:mapping == nil || mapping.valueSetsAsEntities ? NSControlStateValueOn : NSControlStateValueOff];
	[self remap];
}

/* What the mapping maps to now, and its report. */
- (void)remap
{
	ORMCoreDataMapping *mapping = [self mapping] ?: [ORMCoreDataMapping defaultMappingNamed:self.editor.model.name];
	ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:self.editor.model mapping:mapping];
	ORMCDModel *mapped = [mapper map];
	NSMutableArray *items = [NSMutableArray array];
	NSSortDescriptor *byName = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
	for (ORMCDEntity *entity in [mapped.entities sortedArrayUsingDescriptors:@[ byName ]]) {
		ORMPreviewItem *item = [[ORMPreviewItem alloc] init];
		item.entity = entity;
		NSMutableArray *children = [NSMutableArray array];
		for (ORMCDProperty *property in [entity properties]) {
			ORMPreviewItem *child = [[ORMPreviewItem alloc] init];
			child.entity = entity;
			child.property = property;
			[children addObject:child];
		}
		item.children = children;
		[items addObject:item];
	}
	_items = items;
	[_preview reloadData];

	NSMutableString *report = [NSMutableString string];
	NSArray *headings = @[ @"Absorbed", @"Not enforced by Core Data", @"Notes" ];
	for (NSUInteger kind = 0; kind < 3; kind++) {
		NSMutableArray *lines = [NSMutableArray array];
		for (ORMMappingNote *note in mapper.notes) {
			if ((NSUInteger)note.kind == kind) {
				[lines addObject:[@"• " stringByAppendingString:note.text]];
			}
		}
		if ([lines count] > 0) {
			[report appendFormat:@"%@\n%@\n\n", [headings objectAtIndex:kind], [lines componentsJoinedByString:@"\n"]];
		}
	}
	[_report setString:[report length] > 0 ? report : @"Everything the model says, Core Data holds."];

	_objectTypes = [[self.editor.model visibleObjectTypes] sortedArrayUsingComparator:^NSComparisonResult(ORMObjectType *a,
	                                                                                                      ORMObjectType *b) {
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	[_types reloadData];
	[_changesTable reloadData];
	if (mapping.baseline == nil) {
		[self say:[NSString stringWithFormat:@"%lu entities. Not written yet: Synchronize writes the model.",
		                                     (unsigned long)[mapped.entities count]]];
	}
}

/* The mapping's .xcdatamodeld, made absolute. */
- (NSString *)resolvedPath
{
	ORMCoreDataMapping *mapping = [self mapping];
	if (mapping == nil) {
		return nil;
	}
	return [mapping resolvedPathRelativeTo:[self.documentURL path]];
}

#pragma mark Actions

- (IBAction)chooseMapping:(id)sender
{
	(void)sender;
	self.mappingId = [[_mappings selectedItem] representedObject];
	_sync = nil;
	[self modelDidChange];
}

- (IBAction)addMapping:(id)sender
{
	(void)sender;
	NSString *base = self.editor.model.name ?: @"Model";
	NSString *name = [[ORMCoreDataMapper entityNameFor:base] length] > 0 ? [ORMCoreDataMapper entityNameFor:base] : @"Model";
	self.mappingId = [self.editor addCoreDataMappingNamed:name path:[name stringByAppendingPathExtension:@"xcdatamodeld"]];
	[self modelDidChange];
}

- (IBAction)removeMapping:(id)sender
{
	(void)sender;
	if (self.mappingId != nil) {
		[self.editor removeCoreDataMapping:self.mappingId];
		self.mappingId = nil;
		[self modelDidChange];
	}
}

- (void)pathChanged:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	if (self.mappingId != nil && ![[_path stringValue] isEqualToString:[self mapping].path]
	    && ![self.editor setPath:[_path stringValue] ofMapping:self.mappingId reason:&reason]) {
		NSBeep();
		[self say:reason];
		[_path setStringValue:[self mapping].path ?: @""];
	}
}

/* A path relative to the document's directory when it is under it. */
- (NSString *)pathRelativeToDocument:(NSString *)path
{
	NSString *directory = [[self.documentURL path] stringByDeletingLastPathComponent];
	if (directory != nil && [path hasPrefix:[directory stringByAppendingString:@"/"]]) {
		return [path substringFromIndex:[directory length] + 1];
	}
	return path;
}

- (void)choosePath:(id)sender
{
	(void)sender;
	if (self.mappingId == nil) {
		[self addMapping:nil];
	}
	NSSavePanel *panel = [NSSavePanel savePanel];
	[panel setAllowedFileTypes:@[ @"xcdatamodeld" ]];
	[panel setNameFieldStringValue:[[self mapping].path lastPathComponent] ?: @"Model.xcdatamodeld"];
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}
	[self.editor setPath:[self pathRelativeToDocument:[[panel URL] path]] ofMapping:self.mappingId reason:NULL];
	[self modelDidChange];
}

- (void)optionChanged:(id)sender
{
	if (self.mappingId == nil) {
		return;
	}
	BOOL on = [sender state] == NSControlStateValueOn;
	if (sender == _identifiers) {
		[self.editor setMaterializesIdentifiers:on ofMapping:self.mappingId];
	} else if (sender == _flatten) {
		[self.editor setFlattensSubtypes:on ofMapping:self.mappingId];
	} else if (sender == _valueSets) {
		[self.editor setValueSetsAsEntities:on ofMapping:self.mappingId];
	}
}

- (void)typeMappingChanged:(id)sender
{
	(void)sender;
	NSInteger row = [_types selectedRow];
	if (row < 0 || (NSUInteger)row >= [_objectTypes count]) {
		NSBeep();
		[self say:@"Select an object type first."];
		return;
	}
	if (self.mappingId == nil) {
		[self addMapping:nil];
	}
	ORMObjectType *type = [_objectTypes objectAtIndex:(NSUInteger)row];
	[self.editor setMapping:(ORMObjectTypeMapping)[_typeMapping indexOfSelectedItem] ofObjectType:type.identifier
	              inMapping:self.mappingId];
}

- (void)changeActionChanged:(id)sender
{
	(void)sender;
	NSInteger row = [_changesTable selectedRow];
	if (_sync == nil || row < 0 || (NSUInteger)row >= [_sync.changes count]) {
		return;
	}
	ORMSyncChange *change = [_sync.changes objectAtIndex:(NSUInteger)row];
	ORMSyncAction action = (ORMSyncAction)[_changeAction indexOfSelectedItem];
	if (![change.possibleActions containsObject:@(action)]) {
		NSBeep();
		[self say:@"That change cannot be made that way."];
		[_changeAction selectItemAtIndex:change.action];
		return;
	}
	change.action = action;
	[_changesTable reloadData];
}

- (IBAction)synchronize:(id)sender
{
	(void)sender;
	if (self.mappingId == nil) {
		[self addMapping:nil];
	}
	NSString *path = [self resolvedPath];
	if (![path isAbsolutePath]) {
		NSBeep();
		[self say:@"Save the model first: the Core Data model's path is relative to it."];
		return;
	}
	BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
	NSString *reason = nil;
	ORMCDModel *theirs = exists ? [ORMCDModel modelAtPath:path reason:&reason] : nil;
	if (exists && theirs == nil) {
		NSBeep();
		[self say:reason];
		return;
	}
	_sync = [[ORMCoreDataSync alloc] initWithEditor:self.editor mapping:self.mappingId theirs:theirs];
	[_changesTable reloadData];
	if ([_sync.changes count] == 0) {
		[self applyAndWrite:nil];
		return;
	}
	[_tabs selectTabViewItemWithIdentifier:@"changes"];
	[self say:[NSString stringWithFormat:@"%lu changes were made in Core Data. Choose what each does, then Apply "
	                                     @"and Write.", (unsigned long)[_sync.changes count]]];
}

- (IBAction)applyAndWrite:(id)sender
{
	(void)sender;
	if (_sync == nil) {
		[self synchronize:nil];
		return;
	}
	ORMCDModel *written = [_sync apply];
	_sync = nil;
	NSString *path = [self resolvedPath];
	NSError *error = nil;
	if (![written writeToPackage:path error:&error]) {
		NSBeep();
		[self say:[error localizedDescription]];
		return;
	}
	[_changesTable reloadData];
	[self modelDidChange];
	[self say:[NSString stringWithFormat:@"Wrote %lu entities to %@.", (unsigned long)[written.entities count], path]];
}

#pragma mark Tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == _types) {
		return (NSInteger)[_objectTypes count];
	}
	if (tableView == _changesTable) {
		return (NSInteger)[_sync.changes count];
	}
	return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if (tableView == _types) {
		ORMObjectType *type = [_objectTypes objectAtIndex:(NSUInteger)row];
		if ([[column identifier] isEqual:@"objectType"]) {
			return [type displayName];
		}
		ORMCoreDataMapping *mapping = [self mapping];
		ORMObjectTypeMapping how = mapping != nil ? [mapping mappingOfObjectType:type.identifier] : ORMMapAutomatically;
		if (how == ORMMapAutomatically) {
			ORMCoreDataMapper *mapper = [[ORMCoreDataMapper alloc] initWithModel:self.editor.model mapping:mapping];
			ORMObjectTypeMapping automatic = [mapper automaticMappingOf:type];
			return [NSString stringWithFormat:@"Automatic: %@", type.kind == ORMValueType ? @"Attribute"
			                                  : [ORMMappingTitles() objectAtIndex:automatic]];
		}
		return [ORMMappingTitles() objectAtIndex:how];
	}
	if (tableView == _changesTable) {
		ORMSyncChange *change = [_sync.changes objectAtIndex:(NSUInteger)row];
		if ([[column identifier] isEqual:@"change"]) {
			return change.conflicts ? [change.text stringByAppendingString:@" (changed in ORM too)"] : change.text;
		}
		return [ORMActionTitles() objectAtIndex:change.action];
	}
	return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	NSTableView *table = [notification object];
	NSInteger row = [table selectedRow];
	if (table == _types && row >= 0) {
		ORMObjectType *type = [_objectTypes objectAtIndex:(NSUInteger)row];
		[_typeMapping selectItemAtIndex:[[self mapping] mappingOfObjectType:type.identifier]];
	} else if (table == _changesTable && row >= 0 && _sync != nil) {
		[_changeAction selectItemAtIndex:[[_sync.changes objectAtIndex:(NSUInteger)row] action]];
	}
}

#pragma mark Preview

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	(void)outlineView;
	return item == nil ? (NSInteger)[_items count] : (NSInteger)[[(ORMPreviewItem *)item children] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	(void)outlineView;
	NSArray *children = item == nil ? _items : [(ORMPreviewItem *)item children];
	return [children objectAtIndex:(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	(void)outlineView;
	return [[(ORMPreviewItem *)item children] count] > 0;
}

/* What an ORM element a property or entity maps reads as. */
- (NSString *)sourceText:(NSString *)source
{
	id element = [self.editor.model elementWithId:source];
	if ([element isKindOfClass:[ORMRole class]]) {
		ORMFactType *fact = [(ORMRole *)element factType];
		return [[fact primaryReading] expandedText] ?: fact.name;
	}
	if ([element isKindOfClass:[ORMObjectType class]]) {
		return [NSString stringWithFormat:@"%@ (%@)", [(ORMObjectType *)element displayName],
		        [(ORMObjectType *)element kind] == ORMValueType ? @"value type" : @"entity type"];
	}
	if ([element isKindOfClass:[ORMFactType class]]) {
		return [[(ORMFactType *)element primaryReading] expandedText] ?: [element name];
	}
	return @"";
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item
{
	(void)outlineView;
	ORMPreviewItem *row = item;
	NSString *identifier = [column identifier];
	if (row.property == nil) {
		ORMCDEntity *entity = row.entity;
		if ([identifier isEqual:@"name"]) {
			return entity.name;
		}
		if ([identifier isEqual:@"type"]) {
			NSMutableString *type = [NSMutableString stringWithString:entity.isAbstract ? @"abstract entity" : @"entity"];
			if (entity.parentName != nil) {
				[type appendFormat:@" : %@", entity.parentName];
			}
			return type;
		}
		return [self sourceText:entity.source];
	}
	ORMCDProperty *property = row.property;
	if ([identifier isEqual:@"name"]) {
		return property.name;
	}
	if ([identifier isEqual:@"type"]) {
		if ([property isKindOfClass:[ORMCDAttribute class]]) {
			return [NSString stringWithFormat:@"%@%@", [(ORMCDAttribute *)property attributeType],
			        property.optional ? @"?" : @""];
		}
		ORMCDRelationship *relationship = (ORMCDRelationship *)property;
		return [NSString stringWithFormat:@"%@%@%@", relationship.toMany ? @"to-many " : @"→ ",
		        relationship.destination, relationship.optional && !relationship.toMany ? @"?" : @""];
	}
	return [self sourceText:property.source];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)column item:(id)item
{
	(void)outlineView;
	ORMPreviewItem *row = item;
	NSString *source = row.property != nil ? row.property.source : row.entity.source;
	return [[column identifier] isEqual:@"name"] && source != nil;
}

/* A name typed here is the mapping's name for the element. */
- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column
             byItem:(id)item
{
	(void)outlineView;
	(void)column;
	ORMPreviewItem *row = item;
	NSString *source = row.property != nil ? row.property.source : row.entity.source;
	if (source == nil) {
		return;
	}
	if (self.mappingId == nil) {
		[self addMapping:nil];
	}
	[self.editor setName:[value description] forSource:source inMapping:self.mappingId];
}

@end
