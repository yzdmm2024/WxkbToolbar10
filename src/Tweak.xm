// WxkbToolbar10 — 微信输入法键盘扩展增强
// 目标：iPhone 12 Pro / iOS 16.6 / Relaxin rootless (ElleKit TweakInject)
// 注入目标：com.tencent.wetype.keyboard (wxkb_plugin.appex)
//
// 1.6.7 行为（用户实测 1.6.6 截图：按钮与原生图标重叠 + 6 个宿主动作没反应）：
//   1) 按钮回归「左滑」原始设计：废弃常驻覆盖条，把按钮接回原生 WBFunctionToolBar
//      滚动容器队尾（原生图标在前、往左滑才看到我们的），每次原生刷新后自动补挂
//      + 重新定位 + 扩 contentSize（根治「点一下就没了」）；
//   2) 宿主动作全死的真根因（读 ElleKit injector.c 源码确认）：Executables 过滤是
//      strcmp 精确匹配，"*" 匹配不到任何进程 → Host dylib 从未被注入。且 ElleKit
//      无 Exclude 键、无 plist 也不注入。改 WxkbToolbar10Host.plist 为
//      Classes=["UIWindow"]（任何带界面的进程必命中），Host %ctor 运行时排除
//      SpringBoard 与键盘扩展自身。这就是「只有左右光标/全删/切换输入法（本地动作）
//      有效、全选/剪切/粘贴/剪贴板/短语/收起（宿主动作）全没反应」的原因；
//   3) 下移明确为整体刚性平移（用户要求，绝不压缩尺寸），上限=底部安全区（刚好
//      填满键盘下方空当贴到屏幕底；屏幕底边以下的部分物理上无法显示）。
//
// 1.6.3 行为（frida 真机诊断后的三处根治）：
//   1) 总根因：键盘扩展沙盒读不到全局偏好 —— NSUserDefaults persistentDomain
//      与 CFPreferences 在 wxkb_plugin 里全返回 null，导致 1.5.x 以来
//      圆角/透明/背景/位移/功能排序/按钮排序在键盘进程里全部用内置默认值。
//      修复：从自身 dylib 路径反推 jbroot，直接读
//      <jbroot>/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.plist
//      （frida 实测该路径可读且键值齐全）。
//   2) 按钮条与「收起键盘」chevron 重叠：chevron 固定在 bar 上不随滚动
//      （frida 实测占 bar 坐标 298~332 / 宽 344）。现在动态预留右侧固定区，
//      滚到头时按钮条右缘正好停在 chevron 左边。
//   3) 按钮点按双保险：sv 级手势（1.6.2）+ strip 级手势（新增，命中优先级
//      更高）+ 恢复 addTarget（1.6.2 移除）。三路任一通即可触发，动作幂等。
// 1.6.4 行为（针对「上移/下移与增强按钮都没反应」）：
//   1) 总根因之二：键盘扩展进程里没有「window.rootViewController 是
//      UIInputViewController」这种结构（frida 实测 UIInputViewController count==0），
//      所以 WXKBInputController() 一直返回 nil —— 光标左右 / 切换输入法 / 全删
//      全得绕到宿主 App，而宿主又没实现「光标左右」，于是这两个按钮彻底无反应；
//      位移也找不到正确的目标视图。修复：沿 WBRootInputView 的 nextResponder 链
//      上行到真正的输入控制器（它就是键盘扩展的主 UIInputViewController）。
//   2) 位移真正生效：1.6.3 把位移作用在内部 WBRootInputView 上，被它的容器裁掉，
//      所以「没效果」。现在作用在输入控制器.view（视图树顶点，无裁剪容器），
//      整块键盘才会跟着上下移动。
//   3) 宿主 bridge 补上「光标左右」两个动作，键盘扩展取不到 textDocumentProxy 时
//      也能在宿主侧移动光标，双保险。
// 1.6.5 行为（针对「10 个按钮点一下就没了 / 下移裁切 / 宿主动作仍点不了」）：
//   1) 增强按钮条彻底重写：不再把 UIButton 塞进微信原生滚动工具栏（原生刷新/滚动
//      会把条子移走并吞触摸，导致「按一下就没了」且点击到不了动作派发）。改为我们自己、
//      完全受控的常驻子视图，挂在键盘根视图 WBRootInputView 顶部：深色半透明底 + 白色
//      图标，UIButton 的 addTarget 直接生效，不再依赖手势命中。WBFunctionToolBar 里
//      所有 WXKBEnsureActionBar(self) 调用与旧 hitTest 兜底一并移除，避免在原工具栏上
//      误建第二个按钮条。
//   2) 下移裁切修复：位移作用在输入控制器.view（键盘树顶点），当偏移为正（下移）且超过
//      安全区/30pt 上限时截断，避免整块键盘被屏幕底部裁掉留空。
//   3) 宿主注入根因修复（WxkbToolbar10Host.plist）：原 plist 把 Exclude 放在顶层且缺
//      少 Filter，导致 Host dylib 从未注入任何 App，于是「剪切/粘贴/快捷短语/收起键盘/
//      粘贴历史」等需宿主执行的动作从 1.0 起全死。已改为 Filter{Executables:["*"],
//      Exclude:{Bundles:[SpringBoard,Preferences], Executables:[wxkb_plugin]}}。
// 1.6.6 行为（用户实测 1.6.5 截图：仍有灰底 + 按钮重叠/换位）：
//   1) 灰底根治加码：1.6.5 只清微信子树 + 直系祖先链，但系统 backdrop 很可能是
//      WBRootInputView 的「兄弟视图」，直系链够不着。现在直接从键盘窗口整棵树清，
//      并按类名识别 _UIBackdropEffectView / UIKBBackdropView 等不走 backgroundColor
//      API 的私有 backdrop 直接隐藏（原值存关联对象，关透明时精确还原）。
//   2) 幽灵按钮条根治：微信会预加载屏外的下一套键盘布局，屏外根视图也会走到
//      WXKBEnsureActionBar，它的条正好露在可见键盘下方（截图底部那排按钮）。
//      现在屏外根不建条，且每次全窗只保留可见根这一根条，其余拆除。
//   3) 按钮条定位改为精确覆盖原生工具栏那一行：1.6.5 的「顶部一小条」被
//      WXKBClearBgTree 误清了深色底（白图标和原生图标叠影成一团乱像）。
//      现在 ClearBgTree 按 tag 跳过按钮条，条子精确盖住工具栏行、深色圆角底。
// 1.6.9 行为（用户实测 1.6.8 截图：按钮前一段空白 / 关掉的功能还显示一排圆圈图标）：
//   1) 空白根治：增强按钮原来被放在「视口宽度」之后（nx 兜底到 contentSize/视口宽），
//      原生图标被隐藏后按钮和 logo 之间隔一条大空白。改为紧跟原生内容 maxX 排布；
//      contentSize 同时往回收（旧版只扩不收，残留滑不到头的空白区）。
//   2) 「关了还显示」根治（frida 真机实锤）：手机上 funcList=(36,17,14,29,32,33,35,5)，
//      与截图 8 个圆圈图标一一对应 —— 「需微信主 App」组的功能码（文字整理/单手模式/
//      小程序/灵动表达/问AI/字体滤镜/排版成图）躺在清单里被原样放行绘制。它们在键盘
//      扩展进程里点了永远无反应，现在工具栏一律拦截不显示，面板同步改为「不会显示」
//      纯信息组、禁止加回、落盘时清理。
// 1.6.8 行为（用户实测 1.6.7 截图：下移后顶部露灰块 / 图标太大 / 点击后要滚回）：
//   1) 下移后顶部灰块：整体平移后，顶部露出的是键盘窗口/容器（UIInputView 等）
//      的背景色。位移非零时清祖先链背景（透明开启时窗口整树已由透明逻辑清理，
//      不重复）；位移归零时精确还原。
//   2) 增强按钮图标改小：pointSize 固定 17（与原生工具栏图标观感一致，不再跟随
//      容器高度放大），颜色不再用微信蓝色 tint，改为跟随深浅模式的深灰黑/白。
//   3) 点击增强按钮后，原生工具栏滚动条自动动画滚回最左（回到原生功能区）。
// 1.6.2 行为：
//   1) 编辑增强按钮点不了二次修复：弃用脆弱的 addTarget + hitTest 方案，改为在
//      原生滚动视图上挂一个「只识别点按、不拦截触摸」的 UITapGestureRecognizer，
//      点在我们按钮范围内就直接触发动作，彻底绕开微信的触摸自管 / 手势拦截。
//   2) 键盘整体上移/下移：位移作用在最上层「输入视图控制器.view」上（系统决定的
//      位置，原生 layout 不会反复重置），并在异步同步里二次兜底，确保生效。
//   3) 未配置清单时改用白名单：只放行已知功能码，未知的（隔空投送/最近使用/
//      收起键盘/定制表情/拼写检查 等私有码）不再显示，符合「没有就不显示」。
//   4) 单手模式（17）仍在「需主 App（无反应）」分组。
//   1) 工具栏功能由「设置 → 微信输入法增强」面板决定：可排序、可隐藏、可增删。
//      「需主 App」的那几项单独分组并明确标注，避免点了没反应还不知道为什么。
//   2) 键盘背景：纯色 / 相册图片（按键盘比例横向裁剪，存 NSData）/ 高级路径，支持透明度。
//   3) 整键盘透明：递归清掉键盘所有原生不透明背景层，透出后面的内容；按键底色与
//      文字色保持不变（默认黑字）。
//   4) 按键配色：四组底色（字母 / 左侧功能 / 右侧功能 / 空格）+ 文字色 + 按下高亮色。
//   5) 字母键支持 A→Z 渐变，以及 26 个字母逐个单独上色。
//   6) 按键圆角可调（1.5.x 无效的根因已修：原生每次状态切换都会把圆角写回固定值，
//      现在改成「递归定位真正的背景视图 + 下一轮 runloop 补刀」，盖得住）。
//   7) 工具栏尾部新增「编辑增强」按钮：光标左右 / 全选 / 剪切 / 粘贴 / 全删 /
//      剪贴板历史 / 快捷短语 / 收起键盘 / 切换输入法。能在扩展内做的直接走
//      UITextDocumentProxy；需要宿主 App 响应的通过 Darwin 通知桥到
//      WxkbToolbar10Host（注入宿主 App 的那个 dylib）。
//   8) 保留 1.2.0 的布局修复：工具栏紧贴左侧 logo 铺满整行 + 原生尺寸横向滑动。
//
// 说明：原生布局把 WBFunctionToolBar 固定在 x=102 / 宽 288（WBTopBar 宽 390），
//       logo 右边界只有 46，于是 logo 与第一个图标之间空出约 68pt 且无法滑入。
//       这里在 WBTopBar 布局完成后把工具栏重定位到 logo 右边界并撑满剩余宽度。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import "WXKBShared.h"

#pragma mark - 私有类声明（实现由原 App 提供）

@interface WBFunctionToolBar : UIView
@end

@interface WBTopBar : UIView
@end

@interface WBKeyView : UIView
- (id)item;
@end

@interface WBRuleKeyView : WBKeyView
@end

@interface WBReturnKeyView : WBKeyView
@end

@interface WBRootInputView : UIView
@end

@interface WBMainInputView : UIView
@end

