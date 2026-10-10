/* ============================================================
 * license_kit · 编译期配置
 *
 * 换产品时只需要改这个文件（以及重新生成的 lk_keys.h）。
 * 载体差异不在这里 —— 载体差异全部落在适配层（lk_ios.m / 你自己的 main）。
 * ============================================================ */
#ifndef LK_CONFIG_H
#define LK_CONFIG_H

/* ---------- 1. 签名模式 ---------- */
/*
 * LK_MODE_A = 1  非对称（ECDSA P-256）—— 推荐，默认
 *   产品端只嵌公钥，即使 dylib 被完全逆向也无法伪造解锁码。
 *   代价：解锁码 108 位（必须复制粘贴）。
 *
 * LK_MODE_A = 0  对称（HMAC-SHA256）—— 母本生成器走的就是这条
 *   解锁码 16 位，可手打。代价：密钥在产品端，被提取后可为任意 UDID 造码。
 *
 * 两者不是互斥的：lk_code_verify 按码长自动分流（16 位走 S，108 位走 A）。
 * 想只吃 Mode A 的强度，把下面的 LK_ACCEPT_MODE_S 设成 0。
 */
#ifndef LK_MODE_A
#define LK_MODE_A 1
#endif

/* ---------- 2. 产品标识 ---------- */
/* 参与签名报文： "<PID>|<UDID>|<到期分钟>"。
 * 作用：即使两个产品用了同一把母本主密钥，A 产品的码也不能解锁 B 产品。
 * 每个产品取一个短标识，只能含 [A-Za-z0-9_-]。
 * 母本按 PID 派生各产品自己的密钥（见 lk_sign.py 的 product_key），
 * 所以一个产品被逆向出密钥，也伪造不出另一个产品的码。 */
#ifndef LK_PRODUCT_ID
#define LK_PRODUCT_ID "locsim"
#endif

/* ---------- 3. 时间策略 ---------- */
/* 时钟回拨容忍（秒）。
 *
 * 重要：这个值必须【远小于你卖出的最短有效期】。
 * 高水位按分钟存储，所以至少要 60s 覆盖取整；再给 NTP 校时留点余量，
 * 180s 足够。默认曾经是 3600（1 小时）—— 如果你卖的是 1 小时码，
 * 那等于把整整一小时的回拨余量白送出去。
 * 时区/夏令时不影响：全程用 UTC（time()），不需要为它们留余量。 */
#ifndef LK_CLOCK_TOL
#define LK_CLOCK_TOL 180
#endif

/* ---------- 3.5 签发日下界（离线防回拨的最后一道闸） ----------
 *
 * 问题：解锁码里只有「到期时间」。用户把三处状态全清掉（含 Keychain）再回拨系统时间，
 * 高水位就没了参照物，一个还没过期的旧码可以被无限期用下去。
 *
 * 解法：到期时间不可能早于签发时间。码里不带签发时间，就用「最长有效期」反推下界：
 *       设备时间 < 到期时间 - LK_MAX_VALIDITY_MIN - LK_NOTBEFORE_TOL_MIN  ⇒  判篡改。
 *
 * 代价（必须理解）：离线 + 全清数据的攻击者最多能把一张码多撑
 * LK_MAX_VALIDITY_MIN + LK_NOTBEFORE_TOL_MIN 分钟。所以把 MAX 设成「你会卖出的
 * 最长有效期」即可 —— 例如只卖年费就保持 366 天，攻击者撑死也就白嫖一年，
 * 和正价年费一致，没有套利空间。
 * 联网用户不受影响：校时拿到的权威时间会直接顶掉本地时间。
 *
 * 注意：这两个值只在这道闸里用，而这道闸只在【没有可信高水位】时才生效
 * （lk_submit 里 have_ref == 0：状态被清光 / 首次激活）。
 * 有高水位时时钟回拨由高水位负责，这里再插一脚只会误锁正版用户。 */
