/* ============================================================
 * lk_env_ios.m —— WxkbToolbar10 的 license_kit 适配层
 *
 * device_id : 本机 UDID，与母本 locsim_gen 签发时同源（MGCopyAnswer UniqueDeviceID）。
 * store_*   : 跨进程共享存储——设置面板（解锁时）写，键盘扩展（运行时）读。
 *             路径走 /var/mobile/Library/Preferences/（jbroot 优先），
 *             两个进程都能读；键盘只读取，不依赖 NSUserDefaults 跨进程同步。
 * ============================================================ */
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <string.h>
#import "lk.h"

#pragma mark - UDID（与母本 locsim_gen 同源）

/* 跨进程共享 UDID 缓存文件：解锁时（设置面板进程，MGCopyAnswer 能拿到真 UDID）把真 UDID
 * 落盘；键盘扩展等 MGCopyAnswer 取不到真 UDID 的进程直接读这份缓存，保证「签码用的 UDID」
 * 与「运行时验签用的 UDID」是同一个。
 *
 * 为什么必须有它：解锁码是用「解锁那一刻 device_id 拿到的 UDID」签的；但运行时（尤其键盘
 * 扩展沙盒，以及切后台回前台后的面板）MGCopyAnswer 往往取不到真 UDID、回退成 "unknown"，
 * 于是运行时拿 "unknown" 去验「绑了真 UDID 的码」→ 验签失败 → lk_peek 返回 LK_LOCKED →
 * 整插件被误判未授权。表现正是用户报的两个 bug：键帽/形状在键盘上不生效（WXKBApplyCorner
 * 被门禁跳过）、切后台回面板整张表置灰且只能点「解锁」按钮。
 * 落盘缓存让所有进程都复用签码时的那个真 UDID，从根上消除跨进程/跨时刻的 UDID 不一致。 */
// 与 Tweak.xm 的 WXKBJbrootPath 同源：从本 dylib 路径反推 jbroot 前缀。
// 键盘扩展沙盒只能可靠读 jbroot 下的真实路径（frida 实测），license/udid 这类
// 共享文件也必须走 jbroot 路径，否则键盘进程读不到面板写的解锁码 / 真 UDID。
static NSString *__wxkbJbroot(void) {
    static NSString *jb = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info;
        if (dladdr((const void *)&__wxkbJbroot, &info) && info.dli_fname) {
            NSString *p = [NSString stringWithUTF8String:info.dli_fname];
            NSRange r = [p rangeOfString:@"/usr/lib/TweakInject"];
            if (r.location != NSNotFound) jb = [p substringToIndex:r.location];
        }
    });
    return jb;
}

static NSString *__udidCacheFile(void) {
    NSString *jb = __wxkbJbroot();
    NSMutableArray *cands = [NSMutableArray array];
    if (jb.length) [cands addObject:[jb stringByAppendingString:
        @"/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.udid"]];
    [cands addObjectsFromArray:@[
        @"/var/jb/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.udid",
        @"/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.udid",
    ]];
    for (NSString *p in cands) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    }
    return cands.lastObject;
}

// 跨进程 UDID 共享：与 WXKB_PREFS_DOMAIN（com.yzdmm.wxkbtoolbar10）同源，且复用
// Tweak 里 WXKBLoadPrefs 已验证的 CFPreferences 通道（走 cfprefsd 守护——设置项正是
// 经它实时下发到键盘扩展的）。解锁时（面板，MGCopyAnswer 能拿真 UDID）把真 UDID 写进此域；
// 键盘扩展等 MGCopyAnswer 取不到真 UDID 的进程，直接读此域拿到「签码时用的同一个 UDID」，
// 于是 lk_peek 用同一 UDID 重验通过 → 扩展不再被误判未授权 → 键帽/形状等真正生效（Bug A）。
// 关键：必须用 CFPreferences（而非 initWithSuiteName:）——沙盒键盘扩展里后者读不到面板写的值，
// 这正是 2.5.15 之后键帽仍不生效的根因。
static NSString *const __wxkbUDIDKey    = @"wxkb_device_udid";
static NSString *const __wxkbUDIDDomain = @"com.yzdmm.wxkbtoolbar10";

