# WxkbToolbar10 — 微信输入法键盘扩展增强
#   tweak  ：工具栏功能自定义（排序/显隐）+ 键盘背景 +
#            整键盘透明 + 按键配色 + 按键圆角
#   bundle ：设置面板（PreferenceLoader）
# rootless（ElleKit / TweakInject），注入目标 com.tencent.wetype.keyboard (wxkb_plugin)
TARGET := iphone:clang:14.5:14.0
# 必须双架构：键盘扩展是 arm64 进程（微信 App 二进制），而「设置」是系统 App，
# 进程为 arm64e —— 纯 arm64 的 preference bundle 在 arm64e 进程里 dlopen 会被
# dyld 拒绝，表现为「未能载入软件包，因为它已损坏或丢失必要的资源」。
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WxkbToolbar10
WxkbToolbar10_FILES = src/Tweak.xm \
	license_kit/src/lk_alg.c \
	license_kit/src/lk_core.c \
	license_kit/src/lk_issue.c \
	license_kit/src/lk_master.c \
	license_kit/src/lk_obf.c \
	license_kit/src/lk_sha256.c \
	license_kit/ios_glue/lk_master_ios.m \
	src/lk_env_ios.m
WxkbToolbar10_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w -Ilicense_kit/include -DLK_MASTER_UNLOCK=1 -DLK_SELFHASH_REQUIRED=0
WxkbToolbar10_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = WxkbToolbar10Prefs
WxkbToolbar10Prefs_FILES = \
	prefs/WXKBCommon.m \
	prefs/WXKBInlineGridCell.m \
	prefs/WxkbToolbar10PrefsRootListController.m \
	prefs/WXKBPickerControllers.m \
	prefs/WXKBLetterColors.m \
	prefs/WXKBPhotoPicker.m \
	prefs/WXKBPreviewKeyboardView.m \
	prefs/WXKBThemeProfile.m \
	prefs/WXKBThemeProfilesController.m \
	prefs/WXKBPreviewKeyboardView.m \
	prefs/WXKBThemeProfile.m \
	prefs/WXKBThemeProfilesController.m \
	license_kit/src/lk_alg.c \
	license_kit/src/lk_core.c \
	license_kit/src/lk_issue.c \
	license_kit/src/lk_master.c \
	license_kit/src/lk_obf.c \
	license_kit/src/lk_sha256.c \
	license_kit/ios_glue/lk_master_ios.m \
	src/lk_env_ios.m
WxkbToolbar10Prefs_BUNDLE_RESOURCE_DIRS = prefs/Resources
WxkbToolbar10Prefs_INSTALL_PATH = /Library/PreferenceBundles
WxkbToolbar10Prefs_FRAMEWORKS = UIKit Foundation PhotosUI
WxkbToolbar10Prefs_PRIVATE_FRAMEWORKS = Preferences
WxkbToolbar10Prefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w -Ilicense_kit/include -DLK_MASTER_UNLOCK=1 -DLK_SELFHASH_REQUIRED=0

include $(THEOS_MAKE_PATH)/bundle.mk