shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform float progress : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	float stepped_noise = hash21(floor(UV * vec2(28.0, 52.0)));
	float fine_wave = sin(UV.x * 71.0 + stepped_noise * 5.0) * 0.025;
	float height_from_bottom = 1.0 - UV.y + (stepped_noise - 0.5) * 0.11 + fine_wave;
	float visible_mask = smoothstep(progress - 0.035, progress + 0.035, height_from_bottom);
	COLOR = vec4(tex.rgb, tex.a * visible_mask);
}
