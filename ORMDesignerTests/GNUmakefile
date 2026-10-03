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
  ../ORMDesigner/ORMCoreDataController.m
ORMDesignerTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include ../ORMDesigner/ORMDesignerCompat.h
ORMDesignerTests_INCLUDE_DIRS = -I../ORMKit -I../ORMDesigner
ADDITIONAL_LIB_DIRS += -L../ORMKit/$(GNUSTEP_OBJ_DIR)
ORMDesignerTests_BUNDLE_LIBS += -lORMKit -lXCTest -ldispatch
ORMDesignerTests_NEEDS_GUI = yes

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
	LD_LIBRARY_PATH="$(CURDIR)/../ORMKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
