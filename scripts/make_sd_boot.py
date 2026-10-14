#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""
make_sd_boot.py - FLSun T1 Pro: build an SD-card boot image from the printer's OWN
eMMC boot partition (p3), so that the stock FLSun kernel mounts the root file system
from the SD card (/dev/mmcblk2p6) instead of the eMMC.

What it changes (nothing else):
  1. In every DTB inside the Rockchip "resource" image (RSCE), the kernel argument
       root=PARTUUID=614e0000-0000      ->   root=/dev/mmcblk2p6   (padded with spaces)
  2. The per-entry SHA1 of each patched DTB in the RSCE table
     (U-Boot rejects the DTB with "Invalid DTB hash" otherwise).
  3. The SHA256 of the "resource" sub-image in the FIT header.

The kernel, the FIT fdt and all other bytes stay identical. Every hash is verified
before it is replaced, so a file that is not a T1 Pro boot image is rejected.

Usage:
    python3 make_sd_boot.py boot_p3.img boot_sd.img
"""
import hashlib
import struct
import sys

OLD = b"root=PARTUUID=614e0000-0000"
NEW = b"root=/dev/mmcblk2p6".ljust(len(OLD), b" ")

FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def die(msg):
    sys.exit("ERROR: " + msg)


def parse_fit(buf):
    """Return {path: {prop: (offset_of_value, length)}} for the FIT header."""
    magic, totalsize, off_struct, off_strings = struct.unpack_from(">IIII", buf, 0)
    if magic != FDT_MAGIC:
        die("input is not a FIT image (bad magic)")
    props, path, p = {}, [], off_struct
    while True:
        (tok,) = struct.unpack_from(">I", buf, p)
        p += 4
        if tok == FDT_BEGIN_NODE:
            end = buf.index(b"\0", p)
            path.append(buf[p:end].decode())
            p = (end + 1 + 3) & ~3
        elif tok == FDT_END_NODE:
            path.pop()
        elif tok == FDT_PROP:
            length, nameoff = struct.unpack_from(">II", buf, p)
            p += 8
            nend = buf.index(b"\0", off_strings + nameoff)
            name = buf[off_strings + nameoff:nend].decode()
            props.setdefault("/".join(path), {})[name] = (p, length)
            p = (p + length + 3) & ~3
        elif tok == FDT_NOP:
            continue
        elif tok == FDT_END:
            return props
        else:
            die("corrupt FIT structure")


def u32(buf, node, prop):
    off, ln = node[prop]
    if ln != 4:
        die("unexpected size for " + prop)
    return struct.unpack_from(">I", buf, off)[0]


def main():
    if len(sys.argv) != 3:
        die("usage: make_sd_boot.py <boot_p3.img from eMMC> <output boot_sd.img>")
    src, dst = sys.argv[1], sys.argv[2]
    buf = bytearray(open(src, "rb").read())
    fit = parse_fit(buf)

    # check all three FIT sub-images first (proves the input is intact)
    for name in ("fdt", "kernel", "resource"):
        node = fit.get("/images/" + name)
        hnode = fit.get("/images/%s/hash" % name)
        if not node or not hnode:
            die("FIT image has no '%s' sub-image - not a T1 Pro boot partition?" % name)
        pos, size = u32(buf, node, "data-position"), u32(buf, node, "data-size")
        voff, vlen = hnode["value"]
        if vlen != 32 or hashlib.sha256(buf[pos:pos + size]).digest() != bytes(buf[voff:voff + 32]):
            die("SHA256 of FIT sub-image '%s' does not match - input damaged?" % name)
    print("FIT image OK (fdt, kernel, resource hashes verified)")

    rnode, rhash = fit["/images/resource"], fit["/images/resource/hash"]
    rpos, rsize = u32(buf, rnode, "data-position"), u32(buf, rnode, "data-size")
    if bytes(buf[rpos:rpos + 4]) != b"RSCE":
        die("resource sub-image is not a Rockchip RSCE image")
    hdr_blocks, tbl_off, ent_blocks = buf[rpos + 8], buf[rpos + 9], buf[rpos + 10]
    (count,) = struct.unpack_from("<I", buf, rpos + 12)

    patched = 0
    for i in range(count):
        e = rpos + (tbl_off + i * ent_blocks) * 512
        if bytes(buf[e:e + 4]) != b"ENTR":
            die("bad RSCE entry %d" % i)
        name = bytes(buf[e + 4:e + 224]).split(b"\0")[0].decode()
        hsize, blk, size = struct.unpack_from("<III", buf, e + 256)
        d0 = rpos + blk * 512
        data = bytes(buf[d0:d0 + size])
        algo = {20: hashlib.sha1, 32: hashlib.sha256}.get(hsize)
        if algo and algo(data).digest() != bytes(buf[e + 224:e + 224 + hsize]):
            die("hash of RSCE entry '%s' does not match - input damaged?" % name)
        if not name.endswith(".dtb"):
            continue
        n = data.count(OLD)
        if n == 0:
            if NEW in data:
                die("'%s' is already patched - use the ORIGINAL eMMC boot partition" % name)
            die("'%s' does not contain '%s'" % (name, OLD.decode()))
        new = data.replace(OLD, NEW)
        buf[d0:d0 + size] = new
        if algo:
            buf[e + 224:e + 224 + hsize] = algo(new).digest()
        patched += 1
        print("patched %-40s (%d x, entry hash updated)" % (name, n))
    if patched == 0:
        die("no DTB patched")

    voff, _ = rhash["value"]
    buf[voff:voff + 32] = hashlib.sha256(buf[rpos:rpos + rsize]).digest()
    open(dst, "wb").write(buf)
    print("FIT resource SHA256 updated")
    print("written: %s  sha256=%s" % (dst, hashlib.sha256(buf).hexdigest()))


if __name__ == "__main__":
    main()
