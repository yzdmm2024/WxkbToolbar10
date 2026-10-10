/* ============================================================
 * license_kit · 对外唯一头文件
 *
 * 分层：
 *   lk_sha256.c  纯算法原语（SHA-256 / HMAC）      无依赖，可单测
 *   lk_alg.c     编码与报文（base32 / 码 / 状态 blob / DER）  无依赖，可单测
 *   lk_core.c    校验状态机（check / submit / selftest）      无依赖，可单测
 *   lk_obf.c     密钥分片 / 字符串解密 / 反调试 / 自哈希      iOS 相关部分需 Darwin
 *   lk_issue.c   签发（生成器端复用同一套算法，保证两端一致）
 *   适配层       lk_ios.m（iOS）/ 你自己的 main（其它平台）
 *
 * 适配层必须提供的回调见 lk_env。核心不碰任何平台 API，因此
 * 可以在 PC 上用 tools/test_core.c 完整跑 KAT。
 * ============================================================ */
#ifndef LK_H
#define LK_H

#include <stdint.h>
#include <stddef.h>
#include "lk_config.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---------- 容量上限 ---------- */
#define LK_MAX_CODE 192     /* Mode A = 108，Mode S = 16，留余量 */
#define LK_MAX_MSG  768     /* "<pid>|<udid>|<expMin>" */
#define LK_MAX_BLOB 384     /* "<hwmMin>|<code>.<sig>" */
#define LK_CHARSET  "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"   /* 32 字符，去 0O1IL */
#define LK_CHARSET_LEN 32

/* ---------- 到期时间字段：5 字符 = 25 bit，单位「分钟」 ----------
 * 起点 2026-01-01 00:00:00 UTC。可表示 0 .. 2^25-1 分钟 ≈ 63.8 年（到 2089 年），
 * 精度 1 分钟 —— 分钟/小时级试用码和年费码用同一套编码，不必分模式。
 *
 * 为什么不是「天」：4 字符 = 20 bit 只能表示整天，5 分钟/2 小时的码没法表达。
 * 为什么不存「相对有效期」：相对值要靠首次激活时间，而激活时间是可被清掉的，
 * 一旦清掉就等于把时钟重置，反而给绕过留了后门。到期时间必须是绝对时间。 */
#define LK_EXP_CHARS     5
#define LK_EXP_EPOCH_MIN 29453760LL   /* 2026-01-01 00:00:00 UTC 对应的分钟数 */
#define LK_EXP_MAX       33554431LL   /* 2^25 - 1，编码上限 */

#define LK_SIG_CHARS   11    /* Mode S 签名位数 */
#define LK_RAWSIG_BYTES 64   /* Mode A 裸签名 r||s */
#define LK_RAWSIG_CHARS 103  /* 64 字节 → base32 5bit/字符 */
#define LK_CODE_LEN_S  16    /* 5 位到期 + 11 位签名 */
#define LK_CODE_LEN_A  108   /* 5 位到期 + 103 位裸签名 */

/* ---------- 状态码 ---------- */
typedef enum {
    LK_UNLOCKED = 0,   /* 已解锁且未过期 */
    LK_LOCKED   = 1,   /* 未解锁 / 解锁码无效 */
    LK_EXPIRED  = 2,   /* 已到期，需要新码 */
    LK_TAMPER   = 3,   /* 检测到时钟或状态存储被篡改 */
    LK_INTERNAL = 4,   /* 内部错误（配置/适配层缺失） */
} lk_status;

