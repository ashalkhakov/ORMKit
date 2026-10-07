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
	return @[ @"Automatic", @"Entity", @"Absorbed", @"Ignored", @"Transformable", @"Joined" ];
}

static NSArray *
ORMActionTitles(void)
{
	return @[ @"Apply to the ORM model", @"Keep in the mapping only", @"Discard (ORM wins)" ];
}

@interface ORMCoreDataController ()
@property (nonatomic, strong) IBOutlet NSPopUpButton *mappingPopUp;
@property (nonatomic, strong) IBOutlet NSTextField *pathField;
@property (nonatomic, strong) IBOutlet NSTextField *validationPathField;
@property (nonatomic, strong) IBOutlet NSButton *identifiersCheck;
@property (nonatomic, strong) IBOutlet NSButton *flattenCheck;
@property (nonatomic, strong) IBOutlet NSButton *valueSetsCheck;
@property (nonatomic, strong) IBOutlet NSButton *absorbIdentifiersCheck;
@property (nonatomic, strong) IBOutlet NSPopUpButton *stylePopUp;
@property (nonatomic, strong) IBOutlet NSTextField *transformableClassField;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSTabView *tabs;
@property (nonatomic, strong) IBOutlet NSOutlineView *preview;
@property (nonatomic, strong) IBOutlet NSTableView *typesTable;
@property (nonatomic, strong) IBOutlet NSPopUpButton *typeMappingPopUp;
@property (nonatomic, strong) IBOutlet NSTextView *reportView;
@property (nonatomic, strong) IBOutlet NSTableView *changesTable;
@property (nonatomic, strong) IBOutlet NSPopUpButton *changeActionPopUp;
@end

@implementation ORMCoreDataController
{
	NSArray<ORMPreviewItem *> *_items;
	NSArray<ORMObjectType *> *_objectTypes;
	ORMCoreDataSync *_sync;
}

- (instancetype)initWithEditor:(ORMEditor *)editor documentURL:(NSURL *)documentURL
{
	if ((self = [super initWithWindowNibName:@"ORMCoreDataWindow"])) {
		_editor = editor;
		_documentURL = [documentURL copy];
		[self window];
	}
	return self;
}

/* What the XIB does not say: the report's font. */
- (void)windowDidLoad
{
	[super windowDidLoad];
	[self.reportView setFont:[NSFont systemFontOfSize:12]];
	[self modelDidChange];
}

#pragma mark The mapping

/* The document's mappings, edited. */
- (ORMMappingEditor *)mappings
{
	return [[ORMMappingEditor alloc] initWithEditor:self.editor];
}

- (ORMCoreDataMapping *)mapping
{
	return self.mappingId != nil ? [ORMCoreDataMapping mappingWithId:self.mappingId inDocument:self.editor.document] : nil;
}

- (void)say:(NSString *)message
{
	[_statusLabel setStringValue:message ?: @""];
}

- (void)modelDidChange
{
	NSArray *mappings = [ORMCoreDataMapping mappingsOfDocument:self.editor.document];
	if (self.mappingId == nil || [self mapping] == nil) {
		self.mappingId = [[mappings firstObject] identifier];
	}
	[_mappingPopUp removeAllItems];
	for (ORMCoreDataMapping *mapping in mappings) {
		[_mappingPopUp addItemWithTitle:mapping.name ?: @"Mapping"];
		[[_mappingPopUp lastItem] setRepresentedObject:mapping.identifier];
		if ([mapping.identifier isEqualToString:self.mappingId]) {
			[_mappingPopUp selectItem:[_mappingPopUp lastItem]];
		}
	}
	ORMCoreDataMapping *mapping = [self mapping];
	BOOL enabled = mapping != nil;
	for (NSControl *control in @[ _pathField, _validationPathField, _identifiersCheck, _flattenCheck, _valueSetsCheck, _absorbIdentifiersCheck, _stylePopUp ]) {
		[control setEnabled:enabled];
	}
	[_pathField setStringValue:mapping.path ?: @""];
	[_validationPathField setStringValue:mapping.validationPath ?: @""];
	[_identifiersCheck setState:mapping == nil || mapping.materializesIdentifiers ? NSControlStateValueOn : NSControlStateValueOff];
	[_flattenCheck setState:mapping.flattensSubtypes ? NSControlStateValueOn : NSControlStateValueOff];
	[_valueSetsCheck setState:mapping == nil || mapping.valueSetsAsEntities ? NSControlStateValueOn : NSControlStateValueOff];
	[_absorbIdentifiersCheck setState:mapping.absorbsIdentifierTypes ? NSControlStateValueOn : NSControlStateValueOff];
	[_stylePopUp selectItemAtIndex:mapping != nil ? mapping.style : ORMStyleApplication];
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
	[_reportView setString:[report length] > 0 ? report : @"Everything the model says, Core Data holds."];

	_objectTypes = [[self.editor.model visibleObjectTypes] sortedArrayUsingComparator:^NSComparisonResult(ORMObjectType *a,
	                                                                                                      ORMObjectType *b) {
		return [a.name localizedCaseInsensitiveCompare:b.name];
	}];
	[_typesTable reloadData];
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
	self.mappingId = [[_mappingPopUp selectedItem] representedObject];
	_sync = nil;
	[self modelDidChange];
}

