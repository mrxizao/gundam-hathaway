shader_type spatial;
// 三渲二全屏后处理（批 17 立项，批 19 重写挂载方式）——
// 色阶量化 + 深度描边（二阶差分）。
//
// ⚠️⚠️ **为什么是 spatial 全屏面片，而不是 canvas_item 后处理**（批 19 血泪）：
// 首版用 canvas_item ColorRect + hint_depth_texture —— **Godot 4.7 的
// canvas_item shader 不支持深度纹理**（真渲染时报
// `SHADER ERROR: 'hint_depth_texture' is not supported in 'canvas_item' shaders`），
// shader 整个编译失败 → ColorRect 显示默认**白色** → "进入战斗地图全屏白光"。
// 无头回归测不出这个错（headless 的 RenderingServer 是 dummy，不编译 shader），
// 必须用真渲染探针抓（tests/_probe 路线）。spatial shader 支持
// hint_depth_texture（Forward+），所以后处理挂在**相机下的全屏面片**上：
// 顶点着色器把面片顶点直接写进 clip space 铺满屏幕，透明队列里最后画，
// SCREEN_TEXTURE 读到的就是完整 3D 画面，DEPTH_TEXTURE 读到场景深度。
// 代价：G-buffer 法线（normal_roughness）在 spatial 里读不到 → 法线边退役，
// 内边描边交给机体 TOON 材质自带的 rim。
//
// 参考思路：B 站教程《在 Godot 中使用 3 渲 2 着色器》（BV1PGBiBvEFG）。
// HUD 等 2D 层永远画在 3D 之后，不受本效果影响。

// ⚠️⚠️ **`cull_disabled` 是必须的，不是可选的**（批 K · 轮 3 实测血泪）：
// 顶点写 clip space 时，任何**翻转某个轴**的坐标映射都会让屏幕空间**绕序反转**，
// 于是默认的 `cull_back` 把整个面片当背面剔除 —— 表现是**一个像素都不渲染**，
// 而日志里 `SHADER ERROR = 0`、`cel_post_visible = true`，一切"看起来正常"。
//
// 这就是本效果**从批 17 立项起一直没在工作**的原因。原来那一行写的是
//   POSITION = vec4(UV.x*2-1, 1-UV.y*2, 0, 1);   ← 第二个分量翻转了 y
// 十二发对照实测（关掉 vs 打开 / 换纯色 fragment / 另起新实例 / 拉开距离到 5 m /
// clip z 取 0·0.5·0.999 / x 与 y 各自翻转）**PNG 全部与 base 逐位相同**；
// 而只把 `1-UV.y*2` 换成 `UV.y*2-1` 的那一发**当场画出全屏纯色**。
//
// 旧注释担心的"双面会画两遍、screen_texture 自引用"**不成立**：quad 是平面，
// 两个三角形不重叠，`cull_disabled` 下每个像素仍只被覆盖一次。
//
// ============================================================
// ⚠️⚠️⚠️ **所以这个效果默认是关的**（批 K · 轮 4 决定）
// ============================================================
//
// 上面那个绕序 bug **从批 17 立项起一直存在** ⇒ 本效果**从来没有真正渲染过一次**。
// 也就是说：**整个工程的所有画质调校都是在"没有这个后处理"的画面上做的**
//（奥恩贝利的环境光剂量、太平洋的波浪淡出、沙漠植被的反照率……每一格都是）。
// 修活它 = 一次性改变全画面，而那些调校全部作废。
//
// 除了"调校作废"，还有两个**结构性**问题，修不掉：
//
// ① **`screen_texture` 里没有透明几何**。
//    这张快照是**透明队列开始前**拍的，而 `render_priority = 100` 让本面片
//    排在**最后**画 ⇒ 所有"排在它前面画的透明物体"都不在快照里。
//    本作的云是 `_make_cloud_material()` 造的 **alpha 混合**几何
//    （alpha 0.34 / 0.95）⇒ 走透明队列 ⇒ **云整个消失**。
//    实测：恒等透传（`intensity=0, saturation=1.0`，什么都不改）那张图里，
//    天空一片干净，而 base 那张的云全在。同理还有尾焰、爆光、光晕。
//    ⇒ 只要本效果开着，**云就不见了**。而云是太平洋/沙漠两张图的主要视觉元素。
//
// ② 逐通道量化会拆色相、归零暗部（见 `fragment()` 里 ② 那段长注释）。
//    这一条**已修**（改成亮度域 + 等比缩放），但①修不掉 ——
//    要修①得把整个 3D 世界渲进 `SubViewport`、再在主视口做后处理，
//    那是一次牵动 HUD/输入/相机的架构改动，不该塞在画质轮里做。
//
// ⇒ **决定**：`Settings.cel_shading` 默认改成 **false**（画面同批 K·轮 3 之前，
//    也就是同所有已验证过的那批图）；shader 的数学同时修对，
//    想开的人可以在设置页打开。等有了 SubViewport 架构再把默认打开。
render_mode unshaded, blend_mix, cull_disabled, depth_test_disabled, depth_draw_never,
	shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

