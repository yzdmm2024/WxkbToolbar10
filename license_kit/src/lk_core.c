/* ============================================================
 * license_kit · 校验状态机
 *
 * 纯 C，不碰任何平台 API —— 时间取 time()，存储/设备标识/验签全部走 lk_env 回调。
 * 因此这一层可以在 PC 上用 tools/test_core.c 跑完整 KAT，不需要真机。
 *
 * 三层时间防线（与 验证逻辑.md 一致）：
 *   1. 本地高水位比对（挡"改时间 + 清数据 + 重输旧码"）
 *   2. 权威时间比对（适配层预取，拿不到就降级为纯本地）
 *   3. 签名（Mode S 的 HMAC / Mode A 的 ECDSA）保证码不可伪造、到期日不可改
 * ============================================================ */
#include "lk.h"
#include "lk_keys.h"
#include <string.h>
#include <stdio.h>
#include <time.h>

/* 全程用"自 LK_EXP_EPOCH_MIN 起的分钟数"当时间标尺 —— 与码里的到期字段同单位。
 * 不来回换算，就不会出现"码按分钟、高水位按天"这类单位错配。
 * 注意 _hwm_sec 必须带上 epoch 偏移（用 lk_exp_to_time），否则会拿
 * "自 2026-01-01 起的秒"去比"自 1970 起的秒"，回拨检测永远不成立。 */
static long long _mins(double t) { return lk_time_to_exp(t); }
static double _hwm_sec(long long m) { return lk_exp_to_time(m); }

/* 当前时间优先走注入回调（便于 PC 单测），否则用系统时钟 */
static double _now(const lk_env *env) {
    if (env && env->now) return env->now();
    return (double)time(NULL);
}

/* 时间早于"该码可能的最早签发时间" ⇒ 回拨。
 * 码里只有到期时间，用最长有效期反推签发时间下界；高水位被清掉时靠它兜底。 */
static int _too_early(long long now_min, long long exp_min) {
    return (now_min + LK_MAX_VALIDITY_MIN + LK_NOTBEFORE_TOL_MIN) < exp_min;
}

/* 信誉分参与判定的实际取值。同一次校验里必须用同一个值做判定与密钥派生，
 * 否则会出现"判定说没问题、但派生出的密钥对不上"的自相矛盾状态。 */
static int _rep_used(const lk_env *env) {
    int r = (env && env->reputation) ? env->reputation() : 0;
#if LK_REP_ENFORCE == 0
    (void)r;
    return 0;
#elif LK_REP_ENFORCE == 1
    return r & 1;          /* 只认"自哈希不符" */
#else
    return r & 7;          /* 自哈希 + 被调试 + 关键函数被 hook */
#endif
}

/* 读三处冗余存储：取签名有效记录中高水位最大的那条。
 * 任一处"存在但签名不符" → 判定被篡改（用户手改 plist/文件会被当场抓到）。 */
static long long _read_state(const lk_env *env, char *code, int code_cap,
                             int *tampered, int rep) {
    long long best = 0;
    int found = 0;
    char best_code[LK_MAX_CODE];

    best_code[0] = 0;
    if (code && code_cap > 0) code[0] = 0;

    for (int slot = 0; slot < LK_SLOT_COUNT && env->store_read; slot++) {
        char buf[LK_MAX_BLOB];
        int n = env->store_read(slot, buf, (int)sizeof(buf));
        long long d = 0;
        char c[LK_MAX_CODE];

        if (n <= 0) continue;
        buf[sizeof(buf) - 1] = 0;

        if (lk_blob_parse(buf, &d, c, (int)sizeof(c), rep) == 0) {
            if (!found || d > best) { best = d; strcpy(best_code, c); found = 1; }
        } else if (tampered) {
            *tampered = 1;
        }
    }

    if (code && code_cap > 0) {
        strncpy(code, best_code, (size_t)code_cap - 1);
        code[code_cap - 1] = 0;
    }
    return found ? best : 0;
}

static void _write_state(const lk_env *env, const char *code, long long hwm, int rep) {
    char blob[LK_MAX_BLOB];
    (void)rep;
    if (!env || !env->store_write) return;
    if (!code) {
        for (int s = 0; s < LK_SLOT_COUNT; s++) env->store_write(s, NULL);
        return;
    }
    /* 永远用 rep=0 写，读取时才用当前 rep。
     * 这样即使有人把 `if (rep)` 那道判定 NOP 掉，写下的状态也会因为
     * 读取时 rep 不同而解析失败 → 走到 TAMPER —— 把"跳过检测"这条路堵死。 */
    if (lk_blob_make(blob, (int)sizeof(blob), code, hwm, 0) < 0) return;
    for (int s = 0; s < LK_SLOT_COUNT; s++) env->store_write(s, blob);
}

