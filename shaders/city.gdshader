shader_type spatial;
// `diffuse_lambert`：与 `BaseMaterial3D`（`_city_material()` 用的那套）的默认漫反射
// 模型对齐，免得"换成 shader 之后同一栋楼亮了一档"。这条在 `terrain.gdshader` 的
// 头顶有实测记录（结论：本工程里加不加没有可观测差异，留着是为了语义一致）。
render_mode cull_back, specular_schlick_ggx, diffuse_lambert;

// 城市建筑立面的材质（1.2.3 批 G）。
//
// ## 为什么要新开一份 shader（而不是继续用 `StandardMaterial3D`）
//
// 1.2 的城市是**一栋楼一个纯色盒子**：`_city_material()` 只给 `albedo + rough 0.90 +
// metallic 0`，全城**同一种哑光材质**，没有幕墙、没有窗格、没有金属。老板的原话是
// 地图"细节材质都很差"。一栋 800 m 高的楼只有一种颜色，近看就是一块塑料板。
//
// 而**现代都市的观感大半来自立面**：玻璃幕墙把天空反射下来、窗格在侧光下分出竖纹。
// 这两样都不需要美术资源，只需要知道"这一面墙上，哪里是玻璃板、哪里是框"。
//
// ## 立面坐标是怎么来的（**这里是最容易做错的一步**）
//
// 所有城市体量共用**一个单位立方体网格**（`_city_cube`），尺寸烘在 `MeshInstance3D`
// 的 `scale` 上（`world_builder.gd:_add_box`）。于是：
//   · 局部 `VERTEX ∈ [-0.5, 0.5]`（单位立方体）
//   · 世界尺度 = `MODEL_MATRIX` 三个基向量的**长度**（纯缩放+旋转，没有剪切）
// 两者相乘就得到**以米为单位的墙面坐标** ⇒ 窗格因此是**米制**的，
// 一栋 40 m 宽和 400 m 宽的楼，窗户一样大 —— 这一点用 UV 是做不到的
//（单位立方体的 UV 不随实例尺寸变化）。
//
//   · 竖面（法线朝 X 或 Z）：`along` 取另一条水平轴、`up` 取局部 Y；
//   · 屋顶 / 底面：**不做立面图案**（屋顶本来就没有窗）。
//
// ## `facade_strength = 0` 时行为**逐字节等价于旧材质**
//
// 这条是刻意设计的：像素探针靠 `--facade=0` 把这一项单独拧回旧样子，
// 于是"改了到底生效多少"是可测的，而不是靠人回忆。

// ⚠️ **刻意不加 `: source_color`**：与 `BaseMaterial3D.albedo_color`、与
// `terrain.gdshader` 的 `albedo_tint` 保持同一口径（**直接当线性值**）。
// 加了的话同一个颜色会在两条路径上得到两种 albedo（同色两亮度）。
uniform vec4 albedo_tint = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.90;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;

// ---- 立面 ----
uniform float facade_strength : hint_range(0.0, 1.0) = 0.0;
// 开间 / 层高（米）。**每个材质一份常量**（而不是"按楼的尺寸算"）——
// 材质是按颜色+类别缓存的，尺寸要是进缓存键，整座城又会退回"几百份材质"。
// 所以：塔楼用一档（5.6 × 4.0），裙房用另一档（9.0 × 5.5，商铺的开口更大）。
uniform float bay_w = 5.6;
uniform float floor_h = 4.0;
// 窗框占一格的归一化宽度（x = 竖向框，y = 横向框/楼板边）
uniform vec2 frame_w = vec2(0.16, 0.26);
// 玻璃板相对墙面的压暗比例（`1 - pane_dark` 倍）
uniform float pane_dark : hint_range(0.0, 0.8) = 0.26;
// 玻璃板自己的粗糙度（低 ⇒ 反射天空/环境，也就是"幕墙亮起来有天空色"）
uniform float pane_rough : hint_range(0.0, 1.0) = 0.12;
// 距离淡出的两端（米）。**提成 uniform 而不是写成字面量**，理由有两条：
//   ① 探针可以把它拧到"永不淡出"（`--fadefar=<米>`），于是"淡出把这一项吃掉了"
//      与"这一项根本没接到楼体上"第一次能被区分开 —— 这两种情况的像素表现
//      **都是"几乎没变"**，第一轮实测就卡在这里查不下去；
//   ② 这两个数的真源应该在 GDScript（`CITY_FACADE_FADE_NEAR/FAR`），
//      而不是散在 shader 源码里 —— 否则没人能一眼看出"窗格在什么距离上还能读"。
// 远处淡出的两端 —— 推导见 `fragment()` 里 `near_f` 那一段。
// 真源是 `world_builder.gd` 的 `CITY_FACADE_FADE_NEAR` / `CITY_FACADE_FADE_FAR`，
// 这里给同一组默认值只是为了"没人设参数时行为也是对的"。
uniform float facade_fade_near = 970.0;
uniform float facade_fade_far = 1950.0;

