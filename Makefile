ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

THEOS_PACKAGE_SCHEME = roothide
DEB_ARCH = iphoneos-arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GlobalTint

GlobalTint_FILES = Tweak.xm
GlobalTint_FRAMEWORKS = UIKit
GlobalTint_EXTRA_FRAMEWORKS = Cephei
GlobalTint_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += globaltintprefs

include $(THEOS_MAKE_PATH)/aggregate.mk
