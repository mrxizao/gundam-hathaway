extends Node
## **B7 三件事的定点验收图**（2026-09-28）。
##
## 用户这一轮进游戏报的三条（verbatim）：
##   ① 「**房屋排列还是田字格一个地块一个房子，城市排列结构不是这样的**」
##      → 「**不要田字格建城市，至少是大格子小格子不均匀分布吧，大格子里面七八栋楼，
##         小个子的话就三二栋楼吧**」
##   ② 「**路面和地面依旧没做区分还是没做出来，现在还是看不到公路路面**」
##   ③ 「**你的高架桥为什么是一堆直着的桥面按照摆了一个圈**，你要不要试试这样摆能不能通车」
##
## 十一张图，每张只回答一件事（**判据图**，不是风景图）：
## | # | 文件 | 光照 | 回答 |
## |---|---|---|---|
## | 1 | `01_实景_topdown_2x2_blocks` | 实景 | 游戏里这两格长什么样？ |
## | 2 | `02_判据_topdown_2x2_blocks` | **判据** | 一格**几栋**？块与块的**缝**等不等宽？ |
## | 3 | `03_判据_topdown_one_block` | **判据** | 画面正好一格 ⇒ 直接**数楼** |
## | 4 | `04_判据_topdown_6x6_blocks` | **判据** | 大格小格**混在一起**、疏密不均吗？ |
## | 5 | `05_low_along_trunk` | 实景 | 路肩（亮）×2 夹沥青（暗）+ 中间标线，读不读得出"这是路"？ |
## | 6 | `06_road_cross_section` | 实景 | 路肩**抬高 12 m** 的实边在不在？ |
## | 7 | `07_groundeye_along_trunk` | 实景 | **玩家视角**（y ≈ 18 m）：路面看得见吗？ |
## | 8 | `08_判据_ring_topdown` | **判据** | 桥面是**一条连续的带**还是 72 块直板的折线？ |
## | 9 | `09_实景_ring_low_along` | 实景 | 桥面 / 护栏 / **中线**三层在不在？（"能不能通车"） |
## | 10 | `10_判据_ring_overview` | **判据** | 整圈是**圆**还是多边形？ |
## | 11 | `11_实景_loweye_towers` | 实景 | **玩家视角**：楼有多粗？（正俯视看到的是线脚叠成的同心框，读不出立面） |
##
## ## ⚠️ 为什么要有"判据光照"这一档
## 这张图是 `dusk_overcast()`：**「铅灰压顶、没有太阳」**、楼只靠散射天光被看清。
## 没有方向光 ⇒ 屋顶与立面亮度几乎相同 ⇒ **结构再对也只能读成一片平瓦**
##（实测 7 km 正俯视 **87.6% 的像素落在 0…2**）。所以"一格几栋楼"必须换一副
## **有方向光**的判据才数得出来。**这一档只用于判据图，不改游戏的观感。**
##
## ## ⚠️ 高空那几张（①②③④⑧⑩）**必须关天气层**
## `fog_enabled` + `volumetric_fog_enabled` + `_cloud_root` + `_sea_mist` **四个都要关**，
## 漏任一个 7 km 以上就是一整张米色，什么都读不出（`_r5_shots` 踩过同一个坑）。
## 低空四张（⑤⑥⑦⑨）**保留天气**，因为"玩家到底看不看得见路"要看**真实大气**。
##
## 跑法（**不能加 `--headless`**，dummy 渲染器抓出来全黑）：
##   godot --path <工程> res://tools/_b7_shots.tscn -- <输出目录> [oenb|davao] [prev|legacy] [gx,gz]
##
## `prev|legacy`（第 3 个参数，可选）：出**改前 / 改后对照图**。**只改内存里那个 `MapDef`
## 实例**，工程文件一个字不动。
##   · `prev` = **上一版**（交付版：`nx = 3`、不跨格）
##   · `legacy` = **细高版**（`0.62 / 1.15` ＋ 不跨格 ＋ `nx = 4`）
## ⚠️ 两档都必须把**地块侧三件套**一起回退（`span_x 1` / `big_fill 0.66~0.86` / `big_n`）：
## 本轮的改动同时动了这三样，只回退倍率拍出来的**不是"改前"**。
##
## `gx,gz`（第 4 个参数，可选）：**强制机位格**。出对照图**必须**给 ——
## 自动机位按"格内塔高之和最大"挑格，而这个量**本身随本轮改动变** ⇒ 两档会挑到
## 不同的格（实测上一版选 `(−4,4)`、本轮选 `(−5,7)`，差 6 km），并排看会得出假结论。
## 给了本参数后机位取**该格格心**（同一条臂内可复现、跨臂可对齐）。
##
## ## ⚠️ 同一条指令在**达沃**上的追加读数（2026-09-28 · 用户第 ④ 条）
## > **田字格块内房子太细了，应该要做的比现在粗300%，每个房子也不用一样粗，
## > 但是最少也要比现在粗200%高度也改下，高度到现在的80%**
##
## 落在 `MapDef.davao()`：`city_tower_w 0.62 → 1.55`、`city_height_mul 1.15 → 0.92`。
## 判断这一条的图是 ①②③（一格几栋、每栋多粗）+ ④（6 格疏密）。
##
## ## ⚠️⚠️ 用户第 ⑤ / "A" 条（2026-09-28 深夜）：**"房子还是太细"的第三轮**
## > **你先划分：哪个格子是大格，哪个格子是小格，小格就放三栋两栋，大格就放七八栋，
## > 相应的，大格地块面积也会比小格大得多**
##
## 判决：**前两轮都改错了杠杆**。第一轮只加 `city_tower_w`（被 `0.46 × 1.55 < 0.72`
## 卡死在 1.55）；第二轮改 `nx` 4→3，**顺带把栋数从 7~8 压到 4~5**（方向反了）。
## 真因是一条**与地块大小无关**的不等式挡不住"地块本身太小"：
## ```
## n = 7~8 ⇒ nx = 4 ⇒ 槽位 ≤ 4 025 × 0.86 / 4 = 865 m ⇒ 塔宽天花板 555 m
## ```
## ⇒ 唯一出路是让大格**跨格**（`MapDef.city_block_span_x = 2`，把中间那条 110 m
## 支路吃掉）。落地后大格边长 **7 406 × 3 703 m**、槽位 **1 852 m**。
## ★ 本探针那行 **`塔宽实测`**（`Tower_*` 的 `scale.x` 全城均值 / 中位 / 极值）
## 就是这一轮唯一在意的读数 —— 跨 `prev` 两档跑同一条机器即可对比。
##
## ## ⚠️⚠️ 机位是**自动**定的（数实建的 `Tower_*`），别改回写死坐标
## 这个数落空过三次（中央公园 / 达沃的岛北移 / `_city_lot_h` 记的是"计划"不是"实建"），
## 完整清单写在 `_ready()` 里那一段注释。**换图、换种子都不该需要动机位。**

