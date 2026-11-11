include $(GNUSTEP_MAKEFILES)/common.make

# ORMDesigner's editor as a framework (ORMDesignerKit.h): ORMDesigner.app is
# its app delegate and menu bar over it, and other apps host it to edit
# models of their own (UDCode's ORM2 extension), as XFormsDesignKit is the
# XForms Designer's. A framework, not a library as ORMKit is: its XIBs are
# its resources, found with -bundleForClass:. Xcode builds the same sources
# (.tools/genxcodeproj.py reads the lists below).
FRAMEWORK_NAME = ORMDesignerKit
ORMDesignerKit_NEEDS_GUI = yes
ORMDesignerKit_CURRENT_VERSION_NAME = A
ORMDesignerKit_DEPLOY_WITH_CURRENT_VERSION = yes
# ORMDesignerCompat.h: current AppKit names gnustep-gui spells the old way.
ORMDesignerKit_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Werror=logical-not-parentheses -include ORMDesignerCompat.h
include ../odatakit.make
ORMDesignerKit_INCLUDE_DIRS = -I../ORMKit -I../ORMRuntime $(ODATAKIT_INCLUDE_DIRS)
ORMDesignerKit_LIB_DIRS += -L../ORMKit/$(GNUSTEP_OBJ_DIR) -L../ORMRuntime/$(GNUSTEP_OBJ_DIR) $(ODATAKIT_LIB_DIRS)
ORMDesignerKit_LIBRARIES_DEPEND_UPON += -lORMKit -lORMRuntime $(ODATAKIT_LIBS) $(DIAGRAMKITUI_LIBS) -ldispatch
include files.make
ORMDesignerKit_OBJC_FILES = $(ORM_DESIGNERKIT_OBJC_FILES)
ORMDesignerKit_RESOURCE_FILES = $(ORM_DESIGNERKIT_RESOURCE_FILES)
ORMDesignerKit_HEADER_FILES = \
  ORMDesignerKit.h \
  ORMDesignerCompat.h \
  ORMDocument.h \
  ORMWindowController.h \
  ORMModelViewController.h \
  ORMCanvasView.h \
  ORMRenderer.h \
  ORMInspectorView.h \
  ORMModelBrowser.h \
  ORMCoreDataController.h \
  ORMQueryController.h \
  ORMFlowDocument.h \
  ORMFlowWindowController.h \
  ORMFlowPlayController.h \
  ORMFlowCanvasView.h \
  ORMPane.h \
  ORMInsertPalette.h \
  ORMIssuesView.h \
  ORMSearchNavigator.h \
  ORMPopulationView.h

ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif

include $(GNUSTEP_MAKEFILES)/framework.make
