# An XCTest bundle that requires tools-xctest. The designer's sources are
# compiled into it (all but main.m): -bundleForClass: then resolves to this
# bundle, and the app need not be loaded.
#
#   make            build the bundle
#   make run-tests  build and run it (under xvfb-run where there is no display)
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ORMDesignerTests

ORMDesignerTests_OBJC_FILES = \
  ORMDesignerTests.m \
  ../ORMDesigner/ORMAppDelegate.m \
  ../ORMDesigner/ORMDocument.m \
  ../ORMDesigner/ORMWindowController.m \
  ../ORMDesigner/ORMCanvasView.m \
  ../ORMDesigner/ORMRenderer.m \
  ../ORMDesigner/ORMInspectorView.m \
  ../ORMDesigner/ORMModelBrowser.m \
  ../ORMDesigner/ORMCoreDataController.m \
  ../ORMDesigner/ORMQueryController.m \
  ../ORMDesigner/ORMSampleMenu.m \
  ../ORMDesigner/ORMPane.m \
  ../ORMDesigner/ORMInsertPalette.m \
  ../ORMDesigner/ORMIssuesView.m \
  ../ORMDesigner/ORMSearchNavigator.m \
  ../ORMDesigner/ORMPopulationView.m \
  ../ORMDesigner/ThirdParty/DMTabBar/DMTabBar.m \
  ../ORMDesigner/ThirdParty/DMTabBar/DMTabBarItem.m
ORMDesignerTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include ../ORMDesigner/ORMDesignerCompat.h
include ../odatakit.make
ORMDesignerTests_INCLUDE_DIRS = -I../ORMKit -I../ORMDesigner $(ODATAKIT_INCLUDE_DIRS)
ADDITIONAL_LIB_DIRS += -L../ORMKit/$(GNUSTEP_OBJ_DIR) $(ODATAKIT_LIB_DIRS)
ORMDesignerTests_BUNDLE_LIBS += -lORMKit $(ODATAKIT_LIBS) -lXCTest -ldispatch
ORMDesignerTests_NEEDS_GUI = yes
# The designer's XIBs: its classes load them from the bundle they are in,
# which here is this one.
ORMDesignerTests_RESOURCE_FILES = \
  ../ORMDesigner/MainMenu.xib \
  ../ORMDesigner/ORMQueryWindow.xib \
  ../ORMDesigner/ORMCoreDataWindow.xib \
  ../ORMDesigner/ORMDocumentWindow.xib \
  ../ORMDesigner/ORMInsertPalette.xib \
  ../ORMDesigner/ORMIssuesView.xib \
  ../ORMDesigner/ORMSearchNavigator.xib \
  ../ORMDesigner/ORMPopulationView.xib

ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
ASAN_ARCH := $(shell uname -m)
ASAN_LIB := $(shell $(CC) -print-file-name=libclang_rt.asan-$(ASAN_ARCH).so)
SANITIZE_ENV := LD_PRELOAD="$(ASAN_LIB)" ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:handle_abort=1
endif

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest
TEST_TIMEOUT ?= 600

.PHONY: run-tests
run-tests: all
	$(SANITIZE_ENV) \
	LD_LIBRARY_PATH="$(CURDIR)/../ORMKit/$(GNUSTEP_OBJ_DIR):$(if $(ODATAKIT),$(ODATAKIT)/obj:)$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
