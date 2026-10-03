/* Copyright (c) 2026 the ORMKit contributors. LGPL 2.1. */

/* ORMKit: Object-Role Modeling (ORM2) models as NORMA saves them.
 *
 * ORMXML        reading and writing .orm files, byte for byte where nothing changed
 * ORMModel      the model read into objects: object types, fact types, roles,
 *               readings, constraints, data types, notes
 * ORMDiagram    NORMA's diagrams and their shapes
 * ORMEditor     every change to a model, undoable, keeping NORMA's derived data
 * ORMVerbalizer the model read out as FORML sentences
 * ORMCDModel    a Core Data model's source, as Xcode keeps it
 * ORMCoreDataMapping, ORMCoreDataMapper
 *               ORM to Core Data, and back (docs/COREDATA-MAPPING.md)
 * ORMReadingText, ORMValueConstraintParser, ORMFactSentence
 *               the small languages a modeller types: readings, value lists,
 *               and NORMA's Fact Editor sentences */

#import "ORMXML.h"
#import "ORMModel.h"
#import "ORMDiagram.h"
#import "ORMDiagramPainter.h"
#import "ORMSVGSurface.h"
#import "ORMPath.h"
#import "ORMLogic.h"
#import "ORMReadingText.h"
#import "ORMValueConstraintParser.h"
#import "ORMEditor.h"
#import "ORMVerbalizer.h"
#import "ORMFactSentence.h"
#import "ORMConstraintSentence.h"
#import "ORMJoinPathBuilder.h"
#import "ORMCDModel.h"
#import "ORMCoreDataMapping.h"
#import "ORMCoreDataMapper.h"
#import "ORMCoreDataSync.h"
#import "ORMCoreDataImport.h"
#import "ORMCoreDataValidation.h"
