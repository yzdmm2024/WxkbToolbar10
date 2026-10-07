// WxkbToolbar10Host — 宿主 App 侧的「编辑增强」执行端
//
// 为什么需要这个 dylib：
//   微信输入法键盘跑在独立沙盒进程（com.tencent.wetype.keyboard）里，键盘扩展
//   拿不到宿主 App 的 firstResponder，所以「全选 / 剪切 / 粘贴 / 全删 / 收起键盘」
//   这类需要 UIResponder 标准动作的按钮，光靠键盘扩展点了必然没反应。
//   这个 dylib 注入普通 App，监听键盘扩展用 Darwin 通知发过来的动作码，
//   在宿主进程里对真正的输入框执行。
//
// 安全设计（对齐 jianpanxiafangzhuangtai 的做法）：
//   - 注入范围限定为普通 App，明确排除 SpringBoard 与 Preferences；
//   - 全部逻辑包在 @try/@catch，不碰宿主 App 的任何状态；
//   - 只响应我们自己的 Darwin 通知，不主动注入 UI、不加任何手势。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "WXKBShared.h"

#pragma mark - Darwin 通知名

#define WXKB_NTF_SELECT_ALL  "com.yzdmm.wxkbtoolbar10/host/selectAll"
#define WXKB_NTF_CUT         "com.yzdmm.wxkbtoolbar10/host/cut"
#define WXKB_NTF_PASTE       "com.yzdmm.wxkbtoolbar10/host/paste"
#define WXKB_NTF_DELETE_ALL  "com.yzdmm.wxkbtoolbar10/host/deleteAll"
#define WXKB_NTF_CLIPBOARD   "com.yzdmm.wxkbtoolbar10/host/clipboard"
#define WXKB_NTF_PHRASES     "com.yzdmm.wxkbtoolbar10/host/phrases"
#define WXKB_NTF_DISMISS     "com.yzdmm.wxkbtoolbar10/host/dismiss"
#define WXKB_NTF_GLOBE       "com.yzdmm.wxkbtoolbar10/host/globe"

#pragma mark - 宿主侧剪贴板历史 / 快捷短语

static NSMutableArray *gClipHistory = nil;
static const NSUInteger kWXKBMaxClip = 30;

static NSArray *WXKBDefaultPhrases(void) {
    return @[@"好的", @"收到", @"谢谢", @"不客气", @"稍等", @"没问题",
             @"了解", @"OK", @"辛苦了", @"马上处理", @"请稍等"];
}

// 短语存 NSUserDefaults standardDomain（宿主进程自己的沙盒，不跨 App 共享，
// 跟原插件用 jbroot 偏好文件不同 —— 这里刻意简化，避免 RootHide 路径问题）
static NSArray *WXKBLoadPhrases(void) {
    @try {
        NSArray *saved = [[NSUserDefaults standardUserDefaults] objectForKey:@"wxkbHostPhrases"];
        if ([saved isKindOfClass:[NSArray class]] && saved.count) return saved;
    } @catch (__unused NSException *e) {
    }
    return WXKBDefaultPhrases();
}

