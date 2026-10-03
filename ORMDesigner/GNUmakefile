include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ORMDesigner
ORMDesigner_NEEDS_GUI = yes
# ORMDesignerCompat.h: current AppKit names gnustep-gui spells the old way.
ORMDesigner_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Werror=logical-not-parentheses -include ORMDesignerCompat.h
ORMDesigner_INCLUDE_DIRS = -I../ORMKit
ORMDesigner_OBJC_FILES = \
  main.m \
  ORMAppDelegate.m \
  ORMDocument.m \
  ORMWindowController.m \
  ORMCanvasView.m \
  ORMRenderer.m \
  ORMInspectorView.m \
  ORMModelBrowser.m \
  ORMCoreDataController.m \
  ORMQueryController.m
# ORMKit is built in the tree beside this one and not installed.
ADDITIONAL_LIB_DIRS += -L../ORMKit/$(GNUSTEP_OBJ_DIR)
ORMDesigner_OBJC_LIBS += -lORMKit -ldispatch
# The icon GNUstep shows in the About panel, on windows and in the dock
# tile; the AppImage installs the same file as its desktop icon.
ORMDesigner_APPLICATION_ICON = ORMDesigner.png
ORMDesigner_RESOURCE_FILES = ORMDesigner.png
# The menu bar is built in code (-[ORMAppDelegate newMainMenu]).
ORMDesigner_MAIN_MODEL_FILE =

ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif

include $(GNUSTEP_MAKEFILES)/application.make
