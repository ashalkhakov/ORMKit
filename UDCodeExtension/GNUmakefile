include $(GNUSTEP_MAKEFILES)/common.make

# UDCode's ORM2 extension (docs/UDCODE.md): ORM2.bundle, ORMDesignerKit's
# editor in a UDCode tab. Built against UDCode's SDK (its udcodekit archive,
# .github/pins.env's UDCODEKIT_VERSION) installed on the same GNUstep stack
# as UDCode's; the top GNUmakefile builds it only where that SDK is.
# Scripts/udcx.sh packages it, its libraries inside it.
BUNDLE_NAME = ORM2
BUNDLE_EXTENSION = .bundle
ORM2_PRINCIPAL_CLASS = ORM2Extension
ORM2_NEEDS_GUI = yes
ORM2_STANDARD_INSTALL = no
# ORMDesignerKit's editor compiled in, its XIBs among the bundle's resources
# (+bundleForClass: then answers this bundle): a framework inside the bundle
# would need its DLL beside its resources, where Windows does not look for
# the bundle's DLL's libraries.
include ../ORMDesignerKit/files.make
ORM2_OBJC_FILES = \
  ORM2Extension.m \
  ORM2EditorViewController.m \
  ORM2TextDiff.m \
  $(addprefix ../ORMDesignerKit/,$(ORM_DESIGNERKIT_OBJC_FILES))
ORM2_RESOURCE_FILES = \
  Resources/LanguageInfo.plist \
  ORM2Editor.xib \
  $(addprefix ../ORMDesignerKit/,$(ORM_DESIGNERKIT_RESOURCE_FILES))
# ORMDesignerCompat.h (ORMDesignerKit's): current AppKit names gnustep-gui
# spells the old way.
ORM2_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Werror=logical-not-parentheses -include ../ORMDesignerKit/ORMDesignerCompat.h
include ../odatakit.make
ORM2_INCLUDE_DIRS = -I../ORMDesignerKit -I../ORMKit -I../ORMRuntime $(ODATAKIT_INCLUDE_DIRS)
ORM2_LIB_DIRS += -L../ORMKit/$(GNUSTEP_OBJ_DIR) -L../ORMRuntime/$(GNUSTEP_OBJ_DIR) $(ODATAKIT_LIB_DIRS)
# Its own libraries, which the package puts beside its binary (ORMKit's,
# ODataKit's): found from where the binary is. UDCode's own (UDCodeKit,
# DiagramKit, GNUstep's) are the running UDCode's: on Linux left for it, as
# UDCode's own plug-ins leave them; a Windows DLL is linked against all it uses.
ORM2_BUNDLE_LIBS += -lORMKit -lORMRuntime $(ODATAKIT_LIBS) $(DIAGRAMKITUI_LIBS) -ldispatch
ifneq ($(OS),Windows_NT)
ORM2_LDFLAGS += -Wl,-rpath,'$$ORIGIN'
else
ORM2_BUNDLE_LIBS += -lUDCodeKit -lUDPieceTable -lLSPKit -lgnustep-gui -lgnustep-base -lobjc
endif

ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif

include $(GNUSTEP_MAKEFILES)/bundle.make
