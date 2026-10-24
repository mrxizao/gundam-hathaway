# 柯西剧场版绑定工具

主模型：assets/models/xi_movie/xi_movie_rigged.scn，自包含纹理和网格。

build_rig.py 从桌面来源文件以及隐藏归档的旧模型中重建兼容骨架，再将原始机械变形烘到 Movie_ 关节。依赖 numpy、scipy。产物写入本目录 output；校验后复制 GLB 到模型的 authoring_hidden 目录，使用 Godot --headless --path 工程 --script res://tools/model_binding/xi_movie/import_rig.gd 重新生成 SCN。该目录和 authoring_hidden 均有 .gdignore，不参与常规导入和导出。

part_bindings.json 记录部件归属；手臂、长腿装甲使用分段蒙皮，步枪、盾牌与机械翼片保留刚性绑定。模型根朝 +Z，由现有 profile 的 180° 朝向层转为游戏 -Z。

原始变形两段均为 6.2 秒。游戏继续使用现有 0.45 秒形态进度，保留原曲线各阶段的时间比例。旧模型重命名并存于 archive/hidden_models/xi_legacy_20261013，用 .gdignore 排除常规导入与导出；其中 SCN 仅供旧形态单元测试显式加载。

## 动作绑定回归

基础柯西已修正十个部件归属：五个左小腿附件绑定 Shin.L，腰背两片外壳绑定 Chest，左上臂内侧件绑定 UpperArm.L，右膝附件绑定 Shin.R，左肩连接件绑定 Shoulder.L。规则同时保留在 build_rig.py 的 manual 表中。

使用 Godot --headless --path 工程 res://tools/model_binding/xi_movie/xi_action_binding_verify.tscn 检查实际运行时动作及修复部件。xi_action_audit.tscn 通过 -- 输出JSON绝对路径导出全部动作骨骼采样；xi_action_preview.tscn 通过 -- 输出目录绝对路径生成八类代表动作的正反面图。
