/* ============================================================
 * lk_env_ios.m —— WxkbToolbar10 的 license_kit 适配层
 *
 * device_id : 本机 UDID，与母本 locsim_gen 签发时同源（MGCopyAnswer UniqueDeviceID）。
 *             2.4.26：强来源（设置面板，未沙盒）算出后写入共享域缓存，
 *             键盘扩展（沙盒，拿不到 UniqueDeviceID）读缓存对齐，
 *             否则解锁码 HMAC(pid|udid|exp) 在键盘侧校验必炸。
 * store_*   : 跨进程共享存储——设置面板（解锁时）写，键盘扩展（运行时）读。
 *             2.4.26 双通道：cfprefsd 共享域 + 微信键盘容器内 plist 直写，
 *             读端两条都试，哪条通走哪条。
 * ============================================================ */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <string.h>
#import <CoreFoundation/CoreFoundation.h>
#import "lk.h"

#pragma mark - 跨进程共享通道（cfprefsd 域 + 容器 plist 直写直读）

// 共享域 = 微信键盘扩展自己的 bundle id。键盘扩展沙盒内读不到真实
// /var/mobile/Library/Preferences，但能经 cfprefsd 读写自己的域；设置面板
// （未沙盒）可写任意域，故两端走同一域即可互通授权状态。
static NSString *__domain(void) { return @"com.tencent.wetype.keyboard"; }

// 权威 UDID 在共享域里的键名
static NSString *WXKB_UDID_KEY(void) { return @"wxkb_device_udid"; }

static NSString *__slotKey(int slot) {
    return [NSString stringWithFormat:@"wxkb_lic_%d", slot];
}

static NSString *__domainPlistName(void) {
    return [__domain() stringByAppendingString:@".plist"];
}

/* ---- 微信键盘（宿主 App）数据容器定位 ----
 * cfprefsd 对沙盒客户端只开放其「容器内」的域文件；设置面板经 CFPreferences
 * 写的是 /var/mobile/Library/Preferences/<domain>.plist，键盘扩展的 cfprefsd
 * 视图未必命中同一份文件。把关键键值再合并直写一份到 WeType 容器的
 * <...>/Library/Preferences/<domain>.plist，键盘侧（沙盒至少能读自己容器）
 * 直读该文件即可拿到。沙盒进程扫描不了 /var/mobile/Containers，扫描失败
 * 自然得到空列表，写端自动退化为 no-op，读端则用 NSHomeDirectory 定位。 */
static NSArray<NSString *> *_wetypeContainerPrefsDirs(void) {
    static NSArray *dirs = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = @"/var/mobile/Containers/Data/Application";
        NSArray *ids = [fm contentsOfDirectoryAtPath:root error:nil];
        if (!ids.count) return;   // 沙盒进程：扫描被拒 → 空
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *cid in ids) {
            NSString *dir = [root stringByAppendingPathComponent:cid];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:
                [dir stringByAppendingPathComponent:
                     @".com.apple.mobile_container_manager.metadata.plist"]];
            NSString *ident = meta[@"MCMMetadataIdentifier"];
            if (![ident isKindOfClass:[NSString class]]) continue;
            /* 覆盖 WeType App 本体与键盘扩展各自的容器 */
            if (![ident hasPrefix:@"com.tencent.wetype"]) continue;
            NSString *pd = [dir stringByAppendingPathComponent:@"Library/Preferences"];
            if ([fm fileExistsAtPath:pd]) [out addObject:pd];
        }
        dirs = out;
    });
    return dirs;
}

/* 任意进程：自己容器里的共享域 plist 全路径（读端用） */
static NSString *_wxkbHomePrefFile(void) {
    NSString *home = NSHomeDirectory();
    if (!home.length) return nil;
    return [home stringByAppendingPathComponent:
            [@"Library/Preferences/" stringByAppendingString:__domainPlistName()]];
}

/* 设置侧直写：把 key/value 合并写进 WeType 容器的域 plist（value=nil 删除键）。
 * 只在未沙盒进程里真正生效；键盘侧调用是 no-op（扫描不到容器）。 */
