// WxkbToolbar10 — 微信输入法键盘扩展工具栏增强
// 目标：iPhone 12 Pro / iOS 16.6 / Relaxin rootless (ElleKit TweakInject)
// 注入目标：com.tencent.wetype.keyboard (wxkb_plugin.appex)
//
// 1.1.0 行为：
//   1) 把「定制工具栏」控制中心里提供的全部功能补进工具栏（与 App 自带功能取并集），
//      这样每个功能都能从工具栏直接取用。
//   2) 禁止「自动缩小铺满」：拦截 setShrunken:，图标始终保持原生尺寸。
//   3) 图标超出可视宽度时恢复横向滑动，左右滑动即可选取，不再挤成一团。

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
    // 图标溢出可视宽度时，确保可以横向滑动选取
    for (UIView *v in self.subviews) {
        if (![v isKindOfClass:[UIScrollView class]]) {
            continue;
        }
        UIScrollView *sv = (UIScrollView *)v;
        if (sv.contentSize.width > sv.bounds.size.width + 0.5) {
            sv.scrollEnabled = YES;
        }
        break;
    }
}

%end

%ctor {
    Class c = objc_getClass("WBFunctionToolBar");
    if (c) {
        Method m = class_getInstanceMethod(c, @selector(updateFuncs:suggestedTypes:prefersRecent:));
        Method m2 = class_getInstanceMethod(c, @selector(updateViewWithFuncs:));
        Method m3 = class_getInstanceMethod(c, @selector(setShrunken:animated:completion:));
        NSLog(@"[WxkbToolbar10] loaded custom=%d enc3=%s encView=%s encShrink=%s",
              kWXKBCustomFuncsCount,
              m ? method_getTypeEncoding(m) : "nil",
              m2 ? method_getTypeEncoding(m2) : "nil",
              m3 ? method_getTypeEncoding(m3) : "nil");
    } else {
        NSLog(@"[WxkbToolbar10] WBFunctionToolBar not found at load");
    }
}