/* ---------- 适配层回调 ---------- */
/*
 * store_read(slot, buf, cap)   读第 slot 处存储，返回实际写入 buf 的长度；无记录返回 -1
 * store_write(slot, blob)      写第 slot 处存储；blob 为 NULL 表示删除；返回 0 成功
 * trusted_time()               返回权威 UTC 秒；拿不到（无网络/未预取）返回 0
 * device_id(buf, cap)          写入设备标识（UDID），返回长度；失败返回 -1
 * now()                        当前时间（UTC 秒）。为 NULL 时用 time()。可注入以便单测
 * ecdsa_verify(msg, der, len)  Mode A 验签：msg 为明文报文，der 为 X9.62/DER 签名；返回 1 通过
 * reputation()                 反调试/完整性信誉分，0 = 干净
 *
 * 除 store_* 和 reputation 外都可为 NULL（对应能力自动降级）。
 */
typedef struct {
    int    (*store_read)(int slot, char *buf, int cap);
    int    (*store_write)(int slot, const char *blob);
    double (*trusted_time)(void);
    double (*now)(void);
    int    (*device_id)(char *buf, int cap);
    int    (*ecdsa_verify)(const char *msg, const uint8_t *der, int der_len);
    int    (*reputation)(void);
} lk_env;

/* 适配层提供的运行期环境单例（在 lk_env_ios.m 中定义，编译进本 dylib / bundle）。
 * 放 extern "C" 块内，确保被 Objective-C++（.xm.mm）引用时按 C 链接，
 * 与 .m 里的 C 定义对得上，避免 name-mangling 导致的 Undefined symbols。 */
const lk_env *lk_get_env(void);

/* 存储槽位 */
enum { LK_SLOT_DEFAULTS = 0, LK_SLOT_FILE = 1, LK_SLOT_KEYCHAIN = 2, LK_SLOT_COUNT = 3 };

/* ============================================================
 * 算法层（纯 C，无平台依赖）
 * ============================================================ */
void lk_sha256(const uint8_t *msg, int len, uint8_t out[32]);
void lk_hmac_sha256(const uint8_t *key, int key_len,
                    const uint8_t *msg, int msg_len, uint8_t out[32]);

/* base32 位流：MSB first，每字符 5 bit，末尾不足补 0 */
int  lk_b32_encode(const uint8_t *in, int in_len, char *out, int cap);
int  lk_b32_decode(const char *in, int in_len, uint8_t *out, int cap);

/* 到期时间 5 字符编解码（25 bit，单位「分钟」，起点 LK_EXP_EPOCH_MIN） */
void      lk_exp_encode(long long exp_min, char out[LK_EXP_CHARS]);
long long lk_exp_decode(const char *p);   /* 返回 -1 表示含非法字符 */

/* exp_min 与 UTC 秒的互转（epoch 只在这里出现，别处一律用 exp_min） */
long long lk_time_to_exp(double t);
double    lk_exp_to_time(long long exp_min);

/* ---------- 有效期单位（生成器选择用，校验端显示也用同一张表） ---------- */
typedef enum {
    LK_UNIT_MINUTE = 0,   /* 分钟 */
    LK_UNIT_HOUR,         /* 小时 */
    LK_UNIT_DAY,          /* 天   */
    LK_UNIT_MONTH,        /* 月（按 30 天） */
    LK_UNIT_YEAR,         /* 年（按 365 天） */
    LK_UNIT_COUNT
} lk_unit;

/* (单位, 数量) → 分钟。月按 30 天、年按 365 天，不做日历推算。
 * 单位越界 / 数量 <= 0 / 乘积超编码上限，均返回 -1。 */
long long lk_unit_to_minutes(int unit, long long amount);
/* 单位名（UTF-8 中文），越界返回 "" */
const char *lk_unit_name(int unit);

/* 剩余时间分段 —— 生成器列表和产品端 UI 共用同一套折算规则。
 * 把 remain_min 拆成"主单位 + 副单位"，供 UI 拼「还剩 1 年 2 个月」：
 *   >= 365 天 → 年 + 月
 *   >=  30 天 → 月 + 天
 *   >=   1 天 → 天
 *   >=   1 小时 → 小时
 *   否则       → 分钟
 * amount2/unit2 无副单位时置 0 / -1。remain_min <= 0 时主单位=分钟、数量=0。
 * 返回主单位编号（lk_unit）。 */
