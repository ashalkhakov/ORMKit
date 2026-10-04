include $(GNUSTEP_MAKEFILES)/common.make

# A library, not a framework, on GNUstep: a framework puts its binary under
# Versions/<v>/<target>/, which every consumer would then have to name. Xcode
# builds the same sources as ORMKit.framework (.tools/genxcodeproj.py reads
# the lists below).
LIBRARY_NAME = ORMKit
# Foundation only: NSXML for the files, NSGeometry for the diagrams. What
# draws lives in ORMDesigner. ODataKit for the OData requests.
ORMKit_NEEDS_GUI = no
include ../odatakit.make
ORMKit_INCLUDE_DIRS += $(ODATAKIT_INCLUDE_DIRS)
ORMKit_LIB_DIRS += $(ODATAKIT_LIB_DIRS)
ORMKit_LIBRARIES_DEPEND_UPON += $(ODATAKIT_LIBS)
ORMKit_OBJCFLAGS += -fobjc-arc -Wall -Werror=logical-not-parentheses
ORMKit_HEADER_FILES = \
  ORMKit.h \
  ORMXML.h \
  ORMModel.h \
  ORMDiagram.h \
  ORMDiagramPainter.h \
  ORMSVGSurface.h \
  ORMReadingText.h \
  ORMValueConstraintParser.h \
  ORMEditor.h \
  ORMObjectTypeEditor.h \
  ORMFactTypeEditor.h \
  ORMConstraintEditor.h \
  ORMDiagramEditor.h \
  ORMElementEditor.h \
  ORMPath.h \
  ORMLogic.h \
  ORMVerbalizer.h \
  ORMFactSentence.h \
  ORMConstraintSentence.h \
  ORMSentenceEditor.h \
  ORMJoinPathBuilder.h \
  ORMCDModel.h \
  ORMCoreDataMapping.h \
  ORMCoreDataMapper.h \
  ORMCoreDataSync.h \
  ORMCoreDataImport.h \
  ORMCoreDataValidation.h \
  ORMODataAnnotator.h \
  ORMQuery.h \
  ORMCDModel+CoreData.h \
  ORMQueryPlan.h \
  ORMQueryPlanner.h \
  ORMQueryInterpreter.h \
  ORMQueryOData.h
ORMKit_OBJC_FILES = \
  ORMXML.m \
  ORMModel.m \
  ORMDiagram.m \
  ORMDiagramPainter.m \
  ORMSVGSurface.m \
  ORMReadingText.m \
  ORMValueConstraintParser.m \
  ORMEditor.m \
  ORMNormalizer.m \
  ORMObjectTypeEditor.m \
  ORMFactTypeEditor.m \
  ORMConstraintEditor.m \
  ORMDiagramEditor.m \
  ORMElementEditor.m \
  ORMPath.m \
  ORMLogic.m \
  ORMVerbalizer.m \
  ORMVerbalizer+Logic.m \
  ORMFactSentence.m \
  ORMConstraintSentence.m \
  ORMJoinPathBuilder.m \
  ORMCDModel.m \
  ORMCoreDataMapping.m \
  ORMCoreDataMapper.m \
  ORMCoreDataSync.m \
  ORMCoreDataImport.m \
  ORMCoreDataValidation.m \
  ORMODataAnnotator.m \
  ORMQuery.m \
  ORMCDModel+CoreData.m \
  ORMQueryPlaces.m \
  ORMQueryPlan.m \
  ORMQueryPlanner.m \
  ORMQueryInterpreter.m \
  ORMQueryOData.m

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
