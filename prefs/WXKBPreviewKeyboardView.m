// WXKBPreviewKeyboardView.m — 仿真键盘预览
//
// 目标：在「设置」进程里画出与真机一模一样的键盘。做法 = 把 Tweak.xm 里的
//   WXKBKeyBackground / WXKBSkinColorFor / WXKBApplyCap / WXKBThemeGradientColor
// 那套取色 + 键帽渲染数学原样搬过来，套到一套固定的 QWERTY 布局上。
// 所以你改任何一个控件，预览立刻跟着变，和真机键盘同源。
//
// 注意：这里只依赖 UIKit 与 NSUserDefaults（偏好走同一个 suite），
//       不需要键盘扩展进程，因此能独立在设置里实时预览。
#import "WXKBPreviewKeyboardView.h"

#pragma mark - 与 Tweak.xm 同源的数学（直接搬，保证一致）

static UIColor *wxkbPVColor(NSString *hex, CGFloat alpha) {
    if (![hex isKindOfClass:[NSString class]]) return nil;
    NSString *s = [hex stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s hasPrefix:@"#"]) s = [s substringFromIndex:1];
    if (s.length != 6 && s.length != 8) return nil;
    unsigned int v = 0;
    if (![[NSScanner scannerWithString:s] scanHexInt:&v]) return nil;
    CGFloat a = alpha;
    if (s.length == 8) { a = alpha * ((v & 0xFF) / 255.0); v >>= 8; }
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0
                           green:((v >> 8) & 0xFF) / 255.0
                            blue:(v & 0xFF) / 255.0 alpha:a];
}

static UIBezierPath *wxkbPVHexagon(CGSize s) {
    CGFloat w = s.width, h = s.height;
    if (w <= 0 || h <= 0) return nil;
    CGFloat cx = w / 2.0, cy = h / 2.0;
    CGFloat a;
    if (w * 0.8660254 <= h) a = h * 0.5773503; else a = w / 2.0;
    CGFloat halfW = a, halfH = a * 0.8660254;
    CGPoint pts[6];
    pts[0] = CGPointMake(cx - halfW * 0.5, cy - halfH);
    pts[1] = CGPointMake(cx + halfW * 0.5, cy - halfH);
    pts[2] = CGPointMake(cx + halfW, cy);
    pts[3] = CGPointMake(cx + halfW * 0.5, cy + halfH);
    pts[4] = CGPointMake(cx - halfW * 0.5, cy + halfH);
    pts[5] = CGPointMake(cx - halfW, cy);
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:pts[0]];
    for (int i = 1; i < 6; i++) [p addLineToPoint:pts[i]];
    [p closePath];
    return p;
}

static UIBezierPath *wxkbPVWaterDrop(CGSize s) {
    CGFloat w = s.width, h = s.height;
    if (w <= 0 || h <= 0) return nil;
    CGFloat cx = w / 2.0, tipY = h * 0.10, r = w / 2.0, bottomCy = h - r;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(cx, tipY)];
    [p addCurveToPoint:CGPointMake(cx + r, bottomCy)
         controlPoint1:CGPointMake(cx + r * 0.55, tipY + h * 0.28)
         controlPoint2:CGPointMake(cx + r, bottomCy - r * 0.55)];
    [p addArcWithCenter:CGPointMake(cx, bottomCy) radius:r
             startAngle:0 endAngle:3.141592653589793 clockwise:YES];
    [p addCurveToPoint:CGPointMake(cx, tipY)
         controlPoint1:CGPointMake(cx - r, bottomCy - r * 0.55)
         controlPoint2:CGPointMake(cx - r * 0.55, tipY + h * 0.28)];
    [p closePath];
    return p;
}

// HSL -> UIColor（与 Tweak 的 WXKBFromHSL 一致；共用 WXKBCommon 的实现）
// 主题族（与 Tweak 的 kThemeFam 一致）：现由 WXKBCommon 的 WXKBThemeFam[32][4] 提供

// 主题渐变取色：row（0~2 字母行，3 空格行），tx 水平进度 0~1
static UIColor *wxkbPVThemeGradientColor(NSInteger gSkinTheme, NSInteger gSkinDir,
                                         NSInteger row, CGFloat tx) {
    if (gSkinTheme < 1 || gSkinTheme > 31) return nil;
    const double *f = WXKBThemeFam[gSkinTheme];
    double h0 = f[0], h1 = f[1], s = f[2], l = f[3];
    if (h1 < h0) h1 += 360.0;
    double ty = row / 3.0;
    double t;
    switch (gSkinDir) {
        case 1:  t = ty; break;
        case 2:  t = (tx + ty) / 2.0; break;
        default: t = tx; break;
    }
    if (t < 0.0) t = 0.0; if (t > 1.0) t = 1.0;
    return WXKBFromHSL(h0 + (h1 - h0) * t, s, l);
}

