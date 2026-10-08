#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""patch_selfhash.py —— 回填 / 校验 lk_obf.c 的自哈希期望值

为什么需要它
------------
lk_obf.c 的 lk_self_intact() 会对本 dylib 的 __TEXT,__text 段做 FNV-1a，
再和 __DATA,__hchk 段里的 g_lk_self_hash 比对。期望值编译期只能先放一个
magic（0x1111111111111111），必须在【链接之后、签名之前】回填真实哈希。
放在 __DATA 而不是 __TEXT，就是为了避开「改哈希导致哈希变化」的死循环。

LK_SELFHASH_REQUIRED = 1 之后，忘了跑这一步的后果是【发布包直接自锁】，
不是「检查被跳过」。所以这一步必须固化进发布流程。

发布顺序（顺序错了会静默失效）
------------------------------
  1. 编译链接出 dylib / 可执行文件
  2. 一切会改动 load command 的后处理（注入 / strip / 加 LC_LOAD_DYLIB …）
  3. python patch_selfhash.py patch  <bin>     <- 本脚本
  4. 签名（ldid -S / TrollFools 注入时重签）
  5. python patch_selfhash.py verify <bin>     <- 发布前最后一道闸

第 2 步若挪到第 3 步之后：改 load command 会让 __text 的文件偏移整体平移，
回填过的哈希就对不上了，而且是静默失效。所以第 5 步不能省。

两个常量必须与 C 端一致
------------------------
FNV_OFFSET / FNV_PRIME 必须和 lk_obf.c 的 lk_self_hash() 逐位相同。
`kat` 用标准 FNV-1a 向量核对本脚本这一侧 —— 这也是唯一能自动发现
「C 端常量被人改过」的手段。

用法
----
  python patch_selfhash.py info   <bin>
  python patch_selfhash.py patch  <bin> [--out <copy>] [--force]
  python patch_selfhash.py verify <bin>
  python patch_selfhash.py kat
  可选：--seg __TEXT --sect __text          对应 lk_config.h 的 LK_SELFHASH_SEG/SECT
        --hchk-seg __DATA --hchk-sect __hchk
