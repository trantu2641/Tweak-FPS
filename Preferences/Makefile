
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SystemFPSPrefs

SystemFPSPrefs_FILES = SystemFPSRootListController.m

SystemFPSPrefs_FRAMEWORKS = UIKit
SystemFPSPrefs_PRIVATE_FRAMEWORKS = Preferences

SystemFPSPrefs_INSTALL_PATH = /Library/PreferenceBundles

# Copy all files inside Resources into the bundle
SystemFPSPrefs_RESOURCE_DIRS = Resources

SystemFPSPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