// 经 cfprefsd 读偏好字符串（与 WXKBLoadPrefs 同源通道，跨进程最稳）
static NSString *__wxkbReadPrefString(NSString *domain, NSString *key) {
    CFStringRef dom = (__bridge CFStringRef)domain;
    CFStringRef k   = (__bridge CFStringRef)key;
    CFPropertyListRef v = CFPreferencesCopyValue(k, dom,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!v) v = CFPreferencesCopyValue(k, dom,
        kCFPreferencesAnyUser, kCFPreferencesAnyHost);
    NSString *s = nil;
    if (v) {
        if (CFGetTypeID(v) == CFStringGetTypeID()) s = (__bridge NSString *)v;
        CFRelease(v);
    }
    return s;
}

// 经 cfprefsd 写偏好字符串并立即同步（让键盘扩展立刻可见）
static void __wxkbWritePrefString(NSString *domain, NSString *key, NSString *val) {
    CFStringRef dom = (__bridge CFStringRef)domain;
    CFStringRef k   = (__bridge CFStringRef)key;
    CFPreferencesSetValue(k, (__bridge CFPropertyListRef)val, dom,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize(dom, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static void _wxkbCacheUDID(NSString *udid) {
    if (!udid.length || [udid isEqualToString:@"unknown"]) return;
    // 主通道：CFPreferences 共享域（与设置下发同通道，键盘扩展必能读到）
    __wxkbWritePrefString(__wxkbUDIDDomain, __wxkbUDIDKey, udid);
    // 备用：落盘文件（jbroot 优先），兼容旧版缓存 / 极端环境
    [udid writeToFile:__udidCacheFile() atomically:NO encoding:NSUTF8StringEncoding error:nil];
}

// 读跨进程共享 UDID：优先 CFPreferences 共享域，其次落盘文件。键盘扩展据此拿到与签码一致的 UDID。
static NSString *__wxkbReadCachedUDID(void) {
    NSString *u = __wxkbReadPrefString(__wxkbUDIDDomain, __wxkbUDIDKey);
    if (u.length && ![u isEqualToString:@"unknown"]) return u;
    NSString *f = [NSString stringWithContentsOfFile:__udidCacheFile()
                                           encoding:NSUTF8StringEncoding error:nil];
    if (f.length && ![f isEqualToString:@"unknown"]) return f;
    return nil;
}

static NSString *__realUDID = nil;     // 本进程经 MGCopyAnswer 拿到的真 UDID（仅成功后才缓存）

// 取本进程真 UDID。**只在成功时缓存**；失败不缓存、下次调用再试（不永久锁定为兜底值）。
// 之前的版本用 __realUDIDTried 永久锁：一旦首次 MGCopyAnswer 因 dlopen 时序返回 nil，
// 就永远回退成 identifierForVendor，与「解锁时绑定的真 UDID」不一致 → lk_peek 验签失败
// → 面板被误判未授权 → 整表除「解锁」外全部禁用（正是「只能点一个按钮」的根因）。
static NSString *__attribute__((noinline)) _wxkbRealUDID(void) {
    if (__realUDID) return __realUDID;   // 已成功拿到，直接返回
    void *h = dlopen("/System/Library/PrivateFrameworks/"
                     "MobileKeyBag.framework/MobileKeyBag", RTLD_LAZY);
    if (h) {
        NSString *(*mg)(NSString *) = dlsym(h, "MGCopyAnswer");
        if (mg) {
            NSString *u = mg(@"UniqueDeviceID");
            if (u.length && ![u isEqualToString:@"unknown"]) {
                __realUDID = u;
                _wxkbCacheUDID(u);   // 落盘 + CFPreferences，供键盘扩展复用（Bug A 修复）
                return u;
            }
        }
    }
    return nil;   // 失败：让调用方回退到共享 UDID / 兜底，且下次重试（不会永久锁死）
}

static NSString *__attribute__((noinline)) _wxkbFallbackUDID(void) {
    NSString *ud = nil;
    id dev = [UIDevice currentDevice];
    SEL s = NSSelectorFromString(@"uniqueIdentifier");
    if ([dev respondsToSelector:s]) {
        IMP imp = [dev methodForSelector:s];
        ud = ((id (*)(id, SEL))imp)(dev, s);
    }
    if (!ud) ud = [[dev identifierForVendor] UUIDString];
    if (!ud) ud = @"unknown";
    return ud;
}

static int my_device_id(char *buf, int cap) {
    NSString *ud = nil;
    int src = 0;                                  // 1=本进程真值 2=跨进程共享 3=兜底
    NSString *real = _wxkbRealUDID();            // 优先：本进程能拿到真 UDID（设置面板）
    if (real.length) { ud = real; src = 1; }
    if (!ud) {                                    // 拿不到：读跨进程共享 UDID（签码时的真 UDID）
        ud = __wxkbReadCachedUDID();
        if (!ud.length || [ud isEqualToString:@"unknown"]) ud = nil;
        else src = 2;
    }
    if (!ud) { ud = _wxkbFallbackUDID(); src = 3; }  // 仍没有：identifierForVendor / unknown
    if (!ud || !ud.length) ud = @"unknown";
    // 诊断日志（无 PII，只报来源与是否退化成 unknown，便于定位键盘扩展读不到真 UDID）
    NSLog(@"[WXKB-lic] device_id src=%d isUnknown=%d",
          src, [ud isEqualToString:@"unknown"] ? 1 : 0);
    const char *c = [ud UTF8String];
    int n = (int)strlen(c);
    if (n >= cap) n = cap - 1;
    memcpy(buf, c, (size_t)n);
    buf[n] = 0;
    return n;
}

#pragma mark - 跨进程共享存储

static NSString *__suite(void) { return @"com.yzdmm.wxkbtoolbar10.license"; }

static NSString *__licFile(void) {
    NSString *jb = __wxkbJbroot();
    NSMutableArray *cands = [NSMutableArray array];
    if (jb.length) [cands addObject:[jb stringByAppendingString:
        @"/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.license.plist"]];
    [cands addObjectsFromArray:@[
        @"/var/jb/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.license.plist",
        @"/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.license.plist",
    ]];
    for (NSString *p in cands) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    }
    return cands.lastObject;
}

// 授权状态存储：回退到 2.5.14 原版实现（NSUserDefaults 共享域 + 文件兜底），不引入 CFPreferences
// 干预 license 通道——避免任何与旧版存储不兼容导致「面板自己读不到已存解锁码 → 误锁」。
// 跨进程 UDID 共享仍走独立的 [WXKB_PREFS_DOMAIN] 通道（见上方 _wxkbCacheUDID），与此处无关。
static int my_store_read(int slot, char *buf, int cap) {
    if (!buf || cap <= 0) return -1;
    buf[0] = 0;
    NSString *val = nil;
    if (slot == LK_SLOT_FILE) {
        val = [NSString stringWithContentsOfFile:__licFile() encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:__suite()];
        val = d ? [d objectForKey:[NSString stringWithFormat:@"lk_slot_%d", slot]] : nil;
    }
    if (!val || ![val isKindOfClass:[NSString class]] || !val.length) return -1;
    int n = (int)[val lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (n >= cap) n = cap - 1;
    memcpy(buf, [val UTF8String], (size_t)n);
    buf[n] = 0;
    return n;
}

static int my_store_write(int slot, const char *blob) {
    NSString *s = blob ? [NSString stringWithUTF8String:blob] : @"";
    if (slot == LK_SLOT_FILE) {
        [s writeToFile:__licFile() atomically:NO encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:__suite()];
        if (blob) [d setObject:s forKey:[NSString stringWithFormat:@"lk_slot_%d", slot]];
        else      [d removeObjectForKey:[NSString stringWithFormat:@"lk_slot_%d", slot]];
        [d synchronize];
    }
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
