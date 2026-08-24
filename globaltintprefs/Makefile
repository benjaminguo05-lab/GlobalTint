ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GlobalTintPrefs

GlobalTintPrefs_FILES = GTListController.m
GlobalTintPrefs_FRAMEWORKS = UIKit
GlobalTintPrefs_PRIVATE_FRAMEWORKS = Preferences
GlobalTintPrefs_EXTRA_FRAMEWORKS = Cephei
GlobalTintPrefs_INSTALL_PATH = /Library/PreferenceBundles
GlobalTintPrefs_CFLAGS = -fobjc-arc
GlobalTintPrefs_CCFLAGS = -std=c++17

include $(THEOS_MAKE_PATH)/bundle.mk
