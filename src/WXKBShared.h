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

// 背景
#define WXKB_KEY_BG_ENABLED    @"bgEnabled"
#define WXKB_KEY_BG_MODE       @"bgMode"        // 1=纯色  2=图片
#define WXKB_KEY_BG_COLOR      @"bgColor"       // #RRGGBB 或 #RRGGBBAA
#define WXKB_KEY_BG_IMAGE      @"bgImage"       // 高级：绝对路径（浅色）
#define WXKB_KEY_BG_IMAGE_DATA @"bgImageData"   // 浅色模式背景图数据
#define WXKB_KEY_BG_ALPHA      @"bgAlpha"       // 0.05 ~ 1.0

// 整键盘透明：把键盘自身所有不透明背景层清掉，透出后面的内容。
// 按键本身（含按键文字色）不受影响。
#define WXKB_KEY_TRANSPARENT   @"keyboardTransparent"

// 按键配色总开关
#define WXKB_KEY_KEY_ENABLED   @"keyColorEnabled"

// 四色分组底色
#define WXKB_KEY_LETTER_BG     @"keyLetterBg"     // 字母键
#define WXKB_KEY_DIGIT_BG      @"keyDigitBg"      // 数字/符号键（数字·符号面板中间的主键）
#define WXKB_KEY_FUNC_L_BG     @"keyFuncLeftBg"   // 左侧功能键（大小写/数字/符号…）
#define WXKB_KEY_FUNC_R_BG     @"keyFuncRightBg"  // 右侧功能键（删除/中英/发送…）
#define WXKB_KEY_SPACE_BG      @"keySpaceBg"      // 空格键
#define WXKB_KEY_KEY_TEXT      @"keyTextColor"    // 浅色模式按键文字色
#define WXKB_KEY_KEY_TEXT_DARK @"keyTextColorDark" // 深色模式按键文字色
#define WXKB_KEY_KEY_HIGHLIGHT @"keyHighlightColor" // 浅色模式按下高亮色
#define WXKB_KEY_KEY_HIGHLIGHT_DARK @"keyHighlightColorDark" // 深色模式按下高亮色

// 26 字母渐变
#define WXKB_KEY_GRAD_ENABLED  @"letterGradientEnabled"
#define WXKB_KEY_GRAD_FROM     @"letterGradientFrom"
#define WXKB_KEY_GRAD_TO       @"letterGradientTo"

// 26 字母逐个上色：NSDictionary { "0".."25" -> "#RRGGBB" }
#define WXKB_KEY_LETTER_MAP    @"letterColorMap"

// 按键圆角（pt，0 ~ 22）—— 仅在「按键形状 = 默认圆角」时生效
#define WXKB_KEY_CORNER        @"keyCornerRadius"

// 按键形状：0 默认圆角（由 keyCornerRadius 决定）/ 1 圆形 / 2 六边形 / 3 水珠
#define WXKB_KEY_SHAPE         @"keyShape"

// 内置皮肤：开启后把 A→Z 字母键与功能键渲染成真实「彩虹按键」键帽
//（百度输入法导出的真·键帽 PNG），关闭则恢复普通按键配色。
// 这是对旧版「彩虹键盘（程序生成 A→Z 色）」的替代。
#define WXKB_KEY_SKIN_ENABLED  @"skinEnabled"

// 皮肤名：当前仅内置 "rainbow" = 百度「彩虹按键」；保留扩展位。
#define WXKB_KEY_SKIN_NAME     @"skinName"

// 皮肤资源在设备上的目录（tweak 从 jbroot 读取）
#define WXKB_SKIN_DIR          @"/Library/Application Support/WxkbToolbar10/skins"

// 立体键帽：在按键背后垫一层向下的深色「侧壁」，模拟电脑键盘 3D 键帽（纯视觉，不动布局）
#define WXKB_KEY_KEYCAP3D      @"keyCap3D"

// 彩虹键盘帽（1.9.0）：浅灰白裙边 + 柔和阴影 + 圆润穹顶的凸起键帽。
#define WXKB_KEY_CAPRAINBOW    @"keyCapRainbow"

// 马卡龙浮雕键帽（2.0.0）：全彩键面（无裙边无描边）+ 顶部提亮 + 底部同色系
// 收边唇 + 柔和投影 + 深炭灰字母 + 键面下层小字（Q→1、A→! …）。
// 开启皮肤时三个键帽开关都没开 → 默认按此风格渲染（图2 原版观感）。
#define WXKB_KEY_CAPMACARON    @"keyCapMacaron"

// 彩虹3D键帽（2.1.0）：粉彩键面 + 明显3D深度 + 柔和渐变 + 极淡描边。
// 百度「彩虹按键」同款风格，每个键不同粉彩色，立体感强。
#define WXKB_KEY_CAPRAINBOW3D  @"keyCapRainbow3D"

// 键盘整体上下位移（pt，-80 ~ +80，正值 = 下移）
#define WXKB_KEY_OFFSET        @"kbOffset"

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