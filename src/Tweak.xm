// WxkbToolbar10 — 微信输入法键盘扩展增强
// 目标：iPhone 12 Pro / iOS 16.6 / Relaxin rootless (ElleKit TweakInject)
// 注入目标：com.tencent.wetype.keyboard (wxkb_plugin.appex)
//
// 1.5.0 行为：
//   1) 工具栏功能由「设置 → 微信输入法增强」面板决定：可排序、可隐藏、可增删。
//   2) 键盘背景：纯色 / 相册图片（按键盘比例横向裁剪，存 NSData）/ 高级路径，支持透明度。
//   3) 按键配色：四组底色（字母 / 左侧功能 / 右侧功能 / 空格）+ 文字色 + 按下高亮色。
//   4) 字母键支持 A→Z 渐变，以及 26 个字母逐个单独上色。
//   5) 按键圆角可调。
//   6) 保留 1.2.0 的布局修复：工具栏紧贴左侧 logo 铺满整行 + 原生尺寸横向滑动。
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

#pragma mark - 配置

static BOOL      gEnabled      = YES;
static NSArray  *gFuncList     = nil;    // NSNumber 数组，用户配置的顺序
static BOOL      gBgEnabled    = NO;
static int       gBgMode       = 1;      // 1 纯色 2 图片
static CGFloat   gBgAlpha      = 1.0;
static UIColor  *gBgColor      = nil;
static NSString *gBgImage      = nil;
static NSData   *gBgImageData  = nil;
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

static NSArray *WXKBDefaultFuncList(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < kWXKBFuncDefaultOnCount; i++) {
        [a addObject:@(kWXKBFuncDefaultOn[i])];
    }
    return a;
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
    if (gCorner < 0.0 || gCorner > 14.0) {
        gCorner = 0.0;
    }
}

static void WXKBOnPrefsChanged(CFNotificationCenterRef center, void *observer,
                               CFStringRef name, const void *object,
                               CFDictionaryRef userInfo) {
    WXKBReload(YES);
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

    for (id o in in) {
        if (![o respondsToSelector:@selector(intValue)]) {
            continue;
        }
        NSNumber *n = @([o intValue]);
        if (![seen containsObject:n]) {
            [out addObject:n];
            [seen addObject:n];
        }
    }
    for (id o in WXKBDefaultFuncList()) {
        if (![seen containsObject:o]) {
            [out addObject:o];
            [seen addObject:o];
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

#pragma mark - 按键圆角

static void WXKBApplyCorner(UIView *v) {
    if (!v || !gEnabled || gCorner <= 0.01) {
        return;
    }
    CGFloat r = gCorner;
    if (fabs(v.layer.cornerRadius - r) > 0.01) {
        v.layer.cornerRadius = r;
    }
    for (UIView *sub in v.subviews) {
        if (fabs(sub.layer.cornerRadius - r) > 0.01) {
            sub.layer.cornerRadius = r;
        }
        if (!sub.layer.masksToBounds) {
            sub.layer.masksToBounds = YES;
        }
    }
}

#pragma mark - 键盘背景

static const NSInteger kWXKBBgViewTag = 0x57584247;   // "WXBG"

static void WXKBApplyBackground(UIView *host) {
    if (!host) {
        return;
    }
    UIView *bg = [host viewWithTag:kWXKBBgViewTag];
    if (!gEnabled || !gBgEnabled) {
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
    if (gBgMode == 2) {
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
    } else {
        bg.layer.contents = nil;
        bg.backgroundColor = gBgColor;
    }
}

#pragma mark - Hooks

%hook WBFunctionToolBar

- (BOOL)updateFuncs:(NSArray *)funcs suggestedTypes:(NSArray *)types prefersRecent:(BOOL)prefersRecent {
    NSArray *f = WXKBIsEditing(self) ? funcs : WXKBApplyFuncList(funcs);
    return %orig(f, types, prefersRecent);
}

- (BOOL)updateViewWithFuncs:(NSArray *)funcs {
    NSArray *f = WXKBIsEditing(self) ? funcs : WXKBApplyFuncList(funcs);
    return %orig(f);
}

- (BOOL)updateFuncs:(NSArray *)funcs {
    NSArray *f = WXKBIsEditing(self) ? funcs : WXKBApplyFuncList(funcs);
    return %orig(f);
}

// 关键：永远不缩小。图标保持原生尺寸，溢出交给横向滑动，避免挤成一团。
- (void)setShrunken:(BOOL)shrunken animated:(BOOL)animated completion:(id)completion {
    %orig(NO, animated, completion);
}

- (void)layoutSubviews {
    %orig;
    WXKBFixScroll(self);
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
}

%end

%ctor {
    WXKBReload(YES);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL, WXKBOnPrefsChanged,
                                    CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    NSLog(@"[WxkbToolbar10] 1.5.0 loaded enabled=%d funcs=%lu bg=%d key=%d grad=%d corner=%.1f",
          gEnabled, (unsigned long)gFuncList.count, gBgEnabled, gKeyEnabled,
          gGradEnabled, gCorner);
}