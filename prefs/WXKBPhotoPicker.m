// WXKBPhotoPicker.m — 相册选图 + 按键盘比例横向裁剪
#import "WXKBCommon.h"
#import <PhotosUI/PhotosUI.h>

#pragma mark - 裁剪页

// 固定一个「微信键盘比例」的裁剪窗，图片在其中拖动/缩放，
// 确认后把窗口内的内容渲染成图，即为横向裁剪结果。
@interface WXKBCropViewController : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) void (^onFinish)(UIImage *cropped);
@end

@implementation WXKBCropViewController {
    UIScrollView *_scroll;
    UIImageView  *_imageView;
    BOOL          _laid;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];
    self.title = @"裁剪背景";

    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scroll.delegate = self;
    _scroll.showsHorizontalScrollIndicator = NO;
    _scroll.showsVerticalScrollIndicator = NO;
    _scroll.clipsToBounds = YES;
    _scroll.backgroundColor = [UIColor blackColor];
    _scroll.bouncesZoom = YES;
    _scroll.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.55].CGColor;
    _scroll.layer.borderWidth = 1.0;
    [self.view addSubview:_scroll];

    _imageView = [[UIImageView alloc] initWithImage:self.image];
    _imageView.userInteractionEnabled = YES;
    [_scroll addSubview:_imageView];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectZero];
    hint.text = @"拖动 / 双指缩放调整位置，比例与微信键盘一致";
    hint.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    hint.font = [UIFont systemFontOfSize:12.0];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.numberOfLines = 0;
    hint.tag = 0x57584331;
    [self.view addSubview:hint];

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                      target:self
                                                      action:@selector(cancelTapped)];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(doneTapped)];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width - 32.0;
    CGFloat h = w * (WXKB_KB_ASPECT_H / WXKB_KB_ASPECT_W);
    CGFloat y = (self.view.bounds.size.height - h) / 2.0;
    _scroll.frame = CGRectMake(16.0, y, w, h);

    UIView *hint = [self.view viewWithTag:0x57584331];
    hint.frame = CGRectMake(16.0, CGRectGetMaxY(_scroll.frame) + 16.0, w, 40.0);

    if (!_laid && w > 0) {
        _laid = YES;
        [self layoutImage];
    }
}

- (void)layoutImage {
    CGSize b = _scroll.bounds.size;
    CGSize i = self.image.size;
    if (i.width <= 0 || i.height <= 0 || b.width <= 0 || b.height <= 0) {
        return;
    }
    CGFloat scale = MAX(b.width / i.width, b.height / i.height);
    _imageView.frame = CGRectMake(0, 0, i.width * scale, i.height * scale);
    _scroll.contentSize = _imageView.frame.size;
    _scroll.minimumZoomScale = 1.0;
    _scroll.maximumZoomScale = 5.0;
    _scroll.zoomScale = 1.0;
    _scroll.contentOffset = CGPointMake((_imageView.frame.size.width - b.width) / 2.0,
                                        (_imageView.frame.size.height - b.height) / 2.0);
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _imageView;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    CGSize b = scrollView.bounds.size;
    CGSize c = scrollView.contentSize;
    CGFloat ox = MAX(0.0, (b.width - c.width) / 2.0);
    CGFloat oy = MAX(0.0, (b.height - c.height) / 2.0);
    scrollView.contentInset = UIEdgeInsetsMake(oy, ox, oy, ox);
}

- (void)cancelTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)doneTapped {
    CGSize cropSize = _scroll.bounds.size;
    if (cropSize.width <= 1.0 || cropSize.height <= 1.0) {
        [self cancelTapped];
        return;
    }
    CGFloat scale = [UIScreen mainScreen].scale;
    CGPoint off = _scroll.contentOffset;

    UIGraphicsBeginImageContextWithOptions(cropSize, NO, scale);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextTranslateCTM(ctx, -off.x, -off.y);
    [_imageView.layer renderInContext:ctx];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (self.onFinish) {
        self.onFinish(out);
    }
}

@end

#pragma mark - 图片编码

