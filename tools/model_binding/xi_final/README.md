# 柯西（最终决战样式）模型绑定

1. Python（numpy/scipy）运行 build_rig.py，读取原始模型及普通柯西派生骨架。
2. 运行 fix_binding.py。该步骤必要：右手、枪、肘、腕与完整肩甲/背翼的归属和转轴必须按新模型校准。
3. Godot --headless --path 工程目录 --script res://tools/model_binding/xi_final/import_rig.gd，生成独立SCN。
4. 运行 build_lod.py，再执行生成的 import_lod.gd。

源GLB路径在脚本和资产manifest中。原始GLB不改写；普通柯西不替换。authoring_hidden使用.gdignore排除导出，运行时只依赖独立SCN与LOD。

part_bindings.json是初步空间归属报告，manual_binding.json及fix_binding.py是最终校准依据。原文件部分网格混有远处孤岛，修复脚本只去除相对主部件很小且远离表面的导出碎片。
