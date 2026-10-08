/* ============================================================
 * license_kit · 编码与报文
 *
 * 两种解锁码格式（到期字段两模式共用）：
 *
 *   到期字段（5 位，25 bit，base32 大端）
 *     = 自 LK_EXP_EPOCH_MIN 起的分钟数。精度 1 分钟，可表示到 2089 年。
 *       存绝对时间而不是"有效时长"，是为了让到期判定不依赖任何可被清掉的
 *       本地激活记录 —— 见 lk.h 里 LK_EXP_CHARS 的注释。
 *
 *   Mode S（对称，16 位）
 *     [0..4]  到期字段 5 位
 *     [5..15] HMAC-SHA256(产品密钥, "<PID>|<UDID>|<expMin>") 前 11 字节，每字节 % 32
 *
 *   Mode A（非对称，108 位）
 *     [0..4]   到期字段 5 位
 *     [5..107] 64 字节 ECDSA 裸签名 r||s 的 base32 位流（5 bit/字符，末位补 0）
 *              —— 线上传定长裸签名，落到 Apple API 前在 lk_code_verify 里转成 DER
 *
 * 状态 blob：
 *     "<hwmMin>|<code>.<sig8>"
 *     sig8 = HMAC-SHA256(状态密钥, "state|<hwmMin>|<code>") 前 8 字节，每字节 % 32
 * ============================================================ */
#include "lk.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static const char CS[LK_CHARSET_LEN + 1] = LK_CHARSET;

/* ---------- base32 位流 ---------- */
int lk_b32_encode(const uint8_t *in, int in_len, char *out, int cap) {
    int bits = in_len * 8;
    int n = (bits + 4) / 5;
    if (n + 1 > cap) return -1;
    for (int i = 0; i < n; i++) {
        unsigned v = 0;
        for (int b = 0; b < 5; b++) {
            int bit = i * 5 + b;
            unsigned one = 0;
            if (bit < bits) one = (in[bit >> 3] >> (7 - (bit & 7))) & 1u;
            v = (v << 1) | one;
        }
        out[i] = CS[v & 31u];
    }
    out[n] = 0;
    return n;
}

int lk_b32_decode(const char *in, int in_len, uint8_t *out, int cap) {
    int bits = in_len * 5;
    int n = bits / 8;
    if (n > cap) return -1;
    memset(out, 0, (size_t)n);
    for (int i = 0; i < in_len; i++) {
        const char *p = strchr(CS, (int)(unsigned char)in[i]);
        if (!p) return -1;
        unsigned v = (unsigned)(p - CS);
        for (int b = 0; b < 5; b++) {
            int bit = i * 5 + b;
            if (bit >= bits) break;
            if ((v >> (4 - b)) & 1u) {
                int bi = bit >> 3;
                if (bi < n) out[bi] |= (uint8_t)(1u << (7 - (bit & 7)));
            }
        }
    }
    return n;
}

/* ---------- 到期时间（分钟，5 字符 25 bit） ---------- */
void lk_exp_encode(long long exp_min, char out[LK_EXP_CHARS]) {
    out[0] = CS[(exp_min >> 20) & 31];
    out[1] = CS[(exp_min >> 15) & 31];
    out[2] = CS[(exp_min >> 10) & 31];
    out[3] = CS[(exp_min >>  5) & 31];
    out[4] = CS[ exp_min        & 31];
}

long long lk_exp_decode(const char *p) {
    long long v = 0;
    for (int i = 0; i < LK_EXP_CHARS; i++) {
        const char *q = strchr(CS, (int)(unsigned char)p[i]);
        if (!q) return -1;
        v = (v << 5) | (long long)(q - CS);
    }
    return v;
}

long long lk_time_to_exp(double t) {
    return (long long)(t / 60.0) - LK_EXP_EPOCH_MIN;
}

double lk_exp_to_time(long long exp_min) {
    return (double)(exp_min + LK_EXP_EPOCH_MIN) * 60.0;
}

/* ---------- 有效期单位 ----------
 * 月按 30 天、年按 365 天：不做日历推算，避免"1 月 31 日 + 1 个月"这类歧义。
 * 生成器选的单位和列表显示用的单位是同一张表，两边不会对不上。 */
#define MIN_PER_HOUR  60LL
#define MIN_PER_DAY   1440LL
#define MIN_PER_MONTH (30LL * MIN_PER_DAY)
#define MIN_PER_YEAR  (365LL * MIN_PER_DAY)

