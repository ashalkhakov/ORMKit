/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* One run of lines that differ: the old text's characters from offset,
 * length long, replaced by text. Each starts and ends on a line boundary. */
@interface ORM2TextChange : NSObject
@property (nonatomic, readonly) NSUInteger offset;
@property (nonatomic, readonly) NSUInteger length;
@property (nonatomic, readonly, copy) NSString *text;
@end

/* What turns old into new, line by line (Myers' diff, which is quick when
 * few lines differ, as after one change of a model): the runs that differ,
 * first to last, their offsets old's. Empty when they are the same. */
NSArray<ORM2TextChange *> *ORM2LineChanges(NSString *old, NSString *new);