/* ---------- 启动 / 进面板前校验 ---------- */
lk_status lk_check(const lk_env *env, lk_reason *why) {
    char udid[160], code[LK_MAX_CODE];
    long long hwm, exp = 0, now_min;
    int tampered = 0, rep;
    double local, server, now;

    if (why) *why = LK_R_NONE;
    if (!env || !env->device_id || !env->store_read) {
        if (why) *why = LK_R_NO_ENV;
        return LK_INTERNAL;
    }
    if (env->device_id(udid, (int)sizeof(udid)) <= 0) {
        if (why) *why = LK_R_NO_UDID;
        return LK_LOCKED;
    }

    rep = _rep_used(env);
    if (rep) {
        if (why) *why = LK_R_ENV_SUSPECT;
        return LK_TAMPER;
    }

    hwm = _read_state(env, code, (int)sizeof(code), &tampered, rep);
    if (tampered) {
        if (why) *why = LK_R_STATE_TAMPERED;
        return LK_TAMPER;
    }

    local = _now(env);
    if (hwm > 0 && (local + LK_CLOCK_TOL) < _hwm_sec(hwm)) {
        if (why) *why = LK_R_CLOCK_ROLLBACK;
        return LK_TAMPER;
    }
    if (!code[0]) {
#if LK_MASTER_UNLOCK
        { long long mexp = 0;
          /* 母本 IPA 在场且完整 → dongle 解锁（每次启动重判，不落码状态）。
           * 走到这里说明 rep 已通过 lk_check 的筛查，环境干净；母本解锁本身
           * 还会在 lk_master_verify 里再查一次自哈希/调试，双重保险。 */
          if (lk_master_verify(env, why, &mexp) == LK_UNLOCKED)
              return LK_UNLOCKED;
        }
#endif
        if (why) *why = LK_R_NOT_UNLOCKED;
        return LK_LOCKED;
    }

    server = env->trusted_time ? env->trusted_time() : 0.0;
    if (server > 0 && (local + LK_CLOCK_TOL) < server) {
        if (why) *why = LK_R_CLOCK_ROLLBACK;
        return LK_TAMPER;
    }
    now = (server > local) ? server : local;
    now_min = _mins(now);

    if (lk_code_verify(env, code, LK_PRODUCT_ID, udid, &exp) != 0) {
        _write_state(env, NULL, 0, rep);          /* 状态里的码本身已失效，清掉 */
        if (why) *why = LK_R_STATE_BAD;
        return LK_LOCKED;
    }

    /* 回拨兜底：高水位可以被清掉，但"到期时间 - 最长有效期"这个下界清不掉 */
    if (_too_early(now_min, exp)) {
        if (why) *why = LK_R_CLOCK_EARLY;
        return LK_TAMPER;
    }

    /* 高水位只升不降 —— 即使已过期也要推进，这样过期后回拨时间依然会被抓到 */
    if (now_min > hwm) _write_state(env, code, now_min, rep);

    if (now_min > exp) {
        if (why) *why = LK_R_EXPIRED;
        return LK_EXPIRED;
    }
    return LK_UNLOCKED;
}

