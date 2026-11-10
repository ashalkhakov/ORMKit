/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import "ORMModelViewController.h"

@class ORMDocument;

/* A document's window (ORMDocumentWindow.xib): its model's editor
 * (ORMModelViewController) filling it, in the responder chain, so the
 * Diagram, Model and Query menus' items reach it. */
@interface ORMWindowController : NSWindowController
- (instancetype)initWithDocument:(ORMDocument *)document;

@property (nonatomic, readonly, strong) ORMModelViewController *modelController;

/* The document's editor was replaced (a revert). */
- (void)editorDidChange;
/* File > New Flow: a flow of this model (docs/FORMS.md, Flows), in a
 * window of its own; the model saved first, since the flow names its file. */
- (IBAction)newFlow:(id)sender;
@end