void wxkb_shared_sync(NSString *key, id value) {
    if (!key.length) return;
    for (NSString *dir in _wetypeContainerPrefsDirs()) {
        NSString *path = [dir stringByAppendingPathComponent:__domainPlistName()];
        NSMutableDictionary *d = [[NSMutableDictionary alloc]
                                  initWithContentsOfFile:path];
        if (![d isKindOfClass:[NSMutableDictionary class]]) {
            d = [NSMutableDictionary dictionary];
        }
        if (value) d[key] = value;
        else       [d removeObjectForKey:key];
        if (!d.count && ![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        NSData *data = [NSPropertyListSerialization
                        dataWithPropertyList:d
                        format:NSPropertyListBinaryFormat_v1_0
                        options:0 error:nil];
        if (data) [data writeToFile:path atomically:YES];
    }
}

/* 读端兜底：直接读自己容器里的域 plist 的某个键 */
id wxkb_shared_read(NSString *key) {
    if (!key.length) return nil;
    NSString *path = _wxkbHomePrefFile();
    if (!path.length) return nil;
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    return d[key];
}

/* 键盘侧自写探针：把键值合并写进【自己容器】的域 plist。
 * 设置面板（未沙盒）扫描容器后直读这份文件，从而验证「容器直写通道」
 * 从键盘 → 设置方向是否可通（cfprefsd 反向对沙盒写端不可靠）。 */
void wxkb_self_sync(NSString *key, id value) {
    if (!key.length) return;
    NSString *path = _wxkbHomePrefFile();
    if (!path.length) return;
    @try {
        NSMutableDictionary *d = [[NSMutableDictionary alloc]
                                  initWithContentsOfFile:path];
        if (![d isKindOfClass:[NSMutableDictionary class]]) {
            d = [NSMutableDictionary dictionary];
        }
        if (value) d[key] = value;
        else       [d removeObjectForKey:key];
        NSData *data = [NSPropertyListSerialization
                        dataWithPropertyList:d
                        format:NSPropertyListBinaryFormat_v1_0
                        options:0 error:nil];
        if (data) [data writeToFile:path atomically:YES];
    } @catch (NSException *e) { }
}

/* 设置侧诊断：从所有通道读同一个键，返回 "通道=值" 拼接串。
 * 通道：cfprefsd 共享域 / 扫描到的 WeType 容器 plist / 设置进程自己 home。 */
NSString *wxkb_diag_read(NSString *key) {
    if (!key.length) return @"(no key)";
    NSMutableArray *parts = [NSMutableArray array];

    CFPropertyListRef v = CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)__domain(),
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) {
        if (CFGetTypeID(v) == CFStringGetTypeID())
            [parts addObject:[NSString stringWithFormat:@"cfprefsd=%@",
                              (__bridge NSString *)v]];
        else
            [parts addObject:@"cfprefsd=(type?)"];
        CFRelease(v);
    } else {
        [parts addObject:@"cfprefsd=(nil)"];
    }

    for (NSString *dir in _wetypeContainerPrefsDirs()) {
        NSString *path = [dir stringByAppendingPathComponent:__domainPlistName()];
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
        id val = [d isKindOfClass:[NSDictionary class]] ? d[key] : nil;
        NSString *tag = [dir stringByDeletingLastPathComponent];
        tag = [tag stringByDeletingLastPathComponent];   // .../Library
        tag = [tag lastPathComponent];                   // 容器 UUID 末段
        if (tag.length > 8) tag = [tag substringFromIndex:tag.length - 8];
        [parts addObject:[NSString stringWithFormat:@"C…%@=%@", tag,
                          val ?: @"(nil)"]];
    }
    return [parts componentsJoinedByString:@" | "];
}

#pragma mark - UDID（与母本 locsim_gen 同源）

