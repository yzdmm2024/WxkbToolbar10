// WXKBShared.h — tweak 与偏好面板共用的配置常量
// 注意：本文件只放 ASCII，中文只出现在各 .m 的 @"..." 里，
//       以免 Windows 本地交叉编译链路丢字。
// 偏好键直接定义为 ObjC 字面量，避免 @宏 的解析歧义。
#ifndef WXKB_SHARED_H
#define WXKB_SHARED_H

// C 字符串版本（仅用于 CFSTR / 文件路径）
#define WXKB_PREFS_DOMAIN_C "com.yzdmm.wxkbtoolbar10"
#define WXKB_CHANGED_NOTIFICATION_C "com.yzdmm.wxkbtoolbar10/changed"

// NSString 版本
#define WXKB_PREFS_DOMAIN @"com.yzdmm.wxkbtoolbar10"

// 偏好键
#define WXKB_KEY_ENABLED       @"enabled"
#define WXKB_KEY_FUNCLIST      @"funcList"
#define WXKB_KEY_BG_ENABLED    @"bgEnabled"
#define WXKB_KEY_BG_MODE       @"bgMode"        // 1=纯色  2=图片
#define WXKB_KEY_BG_COLOR      @"bgColor"       // #RRGGBB
#define WXKB_KEY_BG_IMAGE      @"bgImage"       // 绝对路径
#define WXKB_KEY_BG_ALPHA      @"bgAlpha"       // 0.05 ~ 1.0
#define WXKB_KEY_KEY_ENABLED   @"keyColorEnabled"
#define WXKB_KEY_KEY_LETTERBG  @"keyLetterBg"
#define WXKB_KEY_KEY_FUNCBG    @"keyFuncBg"
#define WXKB_KEY_KEY_TEXT      @"keyTextColor"
#define WXKB_KEY_KEY_HIGHLIGHT @"keyHighlightColor"

// 工具栏功能 id（tag）。顺序即偏好面板中的展示顺序。
static const int kWXKBFuncCodes[] = {
    1, 2, 3, 5, 16, 17, 18, 20, 27, 28, 31, 14, 29, 32, 33, 35, 36
};
#define kWXKBFuncCount ((int)(sizeof(kWXKBFuncCodes) / sizeof(kWXKBFuncCodes[0])))

// 键盘扩展内确认可用、默认启用的功能；其余默认关闭，避免「点了没反应」。
static const int kWXKBFuncDefaultOn[] = {1, 2, 3, 5, 16, 17, 18, 20, 27, 28, 31};
#define kWXKBFuncDefaultOnCount ((int)(sizeof(kWXKBFuncDefaultOn) / sizeof(kWXKBFuncDefaultOn[0])))

#endif