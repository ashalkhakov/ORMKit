# ODataKit, which ORMKit says conceptual queries with (ORMQueryOData.h):
# its ODataKit library, over Core Data (FreeCoreData on GNUstep).
#
# Installed by default, as CI and the docker image have it. A built
# checkout instead:
#
#   make ODATAKIT=../../ODataKit      (after make in that checkout)
ifneq ($(ODATAKIT),)
override ODATAKIT := $(abspath $(ODATAKIT))
ODATAKIT_INCLUDE_DIRS = -I$(ODATAKIT)/Source/ODataKit/include
ODATAKIT_LIB_DIRS = -L$(ODATAKIT)/obj
endif
ODATAKIT_LIBS = -lODataKit -lCoreData
