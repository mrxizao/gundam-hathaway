# -*- coding: utf-8 -*-
"""「运输仓装得下柯西吗」—— 按柯西的**真实顶点云**（不是包围盒）逐点判。

★ 为什么不能用包围盒 / 不能直接 import 柯西，先记下两次踩空：
  ① 用**包围盒**当机体形状 ⇒ 要 k = 100.48 才「装得下」。机甲的四个角是空的，
     这是**把空气也算进去**的过度保守口径。
  ② `bpy.ops.import_scene.gltf(xi_fly.glb)` 量顶点 ⇒ 量到 **1.90212 × 2.00 × 2.00**，
     而工程口径是 **0.72802 × 0.98145 × 0.75877**。根因：`xi_fly.glb` 带
     **`skins=1`**（203 个蒙皮件 + `fly` 动画），Blender 导入时**把骨架的 rest 姿态
     蒙皮上去了**，形状被撑开 ⇒ 读数不可用。**带骨架的 glb 别用 Blender 量顶点。**
     ⇒ 正确做法：**直接解 glb 的 POSITION accessor**（原始顶点云 = 组装好的机体），
       再 × `28.0/0.98145 = 28.529` 换到工程口径的米数。
       对照：raw × 28.529 = (20.77, 28.00, 21.65) —— 与 `XI_BOX` **逐位一致** ✓
  ③ 单位别写反：要把**柯西**换算到**仓自身的空间**，除数是 `k`
     （`p_pod = p_world / k`）。第一版写成了「柯西 × k」⇒ k=90 仍 0% 在内。

判据：`r <= R_worst(theta)`，其中 `R(x, theta)` 是**从仓轴心向外打射线、记第一次命中**
得到的外缘半径图。⚠️ 筒壁**不是圆的**（中段外缘半径 min/max ≈ **0.761**），
所以「AABB 半宽当半径」会高估 ⇒ 必须按真实外缘算，本脚本会把该不对称量打出来。

用法：
    blender.exe --background --factory-startup --python tools/pod_fit_check.py

`k` 的真源在 `scripts/world/world_builder.gd`（`POD_FIT_MIN` / `POD_CLEARANCE`），
本脚本**直接从那里读**，不另存一份 —— 否则工具会漂成第二个真源。
"""
import json
import math
import os
import re
import struct
import sys
import time

import bpy
import numpy as np
from mathutils.bvhtree import BVHTree

sys.stdout.reconfigure(encoding="utf-8")

# ---------------- 路径与 k 的真源 ----------------
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POD = os.path.join(ROOT, "assets", "models", "xi_pod", "xi_pod.glb")
XI = os.path.join(ROOT, "assets", "models", "xi", "xi_fly.glb")
WB = os.path.join(ROOT, "scripts", "world", "world_builder.gd")
POD_SIZE = np.array([0.97977, 0.40694, 0.45036])
XI_TARGET_H = 28.0

_gsrc = open(WB, "r", encoding="utf-8").read()


def _const(name):
    m = re.search(r"^const %s := ([0-9.]+)$" % name, _gsrc, re.M)
    assert m, "world_builder.gd 里找不到 %s" % name
    return float(m.group(1))


def _const_opt(name):
    m = re.search(r"^const %s := ([0-9.]+)$" % name, _gsrc, re.M)
    return None if m is None else float(m.group(1))


FIT_MIN = _const("POD_FIT_MIN")
CLEARANCE = _const("POD_CLEARANCE")
SHIPPED_K = FIT_MIN * CLEARANCE
print("从 world_builder.gd 读到：POD_FIT_MIN = %.2f  POD_CLEARANCE = %.3f"
      " ⇒ 工程当前 POD_SCALE = %.3f" % (FIT_MIN, CLEARANCE, SHIPPED_K))


# ---------------- 纯 Python 解 xi_fly.glb 的 POSITION ----------------
def glb_chunks(p):
    d = open(p, "rb").read()
    assert struct.unpack_from("<I", d, 0)[0] == 0x46546C67
    off, js, bn = 12, None, None
    while off + 8 <= len(d):
        ln, ty = struct.unpack_from("<2I", d, off)
        body = d[off + 8:off + 8 + ln]
        if ty == 0x4E4F534A:
            js = json.loads(body.decode("utf-8"))
        elif ty == 0x004E4942:
            bn = body
        off += 8 + ln
    return js, bn


g, bin_ = glb_chunks(XI)


