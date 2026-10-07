include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = ORMDesigner
ORMDesigner_NEEDS_GUI = yes
# ORMDesignerCompat.h: current AppKit names gnustep-gui spells the old way.
ORMDesigner_OBJCFLAGS += -fobjc-arc -fblocks -Wall -Werror=logical-not-parentheses -include ORMDesignerCompat.h
include ../odatakit.make
ORMDesigner_INCLUDE_DIRS = -I../ORMKit -I../ORMRuntime $(ODATAKIT_INCLUDE_DIRS)
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
  ORMQueryController.m \
  ORMSampleMenu.m \
  ORMPane.m \
  ORMInsertPalette.m \
  ORMIssuesView.m \
  ORMSearchNavigator.m \
  ORMPopulationView.m \
  ThirdParty/DMTabBar/DMTabBar.m \
  ThirdParty/DMTabBar/DMTabBarItem.m
# ORMKit is built in the tree beside this one and not installed.
ADDITIONAL_LIB_DIRS += -L../ORMKit/$(GNUSTEP_OBJ_DIR) -L../ORMRuntime/$(GNUSTEP_OBJ_DIR) $(ODATAKIT_LIB_DIRS)
ORMDesigner_OBJC_LIBS += -lORMKit -lORMRuntime $(ODATAKIT_LIBS) -ldispatch
# The icon GNUstep shows in the About panel, on windows and in the dock
# tile; the AppImage installs the same file as its desktop icon.
ORMDesigner_APPLICATION_ICON = ORMDesigner.png
# The windows and the menu bar are XIBs. Xcode compiles them to .nib; here
# they are copied in as they are, and gnustep-gui reads the XIB directly
# (GSXib5). Both are found by the same -initWithNibNamed:, so no path or
# extension appears in the source.
ORMDesigner_RESOURCE_FILES = \
  ORMDesigner.png \
  MainMenu.xib \
  ORMQueryWindow.xib \
  ORMCoreDataWindow.xib \
  ORMDocumentWindow.xib \
  ORMInsertPalette.xib \
  ORMIssuesView.xib \
  ORMSearchNavigator.xib \
  ORMPopulationView.xib \
  ThirdParty/DMTabBar/LICENSE-DMTabBar.txt \
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
