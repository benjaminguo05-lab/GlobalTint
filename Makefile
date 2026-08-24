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
# Cephei's generated Swift compatibility header uses C++11+ aliases.
# Theos applies per-instance CCFLAGS to Logos Objective-C++ (.xm -> .mm) builds.
GlobalTint_CCFLAGS = -std=c++17

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += globaltintprefs

include $(THEOS_MAKE_PATH)/aggregate.mk
