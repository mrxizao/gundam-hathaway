shader_type spatial;
// 出水**烟雾**（马夫蒂火箭从海里顶起来时，水面炸开的那一片滚滚的烟）。
//
// ============================================================ ★ 2026-09-30 新增
//
// ## 为什么要它（老板原话）
// > 「**发射时候的周围环绕的东西做成风压太丑陋了，还不如做成烟雾呢**」
//
// 在这之前"水柱"是**一根圆柱壳**（`SplashColumn`：半径 62~96 m、高 `alt+130` m，
// 而且与火箭**同一个 XZ**）。它在真机像素上的实测读数：
//
// | 图 | 读数 | 看到的东西 |
// |---|---|---|
// | `02_breach_side` | 亮 0.9416 / 均值 167.7 | 一根**满屏的纯白巨柱**，把火箭整个吞掉 |
// | `04_rocket_side` | 亮 **1.0000** / 均值 **255.0** | 整幅纯白 —— 连箭体都拍不到 |
// | `05_rocket_top` | 亮 0.9869 / 均值 241.2 | 同上 |
//
// ⇒ 它读起来不是"水"，是一层**包住箭体的白壳**（老板说的"风压"）。
// 三个成因，缺一不可：
//   ① **几何**：圆柱壳与箭同轴 ⇒ 它必然包住箭，且从侧面看是一面**竖直的墙**；
//   ② **纯白**：`tint = (0.90,0.94,0.97)` + `unshaded` ⇒ 夜图里它是画面里最亮的东西；
//   ③ **不透明**：`ALPHA = alpha * band`，`band` 在高度中段是 1.0 ⇒ 直接盖死。
//
// ## 这一版把它改成**烟雾**（三处对症）
// | 症状 | 改法 |
// |---|---|
// | ① 包住箭的圆柱壳 | 改成 **72 团各自独立的球**（`SplashSmoke` MultiMesh），球心**不在轴线上** —— 落在半径 `SMOKE_R0..R1` 的环上并向外飘 ⇒ 它是**一圈往外滚的烟**，箭体从烟里露出来 |
// | ② 纯白 | 底色换成**暗灰**（`tint_dark`），只有被**引擎火烤到的那一侧**才是暖亮（`tint_glow` + `glow`）—— 夜里冒出来的烟本来就该是暗的、底下一圈是亮的 |
// | ③ 硬边 | **正面比**（`dot(NORMAL, VIEW)`）当软边：正对相机最浓、边缘趋零 ⇒ 团与团之间自然交融，没有硬轮廓 |
//
// ## ⚠️ 为什么用**球**而不是公告板面片
// 云用的是"绕世界 Y 转的盘"（`_add_cloud_layer`），因为云在几百米外、只从下方看。
// 烟在相机**旁边**（发射段机位离箭体 66 m），四张判据图里既有平视也有俯视 ——
// 盘在俯视时会退化成一条线。球没有这个问题，代价只是顶点数（球 8×6 段 ≈ 84 三角）。
//
// ## ⚠️ 逐实例去相关：`MODEL_MATRIX[3]`
// `MultiMesh` 的所有实例共用同一份网格 ⇒ `VERTEX`（局部坐标）**逐实例相同**。
// 直接拿它算噪声，72 团会显示**同一个花纹**（看起来像"同一朵烟复制了 72 份"）。
// ⇒ 用实例的**世界原点**（`MODEL_MATRIX[3].xyz`）投影出一个种子，把噪声平移开。
// 这一条是"读起来是烟"与"读起来是贴图"的分界。

render_mode blend_mix, depth_draw_never, unshaded, shadows_disabled;

// 总体不透明度（0 = 完全没有，1 = 最浓）。由 `SeaSplash` 每帧推。
uniform float alpha : hint_range(0.0, 1.0) = 0.0;

// 引擎火照到烟的那一侧有多亮（0 = 冷烟、1 = 整团被烤亮）。
// 由 `SeaSplash` 按**箭底高度**推：越贴近水面/尾焰越亮，升上去就冷掉。
uniform float glow : hint_range(0.0, 1.0) = 1.0;

// 整体浓度倍率。只用来做"烟越抽越稀"（与 `alpha` 分开：那是"有没有"，这是"多厚"）。
uniform float dens : hint_range(0.0, 2.0) = 1.0;

