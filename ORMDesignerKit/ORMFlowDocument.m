/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFlowDocument.h"
#import "ORMFlowWindowController.h"

NSString * const ORMFlowDocumentType = @"org.ormkit.flow";

static NSError *
ORMFlowDocumentError(NSString *description, NSString *suggestion)
{
	return [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError
	                       userInfo:@{ NSLocalizedDescriptionKey : description,
	                                   NSLocalizedRecoverySuggestionErrorKey : suggestion ?: @"" }];
}

/* The model at the URL, read as ORMDesigner reads one. */
static ORMModel *
ORMFlowModelAt(NSURL *url, NSString **reason)
{
	NSData *data = url != nil ? [NSData dataWithContentsOfURL:url] : nil;
	if (data == nil) {
		*reason = [NSString stringWithFormat:@"There is no model at %@.", [url path] ?: @"its place"];
		return nil;
	}
	NSXMLDocument *document = ORMParseDocument(data, reason);
	return document != nil ? [ORMModel modelOfDocument:document reason:reason] : nil;
}

@implementation ORMFlowDocument

/* As a model is: saved when the modeller says so. */
+ (BOOL)autosavesInPlace
{
	return NO;
}

- (instancetype)init
{
	if ((self = [super init])) {
		_editor = [[ORMFlowEditor alloc] initWithFlow:[[ORMFlow alloc] init] model:nil undoManager:[self undoManager]];
	}
	return self;
}

+ (instancetype)flowForModelAtURL:(NSURL *)modelURL model:(ORMModel *)model named:(NSString *)name
{
	ORMFlowDocument *document = [[self alloc] init];
	ORMFlow *flow = [[ORMFlow alloc] init];
	flow.name = name;
	flow.modelPath = [modelURL lastPathComponent];
	document->_editor = [[ORMFlowEditor alloc] initWithFlow:flow model:model undoManager:[document undoManager]];
	[document setFileType:ORMFlowDocumentType];
	return document;
}

- (void)makeWindowControllers
{
	[self addWindowController:[[ORMFlowWindowController alloc] initWithEditor:self.editor]];
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
	NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
	ORMFlow *flow = data != nil ? [ORMFlow flowWithData:data error:error] : nil;
	if (flow == nil) {
		if (error != NULL && *error == nil) {
			*error = ORMFlowDocumentError(@"The file is not a flow.", nil);
		}
		return NO;
	}
	NSString *reason = nil;
	NSURL *modelURL = [flow.modelPath length] > 0
		? [NSURL fileURLWithPath:flow.modelPath relativeToURL:[url URLByDeletingLastPathComponent]] : nil;
	ORMModel *model = ORMFlowModelAt(modelURL, &reason);
	if (model == nil) {
		if (error != NULL) {
			*error = ORMFlowDocumentError([NSString stringWithFormat:@"The flow's model, %@, cannot be read.", flow.modelPath ?: @"none named"],
			                              reason);
		}
		return NO;
	}
	_editor = [[ORMFlowEditor alloc] initWithFlow:flow model:model undoManager:[self undoManager]];
	return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error
{
	return [self.editor XMLData];
}

@end
