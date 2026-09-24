include $(THEOS)/makefiles/common.mk
BUNDLE_NAME := ChromaPrefs
ChromaPrefs_FILES := Prefs.m ../shared/Config.m ../shared/Schema.m
ChromaPrefs_RESOURCE_FILES := Info.plist Spectrum.png
ChromaPrefs_CFLAGS := -fobjc-arc -Wall -Wextra -Wno-unused-parameter -I../shared
ChromaPrefs_FRAMEWORKS := UIKit Foundation CoreFoundation QuartzCore
# Public Xcode SDKs omit Preferences. Link only the host class we subclass.
ChromaPrefs_LDFLAGS := $(abspath Preferences.tbd)
ChromaPrefs_LIBRARIES := roothide
ChromaPrefs_INSTALL_PATH := /Library/PreferenceBundles
include $(THEOS_MAKE_PATH)/bundle.mk
