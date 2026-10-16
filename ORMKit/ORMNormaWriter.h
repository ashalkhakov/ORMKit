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

/* The ids of elements the model has just taken away: references to them
 * go, where a reference the model cannot resolve otherwise stays (a file
 * NORMA left so). */
@property (nonatomic, copy) NSSet<NSString *> *gone;

/* Every element of the model written. */
- (void)writeModel;
/* The model's custom reference modes the document does not have yet,
 * with their kinds. */
- (void)writeReferenceModes;
/* Whether readings get NORMA's <orm:ExpandedData>: a file of an older
 * NORMA that has none keeps none. */
@property (nonatomic) BOOL writesExpandedData;
/* What NORMA keeps beside the model for the element, derived: an object
 * type's PlayedRoles and _ReferenceMode; a fact type's _Name, its roles'
 * _IsMandatory and _Multiplicity, its InternalConstraints and its
 * readings' ExpandedData; a uniqueness constraint's
 * PreferredIdentifierFor. */
- (void)writeNormaDataOf:(ORMElement *)element;
/* One element written: its own values, not its children's. */
- (void)writeElement:(ORMElement *)element;
@end
