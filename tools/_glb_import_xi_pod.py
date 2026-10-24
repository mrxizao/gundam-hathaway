# -*- coding: utf-8 -*-
"""一次性：把「柯西收纳仓」GLB 纳入工程资产目录，并修掉非 ASCII 贴图名。

★ 纪律：**原件（桌面）一个字节都不动**，只改工程内的副本。
★ 改名走 GLB 的 JSON chunk（纯文本改名），几何/BIN 一个字节不碰；
  JSON 变长/变短都靠重建 chunk 长度 + 4 字节空格填充解决。
"""
import hashlib
import json
import os
import shutil
import struct
import sys

sys.stdout.reconfigure(encoding="utf-8")

SRC = (r"C:\Users\MSIPC\Desktop\游戏\闪哈游戏\柯西收纳仓"
       r"\tripo_convert_5d0a550f-7f1c-4e20-99a7-18c5af291979.glb")
DST_DIR = r"C:\Users\MSIPC\Documents\gundam\assets\models\xi_pod"
DST = os.path.join(DST_DIR, "xi_pod.glb")

CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942
MAGIC = 0x46546C67


def md5(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def read_chunks(path):
    d = open(path, "rb").read()
    magic, ver, declared = struct.unpack_from("<3I", d, 0)
    assert magic == MAGIC and declared == len(d), "不是正常的 glb"
    off, chunks = 12, []
    while off + 8 <= len(d):
        clen, ctype = struct.unpack_from("<2I", d, off)
        off += 8
        chunks.append([ctype, d[off:off + clen]])
        off += clen
    return chunks


def write_glb(path, chunks):
    body = b""
    for ctype, payload in chunks:
        pad = (4 - len(payload) % 4) % 4
        filler = b" " if ctype == CHUNK_JSON else b"\x00"
        p = payload + filler * pad
        body += struct.pack("<2I", len(p), ctype) + p
    with open(path, "wb") as f:
        f.write(struct.pack("<3I", MAGIC, 2, 12 + len(body)) + body)


# ---------------------------------------------------------------- 1) 入库
os.makedirs(DST_DIR, exist_ok=True)
print("原件 md5 : %s  (%s 字节)" % (md5(SRC), f"{os.path.getsize(SRC):,}"))
if os.path.exists(DST):
    print("工程内已存在，不覆盖 ->", DST)
else:
    shutil.copyfile(SRC, DST)
    print("已复制 ->", DST)
print("副本与原件同源: %s" % ("是 ✅" if md5(SRC) == md5(DST) else "否 !!"))

# ---------------------------------------------------------------- 2) 改中文名
chunks = read_chunks(DST)
js_bytes = [c for c in chunks if c[0] == CHUNK_JSON][0]
js = json.loads(js_bytes[1].decode("utf-8"))

RENAME = {}
for i, im in enumerate(js.get("images", [])):
    nm = im.get("name", "")
    if nm and not nm.isascii():
        new = "xi_pod_basecolor" if i == 0 else "xi_pod_tex_%03d" % i
        RENAME[nm] = new
        im["name"] = new
for m in js.get("materials", []):          # 材质名同步（若有指向贴图的中文名）
    if m.get("name") and not m["name"].isascii():
        RENAME[m["name"]] = "xi_pod_mat"
        m["name"] = "xi_pod_mat"

print("\n改名: %s" % (RENAME if RENAME else "(无需改)"))

new_json = json.dumps(js, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")
for c in chunks:
    if c[0] == CHUNK_JSON:
        c[1] = new_json
write_glb(DST, chunks)

# ---------------------------------------------------------------- 3) 复核
chunks2 = read_chunks(DST)
js2 = json.loads([c for c in chunks2 if c[0] == CHUNK_JSON][0][1].decode("utf-8"))
bin_len_before = len(js_bytes[1])
print("\n复核:")
print("  JSON chunk: %s -> %s 字节" % (bin_len_before, len(new_json)))
print("  images    : %s" % [im.get("name") for im in js2.get("images", [])])
print("  materials : %s" % [m.get("name") for m in js2.get("materials", [])])
print("  nodes     : %s" % [n.get("name") for n in js2.get("nodes", [])])
print("  网格/图元/顶点/三角 应与原件一致:")
mq = js2["meshes"][0]
print("    mesh name=%s primitives=%d  attrs=%s"
      % (mq.get("name"), len(mq["primitives"]),
         list(mq["primitives"][0]["attributes"].keys())))
print("  accessor[POSITION].count = %d"
      % js2["accessors"][mq["primitives"][0]["attributes"]["POSITION"]]["count"])
print("  新文件大小: %s 字节" % f"{os.path.getsize(DST):,}")
print("  新 md5    : %s" % md5(DST))
