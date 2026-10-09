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

@interface WBCCFuncItem : UIControl
@end

@interface WBPasteboardHotWordShellView : UIView
@end

@interface WBPasteboardListView : UIView
@end

@interface WBPasteboardImageDetailView : UIView
@end

@interface WBTopBarTipsView : UIView
@end

@interface WBBaseToast : UIView
@end

@interface WBToastView : UIView
@end

@interface WBToastView2 : UIView
@end

@interface WBModernToast : UIView
@end

@interface WBCommonPanelView : UIView
@end

@interface WBSubPanelView : UIView
@end

@interface WBNetworkAlertView : UIView
@end

@interface WBCandidateExpandView : UIView
@end

@interface WBCandidateView : UIView
@end

@interface WBCandidateCell : UIView
@end

@interface WBTextItemLabel : UILabel
@end

@interface WBCorrectionNoticeView : UIView
@end

@interface WBRewriteNoticeView : UIView
@end

@interface WBAskAIToast : UIView
@end

@interface WBPasteboardServiceContent : UIView
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
static NSInteger  gSkinBg       = 0;     // 皮肤背景：0白底 1全透明 2灰色 3白50%
static NSInteger  gSkinTheme    = 0;     // 主题族：0百度彩虹 1彩虹 2马卡龙 3蜜桃 4薄荷 5暮紫 6海蓝 7落日 8森系
static NSInteger  gSkinDir      = 0;     // 变色方向：0横向 1竖向 2斜向（2.3.9）
static NSString *gSkinName     = nil;    // 皮肤名（当前固定 rainbow）
static NSInteger gCapStyle     = 0;      // 键帽风格（单选）：0=关闭 1=立体 2=彩虹 3=彩虹3D 4=玻璃态 5=霓虹
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
    id sb = d[WXKB_KEY_SKIN_BG];
    NSInteger sbv = sb ? [sb integerValue] : 0;
    if (sbv < 0 || sbv > 3) sbv = 0;
    gSkinBg = sbv;
    id sn = d[WXKB_KEY_SKIN_NAME];
    gSkinName = ([sn isKindOfClass:[NSString class]] && [sn length]) ? sn : @"rainbow";
    id stt = d[WXKB_KEY_SKIN_THEME];
    NSInteger stv = stt ? [stt integerValue] : 0;
    if (stv < 0 || stv > 31) stv = 0;
    gSkinTheme = stv;
    id sd = d[WXKB_KEY_SKIN_DIR];
    NSInteger sdv = sd ? [sd integerValue] : 0;
    if (sdv < 0 || sdv > 2) sdv = 0;
    gSkinDir = sdv;

    gCapStyle = [d[WXKB_KEY_CAP_STYLE] integerValue];

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

// 正六边形路径：保证六条边长度相等，以较短边为基准计算边长，
// 方向为"横扁"（左右两个顶点，上下两条水平边），契合键盘按键宽>高的比例，
// 视觉上是蜂窝形键帽，完整落在按键矩形内。
static UIBezierPath *WXKBHexagonPath(CGSize s) {
    CGFloat w = s.width, h = s.height;
    if (w <= 0 || h <= 0) return nil;
    CGFloat cx = w / 2.0, cy = h / 2.0;
    // 正六边形（横扁方向）：
    //   顶点数：6，边长 a
    //   宽度（两顶点距离）= 2a
    //   高度（两平行边距离）= a * sqrt(3) ≈ 1.732a
    // 取较短边决定边长 a，保证六边形完整落在矩形内。
    CGFloat a;  // 边长
    if (w * 0.866025403784439 <= h) {
        // 矩形偏宽：受高度限制 → h = a * sqrt(3) → a = h / sqrt(3)
        a = h * 0.577350269189626;
    } else {
        // 矩形偏高：受宽度限制 → w = 2a → a = w / 2
        a = w / 2.0;
    }
    CGFloat halfW = a;                       // 水平半宽 = a
    CGFloat halfH = a * 0.866025403784439;   // 垂直半高 = a * sin(60°)
    // 六个顶点，从最上面左边那个开始顺时针
    CGPoint pts[6];
    pts[0] = CGPointMake(cx - halfW * 0.5, cy - halfH);   // 左上
    pts[1] = CGPointMake(cx + halfW * 0.5, cy - halfH);   // 右上
    pts[2] = CGPointMake(cx + halfW,       cy);           // 右顶点
    pts[3] = CGPointMake(cx + halfW * 0.5, cy + halfH);   // 右下
    pts[4] = CGPointMake(cx - halfW * 0.5, cy + halfH);   // 左下
    pts[5] = CGPointMake(cx - halfW,       cy);           // 左顶点
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:pts[0]];
    for (int i = 1; i < 6; i++) [p addLineToPoint:pts[i]];
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

// 键帽形状统一路径生成（0 圆角由调用方按动态圆角处理；1..11 由本函数生成固定形状）：
// 1 圆形 / 2 六边形 / 3 水珠 / 4 椭圆 / 5 菱形 / 6 五边形 / 7 星形 /
// 8 心形 / 9 药丸 / 10 半圆 / 11 圆角方
static UIBezierPath *WXKBShapePath(NSInteger shape, CGSize s) {
    CGFloat w = s.width, h = s.height;
    if (w <= 0 || h <= 0) return nil;
    CGFloat cx = w / 2.0, cy = h / 2.0;
    UIBezierPath *p = [UIBezierPath bezierPath];
    switch (shape) {
        case 1:  // 圆形
            return [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, w, h)];
        case 2:  // 六边形
            return WXKBHexagonPath(s);
        case 3:  // 水珠
            return WXKBWaterDropPath(s);
        case 4: {  // 椭圆（略扁）
            CGFloat ew = w * 0.98, eh = h * 0.86;
            return [UIBezierPath bezierPathWithOvalInRect:
                        CGRectMake((w - ew) / 2.0, (h - eh) / 2.0, ew, eh)];
        }
        case 5: {  // 菱形
            CGPoint pts[4] = { CGPointMake(cx, h * 0.06), CGPointMake(w * 0.94, cy),
                               CGPointMake(cx, h * 0.94), CGPointMake(w * 0.06, cy) };
            [p moveToPoint:pts[0]];
            for (int i = 1; i < 4; i++) [p addLineToPoint:pts[i]];
            [p closePath]; return p;
        }
        case 6: {  // 五边形（正）
            NSInteger n = 5; CGFloat R = MIN(w, h) / 2.0 * 0.98;
            for (int i = 0; i < n; i++) {
                double ang = -1.570796326794897 + i * 2 * 3.141592653589793 / n;
                CGPoint pt = CGPointMake(cx + R * cos(ang), cy + R * sin(ang));
                if (i == 0) [p moveToPoint:pt]; else [p addLineToPoint:pt];
            }
            [p closePath]; return p;
        }
        case 7: {  // 星形（五芒）
            NSInteger n = 5; CGFloat Ro = MIN(w, h) / 2.0 * 0.98, Ri = Ro * 0.45;
            for (int i = 0; i < n * 2; i++) {
                double ang = -1.570796326794897 + i * 3.141592653589793 / n;
                CGFloat rr = (i % 2 == 0) ? Ro : Ri;
                CGPoint pt = CGPointMake(cx + rr * cos(ang), cy + rr * sin(ang));
                if (i == 0) [p moveToPoint:pt]; else [p addLineToPoint:pt];
            }
            [p closePath]; return p;
        }
        case 8: {  // 心形（参数方程采样）
            NSInteger N = 72; CGFloat sc = MIN(w, h) / 32.0;
            for (int i = 0; i < N; i++) {
                double tt = 2.0 * 3.141592653589793 * i / (N - 1);
                double hx = 16.0 * pow(sin(tt), 3.0);
                double hy = 13.0 * cos(tt) - 5.0 * cos(2 * tt)
                          - 2.0 * cos(3 * tt) - cos(4 * tt);
                CGPoint pt = CGPointMake(cx + hx * sc * 0.5,
                                        cy - hy * sc * 0.5 + h * 0.14);
                if (i == 0) [p moveToPoint:pt]; else [p addLineToPoint:pt];
            }
            [p closePath]; return p;
        }
        case 9:  // 药丸（横向胶囊）
            return [UIBezierPath bezierPathWithRoundedRect:
                        CGRectMake(w * 0.02, h * 0.06, w * 0.96, h * 0.88)
                                                 cornerRadius:h * 0.44];
        case 10: { // 半圆（平边在下）
            CGFloat r = MIN(w, h) / 2.0 * 0.98;
            [p moveToPoint:CGPointMake(cx - r, cy)];
            [p addArcWithCenter:CGPointMake(cx, cy) radius:r
                     startAngle:3.141592653589793 endAngle:0.0 clockwise:NO];
            [p closePath]; return p;
        }
        case 11: // 圆角方（小圆角）
            return [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, w, h)
                                                 cornerRadius:MIN(w, h) * 0.18];
        default:  // 兜底：圆角矩形
            return [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, w, h)
                                                 cornerRadius:MIN(w, h) / 2.0];
    }
}

static UIColor *WXKBSkinCanvasColor(void);  // 前向声明（皮肤画布底色，定义在下方皮肤块）

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
    } else {                                // 六边形 / 水珠 / 其它形状
        target.layer.cornerRadius = 0;
        CAShapeLayer *mask = objc_getAssociatedObject(target, kWXKBMaskLayerKey);
        if (!mask) {
            mask = [CAShapeLayer layer];
            objc_setAssociatedObject(target, kWXKBMaskLayerKey, mask,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            target.layer.mask = mask;
        }
        UIBezierPath *path = (shape >= 2) ? WXKBShapePath(shape, sz)
                                          : WXKBHexagonPath(sz);
        mask.path = path.CGPath;
    }
}

static void WXKBApplyCorner(UIView *v);
static UIColor *WXKBKeyBackground(WBKeyView *v);
static NSInteger WXKBLetterIndex(WBKeyView *v);

