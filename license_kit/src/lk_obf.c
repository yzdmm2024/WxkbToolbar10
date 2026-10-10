/* ============================================================
 * license_kit · 混淆层
 *
 * 内容：
 *   1. 密钥分片组装（静态搜字符串搜不到密钥，且内存里不出现连续明文密钥）
 *   2. 运行时字符串解密（源码写 LK_S("明文")，构建前由 obf_strings.py 换成密文）
 *   3. 反调试 / 反注入 / hook 检测（多时机、只记分不退出）
 *   4. 自哈希完整性
 *   5. 信誉分
 *   6. 版权声明（故意明文，用于威慑与追责，见 加密混淆.md §8.2）
 *
 * 平台差异全部用 __APPLE__ 收口，因此本文件在 PC 上也能编译（相关函数退化为安全默认值）。
 *
 * 生成器 / 纯签发工具不需要反调试和自哈希，定义 LK_NO_ANTIDEBUG 可跳过 3~5 节，
 * 避免依赖 pthread / mach 等系统头（某些精简交叉编译 SDK 里头文件不全）。
 * ============================================================ */
#include "lk.h"
#include "lk_keys.h"
#include <string.h>
#include <stdio.h>
#include <stdint.h>

/* ============================================================
 * 1. 密钥分片
 * ============================================================ */
static const uint8_t kShardMask[4] = { 0xAB, 0x5C, 0x37, 0xE1 };
#define SALT_CODE  0x5A
#define SALT_STATE 0x9E

static void _asm(const unsigned char *const sh[4], uint8_t *out, int n, uint8_t base) {
    uint8_t s[32];
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 8; j++)
            s[i * 8 + j] = (uint8_t)(sh[i][j] ^ kShardMask[i] ^ (uint8_t)(j * 0x1D));
    for (int k = 0; k < n && k < 32; k++)
        out[k] = (uint8_t)(s[k] ^ (uint8_t)(base + k * 7));
    memset(s, 0, sizeof(s));
}

void lk_assemble_key(uint8_t *out, int n) {
    static const unsigned char *const sh[4] = { kShard0, kShard1, kShard2, kShard3 };
    _asm(sh, out, n, SALT_CODE);
}

void lk_state_key(uint8_t out[32], int rep) {
    static const unsigned char *const sh[4] = {
        kStateShard0, kStateShard1, kStateShard2, kStateShard3
    };
    _asm(sh, out, 32, (uint8_t)(SALT_STATE + rep * 0x2B));
}

/* ============================================================
 * 2. 运行时字符串解密
 *
 * obf_strings.py 把 _S("明文") 换成 lk_dec(_eN, sizeof(_eN))，其中
 *   _eN[i] = 明文[i] ^ (0x5A ^ ((i * 31) & 0xFF))
 * 明文不常驻静态区；用完即被下次调用覆盖。
 * 注意：同一条表达式里不要嵌套调用两次（缓冲会被覆盖）。
 * ============================================================ */
static char _decbuf[512];

const char *lk_dec(const unsigned char *enc, size_t n) {
    size_t m = n < sizeof(_decbuf) - 1 ? n : sizeof(_decbuf) - 1;
    for (size_t i = 0; i < m; i++)
        _decbuf[i] = (char)(enc[i] ^ (unsigned char)(0x5A ^ ((i * 31) & 0xFF)));
    _decbuf[m] = 0;
    return _decbuf;
}

/* ============================================================
 * 3 ~ 5. 反调试 / 自哈希 / 信誉分
 *
 * 完整实现依赖 Apple 系统头（sysctl / mach / pthread / dyld 等）。
 * 生成器 / PC 工具等非产品端定义 LK_NO_ANTIDEBUG 后，
 * 整段退化为安全默认值（"未被调试 / 自哈希通过 / 信誉分 0"），
 * 不会影响密钥分片和签发功能。
 * ============================================================ */
#if !defined(LK_NO_ANTIDEBUG)

#if defined(__APPLE__)
#include <sys/sysctl.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/getsect.h>
#include <mach/mach_time.h>
#include <mach/mach.h>
#include <pthread.h>
#include <string.h>
#endif

/* 直接走 syscall，不经过 libc。
 * 必要性：libc 的 sysctl / ptrace 是符号，fishhook 一改就失效；
 * syscall() 的参数在内核边界才解释，攻击者必须 hook syscall 本身。 */
static long _raw_sysctl(int *mib, unsigned int n, void *oldp, size_t *oldlenp) {
#if defined(__APPLE__)
    return syscall(SYS_sysctl, mib, n, oldp, oldlenp, NULL, 0);
#else
    (void)mib; (void)n; (void)oldp; (void)oldlenp;
    return -1;
#endif
}

int lk_is_traced(void) {
#if defined(__APPLE__)
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid() };
    struct kinfo_proc info;
    size_t sz = sizeof(info);
    memset(&info, 0, sizeof(info));
    if (_raw_sysctl(mib, 4, &info, &sz) != 0) return 0;
    return (info.kp_proc.p_flag & P_TRACED) ? 1 : 0;