static void WXKBSavePhrases(NSArray *p) {
    @try {
        [[NSUserDefaults standardUserDefaults] setObject:p forKey:@"wxkbHostPhrases"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } @catch (__unused NSException *e) {
    }
}

static void WXKBInitClipObserver(void) {
    static dispatch_once_t once;
    static id token = nil;
    dispatch_once(&once, ^{
        gClipHistory = [[NSMutableArray alloc] init];
        token = [[NSNotificationCenter defaultCenter]
            addObserverForName:UIPasteboardChangedNotification object:nil
                       queue:[NSOperationQueue mainQueue]
                  usingBlock:^(NSNotification *note) {
            @try {
                NSString *text = [UIPasteboard generalPasteboard].string;
                if (text.length == 0) return;
                if (gClipHistory.count && [gClipHistory.firstObject isEqualToString:text]) return;
                [gClipHistory insertObject:text atIndex:0];
                if (gClipHistory.count > kWXKBMaxClip) [gClipHistory removeLastObject];
            } @catch (__unused NSException *e) {
            }
        }];
        (void)token;
    });
}

#pragma mark - 宿主侧 UI 辅助

static UIWindow *WXKBKeyWindow(void) {
    @try {
        UIApplication *app = [UIApplication sharedApplication];
        NSMutableArray *wins = [NSMutableArray array];
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in app.connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) {
                    [wins addObjectsFromArray:((UIWindowScene *)s).windows];
                }
            }
        }
        if (wins.count == 0) [wins addObjectsFromArray:app.windows];
        for (UIWindow *w in wins) {
            if (w.isKeyWindow) return w;
        }
        return wins.lastObject;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static UIResponder *WXKBFirstResponder(void) {
    @try {
        UIWindow *kw = WXKBKeyWindow();
        return [kw valueForKey:@"firstResponder"];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static UIViewController *WXKBTopViewController(void) {
    @try {
        UIWindow *kw = WXKBKeyWindow();
        UIViewController *vc = kw.rootViewController;
        while (vc.presentedViewController) vc = vc.presentedViewController;
        return vc;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static void WXKBToast(NSString *msg) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIWindow *w = WXKBKeyWindow();
            if (!w) return;
            UILabel *l = [[UILabel alloc] init];
            l.text = msg;
            l.font = [UIFont systemFontOfSize:14];
            l.textColor = [UIColor whiteColor];
            l.textAlignment = NSTextAlignmentCenter;
            l.numberOfLines = 0;
            l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
            l.layer.cornerRadius = 10;
            l.layer.masksToBounds = YES;
            CGFloat pad = 16.0;
            CGSize sz = [l sizeThatFits:CGSizeMake(w.bounds.size.width - 80, CGFLOAT_MAX)];
            l.frame = CGRectMake((w.bounds.size.width - sz.width - pad * 2) / 2,
                                 w.bounds.size.height * 0.35,
                                 sz.width + pad * 2, sz.height + 20);
            [w addSubview:l];
            [UIView animateWithDuration:0.2 animations:^{
                l.alpha = 0;
            } completion:^(BOOL fin) {
                l.alpha = 1;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    [UIView animateWithDuration:0.3 animations:^{
                        l.alpha = 0;
                    } completion:^(BOOL f2) {
                        [l removeFromSuperview];
                    }];
                });
            }];
        } @catch (__unused NSException *e) {
        }
    });
}

#pragma mark - 弹窗：剪贴板历史 / 快捷短语

static void WXKBShowClipboard(void) {
    WXKBInitClipObserver();
    UIViewController *vc = WXKBTopViewController();
    if (!vc) return;
    @try {
        if (gClipHistory.count == 0) {
            UIAlertController *a =
                [UIAlertController alertControllerWithTitle:@"剪贴板历史"
                                                    message:@"暂无复制记录"
                                             preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [vc presentViewController:a animated:YES completion:nil];
            return;
        }
        UIAlertController *a =
            [UIAlertController alertControllerWithTitle:@"剪贴板历史"
                                                message:nil
                                         preferredStyle:UIAlertControllerStyleActionSheet];
        for (id item in gClipHistory) {
            if (![item isKindOfClass:[NSString class]]) continue;
            NSString *d = ((NSString *)item).length > 40
                ? [[(NSString *)item substringToIndex:40] stringByAppendingString:@"…"]
                : item;
            [a addAction:[UIAlertAction actionWithTitle:d style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *act) {
                @try {
                    UIResponder *fr = WXKBFirstResponder();
                    if ([fr conformsToProtocol:@protocol(UITextInput)]) {
                        [UIPasteboard generalPasteboard].string = item;
                        [(id<UITextInput>)fr insertText:item];
                    }
                } @catch (__unused NSException *e) {
                }
            }]];
        }
        [a addAction:[UIAlertAction actionWithTitle:@"清空历史" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *act) {
            [gClipHistory removeAllObjects];
        }]];
        [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [vc presentViewController:a animated:YES completion:nil];
    } @catch (__unused NSException *e) {
    }
}