// —— 立体键帽（真实电脑键盘风）——
// 每颗键渲染成一颗真键帽：① 深色「键体」铺满轮廓 = 侧壁/前脸；② 在键体内**内缩一圈**的
// 凸起「顶面」（上亮下暗穹顶渐变） = 键帽被抬起、四周露出侧壁；③ 正下方再伸出一截侧壁，
// 给有空隙/透明键盘时的真实厚度；④ v 上投一道柔和阴影，整颗键像浮在底板上。
// 全部是附加图层、不动布局（不碰 frame/约束、不碰文字），规避 1.6.16 那类崩溃。

static const void *kWXKBCapLayerKey = &kWXKBCapLayerKey;   // 伸出底部的侧壁
static const void *kWXKBCapBodyKey  = &kWXKBCapBodyKey;    // 键体（深色侧壁/前脸）
static const void *kWXKBCapTopKey   = &kWXKBCapTopKey;     // 凸起顶面（穹顶渐变）
static const void *kWXKBCapSkirtKey = &kWXKBCapSkirtKey;   // 1.8.0 侧壁裙边渐变
static const void *kWXKBCapEdgeKey  = &kWXKBCapEdgeKey;    // 1.8.0 轮廓硬描边

// 键帽风格：0 关 / 1 立体键帽（电脑键盘风：深色裙边+近黑描边）/
// 2 彩虹键盘帽（1.9.0：浅色裙边+柔和阴影）/
// 3 彩虹3D键帽（2.1.0：百度彩虹按键同款，粉彩配色+明显3D深度）/
// 4 玻璃态（2.2.0：半透明+模糊+高光）/
// 5 霓虹（2.2.0：深色背景+发光边缘）。
// 单选：一次只能开一种，由 capStyle 偏好决定。
static NSInteger WXKBCapStyle(void) {
    if (!gEnabled) return 0;
    if (gCapStyle < 0 || gCapStyle > 11) return 0;
    if (gSkinEnabled && gCapStyle == 0) return 3;  // 皮肤默认 = 彩虹3D
    return gCapStyle;
}