- (IBAction)addMapping:(id)sender
{
	(void)sender;
	NSString *base = self.editor.model.name ?: @"Model";
	NSString *name = [[ORMCoreDataMapper entityNameFor:base] length] > 0 ? [ORMCoreDataMapper entityNameFor:base] : @"Model";
	self.mappingId = [[self mappings] addCoreDataMappingNamed:name path:[name stringByAppendingPathExtension:@"xcdatamodeld"]];
	[self modelDidChange];
}

- (IBAction)removeMapping:(id)sender
{
	(void)sender;
	if (self.mappingId != nil) {
		[[self mappings] removeCoreDataMapping:self.mappingId];
		self.mappingId = nil;
		[self modelDidChange];
	}
}

- (void)pathChanged:(id)sender
{
	(void)sender;
	NSString *reason = nil;
	if (self.mappingId != nil && ![[_pathField stringValue] isEqualToString:[self mapping].path]
	    && ![[self mappings] setPath:[_pathField stringValue] ofMapping:self.mappingId reason:&reason]) {
		NSBeep();
		[self say:reason];
		[_pathField setStringValue:[self mapping].path ?: @""];
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
	[[self mappings] setPath:[self pathRelativeToDocument:[[panel URL] path]] ofMapping:self.mappingId reason:NULL];
	[self modelDidChange];
}

- (void)validationPathChanged:(id)sender
{
	(void)sender;
	if (self.mappingId != nil && ![[_validationPathField stringValue] isEqualToString:[self mapping].validationPath ?: @""]) {
		[[self mappings] setValidationPath:[_validationPathField stringValue] ofMapping:self.mappingId];
	}
}

- (void)chooseValidationPath:(id)sender
{
	(void)sender;
	if (self.mappingId == nil) {
		[self addMapping:nil];
	}
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setCanChooseDirectories:YES];
	[panel setCanChooseFiles:NO];
	[panel setCanCreateDirectories:YES];
	[panel setPrompt:@"Choose"];
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}
	[[self mappings] setValidationPath:[self pathRelativeToDocument:[[panel URL] path]] ofMapping:self.mappingId];
	[self modelDidChange];
}

- (void)styleChanged:(id)sender
{
	(void)sender;
	if (self.mappingId == nil) {
		return;
	}
	[[self mappings] setStyle:(ORMMappingStyle)[_stylePopUp indexOfSelectedItem] ofMapping:self.mappingId];
}

- (void)optionChanged:(id)sender
{
	if (self.mappingId == nil) {
		return;
	}
	BOOL on = [sender state] == NSControlStateValueOn;
	if (sender == _identifiersCheck) {
		[[self mappings] setMaterializesIdentifiers:on ofMapping:self.mappingId];
	} else if (sender == _flattenCheck) {
		[[self mappings] setFlattensSubtypes:on ofMapping:self.mappingId];
	} else if (sender == _valueSetsCheck) {
		[[self mappings] setValueSetsAsEntities:on ofMapping:self.mappingId];
	} else if (sender == _absorbIdentifiersCheck) {
		[[self mappings] setAbsorbsIdentifierTypes:on ofMapping:self.mappingId];
	}
}

/* "Kept in CRMCustomer; BillingAccount (outer, by UserId); Subscriber
 * (outer, by Guid, through CRMCustomer)": a joined type's members. */
- (NSString *)membersTextOf:(ORMObjectType *)type
{
	NSArray<ORMJoinMember *> *members = [[self mapping].joins objectForKey:type.identifier];
	NSMutableArray *parts = [NSMutableArray array];
	for (ORMJoinMember *member in members) {
		if (member == [members firstObject]) {
			[parts addObject:member.name];
			continue;
		}
		ORMConstraint *by = member.correlationId != nil ? [self.editor.model elementWithId:member.correlationId]
		                                                : type.preferredIdentifier;
		NSArray *values = [[by allRoles] valueForKeyPath:@"player.name"] ?: @[];
		NSMutableArray *says = [NSMutableArray array];
		if (member.isOuter) {
			[says addObject:@"outer"];
		}
		[says addObject:[NSString stringWithFormat:@"by %@", [values componentsJoinedByString:@" and "]]];
		for (ORMJoinMember *via in members) {
			if (via != [members firstObject] && [via.identifier isEqualToString:member.viaId]) {
				[says addObject:[NSString stringWithFormat:@"through %@", via.name]];
			}
		}
		[parts addObject:[NSString stringWithFormat:@"%@ (%@)", member.name, [says componentsJoinedByString:@", "]]];
	}
	return [NSString stringWithFormat:@"%@ is kept in %@.", type.name, [parts componentsJoinedByString:@"; "]];
}

