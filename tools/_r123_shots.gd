extends Node
## 验收工具：**这一轮的三条要求**（公路 / 高架桥 / 错落 / 不在水上）。
##
## 跑法（**不能加 `--headless`**，headless 是 dummy 渲染器，抓出来全黑）：
##   godot --path <工程> res://tools/_r123_shots.tscn -- <输出目录> [奥恩增益] [达沃增益]
##
## ## 每张图 7 个机位，各看一件事
## | # | 机位 | 看什么 |
## |---|---|---|
## | A | 1.35 km 斜俯路网全景 | 整片路面网格建出来了没有 + 高架十字与环线 |
## | B | 斜俯 16°，锚在主干格线 | 主干 460 m（＋压在上方的 420 m 高架桥面）与相邻 110 m 支路**同框** |
## | C | 斜俯 16°，锚在次干格线 | 次干 260 m 与相邻 110 m 支路**同框**（"每 5 格一条"） |
## | D | 钻进桥下（y = 180 m） | 桥面底 / 一排桥墩 / 桥下那条地面主干道 |
## | E | 顺高架桥面斜看 | 桥面 / 护栏 / 桥墩 / 桥下的地面主干道 |
## | F | 平视市中心 | 楼群**错落**与**高度**（达沃更高） |
## | G | 自陆一侧朝水斜俯（俯角 24°） | 水面 → 岸线 → 护岸 → 退让带 → 前几排楼 |
## | G' | 开阔海面朝空 | 判那组"等距竖向细线"出在哪一层（对照图） |
##
## B / C **两张同一几何**（1 200 m 高、俯角 16°、视野 ±4 025 m = 一格）
## ⇒ 各自把"干线 + 相邻支路"**收进同一张图**，宽度差不必跨图比较。
##
## ## ⚠️ 关于**存图增益**（沿用 `pixprobe` 的 `--gain` 那条约定）
## 奥恩贝利是**刻意的"阴天黄昏死城"**（`dusk_overcast`，全城没有一盏灯），
## 实拍整帧亮度只有 0.003 量级 —— 直接存出来是一块黑，**肉眼判不了结构**，
## 会误判成"这一轮没建出东西"。所以这里对**存出来的 PNG**乘一个增益
##（`Image.adjust_bcs`），**只动图片、不动渲染、不动统计口径**。
## ⚠️ 增益会**打进日志**（`[shots] ... gain=`）。后人比图时必须先看增益，
## 否则会拿一张 ×2.5 的图去和别人 ×1.0 的图比。
##
## ## ⚠️ 关于最后那张 `G_sky_probe`
## 画面里有一组**等距的竖向细线**（天空与水面上都穿过去），前几轮的
## `_pixprobe_v_oen_g.png` 里也有。这张"相机垂直朝天、画面里只有天空"的对照图
## 就是为了判它到底是不是天空/大气层的产物（若是，则与本轮改动无关）。

