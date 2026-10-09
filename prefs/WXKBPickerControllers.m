// WXKBPickerControllers.m — 系统取色器入口 + 单选列表 + 子页预览选择器
#import "WXKBCommon.h"
#import "WXKBPreviewKeyboardView.h"

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

#pragma mark - 单选列表（旧，保留兼容）

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

#pragma mark - 子页预览选择器（横向布局 + 实时预览 + 确定返回）

@interface WXKBChoicePreviewController : WXKBBaseListController {
    WXKBPreviewKeyboardView *_pv;
    UIScrollView *_optScroll;
    NSMutableArray *_optButtons;
    NSString *_key;
    NSArray *_values;
    NSArray *_titles;
    BOOL _isTheme;
}
@end

@implementation WXKBChoicePreviewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = [self.specifier name] ?: @"选择";
    _key = [self.specifier propertyForKey:@"key"];
    _values = [self.specifier propertyForKey:@"values"];
    _titles = [self.specifier propertyForKey:@"titles"];
    _isTheme = [_key isEqualToString:WXKB_KEY_SKIN_THEME];

    CGFloat w = CGRectGetWidth([UIScreen mainScreen].bounds);
    if (w < 1.0) w = 375.0;
    CGFloat pad = 12.0;
    CGFloat innerW = w - pad * 2.0;

    CGFloat ph = [WXKBPreviewKeyboardView preferredHeightForWidth:innerW];
    _pv = [[WXKBPreviewKeyboardView alloc] initWithFrame:CGRectMake(pad, pad, innerW, ph)];
    _pv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_pv refresh];

    CGFloat btnH = 58.0, btnW = 72.0, gap = 10.0;
    CGFloat scrollY = pad * 2.0 + ph;
    _optScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, scrollY, w, btnH + 6.0)];
    _optScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _optScroll.showsHorizontalScrollIndicator = NO;
    _optScroll.showsVerticalScrollIndicator = NO;
    _optButtons = [NSMutableArray array];
    CGFloat x = pad;
    id current = [self readPreferenceValue:self.specifier];
    for (NSUInteger i = 0; i < _values.count; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(x, 0, btnW, btnH);
        b.layer.cornerRadius = 10.0;
        b.layer.masksToBounds = YES;
        b.titleLabel.font = [UIFont systemFontOfSize:13.0];
        b.titleLabel.textAlignment = NSTextAlignmentCenter;
        b.titleLabel.numberOfLines = 2;
        [b setTitle:_titles[i] forState:UIControlStateNormal];
        if (_isTheme) {
            UIColor *sw = WXKBThemeSwatchColor([_values[i] integerValue]);
            [b setBackgroundColor:(sw ?: [UIColor lightGrayColor])];
            [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        } else {
            [b setBackgroundColor:[UIColor colorWithWhite:0.92 alpha:1.0]];
            [b setTitleColor:[UIColor darkTextColor] forState:UIControlStateNormal];
        }
        b.tag = (NSInteger)i;
        [b addTarget:self action:@selector(pick:) forControlEvents:UIControlEventTouchUpInside];
        [_optScroll addSubview:b];
        [_optButtons addObject:b];
        x += btnW + gap;
    }
    _optScroll.contentSize = CGSizeMake(MAX(x, w), btnH + 6.0);
    [self updateHighlight:current];

    CGFloat headerH = scrollY + btnH + 6.0 + pad;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, headerH)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_pv];
    [header addSubview:_optScroll];
    self.tableView.tableHeaderView = header;
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:nil];
    [g setProperty:@"上方实时预览随选择即时变化；选好后点「确定并返回」。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbButton:@"确定并返回" action:@selector(done:)]];
    _specifiers = s;
    return _specifiers;
}

- (void)pick:(UIButton *)b {
    NSInteger i = b.tag;
    if (i < 0 || i >= (NSInteger)_values.count) {
        return;
    }
    id val = _values[i];
    WXKBSetPref(_key, val);
    if ([_key isEqualToString:WXKB_KEY_SKIN_THEME] && [val integerValue] != 0) {
        WXKBSetPref(WXKB_KEY_SKIN_ENABLED, @YES);
    }
    [[self class] wxkbNotifyChanged];
    [_pv refresh];
    [self updateHighlight:val];
}

- (void)updateHighlight:(id)cur {
    NSString *curDesc = [cur description];
    for (NSUInteger i = 0; i < _optButtons.count; i++) {
        UIButton *b = _optButtons[i];
        BOOL sel = [[_values[i] description] isEqualToString:curDesc];
        b.layer.borderWidth = sel ? 3.0 : 0.0;
        b.layer.borderColor = sel ? ([[UIColor systemBlueColor] CGColor]) : nil;
    }
}

- (void)done:(id)sender {
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
    [g setProperty:@"点任意字母，直接用系统取色器上色；返回即生效。"
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
