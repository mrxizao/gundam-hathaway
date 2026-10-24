shader_type spatial;
// **出水泡沫环**（马夫蒂火箭从海里顶起来时，水面向外炸开的那一圈白沫）。
//
// ## 它为什么存在
// 老板砍掉海上平台、要「**直接从海里面出来**」。若只把箭体位置从水下搬到水上，
// 画面读起来是**穿模** —— 一枚 58 m 的箭从水面里凭空浮起来，海面**一点反应都没有**。
// 真实的下潜/海上发射里，出水那一瞬间水面会炸开：一圈向外扩张的泡沫 + 一片涌起来的烟。
// 这就是那两件 —— **本文件只画环**，烟在 `sea_smoke.gdshader`。
//
// ## ★ 2026-09-30：水柱那一支**已经删掉**
// 它原来有 `mode = 0`（环）与 `mode = 1`（圆柱壳水柱）两支。老板看了图之后说
// > 「**发射时候的周围环绕的东西做成风压太丑陋了，还不如做成烟雾呢**」
// 而实测读数支持这个判断：`04_rocket_side` 整幅纯白（均值 **255.0**）、
// `02_breach_side` 亮 0.9416 —— 那根与箭同轴的白柱把火箭整个吞了。
// ⇒ 水柱改由 `SeaSplash` 的 **72 团球体烟**（`SplashSmoke`）承担，
// 本文件的 `mode` / `flare` 两个 uniform 与那条 `if (mode == 1)` 顶点分支**一并删除**。
// ⚠️ 留着它们不只是"死代码"：`flare` 那条 `VERTEX.xz *= k` 在环上会把整圈泡沫
// 按 UV.y（= 半径）放大 —— 谁哪天顺手把 `mode` 传成 1，环会静默变成一圈喇叭口。
//
// ## ⚠️ 为什么是程序化噪声而不是贴图
// 同 `cloud.gdshader` / `room_curtain.gdshader`：这一套东西的**唯一**用途是
// "在屏幕上读得出是水花"。引一份外部贴图只会让"特效能不能工作"多一个可失败点，
// 而程序化噪声是自足的，还能按 `churn` 真的翻搅起来。
//
// ## ⚠️ 为什么 `depth_draw_never`
// 泡沫是半透明的，写深度会让它把后面的火箭/海面切出一道硬边。
// `depth_test_disabled` **不要**加 —— 那会让它在任何东西前面都画上，
// 包括画在**镜头与火箭之间**（那正是玩家看得最多的一段）。
// `cull_disabled` 要：环是一张单层薄片，从下面看（贴着水面时）也得在。

render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled,
	fog_disabled;

// 总体不透明度（0 = 完全没有，1 = 最浓）。由 `SeaSplash` 每帧推。
uniform float alpha : hint_range(0.0, 1.0) = 0.0;

// 翻搅速率。它是一个**乘进 TIME 的倍率**（不是速度本身）——
// 水花翻搅得比云快得多，所以默认给到 2.4。
uniform float churn : hint_range(0.0, 8.0) = 2.4;

// 噪声密度：环上是"泡沫团有多少"。
uniform float scale : hint_range(1.0, 40.0) = 9.0;

// ★ **近场淡出**（米）：球心 / 环心离相机小于这个距离就淡出去。
//
// ## 它防的是什么
// 发射段机位离箭体 **66 m**（`ChaseCamera.LAUNCH_OFFSET` = `D 62 / H 52`），
// 而泡沫环的半径是 110~860 m ⇒ 环带**经常穿过相机所在的那一圈**。
// 不淡出的话，离镜头 2 m 的那一段泡沫会以一整屏的白色糊住画面 ——
// 而那与"第一版水柱糊满屏"是**同一个失效形态**（老板看的就是那个）。
// ⇒ 用相机距离当开关，把"贴脸的那一段"去掉。两个数（内 / 外）之间平滑过渡。
uniform float near_fade_in : hint_range(0.0, 400.0) = 14.0;
uniform float near_fade_out : hint_range(0.0, 800.0) = 120.0;

// 亮部（泡沫）与暗部（水）。
uniform vec3 tint : source_color = vec3(0.90, 0.94, 0.97);
uniform vec3 tint_deep : source_color = vec3(0.46, 0.58, 0.66);

varying vec2 uvw;

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
		p *= 2.07;
		amp *= 0.5;
	}
	return s;
}

void vertex() {
	uvw = UV;
}

void fragment() {
	if (alpha <= 0.002) {
		discard;
	}

	// ⚠️ 方位角方向要**按周长补偿**：UV.x 是 0..1 绕一圈，在半径 r 的地方
	// 一个 UV.x 单位对应 `2πr` 米。不补的话环上的泡沫会被拉成"内密外疏"的
	// 放射状条纹 —— 那是"贴图没做 UV 展开"的典型长相。
	// 这里用节点 `scale` 的 x 分量当半径的代理（环是等比缩放的）。
	float r_scale = max(length(MODEL_MATRIX[0].xyz), 0.001);
	float circ = 6.2831853 * r_scale;

	// 环：极坐标采样（`UV.y` 当半径）
	float ang = UV.x * circ;
	vec2 p = vec2(ang / 40.0, UV.y * scale);
	p += vec2(TIME * churn * 0.35, -TIME * churn);

	// 域扭曲：把圆斑卷成"被水冲开的絮"
	vec2 warp = vec2(vnoise(p * 0.55), vnoise(p * 0.55 + 11.3)) - 0.5;
	float n = fbm(p + warp * 2.2);

	// 泡沫：噪声的**高值**处是白的泡沫团，低值处是水（暗）
	float foam = smoothstep(0.34, 0.78, n);

	// 环的形状遮罩：内缘起、外缘散；越往外越稀（泡沫在水面上铺开就淡了）
	float band = smoothstep(0.0, 0.30, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	foam *= 1.0 - UV.y * 0.45;

	// ★ 近场淡出（见 `near_fade_in` 的长注释）
	float camdist = distance(MODEL_MATRIX[3].xyz, CAMERA_POSITION_WORLD);
	float nf = smoothstep(near_fade_in, near_fade_out, camdist);

	vec3 c = mix(tint_deep, tint, foam);
	ALBEDO = c;
	ALPHA = alpha * band * mix(0.45, 1.0, foam) * nf;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
