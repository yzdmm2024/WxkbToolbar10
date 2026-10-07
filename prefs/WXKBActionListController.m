// WXKBActionListController.m — 「编辑增强」按钮的排序与显隐
// 这些按钮渲染在微信键盘工具栏尾部，提供全选/剪切/粘贴/光标左右/全删/
// 剪贴板历史/快捷短语/收起键盘/切换输入法。
#import "WXKBCommon.h"

static NSString *WXKBActionName(int code) {
    switch (code) {
        case WXKB_ACT_CURSOR_LEFT:  return @"光标左移";
        case WXKB_ACT_CURSOR_RIGHT: return @"光标右移";
        case WXKB_ACT_SELECT_ALL:   return @"全选";
        case WXKB_ACT_CUT:          return @"剪切";
        case WXKB_ACT_PASTE:        return @"粘贴";
        case WXKB_ACT_DELETE_ALL:   return @"全删（清空输入框）";
        case WXKB_ACT_CLIPBOARD:    return @"剪贴板历史";
        case WXKB_ACT_PHRASES:      return @"快捷短语";
        case WXKB_ACT_DISMISS:      return @"收起键盘";
        case WXKB_ACT_GLOBE:        return @"切换输入法";
        default:                    return [NSString stringWithFormat:@"功能 %d", code];
    }
}

// 用户排序后的清单；首次访问写入默认顺序
static NSArray<NSNumber *> *WXKBActionOrder(void) {
    id v = WXKBGetPref(WXKB_KEY_ACTION_ORDER);
    if ([v isKindOfClass:[NSArray class]] && [v count] > 0) {
        NSMutableArray *a = [NSMutableArray array];
        for (id o in v) {
            if ([o respondsToSelector:@selector(intValue)]) {
                [a addObject:@([o intValue])];
            }
        }
        return a;
    }
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < kWXKBActionCount; i++) {
        [a addObject:@(kWXKBActionCodes[i])];
    }
    WXKBSetPref(WXKB_KEY_ACTION_ORDER, a);
    return a;
}

// 显隐字典 { code -> BOOL }；没写过的默认显示
static BOOL WXKBActionShown(int code) {
    NSDictionary *m = WXKBGetPref(WXKB_KEY_ACTION_SHOW);
    if ([m isKindOfClass:[NSDictionary class]]) {
        id v = m[@(code)];
        if (v != nil && [v respondsToSelector:@selector(boolValue)]) {
            return [v boolValue];
        }
    }
    return YES;
}

static void WXKBActionSetShown(int code, BOOL on) {
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    NSDictionary *old = WXKBGetPref(WXKB_KEY_ACTION_SHOW);
    if ([old isKindOfClass:[NSDictionary class]]) {
        [m addEntriesFromDictionary:old];
    }
    m[@(code)] = @(on);
    WXKBSetPref(WXKB_KEY_ACTION_SHOW, m);
}

@interface WXKBActionListController : WXKBBaseListController
@end