/* ---------- 用户提交解锁码 ---------- */
lk_status lk_submit(const lk_env *env, const char *input, lk_reason *why) {
    char canon[LK_MAX_CODE], udid[160], old[LK_MAX_CODE];
    long long exp = 0, old_exp = 0, hwm, now_min;
    int tampered = 0, renewal = 0, have_ref = 0, rep;
    double local, server, now;

    if (why) *why = LK_R_NONE;
    if (!env || !env->device_id || !env->store_read) {
        if (why) *why = LK_R_NO_ENV;
        return LK_INTERNAL;
    }
    if (!input || lk_code_normalize(input, canon, (int)sizeof(canon)) <= 0) {
        if (why) *why = LK_R_EMPTY_INPUT;
        return LK_LOCKED;
    }
    if (env->device_id(udid, (int)sizeof(udid)) <= 0) {
        if (why) *why = LK_R_NO_UDID;
        return LK_LOCKED;
    }

    rep = _rep_used(env);
    if (rep) {
        if (why) *why = LK_R_ENV_SUSPECT;
        return LK_TAMPER;
    }

    /* 1) 本地快速验签：码本身对不对立刻就能答，不让用户干等网络 */
    if (lk_code_verify(env, canon, LK_PRODUCT_ID, udid, &exp) != 0) {
        if (why) *why = LK_R_BAD_CODE;      /* 不回显正确码，也不透露任何验证信息 */
        return LK_LOCKED;
    }

    /* 2) 读旧状态 + 判定这次是不是「续签」
     *
     * 状态不可信时【不能】直接拒绝 —— 那样用户会被永久锁死且无法自救：
     *   - 换密钥/换 kStateShard 后重编 dylib：老用户 Keychain 里还是旧密钥
     *     签的 blob → 解析失败 → 永久 TAMPER
     *   - 用户把系统时间调到很远的未来 → 高水位被写成巨大值 → 调回正常
     *     时间后永久 TAMPER
     * 这两种情况用户手里往往都有合法的新码，所以允许码来重置状态。
     *
     * 续签判定（关键）：新码的到期时间【严格晚于】状态里那张码 → 这是一次
     * 真实的续期，允许它重置时钟参照；否则就是"拿旧码 + 回拨时钟重放"，
     * 继续按回拨处理。单看"码合法"是分不出这两者的 —— 过期码在回拨后的
     * 时间点上同样合法。有了这条判据，"付费用户续签一定进得来"和
     * "旧码重放一定被挡"才能同时成立。
     *
     * 注意 lk_check / lk_peek 仍然返回 TAMPER —— 只读路径不静默接受，
     * UI 应据此提示"状态异常，请重新输入解锁码"。 */
    old[0] = 0;
    hwm = _read_state(env, old, (int)sizeof(old), &tampered, rep);
    if (old[0]) lk_code_exp(old, &old_exp);   /* blob 已验签，这里只取值不验签 */
    renewal = (exp > old_exp);
    if (tampered) hwm = 0;                    /* 旧状态不可信，丢弃重来 */

    local = _now(env);
    if (hwm > 0 && (local + LK_CLOCK_TOL) < _hwm_sec(hwm)) {
        /* 高水位落在未来 = 本地时钟被前调过（或状态来自另一次安装）。
         * 它记的是一个假的"未来"，继续拿它当参照会把用户永久锁死；
         * 但也不能无条件丢弃 —— 否则"旧码 + 回拨时钟"就能无限续命。
         * 只有拿着到期时间更晚的新码（真续签）才允许重置。 */
        if (!renewal) {
            if (why) *why = LK_R_CLOCK_ROLLBACK;
            return LK_TAMPER;
        }
        hwm = 0;                              /* 真续签 → 以这次为准重建参照 */
    }
    /* 高水位可用时，"时钟被回拨"这件事已经被它挡住了；此时再叠 _too_early
     * 只会误锁"系统时间偏慢"的正版用户（刚开机没联网校时、跨时区等），
     * 所以只在没有可信参照时才用它兜底。 */
    have_ref = (hwm > 0);

    /* 3) 权威时间终判（适配层在调用前预取；拿不到则 server = 0，降级为纯本地） */
    server = env->trusted_time ? env->trusted_time() : 0.0;
    if (server > 0 && (local + LK_CLOCK_TOL) < server) {
        if (why) *why = LK_R_CLOCK_ROLLBACK;
        return LK_TAMPER;
    }
    now = (server > local) ? server : local;
    now_min = _mins(now);

    if (now_min > exp) {
        if (why) *why = LK_R_EXPIRED;
        return LK_EXPIRED;
    }
    if (!have_ref && _too_early(now_min, exp)) {
        if (why) *why = LK_R_CLOCK_EARLY;
        return LK_TAMPER;
    }

    _write_state(env, canon, now_min > hwm ? now_min : hwm, rep);
    return LK_UNLOCKED;
}