@interface WXKBPhraseEditor : UITableViewController
@end
@implementation WXKBPhraseEditor {
    NSMutableArray *_phrases;
}
- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _phrases = [WXKBLoadPhrases() mutableCopy];
        self.title = @"快捷短语";
        self.navigationItem.rightBarButtonItem =
            [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                         target:self action:@selector(addPhrase)];
        self.navigationItem.leftBarButtonItem =
            [[UIBarButtonItem alloc] initWithTitle:@"完成" style:UIBarButtonItemStyleDone
                                           target:self action:@selector(done)];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableFooterView = [[UIView alloc] init];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"c"];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return (NSInteger)_phrases.count;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"c" forIndexPath:ip];
    c.textLabel.text = _phrases[(NSUInteger)ip.row];
    c.textLabel.font = [UIFont systemFontOfSize:16];
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    @try {
        NSString *t = _phrases[(NSUInteger)ip.row];
        UIResponder *fr = WXKBFirstResponder();
        if ([fr conformsToProtocol:@protocol(UITextInput)]) {
            [(id<UITextInput>)fr insertText:t];
        }
    } @catch (__unused NSException *e) {
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)st
 forRowAtIndexPath:(NSIndexPath *)ip {
    if (st == UITableViewCellEditingStyleDelete) {
        [_phrases removeObjectAtIndex:(NSUInteger)ip.row];
        WXKBSavePhrases(_phrases);
        [tv deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tv
           editingStyleForRowAtIndexPath:(NSIndexPath *)ip {
    return UITableViewCellEditingStyleDelete;
}
- (void)addPhrase {
    UIAlertController *a =
        [UIAlertController alertControllerWithTitle:@"添加短语" message:nil
                                     preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"短语内容";
        tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"添加" style:UIAlertActionStyleDefault
                                      handler:^(UIAlertAction *act) {
        NSString *t = [[a.textFields.firstObject text]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (t.length) {
            [_phrases addObject:t];
            WXKBSavePhrases(_phrases);
            [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)_phrases.count - 1
                                                                           inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)done {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

static void WXKBShowPhrases(void) {
    UIViewController *vc = WXKBTopViewController();
    if (!vc) return;
    @try {
        WXKBPhraseEditor *ed = [[WXKBPhraseEditor alloc] init];
        UINavigationController *nav =
            [[UINavigationController alloc] initWithRootViewController:ed];
        [vc presentViewController:nav animated:YES completion:nil];
    } @catch (__unused NSException *e) {
    }
}

#pragma mark - 动作实现

static void WXKBRunOnHost(int code) {
    @try {
        switch (code) {
            case WXKB_ACT_SELECT_ALL: {
                [[UIApplication sharedApplication] sendAction:@selector(selectAll:)
                                                            to:nil from:nil forEvent:nil];
                break;
            }
            case WXKB_ACT_CUT: {
                [[UIApplication sharedApplication] sendAction:@selector(cut:)
                                                            to:nil from:nil forEvent:nil];
                break;
            }
            case WXKB_ACT_PASTE: {
                [[UIApplication sharedApplication] sendAction:@selector(paste:)
                                                            to:nil from:nil forEvent:nil];
                break;
            }
            case WXKB_ACT_DELETE_ALL: {
                UIResponder *fr = WXKBFirstResponder();
                if (!fr || ![fr conformsToProtocol:@protocol(UITextInput)]) {
                    WXKBToast(@"请先点进输入框");
                    return;
                }
                id<UITextInput> ti = (id<UITextInput>)fr;
                UITextRange *all = [ti textRangeFromPosition:ti.beginningOfDocument
                                                    toPosition:ti.endOfDocument];
                if (all) [ti replaceRange:all withText:@""];
                break;
            }
            case WXKB_ACT_CLIPBOARD:
                WXKBShowClipboard();
                break;
            case WXKB_ACT_PHRASES:
                WXKBShowPhrases();
                break;
            case WXKB_ACT_DISMISS: {
                [[UIApplication sharedApplication] sendAction:@selector(resignFirstResponder)
                                                            to:nil from:nil forEvent:nil];
                break;
            }
            case WXKB_ACT_GLOBE: {
                // 键盘扩展里切不动时的兜底：走系统键盘的 taskQueue
                Class impl = objc_getClass("UIKeyboardImpl");
                id kb = nil;
                if (impl) {
                    if ([impl respondsToSelector:@selector(activeInstance)])
                        kb = [impl performSelector:@selector(activeInstance)];
                    if (!kb && [impl respondsToSelector:@selector(sharedInstance)])
                        kb = [impl performSelector:@selector(sharedInstance)];
                }
                if (!kb) { WXKBToast(@"无法切换输入法"); return; }
                if ([kb respondsToSelector:@selector(taskQueue)] &&
                    [kb respondsToSelector:@selector(setInputModeToNextInPreferredListWithExecutionContext:)]) {
                    id queue = [kb performSelector:@selector(taskQueue)];
                    if (queue) {
                        void (^blk)(id, int) = ^(id context, int arg2) {
                            @try {
                                [kb performSelector:@selector(setInputModeToNextInPreferredListWithExecutionContext:)
                                          withObject:context];
                            } @catch (__unused NSException *e) {
                            }
                        };
                        [queue performSelector:@selector(addTask:) withObject:blk];
                        return;
                    }
                }
                if ([kb respondsToSelector:@selector(setInputModeToNextInPreferredList)]) {
                    [kb performSelector:@selector(setInputModeToNextInPreferredList)];
                    return;
                }
                WXKBToast(@"无法切换输入法");
                break;
            }
            case WXKB_ACT_CURSOR_LEFT:
            case WXKB_ACT_CURSOR_RIGHT: {
                // 键盘扩展里若 textDocumentProxy 取不到（极少），兜底到宿主移动光标
                UIResponder *fr = WXKBFirstResponder();
                if (!fr || ![fr conformsToProtocol:@protocol(UITextInput)]) {
                    WXKBToast(@"请先点进输入框");
                    break;
                }
                id<UITextInput> ti = (id<UITextInput>)fr;
                UITextPosition *cur = ti.selectedTextRange.start;
                if (!cur) break;
                NSInteger delta = (code == WXKB_ACT_CURSOR_LEFT) ? -1 : 1;
                UITextPosition *np = [ti positionFromPosition:cur offset:delta];
                if (np) {
                    UITextRange *rng = [ti textRangeFromPosition:np toPosition:np];
                    if (rng) [ti setSelectedTextRange:rng];
                }
                break;
            }
            default:
                break;
        }
    } @catch (__unused NSException *e) {
    }
}

#pragma mark - Darwin 通知路由

static void WXKBHostRoute(CFStringRef name) {
    int code = 0;
    if (CFEqual(name, CFSTR(WXKB_NTF_SELECT_ALL)))      code = WXKB_ACT_SELECT_ALL;
    else if (CFEqual(name, CFSTR(WXKB_NTF_CUT)))        code = WXKB_ACT_CUT;
    else if (CFEqual(name, CFSTR(WXKB_NTF_PASTE)))      code = WXKB_ACT_PASTE;
    else if (CFEqual(name, CFSTR(WXKB_NTF_DELETE_ALL))) code = WXKB_ACT_DELETE_ALL;
    else if (CFEqual(name, CFSTR(WXKB_NTF_CLIPBOARD)))  code = WXKB_ACT_CLIPBOARD;
    else if (CFEqual(name, CFSTR(WXKB_NTF_PHRASES)))    code = WXKB_ACT_PHRASES;
    else if (CFEqual(name, CFSTR(WXKB_NTF_DISMISS)))    code = WXKB_ACT_DISMISS;
    else if (CFEqual(name, CFSTR(WXKB_NTF_GLOBE)))      code = WXKB_ACT_GLOBE;
    if (code == 0) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // 后台 App 里不要执行，否则会把一堆后台输入框清空
            if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
                return;
            }
            WXKBRunOnHost(code);
        } @catch (__unused NSException *e) {
        }
    });
}

static void WXKBHostSelectAllCB(CFNotificationCenterRef c, void *o, CFStringRef n,
                                const void *ob, CFDictionaryRef u) {
    WXKBHostRoute(n);
}

#pragma mark - 构造

%ctor {
    @autoreleasepool {
        // 1.6.7：plist 用 Classes=["UIWindow"] 意味着所有带界面的进程都会加载本
        // dylib（ElleKit 无 Exclude 键、Executables 不支持通配符，见 plist 注释），
        // 这里运行时把不该工作的进程排除掉：
        //   - SpringBoard：系统界面，绝不能碰；
        //   - 键盘扩展自身（wxkb_plugin）：Darwin 通知会广播回自己，避免它对
        //     WeType 内部视图执行编辑动作；
        //   - 无主 bundle 的守护进程：没有 UI，无意义。
        @try {
            NSString *bid = nil;
            CFBundleRef mb = CFBundleGetMainBundle();
            if (mb) {
                CFStringRef i = CFBundleGetIdentifier(mb);
                if (i) bid = [(__bridge NSString *)i copy];
            }
            if (!bid) return;
            if ([bid isEqualToString:@"com.apple.springboard"]) return;
            if ([bid isEqualToString:@"com.tencent.wetype.keyboard"]) return;
        } @catch (__unused NSException *e) {
            return;
        }

        WXKBInitClipObserver();
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            WXKBHostSelectAllCB, CFSTR(WXKB_NTF_SELECT_ALL), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            WXKBHostSelectAllCB, CFSTR(WXKB_NTF_CUT), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            WXKBHostSelectAllCB, CFSTR(WXKB_NTF_PASTE), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            WXKBHostSelectAllCB, CFSTR(WXKB_NTF_DELETE_ALL), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            WXKBHostSelectAllCB, CFSTR(WXKB_NTF_CLIPBOARD), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            WXKBHostSelectAllCB, CFSTR(WXKB_NTF_PHRASES), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            WXKBHostSelectAllCB, CFSTR(WXKB_NTF_DISMISS), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            WXKBHostSelectAllCB, CFSTR(WXKB_NTF_GLOBE), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}