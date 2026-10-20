TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Spotify
ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SpicyLyricsiOS
SpicyLyricsiOS_FILES = Tweak.x $(wildcard Sources/*.m) $(wildcard Sources/*.c)
SpicyLyricsiOS_CFLAGS = -fobjc-arc -ISources -Wno-deprecated-declarations
SpicyLyricsiOS_FRAMEWORKS = UIKit MediaPlayer QuartzCore CoreImage

include $(THEOS_MAKE_PATH)/tweak.mk
