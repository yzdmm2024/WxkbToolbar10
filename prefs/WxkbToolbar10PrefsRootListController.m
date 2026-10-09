// WxkbToolbar10PrefsRootListController.m — 设置面板根页
#import "WXKBCommon.h"
#import "WXKBPreviewKeyboardView.h"
#import <stdlib.h>

@interface WxkbToolbar10PrefsRootListController : WXKBBaseListController {
    WXKBPreviewKeyboardView *_previewView;   // 顶部内联实时预览
}
@end

@implementation WxkbToolbar10PrefsRootListController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 顶部内联实时预览：用同一套取色 / 键帽渲染数学画仿真键盘，
    // 改任意控件 -> wxkbNotifyChanged -> 预览自行重绘（见 WXKBPreviewKeyboardView）。
    CGFloat w = CGRectGetWidth([UIScreen mainScreen].bounds);
    if (w < 1.0) w = 375.0;
    CGFloat h = [WXKBPreviewKeyboardView preferredHeightForWidth:w];
    _previewView = [[WXKBPreviewKeyboardView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    _previewView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    // 兼容不同 iOS / 越狱环境下 PSListController 暴露的表视图访问器：
    // 部分环境（如某些 roothide/rootless 的 Preferences）并未暴露 tableView 属性，
    // 直接 self.tableView 会触发 doesNotRecognizeSelector 闪退（见崩溃日记）。
    // 依次尝试 tableView -> table -> 视图层级兜底，保证面板不再崩溃且预览尽量保留。
    UITableView *tv = nil;
    if ([self respondsToSelector:@selector(tableView)]) {
        tv = self.tableView;
    }
    if (!tv && [self respondsToSelector:@selector(table)]) {
        tv = (UITableView *)self.table;
    }
    if (!tv) {
        for (UIView *v in self.view.subviews) {
            if ([v isKindOfClass:[UITableView class]]) { tv = (UITableView *)v; break; }
        }
    }
    if (tv) {
        tv.tableHeaderView = _previewView;
    } else {
        // 极端兜底：直接叠在视图顶部，保证不闪退且预览仍可见
        [self.view addSubview:_previewView];
    }

    [_previewView refresh];

    // 切到别的 app 再回到设置：系统常把表视图滚动手势卡在「追踪/变化」态，
    // 导致整张表（含皮肤/键帽选择）点不动。注册回到前台通知，自动复位一次。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(wxkbRefreshPanel:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// 兼容不同环境取表视图（与 viewDidLoad 同一套兜底）
- (UITableView *)wxkbTableView {
    UITableView *tv = nil;
    if ([self respondsToSelector:@selector(tableView)]) tv = self.tableView;
    if (!tv && [self respondsToSelector:@selector(table)]) tv = (UITableView *)self.table;
    if (!tv) {
        for (UIView *v in self.view.subviews) {
            if ([v isKindOfClass:[UITableView class]]) { tv = (UITableView *)v; break; }
        }
    }
    return tv;
}

// 彻底修复「切 app 回前台整表点不动」：reloadData / 手势 KVC 都救不活卡死的表，
// 只有重建表视图（重进插件=新建实例）才行。这里在回到前台时直接重建一张新表。
- (void)wxkbRebuildTable {
    UITableView *old = [self wxkbTableView];
    if (!old || !old.superview) return;
    CGRect frame = old.frame;
    UITableViewStyle style = old.style;
    CGPoint offset = old.contentOffset;
    UITableView *newTv = [[UITableView alloc] initWithFrame:frame style:style];
    newTv.autoresizingMask = old.autoresizingMask;
    newTv.backgroundColor = old.backgroundColor;
    newTv.separatorStyle = old.separatorStyle;
    newTv.tableHeaderView = _previewView;
    newTv.delegate = (id<UITableViewDelegate>)self;
    newTv.dataSource = (id<UITableViewDataSource>)self;
    newTv.contentOffset = offset;
    newTv.userInteractionEnabled = YES;
    newTv.scrollEnabled = YES;
    [old.superview insertSubview:newTv belowSubview:old];
    [old removeFromSuperview];
    // 把 PSListController 内部指向旧表的指针重定向到新表（兼容不同 ivar/属性名）
    for (NSString *k in @[@"tableView", @"_tableView", @"_table"]) {
        @try { [self setValue:newTv forKey:k]; } @catch (NSException *e) {}
    }
    _specifiers = nil;            // 重建 specifiers，刷新右侧当前值
    [newTv reloadData];
    [_previewView refresh];
}

// 逃生口按钮 + 回到前台通知都走这里：重建表视图，彻底解除卡死。
- (void)wxkbRefreshPanel:(id)sender {
    [self wxkbRebuildTable];
}

// 清除系统键盘缓存：杀掉键盘守护进程（com.apple.TextInput），已开的 App 重排键盘即生效。
// 键盘布局被 iOS 缓存进进程——只改返回值不够，必须清缓存（这正是 ClassicKeyboardXS
// 看似「没生效」的真因：hook 写对了，但已开的 app 还在用旧布局）。
- (void)wxkbClearKBCache:(id)sender {
    int r = system("killall -9 TextInput 2>/dev/null");
    NSString *msg = (r == 0)
        ? @"已杀掉键盘守护进程，已开的 App 会自动重排键盘，紧凑设置立即生效。"
        : @"未找到 TextInput 守护进程（你的系统键盘可能运行在 App 进程内）。请直接杀掉并重开对应 App，或 Respring 后重试。";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"已发送清缓存"
                                                             message:msg
                                                      preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;               // 子页返回后刷新右侧当前值
    [self reloadSpecifiers];
    [_previewView refresh];           // 子页改完回来，预览立即同步
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;

    // ---- 总开关 ----
    g = [PSSpecifier groupSpecifierWithName:@"总开关"];
    [g setProperty:@"改动后收起键盘再弹出即可生效。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用增强" key:WXKB_KEY_ENABLED def:YES]];
    // 逃生口：切 app 回前台整张表点不动时，点这里立即复位（详见 wxkbRefreshPanel:）
    [s addObject:[self wxkbButton:@"刷新面板（卡住时点这里）" action:@selector(wxkbRefreshPanel:)]];

    // ---- 主题与皮肤（紧跟顶部预览，改主题立刻在预览看到）----
    g = [PSSpecifier groupSpecifierWithName:@"主题与皮肤"];
    [g setProperty:@"一键套用内置彩虹键盘，顶部预览实时跟随。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用彩虹按键皮肤" key:WXKB_KEY_SKIN_ENABLED def:NO]];

    // 主题色板：一行 6 个，直接点选，哪个亮哪个就变（点主题自动开皮肤）
    [s addObject:[self wxkbGrid:WXKB_KEY_SKIN_THEME
                         titles:@[@"原图",@"彩虹",@"马卡龙",@"蜜桃",@"薄荷",@"暮紫",@"海蓝",@"落日",@"森系",
                                  @"极光",@"霓粉",@"电蓝",@"柑橘",@"柠檬",@"葡萄",@"玫瑰金",@"薄雾",@"天空",
                                  @"珊瑚",@"紫罗兰",@"青柠",@"深海",@"暗霓",@"暖阳",@"冰蓝",@"莓果",@"橄榄",@"钨丝",@"蒸汽波",@"翡翠",@"蜜橙",@"雾蓝"]
                         values:@[@0,@1,@2,@3,@4,@5,@6,@7,@8,@9,@10,@11,@12,@13,@14,@15,@16,@17,@18,@19,@20,@21,@22,@23,@24,@25,@26,@27,@28,@29,@30,@31]
                         colors:nil columns:6 mode:@"theme"]];

    // 变色方向 / 皮肤背景：内联单选，不再跳二级页
    [s addObject:[self wxkbGrid:WXKB_KEY_SKIN_DIR
                         titles:@[@"横向",@"竖向",@"斜向"] values:@[@0,@1,@2]
                         colors:nil columns:6 mode:@"select"]];
    [s addObject:[self wxkbGrid:WXKB_KEY_SKIN_BG
                         titles:@[@"白底",@"透明",@"灰色",@"白50%"] values:@[@0,@1,@2,@3]
                         colors:nil columns:6 mode:@"select"]];

    // ---- 键帽与形状 ----
    g = [PSSpecifier groupSpecifierWithName:@"键帽与形状"];
    [g setProperty:@"仅改按键外观，不影响键盘布局。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbGrid:WXKB_KEY_CAP_STYLE
                         titles:@[@"关闭",@"立体",@"彩虹帽",@"3D帽",@"卡通",@"霓虹"]
                         values:@[@0,@1,@2,@3,@4,@5] colors:nil columns:6 mode:@"select"]];
    [s addObject:[self wxkbGrid:WXKB_KEY_SHAPE
                         titles:@[@"圆角",@"圆形",@"六边形",@"水珠"]
                         values:@[@0,@1,@2,@3] colors:nil columns:6 mode:@"select"]];
    [s addObject:[self wxkbSlider:@"按键圆角" key:WXKB_KEY_CORNER def:0.0
                              min:0.0 max:22.0]];

    // ---- 键盘背景 ----
    g = [PSSpecifier groupSpecifierWithName:@"键盘背景"];
    [g setProperty:@"透明 / 纯色 / 图片三种背景，图片按键盘比例自动裁剪。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用自定义背景" key:WXKB_KEY_BG_ENABLED def:NO]];
    [s addObject:[self wxkbSwitch:@"整键盘透明" key:WXKB_KEY_TRANSPARENT def:NO]];
    [s addObject:[self wxkbGrid:WXKB_KEY_BG_MODE
                         titles:@[@"纯色",@"图片"] values:@[@1,@2] colors:nil columns:6 mode:@"select"]];
    [s addObject:[self wxkbColorRow:@"背景颜色" key:WXKB_KEY_BG_COLOR def:@"#1C1C1E"]];
    [s addObject:[self wxkbLink:@"背景图片" detailClass:@"WXKBPhotoListController"]];
    [s addObject:[self wxkbSlider:@"背景透明度" key:WXKB_KEY_BG_ALPHA def:1.0
                              min:0.05 max:1.0]];

    // ---- 按键配色 ----
    g = [PSSpecifier groupSpecifierWithName:@"按键配色"];
    [g setProperty:@"精细调节五组按键底色与文字色（需开启「启用自定义配色」）。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用自定义配色" key:WXKB_KEY_KEY_ENABLED def:NO]];
    [s addObject:[self wxkbColorRow:@"字母键底色" key:WXKB_KEY_LETTER_BG
                                 def:WXKB_DEF_LETTER_BG]];
    [s addObject:[self wxkbColorRow:@"数字/符号键底色" key:WXKB_KEY_DIGIT_BG
                                 def:@"#FFD166"]];
    [s addObject:[self wxkbColorRow:@"左侧功能键底色" key:WXKB_KEY_FUNC_L_BG
                                 def:WXKB_DEF_FUNC_L_BG]];
    [s addObject:[self wxkbColorRow:@"右侧功能键底色" key:WXKB_KEY_FUNC_R_BG
                                 def:WXKB_DEF_FUNC_R_BG]];
    [s addObject:[self wxkbColorRow:@"空格键底色" key:WXKB_KEY_SPACE_BG
                                 def:WXKB_DEF_SPACE_BG]];
    [s addObject:[self wxkbColorRow:@"按键文字色" key:WXKB_KEY_KEY_TEXT
                                 def:WXKB_DEF_TEXT]];
    [s addObject:[self wxkbColorRow:@"按下高亮色" key:WXKB_KEY_KEY_HIGHLIGHT
                                 def:WXKB_DEF_HIGHLIGHT]];

    // ---- 字母键进阶 ----
    g = [PSSpecifier groupSpecifierWithName:@"字母键进阶"];
    [g setProperty:@"字母 A→Z 连续渐变，或点下方字母逐个上色（点字母直接取色，无空白等待）。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用字母渐变" key:WXKB_KEY_GRAD_ENABLED def:NO]];
    [s addObject:[self wxkbColorRow:@"渐变起始色" key:WXKB_KEY_GRAD_FROM
                                 def:WXKB_DEF_GRAD_FROM]];
    [s addObject:[self wxkbColorRow:@"渐变结束色" key:WXKB_KEY_GRAD_TO
                                 def:WXKB_DEF_GRAD_TO]];
    [s addObject:[self wxkbLetterGrid]];

    // ---- 配色预设 ----
    g = [PSSpecifier groupSpecifierWithName:@"配色预设"];
    [g setProperty:@"点一下即套用整套配色，之后仍可在「按键配色」里微调。" forKey:@"footerText"];
    [s addObject:g];
    for (NSString *nm in @[@"极光", @"莫兰迪", @"暗夜", @"清新"]) {
        PSSpecifier *b = [self wxkbButton:[NSString stringWithFormat:@"应用「%@」", nm]
                                      action:@selector(applyPreset:)];
        [b setProperty:nm forKey:@"wxkbPreset"];
        [s addObject:b];
    }

    // ---- 我的主题 ----
    g = [PSSpecifier groupSpecifierWithName:@"我的主题"];
    [g setProperty:@"把当前整套外观存档，随时一键套用，顶部预览实时跟随。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbLink:@"管理我的主题…" detailClass:@"WXKBThemeProfilesController"]];

    // ---- 键盘位置 ----
    g = [PSSpecifier groupSpecifierWithName:@"键盘位置"];
    [g setProperty:[NSString stringWithFormat:
                        @"整体上/下移键盘，改动立即生效（当前偏移 %.0fpt，范围 ±80）。",
                        [self kbOffsetValue]]
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbButton:@"上移 5pt" action:@selector(kbUp:)]];
    [s addObject:[self wxkbButton:@"下移 5pt" action:@selector(kbDown:)]];
    [s addObject:[self wxkbButton:@"重置为 0" action:@selector(kbReset:)]];

    // ---- 系统键盘紧凑（作用于系统键盘，不是微信键盘）----
    g = [PSSpecifier groupSpecifierWithName:@"系统键盘紧凑"];
    [g setProperty:@"收窄系统键盘底部留白、把地球/听写键收进键盘本体。改完点下方「清除键盘缓存」立即生效（iOS 会缓存键盘布局，不清缓存已开的 App 不会变）。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用紧凑键盘" key:WXKB_KEY_COMPACT def:NO]];
    [s addObject:[self wxkbButton:@"清除键盘缓存（让改动立即生效）" action:@selector(wxkbClearKBCache:)]];

    _specifiers = s;
    return _specifiers;
}

