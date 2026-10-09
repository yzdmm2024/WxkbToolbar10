// WXKBInlineGridCell.m — 内联网格 cell
//
// 用法（由 WXKBBaseListController 的 wxkbGrid: / wxkbLetterGrid 构造）：
//   wxkbGridMode = @"theme"  → 32 主题色板（色块 + 名称，点击即选，自动开皮肤）
//   wxkbGridMode = @"select" → 普通单选（文字 chip，统一列数）
//   wxkbGridMode = @"letter" → 26 字母键盘（点击字母直接弹取色器）
// 点击选择类 → 直接写偏好 + 通知预览刷新；点击字母 → 让所属控制器弹 UIColorPickerViewController。
#import "WXKBInlineGridCell.h"

static void WXKBInlineGridNotify(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object,
                                 CFDictionaryRef userInfo) {
    WXKBInlineGridCell *self2 = (__bridge WXKBInlineGridCell *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self2 wxkbRefreshLetterColors];
    });
}

@interface WXKBInlineGridCell ()
@property (nonatomic, assign) BOOL built;
@property (nonatomic, strong) NSMutableArray *flatItems;   // 所有 item（NSMutableDictionary）
@property (nonatomic, strong) NSArray *layoutRows;         // NSArray<NSArray<item>>
@property (nonatomic, assign) NSInteger cols;
@property (nonatomic, weak)   PSSpecifier *lastSpecifier;
@end

@implementation WXKBInlineGridCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.textLabel.hidden = YES;
        self.detailTextLabel.hidden = YES;
        _flatItems = [NSMutableArray array];
        _cols = 0;
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                      (__bridge const void *)self,
                                      CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL);
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    if (_lastSpecifier != specifier) {
        // 被复用给别的网格时，清掉旧内容重建，避免串台
        for (UIView *v in self.contentView.subviews) [v removeFromSuperview];
        [_flatItems removeAllObjects];
        _layoutRows = nil;
        _built = NO;
        _lastSpecifier = specifier;
    }
    [super setSpecifier:specifier];
    [self wxkbBuild];
}

