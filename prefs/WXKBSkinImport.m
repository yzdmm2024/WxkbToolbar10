// WXKBSkinImport.m — 百度 .bdi 皮肤导入 / 内置预设 / 清除
#import "WXKBSkinImport.h"
#import "WXKBCommon.h"
#import <objc/runtime.h>

// iOS SDK 不导出 NSTask（仅 macOS 公开）；越狱环境运行时可用，这里补最小接口声明。
@interface NSTask : NSObject
- (void)setLaunchPath:(NSString *)path;
- (void)setArguments:(NSArray<NSString *> *)arguments;
- (void)launch;
- (void)waitUntilExit;
- (int)terminationStatus;
@end

// 前向声明：delegate 回调里会先调用，定义在下文。
BOOL WXKBParseAndApplyBdi(NSString *bdiPath, NSString **err);

#pragma mark - 内部 delegate：文件选择器

@interface WXKBSkinImporter : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *vc;
@end

@implementation WXKBSkinImporter

- (void)documentPicker:(UIDocumentPickerViewController *)controller
    didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *u = urls.firstObject;
    if (!u) {
        [self finish:NO msg:@"未选择文件"];
        return;
    }
    BOOL sec = [u startAccessingSecurityScopedResource];
    NSString *err = nil;
    BOOL ok = WXKBParseAndApplyBdi(u.path, &err);
    if (sec) {
        [u stopAccessingSecurityScopedResource];
    }
    [self finish:ok msg:err];
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    // 用户取消，不提示
}

- (void)finish:(BOOL)ok msg:(NSString *)msg {
    NSString *title = ok ? @"已导入" : @"导入失败";
    NSString *message = ok ? @"皮肤已应用，收起键盘再弹出即可生效。"
                           : (msg ?: @"未知错误");
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:title message:message
                   preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好"
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self.vc presentViewController:a animated:YES completion:nil];
}

@end

#pragma mark - 解压 + 解析 + 应用

// 解析 default.css 里 [STYLE1] 段的某个颜色键，取后 6 位作为 RRGGBB（兼容百度 AARRGGBB）。
static NSString *WXKBSkinParseColor(NSString *cssDir, NSString *mode,
                                     NSString *which) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *cp = [cssDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"skin/%@/skin/res/default.css", mode]];
    if (![fm fileExistsAtPath:cp]) {
        cp = [cssDir stringByAppendingPathComponent:@"skin/res/default.css"];
    }
    if (![fm fileExistsAtPath:cp]) {
        return nil;
    }
    NSString *css = [NSString stringWithContentsOfFile:cp
                                             encoding:NSUTF8StringEncoding
                                                error:nil];
    if (!css) {
        return nil;
    }
    NSRange r = [css rangeOfString:@"[STYLE1]"];
    NSString *seg = css;
    if (r.location != NSNotFound) {
        NSRange rest = NSMakeRange(r.location + 8,
                                   css.length - r.location - 8);
        NSRange end = [css rangeOfString:@"[STYLE"
                                options:0
                                  range:rest];
        NSUInteger endLoc = (end.location == NSNotFound)
                                ? css.length : end.location;
        seg = [css substringWithRange:NSMakeRange(r.location, endLoc - r.location)];
    }
    NSString *key = [which isEqualToString:@"hl"] ? @"HL_COLOR" : @"NM_COLOR";
    NSRegularExpression *rx = [NSRegularExpression
        regularExpressionWithPattern:
            [NSString stringWithFormat:@"%@=([0-9a-fA-F]+)", key]
                             options:0 error:nil];
    NSTextCheckingResult *m = [rx firstMatchInString:seg
                                            options:0
                                              range:NSMakeRange(0, seg.length)];
    if (!m) {
        return nil;
    }
    NSString *hex = [seg substringWithRange:[m rangeAtIndex:1]];
    if (hex.length >= 6) {
        // 取后 6 位 = RRGGBB（百度 8 位是 AARRGGBB）
        hex = [hex substringWithRange:NSMakeRange(hex.length - 6, 6)];
    }
    return hex;
}

// 把解析出的图 + 配色写进偏好并通知键盘扩展
static void WXKBApplySkinWithImages(NSData *dark, NSData *light,
                                     NSString *tLight, NSString *tDark,
                                     NSString *hLight, NSString *hDark) {
    WXKBSetPref(WXKB_KEY_BG_ENABLED, @YES);
    WXKBSetPref(WXKB_KEY_BG_MODE, @2);
    WXKBSetPref(WXKB_KEY_BG_IMAGE_DATA_DARK, dark);
    WXKBSetPref(WXKB_KEY_BG_IMAGE_DATA, light);
    WXKBSetPref(WXKB_KEY_KEY_ENABLED, @YES);
    WXKBSetPref(WXKB_KEY_KEY_TEXT, tLight);
    WXKBSetPref(WXKB_KEY_KEY_TEXT_DARK, tDark);
    WXKBSetPref(WXKB_KEY_KEY_HIGHLIGHT, hLight);
    WXKBSetPref(WXKB_KEY_KEY_HIGHLIGHT_DARK, hDark);
    [WXKBBaseListController wxkbNotifyChanged];
}

