class_name LoadingScreen
extends Control
## 读条界面（批 10）：进入战斗地图前的全屏加载层。
##
## ## 为什么要有它（用户 2026-09-22："做读条系统，辅助游戏加载，
## 在进入战斗地图之前进入读条"）
##
## 这个工程的"换地图"是**纯代码程序化生成**的（`WorldBuilder.apply_map`）：
## 地表 SurfaceTool 网格、三带云 MultiMesh、城市几百个方块……全部同步建完才返回。
## 地图一大（1.2 第二十二轮放大到 129 km 见方），这一帧就能卡住 **数百毫秒到数秒**，
## 玩家看到的是"按了出击 → 游戏冻住 → 突然已经在天上"。
##
## 读条系统做两件事：
##   1. **把那段冻结藏进一张会动的画面里** —— 主流程拆成阶段（见
##      `WorldBuilder.apply_map_staged()`），每个阶段之间 `await` 一帧，
##      读条层借这些帧把自己画出来、把进度条往前推；
##   2. **保证它至少停留一小段时间**（`MIN_VISIBLE`）：地图恰好很快的时候，
##      读条一闪而过比不读条更难受 —— 宁可补齐到 0.6 s。
##
## ## 用法（`main.gd::_begin_match_loading()`）
## [codeblock]
## loading.open("太平洋群岛 · 夜")
## loading.advance(0.2, "重塑地表……")
## await world.apply_map_staged(map)     # 内部会在阶段间发进度
## loading.advance(0.9, "部署机体……")
## spawn_round()
## await loading.finish()                # 补齐最短显示时间 + 淡出
## [/codeblock]
##
## ## 实现备注
## - 与 `MainMenu` / `FlightHUD` 同一套 UI 哲学：**全代码自绘**（`_draw`），
##   工程里没有手搭的 .tscn；挂在 main 的 HUDLayer（CanvasLayer）里。
## - 铺满父级（`set_anchors_and_offsets_preset`，**不是** `set_anchors_preset`）
##   + `mouse_filter = STOP`：
##   读条期间吞掉一切鼠标输入，玩家点不穿它。
## - 进度条显示值向目标值**缓动**而不是跳变：阶段是大颗粒的（地表 → 云 → 时段），
##   跳变会显得"卡了一下又跳一格"，缓动让条一直活着。

## 最短可见时间（秒）。低于这个时长的读条会"闪一下"，宁可补齐。
const MIN_VISIBLE := 0.6
## 进度条显示值向目标缓动的速率。1.8 ≈ 半秒多走完一格大阶段。
const BAR_SPEED := 1.8
## 淡出时长（秒）。
const FADE_OUT := 0.35
## ⚠️ 2026-09-30 用户要求："加载过程中的小提示系统也要删掉"。
## 这里原来有 `TIP_ROTATE` + `TIPS`（6 条提示）轮播。现在是**整块撤除**，不是把数组
## 清空 —— `TIPS` 一空，`randi() % TIPS.size()` 就是除零（`_tip_base` 那行）。
## 别照 `HELP_SECTIONS` 把它加回来。

var _font: Font
## 进度目标（0..1）。显示值向它缓动。
var _target := 0.0
## 显示中的进度（缓动后）。
var _shown := 0.0
## 阶段文字（"重塑地表……"）。
var _step_text := ""
## 读条标题（地图名）。
var _title := ""
## 已可见的时长（秒）—— 用于最短显示时间与提示轮播。
var _visible_t := 0.0
## 是否处于淡出中。
var _fading := false
## 淡出剩余比例（1 → 0）。
var _fade := 1.0


func _ready() -> void:
	# 铺满父级（HUDLayer 是全屏 CanvasLayer）
	# ⚠️ 必须用 `set_anchors_and_offsets_preset`，**不是** `set_anchors_preset`。
	# 后者的语义是「**保持控件当前的视觉矩形**」：它只设 anchors，再反算 offsets 去凑出
	# 「现在这个 0×0 的矩形」⇒ `size` **恒为 (0,0)** ⇒ `_draw()` 永远拿不到屏幕尺寸。
	# 全工程 13 处全屏 Control 只有这里写错过，而且**复发过两次**：
	#   2026-09-22 设计文档（1.3 测试版 §7.6）已逐字定位到这一行，但从未落盘；
	#   2026-10-01 用户肉眼看到「读条界面露出屏幕下的一部分」（底部 100 px 裸视口）。
	# 判据在 `tests/suite_loading.gd` 的「铺满与尺寸」一节（纯布局，**无头可跑**）。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = get_theme_default_font()
	if _font == null:
		_font = ThemeDB.fallback_font
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_visible_t += delta
	# 缓动：显示值向目标靠拢（指数趋近，帧率无关）
	_shown = lerpf(_shown, _target, 1.0 - exp(-BAR_SPEED * delta))
	if _shown > _target:
		_shown = _target
	if _fading:
		_fade = maxf(_fade - delta / FADE_OUT, 0.0)
		if _fade <= 0.0:
			visible = false
	queue_redraw()