- (void)typeMappingChanged:(id)sender
{
	(void)sender;
	NSInteger row = [_typesTable selectedRow];
	if (row < 0 || (NSUInteger)row >= [_objectTypes count]) {
		NSBeep();
		[self say:@"Select an object type first."];
		return;
	}
	if (self.mappingId == nil) {
		[self addMapping:nil];
	}
	ORMObjectType *type = [_objectTypes objectAtIndex:(NSUInteger)row];
	ORMObjectTypeMapping how = (ORMObjectTypeMapping)[_typeMappingPopUp indexOfSelectedItem];
	if (how == ORMMapJoined && [[[self mapping].joins objectForKey:type.identifier] count] == 0) {
		/* Its entity the hub, to add members to (Merge Entity Types). */
		if (!type.isEntity) {
			NSBeep();
			[self say:@"Only an entity type is kept in several entities."];
			[_typeMappingPopUp selectItemAtIndex:[[self mapping] mappingOfObjectType:type.identifier]];
			return;
		}
		ORMCDModel *mapped = [[[ORMCoreDataMapper alloc] initWithModel:self.editor.model mapping:[self mapping]] map];
		NSString *name = [mapped entityWithSource:type.identifier].name ?: [ORMCoreDataMapper entityNameFor:type.name];
		[[self mappings] addMemberNamed:name by:nil via:nil outer:NO ofObjectType:type.identifier inMapping:self.mappingId];
		[self say:[self membersTextOf:type]];
	} else if (how == ORMMapTransformable) {
		[[self mappings] setTransformableClass:[_transformableClassField stringValue] transformer:nil ofObjectType:type.identifier
		                         inMapping:self.mappingId];
	} else {
		[[self mappings] setMapping:how ofObjectType:type.identifier inMapping:self.mappingId];
	}
}

- (void)changeActionChanged:(id)sender
{
	(void)sender;
	NSInteger row = [_changesTable selectedRow];
	if (_sync == nil || row < 0 || (NSUInteger)row >= [_sync.changes count]) {
		return;
	}
	ORMSyncChange *change = [_sync.changes objectAtIndex:(NSUInteger)row];
	ORMSyncAction action = (ORMSyncAction)[_changeActionPopUp indexOfSelectedItem];
	if (![change.possibleActions containsObject:@(action)]) {
		NSBeep();
		[self say:@"That change cannot be made that way."];
		[_changeActionPopUp selectItemAtIndex:change.action];
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
	NSString *checked = @"";
	ORMCoreDataMapping *mapping = [self mapping];
	NSString *validation = [mapping resolvedValidationPathRelativeTo:[self.documentURL path]];
	if (validation != nil) {
		ORMValidationGenerator *generator = [[ORMValidationGenerator alloc] initWithModel:self.editor.model
		                                                                         mapping:mapping
		                                                                        coreData:written
		                                                                            name:mapping.name];
		if (![generator writeToDirectory:validation error:&error]) {
			NSBeep();
			[self say:[error localizedDescription]];
			return;
		}
		checked = [NSString stringWithFormat:@" %lu constraints Core Data cannot enforce are checked in %@.",
		                                     (unsigned long)generator.ruleCount, validation];
	}
	[_changesTable reloadData];
	[self modelDidChange];
	[self say:[NSString stringWithFormat:@"Wrote %lu entities to %@.%@", (unsigned long)[written.entities count], path,
	                                     checked]];
}

#pragma mark Tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == _typesTable) {
		return (NSInteger)[_objectTypes count];
	}
	if (tableView == _changesTable) {
		return (NSInteger)[_sync.changes count];
	}
	return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
	if (tableView == _typesTable) {
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
		if (how == ORMMapJoined) {
			NSArray *members = [[mapping.joins objectForKey:type.identifier] valueForKey:@"name"];
			return [NSString stringWithFormat:@"Joined: %@", [members componentsJoinedByString:@", "]];
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
	if (table == _typesTable && row >= 0) {
		ORMObjectType *type = [_objectTypes objectAtIndex:(NSUInteger)row];
		[_typeMappingPopUp selectItemAtIndex:[[self mapping] mappingOfObjectType:type.identifier]];
		[_transformableClassField setStringValue:[[[self mapping].transformables objectForKey:type.identifier] firstObject] ?: @""];
		[_transformableClassField setEnabled:type.kind == ORMValueType];
		if ([[[self mapping].joins objectForKey:type.identifier] count] > 0) {
			[self say:[self membersTextOf:type]];
		}
	} else if (table == _changesTable && row >= 0 && _sync != nil) {
		[_changeActionPopUp selectItemAtIndex:[[_sync.changes objectAtIndex:(NSUInteger)row] action]];
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
	[[self mappings] setName:[value description] forSource:source inMapping:self.mappingId];
}

@end
