// WxkbToolbar10 — 微信输入法键盘扩展工具栏图标扩展 + 自动缩小铺满
// 目标：iPhone 12 Pro / iOS 16.6 / Relaxin rootless (ElleKit TweakInject)
// 注入目标：com.tencent.wetype.keyboard (wxkb_plugin.appex)
//
// 原理：
//   1) WBFunctionToolBar 的功能列表由 funcs(NSNumber 数组) 决定，拦截更新入口把 funcs
//      补齐到 WXKB_TARGET_FUNCS 个。
//   2) 默认布局是固定 34pt 宽 + 12pt 间距的横向 UIScrollView：图标变多只会「横向滑动」，
//      并不会缩小。因此再拦截布局入口，在按钮溢出时把它们重排为等宽铺满可视宽度，
//      并把 contentSize 收敛为可视尺寸（即「自动缩小铺满、不滑动」）。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 目标功能图标个数（不含工具栏右侧固定的「＋」）
#define WXKB_TARGET_FUNCS 10

// 补齐顺序：优先加入这几个，再按备选表补足
static const int kWXKBExtras[] = {
    2, 3, 31, 32,   // 表情 / 常用语 / 剪贴板 / 问AI
    16, 36, 35, 29, 33, 14, 18, 27, 17, 28, 20, 1
};
static const int kWXKBExtrasCount = (int)(sizeof(kWXKBExtras) / sizeof(kWXKBExtras[0]));

// 让编译器认识工具栏的私有 getter（实现由原类提供）
@interface NSObject (WXKBEditing)
- (BOOL)editing;
@end

static NSArray *WXKBExpandFuncs(NSArray *in) {
    if (![in isKindOfClass:[NSArray class]]) {
        return in;
    }
    if ((int)[in count] >= WXKB_TARGET_FUNCS) {
        return in;
    }

    NSMutableArray *out = [NSMutableArray arrayWithArray:in];
    NSMutableSet *have = [NSMutableSet set];
    for (id o in in) {
        if ([o respondsToSelector:@selector(intValue)]) {
            [have addObject:@([o intValue])];
        }
    }

    for (int i = 0; i < kWXKBExtrasCount && (int)[out count] < WXKB_TARGET_FUNCS; i++) {
        NSNumber *n = @(kWXKBExtras[i]);
        if (![have containsObject:n]) {
            [out addObject:n];
            [have addObject:n];
        }
    }
    return out;
}

// 编辑（定制工具栏）状态下保持原样，避免干扰拖拽排序
static BOOL WXKBIsEditing(id bar) {
    if ([bar respondsToSelector:@selector(editing)]) {
        return [bar editing];
    }
    return NO;
}

static UIScrollView *WXKBFindScroll(UIView *bar) {
    for (UIView *v in bar.subviews) {
        if ([v isKindOfClass:[UIScrollView class]]) {
            return (UIScrollView *)v;
        }
    }
    return nil;
}

static BOOL WXKBIsToolBarButton(UIView *v) {
    NSString *cn = NSStringFromClass([v class]);
    return [cn containsString:@"ToolBarButton"] && ![cn containsString:@"Indicator"];
}

// 溢出时把功能按钮等宽铺满可视宽度，并收敛 contentSize（取消滑动）
static void WXKBRefill(id bar) {
    UIView *barView = (UIView *)bar;
    UIScrollView *sv = WXKBFindScroll(barView);
    if (!sv) {
        return;
    }
    if (WXKBIsEditing(bar)) {
        sv.scrollEnabled = YES;   // 编辑态恢复滑动，避免影响拖拽排序
        return;
    }

    CGRect b = sv.bounds;
    if (b.size.width <= 0 || b.size.height <= 0) {
        return;
    }

    NSMutableArray<UIView *> *btns = [NSMutableArray array];
    for (UIView *v in sv.subviews) {
        if (WXKBIsToolBarButton(v)) {
            [btns addObject:v];
        }
    }
    NSUInteger n = btns.count;
    if (n < 2) {
        return;
    }

    // 仅在「图标溢出」或「已扩容到多图标」时铺满，普通少量图标保持原样
    BOOL overflow = sv.contentSize.width > b.size.width + 0.5;
    if (!overflow && n < 8) {
        return;
    }

    CGFloat slot = b.size.width / (CGFloat)n;
    for (NSUInteger i = 0; i < n; i++) {
        btns[i].frame = CGRectMake(slot * (CGFloat)i, 0, slot, b.size.height);
    }
    sv.contentSize = b.size;
    sv.scrollEnabled = NO;
}

%hook WBFunctionToolBar

- (BOOL)updateFuncs:(NSArray *)funcs suggestedTypes:(NSArray *)types prefersRecent:(BOOL)prefersRecent {
    NSArray *f = WXKBIsEditing(self) ? funcs : WXKBExpandFuncs(funcs);
    return %orig(f, types, prefersRecent);
}

- (BOOL)updateViewWithFuncs:(NSArray *)funcs {
    NSArray *f = WXKBIsEditing(self) ? funcs : WXKBExpandFuncs(funcs);
    return %orig(f);
}

- (BOOL)updateFuncs:(NSArray *)funcs {
    NSArray *f = WXKBIsEditing(self) ? funcs : WXKBExpandFuncs(funcs);
    return %orig(f);
}

- (void)layoutSubviews {
    %orig;
    WXKBRefill(self);
}

- (void)layoutForAnimated:(BOOL)animated animateFinishedBlock:(id)block {
    %orig(animated, block);
    WXKBRefill(self);
}

%end

%ctor {
    Class c = objc_getClass("WBFunctionToolBar");
    if (c) {
        Method m = class_getInstanceMethod(c, @selector(updateFuncs:suggestedTypes:prefersRecent:));
        Method m2 = class_getInstanceMethod(c, @selector(updateViewWithFuncs:));
        Method m3 = class_getInstanceMethod(c, @selector(layoutSubviews));
        NSLog(@"[WxkbToolbar10] loaded target=%d enc3=%s encView=%s encLayout=%s",
              WXKB_TARGET_FUNCS,
              m ? method_getTypeEncoding(m) : "nil",
              m2 ? method_getTypeEncoding(m2) : "nil",
              m3 ? method_getTypeEncoding(m3) : "nil");
    } else {
        NSLog(@"[WxkbToolbar10] WBFunctionToolBar not found at load");
    }
}