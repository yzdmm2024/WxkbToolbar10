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
            @14: @"小程序（需主 App）",
            @29: @"灵动表达（需主 App）",
            @32: @"问 AI（需主 App）",
            @33: @"字体滤镜（需主 App）",
            @35: @"排版成图（需主 App）",
            @36: @"文字整理（需主 App）"
        };
    });
    return d;
}

static NSString *WXKBFuncName(int code) {
    return WXKBFuncNames()[@(code)] ?: [NSString stringWithFormat:@"功能 %d", code];
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
    for (int i = 0; i < kWXKBFuncDefaultOnCount; i++) {
        [a addObject:@(kWXKBFuncDefaultOn[i])];
    }
    WXKBSetPref(WXKB_KEY_FUNCLIST, a);
    return a;
}

static NSArray<NSNumber *> *WXKBAllFuncs(void) {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 0; i < kWXKBFuncCount; i++) {
        [a addObject:@(kWXKBFuncCodes[i])];
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

    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"已显示"];
    [g setProperty:@"点右上角「编辑」可拖动排序、左滑隐藏。" forKey:@"footerText"];
    [s addObject:g];
    for (NSNumber *n in enabled) {
        PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:WXKBFuncName(n.intValue)
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSStaticTextCell
                                                           edit:nil];
        [sp setProperty:n forKey:@"funcCode"];
        [s addObject:sp];
    }

    g = [PSSpecifier groupSpecifierWithName:@"已隐藏"];
    [g setProperty:@"点击任意一项即可重新加回工具栏。" forKey:@"footerText"];
    [s addObject:g];
    for (NSNumber *n in WXKBAllFuncs()) {
        if ([enabled containsObject:n]) {
            continue;
        }
        PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:WXKBFuncName(n.intValue)
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
        [sp setProperty:n forKey:@"funcCode"];
        [sp setProperty:@selector(addFunc:) forKey:@"action"];
        [s addObject:sp];
    }

    _specifiers = s;
    return _specifiers;
}

- (NSUInteger)enabledCount {
    return WXKBEnabledFuncs().count;
}

- (void)saveEnabled:(NSArray<NSNumber *> *)list {
    WXKBSetPref(WXKB_KEY_FUNCLIST, list);
    [[self class] wxkbNotifyChanged];
    [self reloadSpecifiers];
}

- (void)addFunc:(PSSpecifier *)specifier {
    NSNumber *code = [specifier propertyForKey:@"funcCode"];
    if (!code) {
        return;
    }
    NSMutableArray *list = [WXKBEnabledFuncs() mutableCopy];
    if (![list containsObject:code]) {
        [list addObject:code];
    }
    [self saveEnabled:list];
}

#pragma mark - 编辑（排序 / 隐藏）

- (NSInteger)enabledOffset {
    return 1;   // 前面有一个分组行
}

- (BOOL)isEnabledRow:(NSIndexPath *)indexPath {
    NSUInteger n = [self enabledCount];
    return indexPath.row >= [self enabledOffset] &&
           indexPath.row < [self enabledOffset] + (NSInteger)n;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isEnabledRow:indexPath];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isEnabledRow:indexPath];
}

- (NSIndexPath *)tableView:(UITableView *)tableView
    targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
                         toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    NSInteger lo = [self enabledOffset];
    NSInteger hi = lo + (NSInteger)[self enabledCount] - 1;
    if (proposedDestinationIndexPath.row > hi) {
        return [NSIndexPath indexPathForRow:hi inSection:proposedDestinationIndexPath.section];
    }
    if (proposedDestinationIndexPath.row < lo) {
        return [NSIndexPath indexPathForRow:lo inSection:proposedDestinationIndexPath.section];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray *list = [WXKBEnabledFuncs() mutableCopy];
    NSInteger from = sourceIndexPath.row - [self enabledOffset];
    NSInteger to = destinationIndexPath.row - [self enabledOffset];
    if (from < 0 || to < 0 || from >= (NSInteger)list.count || to >= (NSInteger)list.count) {
        return;
    }
    NSNumber *item = list[from];
    [list removeObjectAtIndex:from];
    [list insertObject:item atIndex:to];
    [self saveEnabled:list];
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) {
        return;
    }
    NSMutableArray *list = [WXKBEnabledFuncs() mutableCopy];
    NSInteger idx = indexPath.row - [self enabledOffset];
    if (idx < 0 || idx >= (NSInteger)list.count) {
        return;
    }
    [list removeObjectAtIndex:idx];
    [self saveEnabled:list];
}

@end