int lk_remain_split(long long remain_min, int *unit, long long *amount,
                    int *unit2, long long *amount2);

/* 报文： "<PID>|<UDID>|<expMin>" */
int lk_msg_build(char *out, int cap, const char *pid, const char *udid, long long exp_min);

/* 裸签名 r||s <-> DER（Apple 的 X962 算法要 DER，线上传输用定长裸签名） */
int lk_der_from_raw(const uint8_t raw[LK_RAWSIG_BYTES], uint8_t out[80]);
int lk_raw_from_der(const uint8_t *der, int der_len, uint8_t raw[LK_RAWSIG_BYTES]);

/* 码的规范化：去掉分隔符/空白、转大写、校验字符合法性。返回规范化后长度，<0 非法 */
int lk_code_normalize(const char *in, char *out, int cap);

/* 解析到期时间（不验签）。返回 0 成功 */
int lk_code_exp(const char *code, long long *exp_min);

/* 展示用分组（每 group 字符插一个 '-'）；校验前会被 lk_code_normalize 去掉 */
int lk_code_group(const char *code, char *out, int cap, int group);

/* Mode S：用内置密钥签发（生成器/CLI 用） */
int lk_code_make_s(const char *pid, const char *udid, long long exp_min, char *out, int cap);

/* Mode A：把 (到期时间, DER 签名) 编码成码 */
int lk_code_make_a(long long exp_min, const uint8_t *der, int der_len, char *out, int cap);

/* 验签（不判过期）。Mode S 用内置 HMAC，Mode A 走 env->ecdsa_verify。
 * LK_ACCEPT_MODE_S = 0 时直接拒收 16 位 Mode S 码（见 lk_config.h）。 */
int lk_code_verify(const lk_env *env, const char *code,
                   const char *pid, const char *udid, long long *exp_min);

/* 状态 blob："<hwmMin>|<code>.<sig8>" */
int lk_blob_make(char *out, int cap, const char *code, long long hwm_min, int rep);
int lk_blob_parse(const char *blob, long long *hwm_min, char *code, int code_cap, int rep);

/* ============================================================
 * 混淆层（lk_obf.c）
 * ============================================================ */
/* 组装 Mode S 码密钥（签发端与校验端都用同一份，与信誉分无关） */
void lk_assemble_key(uint8_t *out, int n);
/* 状态 blob 的签名密钥。与码密钥分开，且参与信誉分派生 ——
 * 这样即使有人把"信誉分判定"那一行 NOP 掉，已写下的状态也会因密钥对不上而解析失败。 */
void lk_state_key(uint8_t out[32], int rep);
/* ---------- 运行时字符串解密（见 加密混淆.md §3.3） ----------
 *
 * 源码里写 LK_S("明文") 或 LK_SB("明文", buf, cap)，构建前跑
 *   python tools/obf_strings.py transform <src> -o <out>
 * 把它们换成 lk_dec / lk_dec_into 调用 + 一份密文字节数组，明文就不会
 * 落在 __cstring 里（`strings` 搜不到）。
 *
 * 两个宏的分工：lk_dec() 共用单个 __thread 缓冲，同一条表达式里解两个串
 * 会互相覆盖（printf("%s %s", LK_S(a), LK_S(b)) 静默出错）。凡是要在一个
 * 表达式里解多个串，就用 LK_SB 自带缓冲 —— obf_strings.py 会检查并告警。
 *
 * 下面两个兜底宏只在【没跑变换】的开发期生效，让源码照样能编译；变换后的
 * 文件里不会再出现 LK_S/LK_SB，这两个宏就成了摆设。
 * 发布包必须跑变换：在适配层顶部写一行
 *   #define LK_STRINGS_OBF_REQUIRED 1
 * 就能让"忘跑变换"直接编译失败，而不是把明文悄悄带进发布包。 */