/* ---------- 只读本地状态 ---------- */
lk_status lk_peek(const lk_env *env, long long *exp_min, lk_reason *why) {
    char udid[160], code[LK_MAX_CODE];
    long long hwm, exp = 0, now_min;
    int tampered = 0, rep;

    if (why) *why = LK_R_NONE;
    if (exp_min) *exp_min = 0;
    if (!env || !env->device_id || !env->store_read) {
        if (why) *why = LK_R_NO_ENV;
        return LK_INTERNAL;
    }
    if (env->device_id(udid, (int)sizeof(udid)) <= 0) {
        if (why) *why = LK_R_NO_UDID;
        return LK_LOCKED;
    }

    rep = _rep_used(env);
    if (rep) {
        if (why) *why = LK_R_ENV_SUSPECT;
        return LK_TAMPER;
    }

    hwm = _read_state(env, code, (int)sizeof(code), &tampered, rep);
    if (tampered) {
        if (why) *why = LK_R_STATE_TAMPERED;
        return LK_TAMPER;
    }
    if (!code[0]) {
#if LK_MASTER_UNLOCK
        { long long mexp = 0;
          if (lk_master_verify(env, why, &mexp) == LK_UNLOCKED) {
              if (exp_min) *exp_min = mexp;
              return LK_UNLOCKED;
          }
        }
#endif
        if (why) *why = LK_R_NOT_UNLOCKED;
        return LK_LOCKED;
    }
    if (lk_code_verify(env, code, LK_PRODUCT_ID, udid, &exp) != 0) {
        if (why) *why = LK_R_STATE_BAD;
        return LK_LOCKED;
    }
    if (exp_min) *exp_min = exp;

    now_min = _mins(_now(env));
    if (hwm > 0 && (_now(env) + LK_CLOCK_TOL) < _hwm_sec(hwm)) {
        if (why) *why = LK_R_CLOCK_ROLLBACK;
        return LK_TAMPER;
    }
    if (now_min > exp) {
        if (why) *why = LK_R_EXPIRED;
        return LK_EXPIRED;
    }
    if (_too_early(now_min, exp)) {
        if (why) *why = LK_R_CLOCK_EARLY;
        return LK_TAMPER;
    }
    return LK_UNLOCKED;
}

void lk_clear(const lk_env *env) {
    _write_state(env, NULL, 0, 0);
}

/* ---------- 功能密钥：把授权"焊进"功能，而不是只给一个布尔值 ----------
 *
 * 为什么需要它：
 *   只要授权表现为"一个返回枚举的函数"，攻击者 NOP 掉那个判断就完事，
 *   成本是几分钟。真正能把逆向成本抬一个数量级的是：让授权产出【解密能力】。
 *
 * 适配层/插件侧用法：
 *   uint8_t fk[32];
 *   int ok = lk_func_key(env, fk);
 *   用 fk 去解密插件的功能数据（坐标算法常量表、Hook 载荷、配置模板…）。
 *   解不开就【静默不工作】—— 不要弹"授权失败"的框，那又变成一个可 patch
 *   的分支。目标是让插件"坏掉"，而不是"锁着"。
 *
 * 密钥输入包含：解锁态 + 高水位 + 到期 + 自哈希 + 信誉分 + 状态密钥。
 *   任何一项被改，密钥就变 → 功能数据解不开。没有可以跳过的分支。
 *
 * 返回 0 = 已解锁；-1 = 未解锁/被篡改。
 * 未解锁时 out 仍是【确定性的无效密钥】而不是全零 —— 免得攻击者靠
 * "输出是不是零"来定位判断点。 */
int lk_func_key(const lk_env *env, uint8_t out[32]) {
    uint8_t sk[32], seed[24];
    char udid[160], code[LK_MAX_CODE];
    long long hwm = 0, exp = 0, now_min;
    uint64_t sh;
    int tampered = 0, rep, ok = 0;

    if (!out) return -1;
    if (!env || !env->device_id || !env->store_read) {
        memset(out, 0x5C, 32);
        return -1;
    }

    rep = _rep_used(env);
    hwm = _read_state(env, code, (int)sizeof(code), &tampered, rep);

    if (!rep && !tampered && code[0] &&
        env->device_id(udid, (int)sizeof(udid)) > 0 &&
        lk_code_verify(env, code, LK_PRODUCT_ID, udid, &exp) == 0) {
        now_min = _mins(_now(env));
        if (now_min <= exp && !_too_early(now_min, exp)) ok = 1;
    }

#if LK_MASTER_UNLOCK
    /* 母本 IPA 解锁同样能产出功能密钥：把授权"焊进"功能，patch 掉校验 = 解不开。 */
    if (!ok) {
        long long mexp = 0;
        if (lk_master_verify(env, NULL, &mexp) == LK_UNLOCKED) {
            ok = 1;
            exp = mexp;
        }
    }
#endif

    sh = lk_self_hash();
    memset(seed, 0, sizeof(seed));
    seed[0] = (uint8_t)(ok ? 0xA5 : 0x00);
    for (int i = 0; i < 8; i++) seed[1 + i]  = (uint8_t)(hwm >> (i * 8));
    for (int i = 0; i < 4; i++) seed[9 + i]  = (uint8_t)(exp >> (i * 8));
    for (int i = 0; i < 8; i++) seed[13 + i] = (uint8_t)(sh  >> (i * 8));
    seed[21] = (uint8_t)rep;
    seed[22] = (uint8_t)(lk_is_traced() & 0xFF);
    seed[23] = (uint8_t)(lk_self_intact() & 0xFF);

    lk_state_key(sk, rep);
    lk_hmac_sha256(sk, 32, seed, (int)sizeof(seed), out);

    memset(sk, 0, sizeof(sk));
    memset(seed, 0, sizeof(seed));
    return ok ? 0 : -1;
}

