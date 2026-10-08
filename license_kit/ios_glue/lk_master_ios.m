/* ============================================================
 * license_kit · 母本 IPA 解锁 —— iOS 读取器（适配层，仅编入 dylib / 注入体）
 *
 * 作用：实现 lk_master_hash_fn 回调 —— 在设备上找到正版母本生成器
 * （com.locsim.generator），读它二进制里的 __TEXT,__text 段，算 SHA256 返回给
 * 核心比对。校验的是代码段而非 plist token（详见 加密混淆.md）：
 *   重签只改 __LINKEDIT，__TEXT,__text 字节不变 → 哈希稳定；
 *   同名空壳 App 无法复现 → 伪造失效；且完全不碰母本 IPA。
 *
 * 为什么单独成文件：
 *   - 核心（lk_master.c）是纯 C，可在 PC 上跑 KAT；这里用 Objective-C +
 *     私有 API（LSApplicationWorkspace）与 Mach-O 解析，只能编进 iOS 构建。
 *   - dylib 初始化时调用一次 lk_master_install_ios() 即可把读取器装上去；
 *     LK_MASTER_UNLOCK=0 时核心根本不会调用，装了也无副作用。
 *
 * 反逆向考量（呼应 加密混淆.md）：
 *   - 不引 LSApplicationServices 头，全程 NSClassFromString / performSelector，
 *     静态链接表里不出现 LSApplicationWorkspace 符号。
 *   - bundle id 由核心解密后传入，这里不写死明文。
 *   - SHA256 直接复用内核算法 lk_sha256，不引入新依赖。
 * ============================================================ */
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <string.h>
#import "lk.h"

#if !defined(__APPLE__)
/* 非 Apple 平台编译时（理论不会，因为只编入 iOS 构建）给个桩，避免链接错误 */
int lk_master_hash_fn_ios(const char *bundle_id, uint8_t *out32, int cap) {
    (void)bundle_id; (void)out32; (void)cap; return -1;
}
void lk_master_install_ios(void) {}
#else

