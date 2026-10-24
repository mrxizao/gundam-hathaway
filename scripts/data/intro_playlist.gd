class_name IntroPlaylist
extends RefCounted
## 开场动画的**选片表**（纯数据 + 纯函数，不碰节点、不碰文件系统）。
##
## ## 需求（用户原话）
##   ① 「我们做一个进游戏一开头就会播的动画系统」→ 动画在 `main._ready()` 之后、
##      主菜单**之前**播，且做成"表驱动"的（加片子只动这张表，见 `scripts/ui/intro_movie.gd`）。
##   ② 「有 20% 的几率在播动画 2（马夫蒂劫持演说）」
##      → 即 **80% 播`开头动画`，20% 播`马夫蒂劫持演说`**。权重就写在这张表里。
##
## ## 为什么概率必须是这张表里的**权重**，而不是播放器里的一行 `if randf() < 0.2`
## 概率是唯一真源：改比例只改这张表；测试只对 `pick_index()` 断言 —— 它是**纯函数**，
## 给定 `roll` 必得唯一结果，于是"20%"是可以被**逐点验**的（0.799→片 1，0.800→片 2）。
## 写成播放器里的 `if`，就只能靠"跑一万次看分布"来验，那是假验证：
## 分布对得上、边界照样可能写错（`<` 写成 `<=` 之类）。
##
## ## 素材格式
## 播放端是 Godot 的 `VideoStreamPlayer`，**核心只认 Ogg Theora（`.ogv`）**
## （官方文档原话：the only supported format in core is Ogg Theora, with optional
## Ogg Vorbis audio tracks）。两个源文件都是 mp4，已在交付前用 ffmpeg 转码并混流了音轨，
## 见本表 `path` 指向的 `assets/video/*.ogv`。

## 一张片子一项。`weight` 是概率权重（不必是百分数，只要求总和为 1.0）。
##
## ⚠️ **表里的先后顺序不代表概率** —— 一切都看 `weight`。这里恰好按"常见 → 稀有"排，
## 是为了读起来顺，不是因为顺序有语义。
const CLIPS := [
	{
		"id": "op",
		"label": "开头动画",
		"path": "res://assets/video/intro_op.ogv",
		"weight": 0.80,
	},
	{
		"id": "mafty",
		"label": "马夫蒂劫持演说",
		"path": "res://assets/video/intro_mafty.ogv",
		"weight": 0.20,
	},
]

## 权重和必须收敛到 1.0，但浮点累加未必刚好落在 1.0 上（`0.8 + 0.2` 在双精度里是安全的，
## 可一旦以后有人把权重改成 0.7/0.15/0.15 就不一定了）⇒ 判等一律带这个容差。
const WEIGHT_EPS := 0.0001


## 权重总和。**必须等于 1.0** —— 小于 1 会让 `roll` 落在尾部时被兜到最后一个片目
## （见 `pick_index()` 的收尾 return），大于 1 会让最后一项永远抽不到。测试对这条断言。
static func total_weight() -> float:
	var s := 0.0
	for c: Dictionary in CLIPS:
		s += float(c["weight"])
	return s


## `roll ∈ [0, 1)` → 片目下标。**纯函数**：同 `roll` 必同结果，不碰 RNG。
##
## 落在哪一段由**累加权重**决定：先 `op`（`[0, 0.8)`），再 `mafty`（`[0.8, 1.0)`）。
## 于是"20%"这件事在边界上是可验的，而不是统计出来的。
static func pick_index(roll: float) -> int:
	var acc := 0.0
	for i in CLIPS.size():
		acc += float(CLIPS[i]["weight"])
		if roll < acc:
			return i
	# 权重和 < 1.0 时 `roll` 可能落在最后一段之外 —— 兜到最后一个片目，
	# 绝不返回越界下标（`roll` 理论上是 `randf()` 的产物，但纯函数不该假设调用方）。
	return CLIPS.size() - 1


## 下标 → 片目（越界自动夹取）。
static func clip_at(i: int) -> Dictionary:
	return CLIPS[clampi(i, 0, CLIPS.size() - 1)]


## 唯一允许碰随机数的地方：取一次 `roll` 再选片。
## 每次开局只调一次 —— 播到一半再抽一次会让"这一局看到的是哪一支"变得不可复现。
static func pick_random() -> Dictionary:
	return clip_at(pick_index(randf()))


## **素材门**：两个 `.ogv` 是否真的存在。
##
## ⚠️ 单独拎出来是因为"素材缺失"必须**优雅退化**（直接进主菜单），不能黑屏卡住：
## 资源文件不在版本控制里、或者换台机器跑，都可能缺。播放端用它来决定要不要起播。
static func has_any_clip() -> bool:
	for c: Dictionary in CLIPS:
		if ResourceLoader.exists(str(c["path"])):
			return true
	return false