- (void)wxkbBuild {
    if (_built) return;
    PSSpecifier *sp = self.specifier;
    if (!sp) return;
    NSString *mode = [sp propertyForKey:@"wxkbGridMode"] ?: @"select";

    if ([mode isEqualToString:@"letter"]) {
        NSArray *rows = [sp propertyForKey:@"wxkbGridRows"];
        for (NSArray *row in rows) {
            for (id o in row) {
                NSInteger li = [o integerValue];
                NSString *letter = [NSString stringWithFormat:@"%c", (char)('A' + li)];
                NSString *hex = WXKBLetterColor(li);
                if (!hex.length) {
                    id v = WXKBGetPref(WXKB_KEY_LETTER_BG);
                    hex = [v isKindOfClass:[NSString class]] ? v : WXKB_DEF_LETTER_BG;
                }
                NSMutableDictionary *d = [NSMutableDictionary dictionary];
                d[@"letter"] = @(li);
                d[@"label"] = letter;
                d[@"hex"] = (hex.length ? hex : WXKB_DEF_LETTER_BG);
                [_flatItems addObject:d];
            }
        }
        _cols = 0;
    } else {
        NSArray *titles = [sp propertyForKey:@"wxkbGridTitles"];
        NSArray *values = [sp propertyForKey:@"wxkbGridValues"];
        NSArray *colors = [sp propertyForKey:@"wxkbGridColors"];
        NSInteger cols = [[sp propertyForKey:@"wxkbGridColumns"] integerValue] ?: 6;
        _cols = cols;
        for (NSUInteger i = 0; i < titles.count; i++) {
            id val = (values && i < values.count) ? values[i] : @(i);
            NSString *col = (colors && i < colors.count) ? colors[i] : nil;
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            d[@"title"] = titles[i];
            d[@"value"] = val;
            if (col) d[@"color"] = col;
            [_flatItems addObject:d];
        }
    }

    // 排版：select 按列数自动换行；letter 用显式行
    NSMutableArray *layout = [NSMutableArray array];
    if (_cols > 0) {
        NSMutableArray *cur = [NSMutableArray array];
        for (NSMutableDictionary *it in _flatItems) {
            [cur addObject:it];
            if ((NSInteger)cur.count == _cols) { [layout addObject:cur]; cur = [NSMutableArray array]; }
        }
        if (cur.count) [layout addObject:cur];
    } else {
        NSArray *rows = [sp propertyForKey:@"wxkbGridRows"];
        for (NSArray *row in rows) {
            NSMutableArray *r = [NSMutableArray array];
            for (id o in row) {
                NSInteger li = [o integerValue];
                for (NSMutableDictionary *it in _flatItems) {
                    if ([it[@"letter"] integerValue] == li) { [r addObject:it]; break; }
                }
            }
            [layout addObject:r];
        }
    }
    _layoutRows = layout;

    // 生成按钮
    for (NSMutableDictionary *it in _flatItems) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.layer.cornerRadius = 8.0;
        b.clipsToBounds = YES;
        b.titleLabel.font = [UIFont systemFontOfSize:11];
        b.titleLabel.adjustsFontSizeToFitWidth = YES;
        b.titleLabel.minimumScaleFactor = 0.5;
        b.titleLabel.textAlignment = NSTextAlignmentCenter;

        BOOL isLetter = (it[@"letter"] != nil);
        if (isLetter) {
            [b setTitle:it[@"label"] forState:UIControlStateNormal];
            [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
            b.backgroundColor = WXKBColorFromHex([it[@"hex"] isKindOfClass:[NSString class]] ? it[@"hex"] : WXKB_DEF_LETTER_BG);
            [b addTarget:self action:@selector(letterTap:) forControlEvents:UIControlEventTouchUpInside];
        } else {
            [b setTitle:it[@"title"] forState:UIControlStateNormal];
            if ([mode isEqualToString:@"theme"]) {
                NSInteger tv = [it[@"value"] integerValue];
                UIColor *c = WXKBThemeSwatchColor(tv);
                b.backgroundColor = c ?: [UIColor lightGrayColor];
                [b setTitleColor:[self wxkbTextOn:c] forState:UIControlStateNormal];
            } else {
                b.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
                [b setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
                b.layer.borderWidth = 1.0;
                b.layer.borderColor = [UIColor colorWithWhite:0.80 alpha:1.0].CGColor;
            }
            [b addTarget:self action:@selector(selectTap:) forControlEvents:UIControlEventTouchUpInside];
        }
        it[@"button"] = b;
        [self.contentView addSubview:b];
    }

    [self wxkbUpdateSelection];
    _built = YES;

    if ([mode isEqualToString:@"letter"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       WXKBInlineGridNotify,
                                       CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL,
                                       CFNotificationSuspensionBehaviorCoalesce);
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_built) return;
    CGRect b = self.contentView.bounds;
    CGFloat padX = 12.0, padY = 8.0, gap = 6.0;
    NSInteger nRows = _layoutRows.count;
    if (nRows < 1) return;
    CGFloat totalH = b.size.height - 2.0 * padY;
    CGFloat rowH = (totalH - gap * (nRows - 1)) / (CGFloat)nRows;
    if (rowH < 8.0) rowH = 8.0;
    CGFloat y = padY;
    for (NSArray *row in _layoutRows) {
        NSInteger n = row.count;
        CGFloat totalW = b.size.width - 2.0 * padX;
        CGFloat bw = (totalW - gap * (n - 1)) / (CGFloat)n;
        if (bw < 2.0) bw = 2.0;
        CGFloat x = padX;
        for (NSMutableDictionary *it in row) {
            UIButton *b = it[@"button"];
            b.frame = CGRectMake(x, y, bw, rowH);
            x += bw + gap;
        }
        y += rowH + gap;
    }
}

- (void)wxkbUpdateSelection {
    NSString *key = [self.specifier propertyForKey:@"key"];
    id cur = (key.length ? WXKBGetPref(key) : nil);
    if (cur == nil) cur = [self.specifier propertyForKey:@"default"];
    NSString *mode = [self.specifier propertyForKey:@"wxkbGridMode"];
    for (NSMutableDictionary *it in _flatItems) {
        if (it[@"letter"]) continue;
        UIButton *b = it[@"button"];
        BOOL sel = (cur != nil) && [[it[@"value"] description] isEqualToString:[cur description]];
        if ([mode isEqualToString:@"theme"]) {
            b.layer.borderWidth = sel ? 3.0 : 0.0;
            b.layer.borderColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0].CGColor;
        } else {
            if (sel) {
                b.backgroundColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
                [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            } else {
                b.backgroundColor = [UIColor colorWithWhite:0.92 alpha:1.0];
                [b setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
            }
        }
    }
}

- (void)selectTap:(UIButton *)b {
    for (NSMutableDictionary *it in _flatItems) {
        if (it[@"button"] == b) {
            NSString *key = [self.specifier propertyForKey:@"key"];
            if (key.length) {
                WXKBSetPref(key, it[@"value"]);
                // 选主题时顺手把「启用彩虹按键皮肤」打开，点了就立刻看得到
                if ([[self.specifier propertyForKey:@"wxkbGridMode"] isEqualToString:@"theme"]
                    && [key isEqualToString:WXKB_KEY_SKIN_THEME]) {
                    WXKBSetPref(WXKB_KEY_SKIN_ENABLED, @YES);
                }
                [WXKBBaseListController wxkbNotifyChanged]; // 刷新预览
            }
            [self wxkbUpdateSelection];
            break;
        }
    }
}

- (void)letterTap:(UIButton *)b {
    NSInteger li = -1;
    for (NSMutableDictionary *it in _flatItems) {
        if (it[@"button"] == b) { li = [it[@"letter"] integerValue]; break; }
    }
    if (li < 0) return;
    id tgt = [self.specifier target];
    if (tgt && [tgt respondsToSelector:@selector(wxkbPresentColorForLetter:title:)]) {
        NSString *title = [NSString stringWithFormat:@"字母 %c", (char)('A' + li)];
        [tgt wxkbPresentColorForLetter:li title:title];
    }
}

- (void)wxkbRefreshLetterColors {
    for (NSMutableDictionary *it in _flatItems) {
        if (it[@"letter"]) {
            NSInteger li = [it[@"letter"] integerValue];
            NSString *hex = WXKBLetterColor(li);
            if (!hex.length) {
                id v = WXKBGetPref(WXKB_KEY_LETTER_BG);
                hex = [v isKindOfClass:[NSString class]] ? v : WXKB_DEF_LETTER_BG;
            }
            UIButton *b = it[@"button"];
            b.backgroundColor = WXKBColorFromHex(hex.length ? hex : WXKB_DEF_LETTER_BG);
        }
    }
}

- (UIColor *)wxkbTextOn:(UIColor *)c {
    CGFloat r = 0, g = 0, bl = 0, a = 0;
    if ([c getRed:&r green:&g blue:&bl alpha:&a]) {
        double lum = 0.299 * r + 0.587 * g + 0.114 * bl;
        return (lum > 0.62) ? [UIColor blackColor] : [UIColor whiteColor];
    }
    return [UIColor whiteColor];
}

@end
