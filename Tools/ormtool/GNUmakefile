include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = ormtool
ormtool_OBJC_FILES = ormtool.m
ormtool_OBJCFLAGS += -fobjc-arc -Wall
ormtool_INCLUDE_DIRS = -I../../ORMKit
# ORMKit is built in the tree beside this one and not installed.
ADDITIONAL_LIB_DIRS += -L../../ORMKit/$(GNUSTEP_OBJ_DIR)
ormtool_TOOL_LIBS += -lORMKit -ldispatch

include $(GNUSTEP_MAKEFILES)/tool.make