/* ============================================================
 * 设备自检 —— 这是"保证逻辑没问题"的手段
 *
 * 真机上跑一次，能同时验证：
 *   ① 自带 SHA-256/HMAC 实现与标准一致
 *   ② 编码/解码往返正确
 *   ③ 本机嵌入的密钥/公钥与签发端（母本）完全匹配
 *   ④ Mode A 的裸签名 → DER 转换 + Apple 验签链路可用
 *   ⑤ 三处存储读写往返可用
 * ============================================================ */
static void _kat_hex(const uint8_t *d, int n, char *out, int cap) {
    static const char H[] = "0123456789abcdef";
    int i, k = 0;
    for (i = 0; i < n && k + 3 < cap; i++) {
        out[k++] = H[d[i] >> 4];
        out[k++] = H[d[i] & 15];
    }
    out[k] = 0;
}

static int _line(char *report, int cap, int *used, const char *name, int ok) {
    int n;
    if (*used >= cap - 1) return ok;
    n = snprintf(report + *used, (size_t)(cap - *used), "%s=%s\n", name, ok ? "PASS" : "FAIL");
    if (n > 0) *used += n;
    return ok;
}

int lk_selftest(const lk_env *env, char *report, int cap) {
    char hex[80], line[LK_MAX_CODE + 32];
    uint8_t d[32], key[32];
    int used = 0, fails = 0, n, ok;

    if (report && cap > 0) report[0] = 0;
    if (!report || cap < 128) return -1;

    /* ① SHA-256("abc") 标准向量 */
    lk_sha256((const uint8_t *)"abc", 3, d);
    _kat_hex(d, 32, hex, (int)sizeof(hex));
    ok = (strcmp(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0);
    fails += !_line(report, cap, &used, "sha256_kat", ok);

    /* ① HMAC-SHA256 RFC 4231 case 2 */
    lk_hmac_sha256((const uint8_t *)"Jefe", 4,
                   (const uint8_t *)"what do ya want for nothing?", 28, d);
    _kat_hex(d, 32, hex, (int)sizeof(hex));
    ok = (strcmp(hex, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843") == 0);
    fails += !_line(report, cap, &used, "hmac_kat", ok);

    /* ② 到期时间往返（覆盖整个 25 bit 取值域，含分钟级小值） */
    ok = 1;
    for (long long v = 0; v <= LK_EXP_MAX; v += 7919) {
        char e[LK_EXP_CHARS];
        lk_exp_encode(v, e);
        if (lk_exp_decode(e) != v) { ok = 0; break; }
    }
    fails += !_line(report, cap, &used, "exp_roundtrip", ok);

    /* ② base32 往返（含末位补零的 64 字节定长） */
    ok = 1;
    for (int i = 0; i < 64; i++) d[i] = (uint8_t)(i * 37 + 11);
    n = lk_b32_encode(d, 64, line, (int)sizeof(line));
    if (n != LK_RAWSIG_CHARS) ok = 0;
    else {
        uint8_t back[64];
        if (lk_b32_decode(line, n, back, (int)sizeof(back)) != 64) ok = 0;
        else if (memcmp(back, d, 64) != 0) ok = 0;
    }
    fails += !_line(report, cap, &used, "base32_roundtrip", ok);

    /* ② DER 往返 */
    ok = 0;
    if (n == LK_RAWSIG_CHARS) {
        uint8_t der[80], back[64];
        int dl = lk_der_from_raw(d, der);
        if (dl > 0 && lk_raw_from_der(der, dl, back) == 0 && memcmp(back, d, 64) == 0) ok = 1;
    }
    fails += !_line(report, cap, &used, "der_roundtrip", ok);

    /* ③ 配置一致性：源码里的产品 ID 必须与签发时用的一致 */
    ok = (strcmp(LK_PRODUCT_ID, LK_ST_PID) == 0);
    fails += !_line(report, cap, &used, "product_id_match", ok);

    /* ③ 对称密钥一致性：本机算出的码必须等于母本签发时记录的那一张 */
    {
        char want[LK_CODE_LEN_S + 1];
        ok = 0;
        if (lk_code_make_s(LK_PRODUCT_ID, LK_ST_UDID, LK_ST_EXP, want, (int)sizeof(want)) == LK_CODE_LEN_S)
            ok = (strcmp(want, LK_ST_CODE_S) == 0);
        fails += !_line(report, cap, &used, "mode_s_key_match", ok);
    }

#if LK_MODE_A
    /* ③④ 公钥一致性 + Apple 验签链路：用母本签好的已知码走完整验签 */
    ok = 0;
    if (env && env->ecdsa_verify) {
        long long e2 = 0;
        if (lk_code_verify(env, LK_ST_CODE_A, LK_PRODUCT_ID, LK_ST_UDID, &e2) == 0)
            ok = (e2 == LK_ST_EXP);
    }
    fails += !_line(report, cap, &used, "mode_a_pubkey_verify", ok);
#endif

    /* ⑤ 存储往返（用槽位 0，测完恢复原值） */
    ok = 0;
    if (env && env->store_read && env->store_write) {
        char save[LK_MAX_BLOB];
        char blob[LK_MAX_BLOB];
        long long h = 0;
        char c[LK_MAX_CODE];
        int sn = env->store_read(LK_SLOT_DEFAULTS, save, (int)sizeof(save));

        if (lk_blob_make(blob, (int)sizeof(blob), LK_ST_CODE_S, 12345, 0) > 0
            && env->store_write(LK_SLOT_DEFAULTS, blob) == 0) {
            char back[LK_MAX_BLOB];
            int bn = env->store_read(LK_SLOT_DEFAULTS, back, (int)sizeof(back));
            if (bn > 0 && lk_blob_parse(back, &h, c, (int)sizeof(c), 0) == 0
                && h == 12345 && strcmp(c, LK_ST_CODE_S) == 0)
                ok = 1;
        }
        if (sn > 0) { save[sizeof(save) - 1] = 0; env->store_write(LK_SLOT_DEFAULTS, save); }
        else env->store_write(LK_SLOT_DEFAULTS, NULL);
    }
    fails += !_line(report, cap, &used, "store_roundtrip", ok);

    /* 设备标识可用性 */
    ok = 0;
    if (env && env->device_id) {
        char u[160];
        ok = (env->device_id(u, (int)sizeof(u)) > 0);
    }
    fails += !_line(report, cap, &used, "device_id", ok);

    /* 环境信息（仅记录，不计失败） */
    if (env && env->trusted_time) {
        double t = env->trusted_time();
        snprintf(line, sizeof(line), "trusted_time=%.0f (%s)\n", t, t > 0 ? "online" : "offline");
        if (used + (int)strlen(line) < cap) { strcat(report, line); used += (int)strlen(line); }
    }
    {
        int intact = lk_self_intact();
        int traced = lk_is_traced();
        snprintf(line, sizeof(line), "self_intact=%d traced=%d hooked=%d rep=%d\n",
                 intact, traced, lk_entry_hooked((const void *)&lk_selftest),
                 env && env->reputation ? env->reputation() : 0);
        if (used + (int)strlen(line) < cap) { strcat(report, line); used += (int)strlen(line); }
    }

    snprintf(line, sizeof(line), "RESULT=%s fails=%d\n", fails ? "FAIL" : "OK", fails);
    if (used + (int)strlen(line) < cap) strcat(report, line);

    /* Mode S 密钥做一次实际使用，避免编译器把派生函数优化掉 */
    lk_assemble_key(key, 32);
    memset(key, 0, sizeof(key));

    return fails;
}