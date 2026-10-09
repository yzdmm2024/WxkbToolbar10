// WXKBOffsetSliderCell.m — 键盘位置滑块 cell
//
// 布局：左标题「键盘上下位置」 + 中间 UISlider（min -80 / max 80，整数吸附）
//      + 右数值标签（带正负号，如 +12 / 0 / -8）。
// 交互：滑动 -> 吸附到整数 -> 写 WXKB_KEY_OFFSET -> 通知预览实时刷新。
// 同步：监听 wxkbNotifyChanged，外部（如「重置为 0」按钮）改了偏移也能回显到滑块。
#import "WXKBOffsetSliderCell.h"

static void WXKBOffsetSliderNotify(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    WXKBOffsetSliderCell *self2 = (__bridge WXKBOffsetSliderCell *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self2 wxkbSyncFromPrefs];
    });
}

@interface WXKBOffsetSliderCell ()
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel  *valueLabel;
@property (nonatomic, strong) UILabel  *titleLabel;
@property (nonatomic, weak)   PSSpecifier *lastSpecifier;
- (void)wxkbSyncFromPrefs;
- (void)sliderChanged:(UISlider *)s;
- (void)wxkbUpdateLabel:(NSInteger)iv;
@end

@implementation WXKBOffsetSliderCell
@synthesize slider=_slider, valueLabel=_valueLabel, titleLabel=_titleLabel, lastSpecifier=_lastSpecifier;

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.accessoryType = UITableViewCellAccessoryNone;          // 不要 PSLinkCell 的箭头
        self.editingAccessoryType = UITableViewCellAccessoryNone;
        self.textLabel.hidden = YES;
        self.detailTextLabel.hidden = YES;
        self.contentView.userInteractionEnabled = YES;   // 内嵌控件能收触摸

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = @"键盘上下位置";
        _titleLabel.font = [UIFont systemFontOfSize:15];
        if (@available(iOS 13.0, *)) _titleLabel.textColor = [UIColor labelColor];
        else _titleLabel.textColor = [UIColor darkTextColor];
        [self.contentView addSubview:_titleLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = [UIFont systemFontOfSize:15];
        if (@available(iOS 13.0, *)) _valueLabel.textColor = [UIColor labelColor];
        else _valueLabel.textColor = [UIColor darkTextColor];
        _valueLabel.textAlignment = NSTextAlignmentRight;
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        _valueLabel.minimumScaleFactor = 0.5;
        [self.contentView addSubview:_valueLabel];

        _slider = [[UISlider alloc] init];
        _slider.minimumValue = -80.0;
        _slider.maximumValue = 80.0;
        _slider.continuous = YES;
        [_slider addTarget:self action:@selector(sliderChanged:)
             forControlEvents:UIControlEventValueChanged];
        [self.contentView addSubview:_slider];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        WXKBOffsetSliderNotify,
                                        CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
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
        _lastSpecifier = specifier;
    }
    [super setSpecifier:specifier];
    [self wxkbSyncFromPrefs];
}

// 从偏好同步滑块与数值（初始 / 外部改动后都走这里）
- (void)wxkbSyncFromPrefs {
    double v = 0.0;
    id val = WXKBGetPref(WXKB_KEY_OFFSET);
    if ([val respondsToSelector:@selector(doubleValue)]) v = [val doubleValue];
    if (v < -80.0) v = -80.0;
    if (v > 80.0) v = 80.0;
    NSInteger iv = (NSInteger)lround(v);
    _slider.value = (float)iv;          // 只显示整数
    [self wxkbUpdateLabel:iv];
}

- (void)sliderChanged:(UISlider *)s {
    NSInteger iv = (NSInteger)lround(s.value);
    s.value = (float)iv;                // 吸附到整数（滑动一次≈1pt）
    [self wxkbUpdateLabel:iv];
    WXKBSetPref(WXKB_KEY_OFFSET, @(iv));
    [WXKBBaseListController wxkbNotifyChanged];   // 实时预览 + 真机键盘立即重排
}

- (void)wxkbUpdateLabel:(NSInteger)iv {
    if (iv > 0)      _valueLabel.text = [NSString stringWithFormat:@"+%ld", (long)iv];
    else if (iv < 0) _valueLabel.text = [NSString stringWithFormat:@"%ld",  (long)iv];
    else             _valueLabel.text = @"0";
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.contentView.bounds;
    CGFloat padX = 16.0, gap = 10.0;
    CGFloat titleW = 96.0, valueW = 46.0;
    CGFloat h = b.size.height;
    _titleLabel.frame = CGRectMake(padX, 0, titleW, h);
    _valueLabel.frame = CGRectMake(b.size.width - padX - valueW, 0, valueW, h);
    _slider.frame = CGRectMake(padX + titleW + gap, 0,
                               b.size.width - padX * 2 - titleW - valueW - gap * 2, h);
}

// 同 WXKBInlineGridCell：PSTableCell 默认会接管整行触摸，导致内嵌滑块收不到拖动。
// 这里把命中测试下放到 contentView 子视图，落到滑块就返回滑块；非滑块区域返回 nil，
// 交给表视图去滚动，且不会触发该行的「选中/跳转」（PSLinkCell 默认会 push 一个 detail）。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    for (UIView *sub in self.contentView.subviews) {
        if (!sub.userInteractionEnabled || sub.hidden) continue;
        CGPoint p = [sub convertPoint:point fromView:self];
        UIView *inner = [sub hitTest:p withEvent:event];
        if (inner) return inner;
    }
    return nil;
}

@end