@interface WBKeyboardView : UIView
@end

@interface NSObject (WXKBKeyItem)
- (NSInteger)alphabetIndex;
- (NSString *)identifier;
@end

@interface NSObject (WXKBEditing)
- (BOOL)editing;
@end

// 前向声明：WXKBInputController 定义位置靠后，但多处（位移、按钮动作）提前用到。
static UIInputViewController *WXKBInputController(void);

#pragma mark - 配置

static BOOL      gEnabled      = YES;
static BOOL      gBgEnabled    = NO;
static int       gBgMode       = 1;      // 1 纯色 2 图片
static CGFloat   gBgAlpha      = 1.0;
static UIColor  *gBgColor      = nil;
static NSString *gBgImage      = nil;
static NSData   *gBgImageData  = nil;
static BOOL      gTransparent  = NO;
static BOOL      gKeyEnabled   = NO;
static UIColor  *gLetterBg     = nil;
static UIColor  *gDigitBg      = nil;    // 数字/符号键（数字·符号面板中间主键）
static UIColor  *gFuncLBg      = nil;
static UIColor  *gFuncRBg      = nil;
static UIColor  *gSpaceBg      = nil;
static UIColor  *gTextColor    = nil;
static UIColor  *gTextColorDark = nil;
static UIColor  *gHighlight    = nil;
static UIColor  *gHighlightDark = nil;
static BOOL      gGradEnabled  = NO;
static UIColor  *gGradFrom     = nil;
static UIColor  *gGradTo       = nil;
static NSDictionary *gLetterMap = nil;
static CGFloat   gCorner       = 0.0;
static int       gShape        = 0;      // 0 默认圆角 1 圆形 2 六边形 3 水珠
static BOOL      gSkinEnabled  = NO;     // 内置皮肤「彩虹按键」（百度）开关
static NSString *gSkinName     = nil;    // 皮肤名（当前固定 rainbow）
static BOOL      gCap3D        = NO;     // 立体键帽（电脑键盘风）
static double    gKbOffset     = 0.0;   // 键盘整体上下位移，正值下移
static double    gLastLoad     = -1;

static UIColor *WXKBColor(NSString *hex, CGFloat alpha) {
    if (![hex isKindOfClass:[NSString class]]) {
        return nil;
    }
    NSString *s = [hex stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"#"]) {
        s = [s substringFromIndex:1];
    }
    if (s.length != 6 && s.length != 8) {
        return nil;
    }
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:s] scanHexInt:&v]) {
        return nil;
    }
    CGFloat a = alpha;
    if (s.length == 8) {
        a = alpha * ((v & 0xFF) / 255.0);
        v >>= 8;
    }
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0
                           alpha:a];
}

// roothide 的 jbroot：从我们自己的 dylib 路径反推（…/.jbroot-XXXX/usr/lib/TweakInject/WxkbToolbar10.dylib）。
// 关键：键盘扩展沙盒会遮蔽 /var/mobile/...，但 jbroot 前缀的真实路径可读
// （frida 实测 wxkb_plugin 里读 <jbroot>/var/mobile/Library/Preferences/
//   com.yzdmm.wxkbtoolbar10.plist 成功，NSUserDefaults persistentDomain 反而全 null）。
// 这是 1.6.2 及以前「设置面板改什么键盘都没反应」的总根因。
static NSString *WXKBJbrootPath(NSString *rel) {
    static NSString *jb = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info;
        if (dladdr((const void *)&WXKBJbrootPath, &info) && info.dli_fname) {
            NSString *p = [NSString stringWithUTF8String:info.dli_fname];
            NSRange r = [p rangeOfString:@"/usr/lib/TweakInject"];
            if (r.location != NSNotFound) {
                jb = [p substringToIndex:r.location];
            }
        }
    });
    if (jb.length == 0) return nil;
    return [jb stringByAppendingString:rel];
}

// 键盘扩展是沙盒进程，读偏好要多种途径兜底。
static NSDictionary *WXKBLoadPrefs(void) {
    NSMutableArray *paths = [NSMutableArray array];
    NSString *j1 = WXKBJbrootPath(@"/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.plist");
    NSString *j2 = WXKBJbrootPath(@"/var/jb/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.plist");
    if (j1) [paths addObject:j1];
    if (j2) [paths addObject:j2];
    [paths addObjectsFromArray:@[
        @"/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.plist",
        @"/var/jb/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.plist",
    ]];
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if ([d isKindOfClass:[NSDictionary class]] && d.count > 0) {
            return d;
        }
    }

    const CFStringRef domain = CFSTR(WXKB_PREFS_DOMAIN_C);
    CFDictionaryRef raw = CFPreferencesCopyMultiple(
        NULL, domain, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost);
    if (!raw) {
        raw = CFPreferencesCopyMultiple(
            NULL, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    }
    if (!raw) {
        raw = CFPreferencesCopyMultiple(
            NULL, domain, kCFPreferencesAnyUser, kCFPreferencesAnyHost);
    }
    if (raw) {
        NSDictionary *d = CFBridgingRelease(raw);
        if (d.count > 0) {
            return d;
        }
    }

    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:WXKB_PREFS_DOMAIN];
    NSDictionary *d = [ud persistentDomainForName:WXKB_PREFS_DOMAIN];
    return ([d isKindOfClass:[NSDictionary class]] && d.count > 0) ? d : nil;
}

static void WXKBReload(BOOL force) {
    double now = CFAbsoluteTimeGetCurrent();
    if (!force && gLastLoad > 0 && now - gLastLoad < 2.0) {
        return;
    }
    gLastLoad = now;

    NSDictionary *d = WXKBLoadPrefs();
    if (!d) {
        return;   // 读不到就沿用当前值（首次为内置默认）
    }

    id v = d[WXKB_KEY_ENABLED];
    gEnabled = v ? [v boolValue] : YES;


    // ---- 背景 ----
    gBgEnabled = [d[WXKB_KEY_BG_ENABLED] boolValue];
    id bm = d[WXKB_KEY_BG_MODE];
    gBgMode = bm ? [bm intValue] : 1;
    id ba = d[WXKB_KEY_BG_ALPHA];
    gBgAlpha = ba ? [ba doubleValue] : 1.0;
    if (gBgAlpha < 0.05 || gBgAlpha > 1.0) {
        gBgAlpha = 1.0;
    }
    id img = d[WXKB_KEY_BG_IMAGE];
    gBgImage = [img isKindOfClass:[NSString class]] ? img : nil;
    id imgData = d[WXKB_KEY_BG_IMAGE_DATA];
    gBgImageData = [imgData isKindOfClass:[NSData class]] ? imgData : nil;

    gBgColor = WXKBColor(d[WXKB_KEY_BG_COLOR], gBgAlpha)
                   ?: [UIColor colorWithWhite:0.11 alpha:gBgAlpha];

    gTransparent = [d[WXKB_KEY_TRANSPARENT] boolValue];

    // ---- 按键配色 ----
    gKeyEnabled = [d[WXKB_KEY_KEY_ENABLED] boolValue];

    // 1.4.x 的单一「功能键底色」作为左右两组的兜底
    UIColor *legacyFunc = WXKBColor(d[@"keyFuncBg"], 1.0);

    gLetterBg = WXKBColor(d[WXKB_KEY_LETTER_BG], 1.0)
                    ?: [UIColor colorWithWhite:1.00 alpha:0.96];
    gDigitBg  = WXKBColor(d[WXKB_KEY_DIGIT_BG], 1.0);   // nil = 沿用左右功能键分组
    gFuncLBg  = WXKBColor(d[WXKB_KEY_FUNC_L_BG], 1.0) ?: legacyFunc
                    ?: [UIColor colorWithWhite:0.66 alpha:1.00];
    gFuncRBg  = WXKBColor(d[WXKB_KEY_FUNC_R_BG], 1.0) ?: legacyFunc
                    ?: [UIColor colorWithWhite:0.66 alpha:1.00];
    gSpaceBg  = WXKBColor(d[WXKB_KEY_SPACE_BG], 1.0)
                    ?: [UIColor colorWithWhite:1.00 alpha:0.96];
    gTextColor = WXKBColor(d[WXKB_KEY_KEY_TEXT], 1.0) ?: [UIColor blackColor];
    gHighlight = WXKBColor(d[WXKB_KEY_KEY_HIGHLIGHT], 1.0)
                     ?: [UIColor colorWithWhite:0.85 alpha:1.00];
    gTextColorDark = WXKBColor(d[WXKB_KEY_KEY_TEXT_DARK], 1.0);
    gHighlightDark = WXKBColor(d[WXKB_KEY_KEY_HIGHLIGHT_DARK], 1.0);

    // ---- 渐变 / 逐个 ----
    gGradEnabled = [d[WXKB_KEY_GRAD_ENABLED] boolValue];
    gGradFrom = WXKBColor(d[WXKB_KEY_GRAD_FROM], 1.0) ?: [UIColor colorWithRed:0.35 green:0.78 blue:0.98 alpha:1.0];
    gGradTo   = WXKBColor(d[WXKB_KEY_GRAD_TO], 1.0)   ?: [UIColor colorWithRed:0.69 green:0.32 blue:0.87 alpha:1.0];
    id lm = d[WXKB_KEY_LETTER_MAP];
    gLetterMap = [lm isKindOfClass:[NSDictionary class]] ? lm : nil;

    // ---- 圆角 ----
    id cr = d[WXKB_KEY_CORNER];
    gCorner = cr ? [cr doubleValue] : 0.0;
    if (gCorner < 0.0 || gCorner > 22.0) {
        gCorner = 0.0;
    }

    id sh = d[WXKB_KEY_SHAPE];
    int s = sh ? [sh intValue] : 0;
    if (s < 0 || s > 3) s = 0;
    gShape = s;

    gSkinEnabled = [d[WXKB_KEY_SKIN_ENABLED] boolValue];
    id sn = d[WXKB_KEY_SKIN_NAME];
    gSkinName = ([sn isKindOfClass:[NSString class]] && [sn length]) ? sn : @"rainbow";

    gCap3D = [d[WXKB_KEY_KEYCAP3D] boolValue];

    // ---- 键盘位置 ----
    id of2 = d[WXKB_KEY_OFFSET];
    gKbOffset = of2 ? [of2 doubleValue] : 0.0;
    if (gKbOffset < -80.0 || gKbOffset > 80.0) {
        gKbOffset = 0.0;
    }

}

#pragma mark - 全树重同步（圆角 / 透明的统一入口）

// 递归找出「真正画背景的那个视图」。
// 1.5.x 的 bug：只对 key.subviews 一层设 cornerRadius，而原生每次状态切换
// （highlighted / 主题刷新）都会在背景视图自己的 layout 里把圆角写回固定值，
// 于是用户的设置被无声覆盖。这里下探到真正带背景的叶子视图，并在下一轮
// runloop 再补一次，确保盖过原生最后一次写入。
static UIView *WXKBFindBgLeaf(UIView *v, NSInteger depth) {
    if (depth > 4 || v.subviews.count == 0) {
        return v;
    }
    for (UIView *s in v.subviews) {
        if ([s isKindOfClass:[UIImageView class]] ||
            [s isKindOfClass:[UILabel class]] ||
            [s isKindOfClass:[UIButton class]]) {
            continue;   // 图标 / 文字不是背景
        }
        UIView *leaf = WXKBFindBgLeaf(s, depth + 1);
        if (leaf) {
            return leaf;
        }
    }
    return v;
}

