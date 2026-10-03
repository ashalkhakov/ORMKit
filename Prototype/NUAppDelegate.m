#import "NUAppDelegate.h"
#import "NUModel.h"

static NSButton *NUButton(NSString *title, id target, SEL action) {
    NSButton *b = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 90, 24)];
    [b setBezelStyle:NSRoundedBezelStyle];
    [b setTitle:title];
    [b setTarget:target];
    [b setAction:action];
    [b setFont:[NSFont systemFontOfSize:12]];
    return b;
}

static NSTextField *NULabel(NSString *text) {
    NSTextField *t = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [t setStringValue:text];
    [t setBezeled:NO];
    [t setDrawsBackground:NO];
    [t setEditable:NO];
    [t setSelectable:NO];
    [t setFont:[NSFont boldSystemFontOfSize:11]];
    return t;
}

static NSTextField *NUField(id target, SEL action) {
    NSTextField *t = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [t setFont:[NSFont systemFontOfSize:12]];
    [t setTarget:target];
    [t setAction:action];
    return t;
}

static NSString *NUPanelPath(id panel) {
    if ([panel respondsToSelector:@selector(URL)]) {
        NSURL *u = [panel URL];
        if (u) return [u path];
    }
    if ([panel respondsToSelector:@selector(filename)])
        return [panel filename];
    return nil;
}

@implementation NUAppDelegate

