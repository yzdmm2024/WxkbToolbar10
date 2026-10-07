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

#pragma mark - 偏好键

#define WXKB_KEY_ENABLED       @"enabled"
#define WXKB_KEY_FUNCLIST      @"funcList"

// 背景
#define WXKB_KEY_BG_ENABLED    @"bgEnabled"
#define WXKB_KEY_BG_MODE       @"bgMode"        // 1=纯色  2=图片
#define WXKB_KEY_BG_COLOR      @"bgColor"       // #RRGGBB 或 #RRGGBBAA
#define WXKB_KEY_BG_IMAGE      @"bgImage"       // 高级：绝对路径
#define WXKB_KEY_BG_IMAGE_DATA @"bgImageData"   // 相册选图后裁剪好的 PNG/JPEG 数据
#define WXKB_KEY_BG_ALPHA      @"bgAlpha"       // 0.05 ~ 1.0

// 整键盘透明：把键盘自身所有不透明背景层清掉，透出后面的内容。
// 按键本身（含按键文字色）不受影响。
#define WXKB_KEY_TRANSPARENT   @"keyboardTransparent"

// 按键配色总开关
#define WXKB_KEY_KEY_ENABLED   @"keyColorEnabled"

// 四色分组底色
#define WXKB_KEY_LETTER_BG     @"keyLetterBg"     // 字母键
#define WXKB_KEY_FUNC_L_BG     @"keyFuncLeftBg"   // 左侧功能键（大小写/数字/符号…）
#define WXKB_KEY_FUNC_R_BG     @"keyFuncRightBg"  // 右侧功能键（删除/中英/发送…）
#define WXKB_KEY_SPACE_BG      @"keySpaceBg"      // 空格键
#define WXKB_KEY_KEY_TEXT      @"keyTextColor"    // 按键文字色
#define WXKB_KEY_KEY_HIGHLIGHT @"keyHighlightColor" // 按下高亮色

// 26 字母渐变
#define WXKB_KEY_GRAD_ENABLED  @"letterGradientEnabled"
#define WXKB_KEY_GRAD_FROM     @"letterGradientFrom"
#define WXKB_KEY_GRAD_TO       @"letterGradientTo"

// 26 字母逐个上色：NSDictionary { "0".."25" -> "#RRGGBB" }
#define WXKB_KEY_LETTER_MAP    @"letterColorMap"

// 按键圆角（pt，0 ~ 22）
#define WXKB_KEY_CORNER        @"keyCornerRadius"

// 编辑增强按钮（渲染在宿主 App 的键盘底栏一带）
#define WXKB_KEY_ACTION_ORDER  @"actionOrder"    // NSNumber 数组，用户排序后的顺序
#define WXKB_KEY_ACTION_SHOW   @"actionShow"     // NSDictionary { code(NSNumber) -> BOOL(NSNumber) }

#pragma mark - 默认值

#define WXKB_DEF_LETTER_BG     @"#FFFFFF"
#define WXKB_DEF_FUNC_L_BG     @"#A8A8A8"
#define WXKB_DEF_FUNC_R_BG     @"#A8A8A8"
#define WXKB_DEF_SPACE_BG      @"#FFFFFF"
#define WXKB_DEF_TEXT          @"#000000"
#define WXKB_DEF_HIGHLIGHT     @"#D9D9D9"
#define WXKB_DEF_GRAD_FROM     @"#5AC8FA"
#define WXKB_DEF_GRAD_TO       @"#AF52DE"

// 键盘背景裁剪比例（微信键盘：宽 390pt / 高约 260pt）
#define WXKB_KB_ASPECT_W       390.0
#define WXKB_KB_ASPECT_H       260.0

#pragma mark - 微信原生工具栏功能 id（tag）

// 键盘扩展内确认可用
static const int kWXKBFuncWorksInKb[] = {1, 2, 3, 5, 16, 17, 18, 20, 27, 28, 31};
#define kWXKBFuncWorksInKbCount ((int)(sizeof(kWXKBFuncWorksInKb) / sizeof(kWXKBFuncWorksInKb[0])))

// 点了没反应：需要微信主 App 才能处理，键盘扩展里必然无响应
static const int kWXKBFuncNeedsHostApp[] = {14, 29, 32, 33, 35, 36};
#define kWXKBFuncNeedsHostAppCount ((int)(sizeof(kWXKBFuncNeedsHostApp) / sizeof(kWXKBFuncNeedsHostApp[0])))

// 面板里展示的全部条目 = 可用 + 需主 App
#define kWXKBFuncAllCount (kWXKBFuncWorksInKbCount + kWXKBFuncNeedsHostAppCount)

#pragma mark - 编辑增强按钮 id

#define WXKB_ACT_SELECT_ALL    1   // 全选
#define WXKB_ACT_CUT           2   // 剪切
#define WXKB_ACT_PASTE         3   // 粘贴
#define WXKB_ACT_CURSOR_LEFT   4   // 光标左移
#define WXKB_ACT_CURSOR_RIGHT  5   // 光标右移
#define WXKB_ACT_DELETE_ALL    6   // 全删（清空整个输入框）
#define WXKB_ACT_CLIPBOARD     7   // 剪贴板历史
#define WXKB_ACT_PHRASES       8   // 快捷短语
#define WXKB_ACT_DISMISS       9   // 收起键盘
#define WXKB_ACT_GLOBE         10  // 切换输入法

// 面板展示顺序（同时是默认全开的顺序）
static const int kWXKBActionCodes[] = {
    WXKB_ACT_CURSOR_LEFT, WXKB_ACT_CURSOR_RIGHT,
    WXKB_ACT_SELECT_ALL, WXKB_ACT_CUT, WXKB_ACT_PASTE,
    WXKB_ACT_DELETE_ALL, WXKB_ACT_CLIPBOARD, WXKB_ACT_PHRASES,
    WXKB_ACT_DISMISS, WXKB_ACT_GLOBE
};
#define kWXKBActionCount ((int)(sizeof(kWXKBActionCodes) / sizeof(kWXKBActionCodes[0])))

#endif