// 总开关强度：0 = 原画面，1 = 全效果。设置页的"三渲二渲染"开关走 visible，
// 这个 uniform 留给以后做"轻微/标准"档位或淡入淡出。
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
// 色阶级数：**亮度**上的台阶数（不是每通道）。见下面那段"为什么只量化亮度"。
//
// ⚠️ 6 → **10**（批 K · 轮 4 实测回调）。6 阶配原来的逐通道量化，会把
// 阴天黄昏的棕色天空拆成一阶 R + 一阶 G/B（见下），整个画面偏红。
// 改成亮度域量化之后，阶数不再是"色相杀手"，但它仍然决定"暗部会不会被归零"：
// 感知域 8 阶下，最暗一阶的边界是 `(1/8)^2.2 = 0.010` 线性 —— 比原方案的
// **0.083** 低 8 倍，暗部才保得住。
uniform float color_steps : hint_range(2.0, 24.0) = 10.0;
// 色阶混合比：1.0 = 硬量化，0 = 原图。硬量化会把 ACES 调过的雾/辉光搅出带状脏痕。
//
// ⚠️ 0.6 → **0.30**（同上）。0.6 在"色阶只有 6 阶 + 逐通道"时是灾难；
// 现在改成亮度域之后它已经温和得多，但本作的画面是**阴天黄昏/夜景**，
// 大面积中低亮度 ⇒ 量化本来就容易读出来，0.30 是"看得出赛璐璐感、又不脏"的档。
uniform float posterize_mix : hint_range(0.0, 1.0) = 0.30;
// 饱和度增益：动漫渲染的另一个标志是"颜色比照片纯"。1.0 = 不动。
//
// ⚠️ 1.18 → **1.08**：原来这一行**没有乘 `intensity`** ⇒ 即使把总开关打到 0，
// 画面仍然被提了 18% 的饱和（"关了还在改色"）。现在乘上之后，
// 1.08 也不需要原来那么狠了。
uniform float saturation : hint_range(0.0, 2.0) = 1.08;
// 描边宽度（屏幕像素）。1.5 在 1080p 下约一根 2px 细线，远景不糊。
uniform float outline_width : hint_range(0.5, 4.0) = 1.5;
// 深度边阈值：**外推残差**的相对差（|中心 - 两侧均值| / 中心）超过它才算边。
// 二阶差分的量纲：真·遮挡边（物体 vs 背景/地面）通常 >> 0.05，宽裕；
// 0.012 盖住极端掠射渐变的曲率残余（俯角 1.5° 的海面残余 ≈ 0.006）。
uniform float depth_edge_threshold : hint_range(0.001, 0.05) = 0.012;
// 深度差的**绝对下限**（米，批 19）。一阶阈值方案下近战（相机离机体 5 m，
// 阈值实际 ≈ 2 cm）机体表面的掠射深度渐变全屏过阈 → 整屏被描成边。
// 真轮廓（隔空遮挡）深度差是米级到公里级，1 m 下限不伤它。
// 单靠它救不了海面掠射渐变（远处像素差可达百米级）——主力是二阶差分，见下。
uniform float outline_min_depth_diff : hint_range(0.0, 8.0) = 1.0;
// 描边颜色：不是纯黑 —— 带一点蓝的深色，和夜景/海洋的调子咬合。
uniform vec4 outline_color : source_color = vec4(0.05, 0.06, 0.10, 1.0);

// 线性化深度。Godot 的深度缓冲是透视非线性 [0,1]，直接做差
// 会被近处的精度差淹没 —— 必须先拉回线性再比较。
// 公式与 Forward+ 的 NDC z∈[0,1] 约定一致（z_ndc=0 → 近平面 n，1 → 远平面 f）。
float linear_depth(vec2 uv) {
	float d = texture(depth_tex, uv).r;
	if (d >= 0.9999) {
		return 1.0e9; // 天空（清屏深度）——给一个"无限远"，让剪影边能算出来
	}
	float n = 1.2;       // 与 chase_camera 的 near 对齐（chase_camera.gd:349）
	float f = 90000.0;   // 远平面（chase_camera.gd:350，90 km）
	return (n * f) / (f - d * (f - n));
}

// 二阶差分边缘检测（批 19 真修复）：用中心两侧的对称邻点**线性外推**中心深度。
//
// 一阶相对差（相邻像素直接做差）在海洋图上全军覆没：海面沿视线是**连续
// 深度渐变**，掠射角下相邻像素深度差达米级到百米级（俯角 10° 处 ≈ 4 m），
// 相对差全部过阈 → 大半屏被描成边。二阶差分对**任何平滑渐变**（无论多陡）
// 外推都准 → 不描；真·遮挡边是深度**跳变**，外推必偏 → 描。
// 有天空参与时退回剪影判断（天空深度是无穷远，外推无意义）。
float depth_edge_pair(float c, float a, float b) {
	if (a >= 1.0e8 && b >= 1.0e8) {
		return 0.0; // 两侧都是天空：中心不是天空也无处可描（孤立像素）
	}
	if (c >= 1.0e8 || a >= 1.0e8 || b >= 1.0e8) {
		// 剪影：中心是实体、且至少一侧是天空 → 必描
		return (c < 1.0e8 && (a >= 1.0e8 || b >= 1.0e8)) ? 1.0 : 0.0;
	}
	float pred = (a + b) * 0.5;
	float diff = abs(c - pred);
	if (diff < outline_min_depth_diff) {
		return 0.0; // 同表面连续渐变的残余噪声（极近处）
	}
	return diff / max(c, 1.0);
}

