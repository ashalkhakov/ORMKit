/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */
#import "ORMModel.h"

/* The model written as NORMA keeps it (docs/MODEL.md): each element's
 * values into the XML element it was read from, in the document read (the
 * carrier), so that what ORMKit does not model stays as it was.
 *
 * A value is written as NORMA writes it, and only where it differs from
 * what the element has: an element whose values are the model's is left
 * as it is, byte for byte. A default NORMA leaves out is left out, and one
 * a file spells out is kept. */
@interface ORMNormaWriter : NSObject
- (instancetype)initWithModel:(ORMModel *)model;
@property (nonatomic, readonly, strong) ORMModel *model;

/* Every element of the model written. */
- (void)writeModel;
/* The model's custom reference modes the document does not have yet,
 * with their kinds. */
- (void)writeReferenceModes;
/* One element written: its own values, not its children's. */
- (void)writeElement:(ORMElement *)element;
@end
