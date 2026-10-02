// A painted tin soldier in its commander's colours: the coat's own paint (red on the foot,
// sky blue on the hussar: `key_hue`) is repainted in the seat's colour, keeping the paint's
// light and shade, so a model of any coat serves every army.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 team : source_color = vec3(0.8, 0.1, 0.1);
uniform bool repaint = true;
uniform float key_hue = 0.0; // 0..1: the coat's hue (0 red, 0.55 sky blue)
uniform float key_width = 0.07;
uniform float flash = 0.0;
uniform float fade = 1.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	if (repaint) {
		vec3 hsv = rgb2hsv(c);
		float dh = abs(hsv.x - key_hue);
		dh = min(dh, 1.0 - dh);
		float key = (1.0 - smoothstep(key_width, key_width * 1.8, dh)) * smoothstep(0.28, 0.45, hsv.y) * smoothstep(0.04, 0.12, hsv.z);
		float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
		float tl = max(dot(team, vec3(0.2126, 0.7152, 0.0722)), 0.02);
		vec3 coat = clamp(team * (l / tl) * 1.5, 0.0, 1.0);
		c = mix(c, coat, key);
	}
	ALBEDO = c * fade;
	METALLIC = 0.3;
	ROUGHNESS = 0.42;
	SPECULAR = 0.6;
	EMISSION = vec3(1.0, 0.75, 0.4) * flash;
}
