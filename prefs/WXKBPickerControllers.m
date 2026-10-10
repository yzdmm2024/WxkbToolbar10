// WXKBPickerControllers.m — 系统取色器入口 + 单选列表 + 子页预览选择器
#import "WXKBCommon.h"
#import "WXKBPreviewKeyboardView.h"
#import <objc/runtime.h>

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
    // 3.3：左右固定 16pt 对称边距（预览键盘不再贴屏、左右等距）
    CGFloat pad = 12.0;          // 上下间距
    CGFloat margin = 16.0;       // 左右对称边距
    CGFloat innerW = w - margin * 2.0;

    CGFloat ph = [WXKBPreviewKeyboardView preferredHeightForWidth:innerW];
    _pv = [[WXKBPreviewKeyboardView alloc] initWithFrame:CGRectMake(margin, pad, innerW, ph)];
    _pv.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                           UIViewAutoresizingFlexibleRightMargin;
    [_pv refresh];

    // 3.3：选项改为一排五个的网格（最后一行不足五个时居中），不再横向滚动
    NSInteger cols = 5;
    CGFloat gapX = 8.0, gapY = 8.0, btnH = 44.0;
    CGFloat btnW = (innerW - gapX * (cols - 1)) / cols;
    NSUInteger n = _values.count;
    NSUInteger rows = (n + (NSUInteger)cols - 1) / (NSUInteger)cols;
    CGFloat gridY = pad + ph + pad;
    _optButtons = [NSMutableArray array];
    id current = [self readPreferenceValue:self.specifier];
    for (NSUInteger i = 0; i < n; i++) {
        NSUInteger r = i / (NSUInteger)cols;
        NSUInteger c = i % (NSUInteger)cols;
        CGFloat rowOffset = 0.0;
        NSUInteger inRow = n - r * (NSUInteger)cols;
        if (r == rows - 1 && inRow < (NSUInteger)cols) {
            rowOffset = (innerW - inRow * btnW - (inRow - 1) * gapX) / 2.0;
        }
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(margin + rowOffset + c * (btnW + gapX),
                             gridY + r * (btnH + gapY), btnW, btnH);
        b.layer.cornerRadius = 10.0;
        b.layer.masksToBounds = YES;
        b.titleLabel.font = [UIFont systemFontOfSize:11.0];
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
        [_optButtons addObject:b];
    }
    CGFloat gridH = rows * btnH + (rows > 0 ? (rows - 1) : 0) * gapY;

    [self updateHighlight:current];

    CGFloat headerH = gridY + gridH + pad;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, headerH)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:_pv];
    for (UIButton *b in _optButtons) [header addSubview:b];

    // 修复 3.2 崩溃：iOS 16 的 Preferences 运行时里 PSListController 没有 tableView
    // 方法（doesNotRecognizeSelector）。改为运行时安全地取表格：
    // 1) PSListController 的 _table ivar（社区通用名）；
    // 2) 逐层扫描父类里名字含 "table" 的对象型 ivar；
    // 3) self.view 本身或其一级子视图中的 UITableView。
    UITableView *tv = nil;
    Ivar iv = class_getInstanceVariable(objc_getClass("PSListController"), "_table");
    if (iv) tv = object_getIvar(self, iv);
    if (![tv isKindOfClass:[UITableView class]]) {
        tv = nil;
        Class c = [self class];
        for (int depth = 0; c && depth < 8 && !tv; depth++) {
            unsigned int n = 0;
            Ivar *ivs = class_copyIvarList(c, &n);
            for (unsigned int i = 0; i < n; i++) {
                const char *nm = ivar_getName(ivs[i]);
                const char *ty = ivar_getTypeEncoding(ivs[i]);
                if (!nm || !ty || ty[0] != '@') continue;
                if (!strstr(nm, "able") && !strstr(nm, "Table")) continue;
                id v = object_getIvar(self, ivs[i]);
                if ([v isKindOfClass:[UITableView class]]) { tv = v; break; }
            }
            if (ivs) free(ivs);
            c = class_getSuperclass(c);
        }
    }
    if (!tv) {
        if ([self.view isKindOfClass:[UITableView class]]) {
            tv = (UITableView *)self.view;
        } else {
            for (UIView *sub in self.view.subviews) {
                if ([sub isKindOfClass:[UITableView class]]) { tv = (UITableView *)sub; break; }
            }
        }
    }
    tv.tableHeaderView = header;  // tv 为 nil 时是安全的空操作
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
