// WXKBInlineGridCell.m — 内联网格 cell
//
// 用法（由 WXKBBaseListController 的 wxkbGrid: / wxkbLetterGrid 构造）：
//   wxkbGridMode = @"theme"  / @"select" → 单行「横向滑动选择条」（色块/文字 chip），高度很矮，省空间
//   wxkbGridMode = @"letter"            → 26 字母键盘（纵向 3 排），点字母直接弹取色器
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
@property (nonatomic, assign) BOOL wxkbEnabled;            // 锁定（未授权）时为 NO：整格置灰、按钮不可点
@property (nonatomic, strong) NSMutableArray *flatItems;   // 所有 item（NSMutableDictionary）
@property (nonatomic, strong) NSArray *layoutRows;         // NSArray<NSArray<item>>（字母键盘用）
@property (nonatomic, assign) NSInteger cols;
@property (nonatomic, weak)   PSSpecifier *lastSpecifier;
@property (nonatomic, strong) UIScrollView *scrollView;    // 横向滑动容器（select/theme 用）
@end

@implementation WXKBInlineGridCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.textLabel.hidden = YES;
        self.detailTextLabel.hidden = YES;
        self.contentView.userInteractionEnabled = YES;   // 保证内嵌控件能收触摸
        _wxkbEnabled = YES;
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
        _scrollView = nil;
        _built = NO;
        _lastSpecifier = specifier;
        // 字母网格可能在复用前注册过 Darwin 通知，这里先移除，避免重复注册/回调到旧状态
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                          (__bridge const void *)self,
                                          CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL);
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

    // 构造按钮
    if ([mode isEqualToString:@"letter"]) {
        NSMutableArray *layout = [NSMutableArray array];
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
        _layoutRows = layout;
        for (NSMutableDictionary *it in _flatItems) {
            UIButton *b = [self wxkbMakeButton:it mode:mode];
            [b addTarget:self action:@selector(letterTap:) forControlEvents:UIControlEventTouchUpInside];
            it[@"button"] = b;
            [self.contentView addSubview:b];
        }
    } else {
        _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        _scrollView.directionalLockEnabled = YES;
        _scrollView.userInteractionEnabled = YES;
        // 刻意不使用 delaysContentTouches = NO。iOS 在 app 切后台时偶尔不会把
        // touchesCancelled 正确派发给嵌套 scrollView，delaysContentTouches=NO 时更易让
        // 手势卡在「追踪中」，导致切回前台后整行点不动/滑不动。保持默认（YES）更稳。
        _scrollView.canCancelContentTouches = YES;
        [self.contentView addSubview:_scrollView];
        for (NSMutableDictionary *it in _flatItems) {
            UIButton *b = [self wxkbMakeButton:it mode:mode];
            [b addTarget:self action:@selector(selectTap:) forControlEvents:UIControlEventTouchUpInside];
            it[@"button"] = b;
            [_scrollView addSubview:b];
        }
    }

    [self wxkbUpdateSelection];
    _built = YES;
    [self wxkbApplyEnabledState];   // 应用当前锁定状态（构建完成后统一置灰/恢复）

    if ([mode isEqualToString:@"letter"]) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       WXKBInlineGridNotify,
                                       CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL,
                                       CFNotificationSuspensionBehaviorCoalesce);
    }
}

