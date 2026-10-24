RX-93 ν高达资源生成（2026-10-16）

源文件：D:/牛高达/完成版本体.glb、浮游炮2.glb，保留原文件。
1. Python 运行 build_source.py，生成 work/nu_asset_build 下七个 GLB 与 metadata.json。依赖 numpy/scipy/Pillow 和 penelope_movie/xi_glb_lib.py。
2. 在该临时目录放一个 config_version=5 的 project.godot。
3. Godot --headless --path <临时目录> --script <本目录>/import_nu.gd -- <临时目录绝对路径>。
4. 将七个压缩 scn 与 metadata.json 复制到 assets/models/nu_gundam（metadata.json 改名 assembly.json）。

本体 95 个网格、48 根机械骨、六个浮游炮组合。保留供稿装配，单独减面压缩，保留 UV 和纹理。没有修改 D 盘原始模型。
NuRifle/NuShield/NuBazooka 为独立装备骨；NuDock0..5 为背包组合；Mount_* 提供武器/喷口/浮游炮的跟随标记。
实时精准姿势由 scripts/flight/nu_motion.gd 完成，枪口取动态标记；丢弃使用最终骨骼变换复制实体。

5. 使用 GPU 运行 bake_state.gd，从装配模型烘焙四张状态线稿 state_0..3.res。当前脚本使用本工程绝对路径。
