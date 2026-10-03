/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMFactSentence.h"
#import "ORMConstraintSentence.h"

/* What the Fact Editor takes: sentences, read against the model and made
 * into what they say. */
@interface ORMSentenceEditor : NSObject
- (instancetype)initWithEditor:(ORMEditor *)editor;
@property (nonatomic, readonly, strong) ORMEditor *editor;

/* Makes what the sentence says, as one step: the object types and fact
 * types it names that the model lacks (placed on the diagram), then its
 * constraints. A sentence that is no constraint is taken as a fact type,
 * as the Fact Editor takes it. The ids of what was made. */
- (NSArray<NSString *> *)addFromSentence:(NSString *)text
                               onDiagram:(NSString *)diagramId
                                      at:(NSPoint)point
                                  reason:(NSString **)reason;
@end

@interface ORMSentenceEditor (ORMFactSentences)
/* Makes what the sentence says: its new object types and the fact type,
 * placed on the diagram. The fact type's id. */
- (NSString *)addFactTypeFromSentence:(NSString *)text
                            onDiagram:(NSString *)diagramId
                                   at:(NSPoint)point
                               reason:(NSString **)reason;
@end
