三城市道路材质 / Round2 Day3
范围：阿德莱德普通道路、河桥、机场跑道/滑行道/停机坪；奥恩贝利和达沃道路、内部支路、高架、环线、运河桥、主桥和引道。
共享材质：road_surface.gd + road_surface.gdshader。family 2..6 = 旧沥青/混凝土/补丁/标线/排水金属。
PBR：asphalt_floor 2.35m、clean_asphalt 2.1m、concrete_floor_01 2m，2K RGB8；反照率 sRGB，OpenGL 法线与 ORM 线性。无高度位移，不改变碰撞。
色彩：对每套原始反照率做 sRGB→linear 均值归一到稳定色系；沥青下限采用中性石墨灰，避免旧RGB量化产生偏青/黑洞；近处使用颗粒，远处收敛到同一色系。数据嵌入 GDScript，运行时不读取 JSON。
三档：高档法线300m、中档140m，低档仅反照率；反照率120–950m过渡到宏观磨损。透明裁切未用于磨损标线，避免远处跳闪。
路向：实例路段使用已有局部 Z；批次路段用 UV(world along/across) + UV2(width/orientation)；曲面环线使用径向框架；垂直路缘使用主轴投影，避免纵向拉伸。
街口：阿德莱德 road_junction_mask.png 来源 ground_layout.json 的真实硬地交叉；tools/bake_road_junction_mask.py 可复现。其余两图用原路网节距抑制街口车辙。
细节：两张实例城市新增稀疏排水口/井盖/修补块，无碰撞，不使用城市随机数；独立近景批次。阿德莱德复用原有排水、斑马线和修补块。
保留：地图造型、道路/桥梁变换、碰撞、机库/出击与任务坐标；奥恩贝利不点标线灯，达沃保留原有标线发光。
来源与版权：sources.json / NOTICE.txt；新增外部贴图均为 Poly Haven CC0。
