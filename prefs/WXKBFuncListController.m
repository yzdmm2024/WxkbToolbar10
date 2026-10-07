// WXKBFuncListController.m — 工具栏功能显隐（按钮/开关式）
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

@interface WXKBFuncListController : WXKBBaseListController
@end

@implementation WXKBFuncListController

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
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];

    // ---- 分组一：键盘内可用（开启即显示在工具栏）----
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:@"键盘内可用（开启即显示在工具栏）"];
    [g setProperty:@"点击右侧开关即可开/关；开启的功能会显示在微信键盘工具栏上，关闭的移除。"
            forKey:@"footerText"];
    [s addObject:g];
    for (int i = 0; i < kWXKBFuncWorksInKbCount; i++) {
        int code = kWXKBFuncWorksInKb[i];
        [s addObject:[self wxkbSwitch:WXKBFuncName(code)
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

@end