#ifndef LK_MAX_VALIDITY
#define LK_MAX_VALIDITY 366     /* 天；只卖小时级产品时改用下面的 MIN 写法 */
#endif
#ifndef LK_MAX_VALIDITY_MIN
#define LK_MAX_VALIDITY_MIN ((long long)LK_MAX_VALIDITY * LK_MIN_PER_DAY)
#endif

/* 往回容忍的量。它的实际含义是【你能接受多大的设备时钟偏慢】：
 * 一张合法码必然满足 到期 ≤ 签发 + MAX，代入下界公式化简后，
 * 这道闸只在「设备时间比签发时间早超过 TOL」时才触发。
 * 所以 TOL 同时是「时钟偏慢容忍度」和「攻击者可多嫖的量」—— 同一个旋钮的两面。 */
#ifndef LK_NOTBEFORE_TOL
#define LK_NOTBEFORE_TOL 2      /* 天 */
#endif
#ifndef LK_NOTBEFORE_TOL_MIN
#define LK_NOTBEFORE_TOL_MIN ((long long)LK_NOTBEFORE_TOL * LK_MIN_PER_DAY)
#endif

/* 内部一律用分钟比较 —— 与码里的到期字段同单位，避免来回换算出错。 */
#define LK_MIN_PER_DAY      1440LL

/* ---------- 3.55 只卖「小时级」产品怎么配 ----------
 *
 * 编译命令里加 -D 即可，不必改本文件：
 *   -DLK_MAX_VALIDITY_MIN=120    最长卖 2 小时（= 你会卖的最长有效期）
 *   -DLK_NOTBEFORE_TOL_MIN=60    容忍设备时钟慢 1 小时
 *   -DLK_CLOCK_TOL=180           高水位回拨容忍 3 分钟
 *
 * 为什么 TOL 要给 1 小时而不是 10 分钟：TOL 就是时钟偏慢的容忍度。
 * 刚开机没联网校时、跨时区、关掉「自动设置」的设备，时间慢几十分钟很常见；
 * 给 10 分钟等于把这些正常用户全判成篡改（永久锁死，而且他们无从知道原因）。
 * 代价是攻击者（清数据 + 回拨）最多多嫖 TOL —— 对 1 小时码是 3 倍，
 * 但那条路要求 root 去清 Keychain，能做到的人本来也能直接改二进制。
 *
 * 三个值必须一起改：只调小 MAX 会让长码被误判成回拨，只调小 TOL 会误锁时钟偏慢的用户。
 *
 * 注意：PC 端 KAT（tools/run_tests.ps1）里的向量用例是按默认的 1 年最长有效期生成的
 * （lk_keys.h 的自检向量、lk_testvec.h 都锚在 1 年上）。把 MAX 改成分钟级之后再跑 KAT，
 * 那几个向量用例会失败 —— 那是预期行为，不是回归；状态机用例（第 10 节）仍然全绿。 */

/* ---------- 3.6 续签语义（付费用户到期后换新码） ----------
 *
 * 到期后设备返回 LK_EXPIRED，UI 提示「请重新输入解锁码」；用户提交新码即可续期，
 * 不需要先清状态、不会丢任何东西。判据在 lk_submit：
 *
 *   新码到期时间 > 状态里那张码的到期时间  ⇒  认定为续签，允许它重置时钟参照
 *   否则                                  ⇒  按「旧码重放」处理，交给回拨判定
 *
 * 这条判据同时保住两件事：付费用户哪怕之前把系统时间调乱过（高水位落在未来）
 * 也能靠新码自救；而「过期码 + 回拨时钟」仍然进不来 —— 单看「码是否合法」分不出
 * 这两者，因为过期码在回拨后的时间点上同样合法。
 *
 * 发码时注意：有效期是【从签发时刻算起的绝对时间】，不是从首次激活算起。
 * 提前 30 分钟发一张 1 小时码，用户实际只能用 30 分钟。 */