## 开一条读条。`title` 通常是地图名（"太平洋群岛 · 夜"）。
func open(title: String) -> void:
	_title = title
	_target = 0.0
	_shown = 0.0
	_step_text = ""
	_visible_t = 0.0
	_fading = false
	_fade = 1.0
	visible = true
	queue_redraw()


## 推进到 `frac`（0..1），同时换阶段文字。**只设目标**：实际条会缓动过去。
func advance(frac: float, label := "") -> void:
	_target = clampf(frac, 0.0, 1.0)
	if label != "":
		_step_text = label
	queue_redraw()


## 等到"条走满 + 至少可见 MIN_VISIBLE 秒"再淡出并等淡出结束。
## 调用方在它返回前不要拆场景（读条还盖在上面呢）。
func finish() -> void:
	# ① 先把目标推满，让条把最后一段走完
	advance(1.0, "准备完毕")
	# ② 等"走满"。⚠️ 不能等 0.999：缓动是指数趋近（每帧只逼近一点），
	#    最后 0.1% 还要再等约 4 秒 —— 玩家会盯着 97% 的条干着急
	#   （批 10 bug 排查 2026-09-22 修的）。97% 之后条头只剩 ~14 px，
	#    直接一次补齐到头，肉眼无感。
	while _shown < 0.97:
		await get_tree().process_frame
	_shown = _target
	# ③ 补齐最短可见时间
	while _visible_t < MIN_VISIBLE:
		await get_tree().process_frame
	# ④ 淡出并等它结束
	_fading = true
	while _fading and _fade > 0.0:
		await get_tree().process_frame


## 立刻收掉（不给最短时间与淡出 —— 异常路径 / 测试用）。
func close_now() -> void:
	visible = false
	_fading = false
	_fade = 0.0


## 读条是否正在显示（测试断言用）。
func is_showing() -> bool:
	return visible


## 当前显示进度（测试断言用：advance 之后会向目标缓动）。
func shown_progress() -> float:
	return _shown


## 本层的绘制尺寸（逻辑像素）。
##
## ⚠️ 兜底**也不许硬编码**画布尺寸。万一 `size` 又变 0（例如锚点写法被人改回
## `set_anchors_preset`），也要退回**父级区域**把整个屏幕铺满：
##   - 硬编码 ⇒ 露出裸视口（本 bug 两次复发就是这么来的：兜底按 1600×900 画，
##     而真机逻辑画布是 1600×1000 ⇒ 底部空出 100 px）；
##   - 干脆不画 ⇒ 读条**整屏透明**，比「露一条边」更难排查。
## 挂进 CanvasLayer（父不是 Control）时，`get_parent_area_size()` 返回的就是视口
## 可见区域 —— 正是本层要铺满的那个矩形。
func _view_size() -> Vector2:
	var v := size
	if v.x <= 0.0 or v.y <= 0.0:
		v = get_parent_area_size()
	return v


func _draw() -> void:
	var view := _view_size()
	var col_a := 1.0 if not _fading else _fade
	# ---- 背景：深蓝黑 ----
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.015, 0.03, 0.06, 0.985 * col_a), true)
	# ---- 标题（地图名）----
	var cx := view.x * 0.5
	var title_y := view.y * 0.38
	_draw_center(Vector2(cx, title_y), _title, 34, Color(0.90, 0.96, 1.0, col_a))
	# ---- 阶段文字 ----
	_draw_center(Vector2(cx, title_y + 46.0), _step_text, 19,
		Color(0.62, 0.78, 0.92, col_a))
	# ---- 进度条 ----
	var bar := Rect2(Vector2(cx - 240.0, title_y + 76.0), Vector2(480.0, 14.0))
	draw_rect(bar, Color(0.10, 0.16, 0.24, col_a), true)
	draw_rect(bar, Color(0.30, 0.46, 0.62, col_a), false, 1.5)
	if _shown > 0.003:
		var fill := Rect2(bar.position, Vector2(bar.size.x * _shown, bar.size.y))
		draw_rect(fill, Color(0.55, 1.0, 0.74, 0.92 * col_a), true)
		# 条头一道更亮的细线，让推进感更明显
		draw_rect(Rect2(
			Vector2(bar.position.x + bar.size.x * _shown - 2.0, bar.position.y),
			Vector2(2.0, bar.size.y)), Color(0.85, 1.0, 0.92, col_a), true)


## 居中一行字（描边 + 主体，和主菜单同一套描边习惯）。
func _draw_center(at: Vector2, s: String, fs: int, col: Color) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := at - Vector2(w * 0.5, 0.0)
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4,
		Color(0.0, 0.02, 0.05, col.a))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
