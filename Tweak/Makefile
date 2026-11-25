# GIF Stash Button: Theos build (macOS + roothide/theos fork, see .github/workflows/tweak.yml)
#
# Loads into SpringBoard and system apps, which are arm64e processes: build on macOS with Xcode's clang, which
# tags the arm64e slice with the versioned ptrauth ABI (0x80000002). CI refuses to package anything else
# (verify_arm64e.py). App Store apps load the arm64 slice.
THEOS_PACKAGE_SCHEME ?= roothide
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GifStashKey

GifStashKey_FILES = Tweak.m GifStashKeyMirror.m GifStashKeyDock.m GifStashKeyPanel.m GifStashKeyDebug.m
GifStashKey_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable
GifStashKey_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation CoreMedia ImageIO

include $(THEOS_MAKE_PATH)/tweak.mk