static NSData *WXKBEncodeImage(UIImage *image, CGFloat maxWidth) {
    if (!image) {
        return nil;
    }
    CGSize s = image.size;
    if (s.width <= 0 || s.height <= 0) {
        return nil;
    }
    CGFloat k = MIN(1.0, maxWidth / s.width);
    CGSize t = CGSizeMake(round(s.width * k), round(s.height * k));

    UIGraphicsBeginImageContextWithOptions(t, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, t.width, t.height)];
    UIImage *small = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (!small) {
        return nil;
    }
    NSData *d = UIImageJPEGRepresentation(small, 0.85);
    if (d.length > 400 * 1024) {
        d = UIImageJPEGRepresentation(small, 0.6);
    }
    return d;
}

#pragma mark - 背景图页

@interface WXKBPhotoListController : WXKBBaseListController <PHPickerViewControllerDelegate>
@end

@implementation WXKBPhotoListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"背景图片";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (NSString *)statusText {
    NSData *d = WXKBGetPref(WXKB_KEY_BG_IMAGE_DATA);
    if ([d isKindOfClass:[NSData class]] && d.length > 0) {
        UIImage *img = [UIImage imageWithData:d];
        if (img) {
            return [NSString stringWithFormat:@"当前：相册图片 %d×%d，约 %d KB",
                    (int)img.size.width, (int)img.size.height,
                    (int)(d.length / 1024)];
        }
        return @"当前：已选择图片";
    }
    NSString *p = WXKBGetPref(WXKB_KEY_BG_IMAGE);
    if ([p isKindOfClass:[NSString class]] && p.length) {
        return [NSString stringWithFormat:@"当前：路径 %@", p];
    }
    return @"当前：未选择背景图";
}

- (NSArray *)specifiers {
    if (_specifiers) {
        return _specifiers;
    }
    NSMutableArray *s = [NSMutableArray array];
    PSSpecifier *g;

    g = [PSSpecifier groupSpecifierWithName:@"从相册选择"];
    [g setProperty:[NSString stringWithFormat:
                       @"%@\n\n选好后会按微信键盘比例（约 3:2）裁剪成横向长条，自动铺满键盘背景。",
                       [self statusText]]
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbButton:@"从相册选择…" action:@selector(pickPhoto:)]];
    [s addObject:[self wxkbButton:@"清除背景图" action:@selector(clearPhoto:)]];

    g = [PSSpecifier groupSpecifierWithName:@"高级"];
    [g setProperty:@"一般不用填；这里直接指定设备上的图片文件路径，优先级低于相册图片。"
            forKey:@"footerText"];
    [s addObject:g];
    [s addObject:[self wxkbEdit:@"图片路径" key:WXKB_KEY_BG_IMAGE def:@""
                    placeholder:@"/var/mobile/bg.png"]];

    _specifiers = s;
    return _specifiers;
}

- (void)pickPhoto:(PSSpecifier *)specifier {
    PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
    cfg.selectionLimit = 1;
    cfg.filter = [PHPickerFilter imagesFilter];
    PHPickerViewController *p = [[PHPickerViewController alloc] initWithConfiguration:cfg];
    p.delegate = self;
    [self presentViewController:p animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker
    didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) {
        return;
    }
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider canLoadObjectOfClass:[UIImage class]]) {
        return;
    }
    [provider loadObjectOfClass:[UIImage class]
              completionHandler:^(UIImage *image, NSError *error) {
        if (!image) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [self presentCrop:image];
        });
    }];
}

- (void)presentCrop:(UIImage *)image {
    WXKBCropViewController *c = [[WXKBCropViewController alloc] init];
    c.image = image;
    __weak typeof(self) weakSelf = self;
    c.onFinish = ^(UIImage *cropped) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }
        NSData *data = WXKBEncodeImage(cropped, 900.0);
        if (data.length > 0) {
            WXKBSetPref(WXKB_KEY_BG_IMAGE_DATA, data);
            WXKBSetPref(WXKB_KEY_BG_MODE, @2);
            WXKBSetPref(WXKB_KEY_BG_ENABLED, @YES);
            [[self class] wxkbNotifyChanged];
        }
        _specifiers = nil;
        [self.navigationController popToViewController:self animated:YES];
        [self reloadSpecifiers];
    };
    [self.navigationController pushViewController:c animated:YES];
}

- (void)clearPhoto:(PSSpecifier *)specifier {
    WXKBSetPref(WXKB_KEY_BG_IMAGE_DATA, nil);
    [[self class] wxkbNotifyChanged];
    _specifiers = nil;
    [self reloadSpecifiers];
}

@end