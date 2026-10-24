shader_type sky;

// 自定义天空。三个时段共用这一支 shader，只是换 uniform。
//
// 为什么不用 ProceduralSkyMaterial：它画不出星星。
// 而"夜晚"的辨识度几乎全在星星和月亮上 —— 只把天调暗得到的是"阴天"，
// 不是"夜晚"。所以天空改成自绘：三段渐变 + 哈希星场 + 天体圆盘。
//
// 星星技巧：在**方向空间**切格子（EYEDIR * density），每格用哈希决定
// "这格有没有星 / 星在格内的偏移 / 多亮"。方向空间切格 = 天球上均匀分布，
// 不会像用 UV 切格那样在两极堆成一坨。

// ⚠️ 星星闪烁的时钟：**不用引擎内建的 `TIME`**（理由与 `ocean.gdshader` 的
// `wave_time` 逐字相同 —— `TIME` 每次跑都不同 ⇒ 星空不可复算）。
// 实测这一处让画面上方的天空在两次同参数跑之间差 **−3.3%**，
// 虽然比海面那 −64% 小得多，但同样是"假 A/B"的燃料。
uniform float sky_time : hint_range(0.0, 1000000.0) = 0.0;

uniform vec3 zenith : source_color = vec3(0.19, 0.40, 0.78);
uniform vec3 horizon : source_color = vec3(0.66, 0.78, 0.92);
uniform vec3 ground : source_color = vec3(0.30, 0.42, 0.52);
uniform float horizon_power : hint_range(0.05, 2.0) = 0.55;
uniform float ground_blend : hint_range(0.01, 1.0) = 0.18;

// 天体（太阳 / 月亮）。方向由 GDScript 写入，不用 LIGHT0_DIRECTION ——
// 那个内建量的方向约定容易搞反，自己传一个"从场景指向天体"的向量最稳。
uniform vec3 disc_dir = vec3(0.0, 0.6, -0.8);
uniform vec3 disc_color : source_color = vec3(1.0, 0.96, 0.88);
uniform float disc_amount : hint_range(0.0, 4.0) = 1.0;
uniform float disc_size : hint_range(0.0005, 0.2) = 0.012;
uniform float disc_halo : hint_range(0.0, 2.0) = 0.35;

uniform float star_amount : hint_range(0.0, 3.0) = 0.0;
// 默认值刻意调过：cell 太小（密度太高）时每颗星只有 1 像素，
// 在 1600×900 下看着还行，一进缩略图/小窗口就被降采样直接抹平 ——
// "夜里有星星"这件事必须一眼能看见。所以格子放大、星芯也放大。
uniform float star_density : hint_range(20.0, 800.0) = 150.0;
uniform float star_brightness : hint_range(0.0, 8.0) = 2.6;

// Space keeps the original star field and disc unchanged.
uniform float atmosphere = 0.0;
uniform float star_coverage : hint_range(0.0, 1.0) = 1.0;
uniform float haze_strength : hint_range(0.0, 1.0) = 0.0;
// Zero by default, so space and the established night sky retain their radiance.
uniform float scatter_strength : hint_range(0.0, 1.0) = 0.0;
uniform float scatter_power : hint_range(1.0, 32.0) = 8.0;
uniform vec3 scatter_color : source_color = vec3(1.0, 0.84, 0.66);

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float hash13(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float star_layer(vec3 d, float scale) {
	vec3 p = d * scale;
	vec3 id = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash13(id);
	if (h < mix(0.930, 1.0 - 0.070 * star_coverage, atmosphere)) {
		return 0.0;
	}
	vec3 off = hash33(id + 1.7) - 0.5;
	float dist = length(f - off * 0.55);
	// 星芯半径 0.26 格 —— 格子约 6 px 时星点约 3~4 px，肉眼刚好是一颗星而不是一个噪点
	float core = atmosphere < 0.5 ? smoothstep(0.26, 0.0, dist) : 1.0 - smoothstep(0.0, 0.18, dist);
	float twinkle = 0.72 + mix(0.28, 0.09, atmosphere) * sin(sky_time * 1.9 + h * 91.0);
	return core * twinkle * (0.30 + 0.70 * hash13(id + 11.3));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;

	float t = pow(clamp(up, 0.0, 1.0), horizon_power);
	vec3 col = mix(horizon, zenith, t);
	col = mix(col, ground, smoothstep(0.015, -ground_blend, up));

	// Broad horizon scattering and a soft lunar aureole, without a screen overlay.
	if (atmosphere > 0.5) {
		float horizon_haze = exp(-max(up, 0.0) * 5.5) * smoothstep(-0.10, 0.04, up);
		float lunar_air = pow(max(dot(d, normalize(disc_dir)), 0.0), 18.0);
		col += horizon * horizon_haze * haze_strength;
		col += disc_color * lunar_air * haze_strength * disc_amount * 0.018;
	}

	// Directional aerial glow; no full-screen color overlay and no extra cloud geometry.
	if (atmosphere > 0.5 && scatter_strength > 0.0) {
		float forward_air = pow(max(dot(d, normalize(disc_dir)), 0.0), scatter_power);
		float low_air = exp(-abs(up) * 3.0) * smoothstep(-0.05, 0.12, up);
		col += scatter_color * forward_air * low_air * scatter_strength;
	}

	if (star_amount > 0.001) {
		float s = star_layer(d, star_density) + star_layer(d, star_density * 0.47) * 0.55;
		// 贴着地平线的星星会被海面和雾吃掉，这里提前压掉，
		// 否则会出现"星星落进海里"的怪画面
		// Only atmospheric maps hide stars below the horizon; space uses the full sphere.
		s *= mix(1.0, smoothstep(-0.03, 0.20, up), atmosphere);
		col += vec3(0.84, 0.90, 1.0) * s * star_amount * star_brightness;
	}

	if (disc_amount > 0.001) {
		float sd = dot(d, normalize(disc_dir));
		float edge = 1.0 - disc_size;
		float disc = smoothstep(edge, edge + disc_size * 0.30, sd);
		float halo = pow(max(sd, 0.0), 420.0) * disc_halo;
		col += disc_color * (disc + halo) * disc_amount;
	}

	COLOR = col;
}
