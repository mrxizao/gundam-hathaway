# -*- coding: utf-8 -*-
"""柯西收纳仓 出图核验（Blender 无头，Workbench 带贴图）。

出 7 个正交视角 + 打印 Blender 世界（Z-up）的真实包围盒。
★ 纪律：只在内存里看，**不存盘任何改过坐标的模型**。
"""
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.stdout.reconfigure(encoding="utf-8")

GLB = r"C:\Users\MSIPC\Documents\gundam\assets\models\xi_pod\xi_pod.glb"
OUT = r"C:\Users\MSIPC\Documents\gundam\_xi_pod_shots"
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

# ---- 真实包围盒（不用 bound_box，逐顶点 + 世界矩阵）----
lo = np.array([1e30] * 3)
hi = np.array([-1e30] * 3)
n_tri = 0
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    me = o.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(n, 3).astype(np.float64)
    mw = np.array(o.matrix_world)
    w = np.c_[co, np.ones(n)] @ mw.T
    lo = np.minimum(lo, w[:, :3].min(axis=0))
    hi = np.maximum(hi, w[:, :3].max(axis=0))
    n_tri += len(me.loop_triangles) if me.loop_triangles else me.calc_loop_triangles() or len(me.loop_triangles)

print("Blender 世界（Z-up）包围盒:")
for k, ax in enumerate("XYZ"):
    print("  %s [%+.4f, %+.4f]  跨度 %.4f" % (ax, lo[k], hi[k], hi[k] - lo[k]))
print("  真实三角数（Blender 侧）: %s" % f"{n_tri:,}")
print("  网格数: %d" % len([o for o in bpy.data.objects if o.type == "MESH"]))

center = Vector((float((lo[0] + hi[0]) / 2), float((lo[1] + hi[1]) / 2),
                 float((lo[2] + hi[2]) / 2)))
span = float(np.max(hi - lo))

# ---- 相机（正交）----
cd = bpy.data.cameras.new("Cam")
cd.type = "ORTHO"
cd.ortho_scale = span * 1.15
cd.clip_start = 0.001
cd.clip_end = span * 40
cam = bpy.data.objects.new("Cam", cd)
bpy.context.scene.collection.objects.link(cam)
bpy.context.scene.camera = cam

# ---- 渲染设置（Workbench + 贴图，秒级）----
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "TEXTURE"
sc.display.shading.show_shadows = True
sc.display.shading.show_cavity = True
sc.display.shading.background_type = "VIEWPORT"
sc.display.shading.background_color = (0.05, 0.05, 0.07)
sc.render.resolution_x = 960
sc.render.resolution_y = 720
sc.render.image_settings.file_format = "PNG"

D = span * 4.0
VIEWS = [
    ("01_front_negY", Vector((0, -D, 0))),
    ("02_back_posY", Vector((0, D, 0))),
    ("03_left_negX", Vector((-D, 0, 0))),
    ("04_right_posX", Vector((D, 0, 0))),
    ("05_top_posZ", Vector((0, 0, D))),
    ("06_bottom_negZ", Vector((0, 0, -D))),
    ("07_quarter", Vector((-D * 0.75, -D * 0.75, D * 0.45))),
]

for name, off in VIEWS:
    cam.location = center + off
    d = center - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("  出图 ->", name)

print("完成。输出目录:", OUT)