var out_dir := "user://b7_shots"
var _idx := 0
var world: WorldBuilder


func _ready() -> void:
	# ⚠️⚠️ **看门狗**（与 `_b7_road_ab.gd` 同一段理由）：带窗口跑时 `_ready()` 里
	# 任何一条抛错都会静默中断协程，而 `quit()` 在最后一行 ⇒ 进程**永远不退出**。
	get_tree().create_timer(300.0).timeout.connect(_on_watchdog)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	var city := "oenb"
	if args.size() > 1:
		city = args[1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	world = WorldBuilder.new()
	add_child(world)
	await get_tree().physics_frame
	# ---- ⚠️ 第 3 个参数 `legacy`：出"**改前**"对照图 ----
	#
	# 2026-09-28 用户第 ④ 条把达沃的 `city_tower_w / city_height_mul` 从
	# `0.62 / 1.15` 改成 `1.55 / 0.92`。要给用户看改前改后的对照，就得能拍出旧值 ——
	# 而**不能**去改工程文件（改回来再改过去，中间任何一个环节断了都是灾难）。
	#
	# ⇒ `MapDef.davao()` **每次都返回一个新实例** ⇒ 在**传进 `apply_map()` 之前**
	# 改这个对象的两个字段即可。**工程文件一个字都不动**，进程退出后一切照旧。
	# ⚠️ `0.62 / 1.15` 是**历史值**（工程里已经读不到了），所以这里必须写死 ——
	# 它是"对照组的定义"，不是"要被维护的参数"。
	var mp: MapDef = MapDef.oenbelli() if city == "oenb" else MapDef.davao()
	# ⚠️ 第 3 个参数是三选一（2026-09-28 深夜重定义）：
	#   `prev`   = **上一版**（交付给用户的那版：`nx = 3`、不跨格）
	#              —— 用来回答"这一轮到底改了多少"
	#   `legacy` = **细高版**（`0.62 / 1.15` ＋ 不跨格 ＋ `nx = 4`）= 用户第 ④ 条之前的样子
	#   不给     = 本轮（`span_x 2` ＋ `fill 0.92` ＋ `nx = 4` ＋ `1.55 / 0.92`）
	# ⚠️ **每一档都必须把地块侧的三件套一起回退**（`span_x` / `big_fill` / `big_n`）：
	# 本轮的改动同时动了这三样，只回退其中一样拍出来的**不是"改前"**
	#（上一轮就踩过：只回退倍率，塔宽没动，因为宽度是 `nx` 给的）。
	# 三档跑**同一格**（第 4 个参数）才可比 —— 见下面强制机位那段。
	if args.size() > 2 and (args[2] == "legacy" or args[2] == "prev"):
		if args[2] == "legacy":
			mp.city_tower_w = 0.62
			mp.city_height_mul = 1.15
			mp.city_block_big_n = Vector2i(7, 8)
		else:
			mp.city_block_big_n = Vector2i(4, 5)   # 上一版的"降一档"
		mp.city_block_small_n = Vector2i(2, 3)
		mp.city_block_span_x = 1
		mp.city_block_big_fill = WorldBuilder.CITY_BLOCK_BIG_FILL
		print("== ⚠️ %s 模式：达沃就地改回 tower_w %.2f / height_mul %.2f"
			% ["LEGACY（细高版）" if args[2] == "legacy" else "PREV（上一版）",
				mp.city_tower_w, mp.city_height_mul]
			+ " / span_x 1 / big_fill 0.66~0.86 / big_n %s（nx = %d）"
			% [str(mp.city_block_big_n),
				WorldBuilder.city_block_grade(0, 0, mp.city_seed,
					mp.city_block_big_n, mp.city_block_small_n, 1,
					mp.city_block_big_fill, mp.city_block_small_fill)["nx"]])
	world.apply_map(mp)
	await _frames(20)

	var cb := WorldBuilder.CITY_CBLOCK
	var shape: Dictionary = WorldBuilder.CITY_SHAPE[world.map.city_layout]
	var rr := float(shape.via_ring_r)
	print("== B7 出图：%s / 一格 %.0f m / 环线 R %.0f m / 桥宽 %.0f m"
		% [world.map.name_cn, cb, rr, WorldBuilder.CITY_VIA_W])

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 1.0
	cam.far = 400000.0
	add_child(cam)
	cam.current = true

	# ⚠️ 机位一律**落在岛内**（台场 gx[−6,6]×gz[−7,7] ⇒ |x|,|z| ≤ 24 km），
	# 落到岛上以外就是水面/运河，拍出来全黑（上一轮踩过：定在 (30187.5, 30187.5) = (7,7)
	# 格正好是运河 ⇒ 整张图全黑，还误判成"路面没建"）。

	# ⚠️⚠️ **机位必须落在"密集街区"上，而且既不能写死、也不能看 `_city_lot_h`**
	#
	# 三次翻车都记在这里，别再踩：
	#   ① 写死 (4037, 4037)（城市中心）⇒ 奥恩贝利那里是 `plaza`（中央公园）
	#      ⇒ 拍出来一整块空地，看着像"城里一栋楼都没有"。
	#   ② 改写成写死 (−14 087.5, −8 050) ⇒ 奥恩贝利对了，**达沃全错**：
	#      达沃的岛整体北移 5 格（`CITY_SHAPE[DAVAO].cz = 5`）⇒ 那个坐标在海里。
	#   ③ 改成"`_city_lot_h` 里名义楼高最高的一格" ⇒ 又错：那张表是在
	#      `city_lot_for()` 之后**无条件**回填的（`world_builder.gd:5182`），
	#      **早于**"这一栋的落位干不干燥"的判据 ⇒ 它记的是**计划**、不是**实建**。
	#      实测达沃格 (2,7) 名义 4 777 m，而 `city_is_dry()` 把那一整片滤光了：
	#      拍出来只有两块楼 + 一整片海。
	#
	# ⇒ 最终做法：遍历实际存在的 `Tower_*` 节点，按 `CITY_CBLOCK` 分格，
	# 取**「格内塔高之和」最大**的那一格。
	#   · 只数**栋数**不够：城市**边缘**的大格也是 8 栋（`city_block_grade()` 与
	#     离市中心的距离无关）—— 实测两城都选到格 (15,·)（离图心 62 km，岛边），
	#     那里的楼只有 100~500 m 高，拍出来每栋都是一块**扁平的瓦**，
	#     完全读不出"楼有多粗"（那是外围低层住宅，不是这座城市的名片）。
	#   · 高度取 `MeshInstance3D.scale.y`（`_add_box()` 把尺寸写在那儿）。
	#   · 机位 = 该格内所有塔的**位置平均**（保证落在楼群中间，而不是格的几何中心 ——
	#     楼常常只占了格的一角）。
	# 这个判据只依赖"真的建出来的几何"，两城 / 换图 / 换种子都不会再落空。
	var tally: Dictionary = {}
	var score: Dictionary = {}
	var sumx: Dictionary = {}
	var sumz: Dictionary = {}
	# ⚠️ 2026-09-28 晚：**塔宽实测**（用户这一轮唯一在意的量："房子太细" → "粗"）。
	# ⚠️ 取 `MeshInstance3D.scale.x` 而**不是** basis 的长度：`_add_city_body()` 把
	# 尺寸写在 scale 上，而 yaw 会进 basis ⇒ 读 basis 会把"宽 / 深"在某些朝向下对调。
	var wsum: Dictionary = {}
	var all_w: Array[float] = []
	for nd: Node in _find_prefixed(world._terrain_root, "Tower_"):
		var p: Vector3 = (nd as Node3D).global_position
		var key := Vector2i(int(floorf(p.x / cb)), int(floorf(p.z / cb)))
		var hh := 0.0
		var ww := 0.0
		for c in nd.get_children():
			var mi := c as MeshInstance3D
			if mi != null:
				hh = mi.scale.y
				ww = mi.scale.x
				break
		tally[key] = int(tally.get(key, 0)) + 1
		score[key] = float(score.get(key, 0.0)) + hh
		sumx[key] = float(sumx.get(key, 0.0)) + p.x
		sumz[key] = float(sumz.get(key, 0.0)) + p.z
		wsum[key] = float(wsum.get(key, 0.0)) + ww
		all_w.append(ww)
	var best := Vector2i.ZERO
	var best_n := 0
	var best_sc := -1.0
	for k: Vector2i in score.keys():
		var sc: float = float(score[k])
		# 先比"塔高之和"，平手再比栋数（同高的两格，取楼多的那个当机位更稳）
		if sc > best_sc or (is_equal_approx(sc, best_sc) and int(tally[k]) > best_n):
			best_sc = sc
			best_n = int(tally[k])
			best = k
	var dp := Vector3((float(best.x) + 0.5) * cb, 0.0, (float(best.y) + 0.5) * cb)
	if best_n > 0:
		dp = Vector3(float(sumx[best]) / float(best_n), 0.0,
			float(sumz[best]) / float(best_n))
	else:
		# 兜底：一栋塔都没有说明这一版建城整个空了（那本身就是要查的事）
		# ⇒ 退到图心，**并且明确喊出来**，不要让整组图静默拍在一片水上。
		push_error("`Tower_*` 一个都没有 ⇒ 自动机位失效，退回图心")
		print("== ⚠️ 找不到任何 `Tower_*`，机位退回图心")
	print("== 密集机位（格内塔高之和最大）：格 %d,%d 有 %d 栋塔、塔高和 %.0f m ⇒ 机位 (%.0f, %.0f)"
		% [best.x, best.y, best_n, best_sc, dp.x, dp.z])
	# ---- ⚠️ 2026-09-28 晚：第 4 个参数 `gx,gz` = **强制机位格** ----
	#
	# ## 为什么"对照图"必须有这个开关
	# 自动机位选的是"**格内塔高之和**最大"的那一格，而这个统计量**本身就随本轮改动变**
	#（本轮把每格栋数从 7~8 降到 4~5 ⇒ 同一格的塔高之和变小）⇒ 两档会挑到**不同的格**、
	# 拍到**不同的地方**，两张"改前 / 改后"根本没法比。
	# 实测：上一版（`nx = 4`）选到格 **(−4, 4)**，本轮（`nx = 3`）选到格 **(−5, 7)** ——
	# 位置差了 6 km，出图并排看会得出"楼形状变了"这种假结论。
	# ⇒ 出对照图时用本参数把格**钉死**，并且机位取**格心**（不是"该格塔的位置平均" ——
	#   那个也会随槽位变化漂几米）。
	# ⚠️ 强制格**必须两条臂都有楼**：这一格空了的话这里会明确喊出来（不静默拍空地）。
	if args.size() > 3:
		var parts := args[3].split(",")
		if parts.size() == 2:
			best = Vector2i(int(parts[0]), int(parts[1]))
			best_n = int(tally.get(best, 0))
			best_sc = float(score.get(best, 0.0))
			dp = Vector3((float(best.x) + 0.5) * cb, 0.0, (float(best.y) + 0.5) * cb)
			print("== ⚠️ **强制机位格** %d,%d（该格本档有 %d 栋塔）⇒ 机位取格心 (%.0f, %.0f)"
				% [best.x, best.y, best_n, dp.x, dp.z])
			if best_n == 0:
				push_error("强制机位格 %d,%d 这一档**一栋塔都没有** ⇒ 对照图无效"
					% [best.x, best.y])
	# ---- ⚠️ 2026-09-28 晚：**塔宽实测**（这一轮的唯一判据读数）----
	# ★ 这一行必须在**同一副光照、同一张图、同一台机器**上跨"改前 / 改后"两档对比才有意义：
	#   `_b7_shots.gd ... legacy` 就是那个"改前"档（只改内存里的 `MapDef`）。
	if all_w.size() > 0:
		all_w.sort()
		var w_mean := 0.0
		for v in all_w:
			w_mean += v
		w_mean /= float(all_w.size())
		var w_med: float = all_w[all_w.size() / 2]
		var w_at_best := 0.0
		if best_n > 0:
			w_at_best = float(wsum[best]) / float(best_n)
		print("== ★ 塔宽实测（`Tower_*` 的 `scale.x`，单位 m）：全城 **%d 栋** · 均值 **%.0f**"
			% [all_w.size(), w_mean]
			+ " · 中位 %.0f · 最细 %.0f · 最粗 %.0f ｜ 密集那一格 %d 栋平均 **%.0f**"
			% [w_med, all_w[0], all_w[all_w.size() - 1], best_n, w_at_best])
	else:
		push_error("`Tower_*` 一栋都没有 ⇒ 塔宽读数无法产出")

	# ① 正俯视 2 格（8.05 km）：一格 4 025 m，画面竖向 8 km 就是两格。
	#    高度 = 半画面 / tan(fov/2) = 4025 / 0.5774 = 6 971 m。
	var h2 := cb / tan(deg_to_rad(30.0))

	# ⚠️ 高空一律**关天气层**（否则 7 km 以上是一整张米色，什么都读不出）；
	# 低空几张（05/06/07）再打开 —— 那几张要的就是**真实大气**。
	_set_weather(false)

	# ---- 第一组：**实景**（原光照）—— "游戏里长什么样" ----
	await _look(cam, Vector3(dp.x, h2, dp.z),
		Vector3(dp.x, 0.0, dp.z), "01_实景_topdown_2x2_blocks")
	# ---- 第二组：**判据光照**（强方向光 + 抬环境光）—— "结构对不对" ----
	# ⚠️ 见 `_set_judge_light()` 那段：这张图的 `dusk_overcast()` **没有太阳**
	#（实测 `sun.light_energy = 0.30` / `ambient = 1.80`），不换一副判据就数不出
	# "一格几栋楼"（屋顶/立面亮度几乎相同 ⇒ 一律读成平瓦）。
	# ⚠️ 达沃是 `night()`，同一件事更严重（不过它窗户全亮，反而自带立体线索）。
	_set_judge_light(true)
	await _look(cam, Vector3(dp.x, h2, dp.z),
		Vector3(dp.x, 0.0, dp.z), "02_判据_topdown_2x2_blocks")
	# 正俯视**一格**（画面竖向正好一格）⇒ 数得清"一格几栋"。
	await _look(cam, Vector3(dp.x, (cb * 0.5) / tan(deg_to_rad(30.0)), dp.z),
		Vector3(dp.x, 0.0, dp.z), "03_判据_topdown_one_block")
	# 正俯视 6 格（24.15 km）：高度 ×3 ⇒ 看大格小格**混在一起、疏密不均**。
	# ⚠️ 同样从 `dp` 起（不是图心）：达沃的图心在海上，从图心拍看不到楼。
	await _look(cam, Vector3(dp.x, h2 * 3.0, dp.z),
		Vector3(dp.x, 0.0, dp.z), "04_判据_topdown_6x6_blocks")
	_set_judge_light(false)

	# ---- 第三组：**路面**（实景 + 真实大气） ----
	_set_weather(true)
	# 低空沿主干道（±z 上那条 `gi == 0` 的 460 m 路）：看路肩 + 标线。
	await _look(cam, Vector3(-9000.0, 220.0, -420.0),
		Vector3(40000.0, 120.0, 0.0), "05_low_along_trunk")
	# 45° 斜俯看路面横断面（离路面 1 500 m，看 12 m 路肩的实边）。
	await _look(cam, Vector3(-3000.0, 1100.0, -2600.0),
		Vector3(9000.0, 40.0, 0.0), "06_road_cross_section")
	# **贴地**沿主干道（y ≈ 18 m，站在路面上往前看）= 玩家真正看到的那一眼。
	#    ⚠️ y 必须**高于桥面顶**（板顶 = 沿线地形函数均值 + LIFT 1.6 + T/2 4.0 ≈ 地形 + 5.6 m），
	#    否则相机在路堤里面，拍出来是一整片黑。
	await _look(cam, Vector3(-9000.0, 18.0, -40.0),
		Vector3(40000.0, 8.0, 0.0), "07_groundeye_along_trunk")

	# ---- 第四组：**环线**（"能不能通车"） ----
	# ⚠️ 环线在 27.6 km 半径上、桥面 240…1321 m ⇒ 3 km 正俯视**必须**关天气层，
	# 否则一根带子糊在米色里。判据光照只为把"连续带 + 中线"照出来。
	_set_weather(false)
	_set_judge_light(true)
	await _look(cam, Vector3(rr + 0.5, 3000.0, 0.5),
		Vector3(rr, 0.0, 0.0), "08_判据_ring_topdown")
	_set_judge_light(false)
	# 环线切线低空（看桥面 / 护栏 / 中线三层）—— 这一张用**实景**，要的就是真实大气。
	_set_weather(true)
	await _look(cam, Vector3(rr - 260.0, 520.0, -6500.0),
		Vector3(rr - 260.0, 340.0, 22000.0), "09_实景_ring_low_along")
	# 环线斜俯全景（看整圈是不是圆）。
	_set_weather(false)
	_set_judge_light(true)
	await _look(cam, Vector3(0.0, rr * 0.62, rr * 2.1),
		Vector3(0.0, 600.0, 0.0), "10_判据_ring_overview")
	_set_judge_light(false)

	# ---- 第五组：**玩家看到的楼群**（市中心低空平视）----
	#
	# ⚠️ 这一张是 2026-09-28 用户第 ④ 条（"**达沃的楼太细**"）的**直接判据**。
	# 正俯视量的是**占地**；"楼有多粗"在俯视图里读不出来 —— 那里看到的先是
	# **线脚叠出来的同心框**（塔高 2~3 km、每栋几十道腰线，俯视时层层可见），
	# 立面被完全遮住（实测 03 那张：满画面金色同心矩形）。
	# 玩家进游戏看到的是**贴地/低空**的那一眼 ⇒ 判据图必须有一条同样的视线。
	#
	# 机位从自动算出来的 `dp`（市中心楼高最集中的一格）往外退 7 km、抬到 380 m，
	# 略微上仰看向楼群 —— 楼群的中段正好占满画面。
	_set_weather(true)
	await _look(cam, Vector3(dp.x, 380.0, dp.z - 7000.0),
		Vector3(dp.x, 900.0, dp.z), "11_实景_loweye_towers")

	print("B7_SHOTS_DONE -> ", out_dir)
	get_tree().quit(0)


## ## 判据光照档：把"阴天黄昏 · **没有太阳**"临时换成一盏**斜上方强太阳 + 抬高的环境光**
##
## 这一档**不是**"把画面调亮"，而是**换一副判据**（`_r5_shots` 的 `_set_weather` 同理）。
##
## 为什么必须换：`MapDef.oenbelli()` 用的是 `TimeOfDay.dusk_overcast()`，原文写着
## **「铅灰压顶、没有太阳、没有星、散射光天下」**、且 `_city_dusk_overcast()` 特意
## **把环境光提上去、把太阳压下去**（楼只能靠天光被看清）。于是：
##   · 没有方向光 ⇒ 屋顶与立面的**亮度几乎相同** ⇒ **任何立体结构都只能读成一片平瓦**；
##   · 实测 7 km 正俯视：**87.6% 的像素落在 0…2**（纯黑），亮的只有路肩(.74)/标线(.95)。
## ⇒ 上一轮"田字格一个地块一个房子"这个观感，**一半来自绕序 bug、一半来自这里**；
##   而"一格 7~8 栋"（`CITY_BLOCK_BIG_N`）**在同一副光照下根本数不出来**。
##
## 恢复时把三个数原样写回（`sun.rotation_degrees` / `sun.light_energy` /
## `_env.ambient_light_energy`）—— 见 `_b7_vis` 那条 `material_override` 的教训：
## **凡改过的运行时参数一律存住再写回。**
var _sun_rot: Vector3
var _sun_energy := 0.0
var _amb_energy := 0.0
var _judge_saved := false

func _set_judge_light(on: bool) -> void:
	if world.sun == null:
		return
	if on and not _judge_saved:
		_sun_rot = world.sun.rotation_degrees
		_sun_energy = world.sun.light_energy
		if world._env != null:
			_amb_energy = world._env.ambient_light_energy
		_judge_saved = true
	# 斜上方 58°、方位 −40°：屋顶全亮、迎光立面半亮 ⇒ 立体线索最强。
	world.sun.rotation_degrees = Vector3(-58.0, -40.0, 0.0) if on else _sun_rot
	world.sun.light_energy = 1.8 if on else _sun_energy
	if world._env != null:
		world._env.ambient_light_energy = 1.10 if on else _amb_energy
	print("[b7sh] 判据光照 = %s（sun energy %.2f / ambient %.2f）"
		% ["**开**" if on else "关（回实景）", world.sun.light_energy,
			world._env.ambient_light_energy if world._env != null else -1.0])


## 天气层（云带 / 距离雾 / 体积雾 / 海雾）开关 —— 见文件头那段。
func _set_weather(on: bool) -> void:
	if world._cloud_root != null:
		world._cloud_root.visible = on
	if world._sea_mist != null:
		world._sea_mist.visible = on
	if world._env != null:
		world._env.fog_enabled = on
		world._env.volumetric_fog_enabled = on
	print("[b7sh] 天气层 = %s" % ("开" if on else "**关**（高空判据图）"))


func _look(cam: Camera3D, from: Vector3, at: Vector3, shot_name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _frames(8)
	await _shot(shot_name)


func _on_watchdog() -> void:
	print("WATCHDOG_TIMEOUT")
	get_tree().quit(3)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 递归收集**节点名以 `pre` 开头**的所有后代（含 `root` 自己）。
##
## ⚠️ 不用 `find_children("*", "", true, false)`：那要字符串通配、还会带上
## 引擎自己的内部节点；这里只要一个前缀匹配，手写一遍更可控。
## ⚠️ 也**不能**按"`Node3D` 的 `position`"直接读塔楼位置 —— `Tower_*` 是
## `StaticBody3D`（`_add_box()` 建的），它的 `position` 就是世界位置（父节点
## `_terrain_root` 在原点），但用 `global_position` 更稳、且不依赖那个前提。
func _find_prefixed(root: Node, pre: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if str(n.name).begins_with(pre):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _shot(shot_name: String) -> void:
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
	var p := out_dir.path_join("%02d_%s.png" % [_idx, shot_name])
	print("SHOT %s err=%d" % [p, img.save_png(p)])
