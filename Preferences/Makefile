
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SystemFPSPrefs

SystemFPSPrefs_FILES = SystemFPSRootListController.m

SystemFPSPrefs_FRAMEWORKS = UIKit
SystemFPSPrefs_PRIVATE_FRAMEWORKS = Preferences

SystemFPSPrefs_INSTALL_PATH = /Library/PreferenceBundles

# Explicitly include both plist resources
SystemFPSPrefs_RESOURCE_FILES = \
    Resources/Info.plist \
    Resources/Root.plist

SystemFPSPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