// 百度彩虹原图（theme 0）的真实键帽色：从 bundled 的 key26a.png 条带采样。
// 与 Tweak 的 strip 参数一致：2160x132，pitch=80，26 颗，本体高 0..108。
static NSArray<UIColor *> *wxkbPVLoadSkinStrip(void) {
    static NSArray *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [WXKB_SKIN_DIR stringByAppendingPathComponent:
                          @"rainbow/res/key26a.png"];
        // 越狱真机上皮肤目录在 /Library/...；roothide 可能在 jbroot，兜底再试一次。
        UIImage *img = [UIImage imageWithContentsOfFile:path];
        if (!img) {
            img = [UIImage imageWithContentsOfFile:
                   [@"/var/jb" stringByAppendingString:path]];
        }
        if (!img) { cached = @[]; return; }
        CGImageRef cg = img.CGImage;
        size_t W = CGImageGetWidth(cg), H = CGImageGetHeight(cg);
        if (W == 0 || H == 0) { cached = @[]; return; }
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, W, H, 8, W * 4, cs,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault);
        CGColorSpaceRelease(cs);
        if (!ctx) { cached = @[]; return; }
        CGContextDrawImage(ctx, CGRectMake(0, 0, W, H), cg);
        unsigned char *data = CGBitmapContextGetData(ctx);
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:26];
        const CGFloat pitch = 80.0, capH = 108.0;
        for (int i = 0; i < 26; i++) {
            CGFloat cx = i * pitch + pitch / 2.0;
            CGFloat cy = capH / 2.0;
            int x0 = (int)(cx - 8), x1 = (int)(cx + 8);
            int y0 = (int)(cy - 8), y1 = (int)(cy + 8);
            long rs = 0, gs = 0, bs = 0, n = 0;
            for (int y = y0; y < y1 && y < (int)H; y++) {
                for (int x = x0; x < x1 && x < (int)W; x++) {
                    unsigned char *p = data + (y * W + x) * 4;
                    // 跳过透明 / 近白画布，取键帽主体色
                    if (p[3] < 200) continue;
                    unsigned char mx = MAX(MAX(p[0], p[1]), p[2]);
                    unsigned char mn = MIN(MIN(p[0], p[1]), p[2]);
                    if (mx - mn < 15) continue;
                    rs += p[0]; gs += p[1]; bs += p[2]; n++;
                }
            }
            if (n > 0) {
                [out addObject:[UIColor colorWithRed:rs / n / 255.0
                                               green:gs / n / 255.0
                                                blue:bs / n / 255.0 alpha:1.0]];
            } else {
                [out addObject:[UIColor colorWithWhite:0.9 alpha:1.0]];
            }
        }
        CGContextRelease(ctx);
        cached = out;
    });
    return cached;
}

static BOOL wxkbPVDarkMode(UIView *ref) {
    if (@available(iOS 13.0, *)) {
        UITraitCollection *tc = ref.traitCollection;
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

// CFNotificationCallback 必须是函数指针，不能是 block
static void WXKBPreviewNotifyCallback(CFNotificationCenterRef center,
                                      void *observer,
                                      CFStringRef name,
                                      const void *object,
                                      CFDictionaryRef userInfo) {
    WXKBPreviewKeyboardView *self2 = (__bridge WXKBPreviewKeyboardView *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self2 refresh];
    });
}

@implementation WXKBPreviewKeyboardView {
    // 由 refresh 读出的偏好派生值（与 Tweak 的全局 g* 对应）
    BOOL  _gEnabled, _gBgEnabled, _gTransparent, _gKeyEnabled, _gSkinEnabled, _gGradEnabled;
    NSInteger _gBgMode, _gShape, _gSkinTheme, _gSkinDir, _gSkinBg;
    NSInteger _gCapStyle, _gEffCapStyle;
    CGFloat _gBgAlpha, _gCorner;
    UIColor *_gBgColor, *_gLetterBg, *_gDigitBg, *_gFuncLBg, *_gFuncRBg, *_gSpaceBg;
    UIColor *_gText, *_gTextDark, *_gHighlight, *_gHighlightDark;
    UIColor *_gGradFrom, *_gGradTo;
    NSDictionary *_gLetterMap;
    UIImage *_gBgImage;
    NSArray<UIColor *> *_gSkinStrip;
    BOOL _didRegisterNotify;
}

+ (CGFloat)preferredHeightForWidth:(CGFloat)width {
    // 紧凑一些：在较小的高度内画完整 4 行键盘，避免占用太多设置空间。
    CGFloat h = width * 0.46;
    if (h < 120.0) h = 120.0;
    if (h > 200.0) h = 200.0;
    return h;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;   // 预览不接收事件
        self.layer.cornerRadius = 12.0;
        self.clipsToBounds = YES;
        self.opaque = NO;
        [self wxkbRegisterNotify];
    }
    return self;
}

- (void)dealloc {
    if (_didRegisterNotify) {
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self,
            CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL);
    }
}

- (void)wxkbRegisterNotify {
    if (_didRegisterNotify) return;
    _didRegisterNotify = YES;
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        WXKBPreviewNotifyCallback,
        CFSTR(WXKB_CHANGED_NOTIFICATION_C), NULL,
        CFNotificationSuspensionBehaviorCoalesce);
}

#pragma mark - 读取偏好（对齐 WXKBReload）