BOOL WXKBParseAndApplyBdi(NSString *bdiPath, NSString **err) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *tmp = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [fm createDirectoryAtPath:tmp
      withIntermediateDirectories:YES
                       attributes:nil
                            error:nil];

    // 越狱环境用系统 unzip 解压（.bdi 即 zip）
    NSTask *t = [[NSTask alloc] init];
    t.launchPath = @"/usr/bin/unzip";
    t.arguments = @[@"-o", bdiPath, @"-d", tmp];
    @try {
        [t launch];
        [t waitUntilExit];
    } @catch (NSException *e) {
        if (err) *err = @"无法调用 unzip（需越狱环境）";
        return NO;
    }
    if (t.terminationStatus != 0) {
        if (err) *err = @"解压 .bdi 失败";
        return NO;
    }

    NSString *(^find)(NSString *, NSString *) =
        ^NSString *(NSString *mode, NSString *file) {
            NSString *p1 = [tmp stringByAppendingPathComponent:
                [NSString stringWithFormat:@"skin/%@/skin/res/%@", mode, file]];
            if ([fm fileExistsAtPath:p1]) return p1;
            NSString *p2 = [tmp stringByAppendingPathComponent:
                [NSString stringWithFormat:@"skin/res/%@", file]];
            if ([fm fileExistsAtPath:p2]) return p2;
            return nil;
        };

    NSData *dark = nil, *light = nil;
    NSString *dp = find(@"dark", @"bj.png");
    if (dp) dark = [NSData dataWithContentsOfFile:dp];
    NSString *lp = find(@"light", @"bj.png");
    if (lp) light = [NSData dataWithContentsOfFile:lp];
    if (!dark && !light) {
        if (err) *err = @"未找到背景图 bj.png";
        [fm removeItemAtPath:tmp error:nil];
        return NO;
    }
    if (!dark) dark = light;
    if (!light) light = dark;

    NSString *tDark  = WXKBSkinParseColor(tmp, @"dark",  @"text") ?: @"f9dcc2";
    NSString *hDark  = WXKBSkinParseColor(tmp, @"dark",  @"hl")   ?: @"fec48f";
    NSString *tLight = WXKBSkinParseColor(tmp, @"light", @"text") ?: @"393c44";
    NSString *hLight = WXKBSkinParseColor(tmp, @"light", @"hl")   ?: @"ec9f27";

    WXKBApplySkinWithImages(dark, light, tLight, tDark, hLight, hDark);
    [fm removeItemAtPath:tmp error:nil];
    return YES;
}

void WXKBImportBdiFromViewController(UIViewController *vc) {
    UIDocumentPickerViewController *dp =
        [[UIDocumentPickerViewController alloc]
            initWithDocumentTypes:@[@"public.data"]
                          inMode:UIDocumentPickerModeOpen];
    WXKBSkinImporter *imp = [[WXKBSkinImporter alloc] init];
    imp.vc = vc;
    dp.delegate = imp;
    dp.allowsMultipleSelection = NO;
    // 把 importer 挂在 dp 上，避免异步回调时它被释放
    objc_setAssociatedObject(dp, "wxkbImporter", imp,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [vc presentViewController:dp animated:YES completion:nil];
}

BOOL WXKBApplyQiuyiPreset(void) {
    NSBundle *b = [NSBundle bundleForClass:[WXKBBaseListController class]];
    NSData *dark = [NSData dataWithContentsOfFile:
        [b pathForResource:@"bj_dark" ofType:@"png"]];
    NSData *light = [NSData dataWithContentsOfFile:
        [b pathForResource:@"bj_light" ofType:@"png"]];
    if (!dark && !light) {
        return NO;
    }
    if (!dark) dark = light;
    if (!light) light = dark;
    WXKBApplySkinWithImages(dark, light, @"393c44", @"f9dcc2",
                            @"ec9f27", @"fec48f");
    return YES;
}

void WXKBClearSkin(void) {
    NSArray *keys = @[
        WXKB_KEY_BG_ENABLED, WXKB_KEY_BG_MODE,
        WXKB_KEY_BG_IMAGE_DATA, WXKB_KEY_BG_IMAGE_DATA_DARK,
        WXKB_KEY_KEY_ENABLED,
        WXKB_KEY_KEY_TEXT, WXKB_KEY_KEY_TEXT_DARK,
        WXKB_KEY_KEY_HIGHLIGHT, WXKB_KEY_KEY_HIGHLIGHT_DARK
    ];
    for (NSString *k in keys) {
        WXKBSetPref(k, nil);
    }
    [WXKBBaseListController wxkbNotifyChanged];
}