const char *lk_dec(const unsigned char *enc, size_t n);
char *lk_dec_into(const unsigned char *enc, size_t n, char *out, int cap);

#ifndef LK_S
#define LK_S(s) (s)
#endif

/* LK_SB 的开发期兜底。static inline 在头文件里不会产生符号，
 * 未被引用时编译器也不会报 unused（inline 函数的正常待遇）。 */
static inline char *lk_dev_copy(const char *s, char *buf, int cap) {
    int i = 0;
    if (buf && cap > 0) {
        while (s && s[i] && i + 1 < cap) { buf[i] = s[i]; i++; }
        buf[i] = 0;
    }
    return buf;
}
#ifndef LK_SB
#define LK_SB(s, buf, cap) lk_dev_copy((s), (buf), (cap))
#endif

#if defined(LK_STRINGS_OBF_REQUIRED) && !defined(LK_OBF_STRINGS_DONE)
#error "发布版必须先跑 tools/obf_strings.py 变换字符串（见 加密混淆.md §3.3）"
#endif

/* 反调试 / 完整性。全部返回"可疑"计数，0 = 干净 */
int lk_is_traced(void);
void lk_deny_attach(void);
int lk_suspicious_image(void);
int lk_entry_hooked(const void *fn);
uint64_t lk_self_hash(void);
int lk_self_intact(void);
int lk_reputation_default(void);
/* 构建后由 patch_selfhash.py 回填；放在 __DATA 段，不在被哈希范围内 */
extern volatile uint64_t g_lk_self_hash;
/* 版权声明（故意明文，见 加密混淆.md §8.2） */
const char *lk_copyright(void);

/* ---------- 原因码 ----------
 * 核心不产出任何用户可见文案（文案留在适配层，便于统一做字符串加密）。
 * 同一个 lk_status 会对应多个原因，适配层按原因码选文案。 */
typedef enum {
    LK_R_NONE = 0,        /* 通过 */
    LK_R_NO_ENV,          /* 适配层回调缺失 */
    LK_R_NO_UDID,         /* 取不到设备标识 */
    LK_R_ENV_SUSPECT,     /* 运行环境异常（完整性/反调试） */
    LK_R_STATE_TAMPERED,  /* 状态存储签名不符 */
    LK_R_CLOCK_ROLLBACK,  /* 系统时间被回拨（低于历史高水位/权威时间） */
    LK_R_CLOCK_EARLY,     /* 系统时间早于该码可能的签发日 → 回拨 */
    LK_R_EMPTY_INPUT,     /* 未输入 */
    LK_R_NOT_UNLOCKED,    /* 尚无有效解锁码 */
    LK_R_BAD_CODE,        /* 码格式/签名不对 */
    LK_R_STATE_BAD,       /* 状态里的码已失效 */
    LK_R_EXPIRED,         /* 已过期 */
    LK_R_INTERNAL,        /* 内部错误（解混淆/配置失败） */
} lk_reason;

/* ---------- 核心状态机（lk_core.c） ---------- */
/* 启动/进面板前校验。why 可传 NULL。 */
lk_status lk_check(const lk_env *env, lk_reason *why);
/* 用户提交解锁码 */
lk_status lk_submit(const lk_env *env, const char *input, lk_reason *why);
/* 只查本地状态：不联网、不写盘。给 UI 决定是否弹窗、显示到期时间用 */
lk_status lk_peek(const lk_env *env, long long *exp_min, lk_reason *why);
/* 清空三处状态（换码/退授权用） */
void lk_clear(const lk_env *env);

/* 功能密钥 —— 把授权"焊进"功能，而不是只返回一个可被 patch 的枚举。
 * 成功返回 0 并写入 32 字节密钥；未解锁/被篡改返回 -1（仍会写入一个
 * 确定性的无效密钥，不是全零）。
 *
 * 插件应该用它去解密自己的功能数据（坐标算法表、Hook 载荷、配置模板…），
 * 解不开就【静默不工作】。这样 patch 掉校验 = 功能数据解不开 = 插件是
 * "坏的"而不是"锁着的" —— 没有可以跳过的分支。
 * 密钥输入包含 自哈希 / 高水位 / 到期 / 信誉分，任一项被改都会变。 */
