// WxkbToolbar10 — 微信输入法键盘扩展增强
// 目标：iPhone 12 Pro / iOS 16.6 / Relaxin rootless (ElleKit TweakInject)
// 注入目标：com.tencent.wetype.keyboard (wxkb_plugin.appex)
//
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
static NSArray  *gFuncList     = nil;    // NSNumber 数组，用户配置的顺序
static BOOL      gBgEnabled    = NO;
static int       gBgMode       = 1;      // 1 纯色 2 图片
static CGFloat   gBgAlpha      = 1.0;
static UIColor  *gBgColor      = nil;
static NSString *gBgImage      = nil;
static NSData   *gBgImageData  = nil;
static BOOL      gTransparent  = NO;
static BOOL      gKeyEnabled   = NO;
static UIColor  *gLetterBg     = nil;
static UIColor  *gFuncLBg      = nil;
static UIColor  *gFuncRBg      = nil;
static UIColor  *gSpaceBg      = nil;
static UIColor  *gTextColor    = nil;
static UIColor  *gHighlight    = nil;
static BOOL      gGradEnabled  = NO;
static UIColor  *gGradFrom     = nil;
static UIColor  *gGradTo       = nil;
static NSDictionary *gLetterMap = nil;
static CGFloat   gCorner       = 0.0;
static double    gKbOffset     = 0.0;   // 键盘整体上下位移，正值下移
static NSArray  *gActionOrder  = nil;
static NSDictionary *gActionShow = nil;
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

