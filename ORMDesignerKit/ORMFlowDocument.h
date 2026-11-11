/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* The type NSDocument reads and writes: ORMKit's .flow. */
extern NSString * const ORMFlowDocumentType;

/* The model at the URL, read as ORMDesigner reads one; nil, and why. */
extern ORMModel *ORMFlowModelAt(NSURL *url, NSString **reason);

/* A .flow file open in ORMDesigner (docs/FORMS.md, Flows), in a window of
 * its own (ORMFlowWindowController): the flow, and the model it names,
 * read from beside it -- its forms and lists are what its screens show. Its
 * changes are the editor's, on this document's undo manager, so its edited
 * state follows them. A new one is made for a model (File > New Flow, in a
 * model's window), its Model the model's file, to be saved beside it. */
@interface ORMFlowDocument : NSDocument
@property (nonatomic, readonly, strong) ORMFlowEditor *editor;

/* A new flow of the model at the URL, untitled, named as given. */
+ (instancetype)flowForModelAtURL:(NSURL *)modelURL model:(ORMModel *)model named:(NSString *)name;
@end