#pragma mark - 键盘位置

- (double)kbOffsetValue {
    id v = WXKBGetPref(WXKB_KEY_OFFSET);
    double d = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 0.0;
    if (d < -80.0 || d > 80.0) d = 0.0;
    return d;
}

- (void)setKbOffset:(double)off {
    if (off < -80.0) off = -80.0;
    if (off > 80.0) off = 80.0;
    WXKBSetPref(WXKB_KEY_OFFSET, @(off));
    [[self class] wxkbNotifyChanged];
    _specifiers = nil;               // 刷新 footer 里的当前值
    [self reloadSpecifiers];
}

- (void)kbUp:(id)sender   { [self setKbOffset:[self kbOffsetValue] - 5]; }
- (void)kbDown:(id)sender { [self setKbOffset:[self kbOffsetValue] + 5]; }
- (void)kbReset:(id)sender{ [self setKbOffset:0]; }

#pragma mark - 配色预设

// 预设名 -> 一套偏好。每行：键 -> 值（颜色用 #RRGGBB，开关用 @YES/@NO）
- (NSDictionary *)wxkbPresetTable {
    return @{
        @"极光": @{
            WXKB_KEY_KEY_ENABLED: @YES,
            WXKB_KEY_CAP_STYLE: @0,
            WXKB_KEY_GRAD_ENABLED: @YES,
            WXKB_KEY_LETTER_BG: @"#101826",
            WXKB_KEY_FUNC_L_BG: @"#0E1524",
            WXKB_KEY_FUNC_R_BG: @"#0E1524",
            WXKB_KEY_SPACE_BG: @"#101826",
            WXKB_KEY_KEY_TEXT: @"#FFFFFF",
            WXKB_KEY_KEY_HIGHLIGHT: @"#7C3AED",
            WXKB_KEY_GRAD_FROM: @"#22D3EE",
            WXKB_KEY_GRAD_TO: @"#A855F7"
        },
        @"莫兰迪": @{
            WXKB_KEY_KEY_ENABLED: @YES,
            WXKB_KEY_CAP_STYLE: @0,
            WXKB_KEY_GRAD_ENABLED: @NO,
            WXKB_KEY_LETTER_BG: @"#D8CFC4",
            WXKB_KEY_FUNC_L_BG: @"#C9BFB2",
            WXKB_KEY_FUNC_R_BG: @"#C9BFB2",
            WXKB_KEY_SPACE_BG: @"#D8CFC4",
            WXKB_KEY_KEY_TEXT: @"#5B534A",
            WXKB_KEY_KEY_HIGHLIGHT: @"#B7A99A"
        },
        @"暗夜": @{
            WXKB_KEY_KEY_ENABLED: @YES,
            WXKB_KEY_CAP_STYLE: @0,
            WXKB_KEY_GRAD_ENABLED: @NO,
            WXKB_KEY_LETTER_BG: @"#2B2B2E",
            WXKB_KEY_FUNC_L_BG: @"#1F1F22",
            WXKB_KEY_FUNC_R_BG: @"#1F1F22",
            WXKB_KEY_SPACE_BG: @"#2B2B2E",
            WXKB_KEY_KEY_TEXT: @"#FFFFFF",
            WXKB_KEY_KEY_HIGHLIGHT: @"#3A3A3C"
        },
        @"清新": @{
            WXKB_KEY_KEY_ENABLED: @YES,
            WXKB_KEY_CAP_STYLE: @0,
            WXKB_KEY_GRAD_ENABLED: @NO,
            WXKB_KEY_LETTER_BG: @"#E8F5E9",
            WXKB_KEY_FUNC_L_BG: @"#C8E6C9",
            WXKB_KEY_FUNC_R_BG: @"#C8E6C9",
            WXKB_KEY_SPACE_BG: @"#E8F5E9",
            WXKB_KEY_KEY_TEXT: @"#2E7D32",
            WXKB_KEY_KEY_HIGHLIGHT: @"#A5D6A7"
        }
    };
}

- (void)applyPreset:(id)sender {
    NSString *pid = nil;
    if ([sender isKindOfClass:[PSSpecifier class]]) {
        pid = [(PSSpecifier *)sender propertyForKey:@"wxkbPreset"];
    }
    NSDictionary *preset = pid ? [self wxkbPresetTable][pid] : nil;
    if (!preset) return;
    for (NSString *k in preset) {
        WXKBSetPref(k, preset[k]);
    }
    [[self class] wxkbNotifyChanged];

    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"已应用"
                   message:[NSString stringWithFormat:@"「%@」配色已套用，收起键盘再弹出即可生效。", pid]
                   preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好"
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
