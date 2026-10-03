# ODataKit, which ORMKit says conceptual queries with (ORMQueryOData.h):
# its ODataKit and ODataIncrementalStore libraries, over Core Data
# (FreeCoreData on GNUstep).
#
# Installed by default, as CI and the docker image have it. A built
# checkout instead:
#
#   make ODATAKIT=../../ODataKit      (after make in that checkout)
ifneq ($(ODATAKIT),)
override ODATAKIT := $(abspath $(ODATAKIT))
ODATAKIT_INCLUDE_DIRS = -I$(ODATAKIT)/Source/ODataKit/include -I$(ODATAKIT)/Source/ODataIncrementalStore/include
ODATAKIT_LIB_DIRS = -L$(ODATAKIT)/obj
endif
# The query builder, which writes the requests' URLs, is the client's.
ODATAKIT_LIBS = -lODataIncrementalStore -lODataKit -lCoreData
