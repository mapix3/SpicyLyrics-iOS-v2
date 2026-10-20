TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Spotify
ARCHS = arm64 arm64e

# rootless по умолчанию (Dopamine, palera1n rootless). Для rootful: make package THEOS_PACKAGE_SCHEME=
THEOS_PACKAGE_SCHEME ?= rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SpicyLyricsiOS
SpicyLyricsiOS_FILES = Tweak.x $(wildcard Sources/*.m)
SpicyLyricsiOS_CFLAGS = -fobjc-arc -ISources -Wno-deprecated-declarations
SpicyLyricsiOS_FRAMEWORKS = UIKit MediaPlayer QuartzCore CoreImage

include $(THEOS_MAKE_PATH)/tweak.mk