/* 用 objc_msgSend 直发，避开 performSelector 的 ARC 内存语义警告 */
static id _call(id obj, SEL sel) {
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

/* ---------- Mach-O 解析：定位 __TEXT,__text 的 (文件偏移, 长度) ---------- */
static uint32_t _r32(const unsigned char *p, int le) {
    if (le) return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}
static uint64_t _r64(const unsigned char *p, int le) {
    uint64_t v = 0;
    if (le) { for (int i = 7; i >= 0; i--) v = (v << 8) | p[i]; }
    else    { for (int i = 0; i < 8; i++) v = (v << 8) | p[i]; }
    return v;
}

/* 在 buf[0,len) 中找 __TEXT,__text，成功填 *out_off/*out_size（相对 buf 起点）返回 1。
 * 支持单 arch arm64 与 fat/universal（挑第一个 arm64 切片）。 */
static int _find_text(const unsigned char *buf, size_t len,
                      uint32_t *out_off, uint32_t *out_size) {
    if (len < 4) return 0;
    uint32_t m0 = _r32(buf, 1), m1 = _r32(buf, 0);
    int le = -1;
    static const uint32_t magics[] = {0xfeedfacf, 0xcffaedfe, 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca};
    for (int k = 0; k < 6; k++) {
        if (m0 == magics[k]) { le = 1; break; }
        if (m1 == magics[k]) { le = 0; break; }
    }
    if (le < 0) return 0;

    uint32_t mag = _r32(buf, le);
    if (mag == 0xcafebabe || mag == 0xcafebabf) {            /* fat / universal */
        int is64 = (mag == 0xcafebabf);
        uint32_t nfat = _r32(buf + 4, le);
        for (uint32_t i = 0; i < nfat; i++) {
            uint32_t base = 8 + i * (is64 ? 32 : 20);
            if (base + (is64 ? 32 : 20) > len) break;
            uint32_t cputype = _r32(buf + base, le);
            uint64_t off, size;
            if (is64) { off = _r64(buf + base + 8, le); size = _r64(buf + base + 16, le); }
            else      { off = _r32(buf + base + 8, le); size = _r32(buf + base + 12, le); }
            if (cputype == 0x0100000C && off + size <= len) { /* CPU_TYPE_ARM64 */
                if (_find_text(buf + off, (size_t)size, out_off, out_size)) return 1;
            }
        }
        return 0;
    }
    if (mag == 0xfeedfacf || mag == 0xcffaedfe) {             /* thin 64-bit */
        uint32_t ncmds = _r32(buf + 16, le);
        uint32_t off = 32;
        for (uint32_t c = 0; c < ncmds; c++) {
            if (off + 8 > len) break;
            uint32_t cmd = _r32(buf + off, le);
            uint32_t cmdsize = _r32(buf + off + 4, le);
            if (cmd == 0x19) {                                /* LC_SEGMENT_64 */
                char seg[17]; memcpy(seg, buf + off + 8, 16); seg[16] = 0;
                uint32_t nsects = _r32(buf + off + 64, le);
                uint32_t sb = off + 72;
                for (uint32_t s = 0; s < nsects; s++) {
                    uint32_t so = sb + s * 80;
                    if (so + 80 > len) break;
                    char sname[17], sseg[17];
                    memcpy(sname, buf + so, 16);       sname[16] = 0;
                    memcpy(sseg,  buf + so + 16, 16);   sseg[16]  = 0;
                    uint64_t size = _r64(buf + so + 40, le);
                    uint32_t foff = _r32(buf + so + 48, le);
                    if (strcmp(sseg, "__TEXT") == 0 && strcmp(sname, "__text") == 0) {
                        *out_off = foff; *out_size = (uint32_t)size; return 1;
                    }
                }
            }
            if (cmdsize == 0) break;
            off += cmdsize;
        }
    }
    return 0;
}

int lk_master_hash_fn_ios(const char *bundle_id, uint8_t *out32, int cap) {
    if (!bundle_id || !out32 || cap < 32) return -1;
    memset(out32, 0, (size_t)(cap > 32 ? 32 : cap));

    NSString *target = [NSString stringWithUTF8String:bundle_id];
    if (!target.length) return -1;

    Class LSA = NSClassFromString(@"LSApplicationWorkspace");
    if (!LSA) return -1;
    id ws = _call(LSA, NSSelectorFromString(@"defaultWorkspace"));
    if (!ws) return -1;

    NSArray *apps = _call(ws, NSSelectorFromString(@"allApplications"));
    if (![apps isKindOfClass:[NSArray class]]) return -1;

    for (id proxy in apps) {
        NSString *bid = _call(proxy, NSSelectorFromString(@"applicationIdentifier"));
        if (![bid isKindOfClass:[NSString class]] || ![bid isEqualToString:target])
            continue;

        NSURL *url = _call(proxy, NSSelectorFromString(@"bundleURL"));
        if (![url isKindOfClass:[NSURL class]]) continue;
        NSBundle *b = [NSBundle bundleWithURL:url];
        if (!b) continue;

        NSString *execPath = [b executablePath];
        if (!execPath) {
            NSString *en = b.infoDictionary[@"CFBundleExecutable"];
            if (!en) continue;
            execPath = [[url path] stringByAppendingPathComponent:en];
        }
        if (!execPath.length) continue;

        NSData *d = [NSData dataWithContentsOfFile:execPath];
        if (!d || [d length] < 4) continue;
        const unsigned char *buf = (const unsigned char *)[d bytes];
        size_t len = (size_t)[d length];

        uint32_t foff = 0, fsize = 0;
        if (!_find_text(buf, len, &foff, &fsize)) continue;
        if ((size_t)foff + fsize > len) continue;

        uint8_t h[32];
        lk_sha256(buf + foff, (int)fsize, h);
        memcpy(out32, h, 32);
        return 32;
    }
    return -1;   /* 没找到母本 */
}

void lk_master_install_ios(void) {
    lk_master_set_hash_fn(&lk_master_hash_fn_ios);
}

/* 编译进 dylib 即自动装上读取器；回调只在 LK_MASTER_UNLOCK 开启且真正走到
 * 母本兜底时才会被调用（LK_MASTER_UNLOCK=0 时核心短路，零开销、零副作用）。
 * 这样宿主 tweak 不用手动调用 lk_master_install_ios() 也能生效。 */
__attribute__((constructor))
static void _lk_master_auto_install(void) {
    lk_master_set_hash_fn(&lk_master_hash_fn_ios);
}

#endif /* __APPLE__ */