def acc_floats(ai):
    a = g["accessors"][ai]
    bv = g["bufferViews"][a["bufferView"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    n = a["count"]
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    assert a["componentType"] == 5126, a["componentType"]
    return np.frombuffer(bin_, dtype="<f4", count=n * ncomp, offset=off).reshape(n, ncomp)


verts = []
for m in g["meshes"]:
    for pr in m["primitives"]:
        verts.append(acc_floats(pr["attributes"]["POSITION"]))
XI_RAW = np.vstack(verts).astype(np.float64)
raw_lo, raw_hi = XI_RAW.min(axis=0), XI_RAW.max(axis=0)
print("柯西 raw POSITION 顶点 %d 个  包围盒跨度 %s（Y = 身高轴）"
      % (len(XI_RAW), np.round(raw_hi - raw_lo, 5)))
S = XI_TARGET_H / float(raw_hi[1] - raw_lo[1])
XI_M = (XI_RAW - (raw_lo + raw_hi) * 0.5) * S
print("  x %.3f 换算到工程口径 ⇒ AABB %s  （应为 20.77 x 28.00 x 21.65）"
      % (S, np.round(XI_M.max(axis=0) - XI_M.min(axis=0), 3)))
XV = XI_M                                   # (n,3)，Y = 身高

# ---------------- 仓的外缘半径图 ----------------
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=POD)
pod_obj = [o for o in bpy.data.objects if o not in before and o.type == "MESH"][0]
dg = bpy.context.evaluated_depsgraph_get()
bvh = BVHTree.FromObject(pod_obj, dg)
pme = pod_obj.data
pn = len(pme.vertices)
pc = np.empty(pn * 3, dtype=np.float32)
pme.vertices.foreach_get("co", pc)
pw = np.c_[pc.reshape(pn, 3).astype(np.float64), np.ones(pn)] @ np.array(pod_obj.matrix_world).T
plo, phi = pw[:, :3].min(axis=0), pw[:, :3].max(axis=0)
CX = float((plo[0] + phi[0]) * 0.5)
print("仓顶点 %d 个  AABB 跨度 %s   长轴中心 x=%.5f" % (pn, np.round(phi - plo, 5), CX))

WIN, NX, NT = 0.25, 121, 720
XS = np.linspace(CX - WIN, CX + WIN, NX)
TH = np.linspace(0.0, 2.0 * np.pi, NT, endpoint=False)
R = np.zeros((NX, NT))
t0 = time.time()
for i, x in enumerate(XS):
    org = (float(x), 0.0, 0.0)
    for j, th in enumerate(TH):
        loc, _n, _i, _d = bvh.ray_cast(org, (0.0, math.cos(th), math.sin(th)))
        R[i, j] = 0.0 if loc is None else math.sqrt(loc[1] ** 2 + loc[2] ** 2)
print("R(x,theta) 图 %d 条射线 %.1f s" % (NX * NT, time.time() - t0))
hit = R[R > 0.0]
print("★ 自检：中段外缘半径 %.5f … %.5f  ⇒ 最窄/最宽 = **%.3f**"
      "（筒壁不是圆的，别拿 AABB 半宽当半径）" % (hit.min(), hit.max(), hit.min() / hit.max()))


def r_lookup(px, th):
    """查最坏值（3x3 邻域取 min）⇒ 判据偏保守，不会漏掉贴壁的顶点。"""
    i = np.clip(np.searchsorted(XS, px) - 1, 0, NX - 1)
    j = (th / (2.0 * np.pi) * NT).astype(np.int64) % NT
    best = None
    for a in (-1, 0, 1):
        for b in (-1, 0, 1):
            v = R[np.clip(i + a, 0, NX - 1), (j + b) % NT]
            best = v if best is None else np.minimum(best, v)
    return best


def cov(k, phi_deg, mirror=False):
    """覆盖率：柯西的**每个顶点**是否都在仓内。

    方位（★ 必须与出图口径逐字一致，否则读数与图对不上）：
      · 柯西的**身高轴 Y** → 仓的**长轴 X**（机体是**躺**在筒里的，不是站着）
      · 柯西的**其它两轴绕仓长轴滚 phi** → 仓的 Y / Z 截面

    ⚠️⚠️ **滚转必须是"绕仓轴的正当旋转"（行列式 +1）**。第一版写成
    `py = X·c − Z·s` / `pz = X·s + Z·c`，对应的基是
    `image(X)=(0,c,s) / image(Y)=(1,0,0) / image(Z)=(0,−s,c)`，
    而 `image(X) × image(Y) = (0,s,−c) = −image(Z)` ⇒ **行列式 = −1**，
    也就是它其实把柯西**前后翻转**了。柯西前后不对称 ⇒ 读数会漂。
    正当版本：`image(Z) = (0, s, −c)`，于是
    `pod_y = c·X + s·Z`、`pod_z = s·X − c·Z`。
    `mirror=True` 保留旧式，只为把"差多少"打出来留档。
    """
    f = math.radians(phi_deg)
    cp, sp = math.cos(f), math.sin(f)
    px = XV[:, 1] / k
    if mirror:
        py = (XV[:, 0] * cp - XV[:, 2] * sp) / k
        pz = (XV[:, 0] * sp + XV[:, 2] * cp) / k
    else:
        py = (XV[:, 0] * cp + XV[:, 2] * sp) / k
        pz = (XV[:, 0] * sp - XV[:, 2] * cp) / k
    r = np.hypot(py, pz)
    th = np.arctan2(pz, py) % (2.0 * np.pi)
    rr = r_lookup(px, th)
    ok = (rr > 0.0) & (r <= rr)
    return float(ok.mean()), int(ok.sum())


print("\n=== 覆盖率 vs k（phi 各行；柯西 %d 个顶点）===" % len(XV))
PHIS = [0.0, 15.0, 30.0, 45.0, 60.0, 75.0, 90.0]
for k in [60.0, 65.73, 70.0, 75.0, 80.0, 85.0, 90.0, 95.0, 100.48, 110.0]:
    cells = ["%5.1f:%.4f" % (p, cov(k, p)[0]) for p in PHIS]
    pod = POD_SIZE * k
    print("  k=%7.2f 仓 %6.2f x %6.2f x %6.2f   %s"
          % (k, pod[0], pod[1], pod[2], "  ".join(cells)))

# ---------------- 二分求 k_min（在 phi 上取最优滚转角）----------------
best_phi, best_c = 0.0, -1.0
for p in np.linspace(0.0, 90.0, 91):
    c, _n = cov(120.0, float(p) % 90.0)
    if c > best_c:
        best_c, best_phi = c, float(p) % 90.0
print("\n=== 二分（先定最优滚转角，再在 k 上二分）===")
lo_k, hi_k = 60.0, 200.0
for _ in range(24):
    mid = (lo_k + hi_k) * 0.5
    ok = any(cov(mid, float(p) % 90.0)[0] >= 1.0 for p in np.linspace(0.0, 90.0, 19))
    if ok:
        hi_k = mid
    else:
        lo_k = mid
k_min = hi_k
for p in np.linspace(0.0, 90.0, 181):
    if cov(k_min, float(p) % 90.0)[0] >= 1.0:
        best_phi = float(p) % 90.0
        break
pod = POD_SIZE * k_min
print("★ k_min（按柯西真实顶点）= %.2f   最佳滚转 phi = %.1f deg" % (k_min, best_phi))
print("  ⇒ 仓 %.2f x %.2f x %.2f m   最长边 / 柯西全高 = %.3f"
      % (pod[0], pod[1], pod[2], pod[0] / 28.0))
assert abs(k_min - FIT_MIN) < 0.05, (
    "源码里的 POD_FIT_MIN=%.2f 与本脚本实测 %.2f 不符 ⇒ 有一边漂了" % (FIT_MIN, k_min))

print("\n=== 对照（同一套探针）===")
for name, k in (("「最长边 = 柯西全高 x 2.3」", 64.40 / 0.97977),
                ("按**包围盒**的最小值", 100.48),
                ("按**真实顶点**的最小值", k_min),
                ("工程当前 POD_SCALE", SHIPPED_K)):
    c, n_in = cov(k, best_phi)
    print("   %-26s k=%7.2f ⇒ 覆盖 %.4f（%d / %d 顶点在内）%s"
          % (name, k, c, n_in, len(XV), "OK" if c >= 1.0 else "X 露出去"))

print("\n=== 负对照：k = k_min x 0.9 ⇒ 必须露出去（判据能变红）===")
c, n_in = cov(k_min * 0.9, best_phi)
print("   k=%.2f ⇒ 覆盖 %.4f  露 %d 点  %s"
      % (k_min * 0.9, c, len(XV) - n_in, "OK 能变红" if c < 1.0 else "**不能变红**"))

def cov_standing(k, phi_deg):
    """**反面口径**：柯西**站着**放（身高轴 = 仓的 Y，垂直于长轴）。

    用来回答"为什么非得躺着" —— 不靠推理，量出来。
    站着时绕机体自身的上下轴滚 phi ⇒ 混的是仓的 X 与 Z：
      `pod_x = c·X − s·Z`（长轴坐标）、`pod_y = Y`（身高）、`pod_z = s·X + c·Z`。
    行列式同样是 +1。
    """
    f = math.radians(phi_deg)
    cp, sp = math.cos(f), math.sin(f)
    px = (XV[:, 0] * cp - XV[:, 2] * sp) / k
    py = XV[:, 1] / k
    pz = (XV[:, 0] * sp + XV[:, 2] * cp) / k
    r = np.hypot(py, pz)
    th = np.arctan2(pz, py) % (2.0 * np.pi)
    rr = r_lookup(px, th)
    ok = (rr > 0.0) & (r <= rr)
    return float(ok.mean()), int(ok.sum())


print("\n=== 方法校准：镜像（旧式）vs 正当旋转（本式）差多少 ===")
for k in (FIT_MIN, SHIPPED_K, FIT_MIN * 0.9):
    a = cov(k, best_phi, mirror=True)
    b = cov(k, best_phi)
    print("   k=%.2f  phi=%.1f  镜像 %.4f  正当 %.4f  差 %+d 点"
          % (k, best_phi, a[0], b[0], b[1] - a[1]))

print("\n=== 工程 k 下的**滚转窗口**（φ 每 5°；出图/摆位必须落在窗口里）===")
bad = []
for p in np.arange(0.0, 90.0 + 1e-9, 5.0):
    c, _n = cov(SHIPPED_K, float(p))
    if c < 1.0:
        bad.append("φ=%.0f:%.4f" % (p, c))
print("   k=%.3f：覆盖率 < 1.0 的方向 %d 个 %s"
      % (SHIPPED_K, len(bad), "（全向都 1.0000）" if not bad else "｜" + "  ".join(bad)))
CARGO_ROLL = _const_opt("POD_CARGO_ROLL_DEG")
if CARGO_ROLL is None:
    print("⚠️ `world_builder.gd` 里还没有 POD_CARGO_ROLL_DEG（摆位滚转角）")
else:
    c, n_in = cov(SHIPPED_K, CARGO_ROLL)
    print("   ★ 源码 `POD_CARGO_ROLL_DEG` = %.1f° ⇒ 覆盖 %.4f（%d / %d）"
          % (CARGO_ROLL, c, n_in, len(XV)))
    assert c >= 1.0, "源码里选的摆位滚转角 %.1f° 在工程 k 下装不下！" % CARGO_ROLL
    assert abs(CARGO_ROLL - best_phi) <= 5.0, (
        "POD_CARGO_ROLL_DEG=%.1f 离最优 φ=%.1f 太远（>5°）⇒ 余量被白白吃掉"
        % (CARGO_ROLL, best_phi))

print("\n=== 常量自洽：源码里的 `POD_FIT_MIN` **本身**必须满覆盖 ===")
PHI_USE = CARGO_ROLL if CARGO_ROLL is not None else best_phi
c_src, n_src = cov(FIT_MIN, PHI_USE)
print("   POD_FIT_MIN=%.2f @ phi=%.1f  ⇒ 覆盖 %.4f（%d / %d）"
      % (FIT_MIN, PHI_USE, c_src, n_src, len(XV)))
assert c_src >= 1.0, (
    "源码 POD_FIT_MIN=%.2f 本身不满覆盖（%.4f）⇒ 常量必须取**向上取整**值。"
    "⚠️ 表里 %.2f 是**显示值**，真值 %.4f —— 别从打印结果抄数字进源码。"
    % (FIT_MIN, c_src, k_min, k_min))
assert k_min <= FIT_MIN + 1e-6, "实测 k_min=%.4f > 源码常量 %.2f ⇒ 常量不够" % (k_min, FIT_MIN)

print("\n=== 反面口径：**站着**放（身高 = 仓的 Y）在工程 k 下装得下吗 ===")
best_st, best_st_phi = -1.0, 0.0
for p in np.arange(0.0, 90.0 + 1e-9, 2.5):
    c, _n = cov_standing(SHIPPED_K, float(p))
    if c > best_st:
        best_st, best_st_phi = c, float(p)
print("   k=%.3f（工程值）最优 φ=%.1f° ⇒ 覆盖 %.4f  %s"
      % (SHIPPED_K, best_st_phi, best_st, "站得下" if best_st >= 1.0 else "**站不下**"))
if best_st >= 1.0:
    print("   ⇒ 站着放**本来就装得下** ⇒ 选躺着是**版式**考虑（像货舱），不是被迫的")
else:
    lo_k, hi_k2 = SHIPPED_K, 400.0
    for _ in range(20):
        mid = (lo_k + hi_k2) * 0.5
        if any(cov_standing(mid, float(p))[0] >= 1.0 for p in np.arange(0.0, 90.0, 5.0)):
            hi_k2 = mid
        else:
            lo_k = mid
    print("   ⇒ 站着放所需最小 k = %.2f（躺着只要 %.2f，是它的 %.2f 倍）"
          % (hi_k2, k_min, hi_k2 / k_min))

print("\nPOD_FIT_CHECK_DONE")
