# -*- coding: utf-8 -*-
"""三台梅萨的朝向核验出图（Blender 无头，Workbench 带贴图）。

★ 为什么要把 `messer_fly.glb` 一起拍进来当**标尺**：
  它的 `SuitProfile.model_yaw_deg = 90` 是**已被老板看图确认过**的事实
  ⇒ 它的「脸」朝 **glTF +X**（绕 Y 转 +90° 落到工程的前方 −Z）。
  于是判据变成一句可对照的话：**新机的「脸」也朝 glTF +X 吗？**
  同视角并排看，比对着孤立一张图猜"哪边是脸"可靠得多
 （`messer_m01` 那次就是这么连着误判三次的：头冠/肩刺/背包都像正面特征）。

★ 轴对应（Blender glTF importer）：Blender (x, y, z) = glTF (x, −z, y)
  ⇒ glTF 的 **+X** = Blender 的 **+X**；glTF 的前方 **−Z** = Blender 的 **+Y**。
  ⇒ 本脚本里「+X 视角」（相机在 +X 看向 −X）拍到的**就是 glTF +X 那一面**。

★ 纪律：只在内存里看，**不存盘任何改过坐标的模型**；逐顶点量包围盒，不读 `bound_box`。
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.stdout.reconfigure(encoding="utf-8")

ASSETS = [
    ("fly", r"C:\Users\MSIPC\Documents\gundam\assets\models\messer\messer_fly.glb"),
    ("cmd", r"C:\Users\MSIPC\Documents\gundam\assets\models\messer_cmd\messer_cmd.glb"),
    ("f01", r"C:\Users\MSIPC\Documents\gundam\assets\models\messer_f01\messer_f01.glb"),
]
OUT = r"C:\Users\MSIPC\Documents\gundam\_messer_shots"
os.makedirs(OUT, exist_ok=True)

# 方位（Blender 基向量）—— 名字写的是**相机所在的轴正向**，不是"拍到哪一面"
VIEWS = [
    ("a_posX", Vector((1, 0, 0))),
    ("b_negX", Vector((-1, 0, 0))),
    ("c_posY", Vector((0, 1, 0))),
    ("d_negY", Vector((0, -1, 0))),
]


def bounds():
    lo = np.array([1e30] * 3)
    hi = np.array([-1e30] * 3)
    n_tri = 0
    n_obj = 0
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        n_obj += 1
        me = o.data
        n = len(me.vertices)
        if n == 0:
            continue
        co = np.empty(n * 3, dtype=np.float32)
        me.vertices.foreach_get("co", co)
        co = co.reshape(n, 3).astype(np.float64)
        mw = np.array(o.matrix_world)
        w = np.c_[co, np.ones(n)] @ mw.T
        lo = np.minimum(lo, w[:, :3].min(axis=0))
        hi = np.maximum(hi, w[:, :3].max(axis=0))
        me.calc_loop_triangles()
        n_tri += len(me.loop_triangles)
    return lo, hi, n_tri, n_obj


summary = []
for tag, path in ASSETS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    lo, hi, n_tri, n_obj = bounds()
    print("=" * 74)
    print("[%s] %s" % (tag, os.path.basename(path)))
    for k, ax in enumerate("XYZ"):
        print("  Blender %s [%+.4f, %+.4f]  跨度 %.4f" % (ax, lo[k], hi[k], hi[k] - lo[k]))
    # Blender (x,y,z) = glTF (x,-z,y)  ⇒ 反推 glTF 三轴跨度
    print("  ⇒ glTF/Godot 空间（Y-up）: X %.4f | Y(高) %.4f | Z %.4f"
          % (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1]))
    print("  网格 %d 个 | 三角 %s" % (n_obj, f"{n_tri:,}"))
    summary.append((tag, hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1], n_obj, n_tri))

    center = Vector((float((lo[0] + hi[0]) / 2), float((lo[1] + hi[1]) / 2),
                     float((lo[2] + hi[2]) / 2)))
    span = float(np.max(hi - lo))

    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = span * 1.15
    cd.clip_start = 0.001
    cd.clip_end = span * 40
    cam = bpy.data.objects.new("Cam", cd)
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.display.shading.background_type = "VIEWPORT"
    sc.display.shading.background_color = (0.05, 0.05, 0.07)
    sc.render.resolution_x = 720
    sc.render.resolution_y = 720
    sc.render.image_settings.file_format = "PNG"

    D = span * 4.0
    for name, dirv in VIEWS:
        cam.location = center + dirv * D
        d = center - cam.location
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (tag, name))
        bpy.ops.render.render(write_still=True)
    print("  出图 4 张 -> %s_*.png" % tag)

print("=" * 74)
print("汇总（glTF 空间跨度 / 网格数 / 三角数）:")
print("  %-5s %8s %8s %8s %6s %12s" % ("tag", "X", "Y(高)", "Z", "网格", "三角"))
for s in summary:
    print("  %-5s %8.4f %8.4f %8.4f %6d %12s"
          % (s[0], s[1], s[2], s[3], s[4], f"{s[5]:,}"))
print("输出目录:", OUT)
