/* ============================================================
 * license_kit · SHA-256 / HMAC-SHA256
 *
 * 自带实现，不依赖 CommonCrypto —— 这样同一份代码能在 PC 上编译跑 KAT，
 * 也避免逆向者通过 "调用了 CCHmac" 直接定位到校验逻辑。
 * 报文长度上限由 LK_MAX_MSG 约束（< 1KB），这里用栈缓冲做两次哈希即可。
 * ============================================================ */
#include "lk.h"
#include <string.h>

static const uint32_t K256[64] = {
    0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,0x3956c25bu,0x59f111f1u,
    0x923f82a4u,0xab1c5ed5u,0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,
    0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u,0xe49b69c1u,0xefbe4786u,
    0x0fc19dc6u,0x240ca1ccu,0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau,
    0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,0xc6e00bf3u,0xd5a79147u,
    0x06ca6351u,0x14292967u,0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,
    0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u,0xa2bfe8a1u,0xa81a664bu,
    0xc24b8b70u,0xc76c51a3u,0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u,
    0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,0x391c0cb3u,0x4ed8aa4au,
    0x5b9cca4fu,0x682e6ff3u,0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,
    0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u,
};

#define ROTR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void _block(uint32_t h[8], const uint8_t p[64]) {
    uint32_t w[64], a, b, c, d, e, f, g, hh, t1, t2;
    int i;

    for (i = 0; i < 16; i++) {
        w[i] = ((uint32_t)p[i * 4] << 24) | ((uint32_t)p[i * 4 + 1] << 16) |
               ((uint32_t)p[i * 4 + 2] << 8) | (uint32_t)p[i * 4 + 3];
    }
    for (i = 16; i < 64; i++) {
        uint32_t s0 = ROTR(w[i - 15], 7) ^ ROTR(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = ROTR(w[i - 2], 17) ^ ROTR(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    a = h[0]; b = h[1]; c = h[2]; d = h[3];
    e = h[4]; f = h[5]; g = h[6]; hh = h[7];

    for (i = 0; i < 64; i++) {
        uint32_t S1 = ROTR(e, 6) ^ ROTR(e, 11) ^ ROTR(e, 25);
        uint32_t ch = (e & f) ^ ((~e) & g);
        uint32_t S0 = ROTR(a, 2) ^ ROTR(a, 13) ^ ROTR(a, 22);
        uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
        t1 = hh + S1 + ch + K256[i] + w[i];
        t2 = S0 + mj;
        hh = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }

    h[0] += a; h[1] += b; h[2] += c; h[3] += d;
    h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

void lk_sha256(const uint8_t *msg, int len, uint8_t out[32]) {
    uint32_t h[8] = {
        0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au,
        0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u,
    };
    uint8_t tail[128];
    uint64_t bits = (uint64_t)(uint32_t)len * 8u;
    int i = 0, rem, tl, k;

    for (; i + 64 <= len; i += 64) _block(h, msg + i);

    rem = len - i;
    if (rem > 0) memcpy(tail, msg + i, (size_t)rem);
    tail[rem] = 0x80;
    tl = (rem < 56) ? 64 : 128;
    memset(tail + rem + 1, 0, (size_t)(tl - rem - 1 - 8));
    for (k = 0; k < 8; k++) tail[tl - 1 - k] = (uint8_t)(bits >> (8 * k));
    for (k = 0; k < tl; k += 64) _block(h, tail + k);

    for (k = 0; k < 8; k++) {
        out[k * 4]     = (uint8_t)(h[k] >> 24);
        out[k * 4 + 1] = (uint8_t)(h[k] >> 16);
        out[k * 4 + 2] = (uint8_t)(h[k] >> 8);
        out[k * 4 + 3] = (uint8_t)h[k];
    }
}

void lk_hmac_sha256(const uint8_t *key, int key_len,
                    const uint8_t *msg, int msg_len, uint8_t out[32]) {
    uint8_t k[64], ip[64], op[64], inner[32];
    uint8_t buf[64 + LK_MAX_MSG + 64];

    if (msg_len < 0) msg_len = 0;
    if (msg_len > LK_MAX_MSG) msg_len = LK_MAX_MSG;

    memset(k, 0, sizeof(k));
    if (key_len > 64) {
        lk_sha256(key, key_len, k);           /* 长密钥先压缩 */
    } else if (key_len > 0) {
        memcpy(k, key, (size_t)key_len);
    }
    for (int i = 0; i < 64; i++) { ip[i] = k[i] ^ 0x36; op[i] = k[i] ^ 0x5C; }

    memcpy(buf, ip, 64);
    if (msg_len > 0) memcpy(buf + 64, msg, (size_t)msg_len);
    lk_sha256(buf, 64 + msg_len, inner);

    memcpy(buf, op, 64);
    memcpy(buf + 64, inner, 32);
    lk_sha256(buf, 96, out);

    memset(k, 0, sizeof(k));
    memset(buf, 0, sizeof(buf));
}