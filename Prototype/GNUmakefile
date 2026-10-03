include $(GNUSTEP_MAKEFILES)/common.make

APP_NAME = NativeUML

NativeUML_OBJC_FILES = \
	main.m \
	NUModel.m \
	NUDiagramView.m \
	NUAppDelegate.m

NativeUML_HEADERS = \
	NUModel.h \
	NUDiagramView.h \
	NUAppDelegate.h

NativeUML_OBJCFLAGS += -fobjc-arc -fobjc-runtime=gnustep-2.0 -Wall
NativeUML_MAIN_MODEL_FILE =

include $(GNUSTEP_MAKEFILES)/application.make
