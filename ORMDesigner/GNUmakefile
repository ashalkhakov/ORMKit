include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ORMDesigner
ORMDesigner_NEEDS_GUI = yes
# ORMDesignerCompat.h (ORMDesignerKit's): current AppKit names gnustep-gui
# spells the old way.
ORMDesigner_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Werror=logical-not-parentheses -include ../ORMDesignerKit/ORMDesignerCompat.h
include ../odatakit.make
ORMDesigner_INCLUDE_DIRS = -I../ORMDesignerKit -I../ORMKit -I../ORMRuntime $(ODATAKIT_INCLUDE_DIRS)
# The app: its delegate, menu bar, samples and updates. The editor is
# ORMDesignerKit's.
ORMDesigner_OBJC_FILES = \
  main.m \
  ORMUpdater-GNUstep.m \
  ORMAppDelegate.m \
  ORMSampleMenu.m
# ORMDesignerKit and ORMKit are built in the tree beside this one and not installed.
ADDITIONAL_LIB_DIRS += -L$(call ORM_DESIGNERKIT,..) -L../ORMKit/$(GNUSTEP_OBJ_DIR) \
  -L../ORMRuntime/$(GNUSTEP_OBJ_DIR) $(ODATAKIT_LIB_DIRS)
# GSUpdater, the stack's: the designer's updates (ORMUpdater-GNUstep.m).
ORMDesigner_OBJC_LIBS += -lORMDesignerKit -lORMKit -lORMRuntime $(ODATAKIT_LIBS) $(DIAGRAMKITUI_LIBS) -lGSUpdater -ldispatch
# The icon GNUstep shows in the About panel, on windows and in the dock
# tile; the AppImage installs the same file as its desktop icon.
ORMDesigner_APPLICATION_ICON = ORMDesigner.png
# The menu bar is a XIB (the windows are ORMDesignerKit's). Xcode compiles
# it to .nib; here it is copied in as it is, and gnustep-gui reads the XIB
# directly (GSXib5).
ORMDesigner_RESOURCE_FILES = \
  ORMDesigner.png \
  MainMenu.xib \
  ../Samples \
  ../ORMKitTests/Fixtures/ActiveFacts \
  ../ORMKitTests/Fixtures/StockMate.orm
# The samples (File > Open Sample): Resources/Samples and Resources/ActiveFacts
# copied in as folders, the latter with its license, and StockMate.
# The app delegate loads the menu bar itself (-[ORMAppDelegate loadMainMenu]),
# to set what a XIB cannot hold.
ORMDesigner_MAIN_MODEL_FILE =

ifeq ($(SANITIZE),1)
ADDITIONAL_OBJCFLAGS += -fsanitize=address -fno-omit-frame-pointer -g
ADDITIONAL_LDFLAGS += -fsanitize=address
endif

include $(GNUSTEP_MAKEFILES)/application.make
