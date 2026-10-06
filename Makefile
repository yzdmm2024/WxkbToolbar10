# WxkbToolbar10 — 微信输入法键盘扩展工具栏：功能图标扩展至 10 个 + 自动缩小铺满
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