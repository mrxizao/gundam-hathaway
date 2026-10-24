shader_type canvas_item;
render_mode blend_mix, unshaded;

// 加速时的屏幕暗角。
//
// 存在的唯一理由：**它必须是平滑的径向渐变**。
// 第一版是在四边直接画四条半透明矩形色带，加速时屏幕周围会出现一圈明显的
// 方形硬边框 —— 看起来像素材没处理干净，而不是速度感。
// 这里用 UV 距离做 smoothstep，任何分辨率、任何宽高比都不会露出边。

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(0.04, 0.09, 0.20);
uniform float inner : hint_range(0.0, 1.5) = 0.40;
uniform float strength : hint_range(0.0, 2.0) = 0.55;

void fragment() {
	// UV → −1..1 的屏幕坐标
	vec2 p = UV * 2.0 - 1.0;
	// 按宽高比稍微压一下横向，让暗角是柔和的椭圆而不是被拉宽
	p.x *= 0.88;
	float d = length(p) / 1.28;
	float v = smoothstep(inner, 1.0, d);
	v = pow(v, 1.7);
	COLOR = vec4(tint, v * strength * intensity);
}