static const long long kUnitMin[LK_UNIT_COUNT] = {
    1LL, MIN_PER_HOUR, MIN_PER_DAY, MIN_PER_MONTH, MIN_PER_YEAR
};
static const char *const kUnitName[LK_UNIT_COUNT] = {
    "分钟", "小时", "天", "个月", "年"
};

long long lk_unit_to_minutes(int unit, long long amount) {
    long long per;
    if (unit < 0 || unit >= LK_UNIT_COUNT) return -1;
    if (amount <= 0) return -1;
    per = kUnitMin[unit];
    if (amount > LK_EXP_MAX / per) return -1;   /* 乘出来超编码上限 */
    return amount * per;
}

const char *lk_unit_name(int unit) {
    if (unit < 0 || unit >= LK_UNIT_COUNT) return "";
    return kUnitName[unit];
}

int lk_remain_split(long long remain_min, int *unit, long long *amount,
                    int *unit2, long long *amount2) {
    int u = LK_UNIT_MINUTE, u2 = -1;
    long long a = 0, a2 = 0;

    if (unit)   *unit = LK_UNIT_MINUTE;
    if (amount) *amount = 0;
    if (unit2)  *unit2 = -1;
    if (amount2) *amount2 = 0;
    if (remain_min <= 0) return LK_UNIT_MINUTE;

    if (remain_min >= MIN_PER_YEAR) {
        long long rest;
        u = LK_UNIT_YEAR;
        a = remain_min / MIN_PER_YEAR;
        rest = remain_min % MIN_PER_YEAR;
        if (rest >= MIN_PER_MONTH) { u2 = LK_UNIT_MONTH; a2 = rest / MIN_PER_MONTH; }
    } else if (remain_min >= MIN_PER_MONTH) {
        long long rest;
        u = LK_UNIT_MONTH;
        a = remain_min / MIN_PER_MONTH;
        rest = remain_min % MIN_PER_MONTH;
        if (rest >= MIN_PER_DAY) { u2 = LK_UNIT_DAY; a2 = rest / MIN_PER_DAY; }
    } else if (remain_min >= MIN_PER_DAY) {
        u = LK_UNIT_DAY;
        a = remain_min / MIN_PER_DAY;
    } else if (remain_min >= MIN_PER_HOUR) {
        u = LK_UNIT_HOUR;
        a = remain_min / MIN_PER_HOUR;
    } else {
        u = LK_UNIT_MINUTE;
        a = remain_min;
    }

    if (unit)   *unit = u;
    if (amount) *amount = a;
    if (unit2)  *unit2 = u2;
    if (amount2) *amount2 = a2;
    return u;
}

/* ---------- 报文 ---------- */
int lk_msg_build(char *out, int cap, const char *pid, const char *udid, long long exp_min) {
    if (!out || cap <= 0) return -1;
    if (!pid)  pid  = "";
    if (!udid) udid = "";
    int n = snprintf(out, (size_t)cap, "%s|%s|%lld", pid, udid, exp_min);
    if (n < 0 || n >= cap) { out[0] = 0; return -1; }
    return n;
}

/* ---------- DER <-> 裸签名 ---------- */
static int _int_der(const uint8_t *v, int n, uint8_t *out) {
    int i = 0, len, pad;
    while (i < n - 1 && v[i] == 0x00) i++;      /* 去掉前导零 */
    len = n - i;
    pad = (v[i] & 0x80) ? 1 : 0;                /* 最高位为 1 时补 0x00，避免被当成负数 */
    out[0] = 0x02;
    out[1] = (uint8_t)(len + pad);
    if (pad) out[2] = 0x00;
    memcpy(out + 2 + pad, v + i, (size_t)len);
    return 2 + pad + len;
}

int lk_der_from_raw(const uint8_t raw[LK_RAWSIG_BYTES], uint8_t out[80]) {
    uint8_t rb[40], sb[40];
    int rl = _int_der(raw, 32, rb);
    int sl = _int_der(raw + 32, 32, sb);
    int total = rl + sl;
    out[0] = 0x30;
    out[1] = (uint8_t)total;                    /* 最长 70，短格式足够 */
    memcpy(out + 2, rb, (size_t)rl);
    memcpy(out + 2 + rl, sb, (size_t)sl);
    return 2 + total;
}

