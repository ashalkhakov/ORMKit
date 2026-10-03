#import <AppKit/AppKit.h>
#import "NUDiagramView.h"

@interface NUAppDelegate : NSObject <NSApplicationDelegate, NUDiagramViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NUDiagramView *diagramView;
@property (strong) NSScrollView *scroll;
@property (strong) NSTextField *nameField;
@property (strong) NSPopUpButton *kindPopup;
@property (strong) NSTextField *refField;
@property (strong) NSTextField *constraintField;
@property (strong) NSButton *independentBtn;
@property (strong) NSTextField *readingField;
@property (strong) NSButton *spanUniqueBtn;
@property (strong) NSButton *roleUniqueBtn;
@property (strong) NSButton *roleMandatoryBtn;
@property (strong) NSTextField *freqMinField;
@property (strong) NSTextField *freqMaxField;
@property (strong) NSPopUpButton *ringPopup;
@property (strong) NSTextField *statusField;
@property (copy) NSString *filePath;
@property (assign) BOOL dirty;
@end
