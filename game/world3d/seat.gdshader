// v2.0.2: a second coat over the land's buildings (Ludo's models, their own material kept and lit
// as ever): the lime of a model's grass plate brought down toward the land's own greens, its
// near-black paint lifted a little, and the foot of every wall darkened where it meets the ground,
// so a building sits in the land rather than on a tile laid on it. It multiplies what the model's
// own pass drew.
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float base_y = 0.0; // the model's foot and height, in its own space
uniform float tall = 1.0;

varying float above;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	above = (VERTEX.y - base_y) / max(tall, 0.0001);
}

void fragment() {
	vec3 lin = texture(albedo_tex, UV).rgb;
	vec3 s = pow(max(lin, vec3(0.0)), vec3(1.0 / 2.2));
	vec3 hsv = rgb2hsv(s);
	// the neon grass of a model's plate: yellow-green, strongly saturated and bright
	float lime = smoothstep(0.12, 0.17, hsv.x) * (1.0 - smoothstep(0.38, 0.46, hsv.x))
		* smoothstep(0.40, 0.65, hsv.y) * smoothstep(0.30, 0.55, hsv.z);
	vec3 h2 = vec3(mix(hsv.x, 0.26, 0.35 * lime), hsv.y * (1.0 - 0.45 * lime), hsv.z * (1.0 - 0.22 * lime));
	vec3 t = pow(hsv2rgb(h2), vec3(2.2));
	vec3 ratio = mix(vec3(1.0), clamp(t / max(lin, vec3(0.002)), vec3(0.0), vec3(2.0)), lime);
	// near-black paint (a chalet's shingles, seen from the board's height, read as a hole in the
	// land) lifted a little toward the rest of the model
	float dark = 1.0 - smoothstep(0.07, 0.24, hsv.z);
	ratio *= 1.0 + 0.55 * dark;
	// the foot of every wall, where it meets the ground
	float foot = 1.0 - smoothstep(0.0, 0.14, above);
	ALBEDO = ratio * (1.0 - 0.32 * foot);
}
