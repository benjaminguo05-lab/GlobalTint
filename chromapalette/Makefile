TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME := roothide
FINALPACKAGE := 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := ChromaApps ChromaSystem
ChromaApps_FILES := src/Apps.mm src/Runtime.mm src/Components.mm src/Accent.mm src/Private.mm shared/Config.m shared/Schema.m
ChromaApps_CFLAGS := -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Ishared -Isrc
ChromaApps_CCFLAGS := -std=c++17
ChromaApps_FRAMEWORKS := UIKit Foundation CoreFoundation QuartzCore
ChromaApps_LIBRARIES := substrate roothide

ChromaSystem_FILES := src/System.mm src/Runtime.mm src/Private.mm shared/Config.m shared/Schema.m
ChromaSystem_CFLAGS := -fobjc-arc -Wall -Wextra -Wno-unused-parameter -Ishared -Isrc
ChromaSystem_CCFLAGS := -std=c++17
ChromaSystem_FRAMEWORKS := UIKit Foundation CoreFoundation QuartzCore
ChromaSystem_LIBRARIES := substrate roothide

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS := prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
