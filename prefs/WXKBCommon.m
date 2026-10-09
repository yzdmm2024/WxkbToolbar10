// WXKBCommon.m — 偏好面板公共基类与读写工具
#import "WXKBCommon.h"
#import "WXKBInlineGridCell.h"   // 声明 setWxkbEnabled:，供 tableView:cellForRowAtIndexPath: 同步锁定态
#import "lk.h"
#import <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif
extern const lk_env *lk_get_env(void);
#ifdef __cplusplus
}
#endif

static NSUserDefaults *WXKBDefaults(void) {
    static NSUserDefaults *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:WXKB_PREFS_DOMAIN];
    });
    return d;
}

id WXKBGetPref(NSString *key) {
    if (!key.length) {
        return nil;
    }
    return [WXKBDefaults() objectForKey:key];
}

void WXKBSetPref(NSString *key, id value) {
    if (!key.length) {
        return;
    }
    if (value == nil) {
        [WXKBDefaults() removeObjectForKey:key];
    } else {
        [WXKBDefaults() setObject:value forKey:key];
    }
    [WXKBDefaults() synchronize];
}

#pragma mark - 颜色转换

UIColor *WXKBColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:[NSString class]]) {
        return [UIColor whiteColor];
    }
    NSString *s = [hex stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"#"]) {
        s = [s substringFromIndex:1];
    }
    if (s.length == 3) {
        s = [NSString stringWithFormat:@"%c%c%c%c%c%c",
             [s characterAtIndex:0], [s characterAtIndex:0],
             [s characterAtIndex:1], [s characterAtIndex:1],
             [s characterAtIndex:2], [s characterAtIndex:2]];
    }
    if (s.length != 6 && s.length != 8) {
        return [UIColor whiteColor];
    }
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:s] scanHexInt:&v]) {
        return [UIColor whiteColor];
    }
    CGFloat a = 1.0;
    if (s.length == 8) {
        a = (v & 0xFF) / 255.0;
        v >>= 8;
    }
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0
                           alpha:a];
}

NSString *WXKBHexFromColor(UIColor *color) {
    if (!color) {
        return @"#FFFFFF";
    }
    CGFloat r = 1, g = 1, b = 1, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 1;
        if ([color getWhite:&w alpha:&a]) {
            r = g = b = w;
        }
    }
    int ri = (int)lround(r * 255.0), gi = (int)lround(g * 255.0), bi = (int)lround(b * 255.0);
    int ai = (int)lround(a * 255.0);
    if (ai >= 255) {
        return [NSString stringWithFormat:@"#%02X%02X%02X", ri, gi, bi];
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X", ri, gi, bi, ai];
}

#pragma mark - 26 字母逐个配色

NSString *WXKBLetterColor(NSInteger index) {
    if (index < 0 || index > 25) {
        return nil;
    }
    NSDictionary *m = WXKBGetPref(WXKB_KEY_LETTER_MAP);
    if (![m isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id v = m[[NSString stringWithFormat:@"%ld", (long)index]];
    return [v isKindOfClass:[NSString class]] ? v : nil;
}

void WXKBSetLetterColor(NSInteger index, NSString *hex) {
    if (index < 0 || index > 25) {
        return;
    }
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    NSDictionary *old = WXKBGetPref(WXKB_KEY_LETTER_MAP);
    if ([old isKindOfClass:[NSDictionary class]]) {
        [m addEntriesFromDictionary:old];
    }
    m[[NSString stringWithFormat:@"%ld", (long)index]] = hex ?: @"";
    WXKBSetPref(WXKB_KEY_LETTER_MAP, m);
}

#pragma mark - 预设色

NSArray<NSString *> *WXKBColorPresets(void) {
    static NSArray *presets = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        presets = @[
            @"#000000", @"#1C1C1E", @"#3A3A3C", @"#8E8E93", @"#C7C7CC", @"#FFFFFF",
            @"#FF3B30", @"#FF9500", @"#FFCC00", @"#34C759", @"#00C7BE", @"#30B0C7",
            @"#007AFF", @"#5856D6", @"#AF52DE", @"#FF2D55", @"#A2845E", @"#5AC8FA"
        ];
    });
    return presets;
}