/* ---------- 3.7 是否接受 16 位 Mode S 码 ----------
 * Mode A（非对称）的意义是「产品端只有公钥，逆向后也造不出码」。
 * 但只要产品端还肯收 16 位 Mode S 码，它就必然内嵌了对称密钥 ——
 * 密钥被提出来照样能造码，Mode A 的强度等于白送。
 *
 * 1 = 收（母本生成器签的就是 16 位码，默认）
 * 0 = 只收 107/108 位 Mode A 码（真正享受非对称强度；此时用 PC 端
 *     `lk_sign.py issue --mode a` 签发，或把母本也做成 Mode A）
 *
 * 注意：产品端 LK_MODE_A = 0 时必须保持 1，否则没有任何码能通过。 */
#ifndef LK_ACCEPT_MODE_S
#define LK_ACCEPT_MODE_S 1   /* 母本生成器签的就是 16 位 Mode S 码，必须收；否则 lk_code_verify 一律拒收、任何码都过不了 */
#endif
/* 待办（P0，需要配套改动才能翻）：改成 0 才能拿到 Mode A 的全部强度。
 * 但不能只翻这一行 —— 翻了之后所有已发出的 16 位码立刻失效，会批量锁死老用户。
 * 正确顺序：
 *   1. 生成器端改成 Mode A 签发（iOS：SecKeyCreateSignature + P-256 私钥，
 *      私钥进 Keychain/Secure Enclave；PC：lk_sign.py issue --mode a）
 *   2. 先发一版仍收 Mode S 的过渡包，让老用户把新码换成 108 位 Mode A 码
 *   3. 确认没有在用 Mode S 的用户后，再把这里设成 0 发布
 * 配合 lk_submit 的续签/恢复路径，换码过程不会把用户锁死。 */

/* 联网校时超时（毫秒）。产品启动校验用 6000，用户提交码时用 3000。 */
#ifndef LK_TIMEOUT_CHECK_MS
#define LK_TIMEOUT_CHECK_MS 6000
#endif
#ifndef LK_TIMEOUT_SUBMIT_MS
#define LK_TIMEOUT_SUBMIT_MS 3000
#endif

/* ---------- 4. 反调试信誉分是否参与判定 ---------- */
/*
 * 0 = 只记录，不影响解锁（最安全，不会误锁付费用户）
 * 1 = 自哈希不符才判失败（默认；正常用户不会触发）
 * 2 = 自哈希 + 被调试 + 关键函数被 hook 全部参与
 *
 * 注意：如果你用 TrollFools 之类「重签 + 注入」的方式分发，某些工具会改动
 * __TEXT，导致自哈希不符 → 误锁。上真机后先跑 lk_selftest()，
 * 看 report 里的 self_intact 是否为 1，不是就把这里改成 0。
 */
#ifndef LK_REP_ENFORCE
#define LK_REP_ENFORCE 1
#endif

/* ---------- 5. 自哈希取样段 ---------- */
/* 默认对 __TEXT,__text 取哈希。若你的重签工具会改这一段，改成 "__TEXT,__const"。 */
#ifndef LK_SELFHASH_SEG
#define LK_SELFHASH_SEG "__TEXT"
#endif
#ifndef LK_SELFHASH_SECT
#define LK_SELFHASH_SECT "__text"
#endif

/* ---------- 5.5 自哈希未回填时的行为 ----------
 * 1 = 判失败（发布版必须用这个）
 * 0 = 跳过检查（仅开发期用）
 *
 * 为什么不能「未回填就跳过」：g_lk_self_hash 在 __DATA 可写段，
 * 往它写回 magic 就能关掉整个自检 —— 那等于给攻击者留了个总开关。
 * 现在写 magic 只会把自己锁死，攻击者必须真的算出正确哈希。
 * 代价：忘了跑 patch_selfhash.py 就会自锁，所以发布流程必须固化这一步。 */
#ifndef LK_SELFHASH_REQUIRED
#define LK_SELFHASH_REQUIRED 1
#endif

/* ---------- 6. 存储槽位标识 ---------- */
/* 三处冗余存储。换产品必须换这三组 key，否则同一台设备上两个产品会互相覆盖。 */
#ifndef LK_STORE_KEY_UD
#define LK_STORE_KEY_UD "lsh_v2"
#endif
#ifndef LK_STORE_FILE
#define LK_STORE_FILE "lsh_v2.dat"
#endif
#ifndef LK_STORE_KEY_KC
#define LK_STORE_KEY_KC "lsh_v2"
#endif

