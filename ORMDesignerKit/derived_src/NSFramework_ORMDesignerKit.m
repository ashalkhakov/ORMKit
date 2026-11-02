#include <Foundation/NSString.h>
@interface NSFramework_ORMDesignerKit : NSObject
+ (NSString *)frameworkVersion;
+ (NSString *const*)frameworkClasses;
@end
@implementation NSFramework_ORMDesignerKit
+ (NSString *)frameworkVersion { return @"A"; }
static NSString *allClasses[] = {@"ORMDocument", @"ORMWindowController", @"ORMModelViewController", @"ORMCanvasView", @"ORMHit", @"ORMInspectorRow", @"ORMInspectorView", @"ORMBrowserItem", @"ORMModelBrowser", @"ORMCoreDataController", @"ORMPreviewItem", @"ORMQueryController", @"ORMInsertPalette", @"ORMIssuesView", @"ORMSearchHit", @"ORMSearchNavigator", @"ORMPopulationView", @"DMTabBar", @"DMTabBarButtonCell", @"DMTabBarItem", NULL};
+ (NSString *const*)frameworkClasses { return allClasses; }
@end