int lk_func_key(const lk_env *env, uint8_t out[32]);

/* 设备自检：返回 0 = 全部通过。report 逐项列出结果（cap 建议 >= 512） */
int lk_selftest(const lk_env *env, char *report, int cap);

/* ============================================================
 * 母本 IPA 解锁（dongle，见 lk_config.h §8.5）
 *
 * 母本检测是平台相关操作（iOS 上要枚举已装 App、读其二进制、算 __TEXT,__text
 * 哈希），因此核心不内置它，而是通过「可安装的回调」注入：
 *   适配层（dylib 初始化时）调用 lk_master_set_hash_fn() 装上 iOS 读取器，
 *   核心在需要时回调它拿母本代码段 SHA256；PC / 未安装读取器时回落为「未找到」
 *   （LK_MASTER_UNLOCK=0 时整套逻辑直接短路返回 LK_LOCKED，KAT 不受影响）。
 *
 * 回调约定：master_hash(bundle_id, out32, cap)
 *   成功把母本 __TEXT,__text 的 SHA256（32 字节）写入 out32，返回 32；
 *   找不到母本 / 读不到 / 解析失败返回 <= 0。
 * 预期哈希（OBF_32）由 lk_master.c 持有，与回调返回值做恒定时间比较。
 *
 * 为什么校验代码段而不是 plist token：重签（TrollStore/ldid）只改 __LINKEDIT
 * 里的签名，不动 __TEXT,__text 字节 → 哈希在签名前后稳定；且无法用同名空壳 App
 * 伪造。详见 加密混淆.md 与 lk_master.c / lk_master_ios.m 顶部注释。
 * ============================================================ */
typedef int (*lk_master_hash_fn)(const char *bundle_id, uint8_t *out32, int cap);
/* 安装 iOS 读取器（在 lk_master_ios.m 里定义）；传 NULL 复位为默认（必失败）桩 */
void lk_master_set_hash_fn(lk_master_hash_fn fn);
/* 预期母本 bundle id 的明文（调试或适配层用，运行时解密返回） */
const char *lk_master_bundle(void);
/* 母本 IPA 在场且完整（代码段哈希吻合）→ 返回 LK_UNLOCKED 并写 *exp_min（分钟）；否则 LK_LOCKED */
lk_status lk_master_verify(const lk_env *env, lk_reason *why, long long *exp_min);

/* ============================================================
 * 签发层（lk_issue.c）—— 生成器端用
 *
 * 单位换算（lk_unit_to_minutes / lk_unit_name）定义在上面「算法层」，
 * 签发端与校验端共用同一张表 —— 见那里的注释。
 * ============================================================ */

/* 算出发起签名的报文与到期时间（Mode A：把 msg 交给 SecKeyCreateSignature）。
 * valid_min 为有效期分钟数，超过 LK_MAX_VALIDITY_MIN 直接拒绝 —— 那种码装上去
 * 会被校验端判成「系统时间被回拨」，签了也用不了。 */
int lk_issue_prepare(const char *pid, const char *udid, long long valid_min, double now,
                     char *msg, int msg_cap, long long *exp_min);
/* Mode S 直接出码 */
int lk_issue_s(const char *pid, const char *udid, long long valid_min, double now,
               char *out, int cap, long long *exp_min);
/* Mode A：拿到 DER 后出码 */
int lk_issue_a(const char *pid, const char *udid, long long valid_min, double now,
               const uint8_t *der, int der_len, char *out, int cap, long long *exp_min);

#ifdef __cplusplus
}
#endif
#endif /* LK_H */