static int _der_int(const uint8_t *p, int avail, uint8_t out[32]) {
    int len;
    if (avail < 2 || p[0] != 0x02) return -1;
    len = p[1];
    if (len < 1 || 2 + len > avail || len > 33) return -1;
    const uint8_t *v = p + 2;
    if (len == 33) {
        if (v[0] != 0x00) return -1;            /* 只允许一个符号填充字节 */
        v++; len = 32;
    }
    memset(out, 0, 32);
    memcpy(out + (32 - len), v, (size_t)len);
    return 2 + (p[1]);
}

int lk_raw_from_der(const uint8_t *der, int der_len, uint8_t raw[LK_RAWSIG_BYTES]) {
    int seq, used, used2;
    if (der_len < 8 || der[0] != 0x30) return -1;
    seq = der[1];
    if (seq + 2 != der_len) return -1;
    used = _der_int(der + 2, der_len - 2, raw);
    if (used < 0) return -1;
    used2 = _der_int(der + 2 + used, der_len - 2 - used, raw + 32);
    if (used2 < 0) return -1;
    if (2 + used + used2 != der_len) return -1;
    return 0;
}

/* ---------- 码规范化 ---------- */
int lk_code_normalize(const char *in, char *out, int cap) {
    int n = 0;
    if (!in || !out || cap < 2) return -1;
    for (const char *p = in; *p; p++) {
        unsigned char c = (unsigned char)*p;
        if (c >= 'a' && c <= 'z') c = (unsigned char)(c - 'a' + 'A');
        if (!strchr(CS, (int)c)) continue;      /* 丢掉连字符、空格、换行 */
        if (n + 1 >= cap) return -1;
        out[n++] = (char)c;
    }
    out[n] = 0;
    return n;
}

/* 展示用分组：每 group 个字符插一个连字符。校验前会被 lk_code_normalize 去掉 */
int lk_code_group(const char *code, char *out, int cap, int group) {
    int n = 0, i = 0;
    if (!code || !out || cap < 2 || group <= 0) return -1;
    for (; code[i]; i++) {
        if (i > 0 && i % group == 0) {
            if (n + 2 > cap) return -1;
            out[n++] = '-';
        }
        if (n + 2 > cap) return -1;
        out[n++] = code[i];
    }
    out[n] = 0;
    return n;
}

int lk_code_exp(const char *code, long long *exp_min) {
    char buf[LK_MAX_CODE];
    int n = lk_code_normalize(code, buf, sizeof(buf));
    long long e;
    if (n != LK_CODE_LEN_S && n != LK_CODE_LEN_A) return -1;
    e = lk_exp_decode(buf);
    if (e < 0) return -1;
    if (exp_min) *exp_min = e;
    return 0;
}

/* ---------- Mode S ---------- */
int lk_code_make_s(const char *pid, const char *udid, long long exp_min, char *out, int cap) {
    char msg[LK_MAX_MSG];
    uint8_t key[32], h[32];
    if (cap < LK_CODE_LEN_S + 1) return -1;
    if (lk_msg_build(msg, sizeof(msg), pid, udid, exp_min) < 0) return -1;

    lk_assemble_key(key, 32);
    lk_hmac_sha256(key, 32, (const uint8_t *)msg, (int)strlen(msg), h);
    memset(key, 0, sizeof(key));

    lk_exp_encode(exp_min, out);
    for (int i = 0; i < LK_SIG_CHARS; i++) out[LK_EXP_CHARS + i] = CS[h[i] % LK_CHARSET_LEN];
    out[LK_CODE_LEN_S] = 0;
    return LK_CODE_LEN_S;
}

/* ---------- Mode A ---------- */
int lk_code_make_a(long long exp_min, const uint8_t *der, int der_len, char *out, int cap) {
    uint8_t raw[LK_RAWSIG_BYTES];
    if (cap < LK_CODE_LEN_A + 1) return -1;
    if (!der || lk_raw_from_der(der, der_len, raw) != 0) return -1;

    lk_exp_encode(exp_min, out);
    if (lk_b32_encode(raw, LK_RAWSIG_BYTES, out + LK_EXP_CHARS,
                      LK_CODE_LEN_A + 1 - LK_EXP_CHARS) != LK_RAWSIG_CHARS)
        return -1;
    out[LK_CODE_LEN_A] = 0;
    return LK_CODE_LEN_A;
}