// 噪声密度（一团烟里有多少个"疙瘩"）。太小是光滑的球，太大是噪点。
uniform float scale : hint_range(0.5, 8.0) = 2.2;

// 暗部（冷烟） / 亮部（被火烤到的烟）。
// ⚠️ `tint_glow` 实测**不能给饱和的橙**：`(0.92, 0.58, 0.26)` 那版在整屏烟团叠满时
// 读出来是一整片「橙黄泡沫」，看不出是烟。改成**偏灰的暖白**（红蓝差从 0.66 压到 0.36），
// 火烤的暖意靠 `glow` 的强度去表达，不靠色相。
uniform vec3 tint_dark : source_color = vec3(0.17, 0.17, 0.19);
uniform vec3 tint_glow : source_color = vec3(0.84, 0.66, 0.48);
// 顶部混进的大气色（烟散到高处就淡了，混一点偏冷的灰蓝）。
uniform vec3 tint_thin : source_color = vec3(0.34, 0.36, 0.42);

varying vec3 lpos;

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
		p *= 2.13;
		amp *= 0.5;
	}
	return s;
}

void vertex() {
	// ⚠️ `vertex()` 里的 `VERTEX` 是**局部坐标**（模型矩阵还没乘上去），
	// 所以它逐实例相同 —— 逐实例去相关靠下面的 `seed`。见头注。
	lpos = VERTEX;
}

void fragment() {
	if (alpha <= 0.002) {
		discard;
	}

	// ---- 逐实例种子（头注那条）----
	vec3 worigin = MODEL_MATRIX[3].xyz;
	float seed = dot(worigin, vec3(0.113, 0.271, 0.197));

	// ---- 烟团的"疙瘩"：它让一团烟不是一个光滑的球 ----
	// 时间一项让烟**自己翻滚**（而不是整团平移）——"滚滚"这个词全靠它。
	float n = fbm(lpos.xz * scale + seed + vec2(TIME * 0.13, TIME * -0.21));
	// 竖直方向再叠一层低频：烟柱子是一节一节的，不是上下均匀的
	n = n * 0.72 + fbm(lpos.xy * scale * 0.7 + seed * 1.7) * 0.28;

	// ---- 软边：**正面比**当透明度（头注 ③）----
	// `NORMAL` 在片元里是**视空间**的，`VIEW` 是"从这片元指向相机"的方向。
	// 正对相机 ⇒ 视线穿过烟团最厚的一段 ⇒ 最浓；转到边缘 ⇒ 趋零 ⇒ 没有硬轮廓。
	// ⚠️ 别改成 `1.0 - facing`（那是**菲涅尔**，会把每一团都画成一枚亮边的玻璃球，
	// 而烟雾恰恰相反：中心厚、边缘薄）。
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float soft = pow(facing, 0.55);

	// ---- 高度剖面：底部浓、顶部散 ----
	// `lpos.y` ∈ [−1, 1]（`SphereMesh` 在 `SeaSplash` 里按 radius 1 / height 2 建）。
	float hgt = clamp(lpos.y * 0.5 + 0.5, 0.0, 1.0);
	float body = mix(1.0, 0.18, smoothstep(0.35, 1.0, hgt));

	// ---- 上色 ----
	// 被火烤到的那一侧亮：**只作用在下半团**，因为光源（尾焰）在烟团之下。
	// `glow` 由调用方按箭底高度推 ⇒ 升上去自动冷掉。
	float lit = glow * (1.0 - smoothstep(0.10, 0.62, hgt)) * (0.45 + 0.55 * n);
	vec3 c = mix(tint_dark, tint_glow, clamp(lit, 0.0, 1.0));
	// 顶部混大气色
	c = mix(c, tint_thin, smoothstep(0.55, 1.0, hgt) * 0.55);
	// 疙瘩在颜色上也抖一下（纯色的大球是最"贴图"的地方）
	c *= 0.82 + 0.36 * n;

	ALBEDO = c;
	// 浓度 = 总体 alpha × 正面比软边 × 高度剖面 × 疙瘩 × `dens`
	ALPHA = alpha * soft * body * mix(0.55, 1.0, n) * dens;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
