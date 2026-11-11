# ORMDesignerKit's sources and resources, for its framework (GNUmakefile)
# and for what compiles them in (UDCodeExtension: on GNUstep the ORM2
# bundle carries the editor itself, its XIBs among its resources, since
# Windows would not find a framework's DLL inside the bundle).
# .tools/genxcodeproj.py reads them too.
ORM_DESIGNERKIT_OBJC_FILES = \
  ORMDocument.m \
  ORMWindowController.m \
  ORMModelViewController.m \
  ORMCanvasView.m \
  ORMRenderer.m \
  ORMInspectorView.m \
  ORMModelBrowser.m \
  ORMCoreDataController.m \
  ORMQueryController.m \
  ORMFlowDocument.m \
  ORMFlowWindowController.m \
  ORMFlowPlayController.m \
  ORMFlowCanvasView.m \
  ORMPane.m \
  ORMInsertPalette.m \
  ORMIssuesView.m \
  ORMSearchNavigator.m \
  ORMPopulationView.m \
  ThirdParty/DMTabBar/DMTabBar.m \
  ThirdParty/DMTabBar/DMTabBarItem.m
# The windows and panes are XIBs. Xcode compiles them to .nib; GNUstep
# copies them in as they are, and gnustep-gui reads the XIB directly (GSXib5).
ORM_DESIGNERKIT_RESOURCE_FILES = \
  ORMModelView.xib \
  ORMModelMenus.xib \
  ORMDocumentWindow.xib \
  ORMQueryWindow.xib \
  ORMFlowWindow.xib \
  ORMFlowPlayWindow.xib \
  ORMCoreDataWindow.xib \
  ORMInsertPalette.xib \
  ORMIssuesView.xib \
  ORMSearchNavigator.xib \
  ORMPopulationView.xib \
  ThirdParty/DMTabBar/LICENSE-DMTabBar.txt
