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

static NSString *__attribute__((noinline)) _UD(void) {
    static NSString *uid = nil;
    static dispatch_once_t o;
    dispatch_once(&o, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/"
                         "MobileKeyBag.framework/MobileKeyBag", RTLD_LAZY);
        if (h) {
            NSString *(*mg)(NSString *) = dlsym(h, "MGCopyAnswer");
            if (mg) uid = mg(@"UniqueDeviceID");
        }
        if (!uid) {
            id dev = [UIDevice currentDevice];
            SEL s = NSSelectorFromString(@"uniqueIdentifier");
            if ([dev respondsToSelector:s]) {
                IMP imp = [dev methodForSelector:s];
                uid = ((id (*)(id, SEL))imp)(dev, s);
            }
        }
        if (!uid) uid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
        if (!uid) uid = @"unknown";
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

static NSString *__suite(void) { return @"com.yzdmm.wxkbtoolbar10.license"; }

// roothide 的 jbroot：从本文件编译进的 dylib/bundle 路径反推（…/.jbroot-XXXX/usr/lib/TweakInject/…）。
// 关键：键盘扩展是沙盒进程，直接读 /var/mobile/… 会被沙盒挡掉，而 /var/jb/… 在 roothide 下
// 并不以这个名字存在 —— 于是键盘里读不到解锁文件，lk_master_verify 返回未授权，
// 导致整个插件在「真实键盘」上被 WXKBIsLicensed() 闸刀静默关掉（面板预览却正常）。
// 反推 jbroot 前缀后，键盘经 jbroot 挂载点能读到真实 /var/mobile/… 文件，授权才通过。
// 面板（PreferenceBundle）的 dylib 路径不含 /usr/lib/TweakInject，jb 为 nil，自动回退原逻辑，不受影响。
static NSString *__jbroot(void) {
    static NSString *jb = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info info;
        if (dladdr((const void *)&__jbroot, &info) && info.dli_fname) {
            NSString *p = [NSString stringWithUTF8String:info.dli_fname];
            NSRange r = [p rangeOfString:@"/usr/lib/TweakInject"];
            if (r.location != NSNotFound) {
                jb = [p substringToIndex:r.location];
            }
        }
    });
    return jb;
}

static NSString *__licFile(void) {
    NSString *jb = __jbroot();
    NSMutableArray *cands = [NSMutableArray array];
    if (jb.length) {
        [cands addObject:[jb stringByAppendingString:
            @"/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.license.plist"]];
    }
    [cands addObjectsFromArray:@[
        @"/var/jb/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.license.plist",
        @"/var/mobile/Library/Preferences/com.yzdmm.wxkbtoolbar10.license.plist",
    ]];
    for (NSString *p in cands) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    }
    return cands.lastObject;
}

static int my_store_read(int slot, char *buf, int cap) {
    if (!buf || cap <= 0) return -1;
    buf[0] = 0;
    NSString *val = nil;
    if (slot == LK_SLOT_FILE) {
        val = [NSString stringWithContentsOfFile:__licFile() encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSUserDefaults *d = [[NSUserDefaults alloc] initWithSuiteName:__suite()];
        val = [d objectForKey:[NSString stringWithFormat:@"lk_slot_%d", slot]];
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
