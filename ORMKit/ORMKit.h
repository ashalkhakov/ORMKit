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
 * ORMPopulationEditor, ORMPopulationChecker, ORMPopulationGenerator,
 * ORMPopulationStore
 *               sample populations: written as NORMA writes them, checked
 *               against the constraints, made up to meet them, and put in a
 *               Core Data store for queries to run against
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
#import "ORMObjectTypeEditor.h"
#import "ORMFactTypeEditor.h"
#import "ORMConstraintEditor.h"
#import "ORMDiagramEditor.h"
#import "ORMElementEditor.h"
#import "ORMPopulationEditor.h"
#import "ORMSentenceEditor.h"
#import "ORMCoreDataValidation.h"
#import "ORMODataAnnotator.h"
#import "ORMQuery.h"
#import "ORMCDModel+CoreData.h"
#if __has_include(<ORMRuntime/ORMRuntime.h>)
#import <ORMRuntime/ORMRuntime.h>
#else
#import "ORMRuntime.h"
#endif
#import "ORMQueryPlanner.h"
#import "ORMRuleChecker.h"
#import "ORMIssueFinder.h"
#import "ORMDeriver.h"
#import "ORMJoinedFacade.h"
#import "ORMEntityMerger.h"
#import "ORMOutlineReader.h"
#import "ORMPopulationStore.h"
#import "ORMPopulationChecker.h"
#import "ORMPopulationGenerator.h"
#import "ORMQueryOData.h"
