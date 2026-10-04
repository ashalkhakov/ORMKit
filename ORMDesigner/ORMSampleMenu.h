/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

/* File > Open Sample: the models the application bundles, to open and
 * query without looking for a file. Each opens as an untitled copy
 * (+[ORMDocument sampleWithContentsOfURL:error:]), so the sample stays as
 * it is. */
@interface ORMSampleMenu : NSObject
/* The samples the menu lists first: those in the bundle's Samples folder
 * (ORMKit's own, after Halpin's papers: Samples/README.md) and those among
 * its resources (StockMate), by name. */
+ (NSArray<NSURL *> *)modelsInBundle:(NSBundle *)bundle;
/* The folders of samples listed each in a submenu: ActiveFacts (Clifford
 * Heath's examples, MIT licensed), if the bundle has it. */
+ (NSArray<NSURL *> *)foldersInBundle:(NSBundle *)bundle;
/* The folder's models, by name. */
+ (NSArray<NSURL *> *)modelsIn:(NSURL *)folder;
/* The menu emptied and filled: the models, then a submenu of each folder's,
 * by its name. Each item's action is openSample:, its represented object
 * the model's URL. */
+ (void)fillMenu:(NSMenu *)menu withModels:(NSArray<NSURL *> *)models folders:(NSArray<NSURL *> *)folders;
@end
