/* ============================================================
 * license_kit · 母本 IPA 解锁（dongle 模式，基于代码段哈希）
 *
 * 设计见 lk_config.h §8.5 与 lk.h 的声明注释。要点：
 *   - 默认 LK_MASTER_UNLOCK=0：整文件短路返回 LK_LOCKED，对现有码验证 /
 *     三处冗余 / KAT 零影响（PC 端没有 iOS 读取器，母本永远「未找到」）。
 *   - 开启后：设备上装着正版母本生成器（com.locsim.generator）且完整，
 *     其 __TEXT,__text 代码段 SHA256 与内置混淆常量吻合 → 解锁。
 *     母本 App 本身就是钥匙，每次启动重判，不落码状态。
 *   - 为什么校验代码段而不是 plist token：
 *       ① 重签（TrollStore / ldid）只改 __LINKEDIT 里的签名，不动
 *          __TEXT,__text 字节 → 哈希在签名前后稳定；
 *       ② 同名空壳 App 无法复现代码段哈希 → 伪造失效；
 *       ③ 完全不改母本 IPA（用户要求：只加 dylib 端验证与混淆）。
 *   - 预期哈希以 lk_dec 同款 XOR 密文落盘（OBF_32）；bundle id 同样加密。
 *     strings 搜不到明文哈希也搜不到 bundle id。
 *   - 环境洁净性由调用方（lk_check / lk_func_key / lk_peek）经 _rep_used
 *     先行把关；本函数再二次校验自哈希/调试状态，双重保险：
 *     任何「NOP 掉反调试/自哈希」的改动都会让这里判失败。
 *
 * 平台相关部分（枚举已装 App、读其二进制、算哈希）不在这里实现，而是由适配层
 * 通过 lk_master_set_hash_fn() 注入一个 iOS 读取器（见 ios_glue/lk_master_ios.m）。
 * ============================================================ */
#include "lk.h"
#include <string.h>
#include <stdio.h>
#include <time.h>

/* ---------- 混淆字面量（lk_dec 同款 XOR：e[i] = p[i] ^ (0x5A ^ (i*31 & 0xFF))） ---------- */
/* com.locsim.generator */
static const unsigned char kBundleEnc[20] = {
    0x39, 0x2A, 0x09, 0x29, 0x4A, 0xAE, 0x83, 0xF0, 0xCB, 0x20,
    0x42, 0x68, 0x4B, 0xA7, 0x8D, 0xF9, 0xCB, 0x21, 0x1B, 0x65
};

/* 母本 __TEXT,__text 的 SHA256，经 lk_dec 同款 XOR 混淆（tools/emit_master_hash.py
 * 生成）。重签不动代码段 → 此值稳定。改母本后必须重跑该脚本刷新本数组。
 * 当前值对应 locsim_gen.ipa 代码段哈希 SHA256 =
 *   a4ebb2edf1006c9682440dc91c87cc81ecfceeb4bc70841293987bda236d645a
 * （2026-10-09 用 emit_master_hash.py 实测重算并刷新，使母本 dongle 真正解锁）。 */
static const unsigned char kMasterTextHashEnc[32] = {
    0xFE, 0xAE, 0xD6, 0xEA, 0xD7, 0xC1, 0x8C, 0x15, 0x20, 0x09, 0x61, 0xC6, 0x32, 0x4E, 0x24, 0x0A,
    0x46, 0xA9, 0x9A, 0xA3, 0x8A, 0xA1, 0x74, 0x81, 0x21, 0xC5, 0x07, 0xC5, 0x1D, 0xB4, 0x9C, 0xC1
};

/* 本地解密（不依赖 lk_obf.c 的共享缓冲，避免同表达式复用问题） */
static int _dec(const unsigned char *e, size_t n, char *out, int cap) {
    if (!out || cap <= 0) return 0;
    size_t m = n < (size_t)cap - 1 ? n : (size_t)cap - 1;
    for (size_t i = 0; i < m; i++)
        out[i] = (char)(e[i] ^ (unsigned char)(0x5A ^ ((i * 31) & 0xFF)));
    out[m] = 0;
    return (int)m;
}

/* 恒定时间比较（逐字节，长度固定 32） */
static int _ct_eq32(const uint8_t *a, const uint8_t *b, size_t n) {
    unsigned char d = 0;
    for (size_t i = 0; i < n; i++) d |= (unsigned char)(a[i] ^ b[i]);
    return d == 0;
}

/* ---------- 母本哈希的 iOS 读取回调（适配层注入；默认桩必失败） ---------- */
static int _default_hash_fn(const char *bundle_id, uint8_t *out32, int cap) {
    (void)bundle_id; (void)out32; (void)cap;
    return -1;   /* 未安装读取器 / 找不到母本 → 未找到 */
}
static lk_master_hash_fn g_hash_fn = _default_hash_fn;

void lk_master_set_hash_fn(lk_master_hash_fn fn) {
    g_hash_fn = fn ? fn : _default_hash_fn;
}

const char *lk_master_bundle(void) {
    static char b[64];
    _dec(kBundleEnc, sizeof(kBundleEnc), b, sizeof(b));
    return b;
}

lk_status lk_master_verify(const lk_env *env, lk_reason *why, long long *exp_min) {
#if !LK_MASTER_UNLOCK
    (void)env; (void)why; (void)exp_min;
    return LK_LOCKED;
#else
    if (why) *why = LK_R_NONE;

    /* 环境必须干净：自哈希 intact + 未被调试。双重保险让「NOP 掉检测」必失败。 */
    if (!lk_self_intact())  { if (why) *why = LK_R_ENV_SUSPECT; return LK_LOCKED; }
    if (lk_is_traced())     { if (why) *why = LK_R_ENV_SUSPECT; return LK_LOCKED; }

    char bundle[64];
    if (!_dec(kBundleEnc, sizeof(kBundleEnc), bundle, sizeof(bundle))) {
        if (why) *why = LK_R_INTERNAL; return LK_LOCKED;
    }

    uint8_t got[32];
    int n = g_hash_fn(bundle, got, (int)sizeof(got));
    if (n != 32) { if (why) *why = LK_R_NOT_UNLOCKED; return LK_LOCKED; }

    /* 解混淆出预期哈希并恒定时间比较 */
    uint8_t exp[32];
    for (int i = 0; i < 32; i++)
        exp[i] = (uint8_t)(kMasterTextHashEnc[i] ^ (unsigned char)(0x5A ^ ((i * 31) & 0xFF)));

    if (!_ct_eq32(exp, got, 32)) { if (why) *why = LK_R_NOT_UNLOCKED; return LK_LOCKED; }

    if (exp_min) {
        double now = (env && env->now) ? env->now() : (double)time(NULL);
        *exp_min = lk_time_to_exp(now) + (long long)LK_MASTER_UNLOCK_DAYS * LK_MIN_PER_DAY;
    }
    return LK_UNLOCKED;
#endif
}
