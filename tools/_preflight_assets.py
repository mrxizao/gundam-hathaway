# -*- coding: utf-8 -*-
"""一次性 wrapper：把中文路径留在这里（不过 shell），加载技能里的 glb_preflight 跑体检。"""
import importlib.util
import sys

sys.stdout.reconfigure(encoding="utf-8")

SKILL = r"C:\Users\MSIPC\.workbuddy\skills\glb-asset-preflight\scripts\glb_preflight.py"
spec = importlib.util.spec_from_file_location("glb_preflight", SKILL)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

TARGETS = [
    r"C:\Users\MSIPC\Desktop\游戏\闪哈游戏\梅萨指挥官\tripo_convert_2df28fa1-5745-4424-9be1-28ca33860e1f.glb",
    r"C:\Users\MSIPC\Desktop\游戏\闪哈游戏\梅萨F01\tripo_convert_f369e9ab-4d8f-4d5d-9ac7-df3672b0ec84.glb",
]

for p in TARGETS:
    try:
        mod.preflight(p)
    except Exception as e:
        print("!! 失败:", e)
        raise