/* ---------- 7. 可信时间源 ---------- */
/* 只读响应头里的 Date，不暴露任何自有服务器。可换成任意公开站点。 */
#ifndef LK_TIME_URL
#define LK_TIME_URL "https://captive.apple.com/hotspot-detect.html"
#endif

/* ---------- 8. 载体预设（只影响适配层默认行为） ---------- */
#define LK_CARRIER_IPA   1   /* TrollStore / 普通 App 沙盒 */
#define LK_CARRIER_DYLIB 2   /* 巨魔/越狱注入的 dylib */
#define LK_CARRIER_DEB   3   /* 越狱 deb 里的 dylib */
#ifndef LK_CARRIER
#define LK_CARRIER LK_CARRIER_DYLIB
#endif

/* 注入类载体里，授权状态该挂在哪个进程。
 * dylib 常被注入多个进程，若每个进程各写一份状态会「状态分裂」。
 * 1 = 只允许在 SpringBoard 里读写状态（推荐，状态唯一）
 * 0 = 谁都能读写（简单，但多个进程可能各自维护一份） */
#ifndef LK_STATE_HOST_ONLY
#define LK_STATE_HOST_ONLY 1
#endif
#ifndef LK_STATE_HOST
#define LK_STATE_HOST "SpringBoard"
#endif

/* ---------- 8.5 母本 IPA 解锁（dongle 模式，默认关闭） ----------
 *
 * 开启后，dylib 在「没有有效解锁码」时再兜底检查：设备上是否装着
 * 正版母本生成器（com.locsim.generator）且完整（其 __TEXT,__text 代码段
 * SHA256 与内置混淆哈希吻合）。装了即解锁，不落码状态，
 * 每次启动重判 —— 母本 App 本身就是钥匙。
 *
 * 设计要点（呼应 加密混淆.md）：
 *   - 校验母本 __TEXT,__text 代码段 SHA256（而非 plist token）：重签只改
 *     __LINKEDIT 里的签名，不动代码段字节 → 哈希稳定；同名空壳 App 无法复现。
 *   - 预期哈希以 lk_dec 同款 XOR 密文落盘（OBF_32），bundle id 同样加密，
 *     strings 搜不到明文哈希也搜不到 bundle id。改母本须重跑 emit_master_hash.py。
 *   - 环境洁净性由调用方经 _rep_used 把关，本函数再二次校验自哈希/调试，
 *     双重保险：任何「NOP 掉反调试/自哈希」的改动都会让这里判失败。
 *   - 检测走 iOS 读取器回调（LSApplicationWorkspace 枚举母本、读其二进制算哈希），
 *     核心不碰平台 API，PC/KAT 不受影响（默认返回「未找到」）。
 *
 * 风险（必须知道）：这是 dongle，不是绝对安全。拿到正版母本 IPA 的人
 * 能直接安装它来通过校验（这是预期行为——「我有母本即解锁」）；但光凭空壳
 * App 无法复现代码段哈希，伪造失效。它与解锁码体系互补，价值是
 * 「让正版母本成为必要条件 + 挡住普通复制传播」。 */
#ifndef LK_MASTER_UNLOCK
#define LK_MASTER_UNLOCK 0
#endif
#ifndef LK_MASTER_UNLOCK_DAYS
#define LK_MASTER_UNLOCK_DAYS 366   /* 仅用于 lk_peek 汇报「剩余」时长，不影响解锁本身 */
#endif

/* ---------- 9. 版权声明（字符串加密后仍会在反汇编里出现，用于威慑与追责） ---------- */
#define LK_COPYRIGHT_TEXT \
    "本程序为付费授权软件，仅供已授权设备使用。" \
    "未经许可的复制、传播、反编译、逆向工程及绕过授权验证，" \
    "均违反《中华人民共和国著作权法》及授权协议，作者保留追究法律责任的权利。"

#endif /* LK_CONFIG_H */