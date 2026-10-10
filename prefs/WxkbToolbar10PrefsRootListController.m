// WxkbToolbar10PrefsRootListController.m — 设置面板根页
#import "WXKBCommon.h"
#import "lk.h"
#include <time.h>

extern const char *lk_reason_cstr(lk_reason r);

/* 2.4.27 诊断探针读取（定义在 src/lk_env_ios.m） */
extern NSString *wxkb_diag_read(NSString *key);

/* WXKBStatusCell 定义在 WXKBCommon.m（cellClass 自定义单元格），
 * 这里用 NSClassFromString 取类，避免跨文件声明。 */

@interface WxkbToolbar10PrefsRootListController : WXKBBaseListController {
    NSString *_wxkbStatus;
    NSString *_wxkbUDID;
}
@end

@implementation WxkbToolbar10PrefsRootListController

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

    // ---- 主题与皮肤 ----
    g = [PSSpecifier groupSpecifierWithName:@"主题与皮肤"];
    [g setProperty:@"点「主题 / 变色方向 / 皮肤背景」进入子页，子页顶部实时预览，选好点「确定」返回。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用彩虹按键皮肤" key:WXKB_KEY_SKIN_ENABLED def:NO]];

    // 主题色板：32 套，进入子页横向选择 + 实时预览
    [s addObject:[self wxkbChoice:@"主题"
                             key:WXKB_KEY_SKIN_THEME
                             def:@0
                           values:@[@0,@1,@2,@3,@4,@5,@6,@7,@8,@9,@10,@11,@12,@13,@14,@15,@16,@17,@18,@19,@20,@21,@22,@23,@24,@25,@26,@27,@28,@29,@30,@31]
                           titles:@[@"原图",@"彩虹",@"马卡龙",@"蜜桃",@"薄荷",@"暮紫",@"海蓝",@"落日",@"森系",
                                    @"极光",@"霓粉",@"电蓝",@"柑橘",@"柠檬",@"葡萄",@"玫瑰金",@"薄雾",@"天空",
                                    @"珊瑚",@"紫罗兰",@"青柠",@"深海",@"暗霓",@"暖阳",@"冰蓝",@"莓果",@"橄榄",@"钨丝",@"蒸汽波",@"翡翠",@"蜜橙",@"雾蓝"]]];

    // 变色方向：12 个（0 横 / 1 竖 / 2 斜 + 9 个角度）
    [s addObject:[self wxkbChoice:@"变色方向" key:WXKB_KEY_SKIN_DIR def:@0
                           values:@[@0,@1,@2,@3,@4,@5,@6,@7,@8,@9,@10,@11]
                           titles:@[@"横向",@"竖向",@"斜向",@"15°",@"30°",@"60°",@"75°",@"105°",@"120°",@"135°",@"150°",@"165°"]]];

    // 皮肤背景
    [s addObject:[self wxkbChoice:@"皮肤背景" key:WXKB_KEY_SKIN_BG def:@0
                           values:@[@0,@1,@2,@3] titles:@[@"白底",@"透明",@"灰色",@"白50%"]]];

    // ---- 键帽与形状 ----
    g = [PSSpecifier groupSpecifierWithName:@"键帽与形状"];
    [g setProperty:@"仅改按键外观，不影响键盘布局。点「键帽样式 / 键帽形状」进入子页横向选 + 实时预览。"
            forKey:@"footerText"];
    [s addObject:g];
    // 键帽样式：12 个（0~5 原有 + 6~11 新增）
    [s addObject:[self wxkbChoice:@"键帽样式" key:WXKB_KEY_CAP_STYLE def:@0
                           values:@[@0,@1,@2,@3,@4,@5,@6,@7,@8,@9,@10,@11]
                           titles:@[@"关闭",@"立体",@"彩虹帽",@"彩虹3D",@"卡通",@"霓虹",
                                    @"磨砂",@"镜面",@"描边",@"软萌",@"极简",@"双色"]]];
    // 键帽形状：12 个（0~3 原有 + 4~11 新增）
    [s addObject:[self wxkbChoice:@"键帽形状" key:WXKB_KEY_SHAPE def:@0
                           values:@[@0,@1,@2,@3,@4,@5,@6,@7,@8,@9,@10,@11]
                           titles:@[@"圆角",@"圆形",@"六边形",@"水珠",
                                    @"椭圆",@"菱形",@"五边形",@"星形",@"心形",@"药丸",@"半圆",@"圆角方"]]];
    [s addObject:[self wxkbSlider:@"按键圆角" key:WXKB_KEY_CORNER def:0.0
                              min:0.0 max:22.0]];

    // ---- 键盘位置 ----
    g = [PSSpecifier groupSpecifierWithName:@"键盘位置"];
    [g setProperty:@"调整键盘整体上下位置（正值下移，负值上移）。无法恢复时把滑块拉回 0。"
            forKey:@"footerText"];
    [s addObject:g];
    /* 2.4.27：自定义 WXKBValueSliderCell 真机不能交互，换回系统 PSSliderCell
     * （「按键圆角」同款，已验证可拖动）。 */
    [s addObject:[self wxkbSlider:@"键盘上下偏移（上下移动）" key:WXKB_KEY_OFFSET def:0.0
                              min:-80.0 max:80.0]];

    // ---- 系统键盘高度（融合 ClassicKeyboardXS，仅作用于系统键盘，非微信键盘）----
    g = [PSSpecifier groupSpecifierWithName:@"系统键盘高度"];
    [g setProperty:@"仅作用于系统键盘（非微信键盘）。正值让系统键盘变矮，负值变高，范围 -120~120；拉回 0 即关闭。改动后收起键盘再弹出生效。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSlider:@"系统键盘高度增量" key:WXKB_KEY_SYS_KB_HEIGHT def:0.0
                              min:-120.0 max:120.0]];

    // ---- 键盘背景 ----
    g = [PSSpecifier groupSpecifierWithName:@"键盘背景"];
    [g setProperty:@"透明 / 纯色 / 图片三种背景，图片按键盘比例自动裁剪。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用自定义背景" key:WXKB_KEY_BG_ENABLED def:NO]];
    [s addObject:[self wxkbSwitch:@"整键盘透明" key:WXKB_KEY_TRANSPARENT def:NO]];
    [s addObject:[self wxkbChoice:@"背景模式" key:WXKB_KEY_BG_MODE def:@1
                           values:@[@1,@2] titles:@[@"纯色",@"图片"]]];
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
    [s addObject:[self wxkbLink:@"逐个字母上色…" detailClass:@"WXKBLetterListController"]];

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
    [g setProperty:@"把当前整套外观存档，随时一键套用。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbLink:@"管理我的主题…" detailClass:@"WXKBThemeProfilesController"]];

    // ---- 关于 ----
    g = [PSSpecifier groupSpecifierWithName:@"关于"];
    [g setProperty:@"WxkbToolbar10 版本 2.4.27\n反馈请联系：wacljcr@qq.com（邮件）"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbButton:@"反馈（邮件联系 wacljcr@qq.com）"
                           action:@selector(wxkbFeedback:)]];

    // ---- 授权与验证（license_kit 门禁） ----
    g = [PSSpecifier groupSpecifierWithName:@"授权与验证"];
    [g setProperty:@"用作者签发的 16 位解锁码解锁；未解锁时工具栏增强不生效。"
            forKey:@"footerText"];
    [s addObject:g];

    [self _wxkbCompute];
    /* 本 SDK 的 PSSpecifier 无 value 属性（st.value 编不过），而
     * setProperty forKey:value 真机又不渲染 —— 走 cellClass 自定义单元格
     * （WXKBStatusCell，定义在 WXKBCommon.m，渲染路径与值滑块同源）。 */
    PSSpecifier *st = [PSSpecifier preferenceSpecifierNamed:@""
                          target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [st setProperty:@"状态" forKey:@"wxkbStatusTitle"];
    [st setProperty:(_wxkbStatus ?: @"…") forKey:@"wxkbStatusValue"];
    [st setProperty:NSClassFromString(@"WXKBStatusCell") forKey:@"cellClass"];
    [st setProperty:@(44) forKey:@"height"];
    [s addObject:st];

    PSSpecifier *ud = [PSSpecifier preferenceSpecifierNamed:@""
                          target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [ud setProperty:@"本机 UDID（换码用）" forKey:@"wxkbStatusTitle"];
    [ud setProperty:(_wxkbUDID ?: @"…") forKey:@"wxkbStatusValue"];
    [ud setProperty:@YES forKey:@"wxkbStatusMultiline"];
    [ud setProperty:NSClassFromString(@"WXKBStatusCell") forKey:@"cellClass"];
    [ud setProperty:@(66) forKey:@"height"];
    [s addObject:ud];

    /* 诊断行：键盘扩展每次弹键盘都会把「它看到的 UDID/授权/通道实况」写进
     * kb_probe 探针键；这行读出来，截图即可定位键盘侧卡在哪一环。 */
    NSString *diag = wxkb_diag_read(@"kb_probe");
    PSSpecifier *dg = [PSSpecifier preferenceSpecifierNamed:@""
                          target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [dg setProperty:@"诊断（键盘→面板通道实况）" forKey:@"wxkbStatusTitle"];
    [dg setProperty:(diag ?: @"(nil)") forKey:@"wxkbStatusValue"];
    [dg setProperty:@YES forKey:@"wxkbStatusMultiline"];
    [dg setProperty:NSClassFromString(@"WXKBStatusCell") forKey:@"cellClass"];
    [dg setProperty:@(66) forKey:@"height"];
    [s addObject:dg];

    PSSpecifier *hint = [PSSpecifier groupSpecifierWithName:@"诊断说明"];
    [hint setProperty:@"先去任意输入框呼出微信键盘，再回到本页点「重新检查授权」——诊断行会显示键盘扩展最近一次上报：ud=键盘拿到的UDID（须与本机UDID一致）、store/cfpLic/fileLic=授权blob三通道、cfpKeys/fileKeys=两通道键数。"
            forKey:@"footerText"];
    [s addObject:hint];

    [s addObject:[self wxkbButton:@"复制 UDID" action:@selector(_wxkbCopyUDID:)]];
    [s addObject:[self wxkbButton:@"解锁" action:@selector(_wxkbDoUnlock:)]];
    [s addObject:[self wxkbButton:@"重新检查授权" action:@selector(_wxkbRecheck:)]];

    _specifiers = s;
    return _specifiers;
}

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

#pragma mark - 反馈（邮件）

- (void)wxkbFeedback:(id)sender {
    NSURL *u = [NSURL URLWithString:
        @"mailto:wacljcr@qq.com?subject=WxkbToolbar10%20%E5%8F%8D%E9%A6%88"];
    UIApplication *app = [UIApplication sharedApplication];
    if (@available(iOS 10.0, *)) {
        [app openURL:u options:@{} completionHandler:nil];
    } else {
        [app openURL:u];
    }
}

#pragma mark - 授权与验证（license_kit）

- (void)_wxkbCompute {
    const lk_env *env = lk_get_env();
    long long exp = 0;
    lk_reason why = LK_R_NONE;
    lk_status st = LK_LOCKED;
    if (env) st = lk_peek(env, &exp, &why);

    if (st == LK_UNLOCKED) {
        long long remain = exp - lk_time_to_exp((double)time(NULL));
        if (remain < 0) remain = 0;
        _wxkbStatus = [NSString stringWithFormat:@"已解锁（剩余约 %lld 分钟）", remain];
    } else if (st == LK_EXPIRED) {
        _wxkbStatus = @"已过期，请重新输入解锁码";
    } else if (st == LK_TAMPER) {
        _wxkbStatus = [NSString stringWithFormat:@"环境异常（%s）", lk_reason_cstr(why)];
    } else {
        _wxkbStatus = [NSString stringWithFormat:@"未解锁（%s）", lk_reason_cstr(why)];
    }

    char ub[160];
    if (env && env->device_id(ub, (int)sizeof(ub)) > 0)
        _wxkbUDID = [NSString stringWithUTF8String:ub];
    else
        _wxkbUDID = @"(无法读取 UDID)";
}

- (void)_wxkbCopyUDID:(PSSpecifier *)spec {
    (void)spec;
    [UIPasteboard generalPasteboard].string = _wxkbUDID;
    [self _wxkbToast:@"已复制 UDID 到剪贴板"];
}

- (void)_wxkbDoUnlock:(PSSpecifier *)spec {
    (void)spec;
    const lk_env *env = lk_get_env();
    if (!env) { [self _wxkbToast:@"验证模块未加载"]; return; }

    /* 母本 dongle 优先：已装正版母本直接自动解锁，无需输码 */
    lk_reason why = LK_R_NONE;
    long long exp = 0;
    if (lk_master_verify(env, &why, &exp) == LK_UNLOCKED) {
        /* 修复：母本解锁必须也把解锁码持久化进跨进程共享域。
         * 键盘扩展是沙盒进程，读不到母本（LSApplicationWorkspace +
         * 读别家二进制被沙盒拦截），lk_master_verify 在键盘里永远 LOCKED，
         * 只能靠共享域里的码来解锁。原先这里只弹 toast、不写码，
         * 导致「设置里显示已解锁、键盘里永远锁死」，皮肤/增强整片静默失效。 */
        char ub[160];
        char code[LK_CODE_LEN_S + 1];
        if (env->device_id(ub, (int)sizeof(ub)) > 0 &&
            lk_code_make_s(LK_PRODUCT_ID, ub, exp, code, (int)sizeof(code)) == LK_CODE_LEN_S) {
            lk_submit(env, code, &why);   // 写入共享域（cfprefsd + 容器 plist 双通道）
        }
        [self _wxkbToast:@"已通过母本自动解锁"];
        [self _wxkbRecheck:spec];
        return;
    }

    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"解锁"
                                                          message:@"请粘贴作者签发的 16 位解锁码"
                                                   preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"解锁码";
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消"
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"解锁"
                                          style:UIAlertActionStyleDefault
                                        handler:^(UIAlertAction *act) {
        UITextField *tf = a.textFields.firstObject;
        lk_reason w = LK_R_NONE;
        lk_status st = lk_submit(env, [tf.text UTF8String], &w);
        if (st == LK_UNLOCKED) [self _wxkbToast:@"解锁成功"];
        else [self _wxkbToast:[NSString stringWithFormat:@"解锁失败：%s", lk_reason_cstr(w)]];
        [self _wxkbRecheck:spec];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    /* 每次进页面都重算状态/UDID 并重建行，解锁回来不用手动点「重新检查」 */
    [self _wxkbRecheck:nil];
}

- (void)_wxkbRecheck:(id)sender {
    (void)sender;
    [self _wxkbCompute];
    /* 通知注入到键盘扩展里的 dylib 重新加载配置并刷新授权状态，
     * 否则已运行的键盘进程会一直沿用解锁前的 gWXKBUnlocked=NO，
     * 表现为「解锁了但工具栏增强仍然不生效」。 */
    [[self class] wxkbNotifyChanged];
    _specifiers = nil;
    [self reloadSpecifiers];
    [self _wxkbToast:[NSString stringWithFormat:@"已重新检查：%@", _wxkbStatus ?: @"…"]];
}

- (void)_wxkbToast:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil
                                                            message:msg
                                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [a dismissViewControllerAnimated:YES completion:nil];
        });
    }];
}

@end