/* ---------- 验签 ---------- */
int lk_code_verify(const lk_env *env, const char *code,
                   const char *pid, const char *udid, long long *exp_min) {
    char canon[LK_MAX_CODE];
    char msg[LK_MAX_MSG];
    long long exp;
    int n = lk_code_normalize(code, canon, sizeof(canon));

    if (n != LK_CODE_LEN_S && n != LK_CODE_LEN_A) return -1;
    exp = lk_exp_decode(canon);
    if (exp < 0) return -1;
    if (lk_msg_build(msg, sizeof(msg), pid, udid, exp) < 0) return -1;

    if (n == LK_CODE_LEN_S) {
#if !LK_ACCEPT_MODE_S
        /* 只吃 Mode A 的产品直接拒收对称码：见 lk_config.h 的说明 */
        return -1;
#else
        char want[LK_CODE_LEN_S + 1];
        if (lk_code_make_s(pid, udid, exp, want, sizeof(want)) != LK_CODE_LEN_S) return -1;
        if (strcmp(want, canon) != 0) return -1;
#endif
    } else {
        uint8_t raw[LK_RAWSIG_BYTES], der[80];
        char again[LK_CODE_LEN_A + 1];
        int dl;
        if (lk_b32_decode(canon + LK_EXP_CHARS, LK_RAWSIG_CHARS, raw, sizeof(raw)) != LK_RAWSIG_BYTES)
            return -1;
        /* 只接受规范编码，避免同一签名有多个可用字符串 */
        if (lk_b32_encode(raw, LK_RAWSIG_BYTES, again + LK_EXP_CHARS,
                          LK_CODE_LEN_A + 1 - LK_EXP_CHARS) != LK_RAWSIG_CHARS)
            return -1;
        lk_exp_encode(exp, again);
        again[LK_CODE_LEN_A] = 0;
        if (strcmp(again, canon) != 0) return -1;

        if (!env || !env->ecdsa_verify) return -1;
        dl = lk_der_from_raw(raw, der);
        if (!env->ecdsa_verify(msg, der, dl)) return -1;
    }

    if (exp_min) *exp_min = exp;
    return 0;
}

/* ---------- 状态 blob ---------- */
static void _sig8(const char *payload, int rep, char out[9]) {
    char m[LK_MAX_BLOB + 16];
    uint8_t key[32], h[32];
    lk_state_key(key, rep);
    snprintf(m, sizeof(m), "state|%s", payload);
    lk_hmac_sha256(key, 32, (const uint8_t *)m, (int)strlen(m), h);
    memset(key, 0, sizeof(key));
    for (int i = 0; i < 8; i++) out[i] = CS[h[i] % LK_CHARSET_LEN];
    out[8] = 0;
}

int lk_blob_make(char *out, int cap, const char *code, long long hwm_min, int rep) {
    char payload[LK_MAX_BLOB], sig[9];
    int n;
    if (!out || cap <= 0) return -1;
    n = snprintf(payload, sizeof(payload), "%lld|%s", hwm_min, code ? code : "");
    if (n < 0 || n >= (int)sizeof(payload)) return -1;
    _sig8(payload, rep, sig);
    n = snprintf(out, (size_t)cap, "%s.%s", payload, sig);
    if (n < 0 || n >= cap) return -1;
    return n;
}

int lk_blob_parse(const char *blob, long long *hwm_min, char *code, int code_cap, int rep) {
    const char *dot, *bar;
    char payload[LK_MAX_BLOB], sig[9];
    size_t plen;

    if (!blob) return -1;
    dot = strrchr(blob, '.');
    if (!dot) return -1;
    plen = (size_t)(dot - blob);
    if (plen == 0 || plen >= sizeof(payload)) return -1;
    if (strlen(dot + 1) != 8) return -1;
    memcpy(payload, blob, plen);
    payload[plen] = 0;

    _sig8(payload, rep, sig);
    if (strcmp(sig, dot + 1) != 0) return -1;    /* 被手工改过 */

    bar = strchr(payload, '|');
    if (!bar) return -1;
    if (hwm_min) *hwm_min = atoll(payload);
    if (code && code_cap > 0) {
        size_t clen = strlen(bar + 1);
        if ((int)clen + 1 > code_cap) return -1;
        memcpy(code, bar + 1, clen + 1);
    }
    return 0;
}