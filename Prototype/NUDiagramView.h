#import <AppKit/AppKit.h>
#import "NUModel.h"

@protocol NUDiagramViewDelegate <NSObject>
- (void)diagramViewSelectionDidChange:(id)sender;
- (void)diagramViewDidEdit:(id)sender;
@end

typedef NS_ENUM(NSInteger, NUTool) {
    NUToolSelect = 0,
    NUToolFactUnary,
    NUToolFactBinary,
    NUToolFactTernary,
    NUToolSubtype,
    NUToolExtUnique,
    NUToolSubset,
    NUToolEquality,
    NUToolExclusion,
    NUToolRing,
    NUToolFrequency
};

@interface NUDiagramView : NSView
@property (strong) NUDiagram *diagram;
@property (weak) id<NUDiagramViewDelegate> delegate;
@property (strong) NUObjectType *selectedObject;
@property (strong) NUFactType *selectedFact;
@property (strong) NUSubtype *selectedSubtype;
@property (strong) NUConstraint *selectedConstraint;
@property (assign) NSInteger selectedRoleIndex;
@property (assign) NUTool tool;
- (void)recomputeSize;
- (void)fitObjectType:(NUObjectType *)ot;
- (void)clearLinkStack;
- (void)commitPendingConstraint;
@end
