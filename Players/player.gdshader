shader_type canvas_item;

// 描边颜色
uniform vec4 line_color : source_color = vec4(1.0, 0.8, 0.0, 1.0); 
// 描边厚度最大值提升到 20，适应高清大图
uniform float line_thickness : hint_range(0, 20) = 0.0; 
// 是否开启呼吸闪烁效果
uniform bool enable_pulse = true; 

void fragment() {
	vec4 original_color = texture(TEXTURE, UV);
	
	// 【核心修复】：如果厚度为 0，直接停止所有计算，原画输出！绝对不可能有任何残留！
	if (line_thickness <= 0.0) {
		COLOR = original_color;
	} else {
		// 动态呼吸计算：利用系统 TIME 生成一个 0.5 到 1.0 之间来回变化的乘数
		float current_thickness = line_thickness;
		if (enable_pulse) {
			current_thickness *= ((sin(TIME * 5.0) + 1.7) / 2.0 * 0.5 + 0.5);
		}
		
		vec2 size = TEXTURE_PIXEL_SIZE * current_thickness;
		
		// 8 方向边缘探测
		float outline = texture(TEXTURE, UV + vec2(-size.x, 0)).a;
		outline += texture(TEXTURE, UV + vec2(0, size.y)).a;
		outline += texture(TEXTURE, UV + vec2(size.x, 0)).a;
		outline += texture(TEXTURE, UV + vec2(0, -size.y)).a;
		outline += texture(TEXTURE, UV + vec2(-size.x, size.y)).a;
		outline += texture(TEXTURE, UV + vec2(size.x, size.y)).a;
		outline += texture(TEXTURE, UV + vec2(-size.x, -size.y)).a;
		outline += texture(TEXTURE, UV + vec2(size.x, -size.y)).a;
		
		// 限制最大 Alpha 为 1.0
		outline = min(outline, 1.0);
		
		// 完美混合：只在透明区域画线，不遮挡原画
		COLOR = mix(original_color, line_color, outline - original_color.a);
	}
}