/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <AppKit/AppKit.h>

/* File > Open Sample: the models the application bundles, to open and
 * query without looking for a file. Each opens as an untitled copy
 * (+[ORMDocument sampleWithContentsOfURL:error:]), so the sample stays as
 * it is. */
@interface ORMSampleMenu : NSObject
/* The folders of samples in the bundle: Samples (ORMKit's own, after
 * Halpin's papers: Samples/README.md) and ActiveFacts (Clifford Heath's
 * examples, MIT licensed), those it has. */
+ (NSArray<NSURL *> *)foldersInBundle:(NSBundle *)bundle;
/* The menu emptied and filled: the first folder's models, then a submenu
 * of each other folder's, by name. Each item's action is openSample:, its
 * represented object the model's URL. */
+ (void)fillMenu:(NSMenu *)menu fromFolders:(NSArray<NSURL *> *)folders;
@end
