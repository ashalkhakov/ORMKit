include $(GNUSTEP_MAKEFILES)/common.make

# What an app built from an ORM model runs (docs/RUNTIME.md): plans, and the
# driver that reads them against a store. No ORM model, no NSXML: ORMKit
# makes the plans and links this to run them. A library on GNUstep, as
# ORMKit is; Xcode builds the same sources as ORMRuntime.framework
# (.tools/genxcodeproj.py reads the lists below).
LIBRARY_NAME = ORMRuntime
ORMRuntime_NEEDS_GUI = no
# Installed as <ORMRuntime/...>, the way Xcode's framework is imported.
ORMRuntime_HEADER_FILES_INSTALL_DIR = ORMRuntime
include ../odatakit.make
ORMRuntime_INCLUDE_DIRS += $(ODATAKIT_INCLUDE_DIRS)
ORMRuntime_LIB_DIRS += $(ODATAKIT_LIB_DIRS)
# ODataKit for an entity's key attributes (ODataPropertyMapper).
ORMRuntime_LIBRARIES_DEPEND_UPON += -lODataKit -lCoreData
ORMRuntime_OBJCFLAGS += -fobjc-arc -Wall -Werror=logical-not-parentheses
ORMRuntime_HEADER_FILES = \
  ORMRuntime.h \
  ORMQueryPlan.h \
  ORMQueryInterpreter.h \
  ORMCursor.h \
  ORMTables.h \
  ORMSaveHook.h
ORMRuntime_OBJC_FILES = \
  ORMQueryPlan.m \
  ORMQueryInterpreter.m \
  ORMCursor.m \
  ORMTables.m \
  ORMSaveHook.m

# As ORMKit's: AddressSanitizer and undefined behaviour, for the tests.
ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif
ifeq ($(UBSAN),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_CFLAGS += -fsanitize=undefined -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=undefined
endif

include $(GNUSTEP_MAKEFILES)/library.make
