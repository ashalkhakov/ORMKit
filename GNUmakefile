#
# ORMKit on GNUstep: ORMRuntime, ORMKit, ormtool and ORMDesigner, and their
# tests.
#
#   make            the libraries, the tool and the designer
#   make check      the imports (Scripts/check-imports.sh); both suites,
#                   built and run under AddressSanitizer (the designer's
#                   under Xvfb when there is no display); ormtool on the
#                   StockMate model (Scripts/ormtool-smoke.sh)
#   make install    the libraries, ormtool and ORMDesigner
#
# Each part builds on the libraries in the tree, not installed ones; on
# FreeCoreData and ODataKit installed (.github/pins.env's releases).
# macOS: Makefile.apple.
#
ifeq ($(GNUSTEP_MAKEFILES),)
  $(error Set GNUSTEP_MAKEFILES (source GNUstep.sh). macOS: make -f Makefile.apple)
endif

include $(GNUSTEP_MAKEFILES)/common.make

PACKAGE_NAME = ORMKit
SUBPROJECTS = ORMRuntime ORMKit Tools/ormtool ORMDesigner

include $(GNUSTEP_MAKEFILES)/aggregate.make

XVFB = $(if $(DISPLAY),,$(shell command -v xvfb-run >/dev/null 2>&1 && echo xvfb-run -a))
ORM_RUN = LD_LIBRARY_PATH="$(CURDIR)/ORMKit/$(GNUSTEP_OBJ_DIR_NAME):$(CURDIR)/ORMRuntime/$(GNUSTEP_OBJ_DIR_NAME)$${LD_LIBRARY_PATH:+:$$LD_LIBRARY_PATH}"

# The suites are built here, not with the rest: under AddressSanitizer
# (SANITIZE=1), which names a bad write where it happens.
check::
	Scripts/check-imports.sh
	$(MAKE) -C ORMKitTests run-tests SANITIZE=1
	$(XVFB) $(MAKE) -C ORMDesignerTests run-tests SANITIZE=1
	$(ORM_RUN) Scripts/ormtool-smoke.sh Tools/ormtool/$(GNUSTEP_OBJ_DIR_NAME)/ormtool

after-clean::
	$(MAKE) -C ORMKitTests clean
	$(MAKE) -C ORMDesignerTests clean
