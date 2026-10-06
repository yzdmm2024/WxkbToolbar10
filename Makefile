# WxkbToolbar10 — 微信输入法键盘扩展工具栏：纳入「定制工具栏」全部功能 + 原生尺寸横向滑动
# rootless（ElleKit / TweakInject），注入目标 com.tencent.wetype.keyboard (wxkb_plugin)
TARGET := iphone:clang:14.5:14.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WxkbToolbar10
WxkbToolbar10_FILES = src/Tweak.xm
WxkbToolbar10_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w
WxkbToolbar10_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk