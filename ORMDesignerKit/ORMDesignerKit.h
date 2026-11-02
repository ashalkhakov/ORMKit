/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
/* ORMDesignerKit: ORMDesigner's editor as a framework, for ORMDesigner.app
 * and for any app that edits ORM models of its own, as XFormsDesignKit is
 * the XForms Designer's.
 *
 * Two ways to host it:
 * - as a document type: ORMDocument, an NSDocument whose window
 *   (ORMWindowController, ORMDocumentWindow.xib in this framework) edits a
 *   NORMA .orm file. A host names it the class of its ORM document type
 *   (NSDocumentClass ORMDocument, extension orm) and opens models through
 *   its NSDocumentController as it opens its own documents;
 * - as a view: ORMModelViewController, the whole editor for an ORMEditor
 *   the host keeps (UDCode's ORM2 extension, in a tab), its view put where
 *   the host wants it and the controller in the responder chain after it. */
#import <AppKit/AppKit.h>
#import "ORMDocument.h"
#import "ORMWindowController.h"
#import "ORMModelViewController.h"
/* Its panes and windows, for a host that shows them on their own. */
#import "ORMCanvasView.h"
#import "ORMRenderer.h"
#import "ORMInspectorView.h"
#import "ORMModelBrowser.h"
#import "ORMPane.h"
#import "ORMInsertPalette.h"
#import "ORMIssuesView.h"
#import "ORMSearchNavigator.h"
#import "ORMPopulationView.h"
#import "ORMQueryController.h"
#import "ORMCoreDataController.h"