- (UIButton *)wxkbMakeButton:(NSMutableDictionary *)it mode:(NSString *)mode {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.layer.cornerRadius = 8.0;
    b.clipsToBounds = YES;
    b.titleLabel.font = [UIFont systemFontOfSize:12];
    b.titleLabel.adjustsFontSizeToFitWidth = YES;
    b.titleLabel.minimumScaleFactor = 0.5;
    b.titleLabel.textAlignment = NSTextAlignmentCenter;
    b.userInteractionEnabled = YES;

    if (it[@"letter"]) {
        [b setTitle:it[@"label"] forState:UIControlStateNormal];
        [b setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        b.backgroundColor = WXKBColorFromHex([it[@"hex"] isKindOfClass:[NSString class]] ? it[@"hex"] : WXKB_DEF_LETTER_BG);
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
    }
    return b;
}

- (CGFloat)wxkbChipWidth:(NSMutableDictionary *)it mode:(NSString *)mode {
    if ([mode isEqualToString:@"theme"]) {
        return 74.0;
    }
    NSString *t = it[@"title"] ?: @"";
    CGSize s = [t sizeWithAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:12]}];
    return MAX(48.0, s.width + 26.0);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_built) return;
    NSString *mode = [self.specifier propertyForKey:@"wxkbGridMode"] ?: @"select";
    CGRect b = self.contentView.bounds;

    if ([mode isEqualToString:@"letter"]) {
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
                UIButton *bt = it[@"button"];
                bt.frame = CGRectMake(x, y, bw, rowH);
                x += bw + gap;
            }
            y += rowH + gap;
        }
    } else {
        CGFloat padY = 8.0, gap = 8.0;
        CGFloat h = b.size.height - 2.0 * padY;
        if (h < 20.0) h = 20.0;
        CGFloat y = padY;
        CGFloat x = 12.0;
        for (NSMutableDictionary *it in _flatItems) {
            UIButton *bt = it[@"button"];
            CGFloat w = [self wxkbChipWidth:it mode:mode];
            bt.frame = CGRectMake(x, y, w, h);
            x += w + gap;
        }
        _scrollView.frame = b;
        _scrollView.contentSize = CGSizeMake(x + 12.0 - gap, b.size.height);
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

// 前台恢复时调用：让嵌套 scrollView 的手势状态复位，避免「切后台回来整行点不动/滑不动」
// （iOS 偶尔在 app 中断触摸时不派发 touchesCancelled，使 pan 手势卡在追踪态）。
- (void)wxkbResetScroll {
    UIScrollView *sv = _scrollView;
    if (!sv) return;
    sv.panGestureRecognizer.enabled = NO;
    sv.panGestureRecognizer.enabled = YES;
    [sv setContentOffset:sv.contentOffset animated:NO];
    [sv setNeedsLayout];
}

// 未授权时整格置灰、按钮不可点。该 SDK 的 PSTableCell 不暴露 setEnabled:，框架也不会
// 调它；故由基类 tableView:cellForRowAtIndexPath: 显式调用 setWxkbEnabled: 同步锁定态。
// 注意：按钮置为不可交互后，hitTest 会自然跳过它们（仍可横向滚动查看，只是不触发选择）。
- (void)setWxkbEnabled:(BOOL)enabled {
    _wxkbEnabled = enabled;
    [self wxkbApplyEnabledState];
}

- (void)wxkbApplyEnabledState {
    CGFloat a = _wxkbEnabled ? 1.0 : 0.35;   // 锁定：半透明置灰
    for (NSMutableDictionary *it in _flatItems) {
        UIButton *b = it[@"button"];
        if (!b) continue;
        b.userInteractionEnabled = _wxkbEnabled;
        b.alpha = a;
    }
    // 滚动容器始终保留滑动（锁定下仅能滑动、不能选）；字母网格无 scrollView 则跳过
    if (_scrollView) _scrollView.userInteractionEnabled = YES;
}

- (UIColor *)wxkbTextOn:(UIColor *)c {
    CGFloat r = 0, g = 0, bl = 0, a = 0;
    if ([c getRed:&r green:&g blue:&bl alpha:&a]) {
        double lum = 0.299 * r + 0.587 * g + 0.114 * bl;
        return (lum > 0.62) ? [UIColor blackColor] : [UIColor whiteColor];
    }
    return [UIColor whiteColor];
}

// 关键修复：PSTableCell 对 PSLinkCell 会接管整行触摸，导致 contentView 内的控件
// 收不到 TouchUpInside。这里遍历子视图并「递归」调用其 hitTest——落到按钮就返回按钮
// （可选中），落到滚动容器的空隙就返回滚动容器（仍可滑动）。注意：必须递归，不能
// 直接 return sub，否则 scrollView 收下触摸后其内部的按钮永远不会被命中。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.contentView.subviews) {
        if (!sub.userInteractionEnabled || sub.hidden) continue;
        CGPoint p = [sub convertPoint:point fromView:self];
        UIView *inner = [sub hitTest:p withEvent:event];
        if (inner) return inner;
    }
    return [super hitTest:point withEvent:event];
}

@end