static NSString *__attribute__((noinline)) _UD(void) {
    static NSString *uid = nil;
    static dispatch_once_t o;
    dispatch_once(&o, ^{
        // 1) 强来源：MGCopyAnswer / uniqueIdentifier —— 只有未沙盒进程能走通
        NSString *strong = nil;
        void *h = dlopen("/System/Library/PrivateFrameworks/"
                         "MobileKeyBag.framework/MobileKeyBag", RTLD_LAZY);
        if (h) {
            NSString *(*mg)(NSString *) = dlsym(h, "MGCopyAnswer");
            if (mg) strong = mg(@"UniqueDeviceID");
        }
        if (!strong.length) {
            id dev = [UIDevice currentDevice];
            SEL s = NSSelectorFromString(@"uniqueIdentifier");
            if ([dev respondsToSelector:s]) {
                IMP imp = [dev methodForSelector:s];
                strong = ((id (*)(id, SEL))imp)(dev, s);
            }
        }
        if (strong.length) {
            /* 只有未沙盒进程（设置面板，HOME=/var/mobile）才有资格当「权威」：
             * 万一沙盒键盘也能骗到某个 UniqueDeviceID，也不能让它覆盖缓存。 */
            BOOL unsandboxed = [NSHomeDirectory() isEqualToString:@"/var/mobile"];
            if (unsandboxed) {
                uid = strong;
                /* 权威 UDID 落进共享域：cfprefsd + 容器 plist 双写。
                 * 键盘扩展拿不到 UniqueDeviceID，靠读这份缓存与本机对齐。 */
                CFPreferencesSetValue(
                    (__bridge CFStringRef)WXKB_UDID_KEY(),
                    (__bridge CFPropertyListRef)uid,
                    (__bridge CFStringRef)__domain(),
                    kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
                CFPreferencesSynchronize((__bridge CFStringRef)__domain(),
                                         kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
                wxkb_shared_sync(WXKB_UDID_KEY(), uid);
                return;
            }
        }
        // 2) 共享域缓存（cfprefsd）
        CFPropertyListRef cv = CFPreferencesCopyValue(
            (__bridge CFStringRef)WXKB_UDID_KEY(),
            (__bridge CFStringRef)__domain(),
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (cv) {
            if (CFGetTypeID(cv) == CFStringGetTypeID())
                uid = (__bridge_transfer NSString *)cv;
            else
                CFRelease(cv);
        }
        // 3) 容器 plist 直读兜底（cfprefsd 视图未同步时）
        if (!uid.length) {
            id fv = wxkb_shared_read(WXKB_UDID_KEY());
            if ([fv isKindOfClass:[NSString class]]) uid = fv;
        }
        // 4) 弱来源兜底：IFV / unknown（仅当缓存尚未建立；设置面板一打开
        //    缓存即建立，之后键盘侧永远与设置侧同值）
        if (!uid.length) {
            uid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        }
        if (!uid.length) uid = @"unknown";
    });
    return uid;
}

static int my_device_id(char *buf, int cap) {
    NSString *ud = _UD();
    if (!ud || !ud.length) return -1;
    const char *c = [ud UTF8String];
    int n = (int)strlen(c);
    if (n >= cap) n = cap - 1;
    memcpy(buf, c, (size_t)n);
    buf[n] = 0;
    return n;
}

#pragma mark - 跨进程共享存储

static int my_store_read(int slot, char *buf, int cap) {
    if (!buf || cap <= 0) return -1;
    buf[0] = 0;
    NSString *key = __slotKey(slot);
    NSString *val = nil;

    /* 通道 1：cfprefsd 共享域 */
    CFPropertyListRef v = CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)__domain(),
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (v) {
        if (CFGetTypeID(v) == CFStringGetTypeID())
            val = (__bridge_transfer NSString *)v;
        else
            CFRelease(v);
    }

    /* 通道 2：容器 plist 直读（cfprefsd 视图未同步 / 键盘沙盒兜底） */
    if (!val.length) {
        id fv = wxkb_shared_read(key);
        if ([fv isKindOfClass:[NSString class]]) val = fv;
    }

    if (!val.length) return -1;
    int n = (int)[val lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (n >= cap) n = cap - 1;
    memcpy(buf, [val UTF8String], (size_t)n);
    buf[n] = 0;
    return n;
}

static int my_store_write(int slot, const char *blob) {
    NSString *s = blob ? [NSString stringWithUTF8String:blob] : @"";
    NSString *key = __slotKey(slot);
    CFStringRef domain = (__bridge CFStringRef)__domain();
    CFPreferencesSetValue(
        (__bridge CFStringRef)key,
        (__bridge CFPropertyListRef)s,
        domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    /* 双通道：同步直写进 WeType 容器 plist（未沙盒进程才真正生效） */
    wxkb_shared_sync(key, s);
    return 0;
}

#pragma mark - 环境（静态单例）

static const lk_env g_env = {
    .store_read   = my_store_read,
    .store_write  = my_store_write,
    .device_id    = my_device_id,
    .now          = NULL,
    .trusted_time = NULL,
    .ecdsa_verify = NULL,
    .reputation   = lk_reputation_default,
};

const lk_env *lk_get_env(void) { return &g_env; }

#pragma mark - 原因码 → 中文（面板展示用）

const char *lk_reason_cstr(lk_reason r) {
    switch (r) {
        case LK_R_NONE:           return "OK";
        case LK_R_NO_ENV:         return "缺少适配层回调";
        case LK_R_NO_UDID:        return "取不到设备 UDID";
        case LK_R_ENV_SUSPECT:    return "运行环境异常（完整性/反调试）";
        case LK_R_STATE_TAMPERED: return "状态存储被篡改";
        case LK_R_CLOCK_ROLLBACK: return "系统时间被回拨";
        case LK_R_CLOCK_EARLY:    return "系统时间过早";
        case LK_R_EMPTY_INPUT:    return "未输入";
        case LK_R_NOT_UNLOCKED:   return "尚未解锁（母本不在或未安装正版）";
        case LK_R_BAD_CODE:       return "解锁码无效";
        case LK_R_STATE_BAD:      return "状态里的码已失效";
        case LK_R_EXPIRED:        return "已过期";
        default:                  return "未知原因";
    }
}
