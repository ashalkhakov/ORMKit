include $(GNUSTEP_MAKEFILES)/common.make

# A library, not a framework, on GNUstep: a framework puts its binary under
# Versions/<v>/<target>/, which every consumer would then have to name. Xcode
# builds the same sources as ORMKit.framework (.tools/genxcodeproj.py reads
# the lists below).
LIBRARY_NAME = ORMKit
# No AppKit: NSXML for the files, DiagramKit (Foundation only) for drawing
# and laying out the diagrams, Core Data for queries and populations in a
# store. What draws on screen lives in ORMDesigner. ODataKit for the OData
# requests.
ORMKit_NEEDS_GUI = no
include ../odatakit.make
# ORMRuntime, built in the tree beside this one: the plans and their driver.
ORMKit_INCLUDE_DIRS += -I../ORMRuntime $(ODATAKIT_INCLUDE_DIRS)
ORMKit_LIB_DIRS += -L../ORMRuntime/$(GNUSTEP_OBJ_DIR) $(ODATAKIT_LIB_DIRS)
ORMKit_LIBRARIES_DEPEND_UPON += -lORMRuntime $(ODATAKIT_LIBS) $(DIAGRAMKIT_LIBS)
ORMKit_OBJCFLAGS += -fobjc-arc -Wall -Werror=logical-not-parentheses
ORMKit_HEADER_FILES = \
  ORMKit.h \
  ORMXML.h \
  ORMModel.h \
  ORMDiagram.h \
  ORMDiagramPainter.h \
  ORMReadingText.h \
  ORMValueConstraintParser.h \
  ORMEditor.h \
  ORMNormaWriter.h \
  ORMObjectTypeEditor.h \
  ORMFactTypeEditor.h \
  ORMConstraintEditor.h \
  ORMDiagramEditor.h \
  ORMElementEditor.h \
  ORMPopulationEditor.h \
  ORMPopulationStore.h \
  ORMPopulationChecker.h \
  ORMPopulationGenerator.h \
  ORMPath.h \
  ORMLogic.h \
  ORMVerbalizer.h \
  ORMFactSentence.h \
  ORMConstraintSentence.h \
  ORMSentenceEditor.h \
  ORMJoinPathBuilder.h \
  ORMDerivationPathWriter.h \
  ORMConstraintQueries.h \
  ORMCDModel.h \
  ORMCoreDataMapping.h \
  ORMCoreDataMapper.h \
  ORMCoreDataSync.h \
  ORMCoreDataImport.h \
  ORMCoreDataValidation.h \
  ORMODataAnnotator.h \
  ORMQuery.h \
  ORMQueryExpression.h \
  ORMCDModel+CoreData.h \
  ORMQueryPlanner.h \
  ORMQueryOData+ORMKit.h \
  ORMRuleChecker.h \
  ORMIssueFinder.h \
  ORMDeriver.h \
  ORMJoinedFacade.h \
  ORMEntityMerger.h \
  ORMOutlineReader.h \
  ORMSchemaText.h
ORMKit_OBJC_FILES = \
  ORMXML.m \
  ORMModel.m \
  ORMDiagram.m \
  ORMDiagramPainter.m \
  ORMReadingText.m \
  ORMValueConstraintParser.m \
  ORMEditor.m \
  ORMNormalizer.m \
  ORMNormaWriter.m \
  ORMObjectTypeEditor.m \
  ORMFactTypeEditor.m \
  ORMConstraintEditor.m \
  ORMDiagramEditor.m \
  ORMElementEditor.m \
  ORMPopulationEditor.m \
  ORMPopulationStore.m \
  ORMPopulationChecker.m \
  ORMPopulationGenerator.m \
  ORMPath.m \
  ORMLogic.m \
  ORMVerbalizer.m \
  ORMVerbalizer+Logic.m \
  ORMFactSentence.m \
  ORMConstraintSentence.m \
  ORMStatementSentence.m \
  ORMJoinPathBuilder.m \
  ORMDerivationPathWriter.m \
  ORMConstraintQueries.m \
  ORMCDModel.m \
  ORMCoreDataMapping.m \
  ORMCoreDataMapper.m \
  ORMCoreDataSync.m \
  ORMCoreDataImport.m \
  ORMCoreDataValidation.m \
  ORMODataAnnotator.m \
  ORMQuery.m \
  ORMQueryExpression.m \
  ORMCDModel+CoreData.m \
  ORMQueryPlaces.m \
  ORMQueryPlanner.m \
  ORMRuleChecker.m \
  ORMIssueFinder.m \
  ORMDeriver.m \
  ORMJoinedFacade.m \
  ORMEntityMerger.m \
  ORMOutlineReader.m \
  ORMSchemaText.m \
  ORMQueryOData+ORMKit.m

# AddressSanitizer: names the write and the allocation it ran past, at the
# moment it happens, instead of whatever allocation later notices.
#
#   make -C ORMKit SANITIZE=1 && make -C ORMKitTests run-tests SANITIZE=1
ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif

# Undefined behaviour: signed overflow, shifts, misaligned and null pointers,
# out-of-range enum and bool loads.
ifeq ($(UBSAN),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_CFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=undefined
endif

include $(GNUSTEP_MAKEFILES)/library.make
