# An XCTest bundle that requires tools-xctest. ORMDesignerKit is linked, its
# XIBs found in it; the app's own sources are compiled into the bundle (all
# but main.m): -bundleForClass: then resolves the menu bar to this bundle,
# and the app need not be loaded.
#
#   make            build the bundle
#   make run-tests  build and run it (under xvfb-run where there is no display)
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ORMDesignerTests

ORMDesignerTests_OBJC_FILES = \
  ORMDesignerTests.m \
  ../ORMDesigner/ORMUpdater.m \
  ../ORMDesigner/ORMAppDelegate.m \
  ../ORMDesigner/ORMSampleMenu.m
ORMDesignerTests_OBJCFLAGS += -fobjc-arc -fblocks -Wall -include ../ORMDesignerKit/ORMDesignerCompat.h
include ../odatakit.make
DESIGNERKIT = ../ORMDesignerKit/ORMDesignerKit.framework/Versions/Current
ORMDesignerTests_INCLUDE_DIRS = -I../ORMDesignerKit -I../ORMKit -I../ORMRuntime -I../ORMDesigner $(ODATAKIT_INCLUDE_DIRS)
ADDITIONAL_LIB_DIRS += -L$(DESIGNERKIT) -L../ORMKit/$(GNUSTEP_OBJ_DIR) -L../ORMRuntime/$(GNUSTEP_OBJ_DIR) $(ODATAKIT_LIB_DIRS)
ORMDesignerTests_BUNDLE_LIBS += -lORMDesignerKit -lORMKit -lORMRuntime $(ODATAKIT_LIBS) $(DIAGRAMKITUI_LIBS) -lXCTest -ldispatch
ORMDesignerTests_NEEDS_GUI = yes
# The menu bar: the app delegate loads it from the bundle it is in, which
# here is this one.
ORMDesignerTests_RESOURCE_FILES = \
  ../ORMDesigner/MainMenu.xib

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
	LD_LIBRARY_PATH="$(CURDIR)/$(DESIGNERKIT):$(CURDIR)/../ORMKit/$(GNUSTEP_OBJ_DIR):$(CURDIR)/../ORMRuntime/$(GNUSTEP_OBJ_DIR):$(if $(ODATAKIT),$(ODATAKIT)/obj:)$$LD_LIBRARY_PATH" \
	PATH="$(CURDIR)/$(DESIGNERKIT):$(CURDIR)/../ORMKit/$(GNUSTEP_OBJ_DIR):$(CURDIR)/../ORMRuntime/$(GNUSTEP_OBJ_DIR):$(if $(ODATAKIT),$(ODATAKIT)/obj:)$$PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
