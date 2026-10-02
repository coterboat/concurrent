// The sea, one plane at height 0 reaching past the chart's edges. Its colour comes from how
// deep the ground lies under it (terrain.gd's heights), with surf at the shore.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D data_l : filter_linear, repeat_disable;
uniform sampler2D sea_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D wave_a : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D wave_b : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec2 map_size = vec2(2400.0, 1500.0);
uniform float relief = 1.0;
uniform float fade = 1.0;
uniform vec3 daylight = vec3(1.0);
uniform float paint = 0.0; // the chart's own sea laid over the water (the board on the land)

varying vec2 mp;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	mp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = mp / map_size;
	bool inside = uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
	float ground = inside ? texture(height_tex, uv).r * relief : -48.0 * relief;
	float depth = max(0.0, -ground);
	float coast = inside ? (texture(data_l, uv).g * 255.0 - 128.0) / 3.0 : -80.0;
	vec3 deep = vec3(0.03, 0.10, 0.16);
	vec3 shallow = vec3(0.14, 0.36, 0.38);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 24.0, depth));
	vec3 st = texture(sea_tex, mp / 700.0).rgb;
	col *= 0.75 + 0.5 * st;
	float ring = sin(-coast * 0.3 - TIME * 1.3);
	float surf = smoothstep(0.82, 1.0, ring) * smoothstep(26.0, 3.0, -coast) * (inside ? 1.0 : 0.0);
	float lap = 1.0 - smoothstep(0.0, 1.6 + 0.6 * sin(TIME * 1.7 + mp.x * 0.05), depth);
	float foam = clamp(surf * 0.5 + lap * 0.8, 0.0, 1.0);
	// the chart's sea (map.gdshader's): navy, lighter by the shore, its faint grid
	vec3 cs = st;
	cs = mix(cs, vec3(0.06, 0.12, 0.22), 0.25);
	float shore_k = clamp(1.0 + coast / 60.0, 0.0, 1.0);
	cs = mix(cs, vec3(0.22, 0.42, 0.52), shore_k * shore_k * 0.55);
	float gpx = max(length(fwidth(mp)) * 0.7, 0.02);
	vec2 gg = abs(fract(mp / 240.0) - 0.5);
	cs = mix(cs, vec3(0.55, 0.62, 0.66), smoothstep(0.5 - gpx / 240.0 * 1.2, 0.5, max(gg.x, gg.y)) * 0.08 * (inside ? 1.0 : 0.0));
	col = mix(col, cs * 1.15, paint * 0.9);
	col = mix(col, vec3(0.86, 0.89, 0.86), foam);
	col *= daylight;
	ALBEDO = to_linear(col);
	ALPHA = fade * clamp(mix(0.5, 0.97, smoothstep(0.0, 9.0, depth)) + foam * 0.5, 0.0, 1.0);
	// painted (the board on the land), the sea is the chart's: matte, so it shows its own navy
	// rather than the sky; in a battle (paint 0) it shines
	ROUGHNESS = mix(mix(0.07, 0.6, foam), 0.55, paint);
	SPECULAR = mix(0.55, 0.12, paint);
	vec3 na = texture(wave_a, mp / 170.0 + TIME * vec2(0.010, 0.006)).rgb;
	vec3 nb = texture(wave_b, mp / 110.0 - TIME * vec2(0.007, 0.011)).rgb;
	NORMAL_MAP = normalize(mix(na, nb, 0.5));
	NORMAL_MAP_DEPTH = 0.55;
}
