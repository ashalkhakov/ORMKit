/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMDocument.h"
#import "ORMWindowController.h"

/* The type's UTI, which NSDocument uses as the type's name on Apple; the
 * Info.plist names GNUstep's NSTypes entry the same. */
NSString * const ORMDocumentType = @"org.ormkit.orm";

@implementation ORMDocument

/* A model is saved when the modeller says so: NORMA may have the same file
 * open, and in-place autosave would write under it. */
+ (BOOL)autosavesInPlace
{
	return NO;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_editor = [[ORMEditor alloc] initWithDocument:[ORMEditor newDocumentNamed:@"ORMModel1"]
		                                  undoManager:[self undoManager]];
	}
	return self;
}

- (void)makeWindowControllers
{
	[self addWindowController:[[ORMWindowController alloc] initWithDocument:self]];
}

- (NSString *)windowNibName
{
	return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)error
{
	(void)typeName;
	NSString *reason = nil;
	NSXMLDocument *document = ORMParseDocument(data, &reason);
	ORMModel *model = document != nil ? [ORMModel modelOfDocument:document reason:&reason] : nil;
	if (model == nil) {
		if (error != NULL) {
			*error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
			                         userInfo:@{ NSLocalizedDescriptionKey: @"The file is not an ORM model.",
			                                     NSLocalizedRecoverySuggestionErrorKey: reason ?: @"" }];
		}
		return NO;
	}
	_editor = [[ORMEditor alloc] initWithDocument:document undoManager:[self undoManager]];
	/* A model NORMA saved without a diagram gets one to draw on. */
	if ([model.diagrams count] == 0 && [document rootElement] != model.modelElement) {
		[[self undoManager] disableUndoRegistration];
		NSString *diagram = [_editor.diagramEditor addDiagramNamed:model.name];
		for (ORMObjectType *type in [_editor.model visibleObjectTypes]) {
			[_editor.diagramEditor placeElement:type.identifier onDiagram:diagram at:ORMAutomaticPlacement];
		}
		for (ORMFactType *fact in [_editor.model ordinaryFactTypes]) {
			[_editor.diagramEditor placeElement:fact.identifier onDiagram:diagram at:ORMAutomaticPlacement];
		}
		[_editor.diagramEditor arrangeDiagram:diagram];
		[[self undoManager] enableUndoRegistration];
	}
	for (NSWindowController *controller in [self windowControllers]) {
		if ([controller isKindOfClass:[ORMWindowController class]]) {
			[(ORMWindowController *)controller editorDidChange];
		}
	}
	return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error
{
	(void)typeName;
	(void)error;
	return [self.editor dataForSaving];
}

- (IBAction)saveCopyForNorma:(id)sender
{
	(void)sender;
	NSSavePanel *panel = [NSSavePanel savePanel];
	[panel setAllowedFileTypes:@[ @"orm" ]];
	NSString *base = [[[self fileURL] lastPathComponent] stringByDeletingPathExtension] ?: self.editor.model.name;
	[panel setNameFieldStringValue:[base stringByAppendingString:@" (NORMA).orm"]];
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}
	NSData *data = ORMDataOfDocument([self.editor documentForNorma]);
	NSError *error = nil;
	if (![data writeToURL:[panel URL] options:NSDataWritingAtomic error:&error]) {
		[self presentError:error];
	}
}

@end