var out_dir := "user://r123_shots"
var gain_oen := 2.5
var gain_dav := 1.8
var _idx := 0
var _world: WorldBuilder


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		gain_oen = float(args[1])
	if args.size() > 2:
		gain_dav = float(args[2])
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	_world = WorldBuilder.new()
	add_child(_world)
	await get_tree().physics_frame

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 1.0
	cam.far = 900000.0
	add_child(cam)
	cam.current = true

	# ⚠️ 机位一律**锚定城域**（`rx × cblock`），不锚定 `ARENA_RADIUS`。
	# 理由与 `city_shots.gd` 那条 ⚠️ 同：竞技场这一轮 ×2.25，而两座城的城域坐标
	# 一个字没动 —— 用竞技场半径当尺子会让机位跑到 2.25 倍远，城缩成一小片。
	var cblock := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)

	for spec: Array in [
			[MapDef.oenbelli(), "OEN", WorldBuilder.CITY_ISLAND_RX, 0.0, gain_oen],
			[MapDef.davao(), "DAV", 15.0, 5.0, gain_dav]]:
		var m: MapDef = spec[0]
		var tag: String = spec[1]
		var rx: float = spec[2]
		var cz: float = spec[3]
		var gain: float = spec[4]
		print("[shots] %s 存图增益 gain=%.1f（只乘存出的 PNG；死城必须提亮才看得出结构）"
			% [tag, gain])
		_world.apply_map(m)
		await _frames(24)
		var isl := rx * cblock                    # 岛半长轴（米）
		var dcy := cz * cblock                    # 岛心 z（达沃北移 5 格）

		# ⚠️⚠️ 相机**一律不许爬过 `WorldBuilder.CLOUD_FLOOR`（1 500 m）**。
		# 第一版把俯瞰机位放到 25 / 41 km，画面里全是**白云夹在楼中间**挡着地面
		# （云盘最低点 1 500 m，而它们是**真实几何**、会正常遮挡）⇒
		# 出来的图"什么都看不见"，还容易被误读成"路没建出来"。
		# 所有机位 ≤ 1 400 m（高架桥面 360 m 的对比也在这条线以内）。
		#
		# ⚠️ 另一个坑（第二版）：**楼在 1~4 km 高**，所以低空机位很容易正好顶在一栋楼上
		# （第二版的 B/C 两张就是这么废掉的：一张被楼挡住、一张贴在一面墙上）。
		# ⇒ 低空机位**必须落在路廊里**（路中心 ±765 m 内没有楼，见 `CITY_FILL` 那段）。
		var xo := 3.0 * cblock if tag == "OEN" else 0.0
		# A 俯瞰路网：1.35 km 高、俯角 ~26°。奥恩贝利横向让开 3 格 —— 图心正好是针塔，
		#   正对它会得到一张"一根大柱子"。
		await _look(cam, Vector3(xo, 1350.0, 1500.0),
			Vector3(xo, 20.0, -2200.0), "%s_A_road_grid" % tag, gain, 16)
		# ---- B / C：**三档路宽**（同一几何，视野正好一格的宽）----
		#
		# ## 为什么要"视野 ±4 025 m"（= 一格）
		# 格距是 4 025 m，而**主干 460 只在 `gi = 0` 这一条**、次干 260 只在 `gi % 5 == 0`。
		# 想让"460 与 110"**并排出现在同一张图里**（而不是靠跨图比较），
		# 画面半宽就必须 ≥ 4 025 m。
		# 半宽 `= d · tan(43.9°)`，而 `d = h / tan(俯角)` ⇒ 二者一起被
		# 「相机不许过 `CLOUD_FLOOR = 1 500 m`」这条卡死 ⇒ **俯角只能是 16°**
		#（1 200 m / tan16° = 4 185 m ≥ 4 025 ✓，再陡就框不下第二格）。
		#
		# ## 为什么俯角必须 < 31°（`fov` 的半角）
		# 俯角 16° ⇒ 画面上缘在水平**上方 15°** ⇒ 画面里有天空。
		# 这条**是活的必要条件**：奥恩贝利是**阴天死城**（`dusk_overcast`），
		# 唯一的光源在天空/云那边，而 `MultiMesh` 构件的**顶面完全不受光** ——
		# 正俯视（90°，第三版）拍出来是一张**纯黑**（`02_OEN_B_trunk` 的 B 版就是）。
		# 必须让相机**斜过来**，看到路面/桥面的**侧面**才读得出东西。
		#
		# | 版本 | 机位 | 死因 |
		# |---|---|---|
		# | ① | 贴地沿路平视 | 三个机位透视不同 ⇒ 宽度差不能对账；夜景里支路黑成一团 |
		# | ② | 1.3 km 斜俯 47° | 被中景楼立面挡死（俯角 47° 时 765 m 处视线只剩 480 m，楼高 2 462 m） |
		# | ③ | 正俯视 90° | 不挡了，但顶面不受光 ⇒ **全黑**（见上） |
		# | ④ | **斜俯 16°，视野 ±4 025 m** | ✔（本条） |
		#
		# ⚠️ 已知局限（如实记入图注）：`gi = 0` 那条**地面**主干道正上方压着
		#   **十字高架桥面**（420 m 宽，且十字**全图贯通、不判水**）⇒
		#   B 那张里"460 主干"会被 420 的桥面盖掉大半，读到的其实是
		#   "桥面 420 叠在主干道 460 上、两侧各露出 20 m"。这不是 bug ——
		#   用户要的"高架叠在主干道上"本来就是这个样子；**干净的 260 : 110 对比看 C**。
		var lz0 := _dry_line_near_city(m, 0.0)
		for lane: Array in [
				["B", "trunk", 0.0],
				["C", "arterial", 5.0 * cblock]]:
			var letter: String = lane[0]
			var lname: String = lane[1]
			var lx: float = lane[2]
			var lz := _dry_line_near_city(m, lx)
			print("[shots] %s_%s 斜俯锚点 x=%.0f z=%.0f（该格线离城心最近的干格）"
				% [tag, lname, lx, lz])
			await _look(cam, Vector3(lx, 1200.0, lz + 4100.0),
				Vector3(lx, 0.0, lz - 85.0), "%s_%s_%s" % [tag, letter, lname],
				gain, 14)
		# ---- D 桥下：相机钻进高架桥**底下**（y = 180 m，在桥面 360 m 之下）----
		#   朝 x = 0 斜看 ⇒ 桥面底 / 一排桥墩 / 桥下那条地面主干道 / 两侧楼群 / 天空
		#   全在一张图里。这是"高架真的是**悬空**的、下面真的**有路**"的判据图。
		#   ⚠️ 相机在 `x = 700 m` 而不是 `x = 0`：要的是**看见**桥底，
		#   站在正下方只能看到一块天花板。700 m 仍在路廊（±765 m）之内 ⇒ 不会撞楼。
		await _look(cam, Vector3(700.0, 180.0, lz0 + 900.0),
			Vector3(0.0, 40.0, lz0 - 600.0), "%s_D_underdeck" % tag, gain, 12)
		# E 高架桥：从桥面斜上方顺桥看 —— 桥面 / 护栏 / 桥墩 / 桥下的地面主干道一起入画
		await _look(cam, Vector3(isl * 0.45, 760.0, -2200.0),
			Vector3(-isl * 0.16, 330.0, 300.0), "%s_E_viaduct" % tag, gain, 12)
		# F 平视市中心：错落与高度
		await _look(cam, Vector3(isl * 0.30, 1050.0, dcy + isl * 0.34),
			Vector3(0.0, 1500.0, dcy), "%s_F_skyline" % tag, gain, 14)
		# G 水岸：**从陆地一侧朝水斜俯**（相机 1.4 km 高、俯角 ~24°）。
		#   画面自上而下读作：水面 → 岸线 → 护岸 → 退让带 → 前几排楼，是
		#   "房子 / 路灯 / 公路都不在水上"最干净的一张判据图。
		#
		# ⚠️ 为什么**不能**正俯视（上一版就这么拍的，两张**纯黑**）：
		#   `MultiMesh` 构件的**顶面完全不受光** —— 阴天/夜景里唯一的光来自天空，
		#   正俯视等于对着一块不反光的天花板。**任何拍路面 / 桥面 / 护岸的机位
		#   都必须斜过来**，让构件露出**侧面**（B/C 上已经踩过一次同样的坑）。
		# ⚠️ 也不用"从水面望岸"（更早那一版）：水面占掉六成画面，远处的楼底被水面
		#   遮住一小截，读起来像"楼站在水里" —— 那是视觉误判，不是几何问题
		#   （水面 −12 m 恒低于陆地最低 −7.9 m，见 `city_is_dry()`）。
		#
		# ⚠️ 岸线 z **自动搜**（`_shore_z()`）：奥恩贝利的水在 +Z、达沃在 −Z，
		#   岸线还带 `bay_wave` 正弦 ⇒ 写死一个 `CITY_BAY_Z` 必然偏。
		#   `wdir` 就是"水在哪一侧"，靠岸线的符号定，两座城共用一套机位公式。
		#   ⚠️ 相机要在**水一侧**（`shore + wdir × 3000`）、视线**抬平到俯角 10°**：
		#   若把相机放在陆地上朝水看（更早那一版），画面里只有水与岸线，
		#   **楼群全在相机背后** —— 而"房子是不是在水上"恰恰是要拍楼。
		#   反过来把相机放到水面上朝陆看、又把俯角压到 10°，楼群（2.5~3.3 km）会
		#   **高耸着从上边缘切出去**，正好读成"城市退在岸线后面、楼在陆上"。
		var shore := _shore_z(m, 0.0)
		var wdir := signf(shore)             # +1 = 水在 +Z 侧，−1 = 水在 −Z 侧
		print("[shots] %s 岸线（沿 x=0 从城心往两侧扫到的最近一处）z=%.0f 水在 %+.0f 侧"
			% [tag, shore, wdir])
		await _look(cam, Vector3(0.0, 900.0, shore + wdir * 3000.0),
			Vector3(0.0, 0.0, shore - wdir * 2100.0), "%s_G_waterfront" % tag, gain, 12)

	# ---- G 对照：把相机搬到**远离城市的开阔海面**上，朝天空抬 66°
	#      （画面九成是天空 + 一条水面），用来判那组"等距竖向细线"到底出在哪一层。
	#      ⚠️ 不能真朝天（`look_at` 的 up 与视线平行会退化），66° 已经够。
	_world.apply_map(MapDef.oenbelli())
	await _frames(16)
	await _look(cam, Vector3(90000.0, 5000.0, 90000.0),
		Vector3(120000.0, 100000.0, 120000.0), "OEN_G_sky_control", gain_oen, 12)

	print("R123_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


## ⚠️ `up` 必须能被换掉：**正俯视**（视线 = −Y）时 `Vector3.UP` 与视线平行，
## `look_at` 会退化（Godot 直接按"朝向没变"处理 ⇒ 拍出来是上一张机位的画面，
## 而且**不报任何错**）。俯视一律传 `Vector3(0, 0, -1)`。
func _look(cam: Camera3D, from: Vector3, at: Vector3, shot_name: String,
		gain: float, frames: int, up := Vector3.UP) -> void:
	cam.global_position = from
	cam.look_at(at, up)
	await _frames(frames)
	await _shot(shot_name, gain)


## 在 `x = lx` 这条**格线**上，返回**离城心（`z = 0`）最近的干燥格**的 `z`，
## 并且**跳出中央广场**（`CITY_SHAPE[·].plaza_r` —— 广场里不建楼、也不铺路）。
##
## ## 为什么要自动搜（不许写死坐标）
## 路面是**按格、逐段过 `city_is_dry`** 筛出来的（见 `_build_city_street_infra`），
## 所以随手写一个 `z` 很可能正落在海湾 / 运河上 —— 拍回来是一张"没有路的路"，
## 反而把"公路建出来了"证成反面。
## 而且**两座城的干区完全不重合**：奥恩贝利的水在 +Z、达沃在 −Z，岸线还带正弦。
## 写死一个坐标必然只有一座城对。这类"算式必须脚本复算"本轮已踩两次。
##
## ## ⚠️⚠️ 为什么不是"最长干区的中点"（上一版就是这么写的，B/C 两张因此废掉）
## 最长的连续干区几乎总落在**岛的边缘**（远离市中心）：那一版锚在 `z = −22 138`，
## 拍回来**只有一条路、左右各一栋楼**，看起来像"城根本没建"。
## 楼只落在「`city_is_land` ∧ 干燥 ∧ 跳过广场 / 公园 / 排除区」的格上
##（见 `_build_city_blocks`）⇒ 锚点必须往**城心**靠，画面里才有楼群。
func _dry_line_near_city(m: MapDef, lx: float) -> float:
	var cblock := WorldBuilder.ARENA_RADIUS / float(WorldBuilder.CITY_GRID)
	var half := WorldBuilder.CITY_GRID / 2
	var plaza := float(WorldBuilder.CITY_SHAPE[m.city_layout].plaza_r)
	for dz in range(half + 1):
		for s: float in ([0.0] if dz == 0 else [1.0, -1.0]):
			var z := float(dz) * s * cblock
			if not WorldBuilder.city_is_dry(lx, z, m.city_layout):
				continue
			if Vector2(lx, z).length() < plaza:
				continue                      # 中央广场：没楼、也没路面
			return z
	return 0.0


## 在 `x` 这条线上，从**城心**（`z = 0`）往两侧扫，返回**最近那一处岸线**的 `z`。
##
## 判据与 `city_is_dry()` **逐字一致**：`_city_landform() > CITY_WATER_Y`。
## 先 200 m 粗扫找到符号翻转的区间，再二分 24 次（精度 ~1e-5 m）。
## ⚠️ 起点必须是城心而不是 `-110 km`：奥恩贝利是**人工岛**（四周都是水），
## 从最外侧扫到的会是岛的另一头；达沃的水又只在 −Z 一侧 —— 两端各扫一次取近的。
func _shore_z(m: MapDef, x: float) -> float:
	var wl := WorldBuilder.CITY_WATER_Y
	var dry0: bool = WorldBuilder._city_landform(x, 0.0, m.city_layout) > wl
	if not dry0:
		return 0.0                            # 城心自己就在水下（不该发生，如实返回 0）
	var step := 200.0
	for s: float in [1.0, -1.0]:
		var z := 0.0
		while absf(z) < 110000.0:
			z += step * s
			if (WorldBuilder._city_landform(x, z, m.city_layout) > wl) != dry0:
				var lo := z - step * s
				var hi := z
				for i in 24:
					var mid := (lo + hi) * 0.5
					if (WorldBuilder._city_landform(x, mid, m.city_layout) > wl) == dry0:
						lo = mid
					else:
						hi = mid
				return (lo + hi) * 0.5
	return 0.0


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(shot_name: String, gain: float) -> void:
	_idx += 1
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	if vp == null or vp.get_texture() == null:
		print("SHOT_FAILED ", shot_name)
		return
	var img := vp.get_texture().get_image()
	if img == null:
		print("SHOT_FAILED(img) ", shot_name)
		return
	# ⚠️ 增益**只乘存出来的这一份**（`duplicate()` 之后再动），
	# 免得后续任何统计/比较被同一张图上的增益污染。
	var shot := img
	if not is_equal_approx(gain, 1.0):
		shot = img.duplicate() as Image
		shot.adjust_bcs(gain, 1.0, 1.0)
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s gain=%.1f err=%d" % [p, gain, shot.save_png(p)])
