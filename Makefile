
TARGET := iphone:clang:16.5:15.0

ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SystemFPS

SystemFPS_FILES = Tweak.xm
SystemFPS_FRAMEWORKS = UIKit QuartzCore
SystemFPS_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += Preferences

include $(THEOS_MAKE_PATH)/aggregate.mk
