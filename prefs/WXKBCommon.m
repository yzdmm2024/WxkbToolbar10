// WXKBCommon.m — 偏好面板公共基类与读写工具
#import "WXKBCommon.h"
#import <Preferences/PSTableCell.h>
#import <objc/runtime.h>
#import <CoreFoundation/CoreFoundation.h>

// 跨进程共享域：设置面板（未沙盒）写、键盘扩展（沙盒）读，二者都走 cfprefsd。
// 此外 wxkb_shared_sync（见 src/wxkb_shared.m）再把键值直写进 WeType 容器
// plist 作为兜底——cfprefsd 跨进程视图未同步时，键盘扩展直读自己的容器文件照样拿得到。
extern void wxkb_shared_sync(NSString *key, id value);

static NSString *WXKBSharedDomain(void) {
    return WXKB_SHARED_DOMAIN;
}

id WXKBGetPref(NSString *key) {
    if (!key.length) {
        return nil;
    }
    // 主通道：cfprefsd 上的共享域（键盘扩展沙盒内能读到）
    CFPropertyListRef v = CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)WXKBSharedDomain(),
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) {
        return (__bridge_transfer id)v;
    }
    // 兜底：旧 NSUserDefaults 域（非沙盒环境）
    return [[[NSUserDefaults alloc] initWithSuiteName:WXKB_PREFS_DOMAIN] objectForKey:key];
}

void WXKBSetPref(NSString *key, id value) {
    if (!key.length) {
        return;
    }
    CFStringRef domain = (__bridge CFStringRef)WXKBSharedDomain();
    CFPreferencesSetValue(
        (__bridge CFStringRef)key,
        value ? (__bridge CFPropertyListRef)value : NULL,
        domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    // 双通道：同步直写进 WeType 容器 plist（未沙盒进程才真正生效）
    wxkb_shared_sync(key, value);
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

#pragma mark - 带数字显示的步进滑块单元格

// 右侧实时显示带正负号的值；滑动时按 step 取整（step>=1 即整数步进）。
@interface WXKBValueSliderCell : PSTableCell {
    UISlider  *_slider;
    UILabel   *_valLabel;
    UILabel   *_titleLabel;
    NSString  *_key;
    double     _min, _max, _step, _def;
}
@end

@implementation WXKBValueSliderCell

- (id)initWithStyle:(int)style reuseIdentifier:(id)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:15];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self addSubview:_titleLabel];

        _slider = [[UISlider alloc] init];
        _slider.continuous = YES;
        [_slider addTarget:self action:@selector(_changed)
            forControlEvents:UIControlEventValueChanged];
        [self addSubview:_slider];

        _valLabel = [[UILabel alloc] init];
        if (@available(iOS 13.0, *)) {
            _valLabel.font = [UIFont monospacedDigitSystemFontOfSize:15
                                                             weight:UIFontWeightMedium];
        } else {
            _valLabel.font = [UIFont systemFontOfSize:15];
        }
        _valLabel.textAlignment = NSTextAlignmentRight;
        _valLabel.textColor = [UIColor labelColor];
        [self addSubview:_valLabel];
    }
    return self;
}

- (void)setSpecifier:(PSSpecifier *)spec {
    [super setSpecifier:spec];
    _key  = [spec propertyForKey:@"key"];
    _min  = [[spec propertyForKey:@"min"]  doubleValue];
    _max  = [[spec propertyForKey:@"max"]  doubleValue];
    _step = [[spec propertyForKey:@"wxkbStep"] doubleValue];
    if (_step <= 0.0) _step = 1.0;
    _def  = [[spec propertyForKey:@"default"] doubleValue];
    _titleLabel.text = [spec propertyForKey:@"wxkbTitle"];

    id raw = WXKBGetPref(_key);
    double v = raw ? [raw doubleValue] : _def;
    if (v < _min) v = _min;
    if (v > _max) v = _max;
    v = round(v / _step) * _step;

    _slider.minimumValue = _min;
    _slider.maximumValue = _max;
    _slider.value = v;
    [self _update:v];
}

- (void)_changed {
    double raw = _slider.value;
    double v = round(raw / _step) * _step;
    if (v < _min) v = _min;
    if (v > _max) v = _max;
    [_slider setValue:v animated:NO];
    [self _update:v];
    WXKBSetPref(_key, @(v));
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL, NULL, YES);
}

