// WXKBFuncListController.m — 工具栏功能显隐（开关式 + 自定义顺序）
#import "WXKBCommon.h"

static NSDictionary *WXKBFuncNames(void) {
    static NSDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{
            @1:  @"语音转文字",
            @2:  @"表情",
            @3:  @"常用语",
            @5:  @"边写边译",
            @16: @"手写找字",
            @17: @"单手模式",
            @18: @"键盘调节",
            @20: @"键盘选择",
            @27: @"繁体输入",
            @28: @"定制工具栏",
            @31: @"剪贴板",
            @14: @"小程序",
            @29: @"灵动表达",
            @32: @"问 AI",
            @33: @"字体滤镜",
            @35: @"排版成图",
            @36: @"文字整理"
        };
    });
    return d;
}

static NSString *WXKBFuncName(int code) {
    return WXKBFuncNames()[@(code)] ?: [NSString stringWithFormat:@"功能 %d", code];
}

// 这几项点了必须由微信主 App 处理，键盘扩展进程里必然无响应。
// 之前混在同一个列表里，用户按了没反应又不知道原因，所以单独分组并写清楚。
static BOOL WXKBFuncNeedsHostApp(int code) {
    for (int i = 0; i < kWXKBFuncNeedsHostAppCount; i++) {
        if (kWXKBFuncNeedsHostApp[i] == code) return YES;
    }
    return NO;
}

@interface WXKBFuncListController : WXKBBaseListController {
    BOOL _reordering;
}
@end

@implementation WXKBFuncListController

// 键盘内可用功能的当前顺序（用户可拖动调整）。返回 NSArray<NSNumber>。
- (NSArray *)funcOrder {
    id o = WXKBGetPref(WXKB_KEY_FUNC_ORDER);
    NSMutableArray *arr = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    if ([o isKindOfClass:[NSArray class]]) {
        for (id x in o) {
            NSNumber *n = [x isKindOfClass:[NSNumber class]] ? x
                : ([x respondsToSelector:@selector(intValue)] ? @([x intValue]) : nil);
            if (!n) continue;
            BOOL known = NO;
            for (int i = 0; i < kWXKBFuncWorksInKbCount; i++) {
                if (kWXKBFuncWorksInKb[i] == [n intValue]) { known = YES; break; }
            }
            if (!known || [seen containsObject:n]) continue;
            [arr addObject:n];
            [seen addObject:n];
        }
    }
    // 保证全部内置功能都在，缺失的补到末尾（防止偏好写坏导致漏功能）
    for (int i = 0; i < kWXKBFuncWorksInKbCount; i++) {
        NSNumber *n = @(kWXKBFuncWorksInKb[i]);
        if (![seen containsObject:n]) [arr addObject:n];
    }
    return arr;
}

- (void)ensureFuncOrder {
    id o = WXKBGetPref(WXKB_KEY_FUNC_ORDER);
    if ([o isKindOfClass:[NSArray class]] && [o count] > 0) {
        return;
    }
    NSMutableArray *def = [NSMutableArray array];
    for (int i = 0; i < kWXKBFuncWorksInKbCount; i++) {
        [def addObject:@(kWXKBFuncWorksInKb[i])];
    }
    WXKBSetPref(WXKB_KEY_FUNC_ORDER, def);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"功能显隐";

    // 旧版用单个 funcList 数组存储显隐，这里迁移成「每个功能一个独立开关键」，
    // 只跑一次：键盘内可用的功能按旧数组里是否出现决定开/关，然后删掉旧键。
    id old = WXKBGetPref(WXKB_KEY_FUNCLIST);
    if ([old isKindOfClass:[NSArray class]] && [old count] > 0) {
        NSMutableSet *inOld = [NSMutableSet set];
        for (id o in old) {
            if ([o respondsToSelector:@selector(intValue)]) {
                [inOld addObject:@([o intValue])];
            }
        }
        for (int i = 0; i < kWXKBFuncWorksInKbCount; i++) {
            int code = kWXKBFuncWorksInKb[i];
            WXKBSetPref(WXKB_FUNC_ON_KEY(code), @([inOld containsObject:@(code)]));
        }
        WXKBSetPref(WXKB_KEY_FUNCLIST, nil);
    }

    // 首次进入面板时，把所有开关键补齐默认值（键盘内可用默认开，需主 App 默认关）。
    for (int i = 0; i < kWXKBFuncWorksInKbCount; i++) {
        int code = kWXKBFuncWorksInKb[i];
        if (WXKBGetPref(WXKB_FUNC_ON_KEY(code)) == nil) {
            WXKBSetPref(WXKB_FUNC_ON_KEY(code), @YES);
        }
    }
    for (int i = 0; i < kWXKBFuncNeedsHostAppCount; i++) {
        int code = kWXKBFuncNeedsHostApp[i];
        if (WXKBGetPref(WXKB_FUNC_ON_KEY(code)) == nil) {
            WXKBSetPref(WXKB_FUNC_ON_KEY(code), @NO);
        }
    }

    // 自定义顺序：保证偏好里有一份默认顺序
    [self ensureFuncOrder];

    // 右上角「排序」按钮：进入/退出拖动模式
    UIBarButtonItem *sort = [[UIBarButtonItem alloc] initWithTitle:@"排序"
                                                            style:UIBarButtonItemStylePlain
                                                           target:self
                                                           action:@selector(toggleSort)];
    self.navigationItem.rightBarButtonItem = sort;
}

