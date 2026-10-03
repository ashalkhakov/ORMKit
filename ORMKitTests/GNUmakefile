# An XCTest bundle that requires tools-xctest
# (https://github.com/gnustep/tools-xctest)
#
#   make            build the bundle
#   make run-tests  build and run it
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ORMKitTests

ORMKitTests_OBJC_FILES = \
  ORMTestSupport.m \
  ORMFileTests.m \
  ORMModelTests.m \
  ORMTextTests.m \
  ORMEditorTests.m \
  ORMLogicTests.m \
  ORMConstraintSentenceTests.m \
  ORMSVGTests.m \
  ORMVerbalizerTests.m \
  ORMCoreDataTests.m \
  ORMCoreDataImportTests.m
ORMKitTests_OBJCFLAGS += -fobjc-arc -Wall -Werror=logical-not-parentheses
ORMKitTests_INCLUDE_DIRS = -I../ORMKit
ADDITIONAL_LIB_DIRS += -L../ORMKit/$(GNUSTEP_OBJ_DIR)
ORMKitTests_BUNDLE_LIBS += -lORMKit -lXCTest -ldispatch
ORMKitTests_NEEDS_GUI = no

# AddressSanitizer. The bundle is dlopened by an xctest binary that is not
# instrumented, so the ASan runtime is loaded first or its interceptors are
# never installed; it is named after the architecture, so it is looked up.
ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
ASAN_ARCH := $(shell uname -m)
ASAN_LIB := $(shell $(CC) -print-file-name=libclang_rt.asan-$(ASAN_ARCH).so)
SANITIZE_ENV := LD_PRELOAD="$(ASAN_LIB)" ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:handle_abort=1
endif

ifeq ($(UBSAN),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_CFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=undefined
UBSAN_ARCH := $(shell uname -m)
UBSAN_LIB := $(shell $(CC) -print-file-name=libclang_rt.ubsan_standalone-$(UBSAN_ARCH).so)
SANITIZE_ENV := LD_PRELOAD="$(UBSAN_LIB)" UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=0
endif

include $(GNUSTEP_MAKEFILES)/bundle.make

XCTEST ?= xctest

# The NORMA files are found relative to __FILE__ rather than through the
# bundle, so they need no RESOURCE_FILES entry -- but the tests run from a
# source tree, not an installed bundle. Bounded: a hang costs TEST_TIMEOUT
# seconds, not the job's whole budget.
TEST_TIMEOUT ?= 600

.PHONY: run-tests
run-tests: all
	$(SANITIZE_ENV) \
	LD_LIBRARY_PATH="$(CURDIR)/../ORMKit/$(GNUSTEP_OBJ_DIR):$$LD_LIBRARY_PATH" \
	  timeout -s ABRT $(TEST_TIMEOUT) $(XCTEST) $(BUNDLE_NAME).bundle
