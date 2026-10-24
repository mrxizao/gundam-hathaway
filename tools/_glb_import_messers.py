# -*- coding: utf-8 -*-
"""一次性：把「梅萨指挥官型 / 梅萨F01型」两份 GLB 纳入工程，并修掉非 ASCII 名。

★ 纪律与 `_glb_import_xi_pod.py` 逐条相同：
  - **Desktop 原件一个字节都不动**，只改工程内的副本；
  - 改名只走 GLB 的 **JSON chunk**（纯文本），几何/BIN 一个字节不碰；
  - JSON 变长/变短靠重建 chunk 长度 + 4 字节空格填充解决。

★ 惯例（沿用工程既有的 `messer_m01_梅萨m01_tripo_part_N_basecolor`）：
  把中文前缀整体替换成资产前缀，**保留 `tripo_part_N` 这一段** ——
  这样 201 个贴图与 201 个零件的对应关系在改名后仍然读得出来。

⚠️ 命令行不放中文（本机纪律）：路径全部写在脚本内部。
"""
import hashlib
import json
import os
import shutil
import struct
import sys

sys.stdout.reconfigure(encoding="utf-8")

JOBS = [
    {
        "src": (r"C:\Users\MSIPC\Desktop\游戏\闪哈游戏\梅萨指挥官"
                r"\tripo_convert_2df28fa1-5745-4424-9be1-28ca33860e1f.glb"),
        "dir": r"C:\Users\MSIPC\Documents\gundam\assets\models\messer_cmd",
        "name": "messer_cmd",
    },
    {
        "src": (r"C:\Users\MSIPC\Desktop\游戏\闪哈游戏\梅萨F01"
                r"\tripo_convert_f369e9ab-4d8f-4d5d-9ac7-df3672b0ec84.glb"),
        "dir": r"C:\Users\MSIPC\Documents\gundam\assets\models\messer_f01",
        "name": "messer_f01",
    },
]

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


def strip_cn(s, prefix):
    """把名字里的中文段换成资产前缀，**保留 tripo_part_N 结构**。

    例：`机甲3d模型_tripo_part_0_basecolor` -> `messer_cmd_tripo_part_0_basecolor`

    ⚠️ **不能只按「非 ASCII 连续块」替换** —— 第一版就是那么写的，得到
    `messer_cmd3d_tripo_part_0_basecolor`：因为 `机甲3d模型` 里的 `3d`
    是 ASCII，被当成"要保留的原文"留了下来。
    ⇒ 正解是按**结构锚点 `_tripo_part_`** 切片：锚点之前的一切都是资产前缀，
      整段丢掉换新的；锚点之后逐字保留。
    """
    if s.isascii():
        return s, False
    anchor = "_tripo_part_"
    k = s.find(anchor)
    if k >= 0:
        return prefix + s[k:], True
    # 兜底：没有结构锚点的名字，整串换成序号名（并丢掉所有非 ASCII）
    t = "".join(ch for ch in s if ch.isascii())
    return t, True


def process(job):
    src, dst_dir, prefix = job["src"], job["dir"], job["name"]
    dst = os.path.join(dst_dir, prefix + ".glb")
    print("=" * 78)
    print("资产: %s" % prefix)
    os.makedirs(dst_dir, exist_ok=True)
    print("  原件 md5 : %s  (%s 字节)" % (md5(src), f"{os.path.getsize(src):,}"))
    # ★ **总是从原件重建**：本脚本是幂等的"复制 + 改名"，
    #   若沿用"已存在就不覆盖"的写法，改了改名规则之后重跑会原地不动、
    #   却打印出一份"看起来成功了"的报告（第一版就是这样骗过自己一次的）。
    shutil.copyfile(src, dst)
    print("  已从原件重建 -> %s" % dst)
    print("  副本与原件同源: %s" % ("是 ✅" if md5(src) == md5(dst) else "否 !!"))

    chunks = read_chunks(dst)
    js_bytes = [c for c in chunks if c[0] == CHUNK_JSON][0]
    js = json.loads(js_bytes[1].decode("utf-8"))

    # ---- 逐类扫描非 ASCII 名 ----
    counts = {}
    renamed = {}
    for key in ("images", "materials", "meshes", "nodes", "accessors"):
        bad = [o for o in js.get(key, []) if o.get("name") and not o["name"].isascii()]
        counts[key] = len(bad)
    print("  非 ASCII 名分布: %s" % counts)

    for key in ("images", "materials", "meshes", "nodes", "accessors"):
        for idx, o in enumerate(js.get(key, [])):
            nm = o.get("name")
            if nm and not nm.isascii():
                new, _ = strip_cn(nm, prefix)
                if not new:
                    new = "%s_%s_%d" % (prefix, key[:-1], idx)
                renamed["%s:%s" % (key, nm)] = new
                o["name"] = new
    # 材质若仍无名字，给个合规名（Godot 侧好看）
    for i, m in enumerate(js.get("materials", [])):
        if not m.get("name"):
            m["name"] = "%s_mat_%03d" % (prefix, i)

    print("  改了 %d 个名字；样例：" % len(renamed))
    for k in list(renamed)[:4]:
        print("    %s  ->  %s" % (k, renamed[k]))

    new_json = json.dumps(js, ensure_ascii=False,
                          separators=(",", ":")).encode("utf-8")
    for c in chunks:
        if c[0] == CHUNK_JSON:
            c[1] = new_json
    write_glb(dst, chunks)

    # ---- 复核 ----
    chunks2 = read_chunks(dst)
    js2 = json.loads([c for c in chunks2 if c[0] == CHUNK_JSON][0][1].decode("utf-8"))
    still = {}
    for key in ("images", "materials", "meshes", "nodes", "accessors"):
        still[key] = sum(1 for o in js2.get(key, [])
                         if o.get("name") and not o["name"].isascii())
    print("  复核 —— JSON chunk %d -> %d 字节" % (len(js_bytes[1]), len(new_json)))
    print("    残留非 ASCII 名: %s %s" % (still, "✅" if not any(still.values()) else "!!"))
    # ---- 几何必须逐项不变 ----
    m0_old = js["meshes"]
    m0_new = js2["meshes"]
    prim_old = sum(len(m["primitives"]) for m in m0_old)
    prim_new = sum(len(m["primitives"]) for m in m0_new)
    print("    meshes %d / primitives %d  ->  %d / %d  %s"
          % (len(m0_old), prim_old, len(m0_new), prim_new,
             "✅" if (len(m0_old), prim_old) == (len(m0_new), prim_new) else "!!"))
    tri = 0
    for m in js2["meshes"]:
        for p in m["primitives"]:
            tri += js2["accessors"][p["indices"]]["count"] // 3
    print("    三角数 %s（应与原件一致）" % f"{tri:,}")
    pos = js2["meshes"][0]["primitives"][0]["attributes"]["POSITION"]
    print("    accessor[POSITION].count(第 0 件) = %d"
          % js2["accessors"][pos]["count"])
    print("  新大小 %s 字节 | 新 md5 %s"
          % (f"{os.path.getsize(dst):,}", md5(dst)))


for j in JOBS:
    process(j)
