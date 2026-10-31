
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SystemFPSPrefs

SystemFPSPrefs_FILES = SystemFPSRootListController.m

SystemFPSPrefs_FRAMEWORKS = UIKit
SystemFPSPrefs_PRIVATE_FRAMEWORKS = Preferences

SystemFPSPrefs_INSTALL_PATH = /Library/PreferenceBundles

# Explicitly package preference resources
SystemFPSPrefs_RESOURCE_FILES = Resources/Root.plist

# Use the custom bundle Info.plist
SystemFPSPrefs_INFO_PLIST = Resources/Info.plist

SystemFPSPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
