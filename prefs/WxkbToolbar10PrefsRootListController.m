// WxkbToolbar10PrefsRootListController.m — 设置面板根页
#import "WXKBCommon.h"
#import "WXKBPreviewKeyboardView.h"
#import "WXKBInlineGridCell.h"
#import "lk.h"
#ifdef __cplusplus
extern "C" {
#endif
extern const lk_env *lk_get_env(void);
extern const char *lk_reason_cstr(lk_reason r);
#ifdef __cplusplus
}
#endif

@interface WxkbToolbar10PrefsRootListController : WXKBBaseListController {
    WXKBPreviewKeyboardView *_previewView;   // 顶部内联实时预览
    BOOL _didPromptUnlock;                   // 本次打开面板是否已弹过解锁（避免子页返回重复弹）
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
}

- (void)dealloc {
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;               // 子页返回后刷新右侧当前值
    [self reloadSpecifiers];
    [_previewView refresh];           // 子页改完回来，预览立即同步
}

// 打开面板：尚未解锁（未输码）时自动弹出解锁界面。任何设备都要解锁，母本自动解锁已移除。
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_didPromptUnlock) return;
    if (![self _wxkbUnlocked]) {
        _didPromptUnlock = YES;
        [self _doUnlock:nil];
    }
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;

    // ---- 解锁 / 验证 ----
    g = [PSSpecifier groupSpecifierWithName:@"解锁 / 验证"];
    [g setProperty:@"本插件需输入解锁码后生效：点下方「解锁」复制本机 UDID 发给作者签 16 位码，再粘贴解锁。未解锁时面板内所有功能均不可用。" forKey:@"footerText"];
    [s addObject:g];
    PSSpecifier *unlockBtn = [self wxkbButton:[self _lkStatusTitle] action:@selector(_doUnlock:)];
    [unlockBtn setProperty:@YES forKey:@"wxkbUnlockEntry"];   // 解锁按钮永远可点（即便锁定）
    [s addObject:unlockBtn];

    // ---- 总开关 ----
    g = [PSSpecifier groupSpecifierWithName:@"总开关"];
    [g setProperty:@"改动后收起键盘再弹出即可生效。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用增强" key:WXKB_KEY_ENABLED def:YES]];

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

    // 锁定态的「置灰 + 不可点」不在这里做——本 SDK 的 PSSpecifier 运行期无 setEnabled:
    // （强行调用会 unrecognized selector 闪退）。改由基类 tableView:cellForRowAtIndexPath:
    // 依据授权状态逐 cell 置灰并关交互（解锁按钮除外），对所有子页统一生效。

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

#pragma mark - 解锁 / 验证

// 仅 16 位码解锁（无母本自动解锁）。解锁状态由 license_kit 持久化（跨更新保留）。
- (BOOL)_wxkbUnlocked {
    const lk_env *env = lk_get_env();
    lk_reason why = LK_R_NONE;
    long long exp = 0;
    return lk_peek(env, &exp, &why) == LK_UNLOCKED;
}

- (NSString *)_lkStatusTitle {
    if ([self _wxkbUnlocked]) return @"解锁（已授权）✓";
    return @"解锁（未授权 · 点此解锁）";
}

- (void)_doUnlock:(PSSpecifier *)spec {
    (void)self; (void)spec;
    const lk_env *env = lk_get_env();
    // 取出与验签同源的本机 UDID，供用户复制后发给作者签码
    char udidBuf[160];
    NSString *udid = @"";
    if (env->device_id && env->device_id(udidBuf, (int)sizeof(udidBuf)) > 0) {
        udid = [NSString stringWithUTF8String:udidBuf];
    }
    NSString *msg = [NSString stringWithFormat:
        @"本机 UDID（点「复制 UDID」发给作者签码）：\n%@\n\n再把作者签发的 16 位解锁码粘贴到下方，点「解锁」。", udid];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"解锁（输入解锁码）"
        message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf){
        tf.placeholder = @"16 位解锁码"; tf.clearButtonMode = UITextFieldViewModeWhileEditing;
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"复制 UDID" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act){
        (void)act;
        if (udid.length) {
            [[UIPasteboard generalPasteboard] setString:udid];
            [self _toast:@"已复制 UDID ✓"];   // 复制后弹 toast 反馈（UIAlertAction.title 只读，不可原地把按钮文案改掉）
        }
    }]];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"解锁" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act){
        (void)act;
        UITextField *tf = a.textFields.firstObject;
        NSString *code = [[tf text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (code.length == 0) return;
        lk_reason w = LK_R_NONE;
        lk_status st = lk_submit(env, [code UTF8String], &w);
        if (st == LK_UNLOCKED) [self _toast:@"解锁成功"];
        else [self _toast:[NSString stringWithFormat:@"解锁失败：%s", lk_reason_cstr(w)]];
        _specifiers = nil;   // 重新计算「锁定」状态，解锁后所有功能开放
        [self performSelector:@selector(reloadSpecifiers) withObject:nil afterDelay:0.2];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)_toast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