static void WXKBApplyCap(UIView *v, UIView *leaf) {
    UIView *target = leaf ?: v;
    CAShapeLayer *wall = objc_getAssociatedObject(v, kWXKBCapLayerKey);
    CAShapeLayer *body = objc_getAssociatedObject(target, kWXKBCapBodyKey);
    CAGradientLayer *top  = objc_getAssociatedObject(target, kWXKBCapTopKey);
    CAGradientLayer *skirt = objc_getAssociatedObject(target, kWXKBCapSkirtKey);
    CAShapeLayer *edge  = objc_getAssociatedObject(target, kWXKBCapEdgeKey);
    // 1.7.5：皮肤模式隐含启用立体键帽渲染——穹顶明暗从皮肤底色推导，
    // 取代退役的 CGImage 贴图路线（见 WXKBApplySkin 注释）。
    if (!gEnabled || WXKBCapStyle() == 0) {
        if (wall)  { [wall removeFromSuperlayer];  objc_setAssociatedObject(v, kWXKBCapLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (body)  { [body removeFromSuperlayer];  objc_setAssociatedObject(target, kWXKBCapBodyKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (top)   { [top  removeFromSuperlayer];  objc_setAssociatedObject(target, kWXKBCapTopKey,   nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (skirt) { [skirt removeFromSuperlayer]; objc_setAssociatedObject(target, kWXKBCapSkirtKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        if (edge)  { [edge removeFromSuperlayer];  objc_setAssociatedObject(target, kWXKBCapEdgeKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
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

    // 2.2.8 实际生效的形状：六边形/水珠只用于正方形键，长矩形键回退为圆角
    CGFloat ratio = (sz.height > 1) ? sz.width / sz.height : 1.0;
    if (ratio < 0) ratio = -ratio;
    BOOL isSquareish = (ratio >= 0.75 && ratio <= 1.35);
    NSInteger effShape = gShape;
    if (gShape >= 2 && !isSquareish) effShape = 0;  // 长键：降级为普通圆角

    NSInteger capStyle = WXKBCapStyle();
    CGFloat kDepth = 4.0;                   // 底部伸出厚度
    CGFloat kInset = 4.0;                   // 顶面左右内缩（露出侧壁裙边）
    CGFloat kFront = 7.0;                   // 顶面底部上抬（露出前脸）
    CGFloat topY   = 2.5;                   // 顶部裙边
    if (capStyle == 2) {                    // 彩虹键盘帽：裙边更薄、前脸更高、观感更圆润
        kInset = 3.0;
        kFront = 8.0;
        topY   = 2.0;
    } else if (capStyle == 3) {             // 彩虹3D键帽：百度同款，实体键盘深度
        kDepth = 7.0;                       // 更厚的底部伸出（实体键盘感）
        kInset = 4.5;                       // 更大的侧壁内缩（露出更多侧壁）
        kFront = 8.0;                       // 更高的前脸（立体感更强）
        topY   = 2.5;                       // 顶部裙边
    } else if (capStyle == 4) {             // 卡通手绘：大圆角 + 柔和弧面 + 浮起阴影
        kDepth = 4.0;                       // 底部投影深度
        kInset = 2.5;                       // 侧壁内缩（柔和）
        kFront = 5.0;                       // 前脸高度
        topY   = 2.0;                       // 顶部裙边
    } else if (capStyle == 5) {             // 霓虹：明显凸起 + 发光边缘
        kDepth = 5.0;
        kInset = 3.0;
        kFront = 6.0;
        topY   = 2.0;
    } else if (capStyle >= 6 && capStyle <= 11) {
        // 6 磨砂 / 7 镜面 / 8 描边 / 9 软萌 / 10 极简 / 11 双色：几何随风格微调
        NSInteger v = capStyle - 6;
        if      (v == 1) { kDepth = 5.0; kInset = 3.0; kFront = 6.0; topY = 2.0; }
        else if (v == 3) { kDepth = 4.0; kInset = 2.5; kFront = 5.0; topY = 2.0; }
        else if (v == 5) { kDepth = 5.0; kInset = 2.5; kFront = 6.0; topY = 2.0; }
        else            { kDepth = 4.0; kInset = 4.0; kFront = 7.0; topY = 2.0; }
    }
    CGFloat rad = 5.0;
    if (gShape == 0) {
        rad = target.layer.cornerRadius;
        if (gCorner > 0.01) rad = gCorner;
        rad = MIN(rad, MIN(sz.width, sz.height) / 2.0);
        if (rad <= 0.5) rad = 5.0;
    }
    if (capStyle == 3 && gShape == 0) {
        // 彩虹3D：圆角适中（百度同款，约键高 1/6）
        rad = MAX(rad, MIN(sz.width, sz.height) * 0.18);
        rad = MIN(rad, MIN(sz.width, sz.height) * 0.30);
    } else if (capStyle == 4 && gShape == 0) {
        // 卡通手绘：大圆角（约键高 1/3）
        rad = MAX(rad, MIN(sz.width, sz.height) * 0.30);
        rad = MIN(rad, MIN(sz.width, sz.height) * 0.45);
    } else if (capStyle == 5 && gShape == 0) {
        // 霓虹：圆角适中
        rad = MAX(rad, MIN(sz.width, sz.height) * 0.20);
        rad = MIN(rad, MIN(sz.width, sz.height) * 0.35);
    }

    // 取按键底色：优先用我们的配色（含彩虹/数字分组），否则取原生背景叶颜色
    UIColor *base = WXKBKeyBackground((WBKeyView *)v);
    if (!base) {
        CGColorRef cg = target.layer.backgroundColor ?: v.layer.backgroundColor;
        if (cg) base = [UIColor colorWithCGColor:cg];
    }

    // 由底色推导键帽各段色（高光 / 亮面 / 正面 / 下缘 / 前面 + 1.8.0 侧壁裙边两档）
    CGFloat h = 0, s = 0, br = 0.9, al = 0;
    UIColor *cHi, *cLight, *cFace, *cLow, *cFront, *cWallHi, *cWallLo;
    if (base && [base getHue:&h saturation:&s brightness:&br alpha:&al] && s > 0.02) {
        cHi     = [UIColor colorWithHue:h saturation:MAX(s * 0.30, 0.0) brightness:MIN(br * 1.35 + 0.34, 1.0) alpha:1.0];
        cLight  = [UIColor colorWithHue:h saturation:s brightness:MIN(br * 1.14, 1.0) alpha:1.0];
        cFace   = [UIColor colorWithHue:h saturation:s brightness:br alpha:1.0];
        cLow    = [UIColor colorWithHue:h saturation:s brightness:br * 0.78 alpha:1.0];
        cFront  = [UIColor colorWithHue:h saturation:MIN(s * 1.25, 1.0) brightness:br * 0.46 alpha:1.0];
        // 1.8.0 电脑键盘风侧壁：大幅去饱和 + 明暗两档 → 穹顶四周一圈中性深色裙边
        cWallHi = [UIColor colorWithHue:h saturation:s * 0.30 brightness:MAX(br * 0.60, 0.30) alpha:1.0];
        cWallLo = [UIColor colorWithHue:h saturation:MIN(s * 0.55, 1.0) brightness:MAX(br * 0.30, 0.14) alpha:1.0];
    } else {
        CGFloat w = (base) ? br : 0.78;
        if (base) { CGFloat a0 = 0; if (![base getWhite:&w alpha:&a0]) w = br; }
        cHi     = [UIColor colorWithWhite:MIN(w * 1.30 + 0.22, 1.0) alpha:1.0];
        cLight  = [UIColor colorWithWhite:MIN(w * 1.12, 1.0) alpha:1.0];
        cFace   = [UIColor colorWithWhite:w alpha:1.0];
        cLow    = [UIColor colorWithWhite:w * 0.82 alpha:1.0];
        cFront  = [UIColor colorWithWhite:w * 0.46 alpha:1.0];
        cWallHi = [UIColor colorWithWhite:MAX(w * 0.68, 0.42) alpha:1.0];
        cWallLo = [UIColor colorWithWhite:MAX(w * 0.36, 0.16) alpha:1.0];
    }
    // 键帽外观：
    // 1 立体键帽 = 近黑硬描边 + 深色裙边
    // 2 彩虹键盘帽 = 浅灰白裙边 + 极淡描边
    // 3 彩虹3D键帽 = 粉彩键面 + 明显侧壁 + 柔和渐变 + 极淡描边
    // 4 玻璃态 = 半透明 + 模糊 + 高光
    // 5 霓虹 = 深色背景 + 发光边缘
    UIColor *cEdge;
    if (capStyle == 3) {
        // 彩虹3D：实体键盘键帽，侧壁同色系稍暗（真实键盘感）
        cWallHi = [UIColor colorWithHue:h saturation:MIN(s * 1.05, 1.0) brightness:MAX(br * 0.78, 0.50) alpha:1.0];
        cWallLo = [UIColor colorWithHue:h saturation:MIN(s * 1.15, 1.0) brightness:MAX(br * 0.62, 0.38) alpha:1.0];
        cEdge   = [UIColor colorWithHue:h saturation:MIN(s * 1.20, 1.0) brightness:MAX(br * 0.50, 0.30) alpha:0.40];
        cHi     = [UIColor colorWithHue:h saturation:MAX(s * 0.50, 0.0) brightness:MIN(br * 1.35 + 0.20, 1.0) alpha:1.0];
        cLow    = [UIColor colorWithHue:h saturation:MIN(s * 1.10, 1.0) brightness:br * 0.65 alpha:1.0];
    } else if (capStyle == 4) {
        // 卡通手绘：无硬描边 + 柔和侧壁 + 顶部微弱高光
        cWallHi = [UIColor colorWithHue:h saturation:MIN(s * 1.05, 1.0) brightness:MAX(br * 0.85, 0.55) alpha:1.0];
        cWallLo = [UIColor colorWithHue:h saturation:MIN(s * 1.10, 1.0) brightness:MAX(br * 0.70, 0.45) alpha:1.0];
        cEdge   = [UIColor colorWithWhite:0.0 alpha:0.0];  // 无描边
        cHi     = [UIColor colorWithHue:h saturation:MAX(s * 0.40, 0.0) brightness:MIN(br * 1.25 + 0.15, 1.0) alpha:1.0];
        cLow    = [UIColor colorWithHue:h saturation:MIN(s * 1.05, 1.0) brightness:br * 0.80 alpha:1.0];
    } else if (capStyle == 5) {
        // 霓虹：深色键面 + 发光侧壁 + 强描边
        cWallHi = [UIColor colorWithHue:h saturation:1.0 brightness:0.90 alpha:1.0];
        cWallLo = [UIColor colorWithHue:h saturation:1.0 brightness:0.60 alpha:1.0];
        cEdge   = [UIColor colorWithHue:h saturation:1.0 brightness:1.0 alpha:0.80];
        cHi     = [UIColor colorWithHue:h saturation:0.80 brightness:0.30 alpha:1.0];
        cLow    = [UIColor colorWithHue:h saturation:1.0 brightness:0.15 alpha:1.0];
        cFace   = [UIColor colorWithHue:h saturation:0.90 brightness:0.20 alpha:1.0];
    } else if (capStyle == 2) {
        cWallHi = [UIColor colorWithWhite:0.985 alpha:1.0];
        cWallLo = [UIColor colorWithWhite:0.800 alpha:1.0];
        cEdge   = [UIColor colorWithWhite:0.60 alpha:0.30];
        cHi     = cLight;   // 穹顶顶部 = 提亮的键面（柔和高光）
        cLow    = cFace;    // 穹顶底部 = 键面本身（轻微压暗，替代强明暗）
    } else if (capStyle >= 6 && capStyle <= 11) {
        // 6 磨砂 / 7 镜面 / 8 描边 / 9 软萌 / 10 极简 / 11 双色
        NSInteger v = capStyle - 6;
        if      (v == 0) { cHi = cLight; }                                  // 磨砂：弱高光
        else if (v == 1) { cHi = [UIColor colorWithWhite:1.0 alpha:1.0]; }  // 镜面：强高光
        else if (v == 4) { cHi = cLight; cLow = cFace; }                     // 极简：平顶
        if      (v == 2) cEdge = [UIColor colorWithWhite:0.08 alpha:0.95];   // 描边：更黑更粗
        else if (v == 3) cEdge = [UIColor colorWithWhite:0.0 alpha:0.0];     // 软萌：无描边
        else if (v == 4) cEdge = [UIColor colorWithWhite:0.25 alpha:0.6];    // 极简：细描边
        else if (v == 5) cEdge = [UIColor colorWithHue:h saturation:MIN(s * 1.2, 1.0) brightness:1.0 alpha:0.8]; // 双色：彩边
        else             cEdge = [UIColor colorWithWhite:0.18 alpha:0.92];
    } else {
        cEdge = [UIColor colorWithWhite:0.18 alpha:0.92];
    }

    // 轮廓按各自坐标系生成：键体/顶面按背景叶尺寸 tbsz（与 layer 坐标一致），
    // 伸出侧壁按按键尺寸 sz（要覆盖整颗键并向下凸出）
    UIBezierPath *silLeaf = nil;
    if (effShape == 0) {
        silLeaf = [UIBezierPath bezierPathWithRoundedRect:
                       CGRectMake(0, 0, tbsz.width, tbsz.height) cornerRadius:rad];
    } else {
        if (effShape == 1) rad = MIN(tbsz.width, tbsz.height) / 2.0;
        silLeaf = WXKBShapePath(effShape, tbsz);
    }
    if (!silLeaf) return;

    // 凸起顶面轮廓：圆角/圆形左右缩 kInset、顶部微缩、底部上抬 kFront（露出高前脸）；
    // 六边形/水珠按比例缩 0.88
    UIBezierPath *topPath;
    if (effShape >= 1) {
        topPath = [silLeaf copy];
        CGFloat cx = tbsz.width / 2.0, cy = tbsz.height / 2.0;
        CGAffineTransform t = CGAffineTransformMakeTranslation(cx, cy);
        t = CGAffineTransformConcat(CGAffineTransformMakeScale(0.88, 0.88), t);
        t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(-cx, -cy));
        [topPath applyTransform:t];
    } else {
        CGFloat rr;
        if (capStyle == 3) {
            rr = rad;                           // 马卡龙：顶面=整颗键面，圆角随轮廓
        } else if (capStyle == 4) {
            rr = MAX(rad * 0.85, 3.5);          // 彩虹3D：顶面圆角稍大，接近轮廓
        } else {
            rr = MAX(rad * 0.8, 3.0);           // 顶面圆角随轮廓走，别被内缩吃掉
        }
        CGFloat botY = kInset + kFront;     // 底部多抬一截 → 前脸更高
        topPath = [UIBezierPath bezierPathWithRoundedRect:
                       CGRectMake(kInset, topY, tbsz.width - 2 * kInset,
                                  tbsz.height - topY - botY) cornerRadius:rr];
    }

    // 伸出底部的侧壁：整颗键轮廓（sz）下移 kDepth
    UIBezierPath *silWall = nil;
    if (effShape == 0) {
        silWall = [UIBezierPath bezierPathWithRoundedRect:
                       CGRectMake(0, 0, sz.width, sz.height) cornerRadius:rad];
    } else {
        silWall = WXKBShapePath(effShape, sz);
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
    body.fillColor = cWallLo.CGColor;
    body.zPosition = -998;

    // ①' 1.8.0 侧壁裙边渐变：铺满整颗轮廓的上亮下暗中性深色，替代旧版单色前脸，
    //     穹顶四周（左/右/上/下）都露出立体裙边 = 真实键帽的斜面侧壁
    if (!skirt) {
        skirt = [CAGradientLayer layer];
        skirt.name = @"wxkb_cap_skirt";
        objc_setAssociatedObject(target, kWXKBCapSkirtKey, skirt, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [target.layer insertSublayer:skirt atIndex:0];
    }
    skirt.frame = CGRectMake(0, 0, tbsz.width, tbsz.height);
    skirt.startPoint = CGPointMake(0.5, 0.0);
    skirt.endPoint   = CGPointMake(0.5, 1.0);
    skirt.colors = @[(id)cWallHi.CGColor, (id)cWallLo.CGColor];
    CAShapeLayer *smask = [CAShapeLayer layer];
    smask.path = silLeaf.CGPath;
    skirt.mask = smask;
    skirt.zPosition = -997.5;
    skirt.hidden = (capStyle == 3) || (capStyle == 8);

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
    if (capStyle == 3) {
        // 彩虹3D：实体键盘强渐变（高光 → 键面 → 底部明显压暗）
        top.locations = @[@0.0, @0.15, @0.70, @1.0];
        top.colors = @[(id)cHi.CGColor, (id)cFace.CGColor, (id)cFace.CGColor, (id)cLow.CGColor];
    } else if (capStyle == 4) {
        // 卡通手绘：柔和弧面渐变（顶部微弱高光 → 键面 → 底部轻微压暗）
        top.locations = @[@0.0, @0.25, @0.75, @1.0];
        top.colors = @[(id)cHi.CGColor, (id)cFace.CGColor, (id)cFace.CGColor, (id)cLow.CGColor];
    } else if (capStyle == 5) {
        // 霓虹：暗键面 → 底部微亮（模拟发光）
        top.locations = @[@0.0, @0.30, @0.70, @1.0];
        top.colors = @[(id)cHi.CGColor, (id)cFace.CGColor, (id)cFace.CGColor, (id)cLow.CGColor];
    } else if (capStyle == 2) {
        // 彩虹键盘帽：柔和两段式（亮面 → 键面），不要强高光带
        top.locations = @[@0.0, @0.45, @0.85, @1.0];
        top.colors = @[(id)cHi.CGColor, (id)cFace.CGColor, (id)cFace.CGColor, (id)cLow.CGColor];
    } else if (capStyle >= 6 && capStyle <= 11) {
        if (capStyle == 10) {   // 极简：平顶
            top.locations = @[@0.0, @0.5, @0.5, @1.0];
            top.colors = @[(id)cLight.CGColor, (id)cLight.CGColor, (id)cFace.CGColor, (id)cFace.CGColor];
        } else {
            top.locations = @[@0.0, @0.12, @0.55, @1.0];
            top.colors = @[(id)cHi.CGColor, (id)cLight.CGColor, (id)cFace.CGColor, (id)cLow.CGColor];
        }
    } else {
        top.locations = @[@0.0, @0.12, @0.55, @1.0];  // 高光带加宽 → 顶部近白的穹顶感
        top.colors = @[(id)cHi.CGColor, (id)cLight.CGColor, (id)cFace.CGColor, (id)cLow.CGColor];
    }
    CAShapeLayer *tmask = [CAShapeLayer layer];
    tmask.path = topPath.CGPath;
    top.mask = tmask;
    top.zPosition = -997;

    // ①'' 1.8.0 轮廓硬描边：整颗键帽外圈一圈细近黑描边（叶片自身裁剪，只露内半宽）
    if (!edge) {
        edge = [CAShapeLayer layer];
        edge.name = @"wxkb_cap_edge";
        objc_setAssociatedObject(target, kWXKBCapEdgeKey, edge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [target.layer insertSublayer:edge atIndex:0];
    }
    edge.frame = CGRectMake(0, 0, tbsz.width, tbsz.height);
    edge.path = silLeaf.CGPath;
    edge.fillColor = [UIColor clearColor].CGColor;
    edge.strokeColor = cEdge.CGColor;
    edge.lineWidth = (capStyle == 2) ? 1.0 : ((capStyle == 4) ? 0.8 : 1.4);
    edge.zPosition = -996;
    edge.hidden = (capStyle == 3);

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
    wall.fillColor = cWallLo.CGColor;
    wall.hidden = (capStyle == 3) || kDepth <= 0.0;

    // ④ 整颗键柔和投影：电脑键盘风更沉，彩虹键盘帽更轻更散，彩虹3D适中
    v.layer.shadowColor  = [UIColor colorWithWhite:0.0 alpha:1.0].CGColor;
    if (capStyle == 3) {
        // 彩虹3D：实体键盘投影，更深更明显
        v.layer.shadowOpacity = 0.25;
        v.layer.shadowOffset  = CGSizeMake(0.0, 4.0);
        v.layer.shadowRadius  = 5.0;
    } else if (capStyle == 4) {
        // 卡通手绘：浮起投影（柔和阴影，模拟悬浮感）
        v.layer.shadowOpacity = 0.20;
        v.layer.shadowOffset  = CGSizeMake(0.0, 3.5);
        v.layer.shadowRadius  = 5.0;
    } else if (capStyle == 5) {
        // 霓虹：发光投影（彩色阴影）
        v.layer.shadowOpacity = 0.50;
        v.layer.shadowOffset  = CGSizeMake(0.0, 2.0);
        v.layer.shadowRadius  = 6.0;
        v.layer.shadowColor   = cEdge.CGColor;  // 发光颜色 = 描边颜色
    } else if (capStyle == 2) {
        v.layer.shadowOpacity = 0.20;
        v.layer.shadowOffset  = CGSizeMake(0.0, 3.0);
        v.layer.shadowRadius  = 4.5;
    } else if (capStyle >= 6 && capStyle <= 11) {
        NSInteger st = capStyle - 6;
        if      (st == 1) {   // 7 镜面：明显投影
            v.layer.shadowOpacity = 0.35; v.layer.shadowOffset = CGSizeMake(0.0, 4.0); v.layer.shadowRadius = 5.0;
            v.layer.shadowColor = [UIColor colorWithWhite:1.0 alpha:1.0].CGColor;
        } else if (st == 3) {  // 9 软萌：浮起投影
            v.layer.shadowOpacity = 0.20; v.layer.shadowOffset = CGSizeMake(0.0, 3.5); v.layer.shadowRadius = 5.0;
        } else if (st == 5) {  // 11 双色：发光投影
            v.layer.shadowOpacity = 0.50; v.layer.shadowOffset = CGSizeMake(0.0, 2.0); v.layer.shadowRadius = 6.0;
            v.layer.shadowColor = cEdge.CGColor;
        } else {              // 6 磨砂 / 8 描边 / 10 极简：标准投影
            v.layer.shadowOpacity = 0.28; v.layer.shadowOffset = CGSizeMake(0.0, 2.0); v.layer.shadowRadius = 3.0;
        }
    } else {
        v.layer.shadowOpacity = 0.28;
        v.layer.shadowOffset  = CGSizeMake(0.0, 2.0);
        v.layer.shadowRadius  = 3.0;
    }

    [CATransaction commit];
}

// —— 马卡龙浮雕：字母键下层小字（Q→1…，原版键帽双层文字）——
static NSString *WXKBSublabelForLetter(NSInteger idx) {
    static NSArray<NSArray<NSString *> *> *rows = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[ @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0"],
                  @[@"!", @"@", @"#", @"~", @"%", @"...", @".", @"(", @")"],
                  @[@"\"", @"'", @"-", @"_", @":", @";", @"?"] ];
    });
    NSInteger row = -1, col = 0;
    if (idx >= 0 && idx <= 9)        { row = 0; col = idx; }
    else if (idx >= 10 && idx <= 18) { row = 1; col = idx - 10; }
    else if (idx >= 19 && idx <= 25) { row = 2; col = idx - 19; }
    if (row < 0) return nil;
    return rows[row][col];
}

static const void *kWXKBSubKey = &kWXKBSubKey;

static void WXKBApplySublabel(UIView *v) {
    if (!v) return;
    // 2.2.0 移除马卡龙浮雕后，不再显示下层小字
    UILabel *sub = objc_getAssociatedObject(v, kWXKBSubKey);
    if (sub) {
        [sub removeFromSuperview];
        objc_setAssociatedObject(v, kWXKBSubKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
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
            if (t == target || WXKBCapStyle() == 0) t.layer.masksToBounds = YES;
        }
        return;
    }

    // shape 1/2/3：忽略 keyCornerRadius，用形状（蒙版只加在背景叶子，不裁文字）
    // 2.2.8 修复：六边形/水珠形状只应用于接近正方形的键（字母键等）。
    // 长矩形键（空格、shift、删除、123、回车…）强行改成六边形会变形、
    // 还会和周围键之间露出黑色三角空隙，视觉上不伦不类。长键回退为普通圆角。
    CGSize sz = v.bounds.size;
    CGFloat ratio = (sz.height > 1) ? sz.width / sz.height : 1.0;
    if (ratio < 0) ratio = -ratio;
    BOOL isSquareish = (ratio >= 0.75 && ratio <= 1.35);
    if (gShape >= 2 && !isSquareish) {
        // 长键：六边形/水珠 → 改用普通大圆角，保持协调
        target.layer.mask = nil;
        objc_setAssociatedObject(target, kWXKBMaskLayerKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGFloat r = sz.height * 0.35;
        if (fabs(target.layer.cornerRadius - r) > 0.01) target.layer.cornerRadius = r;
        target.layer.masksToBounds = YES;
        if (target != v) {
            v.layer.mask = nil;
            v.layer.cornerRadius = 0;
        }
        return;
    }
    WXKBApplyShapeMask(target, gShape, target.bounds.size);
    if (target != v) {
        // key 自身不再额外圆角/蒙版，避免双重裁剪
        v.layer.mask = nil;
        v.layer.cornerRadius = 0;
        // 2.2.9 修复六边形/水珠模式下键之间透出黑色菱形的问题：
        // 六边形 mask 后，target 背景叶四角被裁掉，v 下面那层（行容器/间隔）
        // 的深色背景从凹角处露出来，形成黑色菱形空隙。
        // 2.2.8 试过把 v 设成透明，但 v 的 superview（行容器）还是深色的。
        // 正确做法：把 v 的背景设成和键盘画布一致的颜色，
        // 这样六边形凹角外面的区域就是画布色，和整体背景融为一体。
        if (gSkinEnabled) {
            UIColor *canvas = WXKBSkinCanvasColor();
            v.backgroundColor = canvas;
            v.layer.backgroundColor = canvas.CGColor;
        }
    }
}

static void WXKBApplySkin(UIView *v, UIView *leaf);  // 前向声明（定义见下方皮肤块）

// 2.2.7 皮肤模式下，递归强制所有文字/图标为深色。
// 之前只 hook 了 tintColorForCurrentState 等少数方法，但微信键盘的文字/图标
// 渲染路径很多（UILabel.textColor、UIImageView.tintColor、UIButton 的各种 state
// 渲染、attributedText 等），漏掉哪一路都会出现"白字看不见"。
// 改为直接在 layout 后遍历子视图树，暴力把所有显示元素改成深色，
// 确保浅色画布上文字图标绝对可见。
//
// 2.2.9 修复：不再做"亮度 > 0.55 才改"的判断。
// 因为微信大量使用 UIDynamicProviderColor（动态颜色），用 getRed: 读到的
// 是 light 模式下的解析值（看起来已经是深色），但实际在深色 trait 环境里
// 显示出来是白色的（比如 WBCCFuncItem 面板里的图标和文字）。
// 皮肤模式下面板底色一定是浅色的，文字/图标必须是深色，直接强制覆盖最可靠。
static void WXKBForceDarkContent(UIView *v) {
    if (!v || !gEnabled || !gSkinEnabled) return;
    UIColor *dark = [UIColor colorWithRed:0.18 green:0.18 blue:0.20 alpha:1.0];
    UIColor *gray = [UIColor colorWithRed:0.35 green:0.35 blue:0.38 alpha:1.0];
    // 遍历子视图（BFS，避免递归栈溢出）
    NSMutableArray *queue = [NSMutableArray arrayWithObject:v];
    while (queue.count > 0) {
        UIView *cur = [queue firstObject];
        [queue removeObjectAtIndex:0];
        // 所有非文字视图统一给深灰 tint：覆盖那些用 self.tintColor 画图的自定义图标
        // 视图（UIControl 之外的图标视图），以及大尺寸模板图标，避免白底白图标。
        if (![cur isKindOfClass:[UILabel class]]) {
            cur.tintColor = gray;
        }
        // UILabel：文字强制深色（动态颜色也直接覆盖，避免白色解析值）
        if ([cur isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)cur;
            if (lbl.textColor && CGColorGetAlpha(lbl.textColor.CGColor) > 0.01) {
                lbl.textColor = dark;
            }
            // highlightedTextColor 也改
            if (lbl.highlightedTextColor &&
                CGColorGetAlpha(lbl.highlightedTextColor.CGColor) > 0.01) {
                lbl.highlightedTextColor = dark;
            }
        }
        // UIImageView：tintColor 已统一深灰；小图标（非照片）转 template
        if ([cur isKindOfClass:[UIImageView class]]) {
            UIImageView *iv = (UIImageView *)cur;
            // 2.3.7 修复：白图标根因是渲染模式判定太窄——只认 AlwaysOriginal，
            // 漏掉更常见的 Automatic（asset 默认渲染模式）。Automatic 在浅色上下文
            // 解析成原色（白像素），tint 改了也没用，必须转 AlwaysTemplate 才受 tint 影响。
            // 阈值从 40 提到 72pt，覆盖 44~50pt 的大图标。只动小图标，照片缩略图更大保留原色。
            if (iv.image && iv.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                CGSize sz = iv.image.size;
                if (sz.width > 0 && sz.width <= 72 && sz.height > 0 && sz.height <= 72) {
                    iv.image = [iv.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    iv.tintColor = gray;
                }
            }
            if (iv.highlightedImage &&
                iv.highlightedImage.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                CGSize hsz = iv.highlightedImage.size;
                if (hsz.width > 0 && hsz.width <= 72 && hsz.height > 0 && hsz.height <= 72) {
                    iv.highlightedImage = [iv.highlightedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                }
            }
        }
        // UIButton：文字颜色 + image + backgroundImage 全部深色化
        // （backgroundImage 之前完全漏处理，是白图标的主因：照片符号 / 隔空投送图标等）
        if ([cur isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)cur;
            for (NSInteger s = 0; s <= 3; s++) {
                UIColor *tc = [btn titleColorForState:s];
                if (tc) [btn setTitleColor:dark forState:s];
                UIImage *im = [btn imageForState:s];
                if (im && im.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                    CGSize isz = im.size;
                    if (isz.width > 0 && isz.width <= 72 && isz.height > 0 && isz.height <= 72) {
                        [btn setImage:[im imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:s];
                    }
                }
                UIImage *bim = [btn backgroundImageForState:s];
                if (bim && bim.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                    CGSize bsz = bim.size;
                    if (bsz.width > 0 && bsz.width <= 72 && bsz.height > 0 && bsz.height <= 72) {
                        [btn setBackgroundImage:[bim imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:s];
                    }
                }
            }
            btn.imageView.tintColor = gray;
            btn.tintColor = gray;
        }
        // 继续遍历子视图
        for (UIView *sv in cur.subviews) {
            [queue addObject:sv];
        }
    }
}

// 精准处理「文字 label 左侧图标」：剪贴板面板里每一项 = [左侧类型图标] + [WBTextItemLabel 文字]，
// 左侧图标通常是白 PNG（渲染模式多为 Automatic，不受 tint 影响），在浅色皮肤下看不见。
// 图标未必和 label 是同父直接兄弟（微信常包一层容器），所以从 label 向上取根容器，
// 再广度遍历其所有后代找 UIImageView / UIButton 图标，转 template + 深灰 tint。
// 2.3.7：阈值提到 72pt 且不再限定 AlwaysOriginal（Automatic 同样处理），覆盖大图标与默认渲染图标。
static void WXKBDarkenSiblingIcons(UIView *label) {
    if (!label || !gEnabled || !gSkinEnabled) return;
    // 向上取文字项根容器（最多 4 层祖先）
    UIView *root = label;
    for (int i = 0; i < 4; i++) {
        UIView *pp = root.superview;
        if (!pp) break;
        root = pp;
    }
    UIColor *gray = [UIColor colorWithRed:0.35 green:0.35 blue:0.38 alpha:1.0];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    NSInteger depth = 0;
    while (queue.count > 0 && depth <= 5) {
        NSMutableArray *next = [NSMutableArray array];
        for (UIView *cur in queue) {
            if ([cur isKindOfClass:[UIImageView class]]) {
                UIImageView *iv = (UIImageView *)cur;
                if (iv.image && iv.image.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                    CGSize s = iv.image.size;
                    if (s.width > 0 && s.width <= 72 && s.height > 0 && s.height <= 72) {
                        iv.image = [iv.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                        iv.tintColor = gray;
                    }
                }
                if (iv.highlightedImage &&
                    iv.highlightedImage.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                    CGSize hs = iv.highlightedImage.size;
                    if (hs.width > 0 && hs.width <= 72 && hs.height > 0 && hs.height <= 72) {
                        iv.highlightedImage = [iv.highlightedImage imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    }
                }
            } else if ([cur isKindOfClass:[UIButton class]]) {
                UIButton *btn = (UIButton *)cur;
                for (NSInteger st = 0; st <= 3; st++) {
                    UIImage *im = [btn imageForState:st];
                    if (im && im.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                        CGSize s = im.size;
                        if (s.width > 0 && s.width <= 72 && s.height > 0 && s.height <= 72) {
                            [btn setImage:[im imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:st];
                        }
                    }
                    UIImage *bim = [btn backgroundImageForState:st];
                    if (bim && bim.renderingMode != UIImageRenderingModeAlwaysTemplate) {
                        CGSize s = bim.size;
                        if (s.width > 0 && s.width <= 72 && s.height > 0 && s.height <= 72) {
                            [btn setBackgroundImage:[bim imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:st];
                        }
                    }
                }
                btn.imageView.tintColor = gray;
                btn.tintColor = gray;
            }
            for (UIView *sv in cur.subviews) [next addObject:sv];
        }
        queue = next;
        depth++;
    }
}

static void WXKBApplyCorner(UIView *v) {
    WXKBApplyCornerInner(v);
    if (!v) return;
    WXKBApplyCap(v, WXKBFindBgLeaf(v, 0));
    WXKBApplySkin(v, WXKBFindBgLeaf(v, 0));
    WXKBApplySublabel(v);
    WXKBForceDarkContent(v);
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
static const CGFloat kWXKBSkinLetterCapH  = 132.0;   // key26a 全高（含键帽+下方柔和投影，投影叠在画布底色上更立体）
static const CGFloat kWXKBSkinFuncPitch   = 216.0;   // key9a 键帽间距（px）
static const CGFloat kWXKBSkinFuncCapH    = 144.0;   // key9a 全高

// 把键帽条里的「画布底色」抠成透明（1.7.2 核心修复）。
// 背景：皮肤条里键帽四周是浅灰画布（实测 (245,247,250)），不抠掉的话贴到键盘上
// 每颗键周围会有一圈浅色边（暗色键盘上尤其明显——用户截图里的「白边」就是它）。
// 做法：从条带四边做泛洪填充（BFS），凡与边界连通的「中性亮灰」像素 → alpha 0。
// 判据用「通道差」而不是「离画布色的距离」：画布是无色偏中性灰(max-min<=5)，
// 而键帽顶面再淡也有色偏(实测 26+9 颗全部 max-min>=15，最淡的 V 键只有 15/23)，
// 若按距离(容差需>=90 才能吃掉投影边缘)会把淡色顶面一起误删——模拟验证踩过这个坑。
// 键帽黑描边(暗)与穹顶内部(有色偏)都不满足判据，泛洪天然被挡在键帽轮廓之外。
static void WXKBReleasePx(void *info, const void *data, size_t size) {
    free((void *)data);
}

static UIImage *WXKBKeycapStrip(UIImage *img) {
    if (!img) return nil;
    CGImageRef cg = img.CGImage;
    if (!cg) return nil;
    size_t W = CGImageGetWidth(cg), H = CGImageGetHeight(cg);
    if (W < 8 || H < 8) return nil;
    UInt8 *px = (UInt8 *)malloc(W * H * 4);
    if (!px) return nil;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, W, H, 8, W * 4, cs,
                                             kCGImageAlphaPremultipliedLast |
                                             kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) { free(px); return nil; }
    CGContextDrawImage(ctx, CGRectMake(0.0, 0.0, (CGFloat)W, (CGFloat)H), cg);
    CGContextRelease(ctx);
    UInt8 *mark = (UInt8 *)calloc(W * H, 1);
    NSInteger *stk = (NSInteger *)malloc(sizeof(NSInteger) * W * H);
    if (mark && stk) {
        NSInteger top = 0;
        size_t lastX = W - 1, lastY = H - 1;
        #define WXKB_SEED(IDX) do { \
            size_t _i = (size_t)(IDX); \
            if (!mark[_i]) { \
                const UInt8 *p = px + _i * 4; \
                UInt8 _mx = p[0] > p[1] ? (p[0] > p[2] ? p[0] : p[2]) \
                                        : (p[1] > p[2] ? p[1] : p[2]); \
                UInt8 _mn = p[0] < p[1] ? (p[0] < p[2] ? p[0] : p[2]) \
                                        : (p[1] < p[2] ? p[1] : p[2]); \
                if (_mx - _mn <= 7 && _mn >= 225) { \
                    mark[_i] = 1; stk[top++] = (NSInteger)_i; \
                } \
            } \
        } while (0)
        for (size_t x = 0; x < W; x++) { WXKB_SEED(x); WXKB_SEED(lastY * W + x); }
        for (size_t y = 0; y < H; y++) { WXKB_SEED(y * W); WXKB_SEED(y * W + lastX); }
        while (top > 0) {
            NSInteger idx = stk[--top];
            NSInteger x = idx % (NSInteger)W, y = idx / (NSInteger)W;
            if (x > 0) WXKB_SEED(idx - 1);
            if (x < (NSInteger)lastX) WXKB_SEED(idx + 1);
            if (y > 0) WXKB_SEED(idx - (NSInteger)W);
            if (y < (NSInteger)lastY) WXKB_SEED(idx + (NSInteger)W);
        }
        #undef WXKB_SEED
        // 1.7.4 致命修复：只置 alpha=0 而保留 RGB(245,247,250) 会产出「RGB > alpha」
        // 的非法 premultiplied 数据 —— GPU 对这种图片的渲染结果是未定义的，
        // 实测整张贴图在真机上渲染成空白（1.7.2/1.7.3 穹顶从未显示的真正根因，
        // 1.7.1 不透明切片能显示恰好反证了这一点）。premultiplied 语义要求
        // alpha=0 的像素 RGB 必须也是 0。
        for (size_t i = 0; i < W * H; i++) {
            if (mark[i]) {
                px[i * 4]     = 0;
                px[i * 4 + 1] = 0;
                px[i * 4 + 2] = 0;
                px[i * 4 + 3] = 0;
            }
        }
    }
    if (mark) free(mark);
    if (stk) free(stk);
    // 1.7.3 致命修复：1.7.2 用「第二个 CGBitmapContext + CGBitmapContextCreateImage」
    // 之后又 free(px) —— CGBitmapContextCreateImage 对手工 malloc 的缓冲是写时复制，
    // 只跟踪「通过 context 的写入」，不管手动 free()；free 之后图片数据悬空，
    // 真机上整张图渲染成空白 → 穹顶贴图完全消失（用户看到「还是平涂」的根因）。
    // 现在改为 CGDataProviderCreateWithData 持有缓冲，图片对象释放时才回收内存。
    CGColorSpaceRef cs2 = CGColorSpaceCreateDeviceRGB();
    CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, px, W * H * 4,
                                                          &WXKBReleasePx);
    CGImageRef out = prov ? CGImageCreate(W, H, 8, 32, W * 4, cs2,
                                          kCGImageAlphaPremultipliedLast |
                                          kCGBitmapByteOrder32Big,
                                          prov, NULL, false,
                                          kCGRenderingIntentDefault)
                          : NULL;
    CGDataProviderRelease(prov);          // CGImage 已 retain，安全
    CGColorSpaceRelease(cs2);
    if (!out) { free(px); return nil; }
    UIImage *res = [[UIImage alloc] initWithCGImage:out scale:img.scale
                                        orientation:UIImageOrientationUp];
    CGImageRelease(out);
    return res;
}

static UIImage *gSkinLetterImg[26];
static UIColor *gSkinLetterCol[26];
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
    if (!letter) {   // a/b 两版键帽图配色一致，只差键面明暗，互为备份
        letter = [UIImage imageWithContentsOfFile:[dir stringByAppendingString:@"key26b.png"]];
    }
    // 1.7.5：key9a/key9b 功能键条正式退役。key26a 第 27 格实测是空白画布而非白色
    // 键帽——1.7.3 功能键全白（画布色被取为面色）、1.7.4 全黑（清零后被取为纯黑）
    // 互为证据。功能键改为直接涂画布白，立体明暗由立体键帽渲染器推导（见下）。
    // 先把画布底色抠成透明（1.7.2），再切片——取色只采键面像素。
    letter = WXKBKeycapStrip(letter);
    NSArray *la = WXKBSliceStrip(letter, 26, kWXKBSkinLetterPitch, kWXKBSkinLetterCapH);
    for (NSInteger i = 0; i < 26; i++) {
        id o = la ? la[i] : nil;
        if ([o isKindOfClass:[UIImage class]]) {
            gSkinLetterImg[i] = o;
            gSkinLetterCol[i] = WXKBFaceColor(o);
        }
    }
    if (gSkinLetterImg[0]) {
        // 2.2.5 检查提取的颜色是否太浅（白色），如果是则使用后备色
        BOOL allTooLight = YES;
        for (NSInteger i = 0; i < 26; i++) {
            if (gSkinLetterCol[i]) {
                CGFloat r, g, b, a;
                [gSkinLetterCol[i] getRed:&r green:&g blue:&b alpha:&a];
                CGFloat brightness = 0.299 * r + 0.587 * g + 0.114 * b;
                if (brightness < 0.85) {
                    allTooLight = NO;
                    break;
                }
            }
        }
        if (allTooLight) {
            // 所有颜色都太浅，使用后备彩虹色
            for (NSInteger i = 0; i < 26; i++) {
                CGFloat hue = (i % 10) / 10.0;
                gSkinLetterCol[i] = [UIColor colorWithHue:hue
                                               saturation:0.65
                                               brightness:0.92
                                                    alpha:1.0];
            }
        }
        gSkinLoaded = YES;
    } else {
        // 2.2.3 皮肤加载失败时，使用代码生成的彩虹色作为后备
        gSkinLoaded = YES;  // 标记为已加载（使用后备色）
        for (NSInteger i = 0; i < 26; i++) {
            // 按行生成彩虹色：每行一个色相渐变
            CGFloat hue = (i % 10) / 10.0;  // 0.0 ~ 0.9
            gSkinLetterCol[i] = [UIColor colorWithHue:hue
                                           saturation:0.65
                                           brightness:0.92
                                                alpha:1.0];
        }
    }
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

// 皮肤的「画布底色」——demo 键盘的背景色，也是白色功能键帽的键面色。
// 2.3.7：新增皮肤背景选项（全透明 / 灰色 / 白50%）。
static UIColor *WXKBSkinCanvasColor(void) {
    switch (gSkinBg) {
        case 1:  // 全透明：键盘背景层全透，只留彩虹键帽，透出后面内容
            return [UIColor clearColor];
        case 2:  // 灰色：中浅灰底，彩色键帽浮在上面
            return [UIColor colorWithRed:0.80 green:0.80 blue:0.82 alpha:1.0];
        case 3:  // 白50%：白色半透明，隐约透出后面内容
            return [UIColor colorWithWhite:1.0 alpha:0.5];
        default: // 0 白底（默认，demo 同款浅色底）
            return [UIColor colorWithRed:245.0 / 255.0 green:247.0 / 255.0 blue:250.0 / 255.0 alpha:1.0];
    }
}

// 皮肤配色（走原生按键底色通道，像切换主题一样给键盘上色）。
// 1.7.5：字母键 → 键面代表色；其余键（shift/123/空格/回车/符号页全部）→
// 画布白（demo 同款白色键帽）。立体明暗（高光/侧壁/投影）由立体键帽渲染器
// WXKBApplyCap 从这个底色推导——它是 CAShapeLayer+渐变实现，真机上稳定渲染，
// 彻底取代始终显示不出来的 CGImage 贴图路线。
// ---- 2.3.9 内置「配套主题」= 主题族 × 变色方向 ----
// 每套 10 色粉彩彩虹，按键盘行循环套色：同一列的三行同色 → 竖向色带，
// 与百度彩虹按键的 9 宫格是同一套视觉语言（demo.png 的观测色：粉彩键面 +
// 更饱和的下缘 + 近白功能键 + 浅白画布）。取色纯代码，选了即生效，不依赖皮肤图。
// ---- 2.3.9 主题族 × 变色方向 ----
// 每族 = (色相起, 色相止, 饱和度, 亮度)，色相在 [起,止] 上线性插值；
// 方向决定渐变沿哪根轴走：横向=按列、竖向=按行、斜向=两者取中。
// 相比 2.3.8 的「10 色板套色」，这里是连续渐变，横向才是真正的彩虹过渡。
static const double kThemeFam[32][4] = {
    {   0,   0, 0.00, 0.00},   // 0 百度彩虹（读原图，不参与）
    {   0, 352, 0.88, 0.72},   // 1 彩虹
    {   0, 352, 0.82, 0.88},   // 2 马卡龙
    {  18,  54, 0.90, 0.86},   // 3 蜜桃
    { 128, 190, 0.72, 0.85},   // 4 薄荷
    { 240, 332, 0.72, 0.86},   // 5 暮紫
    { 182, 250, 0.80, 0.82},   // 6 海蓝
    { 336,  42, 0.90, 0.80},   // 7 落日
    {  66, 160, 0.70, 0.84},   // 8 森系
    { 140, 200, 0.85, 0.60},   // 9 极光
    { 300, 360, 0.95, 0.70},   // 10 霓粉
    { 205, 255, 0.95, 0.62},   // 11 电蓝
    {  20,  50, 0.95, 0.62},   // 12 柑橘
    {  52,  78, 0.90, 0.70},   // 13 柠檬
    { 270, 320, 0.72, 0.66},   // 14 葡萄
    { 338,  18, 0.55, 0.80},   // 15 玫瑰金
    { 140, 170, 0.50, 0.80},   // 16 薄雾
    { 190, 220, 0.65, 0.78},   // 17 天空
    {   2,  26, 0.85, 0.72},   // 18 珊瑚
    { 258, 292, 0.82, 0.64},   // 19 紫罗兰
    {  82, 112, 0.85, 0.66},   // 20 青柠
    { 200, 242, 0.88, 0.46},   // 21 深海
    { 280, 332, 0.92, 0.56},   // 22 暗霓
    {  30,  60, 0.90, 0.75},   // 23 暖阳
    { 182, 212, 0.55, 0.86},   // 24 冰蓝
    { 326, 358, 0.82, 0.62},   // 25 莓果
    {  60,  92, 0.55, 0.66},   // 26 橄榄
    {  28,  48, 0.32, 0.56},   // 27 钨丝
    { 262, 330, 0.70, 0.74},   // 28 蒸汽波
    { 150, 182, 0.82, 0.58},   // 29 翡翠
    {  24,  46, 0.92, 0.68},   // 30 蜜橙
    { 208, 240, 0.38, 0.80}    // 31 雾蓝
};

// HSL → UIColor（色相 0~360，饱和/亮度 0~1）
static UIColor *WXKBFromHSL(double h, double s, double l) {
    double C = (1.0 - fabs(2.0 * l - 1.0)) * s;
    double hp = fmod(h, 360.0) / 60.0;
    if (hp < 0) hp += 6.0;
    double X = C * (1.0 - fabs(fmod(hp, 2.0) - 1.0));
    double r = 0, g = 0, b = 0;
    if      (hp < 1) { r = C; g = X; }
    else if (hp < 2) { r = X; g = C; }
    else if (hp < 3) { g = C; b = X; }
    else if (hp < 4) { g = X; b = C; }
    else if (hp < 5) { r = X; b = C; }
    else             { r = C; b = X; }
    double m = l - C / 2.0;
    return [UIColor colorWithRed:r + m green:g + m blue:b + m alpha:1.0];
}

// 皮肤片号 0..25（行 10/9/7）→ 行号 0..2 + 水平进度 tx。
// units/offs 与预览图同源：第二行两端各有加宽的 ⇧/⌫，所以中间 7 键并不铺满整行，
// 用同一套比例才能让真机与预览的渐变色带位置对齐。
static BOOL WXKBThemeRowCol(NSInteger slot, NSInteger *row, CGFloat *tx) {
    static const double units[3] = {10.0, 9.0, 9.9};
    static const double offs[3]  = { 0.0, 0.0, 1.45};
    NSInteger r, k;
    if (slot < 0 || slot > 25) return NO;
    if (slot < 10)      { r = 0; k = slot; }
    else if (slot < 19) { r = 1; k = slot - 10; }
    else                { r = 2; k = slot - 19; }
    *row = r;
    *tx  = (CGFloat)((offs[r] + k + 0.5) / units[r]);
    return YES;
}

// 主题渐变取色：row 行号（0~2 字母行，3 空格行），tx 水平进度 0~1
static UIColor *WXKBThemeGradientColor(NSInteger row, CGFloat tx) {
    if (gSkinTheme < 1 || gSkinTheme > 31) return nil;
    const double *f = kThemeFam[gSkinTheme];
    double h0 = f[0], h1 = f[1], s = f[2], l = f[3];
    if (h1 < h0) h1 += 360.0;                 // 跨 0° 的族（落日）绕回
    double ty = row / 3.0;
    double t;
    if (gSkinDir >= 3) {
        // 角度方向（3~11 → 15°/30°/60°/75°/105°/120°/135°/150°/165°）
        static const double kAng[9] = {15.0,30.0,60.0,75.0,105.0,120.0,135.0,150.0,165.0};
        if (gSkinDir - 3 < 9) {
            double a = kAng[gSkinDir - 3] * 3.141592653589793 / 180.0;
            double c = cos(a), d = sin(a);
            double val = tx * c + ty * d;
            double mn = (c > 0 ? 0.0 : c) + (d > 0 ? 0.0 : d);
            double mx = (c > 0 ? c : 0.0) + (d > 0 ? d : 0.0);
            double denom = mx - mn;
            t = (denom > 1e-6) ? (val - mn) / denom : 0.5;
        } else {
            t = tx;
        }
    } else {
        switch (gSkinDir) {
            case 1:  t = ty;              break;  // 竖向：按行
            case 2:  t = (tx + ty) / 2.0; break;  // 斜向
            default: t = tx;              break;  // 横向：按列
        }
    }
    if (t < 0.0) t = 0.0;
    if (t > 1.0) t = 1.0;
    return WXKBFromHSL(h0 + (h1 - h0) * t, s, l);
}

// slot：QWERTY 行序 0..25（行 10/9/7）
static UIColor *WXKBThemeLetterColor(NSInteger slot) {
    NSInteger row = 0;
    CGFloat tx = 0.5;
    if (!WXKBThemeRowCol(slot, &row, &tx)) return nil;
    return WXKBThemeGradientColor(row, tx);
}

// 功能键（大小写/删除/空格/回车/符号页…）：浅灰白，与百度 demo 的白色功能键一致。
static UIColor *WXKBSkinFuncColor(void) {
    return [UIColor colorWithRed:0.90 green:0.90 blue:0.92 alpha:1.0];
}

static UIColor *WXKBSkinColorFor(WBKeyView *v) {
    if (!gEnabled || !gSkinEnabled || !v) return nil;
    NSInteger li = WXKBLetterIndex(v);
    if (gSkinTheme >= 1) {
        // 2.3.9 配套主题：不读皮肤图。字母键按「族 × 方向」取渐变中间色，
        // 空格键取第 4 行色，其余键近白（与百度 demo 的白色功能键一致）。
        if (li != NSNotFound) {
            UIColor *tc = WXKBThemeLetterColor(WXKBSkinSlotForLetter(li));
            if (tc) return tc;
        }
        if (WXKBKindOf(v) == WXKBKeyKindSpace) {
            UIColor *tc = WXKBThemeGradientColor(3, 0.5);
            if (tc) return tc;
        }
        return WXKBSkinFuncColor();
    }
    WXKBLoadSkin();
    if (!gSkinLoaded) return nil;
    if (li != NSNotFound) {
        NSInteger slot = WXKBSkinSlotForLetter(li);
        if (slot != NSNotFound && slot < 26 && gSkinLetterCol[slot]) {
            return gSkinLetterCol[slot];
        }
    }
    // 2.2.3 功能键：浅灰色（不再是画布白，避免白茫茫一片）
    return [UIColor colorWithRed:0.88 green:0.88 blue:0.90 alpha:1.0];
}

static const void *kWXKBSkinKey      = &kWXKBSkinKey;       // 已贴图片（去重，避免重复赋值）
static const void *kWXKBSkinLayerKey = &kWXKBSkinLayerKey;  // 皮肤图层（子图层方式）

// 1.7.5：CGImage 皮肤贴图路线正式退役。
// 带透明的皮肤切片在真机上从未渲染成功过——1.7.2 的 free 悬空、1.7.3/1.7.4 的
// premultiplied 非法都是修过的真问题，但修完依旧空白，说明这条链路还有未知的
// 设备侧差异。既然插件自带的立体键帽渲染器（WXKBApplyCap，CAShapeLayer+渐变）
// 一直在真机上稳定渲染，穹顶立体感就交给它：底色（WXKBSkinColorFor）+ 推导
// 明暗 = demo 的穹顶键帽效果，零图片依赖。
// 此函数现在只负责清掉历史版本可能留下的皮肤子图层。
static void WXKBApplySkin(UIView *v, UIView *leaf) {
    if (!v) return;
    UIView *target = leaf ?: v;
    CALayer *skin = objc_getAssociatedObject(target, kWXKBSkinLayerKey);
    if (skin) {
        [skin removeFromSuperlayer];
        objc_setAssociatedObject(target, kWXKBSkinLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(target, kWXKBSkinKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
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

static UIColor *WXKBKeyText(WBKeyView *v) {
    // 2.2.4 开启皮肤时，所有文字强制黑色
    if (gSkinEnabled) {
        return [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0];
    }

    NSInteger cs = WXKBCapStyle();
    BOOL isLetterKey = (v && WXKBLetterIndex(v) != NSNotFound);

    // 默认：键帽风格用深炭灰，其他用用户设置
    if (isLetterKey && (cs == 3 || cs == 4 || cs == 5)) {
        return [UIColor colorWithRed:0.23 green:0.23 blue:0.25 alpha:1.0];
    }
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
    if (!gEnabled || (!gBgEnabled && !gTransparent && !gSkinEnabled)) {
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
    } else if (gSkinEnabled) {
        // 1.7.5 皮肤模式：键盘背景涂画布色（demo 同款浅色底），键帽浮在上面。
        // 2.3.7：画布色可能是透明或半透明（全透明 / 白50%），此时背景层必须 opaque=NO，
        // 否则不透明层会盖住后面内容，透明设置失效。
        bg.layer.contents = nil;
        UIColor *skinBg = WXKBSkinCanvasColor();
        bg.backgroundColor = skinBg;
        bg.opaque = (CGColorGetAlpha(skinBg.CGColor) > 0.99);
    } else {
        // 只开了整键盘透明：这一层保持全透
        bg.layer.contents = nil;
        bg.backgroundColor = [UIColor clearColor];
        bg.opaque = NO;
    }

    // 1.9.0 修复：下拉搜索等深色容器里，系统按深色外观渲染工具栏图标与
    // 功能键图案（shift/中英/搜索…）→ 白画布上全白看不见。皮肤模式是
    // 白画布，强制键盘区域用浅色外观，图标/文字自然变深。
    if (@available(iOS 13.0, *)) {
        UIUserInterfaceStyle want = gSkinEnabled ? UIUserInterfaceStyleLight
                                                 : UIUserInterfaceStyleUnspecified;
        if (host.overrideUserInterfaceStyle != want) {
            host.overrideUserInterfaceStyle = want;
        }
        // 2.2.6 修复：只改 host 覆盖不到键盘 window 里其它子树（工具栏面板 /
        // 「拷贝的图片」等面板）——它们在深色宿主里仍按深色外观渲染成白字白图标。
        // 键盘扩展有独立 window，直接对 window 生效，不影响宿主 App。
        UIWindow *win = host.window;
        if (win && win.overrideUserInterfaceStyle != want) {
            win.overrideUserInterfaceStyle = want;
        }
    }

    // 2.2.7 暴力修复：皮肤模式下递归遍历整个键盘视图树，
    // 把所有浅色/白色的文字、图标、按钮文字强制改成深色。
    // 作为 overrideUserInterfaceStyle 的兜底——有些渲染路径不走
    // trait collection，白色外观设置了也没用，直接改视图属性最可靠。
    // 2.2.8 扩大范围：从 window 开始遍历，覆盖工具栏展开面板、
    // 候选栏面板、各种弹层视图等不在 rootInputView 里的子树。
    UIView *darkRoot = host.window ?: host;
    WXKBForceDarkContent(darkRoot);
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
    // 2.2.6 皮肤模式：工具栏面板底色是浅色画布，图标/文字 tint 改深灰，
    // 否则深色宿主下白色图标在白底上完全看不见。
    if (gSkinEnabled) {
        self.tintColor = [UIColor colorWithRed:74.0 / 255.0 green:74.0 / 255.0 blue:81.0 / 255.0 alpha:1.0];
    }
    // 2.2.8 暴力兜底：递归遍历整个工具栏及其所有子视图/面板，
    // 把浅色图标文字强制改成深色（展开面板里的图标也覆盖到）。
    WXKBForceDarkContent(self);
    WXKBFixScroll(self);
    WXKBScheduleSync();
}

%end

// WBTopBar 承载候选栏与工具栏；在它自身布局完成后重定位工具栏，避免被原生布局改回 x=102。
%hook WBTopBar

- (void)layoutSubviews {
    %orig;
    // 1.7.5 皮肤模式：键盘背景已涂画布白，顶栏 tint 改深灰，保证白色图标/文字可见
    if (gSkinEnabled) {
        self.tintColor = [UIColor colorWithRed:74.0 / 255.0 green:74.0 / 255.0 blue:81.0 / 255.0 alpha:1.0];
    }
    // 2.2.8 暴力兜底：顶栏及子视图递归深色
    WXKBForceDarkContent(self);
    WXKBFillRow(self);
}

%end

// 功能面板里的每一项（语音转文字、表情、剪贴板…）。
// 皮肤模式下面板底色是浅色的，但这里的图标和文字用了 UIDynamicProviderColor，
// 在深色宿主下会解析成白色 → 白底白字看不见。
// Hook 它的 layoutSubviews，暴力递归改成深色。
%hook WBCCFuncItem

- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) {
        WXKBForceDarkContent(self);
    }
}

%end

// 2.2.10 剪贴板相关面板（"拷贝的图片"/"拷贝的内容"提示条、剪贴板历史列表等）。
// 皮肤模式下面板底色是浅色的，但文字/图标用了动态颜色，
// 在深色宿主下解析为白色 → 白底白字看不见。
// Hook 它们的 layoutSubviews，递归强制深色。
%hook WBPasteboardHotWordShellView

- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) {
        WXKBForceDarkContent(self);
    }
}

%end

%hook WBPasteboardListView

- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) {
        WXKBForceDarkContent(self);
    }
}

%end

%hook WBPasteboardImageDetailView

- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) {
        WXKBForceDarkContent(self);
    }
}

%end

// 2.3.1 各种提示/Toast/面板类的通用深色化。
// 皮肤模式下这些视图的背景是浅色的（透出键盘画布色或自身白底），
// 但文字/图标是动态颜色，在深色宿主下解析为白色 → 看不见。
// 逐个 hook layoutSubviews 和 didMoveToWindow，确保出现时立刻深色化。
// 类不存在时 Logos 自动忽略，不影响运行。

%hook WBTopBarTipsView
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    if (gSkinEnabled && gEnabled && !hidden) {
        // 出现时立刻改色，延迟一下确保文字/图片已设置
        WXKBForceDarkContent(self);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WXKBForceDarkContent(self);
        });
    }
}
- (void)setAlpha:(CGFloat)alpha {
    %orig(alpha);
    if (gSkinEnabled && gEnabled && alpha > 0.01) {
        WXKBForceDarkContent(self);
    }
}
%end

%hook WBBaseToast
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

%hook WBToastView
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

%hook WBToastView2
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

%hook WBModernToast
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

%hook WBCommonPanelView
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

%hook WBSubPanelView
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

%hook WBNetworkAlertView
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

%hook WBCandidateExpandView
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

// 候选栏（普通模式）- 候选词文字可能是动态颜色，白底上变白
%hook WBCandidateView
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

%hook WBCandidateCell
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
- (void)setSelected:(BOOL)selected {
    %orig(selected);
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)setHighlighted:(BOOL)highlighted {
    %orig(highlighted);
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
%end

// 候选词文字 label - 直接强制设为深色
%hook WBTextItemLabel
- (void)setTextColor:(UIColor *)color {
    if (gSkinEnabled && gEnabled) {
        // 强制深色，不接受动态颜色
        %orig([UIColor colorWithWhite:0.18 alpha:1.0]);
        // 顺手把左侧兄弟图标（图片符号 / 复制符号）强制深灰
        WXKBDarkenSiblingIcons(self);
    } else {
        %orig(color);
    }
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) {
        // 触发 setTextColor: 的 hook 来强制深色
        [self setTextColor:self.textColor];
        WXKBDarkenSiblingIcons(self);
    }
}
%end

// 2.3.2 更多提示/通知类：修正通知、改写通知、AI Toast、剪贴板服务内容
%hook WBCorrectionNoticeView
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    if (gSkinEnabled && gEnabled && !hidden) {
        WXKBForceDarkContent(self);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WXKBForceDarkContent(self);
        });
    }
}
%end

%hook WBRewriteNoticeView
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
- (void)setHidden:(BOOL)hidden {
    %orig(hidden);
    if (gSkinEnabled && gEnabled && !hidden) {
        WXKBForceDarkContent(self);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            WXKBForceDarkContent(self);
        });
    }
}
%end

%hook WBAskAIToast
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
}
%end

%hook WBPasteboardServiceContent
- (void)layoutSubviews {
    %orig;
    if (gSkinEnabled && gEnabled) WXKBForceDarkContent(self);
}
- (void)didMoveToWindow {
    %orig;
    if (gSkinEnabled && gEnabled && self.window) WXKBForceDarkContent(self);
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
    // 2.2.2 按压反馈：键面轻微变暗
    NSInteger cs = WXKBCapStyle();
    if (cs > 0) {
        UIColor *bg = WXKBKeyBackground(self);
        if (bg) {
            CGFloat r, g, b, a;
            [bg getRed:&r green:&g blue:&b alpha:&a];
            // 按下时亮度降低 15%
            return [UIColor colorWithRed:MAX(r * 0.85, 0.0)
                                   green:MAX(g * 0.85, 0.0)
                                    blue:MAX(b * 0.85, 0.0)
                                   alpha:a];
        }
    }
    UIColor *c = WXKBKeyHighlight();
    if (c) return c;
    return %orig;
}

- (UIColor *)tintColorForCurrentState {
    UIColor *c = WXKBKeyText(self);
    if (c) return c;
    return %orig;
}

- (UIColor *)normalTintColorForCurrentState {
    UIColor *c = WXKBKeyText(self);
    if (c) return c;
    return %orig;
}

- (UIColor *)subTintColorForCurrentState {
    UIColor *c = WXKBKeyText(self);
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
    // 2.2.2 按压反馈：键面轻微变暗
    NSInteger cs = WXKBCapStyle();
    if (cs > 0) {
        UIColor *bg = WXKBKeyBackground(self);
        if (bg) {
            CGFloat r, g, b, a;
            [bg getRed:&r green:&g blue:&b alpha:&a];
            // 按下时亮度降低 15%
            return [UIColor colorWithRed:MAX(r * 0.85, 0.0)
                                   green:MAX(g * 0.85, 0.0)
                                    blue:MAX(b * 0.85, 0.0)
                                   alpha:a];
        }
    }
    UIColor *c = WXKBKeyHighlight();
    if (c) return c;
    return %orig;
}

// 2.2.6 修复：shift / 退格 / 空格 / 中英 等功能键（本类）之前没有 tint hook，
// 皮肤模式下这些键的图标仍是系统深色外观渲染的白色 → 浅色键上看不见。
- (UIColor *)tintColorForCurrentState {
    UIColor *c = WXKBKeyText(self);
    if (c) return c;
    return %orig;
}

- (UIColor *)normalTintColorForCurrentState {
    UIColor *c = WXKBKeyText(self);
    if (c) return c;
    return %orig;
}

- (UIColor *)subTintColorForCurrentState {
    UIColor *c = WXKBKeyText(self);
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
    // 2.2.2 按压反馈：键面轻微变暗
    NSInteger cs = WXKBCapStyle();
    if (cs > 0) {
        UIColor *bg = WXKBKeyBackground(self);
        if (bg) {
            CGFloat r, g, b, a;
            [bg getRed:&r green:&g blue:&b alpha:&a];
            // 按下时亮度降低 15%
            return [UIColor colorWithRed:MAX(r * 0.85, 0.0)
                                   green:MAX(g * 0.85, 0.0)
                                    blue:MAX(b * 0.85, 0.0)
                                   alpha:a];
        }
    }
    UIColor *c = WXKBKeyHighlight();
    if (c) return c;
    return %orig;
}

- (UIColor *)normalTintColorForCurrentState {
    UIColor *c = WXKBKeyText(self);
    if (c) return c;
    return %orig;
}

- (UIColor *)highlightedTintColorForCurrentState {
    UIColor *c = WXKBKeyText(self);
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
    NSLog(@"[WxkbToolbar10] 2.4.14 loaded enabled=%d bg=%d trans=%d key=%d grad=%d shape=%d capStyle=%ld corner=%.1f offset=%.1f skin=%d skinBg=%ld skinTheme=%ld skinDir=%ld",
          gEnabled, gBgEnabled, gTransparent, gKeyEnabled,
          gGradEnabled, gShape, (long)gCapStyle, gCorner, gKbOffset, gSkinEnabled, (long)gSkinBg, (long)gSkinTheme, (long)gSkinDir);
}