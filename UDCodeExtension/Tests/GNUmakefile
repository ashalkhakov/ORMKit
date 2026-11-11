# The ORM2 extension's tests (an XCTest bundle; tools-xctest), against
# UDCode's SDK installed: the extension's sources compiled in (its XIB found
# in this bundle), UDCodeKit's document and text model linked.
#
#   make            build the bundle
#   make run-tests  build and run it (under xvfb-run where there is no display)
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ORM2Tests

ORM2Tests_OBJC_FILES = \
  ORM2Tests.m \
  ../ORM2Extension.m \
  ../ORM2EditorViewController.m \
  ../ORM2FlowEditorViewController.m \
  ../ORM2TextDiff.m
ORM2Tests_RESOURCE_FILES = ../ORM2Editor.xib ../ORM2FlowEditor.xib
ORM2Tests_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include ../../ORMDesignerKit/ORMDesignerCompat.h
include ../../odatakit.make
DESIGNERKIT = $(call ORM_DESIGNERKIT,../..)
ORM2Tests_INCLUDE_DIRS = -I.. -I../../ORMDesignerKit -I../../ORMKit -I../../ORMRuntime $(ODATAKIT_INCLUDE_DIRS)
ADDITIONAL_LIB_DIRS += -L$(DESIGNERKIT) -L../../ORMKit/$(GNUSTEP_OBJ_DIR) -L../../ORMRuntime/$(GNUSTEP_OBJ_DIR) $(ODATAKIT_LIB_DIRS)
ORM2Tests_BUNDLE_LIBS += -lORMDesignerKit -lORMKit -lORMRuntime $(ODATAKIT_LIBS) $(DIAGRAMKITUI_LIBS) \
  -lUDCodeKit -lUDPieceTable -lLSPKit -lXCTest -ldispatch
ORM2Tests_NEEDS_GUI = yes

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 600

.PHONY: run-tests
run-tests: all
	LD_LIBRARY_PATH="$(CURDIR)/$(DESIGNERKIT):$(CURDIR)/../../ORMKit/$(GNUSTEP_OBJ_DIR):$(CURDIR)/../../ORMRuntime/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	PATH="$(CURDIR)/$(DESIGNERKIT):$(CURDIR)/../../ORMKit/$(GNUSTEP_OBJ_DIR):$(CURDIR)/../../ORMRuntime/$(GNUSTEP_OBJ_DIR):$$PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
