阿德莱德地表 · 第二轮第二天

覆盖：内陆地形、机场草坪、城区公园、河岸与郊地。海岸沙色与道路材质继续沿用原材质。
新材质：leafy_grass（绿草）、withered_grass（枯草）、dirt（裸土），各 2K 颜色/GL 法线/ORM；实际 2 米平铺。
颜色贴图使用 sRGB，法线/ORM/遮罩使用线性数据；ORM=R AO / G roughness / B metallic；地表金属度恒 0。
共享布局遮罩：4096 RGBA；世界范围 X[-65000,80000] Z[-65000,65000] 米。
R/G 为到现有硬地/建筑地块的最近距离，0..512 米；B 为现有河道湿润带；A 为机场草坪。
此遮罩来自实际几何与地块，不使用城市 RNG，也不在运行时生成昂贵图像。正常加载只读取压缩纹理。

三个尺度：650/240 米附近的连续远景色彩；16/24 米中景枯绿和侵蚀；2 米近景 PBR。中景噪声按屏幕导数和距离过滤。
高档：三材质颜色混合、近处旋转第二组颜色采样、法线与 ORM。
中档：三材质单组采样、较短法线距离。
低档：保留地理分区与枯绿/裸土；两张颜色图，枯草使用绿草颜色校正；关闭法线/ORM。
地形顶点法线统一到上半球，避免上下翻转法线在过渡区相消。纹理使用显式 textureGrad，三角形/距离分支不使用未定义导数。

地图修改后的离线再烘焙（先在工程副本操作）：
1. Godot --headless --path <工程> res://tools/export_adelaide_ground_layout.tscn
2. python tools/bake_adelaide_ground_mask.py
3. Godot 导入后运行 res://tests/test_runner.tscn -- --only=suite_adelaide_ground
4. 比较机场、河岸、街口和远景。suite_adelaide_ground 会对照实际路网、地块和碰撞哈希，防止布局遮罩过期。
Python 工具只用于离线资产编译，游戏运行不依赖 Python。需 numpy 与 Pillow。
ground_calibration.json 保存源贴图线性均值和目标反射率；着色器调整颜色，不改原始光照方向。

保护范围：地形碰撞、道路/河岸位置、楼房种子、任务标记与机库出击路线保持；不增加草簇节点。
