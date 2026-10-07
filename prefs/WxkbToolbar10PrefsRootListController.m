// WxkbToolbar10PrefsRootListController.m — 设置面板根页
#import "WXKBCommon.h"
#import "WXKBSkinImport.h"

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

    // ---- 皮肤（百度 .bdi） ----
    g = [PSSpecifier groupSpecifierWithName:@"皮肤（百度输入法 .bdi）"];
    [g setProperty:@"一键套用百度输入法皮肤：整键盘背景图 + 按键文字色/高亮色，"
                  @"并跟随系统深色自动切换。导入后「键盘背景」「按键配色」仍可手动微调。"
                  @"注意：百度的是整图皮肤，按键形状/艺术字无法迁移，仅还原风格与配色。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbButton:@"导入百度皮肤 (.bdi)"
                            action:@selector(importBdi:)]];
    [s addObject:[self wxkbButton:@"应用内置「秋意」预设"
                            action:@selector(applyQiuyi:)]];
    [s addObject:[self wxkbButton:@"清除皮肤（恢复默认）"
                            action:@selector(clearSkin:)]];

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
    [g setProperty:@"点每一行用系统颜色面板选色。四个底色分别对应：字母键 / 左侧功能键（大小写·数字·符号）/ 右侧功能键（删除·中英切换·发送）/ 空格。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用自定义配色" key:WXKB_KEY_KEY_ENABLED def:NO]];
    [s addObject:[self wxkbColorRow:@"字母键底色" key:WXKB_KEY_LETTER_BG
                                 def:WXKB_DEF_LETTER_BG]];
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

    // ---- 字母渐变 / 逐个 ----
    g = [PSSpecifier groupSpecifierWithName:@"字母键进阶"];
    [g setProperty:@"渐变按 A→Z 自动插值；开启渐变后，未单独设色的字母按渐变取色。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用字母渐变" key:WXKB_KEY_GRAD_ENABLED def:NO]];
    [s addObject:[self wxkbColorRow:@"渐变起始色" key:WXKB_KEY_GRAD_FROM
                                 def:WXKB_DEF_GRAD_FROM]];
    [s addObject:[self wxkbColorRow:@"渐变结束色" key:WXKB_KEY_GRAD_TO
                                 def:WXKB_DEF_GRAD_TO]];
    [s addObject:[self wxkbLink:@"26 字母逐个配色" detailClass:@"WXKBLetterColorController"]];

    // ---- 按键形状 ----
    g = [PSSpecifier groupSpecifierWithName:@"按键形状"];
    [g setProperty:@"0 = 原生直角。改大后按键更圆润（上限 22）。"
            forKey:@"footerText"];
    [s addObject:g];
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

#pragma mark - 皮肤（.bdi / 预设 / 清除）

- (void)importBdi:(id)sender {
    WXKBImportBdiFromViewController(self);
}

- (void)applyQiuyi:(id)sender {
    BOOL ok = WXKBApplyQiuyiPreset();
    NSString *title = ok ? @"已应用" : @"应用失败";
    NSString *msg = ok ? @"「秋意」皮肤已套用，收起键盘再弹出即可生效。"
                       : @"未找到内置皮肤资源。";
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:title message:msg
                   preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好"
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)clearSkin:(id)sender {
    WXKBClearSkin();
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"已清除"
                   message:@"皮肤已恢复默认，收起键盘再弹出即可生效。"
                   preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好"
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end