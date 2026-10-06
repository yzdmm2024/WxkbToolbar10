# WxkbToolbar10 — 微信输入法键盘扩展增强
#   tweak  ：工具栏功能自定义（排序/显隐）+ 键盘背景 + 按键配色
#   bundle ：设置面板（PreferenceLoader）
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

BUNDLE_NAME = WxkbToolbar10Prefs
WxkbToolbar10Prefs_FILES = \
	prefs/WXKBCommon.m \
	prefs/WxkbToolbar10PrefsRootListController.m \
	prefs/WXKBFuncListController.m \
	prefs/WXKBPickerControllers.m
WxkbToolbar10Prefs_BUNDLE_RESOURCE_DIRS = prefs/Resources
WxkbToolbar10Prefs_INSTALL_PATH = /Library/PreferenceBundles
WxkbToolbar10Prefs_FRAMEWORKS = UIKit Foundation
WxkbToolbar10Prefs_PRIVATE_FRAMEWORKS = Preferences
WxkbToolbar10Prefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w

include $(THEOS_MAKE_PATH)/bundle.mk