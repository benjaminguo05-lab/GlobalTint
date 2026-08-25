ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

THEOS_PACKAGE_SCHEME = roothide
DEB_ARCH = iphoneos-arm64e

include $(THEOS)/makefiles/common.mk

# GlobalTintLoader:
# Broadly matched by MobileLoader, but it is intentionally pure C and contains
# no UIKit/Logos code. It refuses SpringBoard and non-.app processes before
# explicitly loading the core.
#
# GlobalTintCore:
# Contains the proven V0.3.5 UIKit implementation. Its own substrate filter is
# intentionally impossible so MobileLoader never auto-loads it; the loader
# dlopens it only inside eligible full application processes.
TWEAK_NAME = GlobalTintLoader GlobalTintCore

GlobalTintLoader_FILES = Loader.c
GlobalTintLoader_CFLAGS = -fvisibility=hidden

GlobalTintCore_FILES = Tweak.xm
GlobalTintCore_FRAMEWORKS = UIKit
GlobalTintCore_LIBRARIES = roothide
GlobalTintCore_CFLAGS = -fobjc-arc
GlobalTintCore_CCFLAGS = -std=c++17

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += globaltintprefs

include $(THEOS_MAKE_PATH)/aggregate.mk
