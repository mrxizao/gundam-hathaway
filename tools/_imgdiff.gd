extends SceneTree
## 像素级差分：判"形态层到底有没有改变画面"。
##
## 为什么要它：出图里有**粒子/尾焰**每帧在动 ⇒ `md5` 不同**不能**证明形态层生效。
## 唯一的办法是**对照**：
##   ① 同组内 `morph 0.00 vs 1.00`  —— 待测信号（形态层差分 + 粒子噪声）
##   ② 同组内 `morph 1.00 vs 1.00`  —— 纯噪声底（只有粒子在动）
## 若 ① ≈ ② ⇒ 信号淹没在噪声里 ⇒ **形态层没有改变画面**。

const DIR := "C:/Users/MSIPC/WorkBuddy/2026-09-25-15-13-53/gundam-anim/_relay/_shots_xi_sync"

const PAIRS := [
	["★冻结 · 信号 (m0→m1)", "frozen_full_f00_m0.00.png", "frozen_full_f30_m1.00.png"],
	["冻结 · 噪声底 (f30→f36)", "frozen_full_f30_m1.00.png", "frozen_full_f36_m1.00.png"],
	["★冻结尾视 · 信号", "frozen_tail_f00_m0.00.png", "frozen_tail_f30_m1.00.png"],
	["冻结尾视 · 噪声底", "frozen_tail_f30_m1.00.png", "frozen_tail_f36_m1.00.png"],
	["缓动 · 首段 (m0→0.22)", "frozen_full_f00_m0.00.png", "frozen_full_f06_m0.22.png"],
	["缓动 · 中段 (0.22→0.44)", "frozen_full_f06_m0.22.png", "frozen_full_f12_m0.44.png"],
]


func _initialize() -> void:
	print("")
	print("########## 形态层出图 像素差分 ##########")
	print("  目录 %s" % DIR)
	print("  %-22s %-30s %10s %10s %8s %8s"
		% ["对照", "A → B", "平均|Δ|/255", "变化像素%", "最大Δ", "判定"])
	for p in PAIRS:
		_diff(str(p[0]), str(p[1]), str(p[2]))
	print("")
	print("VERDICT: IMGDIFF-DONE")
	quit(0)


func _diff(tag: String, fa: String, fb: String) -> void:
	var ta := ImageTexture.new()
	var a := Image.new()
	var b := Image.new()
	var ea := a.load(DIR.path_join(fa))
	var eb := b.load(DIR.path_join(fb))
	if ea != OK or eb != OK:
		print("  %-22s !! 读图失败（%d / %d）" % [tag, ea, eb])
		return
	a.convert(Image.FORMAT_RGBA8)
	b.convert(Image.FORMAT_RGBA8)
	if a.get_size() != b.get_size():
		print("  %-22s !! 尺寸不同 %s vs %s" % [tag, str(a.get_size()), str(b.get_size())])
		return
	var w := a.get_width()
	var h := a.get_height()
	var sum := 0.0
	var mx := 0
	var changed := 0
	var n := 0
	# 隔 2 像素采样：判"有没有整体形变"够用，也快得多。
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) \
				+ absf(ca.b - cb.b)
			d = d / 3.0 * 255.0
			sum += d
			n += 1
			if d > 8.0:
				changed += 1
			if int(d) > mx:
				mx = int(d)
	var mean := sum / maxf(float(n), 1.0)
	var pct := 100.0 * float(changed) / maxf(float(n), 1.0)
	var verdict := "-"
	if tag.find("信号") >= 0:
		verdict = "**有信号**" if pct > 1.0 else "≈ 零（形态层没改变画面）"
	print("  %-22s %-30s %10.3f %9.2f%% %8d %8s"
		% [tag, "%s → %s" % [fa.substr(0, 12), fb.substr(0, 12)], mean, pct, mx, verdict])
