// WXKBFuncListController.m — 工具栏功能的排序与显隐
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

// 用户配置的清单；首次访问时用「键盘内可用」的一组功能初始化
static NSArray<NSNumber *> *WXKBEnabledFuncs(void) {
    id v = WXKBGetPref(WXKB_KEY_FUNCLIST);
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
    for (int i = 0; i < kWXKBFuncWorksInKbCount; i++) {
        [a addObject:@(kWXKBFuncWorksInKb[i])];
    }
    WXKBSetPref(WXKB_KEY_FUNCLIST, a);
    return a;
}

// 键盘内已启用的功能码（保持用户顺序）—— 需主 App 的项不在其中
static NSArray<NSNumber *> *WXKBDefaultEnabledSplit(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (NSNumber *n in WXKBEnabledFuncs()) {
        if (!WXKBFuncNeedsHostApp(n.intValue)) [a addObject:n];
    }
    return a;
}

static NSArray<NSNumber *> *WXKBAllFuncs(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < kWXKBFuncWorksInKbCount; i++) {
        [a addObject:@(kWXKBFuncWorksInKb[i])];
    }
    for (int i = 0; i < kWXKBFuncNeedsHostAppCount; i++) {
        [a addObject:@(kWXKBFuncNeedsHostApp[i])];
    }
    return a;
}

@interface WXKBFuncListController : WXKBBaseListController
@end

@implementation WXKBFuncListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"功能排序与显隐";
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    NSArray<NSNumber *> *enabled = WXKBEnabledFuncs();
    NSArray<NSNumber *> *all = WXKBAllFuncs();

    // ---- 分组一：键盘内可用 ----
    NSMutableArray *kbOn = [NSMutableArray array];
    NSMutableArray *kbHidden = [NSMutableArray array];
    for (NSNumber *n in all) {
        if (WXKBFuncNeedsHostApp(n.intValue)) continue;
        if ([enabled containsObject:n]) {
            [kbOn addObject:n];
        } else {
            [kbHidden addObject:n];
        }
    }
    // 已显示列表里可能残留了旧的「需主 App」项，保持用户顺序但并入对应分组
    for (NSNumber *n in enabled) {
        if (!WXKBFuncNeedsHostApp(n.intValue) && ![kbOn containsObject:n]) {
            [kbOn addObject:n];
        }
    }

    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"键盘内可用（点了有反应）"];
    [g setProperty:@"点右上角「编辑」可拖动排序、左滑隐藏。"
            forKey:@"footerText"];
    [s addObject:g];
    for (NSNumber *n in kbOn) {
        PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:WXKBFuncName(n.intValue)
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSStaticTextCell
                                                           edit:nil];
        [sp setProperty:n forKey:@"funcCode"];
        [sp setProperty:@NO forKey:@"wxkbHostOnly"];
        [s addObject:sp];
    }

    // ---- 分组二：需主 App（永不显示） ----
    // 1.6.9：这组改为纯信息展示。之前它们躺在启用清单里就会画到工具栏上（用户截图
    // 实锤：8 个「无反应」图标全来自清单残留），且面板分组样式让用户以为「单独分组
    // = 已关闭」。现在键盘侧统一拦截，面板明确标注「不会显示」。
    g = [PSSpecifier groupSpecifierWithName:@"需微信主 App（不会显示）"];
    [g setProperty:@"这几项必须由微信主 App 处理，键盘扩展进程里点了没有任何反应，"
                  @"工具栏永远不显示（清单里残留的也会被自动忽略）。"
            forKey:@"footerText"];
    [s addObject:g];
    for (NSNumber *n in all) {
        if (!WXKBFuncNeedsHostApp(n.intValue)) continue;
        PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:
                              [WXKBFuncName(n.intValue) stringByAppendingString:@"（无反应）"]
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSStaticTextCell
                                                           edit:nil];
        [s addObject:sp];
    }

    // ---- 分组三：已隐藏 ----
    if (kbHidden.count > 0) {
        g = [PSSpecifier groupSpecifierWithName:@"已隐藏（点击加回工具栏）"];
        [g setProperty:@"点击任意一项即可重新加回工具栏。" forKey:@"footerText"];
        [s addObject:g];
        for (NSNumber *n in kbHidden) {
            PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:WXKBFuncName(n.intValue)
                                                             target:self
                                                                set:nil
                                                                get:nil
                                                             detail:nil
                                                               cell:PSButtonCell
                                                               edit:nil];
            [sp setProperty:n forKey:@"funcCode"];
            sp->action = @selector(addFunc:);
            [s addObject:sp];
        }
    }

    _specifiers = s;
    return _specifiers;
}

