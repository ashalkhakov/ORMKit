/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* The type NSDocument reads and writes: NORMA's .orm. */
extern NSString * const ORMDocumentType;

/* An .orm file open in ORMDesigner. The XML document is the model; the
 * editor holds it, changes it, and keeps its undo on this document's undo
 * manager, so the document's edited state follows the editor's changes. */
@interface ORMDocument : NSDocument
@property (nonatomic, readonly, strong) ORMEditor *editor;

/* File > Save a Copy for NORMA: the file without ORMKit's own elements. */
- (IBAction)saveCopyForNorma:(id)sender;
@end
