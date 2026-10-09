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
    BOOL _didPromptUnlock;                   // 本次打开面板是否已弹过解锁（避免子页返回重复弹）
}
@end

@implementation WxkbToolbar10PrefsRootListController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 切后台再回到前台时，iOS 不会重发 viewWillAppear（视图从未离开层级），但表视图自身的
    // 滚动手势可能卡在「追踪态」（系统未派发 touchesCancelled），导致整张表（开关/滑块/网格）
    // 都点不动。回到前台时强制复位表视图手势 + 重建 cell，恢复可点（Bug B 修复）。
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

#pragma mark - 切后台回来复位

// 兼容不同环境下表视图访问器（同 viewDidLoad）
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

// 强制结束可能卡在「追踪/变化」态的滚动手势（系统未派发 touchesCancelled 时，表视图会
// 一直认为手指还按着 → 整张表开关/滑块/网格都点不动）。用 KVC 直接把 state 置为 Ended，
// 安全复位：仅确保表视图可交互、手势处于启用态。
// 切勿用 KVC 强改 panGestureRecognizer.state —— 那会让 UITableView 的触摸派发错乱，
// 表现为「整张表只剩首个开关能点、其余点不动」（2.5.15 的倒退正是它造成的）。
// 真正的「切后台回前台整表点不动」由用户主动点「刷新面板」按钮（见下方）解决，稳且不伤交互。
- (void)wxkbUnstickScrollViews {
    UITableView *tv = [self wxkbTableView];
    if (!tv) return;
    tv.userInteractionEnabled = YES;
    tv.scrollEnabled = YES;
    for (UIGestureRecognizer *g in tv.gestureRecognizers) {
        if (!g.enabled) g.enabled = YES;
    }
}

// 回到前台：安全复位表视图交互 + 重建 specifiers/cell（恢复可点）。
- (void)wxkbAppBecameActive {
    if (!self.isViewLoaded) return;          // 面板还没打开过，无需处理
    [self wxkbUnstickScrollViews];
    [self reloadSpecifiers];
}

// 用户主动刷新：卡住时点它。强重建 cell，彻底恢复触摸与显示（Bug B 的手动逃生口）。
- (void)wxkbRefresh:(id)sender {
    (void)sender;
    [self wxkbUnstickScrollViews];
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;               // 子页返回后刷新右侧当前值
    [self reloadSpecifiers];
}

// 打开面板：尚未解锁（未输码）时自动弹出解锁界面。任何设备都要解锁，母本自动解锁已移除。
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self wxkbUnstickScrollViews];   // 进入面板即复位手势，避免「进面板就点不动」
    // 诊断：打印面板授权态（抓包定位「只能点按钮」是不是 licensed=NO 误锁）
    {
        const lk_env *env = lk_get_env();
        if (env) {
            long long exp = 0; lk_reason why = LK_R_NONE;
            lk_status st = lk_peek(env, &exp, &why);
            NSLog(@"[WXKB-panel] lk_peek=%d why=%d unlocked=%d",
                  (int)st, (int)why, (st == LK_UNLOCKED) ? 1 : 0);
        }
    }
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
    [s addObject:[self wxkbButton:@"刷新面板（卡住时点这里）" action:@selector(wxkbRefresh:)]];

    // ---- 外观设置（二级界面入口，每页顶部带实时预览）----
    g = [PSSpecifier groupSpecifierWithName:@"外观设置"];
    [g setProperty:@"以下功能各自有独立页面，页面顶部都有实时预览键盘，改完立刻能看到效果。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbLink:@"按键皮肤" detailClass:@"WXKBSkinPageController"]];
    [s addObject:[self wxkbLink:@"键盘和形状" detailClass:@"WXKBShapePageController"]];
    [s addObject:[self wxkbLink:@"键盘背景" detailClass:@"WXKBBgPageController"]];
    [s addObject:[self wxkbLink:@"按键配色" detailClass:@"WXKBColorPageController"]];
    [s addObject:[self wxkbLink:@"字母键进阶" detailClass:@"WXKBLetterPageController"]];

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

    // ---- 关于本插件（版本号 + 反馈，置于最底部）----
    g = [PSSpecifier groupSpecifierWithName:@"关于本插件"];
    [g setProperty:@"WxkbToolbar10 v2.5.17\n如有问题或建议，可邮件反馈作者：wacljcr@qq.com（请附设备型号与系统版本）"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbButton:@"复制作者邮箱" action:@selector(copyEmail:)]];

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

- (void)copyEmail:(id)sender {
    (void)sender;
    [[UIPasteboard generalPasteboard] setString:@"wacljcr@qq.com"];
    [self _toast:@"已复制作者邮箱 ✓"];
}

@end