#pragma mark - 色块缩略图

static UIImage *WXKBSwatch(UIColor *color, CGFloat size) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0);
    UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, size, size)
                                                     cornerRadius:size * 0.28];
    [color setFill];
    [p fill];
    [[UIColor colorWithWhite:0.0 alpha:0.18] setStroke];
    p.lineWidth = 0.5;
    [p stroke];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - 主题族色板（与 Tweak 的 kThemeFam 同源，共 32 套）

const double WXKBThemeFam[32][4] = {
    {   0,   0, 0.00, 0.00},   // 0 百度彩虹（原图，读皮肤图，不参与渐变）
    {   0, 352, 0.88, 0.72},   // 1 彩虹
    {   0, 352, 0.82, 0.88},   // 2 马卡龙
    {  18,  54, 0.90, 0.86},   // 3 蜜桃
    { 128, 190, 0.72, 0.85},   // 4 薄荷
    { 240, 332, 0.72, 0.86},   // 5 暮紫
    { 182, 250, 0.80, 0.82},   // 6 海蓝
    { 336,  42, 0.90, 0.80},   // 7 落日
    {  66, 160, 0.70, 0.84},   // 8 森系
    { 140, 200, 0.85, 0.60},   // 9 极光
    { 300, 360, 0.95, 0.70},   // 10 霓粉
    { 205, 255, 0.95, 0.62},   // 11 电蓝
    {  20,  50, 0.95, 0.62},   // 12 柑橘
    {  52,  78, 0.90, 0.70},   // 13 柠檬
    { 270, 320, 0.72, 0.66},   // 14 葡萄
    { 338,  18, 0.55, 0.80},   // 15 玫瑰金
    { 140, 170, 0.50, 0.80},   // 16 薄雾
    { 190, 220, 0.65, 0.78},   // 17 天空
    {   2,  26, 0.85, 0.72},   // 18 珊瑚
    { 258, 292, 0.82, 0.64},   // 19 紫罗兰
    {  82, 112, 0.85, 0.66},   // 20 青柠
    { 200, 242, 0.88, 0.46},   // 21 深海
    { 280, 332, 0.92, 0.56},   // 22 暗霓
    {  30,  60, 0.90, 0.75},   // 23 暖阳
    { 182, 212, 0.55, 0.86},   // 24 冰蓝
    { 326, 358, 0.82, 0.62},   // 25 莓果
    {  60,  92, 0.55, 0.66},   // 26 橄榄
    {  28,  48, 0.32, 0.56},   // 27 钨丝
    { 262, 330, 0.70, 0.74},   // 28 蒸汽波
    { 150, 182, 0.82, 0.58},   // 29 翡翠
    {  24,  46, 0.92, 0.68},   // 30 蜜橙
    { 208, 240, 0.38, 0.80}    // 31 雾蓝
};

UIColor *WXKBFromHSL(double h, double s, double l) {
    double C = (1.0 - fabs(2.0 * l - 1.0)) * s;
    double hp = fmod(h, 360.0) / 60.0;
    if (hp < 0) hp += 6.0;
    double X = C * (1.0 - fabs(fmod(hp, 2.0) - 1.0));
    double r = 0, g = 0, b = 0;
    if      (hp < 1) { r = C; g = X; }
    else if (hp < 2) { r = X; g = C; }
    else if (hp < 3) { g = C; b = X; }
    else if (hp < 4) { g = X; b = C; }
    else if (hp < 5) { r = X; b = C; }
    else             { r = C; b = X; }
    double m = l - C / 2.0;
    return [UIColor colorWithRed:r + m green:g + m blue:b + m alpha:1.0];
}

// 主题代表色（用于面板色板缩略）：0=原图给个紫粉代表；其余取渐变中段色
UIColor *WXKBThemeSwatchColor(NSInteger theme) {
    if (theme < 0 || theme > 31) return nil;
    if (theme == 0) {
        return WXKBFromHSL(300, 0.55, 0.72);
    }
    const double *f = WXKBThemeFam[theme];
    double h0 = f[0], h1 = f[1], s = f[2], l = f[3];
    if (h1 < h0) h1 += 360.0;
    return WXKBFromHSL(h0 + (h1 - h0) * 0.5, s, l);
}

