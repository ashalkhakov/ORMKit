/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>
#import <UDCodeKit/UDExtension.h>

/* UDCode's ORM2 extension (docs/UDCODE.md): NORMA's .orm models, edited in
 * UDCode with ORMDesigner's editor (ORMDesignerKit), in a tab of their own,
 * as part of a project. A model is its document's text: the editor writes
 * each change into it (ORM2EditorViewController), so undo, saving, the
 * tab's dot and source control are UDCode's, and a tab of its text shows it
 * as XML (its grammar is the XML mode's). The editor's menus (Model,
 * Diagram, Core Data, Query) are in UDCode's Editor menu. */
@interface ORM2Extension : NSObject <UDExtension>
@end