static const void *kWXKBMaskLayerKey = &kWXKBMaskLayerKey;

// 六边形路径（正多边形，可拉伸到按键矩形）
static UIBezierPath *WXKBHexagonPath(CGSize s) {
    CGFloat w = s.width, h = s.height;
    if (w <= 0 || h <= 0) return nil;
    CGFloat cx = w / 2.0, cy = h / 2.0;
    UIBezierPath *p = [UIBezierPath bezierPath];
    for (int i = 0; i < 6; i++) {
        CGFloat a = (3.141592653589793 / 180.0) * (60.0 * i - 90.0);
        CGFloat x = cx + (w / 2.0) * cos(a);
        CGFloat y = cy + (h / 2.0) * sin(a);
        if (i == 0) [p moveToPoint:CGPointMake(x, y)];
        else [p addLineToPoint:CGPointMake(x, y)];
    }
    [p closePath];
    return p;
}

// 水珠（水滴）路径：上方尖、下方圆
static UIBezierPath *WXKBWaterDropPath(CGSize s) {
    CGFloat w = s.width, h = s.height;
    if (w <= 0 || h <= 0) return nil;
    CGFloat cx = w / 2.0;
    CGFloat tipY = h * 0.10;
    CGFloat r = w / 2.0;
    CGFloat bottomCy = h - r;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(cx, tipY)];
    [p addCurveToPoint:CGPointMake(cx + r, bottomCy)
         controlPoint1:CGPointMake(cx + r * 0.55, tipY + h * 0.28)
         controlPoint2:CGPointMake(cx + r, bottomCy - r * 0.55)];
    [p addArcWithCenter:CGPointMake(cx, bottomCy) radius:r
             startAngle:0 endAngle:3.141592653589793 clockwise:YES];
    [p addCurveToPoint:CGPointMake(cx, tipY)
         controlPoint1:CGPointMake(cx - r, bottomCy - r * 0.55)
         controlPoint2:CGPointMake(cx - r * 0.55, tipY + h * 0.28)];
    [p closePath];
    return p;
}