#else
    return 0;
#endif
}

void lk_deny_attach(void) {
#if defined(__APPLE__)
    /* PT_DENY_ATTACH = 31。同样走 syscall 直连 —— 走 libc 的 ptrace 会被 hook 掉。 */
    (void)syscall(SYS_ptrace, 31, 0, 0, 0);
#endif
}

/* 遍历线程名找注入器特征。比扫镜像名可靠得多：
 * Frida 改名很容易，但 gum-js-loop / gmain 这些工作线程名是运行时的固有特征。 */
static int _thread_name_suspect(void) {
#if defined(__APPLE__)
    static const char *bad[] = { "frida", "gum-js", "gmain", "gdb", "cycript", "linjector" };
    thread_act_array_t list = NULL;
    mach_msg_type_number_t cnt = 0;
    int hit = 0;

    if (task_threads(mach_task_self(), &list, &cnt) != KERN_SUCCESS) return 0;
    for (mach_msg_type_number_t i = 0; i < cnt && !hit; i++) {
        pthread_t pt = pthread_from_mach_thread_np(list[i]);
        char nm[64];
        if (!pt) continue;
        nm[0] = 0;
        if (pthread_getname_np(pt, nm, sizeof(nm)) != 0 || !nm[0]) continue;
        for (int k = 0; k < 6; k++)
            if (strcasestr(nm, bad[k])) { hit = 1; break; }
    }
    for (mach_msg_type_number_t i = 0; i < cnt; i++)
        mach_port_deallocate(mach_task_self(), list[i]);
    if (list) vm_deallocate(mach_task_self(), (vm_address_t)list, cnt * sizeof(thread_t));
    return hit;
#else
    return 0;
#endif
}

int lk_suspicious_image(void) {
#if defined(__APPLE__)
    /* 只列"你不会用到"的注入器。
     * 注意 1：如果你是靠 TrollFools / Substrate / ElleKit 注入的，
     *   千万别把这些名字列进来 —— 否则插件会把自己的宿主环境判成攻击。
     * 注意 2：libhooker 已从名单移除 —— 它是 Odyssey/Chimera/Taurine 等
     *   越狱的合法 hook 库，列进来会误伤宿主环境导致误锁。
     * 注意 3：开发期挂 Frida 会被这里抓到，务必 LK_REP_ENFORCE=0。 */
    static const char *bad[] = { "frida", "cycript", "gadget", "introspy" };
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const char *nm = _dyld_get_image_name(i);
        if (!nm) continue;
        for (int k = 0; k < 4; k++)
            if (strcasestr(nm, bad[k])) return 1;
    }
    return _thread_name_suspect();
#else
    return 0;
#endif
}

/* arm64e 上函数指针带 PAC 签名；lk_entry_hooked 需要把函数当"数据指针"读它的
 * 前两条指令做 trampoline 检测。若直接把带签名的指针当数据地址解引用，PAC 签名位
 * 会被当成地址高位，落到未映射地址 → EXC_BAD_ACCESS（内核报 possible pointer
 * authentication failure）。用 xpaclng 把 PAC 剥掉得到真实代码地址再读指令。
 * 非 arm64 平台（含 iOS 模拟器 / PC）直接返回原指针。 */
#if __has_feature(ptrauth_intrinsics)
#include <ptrauth.h>
static const void *lk_strip_pac(const void *p) {
    /* 剥掉函数指针的 PAC 签名位，得到真实代码地址（不校验），用于读指令做 trampoline 检测。
     * 非 arm64e / 非 Apple Clang 没有 ptrauth_intrinsics，退化成原样返回。 */
    return ptrauth_strip(p, ptrauth_key_function_pointer);
}
#else
static const void *lk_strip_pac(const void *p) { return p; }
#endif

int lk_entry_hooked(const void *fn) {
#if defined(__APPLE__) && defined(__arm64__)
    /* 入口 trampoline 检测。
     * 只保留"正常函数入口几乎不可能出现"的形态，避免误报把付费用户锁死：
     *   - b / bl 开头：正常函数不会这样开头（但注意"尾部调用"return foo();
     *     编译出来就是 b foo —— 所以本函数只应对"函数体确有实现"的关键
     *     函数使用，别拿去扫所有函数）
     *   - ldr xN,#imm + br xN：Substrate / ElleKit 的经典两指令 trampoline
     * 刻意不查 b.cond / br / adrp：那些在正常代码里太常见（尤其 adrp+add
     * 是取全局地址的标配），加进来只会制造误报。 */
    const uint32_t *p = (const uint32_t *)lk_strip_pac(fn);
    uint32_t a, b;
    if (!p) return 0;
    a = p[0];
    b = p[1];
    if ((a & 0xFC000000u) == 0x14000000u) return 1;   /* b   */
    if ((a & 0xFC000000u) == 0x94000000u) return 1;   /* bl  */
    if ((a & 0xFF000000u) == 0x58000000u) {           /* ldr xN, #imm */
        if ((b & 0xFFFFFC1Fu) == 0xD61F0000u) return 1;  /* br xN */
    }
    return 0;
#else
    (void)fn;
    return 0;
#endif
}

