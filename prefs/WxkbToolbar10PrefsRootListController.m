// WxkbToolbar10PrefsRootListController.m — 设置面板根页
#import "WXKBCommon.h"

@interface WxkbToolbar10PrefsRootListController : WXKBBaseListController
@end

@implementation WxkbToolbar10PrefsRootListController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;               // 子页返回后刷新右侧当前值
    [self reloadSpecifiers];
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

    // ---- 键盘背景 ----
    g = [PSSpecifier groupSpecifierWithName:@"键盘背景"];
    [g setProperty:@"「整键盘透明」会清掉键盘自带的背景层，透出后面的内容；"
                  @"按键底色与按键文字色不受影响，默认仍是黑字。"
                  @"「图片」请到「背景图片」里从相册选，会按键盘比例自动横向裁剪。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用自定义背景" key:WXKB_KEY_BG_ENABLED def:NO]];
    [s addObject:[self wxkbSwitch:@"整键盘透明" key:WXKB_KEY_TRANSPARENT def:NO]];
    [s addObject:[self wxkbChoice:@"背景类型" key:WXKB_KEY_BG_MODE def:@1
                           values:@[@1, @2]
                           titles:@[@"纯色", @"图片"]]];
    [s addObject:[self wxkbColorRow:@"背景颜色" key:WXKB_KEY_BG_COLOR def:@"#1C1C1E"]];
    [s addObject:[self wxkbLink:@"背景图片" detailClass:@"WXKBPhotoListController"]];
    [s addObject:[self wxkbSlider:@"背景透明度" key:WXKB_KEY_BG_ALPHA def:1.0
                              min:0.05 max:1.0]];

    // ---- 按键配色 ----
    g = [PSSpecifier groupSpecifierWithName:@"按键配色"];
    [g setProperty:@"点每一行用系统颜色面板选色。五组底色分别对应：字母键 / 数字·符号键（数字符号面板中间的主键）/ 左侧功能键（大小写·数字·符号）/ 右侧功能键（删除·中英切换·发送）/ 空格。"
            forKey:@"footerText"];
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

    // ---- 皮肤（内置）----
    g = [PSSpecifier groupSpecifierWithName:@"皮肤（内置）"];
    [g setProperty:@"开启后把键盘渲染成内置的「彩虹按键」真实皮肤（来自百度输入法导出的真·键帽图），"
                  @"替代旧版程序生成的彩虹色。关闭则恢复上方普通按键配色。皮肤图片缺失时会自动退回彩虹配色。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用彩虹按键皮肤" key:WXKB_KEY_SKIN_ENABLED def:NO]];

    // ---- 字母渐变 / 逐个 ----
    g = [PSSpecifier groupSpecifierWithName:@"字母键进阶"];
    [g setProperty:@"字母键支持 A→Z 渐变，以及 26 字母逐个单独上色。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用字母渐变" key:WXKB_KEY_GRAD_ENABLED def:NO]];
    [s addObject:[self wxkbColorRow:@"渐变起始色" key:WXKB_KEY_GRAD_FROM
                                 def:WXKB_DEF_GRAD_FROM]];
    [s addObject:[self wxkbColorRow:@"渐变结束色" key:WXKB_KEY_GRAD_TO
                                 def:WXKB_DEF_GRAD_TO]];
    [s addObject:[self wxkbLink:@"26 字母逐个配色" detailClass:@"WXKBLetterColorController"]];

    // ---- 配色预设 ----
    g = [PSSpecifier groupSpecifierWithName:@"配色预设（一键套用）"];
    [g setProperty:@"点一下即套用整套配色，之后仍可在上方逐项微调。开启「启用自定义配色」后预设才会显示。"
            forKey:@"footerText"];
    [s addObject:g];
    for (NSString *nm in @[@"极光", @"莫兰迪", @"暗夜", @"清新"]) {
        PSSpecifier *b = [self wxkbButton:[NSString stringWithFormat:@"应用「%@」", nm]
                                      action:@selector(applyPreset:)];
        [b setProperty:nm forKey:@"wxkbPreset"];
        [s addObject:b];
    }

    // ---- 按键形状 ----
    g = [PSSpecifier groupSpecifierWithName:@"按键形状 / 立体键帽"];
    [g setProperty:@"「默认圆角」由下方滑块决定；「圆形 / 六边形 / 水珠」会忽略圆角滑块，"
                  @"直接把按键裁成对应形状。「彩虹键盘帽」是浅色柔和凸起键帽"
                  @"（白/浅灰裙边 + 柔和阴影，开启皮肤时默认）；「立体键帽」是深色"
                  @"电脑键盘风（深色裙边 + 近黑描边）。两者同时开启时优先彩虹键盘帽。"
                  @"以上都只改视觉，不影响键盘布局。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbChoice:@"按键形状" key:WXKB_KEY_SHAPE def:@0
                           values:@[@0, @1, @2, @3]
                           titles:@[@"默认圆角", @"圆形", @"六边形", @"水珠"]]];
    [s addObject:[self wxkbSwitch:@"彩虹键盘帽（柔和凸起）" key:WXKB_KEY_CAPRAINBOW def:NO]];
    [s addObject:[self wxkbSwitch:@"立体键帽（电脑键盘风）" key:WXKB_KEY_KEYCAP3D def:NO]];
    [s addObject:[self wxkbSlider:@"按键圆角" key:WXKB_KEY_CORNER def:0.0
                              min:0.0 max:22.0]];

    // ---- 键盘位置 ----
    g = [PSSpecifier groupSpecifierWithName:@"键盘位置"];
    [g setProperty:[NSString stringWithFormat:
                        @"整体上移 / 下移键盘（正在输入的这块），改动立即生效。"
                        @"当前偏移：%.0fpt（正数 = 下移，范围 ±80）。",
                        [self kbOffsetValue]]
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbButton:@"上移 5pt" action:@selector(kbUp:)]];
    [s addObject:[self wxkbButton:@"下移 5pt" action:@selector(kbDown:)]];
    [s addObject:[self wxkbButton:@"重置为 0" action:@selector(kbReset:)]];

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
            WXKB_KEY_KEYCAP3D: @NO,
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
            WXKB_KEY_KEYCAP3D: @NO,
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
            WXKB_KEY_KEYCAP3D: @NO,
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
            WXKB_KEY_KEYCAP3D: @NO,
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