@implementation WXKBBaseListController

+ (void)wxkbNotifyChanged {
    // 通知键盘扩展立刻重读偏好；收不到也没关系，重弹键盘一样生效。
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL, NULL, YES);
}

#pragma mark - 统一走我们自己的偏好域

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id v = WXKBGetPref(key);
    if (v != nil) {
        return v;
    }
    return [specifier propertyForKey:@"default"];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) {
        return;
    }
    WXKBSetPref(key, value);
    [[self class] wxkbNotifyChanged];
}

#pragma mark - 26 字母的取值/存值

- (id)wxkbLetterValue:(PSSpecifier *)specifier {
    NSInteger idx = [[specifier propertyForKey:@"wxkbLetterIndex"] integerValue];
    return WXKBLetterColor(idx) ?: @"默认";
}

- (void)wxkbSetLetterValue:(id)value specifier:(PSSpecifier *)specifier {
    NSInteger idx = [[specifier propertyForKey:@"wxkbLetterIndex"] integerValue];
    WXKBSetLetterColor(idx, [value isKindOfClass:[NSString class]] ? value : nil);
    [[self class] wxkbNotifyChanged];
}

#pragma mark - 色块显示

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *sp = [self specifierAtIndexPath:indexPath];
    NSString *hex = nil;

    NSNumber *letterIdx = [sp propertyForKey:@"wxkbLetterIndex"];
    if (letterIdx) {
        hex = WXKBLetterColor([letterIdx integerValue]);
        if (!hex.length) {
            hex = WXKBGetPref(WXKB_KEY_LETTER_BG);
        }
        if (![hex isKindOfClass:[NSString class]] || !hex.length) {
            hex = WXKB_DEF_LETTER_BG;
        }
    } else {
        id v = [sp propertyForKey:@"wxkbSwatchKey"];
        if ([v isKindOfClass:[NSString class]]) {
            id cur = WXKBGetPref(v);
            hex = [cur isKindOfClass:[NSString class]] ? cur
                                                       : [sp propertyForKey:@"default"];
        }
    }

    if ([hex isKindOfClass:[NSString class]] && hex.length) {
        cell.imageView.image = WXKBSwatch(WXKBColorFromHex(hex), 29);
    }

    // —— 锁定态置灰：未授权时，除「解锁」按钮外所有功能 cell 一律变灰且不可交互 ——
    // 关键：本 SDK 的 PSSpecifier 运行期根本没有 setEnabled:/isEnabled（强调用会
    // unrecognized selector 闪退），故绕开 specifier，直接在 cell 层做禁用。
    BOOL isUnlock = [[sp propertyForKey:@"wxkbUnlockEntry"] boolValue];
    BOOL licensed = NO;
    {
        const lk_env *env = lk_get_env();
        if (env) {
            long long exp = 0; lk_reason why = LK_R_NONE;
            if (lk_peek(env, &exp, &why) == LK_UNLOCKED) licensed = YES;
        }
    }
    if (!licensed && !isUnlock) {
        cell.userInteractionEnabled = NO;                       // 整行不可选/不可点
        if (cell.textLabel)       cell.textLabel.enabled = NO;  // 文字转灰
        if (cell.detailTextLabel) cell.detailTextLabel.enabled = NO;
        if (cell.imageView)       cell.imageView.alpha = 0.4;
        for (UIView *v in cell.contentView.subviews) {          // 开关/滑块等子控件禁用+变灰
            if ([v isKindOfClass:[UIControl class]]) { ((UIControl *)v).enabled = NO; v.alpha = 0.4; }
        }
    } else {
        cell.userInteractionEnabled = YES;
        if (cell.textLabel)       cell.textLabel.enabled = YES;
        if (cell.detailTextLabel) cell.detailTextLabel.enabled = YES;
        if (cell.imageView)       cell.imageView.alpha = 1.0;
        for (UIView *v in cell.contentView.subviews) {
            if ([v isKindOfClass:[UIControl class]]) { ((UIControl *)v).enabled = YES; v.alpha = 1.0; }
        }
    }

    // 内联网格 cell：把锁定态透传给 cell，使其整格按钮置灰、不可点（解锁后恢复）。
    // 直接用 cellClass 判断，避免引入头文件依赖；cell 此处类型是 UITableViewCell*，
    // 转发前转 id 以绕过编译期 selector 检查（respondsToSelector 已保护）。
    id cellObj = cell;
    Class gridCls = [sp propertyForKey:@"cellClass"];
    if (gridCls && [cellObj isKindOfClass:gridCls] &&
        [cellObj respondsToSelector:@selector(setWxkbEnabled:)]) {
        [cellObj setWxkbEnabled:(licensed || isUnlock)];
    }

    return cell;
}