- (void)_update:(double)v {
    if (_step >= 1.0) {
        int iv = (int)round(v);
        _valLabel.text = (iv > 0)
            ? [NSString stringWithFormat:@"+%d", iv]
            : [NSString stringWithFormat:@"%d", iv];
    } else {
        _valLabel.text = [NSString stringWithFormat:@"%.2f", v];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    CGFloat W = b.size.width;
    CGFloat pad = 16.0;
    CGFloat rightW = 56.0;
    _titleLabel.frame = CGRectMake(pad, 7.0, W - pad * 2.0 - rightW, 22.0);
    CGFloat y = 34.0;
    _slider.frame = CGRectMake(pad, y, W - pad * 2.0 - rightW, 30.0);
    _valLabel.frame = CGRectMake(W - pad - rightW, y, rightW, 30.0);
    [self bringSubviewToFront:_titleLabel];
    [self bringSubviewToFront:_slider];
    [self bringSubviewToFront:_valLabel];
}

- (CGFloat)preferredHeight {
    return 64.0;
}

@end

#pragma mark - 状态行单元格（标题左 / 值右）

/* 不依赖 PSTitleValueCell（本 SDK 的 PSSpecifier 无 value 属性，
 * setProperty forKey:value 真机又不渲染）；cellClass 自定义单元格，
 * 与 WXKBValueSliderCell 同一套已验证的渲染路径。 */
@interface WXKBStatusCell : PSTableCell {
    UILabel *_titleLabel;
    UILabel *_valLabel;
}
@end

@implementation WXKBStatusCell

- (id)initWithStyle:(int)style reuseIdentifier:(id)identifier {
    self = [super initWithStyle:style reuseIdentifier:identifier];
    if (self) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:17];
        _titleLabel.textColor = [UIColor labelColor];
        [self addSubview:_titleLabel];

        _valLabel = [[UILabel alloc] init];
        _valLabel.font = [UIFont systemFontOfSize:15];
        _valLabel.textColor = [UIColor secondaryLabelColor];
        _valLabel.textAlignment = NSTextAlignmentRight;
        _valLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _valLabel.adjustsFontSizeToFitWidth = YES;
        _valLabel.minimumScaleFactor = 0.6;
        [self addSubview:_valLabel];
    }
    return self;
}

- (void)setSpecifier:(PSSpecifier *)spec {
    [super setSpecifier:spec];
    _titleLabel.text = [spec propertyForKey:@"wxkbStatusTitle"] ?: @"";
    _valLabel.text   = [spec propertyForKey:@"wxkbStatusValue"] ?: @"";
    BOOL multi = [[spec propertyForKey:@"wxkbStatusMultiline"] boolValue];
    _valLabel.numberOfLines = multi ? 2 : 1;
    _valLabel.textAlignment = multi ? NSTextAlignmentLeft : NSTextAlignmentRight;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat pad = 16.0;
    CGFloat W = self.bounds.size.width;
    BOOL multi = [[self.specifier propertyForKey:@"wxkbStatusMultiline"] boolValue];
    if (multi) {
        /* 标题一行，值换行铺满整行（长 UDID / 诊断串） */
        _titleLabel.frame = CGRectMake(pad, 6.0, W - pad * 2.0, 20.0);
        _valLabel.frame  = CGRectMake(pad, 27.0, W - pad * 2.0, 38.0);
    } else {
        _titleLabel.frame = CGRectMake(pad, 11.0, W * 0.34, 24.0);
        _valLabel.frame   = CGRectMake(W * 0.36, 11.0, W * 0.64 - pad, 24.0);
    }
    [self bringSubviewToFront:_titleLabel];
    [self bringSubviewToFront:_valLabel];
}

@end

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
    // 取该行的 specifier：优先用 cell.specifier（PSTableCell 可靠提供），
    // 兜底才用 specifierAtIndexPath:（部分 roothide/iOS 环境该私有访问器缺失会闪退）。
    PSSpecifier *sp = nil;
    if ([cell respondsToSelector:@selector(specifier)]) {
        sp = [(PSTableCell *)cell specifier];
    }
    if (!sp && [self respondsToSelector:@selector(specifierAtIndexPath:)]) {
        sp = [self specifierAtIndexPath:indexPath];
    }
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
    return cell;
}

#pragma mark - 行高（内联网格用）

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *sp = nil;
    if ([self respondsToSelector:@selector(specifierAtIndexPath:)]) {
        sp = [self specifierAtIndexPath:indexPath];
    }
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
    Class c = NSClassFromString(@"WXKBChoicePreviewController");
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
    // 系统 PSLinkListCell 靠 validValues/validTitles 在行右侧显示当前选中项
    [sp setProperty:values forKey:@"validValues"];
    [sp setProperty:titles forKey:@"validTitles"];
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

- (PSSpecifier *)wxkbValueSlider:(NSString *)name key:(NSString *)key def:(double)def
                              min:(double)min max:(double)max step:(double)step {
    // 标题放自定义属性里，specifier name 留空，避免 PSTableCell 自带标题重复显示
    PSSpecifier *sp = [PSSpecifier preferenceSpecifierNamed:@""
                                                     target:self
                                                        set:nil
                                                        get:nil
                                                     detail:nil
                                                       cell:PSStaticTextCell
                                                       edit:nil];
    [sp setProperty:name forKey:@"wxkbTitle"];
    [sp setProperty:key forKey:@"key"];
    [sp setProperty:@(def) forKey:@"default"];
    [sp setProperty:@(min) forKey:@"min"];
    [sp setProperty:@(max) forKey:@"max"];
    [sp setProperty:@(step) forKey:@"wxkbStep"];
    [sp setProperty:[WXKBValueSliderCell class] forKey:@"cellClass"];
    [sp setProperty:@(64) forKey:@"height"];
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