// WxkbToolbar10PrefsSubpages.m — 二级界面（每个页面顶部带一个实时预览键盘）
//
// 背景：原来的设置是「单页 + 顶部一个总预览」。现在拆成 5 个二级页
//   （按键皮肤 / 键盘和形状 / 键盘背景 / 按键配色 / 字母键进阶），每页各自带一个
//   实时预览键盘。预览视图 WXKBPreviewKeyboardView 本身监听 WXKB_CHANGED_NOTIFICATION，
//   任意设置一改就自动重绘，所以在本页改控件 -> 预览立刻跟着变，无需回上一页。
//
// 每个二级页 = WXKBSubpageBase 子类，基类负责：顶部预览 header、切后台回来复位表视图
// 手势（避免「切 app 再回来整张表点不动」的 Bug B）、viewWillAppear 刷新预览。
// 子类只管返回自己的 specifiers（从原主控的扁平分组搬过来）。
#import "WXKBCommon.h"
#import "WXKBPreviewKeyboardView.h"

#pragma mark - 二级页公共基类

@interface WXKBSubpageBase : WXKBBaseListController {
    WXKBPreviewKeyboardView *_previewView;
}
@end

@implementation WXKBSubpageBase

// 兼容不同环境下表视图访问器（同主控）：部分 roothide/rootless 的 Preferences 未暴露
// tableView 属性，直接 self.tableView 会触发 doesNotRecognizeSelector 闪退。
- (UITableView *)wxkbTableView {
    if ([self respondsToSelector:@selector(tableView)]) {
        UITableView *t = self.tableView;
        if (t) return t;
    }
    if ([self respondsToSelector:@selector(table)]) {
        UITableView *t = (UITableView *)self.table;
        if (t) return t;
    }
    for (UIView *v in self.view.subviews) {
        if ([v isKindOfClass:[UITableView class]]) return (UITableView *)v;
    }
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // 顶部内联实时预览：与主控同源的仿真键盘，改任意控件 -> wxkbNotifyChanged ->
    // 预览自行重绘（见 WXKBPreviewKeyboardView 的 Darwin 通知观察）。
    CGFloat w = CGRectGetWidth([UIScreen mainScreen].bounds);
    if (w < 1.0) w = 375.0;
    CGFloat h = [WXKBPreviewKeyboardView preferredHeightForWidth:w];
    _previewView = [[WXKBPreviewKeyboardView alloc] initWithFrame:CGRectMake(0, 0, w, h)];
    _previewView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UITableView *tv = [self wxkbTableView];
    if (tv) {
        tv.tableHeaderView = _previewView;
    } else {
        [self.view addSubview:_previewView];
    }
    [_previewView refresh];

    // 导航栏「刷新」按钮：卡住时点它，强重建 cell 恢复交互（Bug B 的手动逃生口）。
    UIBarButtonItem *rf = [[UIBarButtonItem alloc] initWithTitle:@"刷新"
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(wxkbRefresh:)];
    self.navigationItem.rightBarButtonItem = rf;

    // 切后台再回来：安全复位表视图手势（Bug B 修复），并刷新预览。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(wxkbAppBecameActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidBecomeActiveNotification
                                                  object:nil];
}

// 安全复位：仅确保表视图可交互、手势处于启用态。
// 切勿用 KVC 强改 panGestureRecognizer.state —— 那会让 UITableView 的触摸派发错乱，
// 表现为「整张表只剩首个开关能点、其余点不动」（2.5.15 的倒退正是它造成的）。
// 真正的「切后台回前台整表点不动」由导航栏「刷新」按钮解决，稳且不伤交互。
- (void)wxkbUnstickScrollViews {
    UITableView *tv = [self wxkbTableView];
    if (!tv) return;
    tv.userInteractionEnabled = YES;
    tv.scrollEnabled = YES;
    for (UIGestureRecognizer *g in tv.gestureRecognizers) {
        if (!g.enabled) g.enabled = YES;
    }
}

- (void)wxkbAppBecameActive {
    if (!self.isViewLoaded) return;
    [self wxkbUnstickScrollViews];
    [self reloadSpecifiers];      // 重建 cell，恢复可交互态
    [_previewView refresh];        // 预览同步
}

// 用户主动刷新：卡住时点导航栏「刷新」。强重建 cell + 刷新预览，彻底恢复触摸与显示。
- (void)wxkbRefresh:(id)sender {
    (void)sender;
    [self wxkbUnstickScrollViews];
    _specifiers = nil;
    [self reloadSpecifiers];
    [_previewView refresh];        // 预览同步
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;               // 子页返回后刷新右侧当前值
    [self reloadSpecifiers];
    [_previewView refresh];           // 改完回到本页，预览立即同步
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self wxkbUnstickScrollViews];   // 进入本页即复位手势，避免「进二级页就点不动」
}

@end