- (void)refresh {
    NSDictionary *d = nil;
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:WXKB_PREFS_DOMAIN];
    d = [ud persistentDomainForName:WXKB_PREFS_DOMAIN];
    if (![d isKindOfClass:[NSDictionary class]] || d.count == 0) {
        d = @{};
    }

    _gEnabled    = d[WXKB_KEY_ENABLED] ? [d[WXKB_KEY_ENABLED] boolValue] : YES;
    _gBgEnabled  = [d[WXKB_KEY_BG_ENABLED] boolValue];
    _gBgMode     = d[WXKB_KEY_BG_MODE] ? [d[WXKB_KEY_BG_MODE] intValue] : 1;
    _gBgAlpha    = d[WXKB_KEY_BG_ALPHA] ? [d[WXKB_KEY_BG_ALPHA] doubleValue] : 1.0;
    if (_gBgAlpha < 0.05 || _gBgAlpha > 1.0) _gBgAlpha = 1.0;
    _gTransparent= [d[WXKB_KEY_TRANSPARENT] boolValue];
    _gKeyEnabled = [d[WXKB_KEY_KEY_ENABLED] boolValue];
    _gLetterBg   = wxkbPVColor(d[WXKB_KEY_LETTER_BG], 1.0)
                       ?: [UIColor colorWithWhite:1.0 alpha:0.96];
    _gDigitBg    = wxkbPVColor(d[WXKB_KEY_DIGIT_BG], 1.0);
    _gFuncLBg    = wxkbPVColor(d[WXKB_KEY_FUNC_L_BG], 1.0)
                       ?: [UIColor colorWithWhite:0.66 alpha:1.0];
    _gFuncRBg    = wxkbPVColor(d[WXKB_KEY_FUNC_R_BG], 1.0)
                       ?: [UIColor colorWithWhite:0.66 alpha:1.0];
    _gSpaceBg    = wxkbPVColor(d[WXKB_KEY_SPACE_BG], 1.0)
                       ?: [UIColor colorWithWhite:1.0 alpha:0.96];
    _gText       = wxkbPVColor(d[WXKB_KEY_KEY_TEXT], 1.0) ?: [UIColor blackColor];
    _gTextDark   = wxkbPVColor(d[WXKB_KEY_KEY_TEXT_DARK], 1.0);
    _gHighlight  = wxkbPVColor(d[WXKB_KEY_KEY_HIGHLIGHT], 1.0)
                       ?: [UIColor colorWithWhite:0.85 alpha:1.0];
    _gHighlightDark = wxkbPVColor(d[WXKB_KEY_KEY_HIGHLIGHT_DARK], 1.0);
    _gGradEnabled = [d[WXKB_KEY_GRAD_ENABLED] boolValue];
    _gGradFrom   = wxkbPVColor(d[WXKB_KEY_GRAD_FROM], 1.0)
                       ?: [UIColor colorWithRed:0.35 green:0.78 blue:0.98 alpha:1.0];
    _gGradTo     = wxkbPVColor(d[WXKB_KEY_GRAD_TO], 1.0)
                       ?: [UIColor colorWithRed:0.69 green:0.32 blue:0.87 alpha:1.0];
    _gLetterMap  = [d[WXKB_KEY_LETTER_MAP] isKindOfClass:[NSDictionary class]]
                       ? d[WXKB_KEY_LETTER_MAP] : nil;
    _gCorner     = d[WXKB_KEY_CORNER] ? [d[WXKB_KEY_CORNER] doubleValue] : 0.0;
    if (_gCorner < 0.0 || _gCorner > 22.0) _gCorner = 0.0;
    int sh = d[WXKB_KEY_SHAPE] ? [d[WXKB_KEY_SHAPE] intValue] : 0;
    if (sh < 0 || sh > 3) sh = 0; _gShape = sh;
    _gSkinEnabled = [d[WXKB_KEY_SKIN_ENABLED] boolValue];
    _gSkinTheme   = d[WXKB_KEY_SKIN_THEME] ? [d[WXKB_KEY_SKIN_THEME] integerValue] : 0;
    if (_gSkinTheme < 0 || _gSkinTheme > 31) _gSkinTheme = 0;
    _gSkinDir     = d[WXKB_KEY_SKIN_DIR] ? [d[WXKB_KEY_SKIN_DIR] integerValue] : 0;
    if (_gSkinDir < 0 || _gSkinDir > 2) _gSkinDir = 0;
    _gSkinBg      = d[WXKB_KEY_SKIN_BG] ? [d[WXKB_KEY_SKIN_BG] integerValue] : 0;
    if (_gSkinBg < 0 || _gSkinBg > 3) _gSkinBg = 0;
    _gCapStyle    = d[WXKB_KEY_CAP_STYLE] ? [d[WXKB_KEY_CAP_STYLE] integerValue] : 0;
    // 与 WXKBCapStyle() 一致：皮肤 + 关 -> 默认彩虹3D
    _gEffCapStyle = _gCapStyle;
    if (_gSkinEnabled && _gCapStyle == 0) _gEffCapStyle = 3;
    if (_gEffCapStyle < 0 || _gEffCapStyle > 5) _gEffCapStyle = 0;

    _gBgColor = wxkbPVColor(d[WXKB_KEY_BG_COLOR], _gBgAlpha)
                    ?: [UIColor colorWithWhite:0.11 alpha:_gBgAlpha];

    // 背景图
    _gBgImage = nil;
    id imgData = d[WXKB_KEY_BG_IMAGE_DATA];
    if (_gBgEnabled && _gBgMode == 2) {
        if ([imgData isKindOfClass:[NSData class]] && [imgData length]) {
            _gBgImage = [UIImage imageWithData:imgData];
        }
        if (!_gBgImage) {
            id imgPath = d[WXKB_KEY_BG_IMAGE];
            if ([imgPath isKindOfClass:[NSString class]] && [imgPath length]) {
                _gBgImage = [UIImage imageWithContentsOfFile:imgPath];
                if (!_gBgImage && ![imgPath hasPrefix:@"/var/jb"]) {
                    _gBgImage = [UIImage imageWithContentsOfFile:
                                 [@"/var/jb" stringByAppendingString:imgPath]];
                }
            }
        }
    }

    // 百度彩虹原图条带（theme 0）
    _gSkinStrip = (_gSkinEnabled && _gSkinTheme == 0) ? wxkbPVLoadSkinStrip() : nil;

    [self wxkbRebuild];
}

