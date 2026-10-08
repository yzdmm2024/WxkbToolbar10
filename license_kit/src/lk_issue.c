/* ============================================================
 * license_kit · 签发层（生成器 / 命令行用）
 *
 * 关键点：签发与校验共用 lk_alg.c 里的同一份算法，母本和产品端不可能算出不同的码。
 * Mode A 的私钥签名由调用方完成（iOS 用 SecKeyCreateSignature，PC 用 Python），
 * 本层只负责"算报文 + 把签名编码成码"。
 *
 * 有效期单位是「分钟」—— 与码里的到期字段同单位。生成器 UI 让用户选
 * 分钟/小时/天/月/年，先经 lk_unit_to_minutes 折成分钟再进来，这里不再换单位。
 * ============================================================ */
#include "lk.h"
#include <string.h>
#include <time.h>

/* 把 (有效期分钟, 当前时间) 折成绝对到期分钟数。
 * valid_min 超过 LK_MAX_VALIDITY_MIN 会被校验端判成「系统时间被回拨」，
 * 这里直接拒绝 —— 避免签出一张装上去就用不了的码。 */
int lk_issue_prepare(const char *pid, const char *udid, long long valid_min, double now,
                     char *msg, int msg_cap, long long *exp_min) {
    long long exp;
    if (valid_min <= 0 || valid_min > LK_MAX_VALIDITY_MIN) return -1;
    if (now <= 0) now = (double)time(NULL);
    exp = lk_time_to_exp(now) + valid_min;
    if (exp > LK_EXP_MAX) return -1;            /* 超出 25 bit 编码上限 */
    if (msg && msg_cap > 0) {
        if (lk_msg_build(msg, msg_cap, pid, udid, exp) < 0) return -1;
    }
    if (exp_min) *exp_min = exp;
    return 0;
}

int lk_issue_s(const char *pid, const char *udid, long long valid_min, double now,
               char *out, int cap, long long *exp_min) {
    long long exp = 0;
    if (lk_issue_prepare(pid, udid, valid_min, now, NULL, 0, &exp) != 0) return -1;
    if (lk_code_make_s(pid, udid, exp, out, cap) != LK_CODE_LEN_S) return -1;
    if (exp_min) *exp_min = exp;
    return 0;
}

int lk_issue_a(const char *pid, const char *udid, long long valid_min, double now,
               const uint8_t *der, int der_len, char *out, int cap, long long *exp_min) {
    long long exp = 0;
    if (lk_issue_prepare(pid, udid, valid_min, now, NULL, 0, &exp) != 0) return -1;
    if (lk_code_make_a(exp, der, der_len, out, cap) != LK_CODE_LEN_A) return -1;
    if (exp_min) *exp_min = exp;
    return 0;
}