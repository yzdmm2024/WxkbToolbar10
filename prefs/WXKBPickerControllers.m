// WXKBPickerControllers.m — 系统取色器入口 + 单选列表
#import "WXKBCommon.h"

#pragma mark - 系统取色器（UIColorPickerViewController）

@interface WXKBSystemColorController : WXKBBaseListController
@property (nonatomic, assign) BOOL shown;
@end

@implementation WXKBSystemColorController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self.specifier name] ?: @"选择颜色";
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:nil];
    [g setProperty:@"用系统颜色面板选色，支持不透明度；返回上一页即生效。"
            forKey:@"footerText"];
    [s addObject:g];
    _specifiers = s;
    return _specifiers;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.presentedViewController) {
        return;
    }
    if (self.shown) {
        // 系统面板被下滑关掉（iOS 14 不会回调 didFinish），直接退回上一页
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    self.shown = YES;
    [self presentPicker];
}

- (void)presentPicker {
    NSNumber *letterIdx = [self.specifier propertyForKey:@"wxkbLetterIndex"];
    NSString *hex = nil;
    if (letterIdx) {
        hex = WXKBLetterColor([letterIdx integerValue]);
        if (!hex.length) {
            id v = WXKBGetPref(WXKB_KEY_LETTER_BG);
            hex = [v isKindOfClass:[NSString class]] ? v : nil;
        }
    } else {
        NSString *key = [self.specifier propertyForKey:@"key"];
        id v = key.length ? WXKBGetPref(key) : nil;
        hex = [v isKindOfClass:[NSString class]] ? v : [self.specifier propertyForKey:@"default"];
    }

    UIColorPickerViewController *p = [[UIColorPickerViewController alloc] init];
    p.delegate = self;
    p.supportsAlpha = YES;
    p.selectedColor = WXKBColorFromHex(hex.length ? hex : @"#FFFFFF");
    if ([self.specifier name].length) {
        p.title = [self.specifier name];
    }
    [self presentViewController:p animated:YES completion:nil];
}

- (void)commitPicker:(UIColorPickerViewController *)vc {
    NSNumber *letterIdx = [self.specifier propertyForKey:@"wxkbLetterIndex"];
    NSString *hex = WXKBHexFromColor(vc.selectedColor);
    if (letterIdx) {
        WXKBSetLetterColor([letterIdx integerValue], hex);
    } else {
        NSString *key = [self.specifier propertyForKey:@"key"];
        if (key.length) {
            WXKBSetPref(key, hex);
        }
    }
    [[self class] wxkbNotifyChanged];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)vc {
    [self commitPicker:vc];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    [self commitPicker:vc];
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - 单选列表

@interface WXKBChoiceListController : WXKBBaseListController
@end

@implementation WXKBChoiceListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self.specifier name] ?: @"选择";
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSArray *values = [self.specifier propertyForKey:@"values"];
    NSArray *titles = [self.specifier propertyForKey:@"titles"];
    id current = [self readPreferenceValue:self.specifier];

    NSMutableArray *s = [NSMutableArray array];
    [s addObject:[PSSpecifier groupSpecifierWithName:nil]];
    for (NSUInteger i = 0; i < values.count; i++) {
        BOOL selected = [[values[i] description] isEqualToString:[current description]];
        NSString *title = selected ? [@"✓ " stringByAppendingString:titles[i]] : titles[i];
        PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:title
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
        sp->action = @selector(choose:);
        [sp setProperty:values[i] forKey:@"choiceValue"];
        [s addObject:sp];
    }
    _specifiers = s;
    return _specifiers;
}

- (void)choose:(PSSpecifier *)specifier {
    NSString *key = [self.specifier propertyForKey:@"key"];
    id val = [specifier propertyForKey:@"choiceValue"];
    WXKBSetPref(key, val);
    // 选了非「原图」主题时，顺手把「启用彩虹按键皮肤」打开，点了立刻看得到效果
    if ([key isEqualToString:WXKB_KEY_SKIN_THEME] && [val integerValue] != 0) {
        WXKBSetPref(WXKB_KEY_SKIN_ENABLED, @YES);
    }
    [[self class] wxkbNotifyChanged];
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - 26 字母逐个上色（原生子页列表，替代自定义内联网格）

@interface WXKBLetterListController : WXKBBaseListController
@end

@implementation WXKBLetterListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"字母键逐个上色";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;          // 从取色器返回后刷新右侧色块
    [self reloadSpecifiers];
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:nil];
    [g setProperty:@"点任意字母，直接用系统取色器上色；返回即生效。顶部预览实时跟随。"
            forKey:@"footerText"];
    [s addObject:g];
    for (NSInteger i = 0; i < 26; i++) {
        NSString *letter = [NSString stringWithFormat:@"%c", (char)('A' + i)];
        [s addObject:[self wxkbLetterRow:letter index:i]];
    }
    _specifiers = s;
    return _specifiers;
}

@end