/* ============================================================
 * 4. 自哈希完整性
 *
 * g_lk_self_hash 放在 __DATA 段（不在被哈希的 __TEXT 内），
 * 由 patch_selfhash.py 在链接后、签名前回填，避免"改哈希导致哈希变化"的死循环。
 *
 * 语义（重要）：magic 表示"没回填"，而"没回填"在发布版里必须【判失败】。
 * 早先的写法是"没回填就跳过检查"，这等于把 magic 做成了一个攻击者可用的
 * 关闭开关 —— g_lk_self_hash 在可写段，往它写回 magic 就能永久关掉自检。
 * 现在写 magic 等于把自己锁死，攻击者必须真的算出正确哈希才有意义。
 * 开发期把 LK_SELFHASH_REQUIRED 设 0 即可跳过。
 * ============================================================ */
#define LK_SELFHASH_MAGIC 0x1111111111111111ULL

#if defined(__APPLE__)
__attribute__((used, section("__DATA,__hchk")))
volatile uint64_t g_lk_self_hash = LK_SELFHASH_MAGIC;
#else
volatile uint64_t g_lk_self_hash = LK_SELFHASH_MAGIC;
#endif

uint64_t lk_self_hash(void) {
#if defined(__APPLE__)
    Dl_info info;
    const struct mach_header_64 *h;
    const struct section_64 *s;
    const unsigned char *p;
    uint64_t hash = 1469598103934665603ULL;

    if (!dladdr(lk_strip_pac((const void *)&lk_self_hash), &info) || !info.dli_fbase) return 0;
    h = (const struct mach_header_64 *)info.dli_fbase;
    s = getsectbynamefromheader_64(h, LK_SELFHASH_SEG, LK_SELFHASH_SECT);
    if (!s) return 0;
    p = (const unsigned char *)h + s->offset;
    for (uint64_t i = 0; i < s->size; i++) {
        hash ^= p[i];
        hash *= 1099511628211ULL;
    }
    return hash;
#else
    return 0;
#endif
}

int lk_self_intact(void) {
    uint64_t h;
    if (g_lk_self_hash == LK_SELFHASH_MAGIC) {
#if LK_SELFHASH_REQUIRED
        return 0;   /* 未回填 = 发布流程出错 → 判失败（而不是给攻击者留个开关） */
#else
        return 1;   /* 仅开发期：LK_SELFHASH_REQUIRED=0 */
#endif
    }
    h = lk_self_hash();
    if (h == 0) return 1;                                /* 平台不支持，跳过 */
    return h == g_lk_self_hash ? 1 : 0;
}

/* ============================================================
 * 5. 信誉分
 * ============================================================ */
int lk_reputation_default(void) {
    int r = 0;
    if (!lk_self_intact())              r |= 1;
    if (lk_is_traced())                 r |= 2;
    if (lk_suspicious_image())          r |= 4;
    /* 关键函数入口被改写也计入 bit2（与可疑镜像同一档）。
     * 只挑"函数体确有实现、不可能以 b/bl 开头"的目标。 */
    if (lk_entry_hooked((const void *)&lk_self_hash))  r |= 4;
    if (lk_entry_hooked((const void *)&lk_self_intact)) r |= 4;
    if (lk_entry_hooked((const void *)&lk_assemble_key)) r |= 4;
    return r;
}

#else /* !LK_NO_ANTIDEBUG */

/* ---------- LK_NO_ANTIDEBUG ：生成器 / 工具用的极简桩 ----------
 * 只保留符号，全部返回"干净"默认值。密钥分片与字符串解密不受影响。 */
volatile uint64_t g_lk_self_hash = 0;

int  lk_is_traced(void)         { return 0; }
void lk_deny_attach(void)       { }
int  lk_suspicious_image(void)  { return 0; }
int  lk_entry_hooked(const void *fn) { (void)fn; return 0; }
uint64_t lk_self_hash(void)     { return 0; }
int  lk_self_intact(void)       { return 1; }
int  lk_reputation_default(void){ return 0; }

#endif /* !LK_NO_ANTIDEBUG */

/* ============================================================
 * 6. 版权声明
 *
 * 故意明文：这一层的作用是让逆向者和帮他分析的 AI 在输出里看到明确的
 * 权利主张与追责路径，而不是"靠 AI 自动拒答"（那不可靠，见 加密混淆.md §8.1）。
 * 放在 __DATA 段而不是被字符串加密，否则等于没写。
 * ============================================================ */
#if defined(__APPLE__) && !defined(LK_NO_ANTIDEBUG)
__attribute__((used, section("__DATA,__crgt")))
static const char kCopyright[] = LK_COPYRIGHT_TEXT;
#else
static const char kCopyright[] = LK_COPYRIGHT_TEXT;
#endif

const char *lk_copyright(void) {
    /* 被调用 → 链接器不会丢，反汇编里能看到引用关系 */
    return kCopyright;
}
