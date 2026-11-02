/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#if __has_include(<ORMKit/ORMKit.h>)
#import <ORMKit/ORMKit.h>
#else
#import "ORMKit.h"
#endif

/* A document's Core Data mappings: each one's options, what the model maps
 * to, what Core Data cannot enforce, how each object type maps, and the
 * synchronization that writes the .xcdatamodeld and brings back what was
 * changed on its side (docs/COREDATA-MAPPING.md).
 *
 * Every change goes through the document's editor, so it is undone with
 * the model's own changes. */
@interface ORMCoreDataController : NSWindowController
- (instancetype)initWithEditor:(ORMEditor *)editor documentURL:(NSURL *)documentURL;
@property (nonatomic, strong) ORMEditor *editor;
/* Where the .orm is: mappings' paths are relative to it. nil for an
 * unsaved document, which cannot be synchronized yet. */
@property (nonatomic, copy) NSURL *documentURL;
/* The mapping shown. */
@property (nonatomic, copy) NSString *mappingId;

- (void)modelDidChange;
/* A path relative to the document's directory when it is under it. */
- (NSString *)pathRelativeToDocument:(NSString *)path;
- (void)say:(NSString *)message;
/* Compares the mapping with its .xcdatamodeld and shows what changed on
 * the Core Data side; writes straight away when nothing did. */
- (IBAction)synchronize:(id)sender;
/* Applies the shown changes' chosen actions and writes the model. */
- (IBAction)applyAndWrite:(id)sender;
- (IBAction)addMapping:(id)sender;
- (IBAction)removeMapping:(id)sender;
@end