#pragma mark - 行高（内联网格用）

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *sp = [self specifierAtIndexPath:indexPath];
    NSNumber *h = [sp propertyForKey:@"wxkbGridHeight"];
    if (h) return [h doubleValue];
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

#pragma mark - Specifier 构造

- (PSSpecifier *)wxkbSwitch:(NSString *)name key:(NSString *)key def:(BOOL)def {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:nil
                                                       cell:PSSwitchCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:@(def) forKey:@"default"];
    return sp;
}

- (PSSpecifier *)wxkbLink:(NSString *)name detailClass:(NSString *)cls {
    Class c = NSClassFromString(cls);
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:nil
                                                        get:nil
                                                     detail:c
                                                       cell:PSLinkCell
                                                       edit:nil];
    return sp;
}

- (PSSpecifier *)wxkbChoice:(NSString *)name key:(NSString *)key def:(id)def
                     values:(NSArray *)values titles:(NSArray *)titles {
    Class c = NSClassFromString(@"WXKBChoiceListController");
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:c
                                                       cell:PSLinkListCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:def forKey:@"default"];
    [sp setProperty:values forKey:@"values"];
    [sp setProperty:titles forKey:@"titles"];
    return sp;
}

- (PSSpecifier *)wxkbColor:(NSString *)name key:(NSString *)key def:(NSString *)def {
    return [self wxkbColorRow:name key:key def:def];
}

- (PSSpecifier *)wxkbColorRow:(NSString *)name key:(NSString *)key def:(NSString *)def {
    Class c = NSClassFromString(@"WXKBSystemColorController");
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:c
                                                       cell:PSLinkCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:def forKey:@"default"];
    [sp setProperty:key forKey:@"wxkbSwatchKey"];
    return sp;
}

- (PSSpecifier *)wxkbLetterRow:(NSString *)letter index:(NSInteger)index {
    Class c = NSClassFromString(@"WXKBSystemColorController");
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:letter
                                                     target:self
                                                        set:@selector(wxkbSetLetterValue:specifier:)
                                                        get:@selector(wxkbLetterValue:)
                                                     detail:c
                                                       cell:PSLinkCell
                                                       edit:nil];
    [sp setProperty:@(index) forKey:@"wxkbLetterIndex"];
    return sp;
}

- (PSSpecifier *)wxkbButton:(NSString *)name action:(SEL)action {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:nil
                                                        get:nil
                                                     detail:nil
                                                       cell:PSButtonCell
                                                       edit:nil];
    sp->action = action;
    return sp;
}

- (PSSpecifier *)wxkbEdit:(NSString *)name key:(NSString *)key def:(NSString *)def
              placeholder:(NSString *)placeholder {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:nil
                                                       cell:PSEditTextCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:def forKey:@"default"];
    [sp setProperty:placeholder forKey:@"placeholder"];
    return sp;
}

- (PSSpecifier *)wxkbSlider:(NSString *)name key:(NSString *)key def:(double)def
                        min:(double)min max:(double)max {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:name
                                                     target:self
                                                        set:@selector(setPreferenceValue:specifier:)
                                                        get:@selector(readPreferenceValue:)
                                                     detail:nil
                                                       cell:PSSliderCell
                                                       edit:nil];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:@(def) forKey:@"default"];
    [sp setProperty:@(min) forKey:@"min"];
    [sp setProperty:@(max) forKey:@"max"];
    return sp;
}

#pragma mark - 内联网格（替代跳二级页的单选 / 主题色板 / 26 字母键盘）

