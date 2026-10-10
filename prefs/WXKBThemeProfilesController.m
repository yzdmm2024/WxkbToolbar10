// WXKBThemeProfilesController.m — 「我的主题」管理页
//
// 列出所有已存主题；点一行 = 套用（写回偏好 + 通知键盘 + 返回根页让预览刷新）；
// 右上角「编辑」可滑动删除。底部有「保存当前外观为新主题」按钮。
#import "WXKBCommon.h"
#import "WXKBThemeProfile.h"

@interface WXKBThemeProfilesController : WXKBBaseListController
@end

@implementation WXKBThemeProfilesController

- (void)viewDidLoad {
    [super viewDidLoad];
    // 右上角编辑按钮：进入编辑态后可滑动删除主题
    self.navigationItem.rightBarButtonItem = [self editButtonItem];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;               // 返回后刷新（套用/删除/新增后）
    [self reloadSpecifiers];
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;

    g = [PSSpecifier groupSpecifierWithName:@"我的主题"];
    [g setProperty:@"把你当前的整套外观（背景 / 按键配色 / 皮肤 / 键帽 / 字母渐变 …）"
                  @"存成具名主题，随时一键套用。先调好外观，再点「保存当前外观」命名存档。"
            forKey:@"footerText"];
    [s addObject:g];

    [s addObject:[self wxkbButton:@"保存当前外观为新主题…" action:@selector(saveCurrent:)]];

    NSArray *names = WXKBThemeProfileNames();
    if (names.count == 0) {
        g = [PSSpecifier groupSpecifierWithName:@"已存主题"];
        [g setProperty:@"还没有存档。先在根页把外观调好，再点上面的「保存当前外观」。"
                forKey:@"footerText"];
        [s addObject:g];
    } else {
        g = [PSSpecifier groupSpecifierWithName:@"已存主题（点击套用）"];
        [s addObject:g];
        for (NSString *nm in names) {
            PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:nm
                                                             target:self
                                                                set:nil
                                                                get:nil
                                                             detail:nil
                                                               cell:PSLinkCell
                                                               edit:nil];
            sp->action = @selector(applyTheme:);
            [sp setProperty:nm forKey:@"wxkbThemeName"];
            [s addObject:sp];
        }
    }

    _specifiers = s;
    return _specifiers;
}

#pragma mark - 保存当前外观

- (void)saveCurrent:(id)sender {
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:@"保存当前外观"
                         message:@"给这套主题起个名字，之后可在「我的主题」里一键套用。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"例如：我的彩虹键盘";
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消"
                                         style:UIAlertActionStyleCancel
                                       handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存"
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *act) {
        NSString *nm = a.textFields.firstObject.text;
        nm = [nm stringByTrimmingCharactersInSet:
                  [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (nm.length == 0) return;
        BOOL ok = WXKBOverwriteThemeProfile(nm);   // 同名则覆盖
        UIAlertController *r = [UIAlertController
            alertControllerWithTitle:ok ? @"已保存" : @"保存失败"
                             message:ok ? [NSString stringWithFormat:
                                              @"「%@」已保存到「我的主题」。", nm]
                                        : @"名字不能为空，或请换个名字再试。"
                      preferredStyle:UIAlertControllerStyleAlert];
        [r addAction:[UIAlertAction actionWithTitle:@"好"
                                            style:UIAlertActionStyleDefault
                                          handler:nil]];
        [self presentViewController:r animated:YES completion:nil];
        _specifiers = nil;
        [self reloadSpecifiers];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 套用主题

- (void)applyTheme:(PSSpecifier *)sender {
    NSString *nm = [sender propertyForKey:@"wxkbThemeName"];
    if (!nm.length) return;
    if (!WXKBApplyThemeProfile(nm)) return;
    // 返回根页：根页的内联预览会收到 changed 通知并重绘
    [self.navigationController popViewControllerAnimated:YES];
}

#pragma mark - 删除主题

// 安全获取 specifier：respondsToSelector 守卫防 roothide/iOS 私有访问器缺失
- (PSSpecifier *)wxkbSpecifierAt:(NSIndexPath *)indexPath {
    if ([self respondsToSelector:@selector(specifierAtIndexPath:)]) {
        return [self wxkbSpecifierAt:indexPath];
    }
    return nil;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
        editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *s = [self wxkbSpecifierAt:indexPath];
    if (!s) return UITableViewCellEditingStyleNone;
    if ([s propertyForKey:@"wxkbThemeName"]) {
        return UITableViewCellEditingStyleDelete;
    }
    return UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    PSSpecifier *s = [self wxkbSpecifierAt:indexPath];
    if (!s) return;
    NSString *nm = [s propertyForKey:@"wxkbThemeName"];
    if (nm.length) WXKBDeleteThemeProfile(nm);
    [self reloadSpecifiers];
}

@end