@implementation WXKBActionListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"编辑增强按钮";
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    NSArray<NSNumber *> *order = WXKBActionOrder();

    NSMutableArray *on = [NSMutableArray array];
    NSMutableArray *off = [NSMutableArray array];
    for (NSNumber *n in order) {
        if (WXKBActionShown(n.intValue)) {
            [on addObject:n];
        } else {
            [off addObject:n];
        }
    }
    // 用户配表里可能有面板不认识的项，忽略即可（顺序仍以 order 为准）

    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"显示在工具栏上"];
    [g setProperty:@"这一排会追加在微信键盘工具栏的最后，跟随原生图标一起横向滑动。"
             forKey:@"footerText"];
    [s addObject:g];
    for (NSNumber *n in on) {
        PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:WXKBActionName(n.intValue)
                                                         target:self
                                                            set:@selector(setPreferenceValue:specifier:)
                                                            get:@selector(readPreferenceValue:)
                                                         detail:nil
                                                           cell:PSSwitchCell
                                                           edit:nil];
        [sp setProperty:n forKey:@"actionCode"];
        [s addObject:sp];
    }

    g = [PSSpecifier groupSpecifierWithName:@"已隐藏"];
    [g setProperty:@"打开开关即可加回工具栏。" forKey:@"footerText"];
    [s addObject:g];
    for (NSNumber *n in off) {
        PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:WXKBActionName(n.intValue)
                                                         target:self
                                                            set:@selector(setPreferenceValue:specifier:)
                                                            get:@selector(readPreferenceValue:)
                                                         detail:nil
                                                           cell:PSSwitchCell
                                                           edit:nil];
        [sp setProperty:n forKey:@"actionCode"];
        [s addObject:sp];
    }

    g = [PSSpecifier groupSpecifierWithName:@"调整顺序"];
    [g setProperty:@"用上下按钮调整，顺序即工具栏上从左到右的排列。点「上移」把该按钮往左挪一位。"
            forKey:@"footerText"];
    [s addObject:g];
    NSArray<NSNumber *> *seq = order;
    for (NSUInteger i = 0; i < seq.count; i++) {
        NSNumber *n = seq[i];
        NSString *nm = WXKBActionName(n.intValue);
        if (i > 0) {
            [s addObject:[self wxkbMoveRow:[NSString stringWithFormat:@"↑ 上移「%@」", nm]
                                     code:n up:YES]];
        }
        if (i + 1 < seq.count) {
            [s addObject:[self wxkbMoveRow:[NSString stringWithFormat:@"↓ 下移「%@」", nm]
                                     code:n up:NO]];
        }
    }

    _specifiers = s;
    return _specifiers;
}

// 一个「上移 / 下移」按钮行
- (PSSpecifier *)wxkbMoveRow:(NSString *)title code:(NSNumber *)code up:(BOOL)up {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:title
                                                     target:self
                                                        set:nil
                                                        get:nil
                                                     detail:nil
                                                       cell:PSButtonCell
                                                       edit:nil];
    [sp setProperty:code forKey:@"actionCode"];
    sp->action = up ? @selector(moveUp:) : @selector(moveDown:);
    return sp;
}

#pragma mark - 开关

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSNumber *code = [specifier propertyForKey:@"actionCode"];
    return code ? @(WXKBActionShown(code.intValue)) : @YES;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSNumber *code = [specifier propertyForKey:@"actionCode"];
    if (!code) return;
    WXKBActionSetShown(code.intValue, [value boolValue]);
    [[self class] wxkbNotifyChanged];
}

#pragma mark - 排序（用「移到上面 / 移到下面」按钮，避免拖动与开关混排的坑）

- (void)moveUp:(PSSpecifier *)specifier {
    NSNumber *code = [specifier propertyForKey:@"actionCode"];
    if (!code) return;
    NSMutableArray *order = [WXKBActionOrder() mutableCopy];
    NSInteger idx = (NSInteger)[order indexOfObject:code];
    if (idx == NSNotFound || idx <= 0) return;
    [order removeObjectAtIndex:(NSUInteger)idx];
    [order insertObject:code atIndex:(NSUInteger)(idx - 1)];
    WXKBSetPref(WXKB_KEY_ACTION_ORDER, order);
    [[self class] wxkbNotifyChanged];
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)moveDown:(PSSpecifier *)specifier {
    NSNumber *code = [specifier propertyForKey:@"actionCode"];
    if (!code) return;
    NSMutableArray *order = [WXKBActionOrder() mutableCopy];
    NSInteger idx = (NSInteger)[order indexOfObject:code];
    if (idx == NSNotFound || idx < 0 || idx >= (NSInteger)order.count - 1) return;
    [order removeObjectAtIndex:(NSUInteger)idx];
    [order insertObject:code atIndex:(NSUInteger)(idx + 1)];
    WXKBSetPref(WXKB_KEY_ACTION_ORDER, order);
    [[self class] wxkbNotifyChanged];
    _specifiers = nil;
    [self reloadSpecifiers];
}

@end