void vertex() {
	// 直接写 clip space = 铺满屏幕，与相机 FOV / 裁剪面 / 窗口大小全部无关。
	//
	// ⚠️⚠️ **两个分量都不许翻转**（理由见上面 `render_mode` 的注释）：
	// `UV` 在 QuadMesh 上是 (0,0) 左上 → (1,1) 右下，而 NDC 的 y 轴**向上**
	// ⇒ 直觉上"该翻一下"，而**翻了就不渲染**。
	// 写成 `UV.y*2-1` 时几何是上下颠倒的，但 fragment 按 `SCREEN_UV`
	//（引擎给的、与几何无关）采样 ⇒ 画面完全正确，不需要再翻回来。
	POSITION = vec4(UV.x * 2.0 - 1.0, UV.y * 2.0 - 1.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 col = texture(screen_tex, uv);
	// ⚠️ spatial 没有 SCREEN_PIXEL_SIZE（那是 canvas_item 的内置量）——
	// 用 VIEWPORT_SIZE 换算归一化像素步长（探针实锤过的坑）。
	vec2 px = outline_width / VIEWPORT_SIZE;

	// ---- ① 深度描边：十字采样 + 二阶差分 ----
	float d0 = linear_depth(uv);
	float dn = linear_depth(uv + vec2(0.0, -px.y));
	float ds = linear_depth(uv + vec2(0.0, px.y));
	float de = linear_depth(uv + vec2(px.x, 0.0));
	float dw = linear_depth(uv + vec2(-px.x, 0.0));

	float depth_edge = max(
		depth_edge_pair(d0, de, dw),
		depth_edge_pair(d0, dn, ds));
	float edge = step(depth_edge_threshold, depth_edge);

	// ---- ② 色阶量化（赛璐璐底色）----
	//
	// ⚠️⚠️ **只量化亮度，绝不逐通道量化**（批 K · 轮 4 实测定性）。
	//
	// 原写法 `floor(c * color_steps + 0.5) / color_steps` 三个通道各算各的，
	// 而本作的主画面是**阴天黄昏**：天空的显示值约 `(0.30, 0.24, 0.20)`（棕）。
	// 6 阶逐通道一打：
	//   R: floor(0.30*6+0.5)/6 = 2/6 = 0.333
	//   G: floor(0.24*6+0.5)/6 = 1/6 = 0.167
	//   B: floor(0.20*6+0.5)/6 = 1/6 = 0.167
	// ⇒ **(0.333, 0.167, 0.167)** —— 一片**饱和的红**。
	// 这不是"风格化"，是**色相被拆掉了**：低亮度区每一阶的相对步长极大
	//（1/6 = 0.167，而天空的 G 只有 0.24），三通道落在不同的阶上，
	// 原本 1.25:1 的 R/G 比被拉成 2:1。
	//
	// 它**同时把暗部归零**：任何低于 `1/(2*6) = 0.083` 的通道直接变 0。
	// 死城的地面与楼体暗面本来就在 0.03~0.08 ⇒ **整片纯黑**。
	// （用户原话："**地图光照一塌糊涂，什么都看不见了**"。）
	//
	// ⇒ 改成**亮度域量化 + 等比缩放色度**：
	//   · **等比缩放**（`c * q/lum`）保色相 —— 这是关键；
	//   · **感知域**量化（先 `pow(lum, 1/2.2)`、量化后再 `pow(·, 2.2)`）
	//     保暗部 —— 10 阶时最暗一阶的边界是 `(1/10)^2.2 = 0.0063` 线性，
	//     比原方案的 0.083 低一个数量级。
	float lum = dot(col.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 c = col.rgb;
	if (lum > 1.0e-5) {
		float enc = pow(lum, 1.0 / 2.2);
		float q = floor(enc * color_steps + 0.5) / color_steps;
		vec3 stepped = col.rgb * (pow(max(q, 0.0), 2.2) / lum);
		c = mix(col.rgb, stepped, posterize_mix * intensity);
	}

	// ---- ③ 饱和度提纯 ----
	// ⚠️ `intensity` **必须乘进来**：原来漏了 ⇒ 总开关打到 0 时画面仍被提 18%
	// 的饱和（"关了还在改色"）。那会让 A/B 归因把它误判成"是别的层在动"。
	c = mix(vec3(lum), c, mix(1.0, saturation, intensity));

	// ---- ④ 合成：边压暗 ----
	float e = edge * intensity;
	c = mix(c, outline_color.rgb, e * 0.85);

	// spatial 输出：ALBEDO = 颜色，ALPHA = 1（blend_mix 下不透明地盖在场景上）
	ALBEDO = c;
	ALPHA = 1.0;
}
