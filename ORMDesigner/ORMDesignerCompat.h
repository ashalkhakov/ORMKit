/*
 * Included on GNUstep only (the GNUmakefile's -include), never by Xcode:
 * AppKit names gnustep-gui lacks, defined by the ones it has, so the sources
 * can use current AppKit. Only names; behaviour belongs in gnustep-gui.
 */
#ifdef __OBJC__
#import <AppKit/AppKit.h>

#ifndef NSCompositingOperationSourceOver
#define NSCompositingOperationSourceOver NSCompositeSourceOver
#endif
#ifndef NSButtonTypeSwitch
#define NSButtonTypeSwitch NSSwitchButton
#endif
#ifndef NSButtonTypeMomentaryPushIn
#define NSButtonTypeMomentaryPushIn NSMomentaryPushInButton
#endif
#ifndef NSButtonTypePushOnPushOff
#define NSButtonTypePushOnPushOff NSPushOnPushOffButton
#endif
#ifndef NSBitmapImageFileTypePNG
#define NSBitmapImageFileTypePNG NSPNGFileType
#endif
#ifndef NSBezelStyleSmallSquare
#define NSBezelStyleSmallSquare NSSmallSquareBezelStyle
#endif
#ifndef NSBezelStyleRounded
#define NSBezelStyleRounded NSRoundedBezelStyle
#endif
#ifndef NSEventModifierFlagShift
#define NSEventModifierFlagShift NSShiftKeyMask
#define NSEventModifierFlagOption NSAlternateKeyMask
#define NSEventModifierFlagCommand NSCommandKeyMask
#define NSEventModifierFlagControl NSControlKeyMask
#endif
#ifndef NSWindowStyleMaskTitled
#define NSWindowStyleMaskTitled NSTitledWindowMask
#define NSWindowStyleMaskClosable NSClosableWindowMask
#define NSWindowStyleMaskMiniaturizable NSMiniaturizableWindowMask
#define NSWindowStyleMaskResizable NSResizableWindowMask
#endif
#ifndef NSControlSizeSmall
#define NSControlSizeSmall NSSmallControlSize
#endif
#ifndef NSTextAlignmentRight
#define NSTextAlignmentRight NSRightTextAlignment
#define NSTextAlignmentCenter NSCenterTextAlignment
#define NSTextAlignmentLeft NSLeftTextAlignment
#endif
#ifndef NSControlStateValueOn
#define NSControlStateValueOn NSOnState
#define NSControlStateValueOff NSOffState
#endif
#ifndef NSModalResponseOK
#define NSModalResponseOK NSOKButton
#endif
#endif