// ---- 顶点阶段传下来的量 ----
// 为什么全在顶点算：fragment 里的 `NORMAL` 是**视图空间**的、矩阵的可用性随管线有差别。
// 顶点阶段要用的全都一定可用，而下面这几个量对**整个盒子**都是常量
//（`local_pos` 除外，它在每个面上是线性的）—— 插值没有任何精度损失。
uniform float surface_detail : hint_range(0.0, 1.0) = 0.0;
float facade_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

varying vec3 local_pos;
varying vec3 n_obj;
varying vec3 world_scale;
// 每栋楼一个相位偏移：不然全城的窗格会在世界坐标上对齐，看上去像一张贴满的网。
varying vec2 cell_phase;
// 与相机的距离（米）：远处的窗格会变成摩尔纹，要淡出。
varying float view_dist;

void vertex() {
	local_pos = VERTEX;
	n_obj = NORMAL;
	world_scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz));
	// 0.173 / 0.311 是两个互质的无理数，取格心当相位不会两栋楼重合。
	cell_phase = vec2(MODEL_MATRIX[3].x * 0.173, MODEL_MATRIX[3].z * 0.311);
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec3 an = abs(n_obj);
	// 竖面判定：法线主要朝水平方向。`step` 比 `if` 便宜，而这里两个分支本来都要算。
	float side = step(0.5, max(an.x, an.z));
	// 墙面坐标（米）。法线朝 X 的面（两个侧壁）用局部 Z，朝 Z 的用局部 X。
	float along = mix(local_pos.x * world_scale.x, local_pos.z * world_scale.z,
		step(an.z, an.x));
	float up = local_pos.y * world_scale.y;

	// 一格的归一化坐标 → 到最近的框边有多远 → 框内为 0、板内为 1
	vec2 cell = vec2(along / bay_w, up / floor_h) + cell_phase;
	vec2 f = fract(cell);
	vec2 m = min(f, 1.0 - f);
	// `+0.03` 是边缘的软化宽度（约 3% 一格）。硬切在低分辨率下会闪。
	vec2 inset = smoothstep(frame_w, frame_w + vec2(0.03), m);
	float pane = inset.x * inset.y;

	// 远处淡出：1600×900 下，600 m 外的窗格只有一两个像素宽 ——
	// 那正是摩尔纹的温床。淡出之后**保留整面幕墙的反射特性**（只改粗糙度、
	// 不再改明暗）：天际线因此仍有"玻璃"的读感，而不是退回一片哑光。
	//
	// ---- ⚠️ 2026-09-23（批 G）**把淡出距离整体往后推**，依据是实测不是手感 ----
	//
	// 第一版写的是 `smoothstep(500.0, 1400.0, ...)`，同期像素探针的 A/B 结果是
	// **`--facade=0` 几乎什么都没改**（`full.mean_lum` 只差 −0.0002）——
	// 也就是说"米制窗格"这项改动在**正常交战距离上根本没出来**（等于白做）。
	//
	// 反推：本工程基准 1600×900、相机竖直 fov 62° ⇒ 距离 d 处每米占 `748.9 / d` 像素。
	//   · 最小开间 5.2 m：500 m → **7.8 px**（远没到需要淡出的程度）、970 m → 4.0 px、
	//     1950 m → **2.0 px**（正好是奈奎斯特极限，再远必然摩尔纹）；
	//   · 最细的框线 0.83 m：970 m 就只剩 0.64 px（**它才是真的会闪的那一层**）。
	//
	// 所以正确的分界是"**按开间**定，不是按一个凭感觉的距离定"：
	//   起点 970 m  = 最小开间还有 4 px，窗格清晰可读 ⇒ 从这里开始淡；
	//   终点 1950 m = 最小开间刚到 2 px 奈奎斯特 ⇒ 到这里淡净，绝不越过。
	// 代价说清楚：1400 m 外那层 0.8 m 的细框线已经是亚像素，会有一点微闪 ——
	// 但它乘在"已淡到 40% 以下"的面板对比上，幅度很小，换来的是
	// **窗格的可读距离从 500 m 拉到 970 m（满对比）**，这是这笔改动值得的地方。
	float near_f = 1.0 - smoothstep(facade_fade_near, facade_fade_far, view_dist);
	float wall = facade_strength * side;
	// Windows vanish below two pixels; broad architectural bays remain visible.
	float window_px = 1.0 / max(max(fwidth(cell.x), fwidth(cell.y)), 0.0001);
	float window_keep = smoothstep(1.5, 4.0, window_px);
	float k_near = wall * pane * near_f * mix(1.0, window_keep, surface_detail);
	float k_far = wall * (1.0 - near_f);

	vec3 base = albedo_tint.rgb;
	// 明暗**只在近处**给：远处整面压暗会把 1.2 逐张图调好的
	// "阴天黄昏里楼只能靠天光被看清"那套亮度基线推翻。
	ALBEDO = mix(base, base * (1.0 - pane_dark), k_near);
	ROUGHNESS = mix(roughness_value, pane_rough, clamp(k_near + k_far, 0.0, 1.0));
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	if (surface_detail > 0.0) {
		float building = facade_hash(floor(cell_phase * 0.25));
		vec2 broad_cell = vec2(along / 64.0, up / 96.0) + cell_phase;
		vec2 broad_f = fract(broad_cell);
		vec2 edge = min(broad_f, 1.0 - broad_f);
		vec2 aa = max(fwidth(broad_cell), vec2(0.001));
		float bay = smoothstep(0.04 - aa.x, 0.04 + aa.x, edge.x)
			* smoothstep(0.055 - aa.y, 0.055 + aa.y, edge.y);
		float broad_keep = smoothstep(1.0, 3.0, 1.0 / max(max(aa.x, aa.y), 0.001));
		float broad = wall * broad_keep;
		float panel_tone = mix(0.87, 1.07, building);
		vec3 warm_cool = mix(vec3(1.04, 1.015, 0.98), vec3(0.97, 1.01, 1.035), building);
		float streak = facade_hash(vec2(floor(along / 18.0), floor(cell_phase.x)));
		float weather = (streak - 0.5) * 0.10 * (1.0 - metallic_value);
		float roof = 1.0 - side;
		float roof_patch = facade_hash(floor(local_pos.xz * world_scale.xz / 38.0) + floor(cell_phase));
		float roof_keep = smoothstep(2.0, 5.0, 38.0 / max(length(fwidth(local_pos.xz * world_scale.xz)), 0.001));
		vec3 finish = warm_cool * panel_tone * (1.0 + weather * broad_keep);
		finish *= 1.0 - (1.0 - bay) * broad * 0.15;
		finish *= 1.0 + roof * (roof_patch - 0.5) * roof_keep * 0.20;
		ALBEDO *= mix(vec3(1.0), finish, surface_detail);
		ROUGHNESS = clamp(ROUGHNESS + surface_detail * ((1.0 - bay) * broad * 0.12 + roof * 0.10), 0.06, 1.0);
	}
}
