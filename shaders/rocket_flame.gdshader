shader_type spatial;
// 马夫蒂火箭**主发动机的火焰与拖尾**。
//
// ============================================================ ★ 2026-09-30 新增
//
// ## 为什么要它（老板原话 + 参考图）
// > 「**火箭升空的时候都没有大型火焰拖尾**」
//
// 参考图（老板发来的《发射场景参考》）里最扎眼的就是那一条：细长的箭体下面挂着
// **一条比箭体本身长好几倍的橙白色火柱**，从箭底一直拖到下面的云层，
// 把云层顶端烤成暖色。改前的火箭**一根焰都没有**（箭体 + 出水特效，仅此）。
//
// ## 三个部件（同一份着色器，参数不同）
// | 部件 | 尺寸 | 作用 |
// |---|---|---|
// | `Core` | 半长 / 半径 0.45 | 白蓝**内芯**：喷口那一截最亮，带**激波环**（马赫环） |
// | `Mid` | 全长 / 半径 1.0 | 橙黄**主焰**：这条就是"大型拖尾"本体 |
// | `Haze` | 1.25 倍长 / 1.8 倍半径 | 外圈**稀薄余焰**：把主焰的轮廓糊掉，不出现"一个干净的锥" |
//
// ## ⚠️ 为什么是"锥壳 + 正面比"，而不是"实体锥"
// 实体锥在真机上会读成**一根实心的橙色塑料棒**（每条射线穿过的厚度都一样，
// 亮度处处相同 ⇒ 没有体积、没有"里面比外面热"）。
// 这里用的是**侧面壳**（`CylinderMesh`，`cap_top/bottom = false`）配
// `facing = |dot(N, V)|`：视线正中穿过的壳（法线朝相机）最亮、转到轮廓线趋零 ——
// 与 `sea_smoke.gdshader` 里那条软边是同一条原理，只是烟的 `pow` 指数更大。
//
// ## ⚠️ 一个静默坑：`UV.y` 的零点在哪
// `CylinderMesh` 的 `v` 从**底面**（`−height/2`）到**顶面**（`+height/2`）。
// `RocketFlame` 把网格绕 X 转 +90° ⇒ 底面落在箭体局部 `z = 0`（= 尾喷口）。
// ⇒ `UV.y = 0` **就是喷口**、`1` 是尾端。若哪天把它转成 −90°，
// 焰会**从尾端往喷口烧**（喷口最暗、末端最亮），而那看起来只像"色带反了"。

render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

// 节流（0 = 熄火，1 = 满推力）。由 `RocketFlame.update()` 每帧推。
// ⚠️ 它同时是**开关**：`<= 0.002` 直接 `discard` —— 熄火那一帧焰必须**整根消失**，
// 不能留下一条半透明的橙带贴在箭尾（那看起来像"忘了关"）。
uniform float strength : hint_range(0.0, 1.0) = 0.0;

// 高空膨胀（0 = 海面，1 = 稀薄大气）。真实焰形在真空里**更长更宽**：
// 喷口外没有大气压着它，气体会往外张。由 `RocketFlame` 按箭底高度推。
uniform float widen : hint_range(0.0, 1.0) = 0.0;

// 湍流强度（0 = 一根光滑的锥）。内芯取小、外圈取大 —— 外圈本来就该更散。
uniform float turb : hint_range(0.0, 3.0) = 1.0;

// 逐层的相位偏移。三层共用同一份噪声函数，不偏开的话三层会**逐像素对齐**，
// 叠出来的图案还是"一层"（观察到的效果 = 只画了最外面那层）。
uniform float seed = 0.0;

// 激波环（马赫环）的强度。只有内芯给正值 —— 主焰上没有这圈纹。
uniform float rings : hint_range(0.0, 2.0) = 0.0;

// 整体亮度倍率（每层不同，用来定"谁压过谁"）。
uniform float gain : hint_range(0.0, 3.0) = 1.0;

// 轴向衰减指数：越大 ⇒ 尾端化得越快（主焰 1.35、外圈 2.0）。
uniform float fade_pow : hint_range(0.3, 4.0) = 1.35;

// 三档颜色：喷口（最热）/ 中段 / 尾端（最冷）。
uniform vec3 col_core : source_color = vec3(0.94, 0.98, 1.0);
uniform vec3 col_mid : source_color = vec3(1.0, 0.68, 0.28);
uniform vec3 col_tip : source_color = vec3(0.88, 0.28, 0.09);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, w.x), mix(c, d, w.x), w.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		s += amp * vnoise(p);
		p *= 2.17;
		amp *= 0.5;
	}
	return s;
}

void fragment() {
	if (strength <= 0.002) {
		discard;
	}

	// `f` = 离喷口多远（0 喷口 / 1 尾端）。零点为什么在这边见头注那条静默坑。
	float f = clamp(UV.y, 0.0, 1.0);

	// ---- 正面比当径向剖面（头注那条）----
	// 高空膨胀时指数下压 ⇒ 边缘更实 ⇒ 读起来"这根焰张开了"。
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float body = pow(facing, mix(2.4, 1.05, widen));

	// ---- 轴向：喷口最亮，尾端化掉 ----
	float axial = pow(1.0 - f, fade_pow);

	// ---- 湍流：沿轴**朝尾端**滚动的噪声（火在往外冲）----
	float n = fbm(vec2(UV.x * 7.0 + seed, f * 5.5 - TIME * 6.5 * turb));
	n = 0.52 + 0.78 * n;

	// ---- 激波环（马赫环）：只在喷口附近那三四个 ----
	// `pow(1.0 - f, 3.0)` 把环限制在近喷口段；不乘它的话整条焰会变成斑马纹。
	//
	// ⚠️⚠️ 这里**不能写 `:=`**。`:=` 是 **GDScript** 的类型推断赋值，GLSL 里没有 ——
	// 写了之后整份着色器**编译失败**，而症状是**这条焰整个不画**（材质退回默认），
	// 与"这一轮没做火焰"长得一模一样。
	// 更阴的是：Godot 只在 stderr 打一行 `SHADER ERROR: Expected a ',' or ';'`，
	// **不会让任何测试变红** ⇒ 上一轮 `suite_rocket_launch` 42 条火焰断言全绿，
	// 而着色器是坏的这个事实**一条都没测出来**。
	// （这一处是 2026-09-30 用 `_rocket_shots` 的冒烟日志抓到的。）
	float shock = 1.0 + rings * 0.6 * sin(f * 46.0 - TIME * 9.0) * pow(1.0 - f, 3.0);

	// ---- 上色：三档沿轴插值 ----
	vec3 c = mix(col_tip, col_mid, smoothstep(0.12, 0.55, 1.0 - f));
	c = mix(c, col_core, smoothstep(0.58, 0.96, 1.0 - f));

	// 加色混合下"亮度 = c × a"，所以强度全部塞进 ALPHA，颜色只负责色相。
	float a = strength * body * axial * n * shock * gain;

	ALBEDO = c;
	ALPHA = clamp(a, 0.0, 1.0);
}
