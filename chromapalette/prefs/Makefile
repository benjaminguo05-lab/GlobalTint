include $(THEOS)/makefiles/common.mk
BUNDLE_NAME := ChromaPrefs
ChromaPrefs_FILES := Prefs.m ../shared/Config.m ../shared/Schema.m
ChromaPrefs_RESOURCE_FILES := Info.plist
ChromaPrefs_CFLAGS := -fobjc-arc -Wall -Wextra -Wno-unused-parameter -I../shared
ChromaPrefs_FRAMEWORKS := UIKit Foundation CoreFoundation QuartzCore
ChromaPrefs_PRIVATE_FRAMEWORKS := Preferences
ChromaPrefs_LIBRARIES := roothide
ChromaPrefs_INSTALL_PATH := /Library/PreferenceBundles
include $(THEOS_MAKE_PATH)/bundle.mk
