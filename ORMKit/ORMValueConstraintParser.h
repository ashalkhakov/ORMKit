/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import <Foundation/Foundation.h>

/* A value constraint as a modeller types it and a diagram shows it:
 * "{'M', 'F'}", "{1..10, 20}", "[0..100)", "{'a'..'z'}", "{18..}".
 *
 * Each range comes back as NORMA stores it: min and max (equal for a
 * single value, empty for an open end) and the inclusion of each bound,
 * "NotSet" unless a bracket says "Open" or "Closed". */
@interface ORMValueConstraintParser : NSObject
/* nil with why when the text is not a value constraint. */
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)rangesFromString:(NSString *)text reason:(NSString **)reason;
@end
