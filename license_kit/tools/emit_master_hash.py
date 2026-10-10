#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""emit_master_hash.py —— 计算母本 IPA 二进制的 __TEXT,__text 段 SHA256，
并用 license_kit 的 lk_dec 同款 XOR 混淆为 C 字节数组（OBF_32）。

为什么校验代码段而不是 Info.plist：
  - 用户明确「不碰母本 IPA、只加 dylib 端验证与混淆」。
  - 重签（TrollStore / ldid）只改 __LINKEDIT 里的签名，不动 __TEXT,__text 的字节，
    所以代码段 SHA256 在签名前后稳定 —— 这是可靠的 dongle 指纹。
  - 比"读 Info.plist 里的明文 token"强得多：伪造同名空壳 App 无法复现代码段哈希。

用法：
  python emit_master_hash.py [母本二进制路径]
  不传参则用下面 DEFAULT_PATH（改成你自己的母本位置）。

输出：原始 SHA256 十六进制 + 混淆后的 32 字节 C 数组（粘进 lk_master.c 的
kMasterTextHashEnc[] 即可），并做 roundtrip 自校验。
"""
import sys
import hashlib

# 默认母本二进制（locsim_gen）。改这里或命令行传参。
DEFAULT_PATH = r"C:/Users/10131/Desktop/我自己写的插件/验证的逻辑/码生成器/locsim_gen/Payload/locsim.app/locsim_gen"

# CPU_TYPE_ARM64
CPU_TYPE_ARM64 = 0x0100000C
# LC_SEGMENT_64
LC_SEGMENT_64 = 0x19


def rd32(b, o, le):
    return int.from_bytes(b[o:o + 4], "little" if le else "big")


def rd64(b, o, le):
    return int.from_bytes(b[o:o + 8], "little" if le else "big")


def find_text(buf):
    """返回母本二进制里 __TEXT,__text 段的 (file_offset, size)，找不到返回 None。
    支持单 arch arm64 与 fat/universal（挑第一个 arm64 切片）。"""
    if len(buf) < 4:
        return None
    m0 = rd32(buf, 0, True)
    m1 = rd32(buf, 0, False)
    le = None
    for cand, is_le in ((m0, True), (m1, False)):
        if cand in (0xfeedfacf, 0xcffaedfe, 0xcafebabe, 0xbebafeca,
                    0xcafebabf, 0xbfbafeca):
            le = is_le
            break
    if le is None:
        return None

    mag = rd32(buf, 0, le)
    # fat / universal
    if mag in (0xcafebabe, 0xcafebabf):
        is64 = (mag == 0xcafebabf)
        nfat = rd32(buf, 4, le)
        for i in range(nfat):
            base = 8 + i * (32 if is64 else 20)
            cputype = rd32(buf, base, le)
            if is64:
                off = rd64(buf, base + 8, le)
                size = rd64(buf, base + 16, le)
            else:
                off = rd32(buf, base + 8, le)
                size = rd32(buf, base + 12, le)
            if cputype == CPU_TYPE_ARM64:
                sub = buf[off:off + size]
                r = find_text(sub)
                if r:
                    return r
        return None
    # thin 64-bit
    if mag in (0xfeedfacf, 0xcffaedfe):
        ncmds = rd32(buf, 16, le)
        off = 32  # sizeof(mach_header_64)
        for _ in range(ncmds):
            cmd = rd32(buf, off, le)
            cmdsize = rd32(buf, off + 4, le)
            if cmd == LC_SEGMENT_64:
                segname = buf[off + 8:off + 24].split(b"\x00")[0].decode("ascii", "replace")
                nsects = rd32(buf, off + 64, le)
                sect_base = off + 72
                for s in range(nsects):
                    so = sect_base + s * 80
                    sectname = buf[so:so + 16].split(b"\x00")[0].decode("ascii", "replace")
                    segname2 = buf[so + 16:so + 32].split(b"\x00")[0].decode("ascii", "replace")
                    size = rd64(buf, so + 40, le)
                    fileoff = rd32(buf, so + 48, le)
                    if segname2 == "__TEXT" and sectname == "__text":
                        return (fileoff, size)
            off += cmdsize
    return None


def obf(p):
    """lk_dec 同款 XOR：e[i] = p[i] ^ (0x5A ^ ((i * 31) & 0xFF))。"""
    return bytes(p[i] ^ (0x5A ^ ((i * 31) & 0xFF)) for i in range(len(p)))


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PATH
    try:
        with open(path, "rb") as f:
            buf = f.read()
    except OSError as e:
        print("ERROR: 无法读取母本二进制: %s" % e)
        sys.exit(1)

    r = find_text(buf)
    if not r:
        print("ERROR: 未在 %s 中找到 __TEXT,__text 段" % path)
        sys.exit(1)
    off, size = r
    if size <= 0 or off + size > len(buf):
        print("ERROR: __text 段范围非法 off=%d size=%d buflen=%d" % (off, size, len(buf)))
        sys.exit(1)

    seg = buf[off:off + size]
    raw = hashlib.sha256(seg).digest()
    ob = obf(raw)

    print("file:            %s" % path)
    print("__text offset:   %d" % off)
    print("__text size:     %d" % size)
    print("SHA256(__text):  %s" % raw.hex())
    print("OBF_32 (%d B):   %s" % (len(ob), ", ".join("0x%02X" % b for b in ob)))
    print("roundtrip OK:    %s" % (obf(ob) == raw))
    print()
    print("/* ---- 粘进 lk_master.c 的 kMasterTextHashEnc[] ---- */")
    print("static const unsigned char kMasterTextHashEnc[32] = {")
    print("    " + ", ".join("0x%02X" % b for b in ob) + "")
    print("};")


if __name__ == "__main__":
    main()
