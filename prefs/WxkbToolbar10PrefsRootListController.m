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

- (NSString *)colorName:(NSString *)name key:(NSString *)key def:(NSString *)def {
    id v = WXKBGetPref(key);
    NSString *hex = [v isKindOfClass:[NSString class]] ? v : def;
    return [NSString stringWithFormat:@"%@  %@", name, hex];
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;

    g = [PSSpecifier groupSpecifierWithName:@"总开关"];
    [g setProperty:@"改动后收起键盘再弹出即可生效。" forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用增强" key:WXKB_KEY_ENABLED def:YES]];

    g = [PSSpecifier groupSpecifierWithName:@"工具栏功能"];
    [g setProperty:@"可拖动排序、左滑隐藏；移除的功能会从键盘工具栏上消失。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbLink:@"功能排序与显隐" detailClass:@"WXKBFuncListController"]];

    g = [PSSpecifier groupSpecifierWithName:@"键盘背景"];
    [g setProperty:@"「图片」需填写设备上的绝对路径，例如 /var/mobile/bg.png。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用自定义背景" key:WXKB_KEY_BG_ENABLED def:NO]];
    [s addObject:[self wxkbChoice:@"背景类型" key:WXKB_KEY_BG_MODE def:@1
                           values:@[@1, @2]
                           titles:@[@"纯色", @"图片"]]];
    [s addObject:[self wxkbColor:[self colorName:@"背景颜色" key:WXKB_KEY_BG_COLOR def:@"#1C1C1E"]
                             key:WXKB_KEY_BG_COLOR
                             def:@"#1C1C1E"]];
    [s addObject:[self wxkbEdit:@"背景图片路径" key:WXKB_KEY_BG_IMAGE def:@""
                    placeholder:@"/var/mobile/bg.png"]];
    [s addObject:[self wxkbSlider:@"背景透明度" key:WXKB_KEY_BG_ALPHA def:1.0
                              min:0.05 max:1.0]];

    g = [PSSpecifier groupSpecifierWithName:@"按键配色"];
    [s addObject:g];
    [s addObject:[self wxkbSwitch:@"启用自定义配色" key:WXKB_KEY_KEY_ENABLED def:NO]];
    [s addObject:[self wxkbColor:[self colorName:@"字母键底色" key:WXKB_KEY_KEY_LETTERBG def:@"#FFFFFF"]
                             key:WXKB_KEY_KEY_LETTERBG
                             def:@"#FFFFFF"]];
    [s addObject:[self wxkbColor:[self colorName:@"功能键底色" key:WXKB_KEY_KEY_FUNCBG def:@"#A8A8A8"]
                             key:WXKB_KEY_KEY_FUNCBG
                             def:@"#A8A8A8"]];
    [s addObject:[self wxkbColor:[self colorName:@"按键文字色" key:WXKB_KEY_KEY_TEXT def:@"#000000"]
                             key:WXKB_KEY_KEY_TEXT
                             def:@"#000000"]];
    [s addObject:[self wxkbColor:[self colorName:@"按下高亮色" key:WXKB_KEY_KEY_HIGHLIGHT def:@"#D9D9D9"]
                             key:WXKB_KEY_KEY_HIGHLIGHT
                             def:@"#D9D9D9"]];

    _specifiers = s;
    return _specifiers;
}

@end