// 「已显示」区从第 1 行开始
- (NSUInteger)visibleOffset {
    return 1;
}

// specifiers 里「已显示」区的顺序：只含键盘内可用的启用项
// （1.6.9 起需主 App 的项永不进工具栏，也不再算可见行）
static NSArray<NSNumber *> *WXKBOrderedVisible(void) {
    return WXKBDefaultEnabledSplit();
}

- (NSUInteger)visibleCount {
    return WXKBOrderedVisible().count;
}

- (void)saveEnabled:(NSArray<NSNumber *> *)list {
    // 1.6.9：需主 App 的码不落盘（键盘侧也会拦截，这里从源头清理）
    NSMutableArray *clean = [NSMutableArray array];
    for (NSNumber *n in list) {
        if (![n respondsToSelector:@selector(intValue)]) continue;
        if (WXKBFuncNeedsHostApp(n.intValue)) continue;
        if (![clean containsObject:n]) [clean addObject:n];
    }
    WXKBSetPref(WXKB_KEY_FUNCLIST, clean);
    [[self class] wxkbNotifyChanged];
    [self reloadSpecifiers];
}

- (void)addFunc:(PSSpecifier *)specifier {
    NSNumber *code = [specifier propertyForKey:@"funcCode"];
    if (!code) {
        return;
    }
    // 1.6.9：需主 App 的项点了永远没反应，不再允许加回工具栏
    if (WXKBFuncNeedsHostApp(code.intValue)) {
        return;
    }
    NSMutableArray *list = [WXKBEnabledFuncs() mutableCopy];
    if (![list containsObject:code]) {
        [list addObject:code];
    }
    [self saveEnabled:list];
}

#pragma mark - 编辑（排序 / 隐藏）

- (BOOL)isVisibleRow:(NSIndexPath *)indexPath {
    NSUInteger n = [self visibleCount];
    return indexPath.row >= (NSInteger)[self visibleOffset] &&
           indexPath.row < (NSInteger)[self visibleOffset] + (NSInteger)n;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isVisibleRow:indexPath];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isVisibleRow:indexPath];
}

// 映射 specifier 行号 <-> 启用清单下标
- (NSNumber *)codeAtRow:(NSInteger)row {
    NSArray *ordered = WXKBOrderedVisible();
    NSInteger idx = row - (NSInteger)[self visibleOffset];
    if (idx < 0 || idx >= (NSInteger)ordered.count) return nil;
    return ordered[(NSUInteger)idx];
}

- (NSInteger)rowForCode:(NSNumber *)code {
    NSArray *ordered = WXKBOrderedVisible();
    NSInteger idx = (NSInteger)[ordered indexOfObject:code];
    if (idx == NSNotFound) return NSNotFound;
    return idx + (NSInteger)[self visibleOffset];
}

- (NSIndexPath *)tableView:(UITableView *)tableView
    targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
                         toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    NSInteger lo = (NSInteger)[self visibleOffset];
    NSInteger hi = lo + (NSInteger)[self visibleCount] - 1;
    if ((NSInteger)proposedDestinationIndexPath.row > hi) {
        return [NSIndexPath indexPathForRow:hi inSection:proposedDestinationIndexPath.section];
    }
    if ((NSInteger)proposedDestinationIndexPath.row < lo) {
        return [NSIndexPath indexPathForRow:lo inSection:proposedDestinationIndexPath.section];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSNumber *moving = [self codeAtRow:sourceIndexPath.row];
    NSNumber *landing = [self codeAtRow:destinationIndexPath.row];
    if (!moving || !landing) return;

    NSMutableArray *list = [WXKBEnabledFuncs() mutableCopy];
    NSInteger from = (NSInteger)[list indexOfObject:moving];
    NSInteger to = (NSInteger)[list indexOfObject:landing];
    if (from == NSNotFound || to == NSNotFound) return;
    [list removeObjectAtIndex:(NSUInteger)from];
    [list insertObject:moving atIndex:(NSUInteger)to];
    [self saveEnabled:list];
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    NSNumber *code = [self codeAtRow:indexPath.row];
    if (!code) return;
    NSMutableArray *list = [WXKBEnabledFuncs() mutableCopy];
    NSInteger idx = (NSInteger)[list indexOfObject:code];
    if (idx == NSNotFound) return;
    [list removeObjectAtIndex:(NSUInteger)idx];
    [self saveEnabled:list];
}

@end