// 键盘扩展是沙盒进程，读偏好要多种途径兜底。
static NSDictionary *WXKBLoadPrefs(void) {
    NSArray *paths = @[
        @"/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.plist",
        @"/var/jb/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.plist",
    ];
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

// 编辑增强按钮最终清单：用户排序 + 用户显隐，缺项按默认补齐。
static NSArray *WXKBResolvedActions(void) {
    NSMutableArray *out = [NSMutableArray array];
    if ([gActionOrder isKindOfClass:[NSArray class]]) {
        for (id o in gActionOrder) {
            if (![o respondsToSelector:@selector(intValue)]) continue;
            NSNumber *n = @([o intValue]);
            if (![out containsObject:n]) [out addObject:n];
        }
    } else {
        for (int i = 0; i < kWXKBActionCount; i++) {
            [out addObject:@(kWXKBActionCodes[i])];
        }
    }
    for (int i = 0; i < kWXKBActionCount; i++) {
        NSNumber *n = @(kWXKBActionCodes[i]);
        if (![out containsObject:n]) [out addObject:n];
    }
    // 逐个套显隐开关
    NSMutableArray *on = [NSMutableArray array];
    for (NSNumber *n in out) {
        BOOL show = YES;
        if ([gActionShow isKindOfClass:[NSDictionary class]]) {
            id v = gActionShow[n];
            if (v != nil && [v respondsToSelector:@selector(boolValue)]) {
                show = [v boolValue];
            }
        }
        if (show) [on addObject:n];
    }
    return on;
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

    id fl = d[WXKB_KEY_FUNCLIST];
    gFuncList = [fl isKindOfClass:[NSArray class]] ? fl : nil;

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
    gFuncLBg  = WXKBColor(d[WXKB_KEY_FUNC_L_BG], 1.0) ?: legacyFunc
                    ?: [UIColor colorWithWhite:0.66 alpha:1.00];
    gFuncRBg  = WXKBColor(d[WXKB_KEY_FUNC_R_BG], 1.0) ?: legacyFunc
                    ?: [UIColor colorWithWhite:0.66 alpha:1.00];
    gSpaceBg  = WXKBColor(d[WXKB_KEY_SPACE_BG], 1.0)
                    ?: [UIColor colorWithWhite:1.00 alpha:0.96];
    gTextColor = WXKBColor(d[WXKB_KEY_KEY_TEXT], 1.0) ?: [UIColor blackColor];
    gHighlight = WXKBColor(d[WXKB_KEY_KEY_HIGHLIGHT], 1.0)
                     ?: [UIColor colorWithWhite:0.85 alpha:1.00];

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

    // ---- 键盘位置 ----
    id of2 = d[WXKB_KEY_OFFSET];
    gKbOffset = of2 ? [of2 doubleValue] : 0.0;
    if (gKbOffset < -80.0 || gKbOffset > 80.0) {
        gKbOffset = 0.0;
    }

    // ---- 编辑增强 ----
    id ao = d[WXKB_KEY_ACTION_ORDER];
    gActionOrder = [ao isKindOfClass:[NSArray class]] ? ao : nil;
    id as = d[WXKB_KEY_ACTION_SHOW];
    gActionShow = [as isKindOfClass:[NSDictionary class]] ? as : nil;
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

static void WXKBApplyCorner(UIView *v) {
    if (!v || !gEnabled || gCorner <= 0.01) {
        return;
    }
    CGFloat r = MIN(gCorner, MIN(v.bounds.size.height, v.bounds.size.width) / 2.0);
    if (r <= 0.01) {
        return;
    }

    UIView *leaf = WXKBFindBgLeaf(v, 0);
    NSMutableArray *targets = [NSMutableArray arrayWithObject:(leaf ?: v)];
    if (leaf != v) {
        [targets addObject:v];
    }
    for (UIView *t in targets) {
        if (!t) continue;
        if (fabs(t.layer.cornerRadius - r) > 0.01) {
            t.layer.cornerRadius = r;
        }
        if (!t.layer.masksToBounds) {
            t.layer.masksToBounds = YES;
        }
    }
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

static void WXKBClearBgTree(UIView *v) {
    if (!v) return;

    // 按键及其子树一律不动：按键底色/文字色保持用户设置（默认黑字）
    if (WXKBIsKeyView(v)) return;

    // 我们自己插入的背景层不参与，单独处理
    if (v.tag == 0x57584247) {
        for (UIView *s in v.subviews) WXKBClearBgTree(s);
        return;
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

static void WXKBApplyTransparency(UIView *host) {
    if (!host) return;
    if (!gEnabled || !gTransparent) {
        WXKBRestoreBgTree(host);
        return;
    }
    WXKBClearBgTree(host);
}

// —— 键盘整体位移 ——
// 用 transform 平移，原生布局不会把它重置回 identity。
static void WXKBApplyOffset(UIView *root) {
    if (!root) return;
    @try {
        CGAffineTransform t =
            (gEnabled && fabs(gKbOffset) > 0.5)
                ? CGAffineTransformMakeTranslation(0, (CGFloat)gKbOffset)
                : CGAffineTransformIdentity;
        if (!CGAffineTransformEqualToTransform(root.transform, t)) {
            root.transform = t;
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

// 用户配置了清单就严格照办（顺序 + 显隐都由用户说了算）；
// 未配置时用 App 原始列表 + 默认可用功能的并集。
static NSArray *WXKBApplyFuncList(NSArray *in) {
    WXKBReload(NO);
    if (!gEnabled) {
        return in;
    }

    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    if ([gFuncList isKindOfClass:[NSArray class]] && gFuncList.count > 0) {
        for (id o in gFuncList) {
            if (![o respondsToSelector:@selector(intValue)]) {
                continue;
            }
            NSNumber *n = @([o intValue]);
            if (![seen containsObject:n]) {
                [out addObject:n];
                [seen addObject:n];
            }
        }
        return out;
    }

    // 默认（用户没在面板里配过）：只允许「已知功能码」通过，未知的（如隔空投送 /
    // 最近使用 / 收起键盘 / 定制表情 / 拼写检查 这些私有码）一律不显示，
    // 避免塞进去渲染出空白图标，也符合「没有就不显示」。
    NSMutableSet *known = [NSMutableSet set];
    for (int i = 0; i < kWXKBFuncWorksInKbCount; i++) {
        [known addObject:@(kWXKBFuncWorksInKb[i])];
    }
    for (int i = 0; i < kWXKBFuncNeedsHostAppCount; i++) {
        [known addObject:@(kWXKBFuncNeedsHostApp[i])];
    }
    for (id o in in) {
        if (![o respondsToSelector:@selector(intValue)]) {
            continue;
        }
        NSNumber *n = @([o intValue]);
        if (![seen containsObject:n] && [known containsObject:n]) {
            [out addObject:n];
            [seen addObject:n];
        }
    }
    return out;
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
    if (!gEnabled || !gKeyEnabled) {
        return nil;
    }
    switch (WXKBKindOf(v)) {
        case WXKBKeyKindLetter: {
            NSInteger idx = WXKBLetterIndex(v);
            return (idx != NSNotFound) ? WXKBLetterColorFor(idx) : gLetterBg;
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

static UIColor *WXKBKeyText(void) {
    return (gEnabled && gKeyEnabled) ? gTextColor : nil;
}

static UIColor *WXKBKeyHighlight(void) {
    return (gEnabled && gKeyEnabled) ? gHighlight : nil;
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

static UIInputViewController *WXKBInputController(void) {
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
            UIViewController *vc = w.rootViewController;
            while (vc) {
                if ([vc isKindOfClass:[UIInputViewController class]]) {
                    return (UIInputViewController *)vc;
                }
                if ([vc isKindOfClass:[UINavigationController class]]) {
                    UIViewController *c = [(UINavigationController *)vc visibleViewController];
                    if (c && c != vc) { vc = c; continue; }
                }
                vc = vc.presentedViewController;
            }
        }
    } @catch (__unused NSException *e) {
    }
    return nil;
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
static const NSInteger kWXKBActionBarTag = 0x57584142;   // "WXAB" 自定义按钮条 tag
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

// 触摸命中识别：点在我们按钮范围内就直接触发动作；点别处则放行给微信原生处理。
@interface WXKBActionTapRecognizer : UITapGestureRecognizer
@end
@implementation WXKBActionTapRecognizer
- (void)wxkbHandle:(UIGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateEnded) return;
    UIView *sv = g.view;
    if (!sv) return;
    CGPoint p = [self locationInView:sv];
    for (UIView *strip in sv.subviews) {
        if (strip.tag != kWXKBActionBarTag) continue;
        for (UIView *b in strip.subviews) {
            NSNumber *code = objc_getAssociatedObject(b, "wxkbCode");
            if (!code) continue;
            CGRect abs = CGRectMake(strip.frame.origin.x + b.frame.origin.x,
                                   strip.frame.origin.y + b.frame.origin.y,
                                   b.frame.size.width, b.frame.size.height);
            if (CGRectContainsPoint(abs, p)) {
                WXKBFireAction((int)code.integerValue);
                return;
            }
        }
    }
}
@end

static const void *kWXKBTapInstalled = &kWXKBTapInstalled;

static void WXKBInstallTap(UIScrollView *sv) {
    if (!sv || objc_getAssociatedObject(sv, kWXKBTapInstalled)) return;
    WXKBActionTapRecognizer *tg = [[WXKBActionTapRecognizer alloc] init];
    [tg addTarget:tg action:@selector(wxkbHandle:)];
    tg.cancelsTouchesInView = NO;   // 不拦截：原生图标照常可用
    tg.delaysTouchesBegan = NO;
    [sv addGestureRecognizer:tg];
    objc_setAssociatedObject(sv, kWXKBTapInstalled, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static UIImage *WXKBActionImage(int code, CGFloat size) {
    NSString *sf = nil, *fallback = nil;
    switch (code) {
        case WXKB_ACT_SELECT_ALL:  sf = @"selection.pin.in.out"; fallback = @"全"; break;
        case WXKB_ACT_CUT:         sf = @"scissors";             fallback = @"剪"; break;
        case WXKB_ACT_PASTE:       sf = @"doc.on.clipboard";    fallback = @"粘"; break;
        case WXKB_ACT_CURSOR_LEFT: sf = @"arrow.left";          fallback = @"←"; break;
        case WXKB_ACT_CURSOR_RIGHT:sf = @"arrow.right";         fallback = @"→"; break;
        case WXKB_ACT_DELETE_ALL:  sf = @"trash";               fallback = @"清"; break;
        case WXKB_ACT_CLIPBOARD:   sf = @"list.clipboard";      fallback = @"历"; break;
        case WXKB_ACT_PHRASES:     sf = @"text.quote";          fallback = @"语"; break;
        case WXKB_ACT_DISMISS:     sf = @"keyboard.chevron.compact.down"; fallback = @"收"; break;
        case WXKB_ACT_GLOBE:       sf = @"globe";               fallback = @"🌐"; break;
        default: return nil;
    }
    @try {
        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:size
                                                            weight:UIImageSymbolWeightRegular];
        UIImage *img = [UIImage systemImageNamed:sf withConfiguration:cfg];
        if (img) return img;
    } @catch (__unused NSException *e) {
    }
    return nil;
}

// 重建工具栏尾部的自定义按钮条
static void WXKBRebuildActionBar(UIView *bar) {
    if (!bar) return;

    UIScrollView *sv = nil;
    for (UIView *v in bar.subviews) {
        if ([v isKindOfClass:[UIScrollView class]]) { sv = (UIScrollView *)v; break; }
    }
    if (!sv) return;
    WXKBInstallTap(sv);   // 触摸识别靠它，所以无论是否重建都要确保装上

    UIView *old = [bar viewWithTag:kWXKBActionBarTag];
    if (old) {
        // 内容没变就别重建，避免每次 layout 都闪一下
        NSArray *want = WXKBResolvedActions();
        NSMutableArray *have = [NSMutableArray array];
        for (UIView *b in old.subviews) {
            NSNumber *c = objc_getAssociatedObject(b, "wxkbCode");
            if (c) [have addObject:c];
        }
        if ([want isEqualToArray:have] &&
            fabs(old.frame.size.height - sv.bounds.size.height) < 0.5) {
            return;
        }
        [old removeFromSuperview];
    }

    if (!gEnabled) return;
    NSArray *actions = WXKBResolvedActions();
    if (actions.count == 0) return;

    CGSize bd = bar.bounds.size;
    if (bd.height < 10) return;

    // 找到原生最后一个图标，作为插入点
    CGFloat startX = 0;
    for (UIView *v in sv.subviews) {
        CGFloat m = CGRectGetMaxX(v.frame);
        if (m > startX) startX = m;
    }
    if (startX <= 0) {
        startX = sv.contentOffset.x + bd.width * 0.45;
    }
    startX += 10;

    CGFloat btn = MIN(30.0, bd.height * 0.62);
    CGFloat gap = 3.0;

    CGFloat totalW = actions.count * btn + (actions.count - 1) * gap;
    UIView *strip = [[UIView alloc] initWithFrame:
                        CGRectMake(startX, 0, totalW, btn)];
    strip.tag = kWXKBActionBarTag;
    strip.userInteractionEnabled = YES;
    strip.backgroundColor = [UIColor clearColor];

    CGFloat x = 0;
    for (NSNumber *n in actions) {
        int code = n.intValue;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(x, 0, btn, btn);
        b.backgroundColor = [UIColor clearColor];
        b.tag = code;
        UIImage *img = WXKBActionImage(code, btn * 0.52);
        if (img) {
            [b setImage:img forState:UIControlStateNormal];
        } else {
            [b setTitle:@"?" forState:UIControlStateNormal];
        }
        // 透明键盘上按键文字保持黑色，按钮图标跟着黑
        b.tintColor = gKeyEnabled && gTextColor ? gTextColor : [UIColor blackColor];
        [b setTitleColor:b.tintColor forState:UIControlStateNormal];
        b.adjustsImageWhenHighlighted = YES;
        objc_setAssociatedObject(b, "wxkbCode", n, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // 不再用 addTarget：触摸完全交给 sv 上的 UITapGestureRecognizer 处理，
        // 这样即便微信在工具栏层自管触摸 / 挂手势，点按也能稳定触发。
        [strip addSubview:b];
        x += btn + gap;
    }
    strip.frame = CGRectMake(startX, (bd.height - btn) / 2.0, totalW, btn);
    [sv addSubview:strip];

    CGFloat right = CGRectGetMaxX(strip.frame) + 12;
    if (sv.contentSize.width < right) {
        sv.contentSize = CGSizeMake(MAX(right, x), bd.height);
    }
    if (sv.contentSize.width > sv.bounds.size.width + 0.5) {
        sv.scrollEnabled = YES;
    }
}

static void WXKBEnsureActionBar(UIView *bar) {
    if (!bar || WXKBIsEditing(bar)) return;
    @try {
        WXKBRebuildActionBar(bar);
    } @catch (__unused NSException *e) {
    }
}

#pragma mark - Hooks

%hook WBFunctionToolBar

- (BOOL)updateFuncs:(NSArray *)funcs suggestedTypes:(NSArray *)types prefersRecent:(BOOL)prefersRecent {
    NSArray *f = WXKBIsEditing(self) ? funcs : WXKBApplyFuncList(funcs);
    BOOL r = %orig(f, types, prefersRecent);
    WXKBEnsureActionBar(self);
    return r;
}

- (BOOL)updateViewWithFuncs:(NSArray *)funcs {
    NSArray *f = WXKBIsEditing(self) ? funcs : WXKBApplyFuncList(funcs);
    BOOL r = %orig(f);
    WXKBEnsureActionBar(self);
    return r;
}

- (BOOL)updateFuncs:(NSArray *)funcs {
    NSArray *f = WXKBIsEditing(self) ? funcs : WXKBApplyFuncList(funcs);
    BOOL r = %orig(f);
    WXKBEnsureActionBar(self);
    return r;
}

// 关键：永远不缩小。图标保持原生尺寸，溢出交给横向滑动，避免挤成一团。
- (void)setShrunken:(BOOL)shrunken animated:(BOOL)animated completion:(id)completion {
    %orig(NO, animated, completion);
}

// 1.6.1 修复：自定义按钮条点不了。
// 原生工具栏自己接管了触摸（滚动视图或工具栏层的 hitTest 不认我们的子视图），
// 所以在工具栏的 hitTest 入口优先问一遍我们的按钮条：点在按钮上就把事件
// 直接交给按钮，其余情况照常走原生逻辑。
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    @try {
        if (!WXKBIsEditing(self)) {
            UIView *strip = [self viewWithTag:kWXKBActionBarTag];
            if (strip && !strip.hidden && strip.userInteractionEnabled &&
                strip.alpha > 0.01) {
                CGPoint local = [strip convertPoint:p fromView:self];
                if ([strip pointInside:local withEvent:e]) {
                    UIView *hit = [strip hitTest:local withEvent:e];
                    if (hit) return hit;
                }
            }
        }
    } @catch (__unused NSException *e) {
    }
    return %orig;
}

- (void)layoutSubviews {
    %orig;
    WXKBFixScroll(self);
    WXKBEnsureActionBar(self);
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
    // 位移优先作用在最上层「输入视图控制器.view」上（它的位置由系统决定、
    // 不会在原生 layout 里被反复重置）；拿不到时再退回自身。
    UIView *iv = [WXKBInputController() view];
    if (iv && iv != (UIView *)self) {
        WXKBApplyOffset(iv);
    } else {
        WXKBApplyOffset(self);
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
    NSLog(@"[WxkbToolbar10] 1.6.2 loaded enabled=%d funcs=%lu bg=%d trans=%d key=%d grad=%d corner=%.1f offset=%.1f acts=%lu",
          gEnabled, (unsigned long)gFuncList.count, gBgEnabled, gTransparent, gKeyEnabled,
          gGradEnabled, gCorner, gKbOffset, (unsigned long)WXKBResolvedActions().count);
}