- (void)buildMenu {
    NSMenu *menubar = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"NativeORM" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"NativeORM"];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];
    [menubar addItem:appItem];

    NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open…" action:@selector(openDocument:) keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Save" action:@selector(saveDocument:) keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"Export verbalization…" action:@selector(exportVerbalization:) keyEquivalent:@"e"];
    [fileItem setSubmenu:fileMenu];
    [menubar addItem:fileItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Add Entity Type" action:@selector(addEntity:) keyEquivalent:@"n"];
    [editMenu addItemWithTitle:@"Add Value Type" action:@selector(addValue:) keyEquivalent:@"v"];
    [editItem setSubmenu:editMenu];
    [menubar addItem:editItem];

    [NSApp setMainMenu:menubar];
}

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [self buildMenu];
    NSRect wr = NSMakeRect(70, 50, 1200, 760);
    self.window = [[NSWindow alloc] initWithContentRect:wr
                                              styleMask:(NSTitledWindowMask |
                                                         NSClosableWindowMask |
                                                         NSMiniaturizableWindowMask |
                                                         NSResizableWindowMask)
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [self.window setTitle:@"NativeORM — MiniNotes (ORM2)"];
    [self.window setReleasedWhenClosed:NO];

    NSView *content = [self.window contentView];
    CGFloat W = wr.size.width, H = wr.size.height;
    CGFloat barH = 64, sideW = 280, pad = 8;

    NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, H - barH, W, barH)];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [content addSubview:bar];

    NSArray *row1 = @[
        @[ @"Entity",  @"addEntity:" ],
        @[ @"Value",   @"addValue:" ],
        @[ @"Unary",   @"toolUnary:" ],
        @[ @"Binary",  @"toolBinary:" ],
        @[ @"Ternary", @"toolTernary:" ],
        @[ @"Subtype", @"toolSubtype:" ],
        @[ @"Open",    @"openDocument:" ],
        @[ @"Save",    @"saveDocument:" ],
        @[ @"Verbalize", @"exportVerbalization:" ],
        @[ @"Seed",    @"reloadSeed:" ]
    ];
    NSArray *row2 = @[
        @[ @"Ext U",   @"toolExtU:" ],
        @[ @"Subset",  @"toolSubset:" ],
        @[ @"Equal",   @"toolEqual:" ],
        @[ @"Exclude", @"toolExclude:" ],
        @[ @"Ring",    @"toolRing:" ],
        @[ @"Freq",    @"toolFreq:" ],
        @[ @"Commit",  @"commitConstraint:" ]
    ];
    CGFloat bx = 8;
    for (NSArray *sp in row1) {
        NSButton *b = NUButton(sp[0], self, NSSelectorFromString(sp[1]));
        [b setFrame:NSMakeRect(bx, 34, 92, 24)];
        [bar addSubview:b];
        bx += 96;
    }
    bx = 8;
    for (NSArray *sp in row2) {
        NSButton *b = NUButton(sp[0], self, NSSelectorFromString(sp[1]));
        [b setFrame:NSMakeRect(bx, 6, 92, 24)];
        [bar addSubview:b];
        bx += 96;
    }

    self.scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 22, W - sideW, H - barH - 22)];
    [self.scroll setHasVerticalScroller:YES];
    [self.scroll setHasHorizontalScroller:YES];
    [self.scroll setBorderType:NSBezelBorder];
    [self.scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    self.diagramView = [[NUDiagramView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 900)];
    self.diagramView.delegate = self;
    self.diagramView.diagram = [NUDiagram miniNotesSeed];
    [self.scroll setDocumentView:self.diagramView];
    [content addSubview:self.scroll];

    NSView *side = [[NSView alloc] initWithFrame:NSMakeRect(W - sideW, 22, sideW, H - barH - 22)];
    [side setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
    [content addSubview:side];

    CGFloat y = side.bounds.size.height - 28;
    void (^lab)(NSString *) = ^(NSString *t) {
        NSTextField *l = NULabel(t);
        [l setFrame:NSMakeRect(pad, y, sideW - 2 * pad, 16)];
        [l setAutoresizingMask:NSViewMinYMargin];
        [side addSubview:l];
    };

    lab(@"Object type name");
    y -= 24;
    self.nameField = NUField(self, @selector(applyInspector:));
    [self.nameField setFrame:NSMakeRect(pad, y, sideW - 2 * pad, 22)];
    [self.nameField setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [side addSubview:self.nameField];

    y -= 22;
    lab(@"Kind");
    y -= 26;
    self.kindPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(pad, y, sideW - 2 * pad, 24)
                                                pullsDown:NO];
    [self.kindPopup addItemsWithTitles:@[ @"Entity type (solid ellipse)",
                                          @"Value type (dashed ellipse)" ]];
    [self.kindPopup setTarget:self];
    [self.kindPopup setAction:@selector(applyInspector:)];
    [self.kindPopup setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [side addSubview:self.kindPopup];

    y -= 22;
    lab(@"Reference mode   e.g. id  →  Note(.id)");
    y -= 24;
    self.refField = NUField(self, @selector(applyInspector:));
    [self.refField setFrame:NSMakeRect(pad, y, sideW - 2 * pad, 22)];
    [self.refField setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [side addSubview:self.refField];

    y -= 22;
    lab(@"Value constraint   e.g. {1..n} or {'A','B'}");
    y -= 24;
    self.constraintField = NUField(self, @selector(applyInspector:));
    [self.constraintField setFrame:NSMakeRect(pad, y, sideW - 2 * pad, 22)];
    [self.constraintField setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [side addSubview:self.constraintField];

    y -= 28;
    self.independentBtn = [[NSButton alloc] initWithFrame:NSMakeRect(pad, y, sideW - 2 * pad, 22)];
    [self.independentBtn setButtonType:NSSwitchButton];
    [self.independentBtn setTitle:@"Independent object type  (!)"];
    [self.independentBtn setTarget:self];
    [self.independentBtn setAction:@selector(applyInspector:)];
    [self.independentBtn setAutoresizingMask:NSViewMinYMargin];
    [side addSubview:self.independentBtn];

    y -= 28;
    lab(@"Fact-type reading   use ... for holes");
    y -= 24;
    self.readingField = NUField(self, @selector(applyInspector:));
    [self.readingField setFrame:NSMakeRect(pad, y, sideW - 2 * pad, 22)];
    [self.readingField setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [side addSubview:self.readingField];

    y -= 28;
    self.spanUniqueBtn = [[NSButton alloc] initWithFrame:NSMakeRect(pad, y, sideW - 2 * pad, 22)];
    [self.spanUniqueBtn setButtonType:NSSwitchButton];
    [self.spanUniqueBtn setTitle:@"Spanning uniqueness (bar over all roles)"];
    [self.spanUniqueBtn setTarget:self];
    [self.spanUniqueBtn setAction:@selector(applyInspector:)];
    [self.spanUniqueBtn setAutoresizingMask:NSViewMinYMargin];
    [side addSubview:self.spanUniqueBtn];

    y -= 24;
    self.roleUniqueBtn = [[NSButton alloc] initWithFrame:NSMakeRect(pad, y, sideW - 2 * pad, 22)];
    [self.roleUniqueBtn setButtonType:NSSwitchButton];
    [self.roleUniqueBtn setTitle:@"Selected role is unique  (UC bar)"];
    [self.roleUniqueBtn setTarget:self];
    [self.roleUniqueBtn setAction:@selector(applyInspector:)];
    [self.roleUniqueBtn setAutoresizingMask:NSViewMinYMargin];
    [side addSubview:self.roleUniqueBtn];

    y -= 24;
    self.roleMandatoryBtn = [[NSButton alloc] initWithFrame:NSMakeRect(pad, y, sideW - 2 * pad, 22)];
    [self.roleMandatoryBtn setButtonType:NSSwitchButton];
    [self.roleMandatoryBtn setTitle:@"Selected role is mandatory  (•)"];
    [self.roleMandatoryBtn setTarget:self];
    [self.roleMandatoryBtn setAction:@selector(applyInspector:)];
    [self.roleMandatoryBtn setAutoresizingMask:NSViewMinYMargin];
    [side addSubview:self.roleMandatoryBtn];

    y -= 22;
    lab(@"Frequency min / max   (0 = none, max -1 = n)");
    y -= 24;
    self.freqMinField = NUField(self, @selector(applyInspector:));
    [self.freqMinField setFrame:NSMakeRect(pad, y, (sideW - 3 * pad) / 2, 22)];
    [self.freqMinField setAutoresizingMask:NSViewMinYMargin];
    [side addSubview:self.freqMinField];
    self.freqMaxField = NUField(self, @selector(applyInspector:));
    [self.freqMaxField setFrame:NSMakeRect(pad + (sideW - 3 * pad) / 2 + pad, y,
                                           (sideW - 3 * pad) / 2, 22)];
    [self.freqMaxField setAutoresizingMask:NSViewMinYMargin];
    [side addSubview:self.freqMaxField];

    y -= 22;
    lab(@"Ring constraint on selected fact");
    y -= 26;
    self.ringPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(pad, y, sideW - 2 * pad, 24)
                                                pullsDown:NO];
    [self.ringPopup addItemsWithTitles:@[
        @"(none)", @"irreflexive (ir)", @"asymmetric (as)",
        @"intransitive (it)", @"acyclic (ac)", @"symmetric (sy)",
        @"antisymmetric (ans)", @"transitive (tr)"
    ]];
    [self.ringPopup setTarget:self];
    [self.ringPopup setAction:@selector(applyInspector:)];
    [self.ringPopup setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
    [side addSubview:self.ringPopup];

    self.statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 2, W - 16, 18)];
    [self.statusField setBezeled:NO];
    [self.statusField setDrawsBackground:NO];
    [self.statusField setEditable:NO];
    [self.statusField setFont:[NSFont systemFontOfSize:11]];
    [self.statusField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [self.statusField setStringValue:@"ORM2. Solid ellipse = entity, dashed = value. Bar = uniqueness. Dot = mandatory. Binary: click two object types."];
    [content addSubview:self.statusField];

    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.diagramView];
    [self diagramViewSelectionDidChange:self.diagramView];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

- (void)setDirty:(BOOL)dirty {
    _dirty = dirty;
    NSString *t = self.diagramView.diagram.title ?: @"Untitled";
    if (self.filePath) t = [self.filePath lastPathComponent];
    [self.window setTitle:[NSString stringWithFormat:@"NativeORM — %@%@", t, dirty ? @" *" : @""]];
}

- (void)diagramViewDidEdit:(id)sender { self.dirty = YES; }

- (void)diagramViewSelectionDidChange:(id)sender {
    NUObjectType *ot = self.diagramView.selectedObject;
    NUFactType *ft = self.diagramView.selectedFact;
    if (ot) {
        [self.nameField setStringValue:ot.name ?: @""];
        [self.kindPopup selectItemAtIndex:ot.kind];
        [self.refField setStringValue:ot.referenceMode ?: @""];
        [self.constraintField setStringValue:ot.valueConstraint ?: @""];
        [self.independentBtn setState:ot.independent ? NSOnState : NSOffState];
        [self.statusField setStringValue:[ot verbalization]];
    } else {
        [self.nameField setStringValue:@""];
        [self.refField setStringValue:@""];
        [self.constraintField setStringValue:@""];
        [self.independentBtn setState:NSOffState];
    }
    if (ft) {
        [self.readingField setStringValue:ft.reading ?: @""];
        [self.spanUniqueBtn setState:ft.spanningUnique ? NSOnState : NSOffState];
        NSInteger i = self.diagramView.selectedRoleIndex;
        [self.ringPopup selectItemAtIndex:ft.ringKind];
        if (i >= 0 && i < (NSInteger)ft.roles.count) {
            NURole *r = ft.roles[i];
            [self.roleUniqueBtn setState:r.unique ? NSOnState : NSOffState];
            [self.roleMandatoryBtn setState:r.mandatory ? NSOnState : NSOffState];
            [self.freqMinField setStringValue:[NSString stringWithFormat:@"%ld", (long)r.freqMin]];
            [self.freqMaxField setStringValue:[NSString stringWithFormat:@"%ld", (long)r.freqMax]];
        } else {
            [self.roleUniqueBtn setState:NSOffState];
            [self.roleMandatoryBtn setState:NSOffState];
            [self.freqMinField setStringValue:@"0"];
            [self.freqMaxField setStringValue:@"0"];
        }
        [self.statusField setStringValue:[ft verbalizationUsing:self.diagramView.diagram]];
    } else {
        [self.readingField setStringValue:@""];
        [self.spanUniqueBtn setState:NSOffState];
        [self.roleUniqueBtn setState:NSOffState];
        [self.roleMandatoryBtn setState:NSOffState];
        [self.freqMinField setStringValue:@""];
        [self.freqMaxField setStringValue:@""];
        [self.ringPopup selectItemAtIndex:0];
    }
    if (self.diagramView.selectedConstraint) {
        NUConstraint *c = self.diagramView.selectedConstraint;
        [self.statusField setStringValue:[c verbalizationUsing:self.diagramView.diagram]];
    }
    if (self.diagramView.selectedSubtype) {
        NUSubtype *s = self.diagramView.selectedSubtype;
        NUObjectType *a = [self.diagramView.diagram objectTypeWithId:s.subId];
        NUObjectType *b = [self.diagramView.diagram objectTypeWithId:s.superId];
        [self.statusField setStringValue:
         [NSString stringWithFormat:@"%@ is a subtype of %@.", a.name, b.name]];
    }
}

- (void)applyInspector:(id)sender {
    NUObjectType *ot = self.diagramView.selectedObject;
    if (ot) {
        ot.name = [[self.nameField stringValue] copy];
        ot.kind = [self.kindPopup indexOfSelectedItem];
        ot.referenceMode = [[self.refField stringValue] copy];
        ot.valueConstraint = [[self.constraintField stringValue] copy];
        ot.independent = ([self.independentBtn state] == NSOnState);
        [self.diagramView fitObjectType:ot];
        self.dirty = YES;
        [self.diagramView setNeedsDisplay:YES];
    }
    NUFactType *ft = self.diagramView.selectedFact;
    if (ft) {
        ft.reading = [[self.readingField stringValue] copy];
        ft.spanningUnique = ([self.spanUniqueBtn state] == NSOnState);
        NSInteger i = self.diagramView.selectedRoleIndex;
        ft.ringKind = [self.ringPopup indexOfSelectedItem];
        if (i >= 0 && i < (NSInteger)ft.roles.count) {
            NURole *r = ft.roles[i];
            r.unique = ([self.roleUniqueBtn state] == NSOnState);
            r.mandatory = ([self.roleMandatoryBtn state] == NSOnState);
            r.freqMin = [[self.freqMinField stringValue] integerValue];
            r.freqMax = [[self.freqMaxField stringValue] integerValue];
        }
        self.dirty = YES;
        [self.diagramView setNeedsDisplay:YES];
        [self.statusField setStringValue:[ft verbalizationUsing:self.diagramView.diagram]];
    }
}

- (void)addEntity:(id)sender {
    NUObjectType *o = [self.diagramView.diagram addObjectTypeNamed:@"Entity" kind:NUObjectEntity];
    self.diagramView.selectedObject = o;
    self.diagramView.selectedFact = nil;
    [self.diagramView fitObjectType:o];
    [self.diagramView recomputeSize];
    [self.diagramView setNeedsDisplay:YES];
    [self diagramViewSelectionDidChange:self.diagramView];
    self.dirty = YES;
}

- (void)addValue:(id)sender {
    NUObjectType *o = [self.diagramView.diagram addObjectTypeNamed:@"Value" kind:NUObjectValue];
    self.diagramView.selectedObject = o;
    self.diagramView.selectedFact = nil;
    [self.diagramView fitObjectType:o];
    [self.diagramView recomputeSize];
    [self.diagramView setNeedsDisplay:YES];
    [self diagramViewSelectionDidChange:self.diagramView];
    self.dirty = YES;
}

- (void)setTool:(NUTool)tool status:(NSString *)msg {
    self.diagramView.tool = tool;
    [self.diagramView clearLinkStack];
    [self.statusField setStringValue:msg];
    [self.window makeFirstResponder:self.diagramView];
}

- (void)toolUnary:(id)sender {
    [self setTool:NUToolFactUnary status:@"Unary fact: click the object type that plays the role."];
}
- (void)toolBinary:(id)sender {
    [self setTool:NUToolFactBinary status:@"Binary fact: click first player, then second."];
}
- (void)toolTernary:(id)sender {
    [self setTool:NUToolFactTernary status:@"Ternary fact: click three object types in reading order."];
}
- (void)toolSubtype:(id)sender {
    [self setTool:NUToolSubtype status:@"Subtype: click subtype, then supertype."];
}
- (void)toolExtU:(id)sender {
    [self setTool:NUToolExtUnique status:@"External uniqueness: click two or more roles, then Commit or Return."];
}
- (void)toolSubset:(id)sender {
    [self setTool:NUToolSubset status:@"Subset: click subset role, then superset role."];
}
- (void)toolEqual:(id)sender {
    [self setTool:NUToolEquality status:@"Equality: click two roles whose populations must be equal."];
}
- (void)toolExclude:(id)sender {
    [self setTool:NUToolExclusion status:@"Exclusion: click two or more exclusive roles, then Commit or Return."];
}
- (void)toolRing:(id)sender {
    [self setTool:NUToolRing status:@"Ring: click a fact type, then pick ir/as/ac/… in the inspector."];
}
- (void)toolFreq:(id)sender {
    [self setTool:NUToolFrequency status:@"Frequency: click a role box, then edit min/max."];
}
- (void)commitConstraint:(id)sender {
    [self.diagramView commitPendingConstraint];
    [self.window makeFirstResponder:self.diagramView];
}

- (void)reloadSeed:(id)sender {
    self.diagramView.diagram = [NUDiagram miniNotesSeed];
    self.filePath = nil;
    self.dirty = NO;
    [self diagramViewSelectionDidChange:self.diagramView];
}

- (void)saveDocument:(id)sender {
    if (self.filePath) { [self writeToPath:self.filePath]; return; }
    NSSavePanel *p = [NSSavePanel savePanel];
    [p setAllowedFileTypes:@[ @"nativorm" ]];
    [p setNameFieldStringValue:@"MiniNotes.nativorm"];
    [p setCanCreateDirectories:YES];
    if ([p runModal] == NSOKButton) {
        NSString *path = NUPanelPath(p);
        [self writeToPath:path];
        self.filePath = path;
        self.dirty = NO;
    }
}

- (void)writeToPath:(NSString *)path {
    [self applyInspector:nil];
    NSData *data = [self.diagramView.diagram archivedData];
    NSError *err = nil;
    if (![data writeToFile:path options:NSDataWritingAtomic error:&err]) {
        NSAlert *a = [[NSAlert alloc] init];
        [a setMessageText:@"Save failed"];
        [a setInformativeText:[err localizedDescription] ?: @"unknown"];
        [a runModal];
        return;
    }
    self.dirty = NO;
    [self.statusField setStringValue:[NSString stringWithFormat:@"Saved %@", path]];
}

- (void)openDocument:(id)sender {
    NSOpenPanel *p = [NSOpenPanel openPanel];
    [p setAllowedFileTypes:@[ @"nativorm", @"nativuml" ]];
    [p setAllowsMultipleSelection:NO];
    if ([p runModal] != NSOKButton) return;
    NSString *path = NUPanelPath(p);
    NSError *err = nil;
    NUDiagram *d = [NUDiagram diagramWithData:[NSData dataWithContentsOfFile:path] error:&err];
    if (!d) {
        NSAlert *a = [[NSAlert alloc] init];
        [a setMessageText:@"Open failed"];
        [a setInformativeText:[err localizedDescription] ?: @"not a NativeORM file"];
        [a runModal];
        return;
    }
    self.diagramView.diagram = d;
    self.filePath = path;
    self.dirty = NO;
    [self diagramViewSelectionDidChange:self.diagramView];
}

- (void)exportVerbalization:(id)sender {
    [self applyInspector:nil];
    NSSavePanel *p = [NSSavePanel savePanel];
    [p setAllowedFileTypes:@[ @"txt" ]];
    [p setNameFieldStringValue:@"MiniNotes.orm.txt"];
    if ([p runModal] != NSOKButton) return;
    NSString *text = [self.diagramView.diagram exportedVerbalization];
    NSError *err = nil;
    if (![text writeToFile:NUPanelPath(p) atomically:YES
                  encoding:NSUTF8StringEncoding error:&err]) {
        NSAlert *a = [[NSAlert alloc] init];
        [a setMessageText:@"Export failed"];
        [a setInformativeText:[err localizedDescription] ?: @""];
        [a runModal];
        return;
    }
    [self.statusField setStringValue:@"Wrote ORM verbalization."];
}

@end