- (PSSpecifier *)wxkbGrid:(NSString *)key titles:(NSArray *)titles values:(NSArray *)values
                    colors:(NSArray *)colors columns:(NSInteger)cols mode:(NSString *)mode {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil
                                                    detail:nil cell:PSTitleValueCell edit:nil];
    [sp setProperty:NSClassFromString(@"WXKBInlineGridCell") forKey:@"cellClass"];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:titles forKey:@"wxkbGridTitles"];
    [sp setProperty:values forKey:@"wxkbGridValues"];
    [sp setProperty:colors forKey:@"wxkbGridColors"];
    [sp setProperty:@(cols) forKey:@"wxkbGridColumns"];
    [sp setProperty:mode forKey:@"wxkbGridMode"];
    // 换行布局：按屏幕可用宽度自动折行，高度随之计算（不再内嵌 scrollView，避免切后台卡死）。
    // 宽度公式与 WXKBInlineGridCell 的 wxkbChipWidth 保持一致；可用宽度取偏保守值，
    // 确保实际折行不会超出估算行数而裁掉最后一行。
    CGFloat screenW = (CGFloat)[UIScreen mainScreen].bounds.size.width;
    CGFloat avail = screenW - 56.0;            // 预留左右内边距
    CGFloat padX = 12.0, padY = 8.0, gapX = 8.0, gapY = 8.0, rowH = 36.0;
    CGFloat x = padX, y = padY;
    for (NSUInteger i = 0; i < titles.count; i++) {
        NSString *t = [titles[i] isKindOfClass:[NSString class]] ? titles[i] : @"";
        CGFloat w;
        if ([mode isEqualToString:@"theme"]) {
            w = 74.0;
        } else {
            CGSize s = [t sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12]}];
            w = MAX(48.0, s.width + 26.0);
        }
        if (x + w > avail && x > padX) { x = padX; y += rowH + gapY; }
        x += w + gapX;
    }
    CGFloat gridH = y + rowH + padY + 6.0;      // +6 余量，防估算偏差裁行
    [sp setProperty:@(gridH) forKey:@"wxkbGridHeight"];
    return sp;
}

- (PSSpecifier *)wxkbLetterGrid {
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil
                                                    detail:nil cell:PSTitleValueCell edit:nil];
    [sp setProperty:NSClassFromString(@"WXKBInlineGridCell") forKey:@"cellClass"];
    [sp setProperty:@"letter" forKey:@"wxkbGridMode"];
    [sp setProperty:@[@[@0,@1,@2,@3,@4,@5,@6,@7,@8,@9],
                       @[@10,@11,@12,@13,@14,@15,@16,@17,@18],
                       @[@19,@20,@21,@22,@23,@24,@25]] forKey:@"wxkbGridRows"];
    [sp setProperty:@(170) forKey:@"wxkbGridHeight"];
    return sp;
}

#pragma mark - 直接弹系统取色器（消灭 3 秒空白）

- (void)wxkbPresentColorForLetter:(NSInteger)idx title:(NSString *)title {
    self.wxkbPendingLetterIndex = idx;
    self.wxkbPendingKey = nil;
    UIColorPickerViewController *p = [[UIColorPickerViewController alloc] init];
    p.delegate = self;
    p.supportsAlpha = YES;
    NSString *hex = WXKBLetterColor(idx);
    if (!hex.length) {
        id v = WXKBGetPref(WXKB_KEY_LETTER_BG);
        hex = [v isKindOfClass:[NSString class]] ? v : WXKB_DEF_LETTER_BG;
    }
    p.selectedColor = WXKBColorFromHex(hex.length ? hex : @"#FFFFFF");
    if (title.length) p.title = title;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)vc {
    if (self.wxkbPendingKey.length) {
        WXKBSetPref(self.wxkbPendingKey, WXKBHexFromColor(vc.selectedColor));
    } else if (self.wxkbPendingLetterIndex >= 0) {
        WXKBSetLetterColor(self.wxkbPendingLetterIndex, WXKBHexFromColor(vc.selectedColor));
    }
    [[self class] wxkbNotifyChanged];
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    [self colorPickerViewControllerDidSelectColor:vc];
    [vc dismissViewControllerAnimated:YES completion:nil];
}

@end