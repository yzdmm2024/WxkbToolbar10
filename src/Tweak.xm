// WxkbToolbar10 — 微信输入法键盘扩展工具栏增强
// 目标：iPhone 12 Pro / iOS 16.6 / Relaxin rootless (ElleKit TweakInject)
// 注入目标：com.tencent.wetype.keyboard (wxkb_plugin.appex)
//
// 1.2.0 行为：
//   1) 把「定制工具栏」控制中心里提供的全部功能补进工具栏（与 App 自带功能取并集）。
//   2) 禁止「自动缩小铺满」：拦截 setShrunken:，图标始终保持原生尺寸。
//   3) 图标超出可视宽度时恢复横向滑动。
//   4) 工具栏左移，紧贴左侧固定按钮（微信 logo）排列，消除两者之间的空白；
//      工具栏与内部滚动容器一起铺满整行剩余宽度，右侧不再留空。
//
// 说明：原生布局把 WBFunctionToolBar 固定在 x=102 / 宽 288（WBTopBar 宽 390），
//       logo 右边界只有 46，于是 logo 与第一个图标之间空出约 68pt 且无法滑入。
//       1.2.0 在 WBTopBar 布局完成后把工具栏重定位到 logo 右边界并撑满剩余宽度。

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 「定制工具栏」控制中心里的全部功能 id（tag）：
//   1 语音转文字   2 表情       3 常用语     5 边写边译    14 小程序
//   16 手写找字    17 单手模式  18 键盘调节  20 键盘选择   27 繁体输入
//   28 定制工具栏  29 灵动表达  31 剪贴板    32 问 AI      33 字体滤镜
//   35 排版成图    36 文字整理
static const int kWXKBCustomFuncs[] = {
    1, 2, 3, 5, 14, 16, 17, 18, 20, 27, 28, 29, 31, 32, 33, 35, 36
};
static const int kWXKBCustomFuncsCount =
    (int)(sizeof(kWXKBCustomFuncs) / sizeof(kWXKBCustomFuncs[0]));

// 私有类声明（Logos 生成 category 需要类名可见；实现由原 App 提供）
@interface WBFunctionToolBar : UIView
@end

@interface WBTopBar : UIView
@end

// 让编译器认识工具栏的私有 getter（实现由原类提供）
@interface NSObject (WXKBEditing)
- (BOOL)editing;
@end

static BOOL WXKBIsEditing(id bar) {
    if ([bar respondsToSelector:@selector(editing)]) {
        return [bar editing];
    }
    return NO;
}

// 与 App 传入的功能列表取并集，补齐「定制工具栏」里的全部功能
static NSArray *WXKBExpandFuncs(NSArray *in) {
    if (![in isKindOfClass:[NSArray class]]) {
        return in;
    }

    NSMutableArray *out = [NSMutableArray arrayWithArray:in];
    NSMutableSet *have = [NSMutableSet set];
    for (id o in in) {
        if ([o respondsToSelector:@selector(intValue)]) {
            [have addObject:@([o intValue])];
        }
    }

    for (int i = 0; i < kWXKBCustomFuncsCount; i++) {
        NSNumber *n = @(kWXKBCustomFuncs[i]);
        if (![have containsObject:n]) {
            [out addObject:n];
            [have addObject:n];
        }
    }
    return out;
}

// 左侧固定按钮（微信 logo 等）的最右边界：与工具栏同处一行、竖直相交、且完全在工具栏左侧。
// 取所有候选中的最大右边界，作为工具栏新的起始 x。
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
            continue;   // 忽略零碎小视图（如 10x10 的 tips 占位）
        }
        if (CGRectGetMaxX(f) > CGRectGetMinX(row) + 0.5) {
            continue;   // 必须完全在工具栏左侧
        }
        if (CGRectGetMaxY(f) < CGRectGetMinY(row) + 0.5) {
            continue;   // 必须与本行竖直相交
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

// 让工具栏紧贴左侧固定按钮并铺满整行剩余宽度；内部滚动容器同步铺满工具栏。
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

        CGSize bd = bar.bounds.size;
        for (UIView *sub in bar.subviews) {
            if (![sub isKindOfClass:[UIScrollView class]]) {
                continue;
            }
            CGRect sf = sub.frame;
            if (fabs(sf.origin.x) > 0.5 || fabs(sf.origin.y) > 0.5 ||
                fabs(sf.size.width - bd.width) > 0.5 ||
                fabs(sf.size.height - bd.height) > 0.5) {
                sub.frame = CGRectMake(0, 0, bd.width, bd.height);
            }
            UIScrollView *sv = (UIScrollView *)sub;
            if (sv.contentSize.width > sv.bounds.size.width + 0.5) {
                sv.scrollEnabled = YES;
            }
            break;
        }
        break;
    }
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

// 关键：永远不缩小。图标保持原生尺寸，溢出交给横向滑动，避免挤成一团。
- (void)setShrunken:(BOOL)shrunken animated:(BOOL)animated completion:(id)completion {
    %orig(NO, animated, completion);
}

- (void)layoutSubviews {
    %orig;
    // 滚动容器始终铺满工具栏；内容溢出可视宽度时确保可以横向滑动
    CGSize bd = self.bounds.size;
    for (UIView *v in self.subviews) {
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

%end

// WBTopBar 承载候选栏与工具栏；在它自身布局完成后重定位工具栏，避免被原生布局改回 x=102。
%hook WBTopBar

- (void)layoutSubviews {
    %orig;
    WXKBFillRow(self);
}

%end

%ctor {
    Class c = objc_getClass("WBFunctionToolBar");
    Class t = objc_getClass("WBTopBar");
    if (c) {
        Method m = class_getInstanceMethod(c, @selector(updateFuncs:suggestedTypes:prefersRecent:));
        Method m2 = class_getInstanceMethod(c, @selector(updateViewWithFuncs:));
        Method m3 = class_getInstanceMethod(c, @selector(setShrunken:animated:completion:));
        NSLog(@"[WxkbToolbar10] 1.2.0 loaded custom=%d topBar=%s enc3=%s encView=%s encShrink=%s",
              kWXKBCustomFuncsCount,
              t ? "yes" : "no",
              m ? method_getTypeEncoding(m) : "nil",
              m2 ? method_getTypeEncoding(m2) : "nil",
              m3 ? method_getTypeEncoding(m3) : "nil");
    } else {
        NSLog(@"[WxkbToolbar10] WBFunctionToolBar not found at load");
    }
}