"""

import argparse
import struct
import sys

# ---------------------------------------------------------------- 常量
# 必须与 lk_obf.c 的 lk_self_hash() 一致
FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK64 = 0xFFFFFFFFFFFFFFFF
SELFHASH_MAGIC = 0x1111111111111111

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
LC_SEGMENT_64 = 0x19

CPU_NAMES = {0x0100000C: "arm64", 0x01000007: "x86_64", 0x0000000C: "arm"}

DEFAULT_SEG, DEFAULT_SECT = "__TEXT", "__text"
DEFAULT_HCHK_SEG, DEFAULT_HCHK_SECT = "__DATA", "__hchk"


def fnv1a64(data):
    h = FNV_OFFSET
    for b in data:
        h = ((h ^ b) * FNV_PRIME) & MASK64
    return h


class MachOError(Exception):
    pass


def _cstr(raw):
    return raw.split(b"\x00", 1)[0].decode("ascii", "replace")


class Section(object):
    __slots__ = ("seg", "sect", "addr", "size", "offset")

    def __init__(self, seg, sect, addr, size, offset):
        self.seg, self.sect = seg, sect
        self.addr, self.size, self.offset = addr, size, offset


class Slice(object):
    __slots__ = ("base", "cputype", "sections")

    def __init__(self, base, cputype, sections):
        self.base, self.cputype, self.sections = base, cputype, sections

    @property
    def cpu(self):
        return CPU_NAMES.get(self.cputype, "cpu=0x%08X" % self.cputype)


def _parse_thin(data, base):
    if base + 32 > len(data):
        raise MachOError("Mach-O 头越界（文件被截断？）")
    magic, cputype = struct.unpack_from("<Ii", data, base)
    if magic != MH_MAGIC_64:
        raise MachOError("不是 64 位小端 Mach-O（magic=0x%08X @0x%X）" % (magic, base))
    ncmds, sizeofcmds = struct.unpack_from("<II", data, base + 16)

    sections = []
    p = base + 32
    lc_end = p + sizeofcmds
    if lc_end > len(data):
        raise MachOError("load command 区越界")

    for _ in range(ncmds):
        if p + 8 > lc_end:
            raise MachOError("load command 越界")
        cmd, cmdsize = struct.unpack_from("<II", data, p)
        if cmdsize < 8 or p + cmdsize > lc_end:
            raise MachOError("load command 长度非法（cmd=0x%X size=%d）" % (cmd, cmdsize))
        if cmd == LC_SEGMENT_64:
            if cmdsize < 72:
                raise MachOError("segment_command_64 太短")
            nsects = struct.unpack_from("<I", data, p + 64)[0]
            sp = p + 72
            for _j in range(nsects):
                if sp + 80 > p + cmdsize:
                    raise MachOError("section_64 越界")
                sect = _cstr(data[sp:sp + 16])
                seg = _cstr(data[sp + 16:sp + 32])
                addr, size, offset = struct.unpack_from("<QQI", data, sp + 32)
                sections.append(Section(seg, sect, addr, size, offset))
                sp += 80
        p += cmdsize

    return Slice(base, cputype, sections)


def parse(data):
    """返回 [Slice]。支持 thin(64 位小端) 与 fat（含 fat_64）。"""
    if len(data) < 8:
        raise MachOError("文件太短，不是 Mach-O")
    be = struct.unpack_from(">I", data, 0)[0]
    if be in (FAT_MAGIC, FAT_MAGIC_64):
        is64 = (be == FAT_MAGIC_64)
        n = struct.unpack_from(">I", data, 4)[0]
        if not (1 <= n <= 64):
            raise MachOError("fat 头里的架构数不合理：%d" % n)
        ent = 32 if is64 else 20
        out = []
        for i in range(n):
            p = 8 + i * ent
            if p + ent > len(data):
                raise MachOError("fat_arch 越界")
            if is64:
                _ct, _cs, off, size = struct.unpack_from(">iiQQ", data, p)
            else:
                _ct, _cs, off, size = struct.unpack_from(">iiII", data, p)
            if off + size > len(data):
                raise MachOError("fat slice 越界")
            out.append(_parse_thin(data, off))
        return out
    return [_parse_thin(data, 0)]


def _find(secs, seg, sect):
    for s in secs:
        if s.seg == seg and s.sect == sect:
            return s
    return None


def _collect(raw, args):
    """定位每个 slice 的 __text 与 __hchk，算出应有哈希。"""
    out = []
    for sl in parse(raw):
        text = _find(sl.sections, args.seg, args.sect)
        if text is None:
            raise MachOError(
                "找不到 %s,%s —— 自哈希没有参照物。检查 LK_SELFHASH_SEG/SECT 配置"
                % (args.seg, args.sect))
        hchk = _find(sl.sections, args.hchk_seg, args.hchk_sect)
        if hchk is None:
            raise MachOError(
                "找不到 %s,%s —— 检查 lk_obf.c 里 g_lk_self_hash 的 "
                "__attribute__((used, section(\"%s,%s\"))) 是否还在。"
                "被 strip 掉或改掉段名，回填就无处可写。"
                % (args.hchk_seg, args.hchk_sect, args.hchk_seg, args.hchk_sect))
        if hchk.size < 8:
            raise MachOError("%s,%s 段只有 %d 字节，放不下 8 字节哈希"
                             % (args.hchk_seg, args.hchk_sect, hchk.size))
        if text.offset + text.size > len(raw):
            raise MachOError("%s,%s 的 offset/size 超出文件" % (args.seg, args.sect))
        if hchk.offset + 8 > len(raw):
            raise MachOError("%s,%s 的 offset 超出文件" % (args.hchk_seg, args.hchk_sect))
        want = fnv1a64(raw[text.offset:text.offset + text.size])
        cur = struct.unpack_from("<Q", raw, hchk.offset)[0]
        out.append((sl, text, hchk, want, cur))
    return out


def _load(path):
    try:
        with open(path, "rb") as f:
            return bytearray(f.read())
    except OSError as e:
        raise MachOError("读不了 %s：%s" % (path, e))


# ---------------------------------------------------------------- 子命令
def cmd_info(args):
    raw = _load(args.bin)
    for sl, text, hchk, want, cur in _collect(raw, args):
        print("slice %s @0x%X" % (sl.cpu, sl.base))
        print("  %-18s off=0x%-8X size=0x%-8X  FNV-1a = 0x%016X"
              % ("%s,%s" % (text.seg, text.sect), text.offset, text.size, want))
        print("  %-18s off=0x%-8X size=0x%-8X  当前值 = 0x%016X  %s"
              % ("%s,%s" % (hchk.seg, hchk.sect), hchk.offset, hchk.size, cur,
                 _state(cur, want)))
    return 0


def _state(cur, want):
    if cur == want:
        return "(已回填，与当前 __text 一致)"
    if cur == SELFHASH_MAGIC:
        return "(还是 magic —— 未回填，发布版会自锁)"
    return "(与当前 __text 不符 —— 回填后又改过 __text/load command？)"


def cmd_patch(args):
    raw = _load(args.bin)
    items = _collect(raw, args)

    changed = False
    for sl, _text, hchk, want, cur in items:
        if cur == want:
            print("  %-8s 已是目标值 0x%016X，无需改动" % (sl.cpu, want))
            continue
        if cur != SELFHASH_MAGIC and not args.force:
            raise MachOError(
                "%s 的 __hchk 里既不是 magic 也不是目标哈希（当前 0x%016X）——\n"
                "        可能已经跑过一遍、或者这个二进制不是这套源码编出来的。\n"
                "        确认无误再加 --force 覆盖。" % (sl.cpu, cur))
        struct.pack_into("<Q", raw, hchk.offset, want)
        changed = True
        print("  %-8s __text FNV-1a = 0x%016X  -> 已回填" % (sl.cpu, want))

    if not changed:
        return 0

    out = args.out or args.bin
    with open(out, "wb") as f:
        f.write(bytes(raw))
    if args.out:
        print("  已写出 %s（原文件未改动）" % args.out)
    print("  提示：__DATA 已改动，现有代码签名失效，必须重签"
          "（ldid -S / TrollFools 注入时重签），然后跑 verify 复查。")
    return 0


def cmd_verify(args):
    raw = _load(args.bin)
    bad = 0
    for sl, _text, _hchk, want, cur in _collect(raw, args):
        if cur == want:
            print("  %-8s OK   0x%016X" % (sl.cpu, cur))
        else:
            bad += 1
            print("  %-8s FAIL 期望 0x%016X，实际 0x%016X  %s"
                  % (sl.cpu, want, cur, _state(cur, want)))
    if bad:
        print("RESULT: FAIL —— 这个包装上去会自锁，别发布")
        return 1
    print("RESULT: OK")
    return 0


def cmd_kat(args):
    vec = [(b"", 0xCBF29CE484222325), (b"a", 0xAF63DC4C8601EC8C)]
    bad = 0
    for data, want in vec:
        got = fnv1a64(data)
        ok = (got == want)
        bad += not ok
        print("  fnv1a64(%-4r) = 0x%016X  %s" % (data, got, "PASS" if ok else "FAIL 期望 0x%016X" % want))
    print("  FNV_OFFSET = 0x%016X   FNV_PRIME = 0x%X" % (FNV_OFFSET, FNV_PRIME))
    print("  这两个值必须和 lk_obf.c 的 lk_self_hash() 逐位相同")
    print("RESULT: %s" % ("FAIL" if bad else "OK"))
    return 1 if bad else 0


# ---------------------------------------------------------------- 入口
def main(argv):
    try:
        sys.stdout.reconfigure(errors="replace")
    except Exception:
        pass

    ap = argparse.ArgumentParser(
        description="回填 / 校验 lk_obf.c 的自哈希期望值",
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")

    def add_common(p):
        p.add_argument("--seg", default=DEFAULT_SEG, help="被哈希的段名（默认 __TEXT）")
        p.add_argument("--sect", default=DEFAULT_SECT, help="被哈希的节名（默认 __text）")
        p.add_argument("--hchk-seg", default=DEFAULT_HCHK_SEG, help="存放哈希的段（默认 __DATA）")
        p.add_argument("--hchk-sect", default=DEFAULT_HCHK_SECT, help="存放哈希的节（默认 __hchk）")

    p = sub.add_parser("info", help="只读：打印段表位置与当前哈希")
    p.add_argument("bin")
    add_common(p)

    p = sub.add_parser("patch", help="回填真实哈希")
    p.add_argument("bin")
    p.add_argument("--out", help="写到副本，不动原文件")
    p.add_argument("--force", action="store_true", help="覆盖非 magic 的既有值")
    add_common(p)

    p = sub.add_parser("verify", help="校验（发布前最后一道闸）")
    p.add_argument("bin")
    add_common(p)

    sub.add_parser("kat", help="核对本脚本的 FNV-1a 常量")

    args = ap.parse_args(argv)
    if not args.cmd:
        ap.print_help()
        return 2

    try:
        return {"info": cmd_info, "patch": cmd_patch,
                "verify": cmd_verify, "kat": cmd_kat}[args.cmd](args)
    except MachOError as e:
        print("错误：%s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))