#pragma mark - 按键皮肤（原「主题与皮肤」：彩虹按键皮肤 / 主题色板 / 变色方向 / 皮肤背景）

@interface WXKBSkinPageController : WXKBSubpageBase
@end
@implementation WXKBSkinPageController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"按键皮肤"; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;
    g = [PSSpecifier groupSpecifierWithName:@"按键皮肤"];
    [g setProperty:@"一键套用内置彩虹键盘，顶部预览实时跟随。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用彩虹按键皮肤" key:WXKB_KEY_SKIN_ENABLED def:NO]];
    [s addObject:[self wxkbGrid:WXKB_KEY_SKIN_THEME
                         titles:@[@"原图",@"彩虹",@"马卡龙",@"蜜桃",@"薄荷",@"暮紫",@"海蓝",@"落日",@"森系",
                                  @"极光",@"霓粉",@"电蓝",@"柑橘",@"柠檬",@"葡萄",@"玫瑰金",@"薄雾",@"天空",
                                  @"珊瑚",@"紫罗兰",@"青柠",@"深海",@"暗霓",@"暖阳",@"冰蓝",@"莓果",@"橄榄",@"钨丝",@"蒸汽波",@"翡翠",@"蜜橙",@"雾蓝"]
                         values:@[@0,@1,@2,@3,@4,@5,@6,@7,@8,@9,@10,@11,@12,@13,@14,@15,@16,@17,@18,@19,@20,@21,@22,@23,@24,@25,@26,@27,@28,@29,@30,@31]
                         colors:nil columns:6 mode:@"theme"]];
    [s addObject:[self wxkbGrid:WXKB_KEY_SKIN_DIR
                         titles:@[@"横向",@"竖向",@"斜向"] values:@[@0,@1,@2]
                         colors:nil columns:6 mode:@"select"]];
    [s addObject:[self wxkbGrid:WXKB_KEY_SKIN_BG
                         titles:@[@"白底",@"透明",@"灰色",@"白50%"] values:@[@0,@1,@2,@3]
                         colors:nil columns:6 mode:@"select"]];
    _specifiers = s;
    return _specifiers;
}
@end

#pragma mark - 键盘和形状（原「键帽与形状」：键帽风格 / 形状 / 圆角）

@interface WXKBShapePageController : WXKBSubpageBase
@end
@implementation WXKBShapePageController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"键盘和形状"; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;
    g = [PSSpecifier groupSpecifierWithName:@"键盘和形状"];
    [g setProperty:@"仅改按键外观，不影响键盘布局。顶部预览实时跟随。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbGrid:WXKB_KEY_CAP_STYLE
                         titles:@[@"关闭",@"立体",@"彩虹帽",@"3D帽",@"卡通",@"霓虹"]
                         values:@[@0,@1,@2,@3,@4,@5] colors:nil columns:6 mode:@"select"]];
    [s addObject:[self wxkbGrid:WXKB_KEY_SHAPE
                         titles:@[@"圆角",@"圆形",@"六边形",@"水珠"]
                         values:@[@0,@1,@2,@3] colors:nil columns:6 mode:@"select"]];
    [s addObject:[self wxkbSlider:@"按键圆角" key:WXKB_KEY_CORNER def:0.0
                              min:0.0 max:22.0]];
    _specifiers = s;
    return _specifiers;
}
@end

#pragma mark - 键盘背景（透明 / 纯色 / 图片）

@interface WXKBBgPageController : WXKBSubpageBase
@end
@implementation WXKBBgPageController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"键盘背景"; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;
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
    _specifiers = s;
    return _specifiers;
}
@end

#pragma mark - 按键配色（五组按键底色 + 文字色 + 高亮色）

@interface WXKBColorPageController : WXKBSubpageBase
@end
@implementation WXKBColorPageController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"按键配色"; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;
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
    _specifiers = s;
    return _specifiers;
}
@end

#pragma mark - 字母键进阶（A→Z 渐变 / 逐个上色）

@interface WXKBLetterPageController : WXKBSubpageBase
@end
@implementation WXKBLetterPageController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"字母键进阶"; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;
    g = [PSSpecifier groupSpecifierWithName:@"字母键进阶"];
    [g setProperty:@"字母 A→Z 连续渐变，或点下方字母逐个上色（点字母直接取色，无空白等待）。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用字母渐变" key:WXKB_KEY_GRAD_ENABLED def:NO]];
    [s addObject:[self wxkbColorRow:@"渐变起始色" key:WXKB_KEY_GRAD_FROM
                                 def:WXKB_DEF_GRAD_FROM]];
    [s addObject:[self wxkbColorRow:@"渐变结束色" key:WXKB_KEY_GRAD_TO
                                 def:WXKB_DEF_GRAD_TO]];
    [s addObject:[self wxkbLetterGrid]];
    _specifiers = s;
    return _specifiers;
}
@end
