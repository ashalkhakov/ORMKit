include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = ormtool
ormtool_OBJC_FILES = ormtool.m
ormtool_OBJCFLAGS += -fobjc-arc -Wall
ormtool_INCLUDE_DIRS = -I../../ORMKit
# ORMKit is built in the tree beside this one and not installed.
ADDITIONAL_LIB_DIRS += -L../../ORMKit/$(GNUSTEP_OBJ_DIR)
ormtool_TOOL_LIBS += -lORMKit -ldispatch

# AddressSanitizer, to link against an ORMKit built with SANITIZE=1. The
# tool is instrumented itself, so the runtime needs no preloading.
ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif

include $(GNUSTEP_MAKEFILES)/tool.make