#pragma mark - 布局 + 上色

// 行定义：每行是若干键的描述。字母键带 alphabetIndex（用于渐进/逐个上色/主题取色）。
- (void)wxkbRebuild {
    // 清掉旧内容
    [self.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    CGRect b = self.bounds;
    CGFloat W = b.size.width, H = b.size.height;

    // 背景层
    [self wxkbDrawBackgroundInRect:b];

    if (!_gEnabled) {
        [self wxkbShowDisabledHintInRect:b];
        return;
    }

    // 键盘内边距 + 行间距（紧凑）
    CGFloat sideMargin = W * 0.018;
    CGFloat gap = W * 0.009;
    CGFloat topPad = H * 0.05;
    CGFloat usableW = W - 2 * sideMargin;

    // 完整微信输入法全键盘（4 行）：每行是 @[ @{t,k,i,w}, ... ]
    //   t=标签  k=种类(L字母/S空格/R功能)  i=字母序号(-1=非字母)  w=宽度权重
    NSMutableArray *row0 = [NSMutableArray array];
    NSString *r0 = @"QWERTYUIOP";
    for (int c = 0; c < 10; c++)
        [row0 addObject:@{@"t":[r0 substringWithRange:NSMakeRange(c,1)],
                          @"k":@"L", @"i":@(c), @"w":@1.0}];
    NSMutableArray *row1 = [NSMutableArray array];
    NSString *r1 = @"ASDFGHJKL";
    for (int c = 0; c < 9; c++)
        [row1 addObject:@{@"t":[r1 substringWithRange:NSMakeRange(c,1)],
                          @"k":@"L", @"i":@(10 + c), @"w":@1.0}];
    NSMutableArray *row2 = [NSMutableArray array];   // ⇧ ZXCVBNM ⌫
    [row2 addObject:@{@"t":@"⇧", @"k":@"L", @"i":@(-1), @"w":@1.3}];
    NSString *r2 = @"ZXCVBNM";
    for (int c = 0; c < 7; c++)
        [row2 addObject:@{@"t":[r2 substringWithRange:NSMakeRange(c,1)],
                          @"k":@"L", @"i":@(19 + c), @"w":@1.0}];
    [row2 addObject:@{@"t":@"⌫", @"k":@"R", @"i":@(-1), @"w":@1.3}];
    NSMutableArray *row3 = [NSMutableArray array];   // 123 ， 空格 。 （已去除地球/语音/返回键）
    [row3 addObject:@{@"t":@"123", @"k":@"L", @"i":@(-1), @"w":@1.3}];
    [row3 addObject:@{@"t":@"，", @"k":@"R", @"i":@(-1), @"w":@1.0}];
    [row3 addObject:@{@"t":@"",   @"k":@"S", @"i":@(-1), @"w":@4.4}];
    [row3 addObject:@{@"t":@"。", @"k":@"R", @"i":@(-1), @"w":@1.0}];
    NSArray *rows = @[row0, row1, row2, row3];

    CGFloat rowGapTotal = gap * 3;
    CGFloat rowH = (H - 2 * topPad - rowGapTotal) / 4.0;
    if (rowH < 6) rowH = 6;

    CGFloat y = topPad;
    for (NSArray *row in rows) {
        CGFloat totalW = 0;
        for (NSDictionary *kd in row) totalW += [kd[@"w"] doubleValue];
        CGFloat slotUnit = usableW / totalW;          // 每权重单位的槽宽（含间距配额）
        CGFloat x = sideMargin + gap * 0.5;            // 行内左右留半距，视觉居中
        for (NSDictionary *kd in row) {
            CGFloat wgt = [kd[@"w"] doubleValue];
            CGFloat slot = slotUnit * wgt;
            CGRect f = CGRectMake(x, y, slot - gap, rowH);
            char kind = [kd[@"k"] characterAtIndex:0];
            NSInteger idx = [kd[@"i"] integerValue];
            [self wxkbAddKey:f label:kd[@"t"] kind:kind
                      letterIdx:(int)idx slot:(idx >= 0 ? (int)idx : -1)
                      isSpace:(kind == 'S')];
            x += slot;
        }
        y += rowH + gap;
    }
}

- (void)wxkbDrawBackgroundInRect:(CGRect)b {
    UIColor *canvas = nil;
    UIImage *img = nil;
    BOOL transparent = NO;

    if (_gBgEnabled && _gBgMode == 2 && _gBgImage) {
        img = _gBgImage;
    } else if (_gBgEnabled) {
        canvas = _gBgColor;
    } else if (_gSkinEnabled) {
        // 皮肤画布色（对齐 WXKBSkinCanvasColor）
        switch (_gSkinBg) {
            case 1: canvas = [UIColor clearColor]; transparent = YES; break;
            case 2: canvas = [UIColor colorWithRed:0.80 green:0.80 blue:0.82 alpha:1.0]; break;
            case 3: canvas = [UIColor colorWithWhite:1.0 alpha:0.5]; break;
            default: canvas = [UIColor colorWithRed:245.0/255.0
                                               green:247.0/255.0 blue:250.0/255.0 alpha:1.0];
        }
    } else if (_gTransparent) {
        canvas = [UIColor clearColor]; transparent = YES;
    } else {
        // 原生键盘底色（无自定义）
        canvas = [UIColor colorWithRed:0.82 green:0.82 blue:0.84 alpha:1.0];
    }

    if (img) {
        UIImageView *iv = [[UIImageView alloc] initWithFrame:b];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.image = img;
        iv.clipsToBounds = YES;
        [self addSubview:iv];
    } else {
        UIView *bg = [[UIView alloc] initWithFrame:b];
        bg.backgroundColor = canvas;
        bg.opaque = (CGColorGetAlpha(canvas.CGColor) > 0.99);
        [self addSubview:bg];
        if (transparent) {
            [self wxkbDrawTransparentHintOn:bg];
        }
    }
}

- (void)wxkbDrawTransparentHintOn:(UIView *)bg {
    bg.backgroundColor = [UIColor clearColor];
    // 斜纹 + 文字提示「透明」
    CAShapeLayer *pat = [CAShapeLayer layer];
    pat.frame = bg.bounds;
    pat.backgroundColor = [UIColor colorWithWhite:0.9 alpha:0.5].CGColor;
    [bg.layer addSublayer:pat];
    UILabel *lab = [[UILabel alloc] initWithFrame:bg.bounds];
    lab.text = @"透明（透出后面内容）";
    lab.font = [UIFont systemFontOfSize:11];
    lab.textColor = [UIColor grayColor];
    lab.textAlignment = NSTextAlignmentCenter;
    [bg addSubview:lab];
}

- (void)wxkbShowDisabledHintInRect:(CGRect)b {
    UILabel *lab = [[UILabel alloc] initWithFrame:b];
    lab.text = @"总开关已关闭 — 键盘保持原生外观";
    lab.font = [UIFont systemFontOfSize:12];
    lab.textColor = [UIColor grayColor];
    lab.textAlignment = NSTextAlignmentCenter;
    lab.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    [self addSubview:lab];
}

#pragma mark - 单颗键

- (UIColor *)wxkbBaseColorForKind:(char)kind letterIdx:(int)letterIdx
                             slot:(int)slot isSpace:(BOOL)isSpace {
    // 皮肤优先（对齐 WXKBSkinColorFor / WXKBKeyBackground）
    if (_gSkinEnabled) {
        if (_gSkinTheme >= 1) {
            if (kind == 'L' && letterIdx >= 0) {
                NSInteger row = (slot < 10) ? 0 : (slot < 19) ? 1 : 2;
                CGFloat tx = (CGFloat)((slot % (row == 0 ? 10 : (row == 1 ? 9 : 7)) + 0.5)
                                       / (row == 0 ? 10.0 : (row == 1 ? 9.0 : 7.0)));
                UIColor *tc = wxkbPVThemeGradientColor(_gSkinTheme, _gSkinDir, row, tx);
                if (tc) return tc;
            }
            if (isSpace) {
                UIColor *tc = wxkbPVThemeGradientColor(_gSkinTheme, _gSkinDir, 3, 0.5);
                if (tc) return tc;
            }
            return [UIColor colorWithRed:0.90 green:0.90 blue:0.92 alpha:1.0];
        } else {
            // theme 0 百度彩虹原图：从 strip 采样
            if (kind == 'L' && letterIdx >= 0 && letterIdx < (int)_gSkinStrip.count) {
                return _gSkinStrip[letterIdx];
            }
            return [UIColor colorWithRed:0.88 green:0.88 blue:0.90 alpha:1.0];
        }
    }

    if (!_gKeyEnabled) return nil;

    if (kind == 'L') {
        // 字母键（对齐 WXKBLetterColorFor）
        if (_gLetterMap) {
            id v = _gLetterMap[[NSString stringWithFormat:@"%d", letterIdx]];
            if ([v isKindOfClass:[NSString class]] && [v length]) {
                UIColor *c = wxkbPVColor(v, 1.0);
                if (c) return c;
            }
        }
        if (_gGradEnabled && _gGradFrom && _gGradTo) {
            CGFloat t = (CGFloat)letterIdx / 25.0;
            CGFloat r1,g1,b1,a1,r2,g2,b2,a2;
            if ([_gGradFrom getRed:&r1 green:&g1 blue:&b1 alpha:&a1] &&
                [_gGradTo   getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) {
                return [UIColor colorWithRed:r1+(r2-r1)*t green:g1+(g2-g1)*t
                                        blue:b1+(b2-b1)*t alpha:a1+(a2-a1)*t];
            }
        }
        return _gLetterBg;
    }
    if (isSpace) return _gSpaceBg;
    if (kind == 'R') return _gFuncRBg;
    return _gFuncLBg;   // 左功能 / 数字符号键
}

- (UIColor *)wxkbTextColorForKind:(char)kind base:(UIColor *)base {
    if (_gSkinEnabled) {
        return [UIColor colorWithRed:0.0 green:0.0 blue:0.0 alpha:1.0];
    }
    BOOL isLetter = (kind == 'L');
    if (isLetter && (_gEffCapStyle == 3 || _gEffCapStyle == 4 || _gEffCapStyle == 5)) {
        return [UIColor colorWithRed:0.23 green:0.23 blue:0.25 alpha:1.0];
    }
    if (!( _gEnabled && _gKeyEnabled)) return nil;
    BOOL dark = wxkbPVDarkMode(self);
    return dark ? (_gTextDark ?: _gText) : _gText;
}

- (void)wxkbAddKey:(CGRect)f label:(NSString *)label kind:(char)kind
          letterIdx:(int)letterIdx slot:(int)slot isSpace:(BOOL)isSpace {
    UIColor *base = [self wxkbBaseColorForKind:kind letterIdx:letterIdx
                                          slot:slot isSpace:isSpace];
    UIView *key = [[UIView alloc] initWithFrame:f];
    key.backgroundColor = [UIColor clearColor];
    key.layer.masksToBounds = NO;   // 让侧壁可伸出
    [self addSubview:key];

    if (_gEffCapStyle == 0 || !base) {
        // 无键帽：直接铺底色 + 圆角
        key.backgroundColor = base ?: [UIColor colorWithWhite:1.0 alpha:0.96];
        CGFloat r = (_gCorner > 0.01) ? _gCorner : 5.0;
        r = MIN(r, MIN(f.size.width, f.size.height) / 2.0);
        key.layer.cornerRadius = MAX(r, 1.0);
        key.layer.masksToBounds = YES;
    } else {
        [self wxkbApplyCap:key rect:f base:base];
    }

    // 文字
    UIColor *tc = [self wxkbTextColorForKind:kind base:base] ?: [UIColor blackColor];
    UILabel *lab = [[UILabel alloc] initWithFrame:key.bounds];
    lab.text = label;
    lab.textAlignment = NSTextAlignmentCenter;
    lab.textColor = tc;
    lab.font = isSpace ? [UIFont systemFontOfSize:MIN(f.size.height * 0.4, 15)]
                       : [UIFont systemFontOfSize:MIN(f.size.height * 0.42, 17)];
    lab.adjustsFontSizeToFitWidth = YES;
    lab.minimumScaleFactor = 0.5;
    [key addSubview:lab];
}

// 把 Tweak 的 WXKBApplyCap 数学搬过来，套到单颗键上（target==key 自身）。
- (void)wxkbApplyCap:(UIView *)key rect:(CGRect)f base:(UIColor *)base {
    CGSize sz = f.size;
    if (sz.width <= 8 || sz.height <= 8) return;
    NSInteger cs = _gEffCapStyle;
    NSInteger shape = _gShape;

    // 2.2.8 长键（空格等）的六边形/水珠回退为圆角
    CGFloat ratio = sz.width / sz.height;
    if (ratio < 0) ratio = -ratio;
    BOOL squareish = (ratio >= 0.75 && ratio <= 1.35);
    NSInteger effShape = shape;
    if (shape >= 2 && !squareish) effShape = 0;

    CGFloat kDepth = 4.0, kInset = 4.0, kFront = 7.0, topY = 2.5;
    if (cs == 2)      { kInset = 3.0; kFront = 8.0; topY = 2.0; }
    else if (cs == 3) { kDepth = 7.0; kInset = 4.5; kFront = 8.0; topY = 2.5; }
    else if (cs == 4) { kDepth = 4.0; kInset = 2.5; kFront = 5.0; topY = 2.0; }
    else if (cs == 5) { kDepth = 5.0; kInset = 3.0; kFront = 6.0; topY = 2.0; }

    CGFloat rad = 5.0;
    if (shape == 0) {
        rad = key.layer.cornerRadius;
        if (_gCorner > 0.01) rad = _gCorner;
        rad = MIN(rad, MIN(sz.width, sz.height) / 2.0);
        if (rad <= 0.5) rad = 5.0;
    }
    if (cs == 3 && shape == 0) {
        rad = MAX(rad, MIN(sz.width, sz.height) * 0.18);
        rad = MIN(rad, MIN(sz.width, sz.height) * 0.30);
    } else if (cs == 4 && shape == 0) {
        rad = MAX(rad, MIN(sz.width, sz.height) * 0.30);
        rad = MIN(rad, MIN(sz.width, sz.height) * 0.45);
    } else if (cs == 5 && shape == 0) {
        rad = MAX(rad, MIN(sz.width, sz.height) * 0.20);
        rad = MIN(rad, MIN(sz.width, sz.height) * 0.35);
    }

    // 由底色推导各段色（与 WXKBApplyCap 完全一致）
    CGFloat h = 0, s = 0, br = 0.9, al = 0;
    UIColor *cHi, *cLight, *cFace, *cLow, *cFront, *cWallHi, *cWallLo, *cEdge;
    if (base && [base getHue:&h saturation:&s brightness:&br alpha:&al] && s > 0.02) {
        cHi    = [UIColor colorWithHue:h saturation:MAX(s*0.30,0) brightness:MIN(br*1.35+0.34,1) alpha:1];
        cLight = [UIColor colorWithHue:h saturation:s brightness:MIN(br*1.14,1) alpha:1];
        cFace  = [UIColor colorWithHue:h saturation:s brightness:br alpha:1];
        cLow   = [UIColor colorWithHue:h saturation:s brightness:br*0.78 alpha:1];
        cFront = [UIColor colorWithHue:h saturation:MIN(s*1.25,1) brightness:br*0.46 alpha:1];
        cWallHi= [UIColor colorWithHue:h saturation:s*0.30 brightness:MAX(br*0.60,0.30) alpha:1];
        cWallLo= [UIColor colorWithHue:h saturation:MIN(s*0.55,1) brightness:MAX(br*0.30,0.14) alpha:1];
    } else {
        CGFloat w = (base) ? br : 0.78;
        if (base) { CGFloat a0=0; if (![base getWhite:&w alpha:&a0]) w = br; }
        cHi    = [UIColor colorWithWhite:MIN(w*1.30+0.22,1) alpha:1];
        cLight = [UIColor colorWithWhite:MIN(w*1.12,1) alpha:1];
        cFace  = [UIColor colorWithWhite:w alpha:1];
        cLow   = [UIColor colorWithWhite:w*0.82 alpha:1];
        cFront = [UIColor colorWithWhite:w*0.46 alpha:1];
        cWallHi= [UIColor colorWithWhite:MAX(w*0.68,0.42) alpha:1];
        cWallLo= [UIColor colorWithWhite:MAX(w*0.36,0.16) alpha:1];
    }
    if (cs == 3) {
        cWallHi= [UIColor colorWithHue:h saturation:MIN(s*1.05,1) brightness:MAX(br*0.78,0.50) alpha:1];
        cWallLo= [UIColor colorWithHue:h saturation:MIN(s*1.15,1) brightness:MAX(br*0.62,0.38) alpha:1];
        cEdge  = [UIColor colorWithHue:h saturation:MIN(s*1.20,1) brightness:MAX(br*0.50,0.30) alpha:0.40];
        cHi    = [UIColor colorWithHue:h saturation:MAX(s*0.50,0) brightness:MIN(br*1.35+0.20,1) alpha:1];
        cLow   = [UIColor colorWithHue:h saturation:MIN(s*1.10,1) brightness:br*0.65 alpha:1];
    } else if (cs == 4) {
        cWallHi= [UIColor colorWithHue:h saturation:MIN(s*1.05,1) brightness:MAX(br*0.85,0.55) alpha:1];
        cWallLo= [UIColor colorWithHue:h saturation:MIN(s*1.10,1) brightness:MAX(br*0.70,0.45) alpha:1];
        cEdge  = [UIColor colorWithWhite:0 alpha:0];
        cHi    = [UIColor colorWithHue:h saturation:MAX(s*0.40,0) brightness:MIN(br*1.25+0.15,1) alpha:1];
        cLow   = [UIColor colorWithHue:h saturation:MIN(s*1.05,1) brightness:br*0.80 alpha:1];
    } else if (cs == 5) {
        cWallHi= [UIColor colorWithHue:h saturation:1 brightness:0.90 alpha:1];
        cWallLo= [UIColor colorWithHue:h saturation:1 brightness:0.60 alpha:1];
        cEdge  = [UIColor colorWithHue:h saturation:1 brightness:1 alpha:0.80];
        cHi    = [UIColor colorWithHue:h saturation:0.80 brightness:0.30 alpha:1];
        cLow   = [UIColor colorWithHue:h saturation:1 brightness:0.15 alpha:1];
        cFace  = [UIColor colorWithHue:h saturation:0.90 brightness:0.20 alpha:1];
    } else if (cs == 2) {
        cWallHi= [UIColor colorWithWhite:0.985 alpha:1];
        cWallLo= [UIColor colorWithWhite:0.800 alpha:1];
        cEdge  = [UIColor colorWithWhite:0.60 alpha:0.30];
        cHi    = cLight;
        cLow   = cFace;
    } else {
        cEdge = [UIColor colorWithWhite:0.18 alpha:0.92];
    }

    UIBezierPath *silLeaf;
    if (effShape == 2) silLeaf = wxkbPVHexagon(sz);
    else if (effShape == 3) silLeaf = wxkbPVWaterDrop(sz);
    else {
        if (effShape == 1) rad = MIN(sz.width, sz.height) / 2.0;
        silLeaf = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,sz.width,sz.height)
                                             cornerRadius:rad];
    }
    if (!silLeaf) return;

    UIBezierPath *topPath;
    if (effShape >= 2) {
        topPath = [silLeaf copy];
        CGFloat cx = sz.width/2.0, cy = sz.height/2.0;
        CGAffineTransform t = CGAffineTransformMakeTranslation(cx, cy);
        t = CGAffineTransformConcat(CGAffineTransformMakeScale(0.88,0.88), t);
        t = CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(-cx,-cy));
        [topPath applyTransform:t];
    } else {
        CGFloat rr;
        if (effShape == 1) rr = MAX(MIN(sz.width,sz.height)/2.0 - kInset, 2.0);
        else if (cs == 3) rr = rad;
        else if (cs == 4) rr = MAX(rad*0.85, 3.5);
        else rr = MAX(rad*0.8, 3.0);
        CGFloat botY = kInset + kFront;
        topPath = [UIBezierPath bezierPathWithRoundedRect:
                       CGRectMake(kInset, topY, sz.width - 2*kInset, sz.height - topY - botY)
                                             cornerRadius:rr];
    }

    UIBezierPath *silWall;
    if (effShape == 2) silWall = wxkbPVHexagon(sz);
    else if (effShape == 3) silWall = wxkbPVWaterDrop(sz);
    else {
        CGFloat r2 = rad;
        if (effShape == 1) r2 = MIN(sz.width, sz.height)/2.0;
        silWall = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,sz.width,sz.height)
                                             cornerRadius:r2];
    }
    if (!silWall) return;

    CALayer *root = key.layer;

    // ① 键体
    CAShapeLayer *body = [CAShapeLayer layer];
    body.frame = CGRectMake(0,0,sz.width,sz.height);
    body.path = silLeaf.CGPath;
    body.fillColor = cWallLo.CGColor;
    body.zPosition = -998;
    [root addSublayer:body];

    // ①' 侧壁裙边渐变
    CAGradientLayer *skirt = [CAGradientLayer layer];
    skirt.frame = CGRectMake(0,0,sz.width,sz.height);
    skirt.startPoint = CGPointMake(0.5,0); skirt.endPoint = CGPointMake(0.5,1);
    skirt.colors = @[(id)cWallHi.CGColor, (id)cWallLo.CGColor];
    CAShapeLayer *smask = [CAShapeLayer layer]; smask.path = silLeaf.CGPath;
    skirt.mask = smask; skirt.zPosition = -997.5;
    skirt.hidden = (cs == 3);
    [root addSublayer:skirt];

    // ② 凸起顶面（穹顶渐变）
    CAGradientLayer *top = [CAGradientLayer layer];
    top.frame = CGRectMake(0,0,sz.width,sz.height);
    top.startPoint = CGPointMake(0.5,0); top.endPoint = CGPointMake(0.5,1);
    if (cs == 3) {
        top.locations = @[@0.0,@0.15,@0.70,@1.0];
        top.colors = @[(id)cHi.CGColor,(id)cFace.CGColor,(id)cFace.CGColor,(id)cLow.CGColor];
    } else if (cs == 4) {
        top.locations = @[@0.0,@0.25,@0.75,@1.0];
        top.colors = @[(id)cHi.CGColor,(id)cFace.CGColor,(id)cFace.CGColor,(id)cLow.CGColor];
    } else if (cs == 5) {
        top.locations = @[@0.0,@0.30,@0.70,@1.0];
        top.colors = @[(id)cHi.CGColor,(id)cFace.CGColor,(id)cFace.CGColor,(id)cLow.CGColor];
    } else if (cs == 2) {
        top.locations = @[@0.0,@0.45,@0.85,@1.0];
        top.colors = @[(id)cHi.CGColor,(id)cFace.CGColor,(id)cFace.CGColor,(id)cLow.CGColor];
    } else {
        top.locations = @[@0.0,@0.12,@0.55,@1.0];
        top.colors = @[(id)cHi.CGColor,(id)cLight.CGColor,(id)cFace.CGColor,(id)cLow.CGColor];
    }
    CAShapeLayer *tmask = [CAShapeLayer layer]; tmask.path = topPath.CGPath;
    top.mask = tmask; top.zPosition = -997;
    [root addSublayer:top];

    // ①'' 轮廓硬描边
    CAShapeLayer *edge = [CAShapeLayer layer];
    edge.frame = CGRectMake(0,0,sz.width,sz.height);
    edge.path = silLeaf.CGPath;
    edge.fillColor = [UIColor clearColor].CGColor;
    edge.strokeColor = cEdge.CGColor;
    edge.lineWidth = (cs == 2) ? 1.0 : ((cs == 4) ? 0.8 : 1.4);
    edge.zPosition = -996;
    edge.hidden = (cs == 3);
    [root addSublayer:edge];

    // ③ 伸出底部的侧壁
    UIBezierPath *wallPath = [silWall copy];
    [wallPath applyTransform:CGAffineTransformMakeTranslation(0, kDepth)];
    CAShapeLayer *wall = [CAShapeLayer layer];
    wall.frame = CGRectMake(0,0,sz.width,sz.height + kDepth);
    wall.path = wallPath.CGPath;
    wall.fillColor = cWallLo.CGColor;
    wall.zPosition = -1000;
    wall.hidden = (cs == 3) || kDepth <= 0.0;
    [root addSublayer:wall];

    // ④ 柔和投影
    key.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1].CGColor;
    if (cs == 3)      { key.layer.shadowOpacity = 0.25; key.layer.shadowOffset = CGSizeMake(0,4);  key.layer.shadowRadius = 5; }
    else if (cs == 4) { key.layer.shadowOpacity = 0.20; key.layer.shadowOffset = CGSizeMake(0,3.5);key.layer.shadowRadius = 5; }
    else if (cs == 5) { key.layer.shadowOpacity = 0.50; key.layer.shadowOffset = CGSizeMake(0,2);  key.layer.shadowRadius = 6; key.layer.shadowColor = cEdge.CGColor; }
    else if (cs == 2) { key.layer.shadowOpacity = 0.20; key.layer.shadowOffset = CGSizeMake(0,3);  key.layer.shadowRadius = 4.5; }
    else              { key.layer.shadowOpacity = 0.28; key.layer.shadowOffset = CGSizeMake(0,2);  key.layer.shadowRadius = 3; }
}

@end