- (void)toggleSort {
    _reordering = !_reordering;
    [self setEditing:_reordering animated:YES];
    self.navigationItem.rightBarButtonItem.title = _reordering ? @"完成" : @"排序";
    if (!_reordering) {
        // 退出排序：按新顺序重建列表
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

// 开关变化后刷新顺位编号（关闭/开启会让后面功能的工具栏顺位前移/后移）
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    if (!_reordering) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];

    // ---- 分组一：键盘内可用（开启即显示在工具栏）----
    // 本组从上到下 = 微信键盘工具栏从左到右（数字＝工具栏顺位）。
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"键盘内可用（开启即显示在工具栏）"];
    [g setProperty:@"本组从上到下 = 微信键盘工具栏从左到右，数字即工具栏顺位。"
                    @"开启的功能显示在工具栏上，关闭的移除。右上角「排序」可拖动调整左右顺序。"
            forKey:@"footerText"];
    [s addObject:g];

    NSArray *order = [self funcOrder];
    int slot = 0;
    for (NSUInteger i = 0; i < [order count]; i++) {
        int code = [order[i] intValue];
        id onv = WXKBGetPref(WXKB_FUNC_ON_KEY(code));
        BOOL on = onv ? [onv boolValue] : YES;
        NSString *name = WXKBFuncName(code);
        if (on) {
            slot++;
            name = [NSString stringWithFormat:@"%d. %@", slot, name];
        }
        [s addObject:[self wxkbSwitch:name
                                  key:WXKB_FUNC_ON_KEY(code)
                                  def:YES]];
    }

    // ---- 分组二：需微信主 App（开启也不会显示）----
    g = [PSSpecifier groupSpecifierWithName:@"需微信主 App（开启也不会显示）"];
    [g setProperty:@"这几项由微信主程序处理，键盘扩展进程里点了没有任何反应，"
                  @"工具栏永远不显示；开关仅供查看，默认关闭。"
            forKey:@"footerText"];
    [s addObject:g];
    for (int i = 0; i < kWXKBFuncNeedsHostAppCount; i++) {
        int code = kWXKBFuncNeedsHostApp[i];
        [s addObject:[self wxkbSwitch:[WXKBFuncName(code) stringByAppendingString:@"（主App）"]
                                  key:WXKB_FUNC_ON_KEY(code)
                                  def:NO]];
    }

    _specifiers = s;
    return _specifiers;
}

#pragma mark - 拖动排序（仅本组可用）

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    // 只让「键盘内可用」分组里功能行可编辑（row 0 是分组标题，不可动）
    return ip.section == 0 && ip.row > 0;
}

- (BOOL)tableView:(UITableView *)tv canMoveRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == 0 && ip.row > 0;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tv
        editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tv
    shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)ip {
    return NO;
}

- (void)tableView:(UITableView *)tv
    moveRowAtIndexPath:(NSIndexPath *)from
           toIndexPath:(NSIndexPath *)to {
    if (from.row < 1 || to.row < 1) {
        return;   // 分组标题不参与
    }
    NSMutableArray *order = [[self funcOrder] mutableCopy];
    NSInteger f = from.row - 1;
    NSInteger t = to.row - 1;
    if (f < 0 || t < 0 || f >= (NSInteger)order.count || t >= (NSInteger)order.count) {
        return;
    }
    id obj = [order objectAtIndex:f];
    [order removeObjectAtIndex:f];
    [order insertObject:obj atIndex:t];
    WXKBSetPref(WXKB_KEY_FUNC_ORDER, order);
    [[self class] wxkbNotifyChanged];
    // 同步本控制器自身 specifiers 顺序（row0 是分组标题），保持与拖动后的视觉一致，
    // 避免连续拖动时数据与显示错位；退出排序时再按新顺序重建以刷新顺位编号。
    if (_specifiers && (f + 1) < (NSInteger)[_specifiers count]
                   && (t + 1) < (NSInteger)[_specifiers count]) {
        NSMutableArray *spc = (NSMutableArray *)_specifiers;
        id sp = [spc objectAtIndex:f + 1];
        [spc removeObjectAtIndex:f + 1];
        [spc insertObject:sp atIndex:t + 1];
    }
}

@end
