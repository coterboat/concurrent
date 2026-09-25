// Paints the campaign map from the mapgen data texture.
//   data.r = territory index   data.g = signed coast distance (128 = shore, 3/px)
//   data.b = distance to a territory border (8/px)   data.a = distance to a region border (8/px)
// state texture (N x 2): row 0 rgb = owner tint, a = flags; row 1 rgb = region tint.
shader_type canvas_item;

uniform sampler2D data_n : filter_nearest;
uniform sampler2D data_l : filter_linear;
uniform sampler2D state_tex : filter_nearest;
uniform sampler2D land_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D sea_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D paper_tex : repeat_enable, filter_linear_mipmap;
uniform vec2 map_size = vec2(2400.0, 1500.0);
uniform float n_terr = 30.0;
uniform float screen_per_texel = 0.5; // screen pixels per map pixel
uniform int hover_id = -1;
uniform int select_id = -1;
uniform float pulse = 0.0;
uniform int view_mode = 0; // 0 = owners, 1 = regions

const int F_TARGET = 1;
const int F_DIM = 2;
const int F_BATTLE = 4;
const int F_OWNED = 8;
const int F_EMPTY = 16;

vec3 desat(vec3 c, float k) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(c, vec3(l), k);
}

void fragment() {
	vec2 uv = UV;
	vec2 mp = uv * map_size; // map pixels
	vec4 dn = texture(data_n, uv);
	vec4 dl = texture(data_l, uv);
	int id = int(round(dn.r * 255.0));
	float idx = (float(id) + 0.5) / n_terr;
	vec4 st = texture(state_tex, vec2(idx, 0.25));
	vec3 region_tint = texture(state_tex, vec2(idx, 0.75)).rgb;
	int flags = int(round(st.a * 255.0));

	float coast = (dl.g * 255.0 - 128.0) / 3.0;    // + land, - sea, in map px
	float bdist = dl.b * 255.0 / 8.0;
	float rdist = dl.a * 255.0 / 8.0;
	float px = 1.0 / max(screen_per_texel, 0.05);   // map px per screen px
	float aa = px * 0.9;

	// ---- sea
	vec3 sea = texture(sea_tex, mp / 700.0).rgb;
	sea = mix(sea, vec3(0.06, 0.12, 0.22), 0.25);
	float shore = clamp(1.0 + coast / 60.0, 0.0, 1.0); // 1 at the shore, 0 far out
	sea = mix(sea, vec3(0.22, 0.42, 0.52), shore * shore * 0.55);
	float ring = sin(-coast * 0.28 - TIME * 1.4);
	float foam = smoothstep(0.86, 1.0, ring) * smoothstep(34.0, 6.0, -coast) * smoothstep(0.0, 4.0, -coast);
	sea += vec3(0.55, 0.6, 0.55) * foam * 0.22;
	// faint chart grid on the water
	vec2 g = abs(fract(mp / 240.0) - 0.5);
	float grid = smoothstep(0.5 - px / 240.0 * 1.2, 0.5, max(g.x, g.y));
	sea = mix(sea, vec3(0.55, 0.62, 0.66), grid * 0.08);

	// ---- land
	vec3 terrain = texture(land_tex, mp / 520.0).rgb;
	vec3 paper = texture(paper_tex, mp / 900.0).rgb;
	vec3 base = desat(terrain, 0.55) * 0.55 + paper * 0.55;
	vec3 owner = st.rgb;
	bool empty = (flags & F_EMPTY) != 0;
	vec3 land;
	if (view_mode == 1) {
		// Regions: the land wears its region's colour; owners ride a band inside each border
		land = mix(base, region_tint, 0.66);
		float band_w = max(7.0 * px, 5.0);
		float band = 1.0 - smoothstep(band_w - aa, band_w + aa, bdist);
		if (!empty) {
			land = mix(land, owner * 1.05, band * 0.92);
		}
	} else {
		land = empty ? mix(base, paper * 0.95, 0.35) : mix(base, owner, 0.58);
		land *= mix(vec3(1.0), region_tint, 0.12);
		// inner glow along each territory's edge, in its own colour
		float glow = 1.0 - smoothstep(0.0, 22.0, bdist);
		if (!empty) {
			land = mix(land, owner * 1.12, glow * 0.4);
		}
	}
	// every region carries a soft band of its own colour just inside its outline
	float edge_d = min(rdist, max(coast, 0.0)); // region border or shoreline, whichever is nearer
	float rglow = 1.0 - smoothstep(0.0, max(16.0 * px, 12.0), edge_d);
	land = mix(land, region_tint * 1.1, rglow * (view_mode == 1 ? 0.25 : 0.45));
	bool hovered = id == hover_id;
	bool selected = id == select_id;
	if ((flags & F_DIM) != 0) {
		land = desat(land, 0.65) * 0.72;
	}
	if ((flags & F_TARGET) != 0) {
		float p = 0.5 + 0.5 * sin(TIME * 5.0);
		land = mix(land, vec3(1.0, 0.86, 0.45), (1.0 - smoothstep(0.0, 26.0, bdist)) * (0.35 + 0.35 * p));
	}
	if ((flags & F_BATTLE) != 0) {
		land = mix(land, vec3(1.0, 0.95, 0.8), 0.18 + 0.12 * pulse);
	}
	if (hovered) {
		land = land * 1.14 + vec3(0.03);
	}
	if (selected) {
		land = land * 1.2 + vec3(0.05, 0.04, 0.0);
	}
	// territory border
	float bw = max(1.1 * px, 1.2);
	float border = 1.0 - smoothstep(bw - aa, bw + aa, bdist);
	vec3 border_col = vec3(0.10, 0.08, 0.07);
	if (selected) {
		float sw = max(4.0 * px, 3.0);
		float sb = 1.0 - smoothstep(sw - aa, sw + aa, bdist);
		land = mix(land, vec3(1.0, 0.86, 0.4), sb);
	}
	land = mix(land, border_col, border * 0.85);
	// region border: a heavy dark rule with a bright gold core, readable at any zoom
	float rw = max(3.6 * px, 3.0);
	float rb = 1.0 - smoothstep(rw - aa, rw + aa, rdist);
	float rcore = 1.0 - smoothstep(rw * 0.38 - aa, rw * 0.38 + aa, rdist);
	land = mix(land, vec3(0.1, 0.075, 0.04), rb * 0.95);
	land = mix(land, vec3(0.95, 0.78, 0.38), rcore * 0.9);

	// ---- coast
	float land_a = smoothstep(-aa, aa, coast);
	vec3 col = mix(sea, land, land_a);
	float cw = max(1.4 * px, 1.4);
	float coast_line = 1.0 - smoothstep(cw - aa, cw + aa, abs(coast));
	col = mix(col, vec3(0.13, 0.1, 0.08), coast_line * 0.9);
	// soft drop shadow of the land onto the sea
	float shadow = smoothstep(-14.0, 0.0, coast) * (1.0 - land_a);
	col *= 1.0 - shadow * 0.28;

	// ---- paper age + vignette over everything
	col *= mix(vec3(1.0), paper * 1.15, 0.22);
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.55;
	COLOR = vec4(col, 1.0);
}
