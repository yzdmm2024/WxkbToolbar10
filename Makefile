// WxkbToolbar10 — 微信输入法键盘扩展增强
//   tweak  ：工具栏功能自定义（排序/显隐）+ 编辑增强按钮 + 键盘背景 +
//            整键盘透明 + 按键配色 + 按键圆角
//   Host   ：注入普通 App，执行全选/剪切/粘贴/全删等需要 firstResponder 的动作
//   bundle ：设置面板（PreferenceLoader）
// rootless（ElleKit / TweakInject），注入目标 com.tencent.wetype.keyboard (wxkb_plugin)
TARGET := iphone:clang:14.5:14.0
# 必须双架构：键盘扩展是 arm64 进程（微信 App 二进制），而「设置」是系统 App，
# 进程为 arm64e —— 纯 arm64 的 preference bundle 在 arm64e 进程里 dlopen 会被
# dyld 拒绝，表现为「未能载入软件包，因为它已损坏或丢失必要的资源」。
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WxkbToolbar10
WxkbToolbar10_FILES = src/Tweak.xm
WxkbToolbar10_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w
WxkbToolbar10_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

# ---- 宿主 App 侧：执行需要 UIResponder 的编辑动作 ----
TWEAK_NAME = WxkbToolbar10Host
WxkbToolbar10Host_FILES = src/Host.xm
WxkbToolbar10Host_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w
WxkbToolbar10Host_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = WxkbToolbar10Prefs
WxkbToolbar10Prefs_FILES = \
	prefs/WXKBCommon.m \
	prefs/WxkbToolbar10PrefsRootListController.m \
	prefs/WXKBFuncListController.m \
	prefs/WXKBActionListController.m \
	prefs/WXKBPickerControllers.m \
	prefs/WXKBLetterColors.m \
	prefs/WXKBPhotoPicker.m
WxkbToolbar10Prefs_BUNDLE_RESOURCE_DIRS = prefs/Resources
WxkbToolbar10Prefs_INSTALL_PATH = /Library/PreferenceBundles
WxkbToolbar10Prefs_FRAMEWORKS = UIKit Foundation PhotosUI
WxkbToolbar10Prefs_PRIVATE_FRAMEWORKS = Preferences
WxkbToolbar10Prefs_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -w

include $(THEOS_MAKE_PATH)/bundle.mk