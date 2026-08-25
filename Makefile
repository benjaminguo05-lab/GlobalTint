ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

THEOS_PACKAGE_SCHEME = roothide
DEB_ARCH = iphoneos-arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GlobalTint

GlobalTint_FILES = Tweak.xm
GlobalTint_FRAMEWORKS = UIKit
GlobalTint_LIBRARIES = roothide
GlobalTint_CFLAGS = -fobjc-arc
GlobalTint_CCFLAGS = -std=c++17

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += globaltintprefs

include $(THEOS_MAKE_PATH)/aggregate.mk