// 仅对「真正画背景的叶子视图」应用形状（不动布局，纯视觉裁剪）
static void WXKBApplyShapeMask(UIView *target, NSInteger shape, CGSize sz) {
    if (!target || sz.width <= 0 || sz.height <= 0) return;
    if (shape == 1) {                       // 圆形
        target.layer.mask = nil;
        objc_setAssociatedObject(target, kWXKBMaskLayerKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGFloat r = MIN(sz.width, sz.height) / 2.0;
        if (fabs(target.layer.cornerRadius - r) > 0.01) target.layer.cornerRadius = r;
        target.layer.masksToBounds = YES;
    } else {                                // 六边形 / 水珠
        target.layer.cornerRadius = 0;
        CAShapeLayer *mask = objc_getAssociatedObject(target, kWXKBMaskLayerKey);
        if (!mask) {
            mask = [CAShapeLayer layer];
            objc_setAssociatedObject(target, kWXKBMaskLayerKey, mask,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            target.layer.mask = mask;
        }
        UIBezierPath *path = (shape == 2) ? WXKBHexagonPath(sz) : WXKBWaterDropPath(sz);
        mask.path = path.CGPath;
    }
}

static void WXKBApplyCorner(UIView *v);
static UIColor *WXKBKeyBackground(WBKeyView *v);

// —— 立体键帽（真实电脑键盘风）——
// 每颗键渲染成一颗真键帽：① 深色「键体」铺满轮廓 = 侧壁/前脸；② 在键体内**内缩一圈**的
// 凸起「顶面」（上亮下暗穹顶渐变） = 键帽被抬起、四周露出侧壁；③ 正下方再伸出一截侧壁，
// 给有空隙/透明键盘时的真实厚度；④ v 上投一道柔和阴影，整颗键像浮在底板上。
// 全部是附加图层、不动布局（不碰 frame/约束、不碰文字），规避 1.6.16 那类崩溃。

static const void *kWXKBCapLayerKey = &kWXKBCapLayerKey;   // 伸出底部的侧壁
static const void *kWXKBCapBodyKey  = &kWXKBCapBodyKey;    // 键体（深色侧壁/前脸）
static const void *kWXKBCapTopKey   = &kWXKBCapTopKey;     // 凸起顶面（穹顶渐变）

static void WXKBApplyCap(UIView *v, UIView *leaf) {
    UIView *target = leaf ?: v;
    CAShapeLayer *wall = objc_getAssociatedObject(v, kWXKBCapLayerKey);
    CAShapeLayer *body = objc_getAssociatedObject(target, kWXKBCapBodyKey);
    CAGradientLayer *top  = objc_getAssociatedObject(target, kWXKBCapTopKey);
    if (!gEnabled || !gCap3D || gSkinEnabled) {
        if (wall)  { [wall removeFromSuperlayer];  objc_setAssociatedObject(v, kWXKBCapLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (body)  { [body removeFromSuperlayer];  objc_setAssociatedObject(target, kWXKBCapBodyKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (top)   { [top  removeFromSuperlayer];  objc_setAssociatedObject(target, kWXKBCapTopKey,   nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        // 还原：清掉我们加的悬浮阴影
        v.layer.shadowOpacity = 0.0;
        return;
    }
    CGSize sz = v.bounds.size;
    if (sz.width <= 8.0 || sz.height <= 8.0) {
        return;
    }
    CGSize tbsz = target.bounds.size;   // 背景叶自身尺寸（键帽图层挂在叶上才不会被遮挡）
    // 键帽要伸出底部 + 投阴影，按键自身不能再裁剪
    if (v.layer.masksToBounds) v.layer.masksToBounds = NO;
    // 压掉系统原生阴影（取消裁剪后会漏出灰圈），改用我们自己的柔和投影
    if (v.layer.shadowOpacity > 0.0 && v.layer.shadowRadius < 0.5) v.layer.shadowOpacity = 0.0;

    static const CGFloat kDepth = 4.0;      // 底部伸出厚度
    static const CGFloat kInset = 3.0;      // 顶面左右内缩（露出侧壁）
    static const CGFloat kFront = 6.0;      // 顶面底部上抬 → 露出更明显的前脸
    CGFloat rad = 5.0;
    if (gShape == 0) {
        rad = target.layer.cornerRadius;
        if (gCorner > 0.01) rad = gCorner;
        rad = MIN(rad, MIN(sz.width, sz.height) / 2.0);
        if (rad <= 0.5) rad = 5.0;
    }

    // 取按键底色：优先用我们的配色（含彩虹/数字分组），否则取原生背景叶颜色
    UIColor *base = WXKBKeyBackground((WBKeyView *)v);
    if (!base) {
        CGColorRef cg = target.layer.backgroundColor ?: v.layer.backgroundColor;
        if (cg) base = [UIColor colorWithCGColor:cg];
    }

    // 由底色推导键帽各段色（高光 / 亮面 / 正面 / 下缘 / 前面）
    CGFloat h = 0, s = 0, br = 0, al = 0;
    UIColor *cHi, *cLight, *cFace, *cLow, *cFront;
    if (base && [base getHue:&h saturation:&s brightness:&br alpha:&al] && s > 0.02) {
        cHi    = [UIColor colorWithHue:h saturation:MAX(s * 0.35, 0.0) brightness:MIN(br * 1.30 + 0.30, 1.0) alpha:1.0];
        cLight = [UIColor colorWithHue:h saturation:s brightness:MIN(br * 1.14, 1.0) alpha:1.0];
        cFace  = [UIColor colorWithHue:h saturation:s brightness:br alpha:1.0];
        cLow   = [UIColor colorWithHue:h saturation:s brightness:br * 0.82 alpha:1.0];
        cFront = [UIColor colorWithHue:h saturation:MIN(s * 1.25, 1.0) brightness:br * 0.46 alpha:1.0];
    } else {
        CGFloat w = (base) ? br : 0.78;
        if (base) { CGFloat a0 = 0; if (![base getWhite:&w alpha:&a0]) w = br; }
        cHi    = [UIColor colorWithWhite:MIN(w * 1.30 + 0.22, 1.0) alpha:1.0];
        cLight = [UIColor colorWithWhite:MIN(w * 1.12, 1.0) alpha:1.0];
        cFace  = [UIColor colorWithWhite:w alpha:1.0];
        cLow   = [UIColor colorWithWhite:w * 0.82 alpha:1.0];
        cFront = [UIColor colorWithWhite:w * 0.46 alpha:1.0];
    }

    // 轮廓按各自坐标系生成：键体/顶面按背景叶尺寸 tbsz（与 layer 坐标一致），
    // 伸出侧壁按按键尺寸 sz（要覆盖整颗键并向下凸出）
    UIBezierPath *silLeaf = nil;
    if (gShape == 2) {
        silLeaf = WXKBHexagonPath(tbsz);
    } else if (gShape == 3) {
        silLeaf = WXKBWaterDropPath(tbsz);
    } else {
        if (gShape == 1) rad = MIN(tbsz.width, tbsz.height) / 2.0;
        silLeaf = [UIBezierPath bezierPathWithRoundedRect:
                       CGRectMake(0, 0, tbsz.width, tbsz.height) cornerRadius:rad];
    }
    if (!silLeaf) return;

    // 凸起顶面轮廓：圆角/圆形左右缩 kInset、顶部微缩、底部上抬 kFront（露出高前脸）；
    // 六边形/水珠按比例缩 0.88
    UIBezierPath *topPath;
    if (gShape >= 2) {
        topPath = [silLeaf copy];
        CGFloat cx = tbsz.width / 2.0, cy = tbsz.height / 2.0;
        CGAffineTransform t = CGAffineTransformMakeTranslation(cx, cy);
        t = CGAffineTransformConcat(CGAffineTransformMakeScale(0.88, 0.88), t);
        t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(-cx, -cy));
        [topPath applyTransform:t];
    } else {
        CGFloat rr = (gShape == 1) ? MAX(MIN(tbsz.width, tbsz.height) / 2.0 - kInset, 1.0)
                                   : MAX(rad - kInset, 1.0);
        CGFloat topY  = 1.5;
        CGFloat botY = kInset + kFront;     // 底部多抬一截 → 前脸更高
        topPath = [UIBezierPath bezierPathWithRoundedRect:
                       CGRectMake(kInset, topY, tbsz.width - 2 * kInset,
                                  tbsz.height - topY - botY) cornerRadius:rr];
    }

    // 伸出底部的侧壁：整颗键轮廓（sz）下移 kDepth
    UIBezierPath *silWall = nil;
    if (gShape == 2) {
        silWall = WXKBHexagonPath(sz);
    } else if (gShape == 3) {
        silWall = WXKBWaterDropPath(sz);
    } else {
        CGFloat r2 = rad;
        if (gShape == 1) r2 = MIN(sz.width, sz.height) / 2.0;
        silWall = [UIBezierPath bezierPathWithRoundedRect:
                       CGRectMake(0, 0, sz.width, sz.height) cornerRadius:r2];
    }
    if (!silWall) return;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // ① 键体（深色，铺满轮廓 = 侧壁 + 前脸）—— 挂在背景叶上，避免被叶遮挡
    if (!body) {
        body = [CAShapeLayer layer];
        body.name = @"wxkb_cap_body";
        objc_setAssociatedObject(target, kWXKBCapBodyKey, body, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [target.layer insertSublayer:body atIndex:0];
    }
    body.frame = CGRectMake(0, 0, tbsz.width, tbsz.height);
    body.path = silLeaf.CGPath;
    body.fillColor = cFront.CGColor;
    body.zPosition = -998;

    // ② 凸起顶面（内缩轮廓内的穹顶渐变：上亮下暗）—— 同样挂在背景叶上
    if (!top) {
        top = [CAGradientLayer layer];
        top.name = @"wxkb_cap_top";
        objc_setAssociatedObject(target, kWXKBCapTopKey, top, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [target.layer insertSublayer:top atIndex:0];
    }
    top.frame = CGRectMake(0, 0, tbsz.width, tbsz.height);
    top.startPoint = CGPointMake(0.5, 0.0);
    top.endPoint   = CGPointMake(0.5, 1.0);
    top.locations = @[@0.0, @0.15, @0.6, @1.0];   // 高光 → 亮面 → 正面 → 下缘
    top.colors = @[(id)cHi.CGColor, (id)cLight.CGColor, (id)cFace.CGColor, (id)cLow.CGColor];
    CAShapeLayer *tmask = [CAShapeLayer layer];
    tmask.path = topPath.CGPath;
    top.mask = tmask;
    top.zPosition = -997;

    // ③ 正下方伸出的侧壁（有空隙/透明键盘时厚度可见）
    UIBezierPath *wallPath = [silWall copy];
    [wallPath applyTransform:CGAffineTransformMakeTranslation(0, kDepth)];
    if (!wall) {
        wall = [CAShapeLayer layer];
        wall.name = @"wxkb_keycap_wall";
        wall.zPosition = -1000;
        objc_setAssociatedObject(v, kWXKBCapLayerKey, wall, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [v.layer insertSublayer:wall atIndex:0];
    }
    wall.frame = CGRectMake(0, 0, sz.width, sz.height + kDepth);
    wall.path = wallPath.CGPath;
    wall.fillColor = cFront.CGColor;

    // ④ 整颗键柔和投影（浮在底板上）
    v.layer.shadowColor  = [UIColor colorWithWhite:0.0 alpha:1.0].CGColor;
    v.layer.shadowOpacity = 0.28;
    v.layer.shadowOffset  = CGSizeMake(0.0, 2.0);
    v.layer.shadowRadius  = 3.0;

    [CATransaction commit];
}

static void WXKBApplyCornerInner(UIView *v) {
    if (!v || !gEnabled) {
        return;
    }
    UIView *leaf = WXKBFindBgLeaf(v, 0);
    UIView *target = leaf ?: v;

    if (gShape == 0) {
        // 还原：清掉任何旧形状，仅按 keyCornerRadius 做圆角
        target.layer.mask = nil;
        objc_setAssociatedObject(target, kWXKBMaskLayerKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (gCorner <= 0.01) {
            if (target.layer.cornerRadius != 0) target.layer.cornerRadius = 0;
            if (target != v && v.layer.cornerRadius != 0) v.layer.cornerRadius = 0;
            return;
        }
        CGFloat r = MIN(gCorner, MIN(v.bounds.size.height, v.bounds.size.width) / 2.0);
        if (r <= 0.01) return;
        NSMutableArray *arr = [NSMutableArray arrayWithObject:target];
        if (target != v) [arr addObject:v];
        for (UIView *t in arr) {
            if (fabs(t.layer.cornerRadius - r) > 0.01) t.layer.cornerRadius = r;
            // 开键帽时按键自身不能裁剪（侧壁要伸出底部），只裁背景叶
            if (t == target || !gCap3D) t.layer.masksToBounds = YES;
        }
        return;
    }

    // shape 1/2/3：忽略 keyCornerRadius，用形状（蒙版只加在背景叶子，不裁文字）
    WXKBApplyShapeMask(target, gShape, target.bounds.size);
    if (target != v) {
        // key 自身不再额外圆角/蒙版，避免双重裁剪
        v.layer.mask = nil;
        v.layer.cornerRadius = 0;
    }
}

static void WXKBApplySkin(UIView *v, UIView *leaf);  // 前向声明（定义见下方皮肤块）

static void WXKBApplyCorner(UIView *v) {
    WXKBApplyCornerInner(v);
    if (!v) return;
    WXKBApplyCap(v, WXKBFindBgLeaf(v, 0));
    WXKBApplySkin(v, WXKBFindBgLeaf(v, 0));
}

static BOOL WXKBIsKeyView(UIView *v) {
    static Class keyCls, ruleCls, retCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keyCls  = objc_getClass("WBKeyView");
        ruleCls = objc_getClass("WBRuleKeyView");
        retCls  = objc_getClass("WBReturnKeyView");
    });
    if (keyCls && [v isKindOfClass:keyCls]) return YES;
    if (ruleCls && [v isKindOfClass:ruleCls]) return YES;
    if (retCls && [v isKindOfClass:retCls]) return YES;
    return NO;
}

// —— 整键盘透明 ——

static const void *kWXKBOrigBgKey   = &kWXKBOrigBgKey;
static const void *kWXKBOrigOpaqueKey = &kWXKBOrigOpaqueKey;
static const void *kWXKBOrigEffectKey = &kWXKBOrigEffectKey;
static const void *kWXKBOrigImgKey  = &kWXKBOrigImgKey;
static const void *kWXKBOrigHiddenKey = &kWXKBOrigHiddenKey;


static void WXKBClearBgTree(UIView *v) {
    if (!v) return;

    // 按键及其子树一律不动：按键底色/文字色保持用户设置（默认黑字）
    if (WXKBIsKeyView(v)) return;

    // 我们自己插入的背景层不参与，单独处理
    if (v.tag == 0x57584247) {
        for (UIView *s in v.subviews) WXKBClearBgTree(s);
        return;
    }


    // 1.6.6：系统键盘 backdrop（_UIBackdropEffectView / UIKBBackdropView 等私有类）
    // 不走 backgroundColor / UIVisualEffectView API，probe 里 backgroundColor 全透明
    // 却仍有灰底就是它画的 —— 直接隐藏才能透。
    @try {
        NSString *cn = NSStringFromClass([v class]);
        if ([cn containsString:@"BackdropEffectView"] ||
            [cn containsString:@"UIKBBackdrop"]) {
            if (!objc_getAssociatedObject(v, kWXKBOrigHiddenKey)) {
                objc_setAssociatedObject(v, kWXKBOrigHiddenKey,
                                         @([v isHidden]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            v.hidden = YES;
            return;
        }
    } @catch (__unused NSException *e) {
    }

    if (!objc_getAssociatedObject(v, kWXKBOrigBgKey)) {
        objc_setAssociatedObject(v, kWXKBOrigBgKey,
                                 v.backgroundColor ?: [UIColor clearColor],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kWXKBOrigOpaqueKey,
                                 @(v.opaque), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([v isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffect *e = ((UIVisualEffectView *)v).effect;
            objc_setAssociatedObject(v, kWXKBOrigEffectKey,
                                     e, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if ([v isKindOfClass:[UIImageView class]]) {
            objc_setAssociatedObject(v, kWXKBOrigImgKey,
                                     ((UIImageView *)v).image,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    if ([v isKindOfClass:[UIVisualEffectView class]]) {
        ((UIVisualEffectView *)v).effect = nil;
    } else if ([v isKindOfClass:[UIImageView class]]) {
        // 只清「铺满父级」的那种背景图，图标不受影响
        UIImageView *iv = (UIImageView *)v;
        if (iv.superview && iv.bounds.size.width >= iv.superview.bounds.size.width - 2 &&
            iv.bounds.size.height >= iv.superview.bounds.size.height - 2) {
            iv.image = nil;
        }
    }

    v.backgroundColor = [UIColor clearColor];
    v.opaque = NO;
    v.layer.opaque = NO;
    if (@available(iOS 13.0, *)) {
        v.backgroundColor = [UIColor clearColor];
    }

    for (UIView *s in v.subviews) {
        WXKBClearBgTree(s);
    }
}

static void WXKBRestoreBgTree(UIView *v) {
    if (!v) return;
    if (WXKBIsKeyView(v)) return;

    NSNumber *hid = objc_getAssociatedObject(v, kWXKBOrigHiddenKey);
    if (hid) {
        v.hidden = [hid boolValue];
        objc_setAssociatedObject(v, kWXKBOrigHiddenKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIColor *bg = objc_getAssociatedObject(v, kWXKBOrigBgKey);
    if (bg) {
        v.backgroundColor = (bg == [UIColor clearColor]) ? nil : bg;
        NSNumber *op = objc_getAssociatedObject(v, kWXKBOrigOpaqueKey);
        v.opaque = op ? op.boolValue : YES;
        objc_setAssociatedObject(v, kWXKBOrigBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, kWXKBOrigOpaqueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIVisualEffect *e = objc_getAssociatedObject(v, kWXKBOrigEffectKey);
    if (e && [v isKindOfClass:[UIVisualEffectView class]]) {
        ((UIVisualEffectView *)v).effect = e;
        objc_setAssociatedObject(v, kWXKBOrigEffectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIImage *img = objc_getAssociatedObject(v, kWXKBOrigImgKey);
    if (img && [v isKindOfClass:[UIImageView class]]) {
        ((UIImageView *)v).image = img;
        objc_setAssociatedObject(v, kWXKBOrigImgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *s in v.subviews) {
        WXKBRestoreBgTree(s);
    }
}

// 1.6.6：透明直接从「键盘窗口」整棵树清。
// 1.6.5 只清微信子树 + 直系祖先链，但系统 backdrop 很可能是 WBRootInputView 的
// 兄弟视图（宿主容器里和键盘并排），直系链根本够不着 —— 用户实测灰底仍在。
// 整窗清能覆盖：兄弟 backdrop、系统宿主 UIInputView、窗口自身背景。
// 按键子树 / 增强按钮条 / 自绘背景层在 WXKBClearBgTree 里照常跳过。
static void WXKBApplyTransparency(UIView *host) {
    if (!host) return;
    UIView *top = host.window ?: host;
    if (!gEnabled || !gTransparent) {
        WXKBRestoreBgTree(top);
        return;
    }
    WXKBClearBgTree(top);
}

// —— 键盘整体位移 ——
// 用 transform 平移，原生布局不会把它重置回 identity。
// 1.6.7（用户明确要求）：下移 = 整体刚性平移，绝不压缩键盘尺寸。
// 屏幕底边以下物理上无法显示（hook 不到「被吃掉」的部分），所以下移上限 =
// 底部安全区（键盘正常悬停在它上方，往下平移刚好填满这条空当、贴到屏幕底），
// 超过就会把最底下一排裁出屏幕。safeAreaInsets 读不到时兜底 46pt（覆盖小黑条区）。
// 1.6.8：位移非零时清祖先链背景 —— 整体平移后顶部露出的灰白块就是键盘容器
// （UIInputView / hosted 容器 / 窗口）画的背景；清掉后露出的是 App 内容，观感即
// 「键盘贴底、上方无空洞」。透明开启时窗口整树已被 WXKBApplyTransparency 清掉，
// 无需重复；位移归零时精确还原祖先链。
static void WXKBClearAncestorBg(UIView *root) {
    UIView *p = root.superview;
    while (p) {
        if ([p isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView *ve = (UIVisualEffectView *)p;
            if (!objc_getAssociatedObject(ve, kWXKBOrigEffectKey)) {
                objc_setAssociatedObject(ve, kWXKBOrigEffectKey,
                                         ve.effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            ve.effect = nil;
        }
        if (!objc_getAssociatedObject(p, kWXKBOrigBgKey)) {
            objc_setAssociatedObject(p, kWXKBOrigBgKey,
                                     p.backgroundColor ?: [UIColor clearColor],
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(p, kWXKBOrigOpaqueKey,
                                     @(p.opaque), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        p.backgroundColor = [UIColor clearColor];
        p.opaque = NO;
        p.layer.opaque = NO;
        if ([p isKindOfClass:[UIWindow class]]) break;
        p = p.superview;
    }
}

static void WXKBRestoreAncestorBg(UIView *root) {
    UIView *p = root.superview;
    while (p) {
        UIVisualEffect *e = objc_getAssociatedObject(p, kWXKBOrigEffectKey);
        if (e && [p isKindOfClass:[UIVisualEffectView class]]) {
            ((UIVisualEffectView *)p).effect = e;
            objc_setAssociatedObject(p, kWXKBOrigEffectKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIColor *bg = objc_getAssociatedObject(p, kWXKBOrigBgKey);
        if (bg) {
            p.backgroundColor = (bg == [UIColor clearColor]) ? nil : bg;
            NSNumber *op = objc_getAssociatedObject(p, kWXKBOrigOpaqueKey);
            p.opaque = op ? op.boolValue : YES;
            objc_setAssociatedObject(p, kWXKBOrigBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(p, kWXKBOrigOpaqueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if ([p isKindOfClass:[UIWindow class]]) break;
        p = p.superview;
    }
}

static void WXKBApplyOffset(UIView *root) {
    if (!root) return;
    @try {
        CGFloat off = (gEnabled ? gKbOffset : 0.0);
        if (off > 0.5) {
            CGFloat safe = 0;
            if (@available(iOS 11.0, *)) safe = root.safeAreaInsets.bottom;
            CGFloat maxDown = (safe > 1.0) ? safe : 46.0;
            if (off > maxDown) off = maxDown;
        }
        CGAffineTransform t =
            (fabs(off) > 0.5)
                ? CGAffineTransformMakeTranslation(0, (CGFloat)off)
                : CGAffineTransformIdentity;
        if (!CGAffineTransformEqualToTransform(root.transform, t)) {
            root.transform = t;
        }
        if (!gTransparent) {
            if (fabs(off) > 0.5) WXKBClearAncestorBg(root);
            else                 WXKBRestoreAncestorBg(root);
        }
    } @catch (__unused NSException *e) {
    }
}

// 偏好变化后让已存在的键盘立刻重排（位置类改动不触发原生 layout）。
static void WXKBRelayoutTree(UIView *v) {
    if (!v) return;
    Class rootCls = objc_getClass("WBRootInputView");
    if (rootCls && [v isKindOfClass:rootCls]) {
        [v setNeedsLayout];
        return;
    }
    for (UIView *s in v.subviews) {
        WXKBRelayoutTree(s);
    }
}

static void WXKBForceRelayout(void) {
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        NSMutableArray *wins = [NSMutableArray array];
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in app.connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    [wins addObjectsFromArray:((UIWindowScene *)s).windows];
                }
            }
        }
        if (wins.count == 0) [wins addObjectsFromArray:app.windows];
        for (UIWindow *w in wins) {
            WXKBRelayoutTree(w);
        }
    } @catch (__unused NSException *e) {
    }
}

// 键盘窗口自身也要透明，否则整棵树的透明会被窗口底色吃掉
static void WXKBClearKeyboardWindows(void) {
    @try {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w.windowLevel == UIWindowLevelNormal ||
                w.windowLevel == UIWindowLevelAlert) {
                if (w.backgroundColor && ![w.backgroundColor isEqual:[UIColor clearColor]]) {
                    objc_setAssociatedObject(w, kWXKBOrigBgKey,
                                             w.backgroundColor,
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    w.backgroundColor = [UIColor clearColor];
                }
                if (w.opaque) {
                    objc_setAssociatedObject(w, kWXKBOrigOpaqueKey, @(YES),
                                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    w.opaque = NO;
                }
            }
        }
    } @catch (__unused NSException *e) {
    }
}

static void WXKBRestoreKeyboardWindows(void) {
    @try {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            UIColor *bg = objc_getAssociatedObject(w, kWXKBOrigBgKey);
            if (bg) {
                w.backgroundColor = bg;
                objc_setAssociatedObject(w, kWXKBOrigBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            NSNumber *op = objc_getAssociatedObject(w, kWXKBOrigOpaqueKey);
            if (op) {
                w.opaque = op.boolValue;
                objc_setAssociatedObject(w, kWXKBOrigOpaqueKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    } @catch (__unused NSException *e) {
    }
}

// 全树扫一遍，重新盖上圆角 + 透明度。原生 layout 之后跑一次，稳赢原生写入。
static void WXKBSyncTree(UIView *root) {
    if (!root) return;
    @try {
        if (WXKBIsKeyView(root)) {
            WXKBApplyCorner(root);
            return;   // 按键子树里没有背景层要清
        }
        if (gEnabled && gTransparent) {
            WXKBClearBgTree(root);
        } else if (gEnabled && gBgEnabled) {
            WXKBRestoreBgTree(root);
        }
        for (UIView *s in root.subviews) {
            WXKBSyncTree(s);
        }
    } @catch (__unused NSException *e) {
    }
}

static BOOL gSyncScheduled = NO;
static void WXKBScheduleSync(void) {
    if (gSyncScheduled) return;
    gSyncScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        gSyncScheduled = NO;
        @try {
            for (UIWindow *w in [UIApplication sharedApplication].windows) {
                WXKBSyncTree(w);
            }
            if (gEnabled && gTransparent) {
                WXKBClearKeyboardWindows();
            } else {
                WXKBRestoreKeyboardWindows();
            }
            // 二次兜底：原生 layout 可能把位移写回，异步再压一次
            UIView *iv = [WXKBInputController() view];
            if (iv) WXKBApplyOffset(iv);
        } @catch (__unused NSException *e) {
        }
    });
}

static void WXKBOnPrefsChanged(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object,
                               CFDictionaryRef userInfo) {
    WXKBReload(YES);
    WXKBScheduleSync();
    WXKBForceRelayout();
}

#pragma mark - 工具栏功能列表

static BOOL WXKBIsEditing(id bar) {
    return [bar respondsToSelector:@selector(editing)] ? [bar editing] : NO;
}


#pragma mark - 布局

// 左侧固定按钮（微信 logo 等）的最右边界：与工具栏同处一行、竖直相交、且完全在工具栏左侧。
static CGFloat WXKBLeftFixedMaxX(UIView *bar, UIView *topBar) {
    UIView *container = topBar.superview;
    if (!container) {
        return 0;
    }
    CGRect row = [topBar convertRect:bar.frame toView:container];
    CGFloat best = 0;
    for (UIView *v in container.subviews) {
        if (v == topBar) {
            continue;
        }
        CGRect f = v.frame;
        if (f.size.width < 20 || f.size.height < 20) {
            continue;
        }
        if (CGRectGetMaxX(f) > CGRectGetMinX(row) + 0.5) {
            continue;
        }
        if (CGRectGetMaxY(f) < CGRectGetMinY(row) + 0.5) {
            continue;
        }
        if (CGRectGetMinY(f) > CGRectGetMaxY(row) - 0.5) {
            continue;
        }
        if (CGRectGetMaxX(f) > best) {
            best = CGRectGetMaxX(f);
        }
    }
    return best;
}

// 滚动容器始终铺满工具栏；内容溢出时恢复横向滑动
static void WXKBFixScroll(UIView *bar) {
    CGSize bd = bar.bounds.size;
    for (UIView *v in bar.subviews) {
        if (![v isKindOfClass:[UIScrollView class]]) {
            continue;
        }
        UIScrollView *sv = (UIScrollView *)v;
        CGRect f = sv.frame;
        if (fabs(f.origin.x) > 0.5 || fabs(f.origin.y) > 0.5 ||
            fabs(f.size.width - bd.width) > 0.5 ||
            fabs(f.size.height - bd.height) > 0.5) {
            sv.frame = CGRectMake(0, 0, bd.width, bd.height);
        }
        if (sv.contentSize.width > sv.bounds.size.width + 0.5) {
            sv.scrollEnabled = YES;
        }
        break;
    }
}

// 工具栏紧贴左侧固定按钮并铺满整行剩余宽度；内部滚动容器同步铺满。
static void WXKBFillRow(UIView *topBar) {
    Class barCls = objc_getClass("WBFunctionToolBar");
    if (!barCls) {
        return;
    }
    CGFloat rowW = topBar.bounds.size.width;
    if (rowW <= 0) {
        return;
    }

    for (UIView *bar in topBar.subviews) {
        if (![bar isKindOfClass:barCls]) {
            continue;
        }
        // 编辑态（长按图标进入的「定制工具栏」）交给原生布局，
        // 否则被强制撑满会和原生编辑界面叠在一起。
        if (WXKBIsEditing(bar)) {
            return;
        }

        CGFloat inset = WXKBLeftFixedMaxX(bar, topBar);
        CGFloat x = inset > 0 ? inset : 0;
        CGFloat w = rowW - x;
        CGRect f = bar.frame;
        if (w >= 40 &&
            (fabs(f.origin.x - x) > 0.5 || fabs(f.size.width - w) > 0.5)) {
            f.origin.x = x;
            f.size.width = w;
            bar.frame = f;
        }
        WXKBFixScroll(bar);
        break;
    }
}

#pragma mark - 按键分类

typedef NS_ENUM(NSInteger, WXKBKeyKind) {
    WXKBKeyKindLetter = 0,   // A-Z
    WXKBKeyKindDigit,        // 数字/符号键（数字·符号面板中间的主键，identifier 是单字符）
    WXKBKeyKindFuncLeft,     // 大小写 / 数字 / 符号 …
    WXKBKeyKindFuncRight,    // 删除 / 中英切换 / 发送 …
    WXKBKeyKindSpace,        // 空格
};

static id WXKBItem(WBKeyView *v) {
    id item = nil;
    @try {
        item = [v item];
    } @catch (__unused NSException *e) {
    }
    return item;
}

// 字母键：alphabetIndex 0..25
static NSInteger WXKBLetterIndex(WBKeyView *v) {
    id item = WXKBItem(v);
    if (!item) {
        return NSNotFound;
    }
    NSInteger idx = NSNotFound;
    @try {
        idx = [item alphabetIndex];
    } @catch (__unused NSException *e) {
    }
    return (idx >= 0 && idx < 26) ? idx : NSNotFound;
}

static NSString *WXKBIdentifier(WBKeyView *v) {
    id item = WXKBItem(v);
    if (!item) {
        return nil;
    }
    NSString *s = nil;
    @try {
        s = [item identifier];
    } @catch (__unused NSException *e) {
    }
    if (![s isKindOfClass:[NSString class]] || !s.length) {
        return nil;
    }
    return [s lowercaseString];
}

static BOOL WXKBIdentHas(NSString *ident, NSArray *keys) {
    if (!ident.length) {
        return NO;
    }
    for (NSString *k in keys) {
        if ([ident containsString:k]) {
            return YES;
        }
    }
    return NO;
}

// 归组：优先按 item.identifier 语义匹配，拿不到就按按键在键盘上的左右半区兜底。
static WXKBKeyKind WXKBKindOf(WBKeyView *v) {
    if (WXKBLetterIndex(v) != NSNotFound) {
        return WXKBKeyKindLetter;
    }

    // 数字/符号键：identifier 是单个非字母字符（1-0、- / : ~ ( ) 等，
    // 只出现在数字·符号面板；中文面板的「，。」这类符号键也会归进来，语义一致）。
    NSString *ident0 = WXKBIdentifier(v);
    if (ident0.length == 1) {
        unichar c = [ident0 characterAtIndex:0];
        BOOL isLetter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        if (!isLetter) {
            return WXKBKeyKindDigit;
        }
    }

    static NSArray *spaceKeys, *leftKeys, *rightKeys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        spaceKeys = @[@"space", @"kongge"];
        leftKeys  = @[@"shift", @"caps", @"number", @"numeric", @"digit",
                      @"symbol", @"punctuation", @"emoji", @"face", @"more",
                      @"symbols", @"num"];
        rightKeys = @[@"delete", @"backspace", @"del", @"return", @"enter",
                      @"send", @"go", @"search", @"done", @"next",
                      @"globe", @"language", @"lang", @"cn", @"en",
                      @"switch", @"hide", @"dismiss", @"keyboard"];
    });

    NSString *ident = WXKBIdentifier(v);
    if (WXKBIdentHas(ident, spaceKeys)) {
        return WXKBKeyKindSpace;
    }
    if (WXKBIdentHas(ident, rightKeys)) {
        return WXKBKeyKindFuncRight;
    }
    if (WXKBIdentHas(ident, leftKeys)) {
        return WXKBKeyKindFuncLeft;
    }

    // 位置兜底：键盘中心线左/右
    UIView *win = v.window;
    CGFloat mid = win ? (win.bounds.size.width / 2.0) : 195.0;
    CGFloat cx = CGRectGetMidX(v.frame);
    UIView *sup = v.superview;
    if (sup) {
        cx = [v.superview convertPoint:CGPointMake(CGRectGetMidX(v.bounds),
                                                   CGRectGetMidY(v.bounds))
                                toView:win].x;
    }
    return (cx < mid) ? WXKBKeyKindFuncLeft : WXKBKeyKindFuncRight;
}

#pragma mark - 按键配色

static UIColor *WXKBGradientColor(NSInteger idx) {
    if (!gGradFrom || !gGradTo) {
        return nil;
    }
    CGFloat t = (CGFloat)idx / 25.0;
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 1;
    CGFloat r2 = 0, g2 = 0, b2 = 0, a2 = 1;
    if (![gGradFrom getRed:&r1 green:&g1 blue:&b1 alpha:&a1] ||
        ![gGradTo getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) {
        return nil;
    }
    return [UIColor colorWithRed:r1 + (r2 - r1) * t
                           green:g1 + (g2 - g1) * t
                            blue:b1 + (b2 - b1) * t
                           alpha:a1 + (a2 - a1) * t];
}

#pragma mark - 内置皮肤（百度「彩虹按键」真实键帽）

// 从 jbroot 下的皮肤目录加载真实键帽 PNG（key26a = 26 字母键帽横排；key9a = 9 功能键帽横排），
// 按图片里的**真实键距**切片成单颗键帽图。皮肤由「彩虹按键」指令从百度输入法导出，
// 路径 = WXKB_SKIN_DIR/<皮肤名>/res/。
//
// ⚠️ 下面这几个数字是对 PNG 逐像素量出来的，别凭直觉改：
//   key26a.png 2160x132 → 26 颗键帽、间距(pitch)恰好 80px，尾部还有 80px 留白(27*80=2160)。
//       若按 2160/26≈83 等分，每片会多带 3px 隔壁键帽 → 键上出现一条错色竖纹（1.7.0 的 bug）。
//       纵向 0..108 是键帽本体，109 之后是键帽下方的柔和投影，必须裁掉，
//       否则投影会被压到键底、看起来就是「贴图没对齐 / 往下偏了」。
//   key9a.png 1944x144 → 9 颗键帽、间距恰好 216px（正好等分）；纵向 0..121 是本体，122 起是投影。
//   配色分三段：片 0..9 / 10..18 / 19..25，每段自成一条从左到右的彩虹
//       （实测色相在片 9→10、18→19 处复位，且饱和度逐段变淡），
//       三段长度 10/9/7 正是 QWERTY 三行的键数 → 字母必须按「行内第几个」取片，
//       不能按字母表序号（1.7.0 就是按序号取，整片颜色全错位）。
static const CGFloat kWXKBSkinLetterPitch = 80.0;    // key26a 键帽间距（px）
static const CGFloat kWXKBSkinLetterCapH  = 109.0;   // key26a 键帽本体高（px，不含投影）
static const CGFloat kWXKBSkinFuncPitch   = 216.0;   // key9a 键帽间距（px）
static const CGFloat kWXKBSkinFuncCapH    = 122.0;   // key9a 键帽本体高（px，不含投影）

static UIImage *gSkinLetterImg[26];
static UIImage *gSkinFuncImg[9];
static UIColor *gSkinLetterCol[26];
static UIColor *gSkinFuncCol[9];
static BOOL      gSkinLoaded = NO;
static BOOL      gSkinTried  = NO;

// 把一张横排键帽条按「真实键距 pitch」切成 count 片，每片只取键帽本体（0..capH，丢掉投影）
static NSArray<UIImage *> *WXKBSliceStrip(UIImage *img, NSInteger count,
                                          CGFloat pitch, CGFloat capH) {
    if (!img || count <= 0 || pitch <= 0.0) return nil;
    CGImageRef base = img.CGImage;
    if (!base) return nil;
    size_t W = CGImageGetWidth(base), H = CGImageGetHeight(base);
    if (W == 0 || H == 0) return nil;
    CGFloat sc = (img.scale > 0) ? img.scale : 1.0;
    CGFloat pw = pitch * sc, ph = capH * sc;
    if (pw <= 0.0) return nil;
    if (pw * (CGFloat)count > (CGFloat)W + 1.0) {     // 键距对不上（换了皮）：退回等分
        pw = (CGFloat)W / (CGFloat)count;
    }
    if (ph <= 0.0 || ph > (CGFloat)H) ph = (CGFloat)H;
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (NSInteger i = 0; i < count; i++) {
        CGRect r = CGRectMake((CGFloat)i * pw, 0.0, pw, ph);
        CGImageRef cg = CGImageCreateWithImageInRect(base, r);
        if (!cg) { [arr addObject:[NSNull null]]; continue; }
        UIImage *u = [UIImage imageWithCGImage:cg scale:sc
                                  orientation:UIImageOrientationUp];
        CGImageRelease(cg);
        [arr addObject:u ? u : [NSNull null]];
    }
    return arr;
}

// 取键帽「顶面」代表色：只采中上部键面（x 30~70%、y 18~50%），避开顶部高光、
// 左右侧壁和底部投影。实测这份皮肤（key9a）这个区域的颜色与官方 demo.png 里
// 每颗键的键面颜色**逐字节相同**，所以它就是「这颗键该用什么色」的标准答案。
// 取像素用固定 RGBA 的位图上下文（UIGraphics* 是 BGRA 字节序，会把红蓝取反）。
static UIColor *WXKBFaceColor(UIImage *img) {
    if (!img) return nil;
    CGImageRef cg = img.CGImage;
    if (!cg) return nil;
    size_t W = CGImageGetWidth(cg), H = CGImageGetHeight(cg);
    if (W < 4 || H < 4) return nil;
    CGRect src = CGRectMake((CGFloat)W * 0.30, (CGFloat)H * 0.18,
                            MAX((CGFloat)W * 0.40, 2.0), MAX((CGFloat)H * 0.32, 2.0));
    CGImageRef sub = CGImageCreateWithImageInRect(cg, src);
    if (!sub) return nil;
    const size_t tw = 12, th = 12;
    unsigned char buf[tw * th * 4];
    memset(buf, 0, sizeof(buf));
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(buf, tw, th, 8, tw * 4, cs,
                                             kCGImageAlphaPremultipliedLast |
                                             kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)tw, (CGFloat)th), sub);
        CGContextRelease(ctx);
    }
    CGImageRelease(sub);
    NSUInteger n = (NSUInteger)(tw * th), r = 0, g = 0, b = 0;
    for (NSUInteger i = 0; i < n; i++) {
        r += buf[i * 4 + 0]; g += buf[i * 4 + 1]; b += buf[i * 4 + 2];
    }
    return [UIColor colorWithRed:(r / (CGFloat)n) / 255.0
                           green:(g / (CGFloat)n) / 255.0
                            blue:(b / (CGFloat)n) / 255.0 alpha:1.0];
}

static void WXKBLoadSkin(void) {
    if (gSkinLoaded || gSkinTried) return;
    gSkinTried = YES;
    if (!gSkinEnabled || !gSkinName.length) return;
    NSString *dir = [[WXKBJbrootPath([WXKB_SKIN_DIR
        stringByAppendingPathComponent:gSkinName]) stringByAppendingPathComponent:@"res"]
        stringByAppendingString:@"/"];
    if (!dir) return;
    UIImage *letter = [UIImage imageWithContentsOfFile:[dir stringByAppendingString:@"key26a.png"]];
    UIImage *func   = [UIImage imageWithContentsOfFile:[dir stringByAppendingString:@"key9a.png"]];
    if (!letter) {   // a/b 两版键帽图配色一致，只差键面明暗，互为备份
        letter = [UIImage imageWithContentsOfFile:[dir stringByAppendingString:@"key26b.png"]];
    }
    if (!func) {
        func = [UIImage imageWithContentsOfFile:[dir stringByAppendingString:@"key9b.png"]];
    }
    NSArray *la = WXKBSliceStrip(letter, 26, kWXKBSkinLetterPitch, kWXKBSkinLetterCapH);
    NSArray *fa = WXKBSliceStrip(func,    9, kWXKBSkinFuncPitch,   kWXKBSkinFuncCapH);
    for (NSInteger i = 0; i < 26; i++) {
        id o = la ? la[i] : nil;
        if ([o isKindOfClass:[UIImage class]]) {
            gSkinLetterImg[i] = o;
            gSkinLetterCol[i] = WXKBFaceColor(o);
        }
    }
    for (NSInteger i = 0; i < 9; i++) {
        id o = fa ? fa[i] : nil;
        if ([o isKindOfClass:[UIImage class]]) {
            gSkinFuncImg[i] = o;
            gSkinFuncCol[i] = WXKBFaceColor(o);
        }
    }
    if (gSkinLetterImg[0]) gSkinLoaded = YES; else gSkinTried = NO;  // 没读到则下次再试
}

// 字母 → 皮肤片号。皮肤条按键盘行排版：26 片分 10/9/7 三段（正好 QWERTY 三行的键数，
// 每段自成一条从左到右的彩虹），所以取片必须按「行内第几个」，而不是字母表序号。
static NSInteger WXKBSkinSlotForLetter(NSInteger letterIdx) {   // 0=A … 25=Z
    static const char *rows[3] = { "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" };
    static const NSInteger off[3] = { 0, 10, 19 };
    if (letterIdx < 0 || letterIdx >= 26) return NSNotFound;
    char want = (char)('A' + letterIdx);
    for (NSInteger r = 0; r < 3; r++) {
        const char *s = rows[r];
        for (NSInteger k = 0; s[k] != '\0'; k++) {
            if (s[k] == want) return off[r] + k;
        }
    }
    return NSNotFound;
}

// 非字母键 → key9a 的哪一片（按 identifier 稳定哈希：同一颗键每次都是同一色）
static NSInteger WXKBSkinFuncSlot(NSString *ident) {
    if (!ident.length) return 0;
    NSInteger j = (NSInteger)([ident hash] % 9);
    return (j < 0) ? (j + 9) : j;
}

// 取一颗键对应的皮肤键帽图
static UIImage *WXKBSkinImageFor(WBKeyView *v) {
    WXKBLoadSkin();
    NSInteger li = WXKBLetterIndex(v);
    NSInteger slot = (li != NSNotFound) ? WXKBSkinSlotForLetter(li) : NSNotFound;
    BOOL isLetter = (slot != NSNotFound);
    if (isLetter && slot < 26 && gSkinLetterImg[slot]) {   // 字母键 → 字母条对应那片
        return gSkinLetterImg[slot];
    }
    NSInteger j = WXKBSkinFuncSlot(WXKBIdentifier(v));
    if (gSkinFuncImg[j]) return gSkinFuncImg[j];
    if (isLetter && slot < 26) return gSkinLetterImg[slot];  // 功能条缺失：退回字母条
    return nil;
}

// 皮肤配色（走原生按键底色通道：让整颗键——包括原生白键框——都被皮肤染色，位置天然对齐）
static UIColor *WXKBSkinColorFor(WBKeyView *v) {
    if (!gEnabled || !gSkinEnabled || !v) return nil;
    WXKBLoadSkin();
    NSInteger li = WXKBLetterIndex(v);
    if (li != NSNotFound) {
        NSInteger slot = WXKBSkinSlotForLetter(li);
        if (slot != NSNotFound && slot < 26 && gSkinLetterCol[slot]) {
            return gSkinLetterCol[slot];
        }
    }
    NSInteger j = WXKBSkinFuncSlot(WXKBIdentifier(v));
    if (j >= 0 && j < 9 && gSkinFuncCol[j]) return gSkinFuncCol[j];
    return nil;
}

static const void *kWXKBSkinKey      = &kWXKBSkinKey;       // 已贴图片（去重，避免重复赋值）
static const void *kWXKBSkinLayerKey = &kWXKBSkinLayerKey;  // 皮肤图层（子图层方式）

// 把皮肤键帽图「叠加」成背景叶的子图层。
// ⚠️ 不能用 leaf.layer.contents：contents 在层的 backgroundColor **之下**，
//    会被原生白键帽底整体盖住（1.7.0 的 bug：彩边只从键顶边露出一条）。
//    与 WXKBApplyCap 同一套做法——insertSublayer，子图层恒在底色之上、文字之下。
static void WXKBApplySkin(UIView *v, UIView *leaf) {
    if (!v) return;
    UIView *target = leaf ?: v;
    CALayer *skin = objc_getAssociatedObject(target, kWXKBSkinLayerKey);
    UIImage *img = (!gEnabled || !gSkinEnabled) ? nil : WXKBSkinImageFor((WBKeyView *)v);
    if (!img) {                                    // 关闭 / 图缺失：移除皮肤层，键回到普通配色
        if (skin) {
            [skin removeFromSuperlayer];
            objc_setAssociatedObject(target, kWXKBSkinLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(target, kWXKBSkinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (!skin) {
        skin = [CALayer layer];
        skin.name = @"wxkb_skin";
        skin.contentsGravity = kCAGravityResize;   // 铺满整颗键
        skin.masksToBounds = YES;
        skin.zPosition = -999;                     // 盖底色、居其它子图层之下
        [target.layer insertSublayer:skin atIndex:0];
        objc_setAssociatedObject(target, kWXKBSkinLayerKey, skin, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect b = target.bounds;
    if (!CGRectEqualToRect(skin.frame, b)) skin.frame = b;
    CGFloat rad = target.layer.cornerRadius;
    if (gShape == 0 && gCorner > 0.01) rad = gCorner;
    rad = MIN(rad, MIN(b.size.width, b.size.height) / 2.0);
    if (fabs(skin.cornerRadius - rad) > 0.01) skin.cornerRadius = rad;
    UIImage *prev = objc_getAssociatedObject(target, kWXKBSkinKey);
    if (prev != img) {
        skin.contents = (__bridge id)img.CGImage;
        objc_setAssociatedObject(target, kWXKBSkinKey, img, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [CATransaction commit];
}

static UIColor *WXKBLetterColorFor(NSInteger idx) {
    if (gLetterMap) {
        id v = gLetterMap[[NSString stringWithFormat:@"%ld", (long)idx]];
        if ([v isKindOfClass:[NSString class]] && [v length]) {
            UIColor *c = WXKBColor(v, 1.0);
            if (c) {
                return c;
            }
        }
    }
    if (gGradEnabled) {
        UIColor *c = WXKBGradientColor(idx);
        if (c) {
            return c;
        }
    }
    return gLetterBg;
}

static UIColor *WXKBKeyBackground(WBKeyView *v) {
    if (!gEnabled) {
        return nil;
    }
    // 内置皮肤优先：直接用皮肤自己那颗键的颜色（不受「键帽颜色」开关影响），
    // 这样连原生键框一起染色，键帽图只需负责立体明暗，位置天然对齐。
    UIColor *skin = WXKBSkinColorFor(v);
    if (skin) {
        return skin;
    }
    if (!gKeyEnabled) {
        return nil;
    }
    switch (WXKBKindOf(v)) {
        case WXKBKeyKindLetter: {
            NSInteger idx = WXKBLetterIndex(v);
            return (idx != NSNotFound) ? WXKBLetterColorFor(idx) : gLetterBg;
        }
        case WXKBKeyKindDigit: {
            if (gDigitBg) return gDigitBg;
            // 未单独设置数字/符号键底色时沿用旧行为：按左右半区归功能键组
            UIView *win = v.window;
            CGFloat mid = win ? (win.bounds.size.width / 2.0) : 195.0;
            CGFloat cx = [v.superview convertPoint:CGPointMake(CGRectGetMidX(v.bounds),
                                                               CGRectGetMidY(v.bounds))
                                            toView:win].x;
            return (cx < mid) ? gFuncLBg : gFuncRBg;
        }
        case WXKBKeyKindFuncLeft:
            return gFuncLBg;
        case WXKBKeyKindFuncRight:
            return gFuncRBg;
        case WXKBKeyKindSpace:
            return gSpaceBg;
    }
    return nil;
}

static BOOL WXKBDarkMode(void) {
    if (@available(iOS 13.0, *)) {
        return ([UIScreen mainScreen].traitCollection.userInterfaceStyle
                    == UIUserInterfaceStyleDark);
    }
    return NO;
}

static UIColor *WXKBKeyText(void) {
    if (!(gEnabled && gKeyEnabled)) return nil;
    return WXKBDarkMode() ? (gTextColorDark ?: gTextColor) : gTextColor;
}

static UIColor *WXKBKeyHighlight(void) {
    if (!(gEnabled && gKeyEnabled)) return nil;
    return WXKBDarkMode() ? (gHighlightDark ?: gHighlight) : gHighlight;
}

#pragma mark - 键盘背景

static const NSInteger kWXKBBgViewTag = 0x57584247;   // "WXBG"

static void WXKBApplyBackground(UIView *host) {
    if (!host) {
        return;
    }
    UIView *bg = [host viewWithTag:kWXKBBgViewTag];
    if (!gEnabled || (!gBgEnabled && !gTransparent)) {
        if (bg) {
            [bg removeFromSuperview];
        }
        return;
    }

    if (!bg) {
        bg = [[UIView alloc] initWithFrame:host.bounds];
        bg.tag = kWXKBBgViewTag;
        bg.userInteractionEnabled = NO;
        bg.autoresizingMask =
            UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host insertSubview:bg atIndex:0];
    }
    bg.frame = host.bounds;
    bg.layer.masksToBounds = YES;
    bg.layer.contentsGravity = kCAGravityResizeAspectFill;

    UIImage *img = nil;
    if (gBgEnabled && gBgMode == 2) {
        if (gBgImageData.length) {
            img = [UIImage imageWithData:gBgImageData];
        }
        if (!img && gBgImage.length) {
            img = [UIImage imageWithContentsOfFile:gBgImage];
            if (!img && ![gBgImage hasPrefix:@"/var/jb"]) {
                img = [UIImage imageWithContentsOfFile:
                           [@"/var/jb" stringByAppendingString:gBgImage]];
            }
        }
    }
    if (img) {
        bg.backgroundColor = nil;
        bg.layer.contents = (__bridge id)img.CGImage;
    } else if (gBgEnabled) {
        bg.layer.contents = nil;
        bg.backgroundColor = gBgColor;
    } else {
        // 只开了整键盘透明：这一层保持全透
        bg.layer.contents = nil;
        bg.backgroundColor = [UIColor clearColor];
        bg.opaque = NO;
    }
}

#pragma mark - 编辑增强按钮

// —— 与宿主 App 的通信 ——
// 键盘扩展是独立进程，够不到宿主的 firstResponder，全选/剪切/粘贴/收起键盘
// 必须让 WxkbToolbar10Host（在宿主 App 里）代为执行。

static CFStringRef WXKBHostNotifyName(int code) {
    switch (code) {
        case WXKB_ACT_SELECT_ALL:   return CFSTR("com.yzdmm.wxkbtoolbar10/host/selectAll");
        case WXKB_ACT_CUT:          return CFSTR("com.yzdmm.wxkbtoolbar10/host/cut");
        case WXKB_ACT_PASTE:        return CFSTR("com.yzdmm.wxkbtoolbar10/host/paste");
        case WXKB_ACT_DELETE_ALL:   return CFSTR("com.yzdmm.wxkbtoolbar10/host/deleteAll");
        case WXKB_ACT_CLIPBOARD:    return CFSTR("com.yzdmm.wxkbtoolbar10/host/clipboard");
        case WXKB_ACT_PHRASES:      return CFSTR("com.yzdmm.wxkbtoolbar10/host/phrases");
        case WXKB_ACT_DISMISS:      return CFSTR("com.yzdmm.wxkbtoolbar10/host/dismiss");
        default:                    return NULL;
    }
}

static void WXKBAskHost(int code) {
    CFStringRef name = WXKBHostNotifyName(code);
    if (!name) return;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         name, NULL, NULL, YES);
}

// —— 扩展内能自己做的 ——

// 键盘扩展进程里没有「window.rootViewController == UIInputViewController」这种结构
// （frida 实测 UIInputViewController count == 0），所以老写法永远返回 nil。
// 真正的输入控制器挂在 WBRootInputView 的 nextResponder 链上，它就是键盘扩展的
// 主 UIInputViewController。沿这条链找到它，才能拿到 textDocumentProxy 与 .view；
// 否则光标左右 / 切换输入法 / 全删 全都得绕到宿主 App，而宿主又没实现光标左右
// （1.6.3 的坑：WXKBInputController 返回 nil → 光标按钮彻底无反应）。
static __weak UIInputViewController *gInputVC = nil;

// 键盘扩展的输入控制器可能是 WeType 自定义的 WBInputViewController，
// 它是 UIInputViewController 的子类，但为稳妥起见同时匹配类名包含 InputViewController。
static BOOL WXKBIsInputVC(id r) {
    if (!r) return NO;
    if ([r isKindOfClass:[UIInputViewController class]]) return YES;
    NSString *cls = NSStringFromClass([r class]);
    return [cls containsString:@"InputViewController"];
}

static UIInputViewController *WXKBResolveInputVC(void) {
    @try {
        Class rootCls = objc_getClass("WBRootInputView");
        UIApplication *app = [UIApplication sharedApplication];
        NSMutableArray *wins = [NSMutableArray array];
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in app.connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    [wins addObjectsFromArray:((UIWindowScene *)s).windows];
                }
            }
        }
        if (wins.count == 0) [wins addObjectsFromArray:app.windows];
        for (UIWindow *w in wins) {
            __block UIInputViewController *hit = nil;
            __block void (^walk)(UIView *);
            walk = ^(UIView *v) {
                if (hit || !v) return;
                if (rootCls && [v isKindOfClass:rootCls]) {
                    UIResponder *r = v.nextResponder;
                    while (r) {
                        if (WXKBIsInputVC(r)) {
                            hit = (UIInputViewController *)r;
                            return;
                        }
                        r = r.nextResponder;
                    }
                }
                for (UIView *s in v.subviews) walk(s);
            };
            walk(w);
            if (hit) return hit;
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
}

static UIInputViewController *WXKBInputController(void) {
    if (gInputVC && [gInputVC view]) return gInputVC;
    UIInputViewController *vc = WXKBResolveInputVC();
    if (vc) gInputVC = vc;
    return vc;
}

static id<UITextDocumentProxy> WXKBProxy(void) {
    UIInputViewController *vc = WXKBInputController();
    if (vc) {
        id<UITextDocumentProxy> p = [vc textDocumentProxy];
        if (p) return p;
    }
    return nil;
}

static void WXKBActCursorMove(NSInteger delta) {
    @try {
        id<UITextDocumentProxy> p = WXKBProxy();
        if (!p) { WXKBAskHost(WXKB_ACT_CURSOR_LEFT); return; }
        [p adjustTextPositionByCharacterOffset:delta];
    } @catch (__unused NSException *e) {
    }
}

static void WXKBActGlobe(void) {
    @try {
        UIInputViewController *vc = WXKBInputController();
        if (vc && [vc respondsToSelector:@selector(advanceToNextInputMode)]) {
            [vc advanceToNextInputMode];
            return;
        }
    } @catch (__unused NSException *e) {
    }
    // 扩展内切不动就交给宿主
    WXKBAskHost(WXKB_ACT_GLOBE);
}

// 光标位置未知时，全删退化成「把光标前的字全删掉」
static void WXKBActDeleteAllLocal(void) {
    @try {
        id<UITextDocumentProxy> p = WXKBProxy();
        if (!p) { WXKBAskHost(WXKB_ACT_DELETE_ALL); return; }
        NSString *before = [p documentContextBeforeInput] ?: @"";
        if (before.length == 0) return;
        for (NSInteger i = 0; i < (NSInteger)before.length; i++) {
            [p deleteBackward];
        }
    } @catch (__unused NSException *e) {
        WXKBAskHost(WXKB_ACT_DELETE_ALL);
    }
}

// —— 按钮动作触发 ——
// 由于我们把按钮塞进了微信原生滚动视图，且微信可能在工具栏层自管触摸 / 挂手势，
// 单纯给按钮 addTarget 经常收不到事件。这里统一用 WXKBFireAction 派发，
// 并在滚动视图上挂一个「只识别点按、不拦截触摸」的 UITapGestureRecognizer
// 来触发（见下方 WXKBInstallTap）。
static void WXKBFireAction(int c) {
    @try {
        switch (c) {
            case WXKB_ACT_CURSOR_LEFT:  WXKBActCursorMove(-1); break;
            case WXKB_ACT_CURSOR_RIGHT: WXKBActCursorMove(1);  break;
            case WXKB_ACT_GLOBE:        WXKBActGlobe();        break;
            case WXKB_ACT_DELETE_ALL:   WXKBActDeleteAllLocal(); break;
            // 其余必须回宿主 App
            case WXKB_ACT_SELECT_ALL:
            case WXKB_ACT_CUT:
            case WXKB_ACT_PASTE:
            case WXKB_ACT_CLIPBOARD:
            case WXKB_ACT_PHRASES:
            case WXKB_ACT_DISMISS:
                WXKBAskHost(c);
                break;
            default: break;
        }
    } @catch (__unused NSException *e) {
    }
}

#pragma mark - Hooks

%hook WBFunctionToolBar

- (BOOL)updateFuncs:(NSArray *)funcs suggestedTypes:(NSArray *)types prefersRecent:(BOOL)prefersRecent {
    // 工具栏功能（增删 / 排序）交由微信原生「定制工具栏」处理：原样透传，
    // 不拦截、不重排，避免与微信自身布局冲突（1.6.16 强改按钮位置曾导致键盘扩展崩溃）。
    NSArray *f = funcs;
    return %orig(f, types, prefersRecent);
}

- (BOOL)updateViewWithFuncs:(NSArray *)funcs {
    NSArray *f = funcs;
    return %orig(f);
}

- (BOOL)updateFuncs:(NSArray *)funcs {
    NSArray *f = funcs;
    return %orig(f);
}

// 关键：永远不缩小。图标保持原生尺寸，溢出交给横向滑动，避免挤成一团。
- (void)setShrunken:(BOOL)shrunken animated:(BOOL)animated completion:(id)completion {
    %orig(NO, animated, completion);
}

- (void)layoutSubviews {
    %orig;
    WXKBFixScroll(self);
    WXKBScheduleSync();
}

%end

// WBTopBar 承载候选栏与工具栏；在它自身布局完成后重定位工具栏，避免被原生布局改回 x=102。
%hook WBTopBar

- (void)layoutSubviews {
    %orig;
    WXKBFillRow(self);
}

%end

%hook WBKeyView

- (void)layoutSubviews {
    %orig;
    WXKBApplyCorner(self);
}

- (UIColor *)normalBgColorForCurrentState {
    UIColor *c = WXKBKeyBackground(self);
    if (c) return c;
    return %orig;
}

- (UIColor *)backgroundColorForCurrentState {
    UIColor *c = WXKBKeyBackground(self);
    if (c) return c;
    return %orig;
}

- (UIColor *)highlightedBgForCurrentState {
    UIColor *c = WXKBKeyHighlight();
    if (c) return c;
    return %orig;
}

- (UIColor *)tintColorForCurrentState {
    UIColor *c = WXKBKeyText();
    if (c) return c;
    return %orig;
}

- (UIColor *)normalTintColorForCurrentState {
    UIColor *c = WXKBKeyText();
    if (c) return c;
    return %orig;
}

- (UIColor *)subTintColorForCurrentState {
    UIColor *c = WXKBKeyText();
    if (c) return c;
    return %orig;
}

%end

%hook WBRuleKeyView

- (void)layoutSubviews {
    %orig;
    WXKBApplyCorner(self);
}

- (UIColor *)normalBgColorForCurrentState {
    UIColor *c = WXKBKeyBackground(self);
    if (c) return c;
    return %orig;
}

- (UIColor *)highlightedBgForCurrentState {
    UIColor *c = WXKBKeyHighlight();
    if (c) return c;
    return %orig;
}

%end

%hook WBReturnKeyView

- (void)layoutSubviews {
    %orig;
    WXKBApplyCorner(self);
}

- (UIColor *)normalBgColorForCurrentState {
    UIColor *c = WXKBKeyBackground(self);
    if (c) return c;
    return %orig;
}

- (UIColor *)highlightedBgForCurrentState {
    UIColor *c = WXKBKeyHighlight();
    if (c) return c;
    return %orig;
}

- (UIColor *)normalTintColorForCurrentState {
    UIColor *c = WXKBKeyText();
    if (c) return c;
    return %orig;
}

- (UIColor *)highlightedTintColorForCurrentState {
    UIColor *c = WXKBKeyText();
    if (c) return c;
    return %orig;
}

%end

// 键盘根视图：插入一层不拦截触摸的背景视图，纯色/图片都画在这里
%hook WBRootInputView

- (void)layoutSubviews {
    %orig;
    WXKBApplyBackground(self);
    WXKBApplyTransparency(self);

    // 位移作用在最上层「输入视图控制器.view」上：它是键盘扩展视图树的顶点，
    // 没有裁剪容器，整体平移后整块键盘都会跟着动（1.6.3 作用在内部
    // WBRootInputView，被它的容器裁掉，所以「没效果」）。
    // 真正的输入控制器就挂在 self 的 nextResponder 链上，直接取最快也最准；
    // 它可能是 WeType 自定义的 WBInputViewController（UIInputViewController 子类）。
    UIView *me = (UIView *)self;
    UIInputViewController *ivc = nil;
    UIResponder *nr = me.nextResponder;
    while (nr) {
        if (WXKBIsInputVC(nr)) {
            ivc = (UIInputViewController *)nr;
            break;
        }
        nr = nr.nextResponder;
    }
    if (ivc) {
        gInputVC = ivc;
        if (ivc.view) {
            WXKBApplyOffset(ivc.view);
            // 清掉作用在自身上的位移残留，避免双重位移
            if (me.transform.tx != 0.0 || me.transform.ty != 0.0) {
                me.transform = CGAffineTransformIdentity;
            }
        }
    } else {
        // 兜底：拿不到控制器就把位移压在自己身上
        WXKBApplyOffset(me);
    }
    WXKBScheduleSync();
}

%end

%hook WBMainInputView

- (void)layoutSubviews {
    %orig;
    if (!objc_getClass("WBRootInputView")) {
        WXKBApplyBackground(self);
    }
}

%end

// 键盘每次弹出时强制重读偏好，改完设置收起键盘再弹出即可生效
%hook WBKeyboardView

- (void)didAttachHosting {
    %orig;
    WXKBReload(YES);
    WXKBScheduleSync();
}

%end

%ctor {
    WXKBReload(YES);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, WXKBOnPrefsChanged,
                                    CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    NSLog(@"[WxkbToolbar10] 1.7.1 loaded enabled=%d bg=%d trans=%d key=%d grad=%d shape=%d cap3d=%d corner=%.1f offset=%.1f skin=%d",
          gEnabled, gBgEnabled, gTransparent, gKeyEnabled,
          gGradEnabled, gShape, gCap3D, gCorner, gKbOffset, gSkinEnabled);
}