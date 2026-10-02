// The ground of the 3D world. Two looks in one, crossfaded by `realism`:
//   0: the campaign chart, exactly as map.gdshader paints it (as light, so it matches the 2D board)
//   1: lit land with the relief from terrain.gd: grass, rock on the slopes, snow up high, woods,
//      rivers on the borders between lowland lands, a wash of each owner's colour at its edges.
// `relief` raises the land from the flat chart (0) to its full height (1).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform sampler2D height_mip : filter_linear_mipmap, repeat_disable; // the same heights, with mipmaps (for the hollows)
uniform sampler2D ground_tex : filter_linear, repeat_disable;
uniform sampler2D data_n : filter_nearest, repeat_disable;
uniform sampler2D data_l : filter_linear, repeat_disable;
uniform sampler2D state_tex : filter_nearest;
uniform sampler2D land_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D sea_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D paper_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap; // a tiling noise for the ground's grain
uniform vec2 map_size = vec2(2400.0, 1500.0);
uniform vec2 cell = vec2(3.0, 3.0);
uniform float n_terr = 30.0;
uniform float relief : hint_range(0.0, 1.0) = 1.0;
uniform float realism : hint_range(0.0, 1.0) = 1.0;
uniform float paint : hint_range(0.0, 1.0) = 0.0; // the chart's colours painted onto the lit land (the board in 3D)
uniform vec3 daylight = vec3(1.0);
uniform float snow_line = 120.0;
// the board's own state, mirrored by LandBoard each frame (map.gdshader's)
uniform int hover_id = -1;
uniform int select_id = -1;
uniform float pulse = 0.0;
uniform int view_mode = 0; // 0 = owners, 1 = regions
// the ground's own texture (world_view.gd's DETAIL): one layer a terrain, blended by the terrain
// weights, as a ratio over the painted colour (so the land keeps its palette and gains its grain)
uniform bool has_detail = false;
uniform sampler2DArray detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 detail_mean[10];
uniform sampler2D weights_a : filter_linear, repeat_disable;
uniform sampler2D weights_b : filter_linear, repeat_disable;
uniform float detail_scale = 110.0; // map px a tile
uniform float clouds = 1.0; // the shadows of passing clouds (0: none)
uniform sampler2D fields_tex : filter_linear, repeat_disable; // the ploughed fields round the villages (scenery.gd)

const int F_TARGET = 1;
const int F_DIM = 2;
const int F_BATTLE = 4;
const int F_EMPTY = 16;

varying vec2 mp;
varying float wy;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 desat(vec3 c, float k) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(c, vec3(l), k);
}

float hgt(vec2 p) {
	return textureLod(height_tex, p / map_size, 0.0).r;
}

void vertex() {
	vec3 wv = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	mp = wv.xz;
	float h = hgt(mp);
	VERTEX.y += h * relief;
	wy = h;
	float hl = hgt(mp - vec2(cell.x, 0.0));
	float hr = hgt(mp + vec2(cell.x, 0.0));
	float hu = hgt(mp - vec2(0.0, cell.y));
	float hd = hgt(mp + vec2(0.0, cell.y));
	NORMAL = normalize(vec3((hl - hr) * relief, 2.0 * cell.x, (hu - hd) * relief));
}

// ---- the campaign chart (map.gdshader, owners view), in its own sRGB terms
vec3 chart(vec2 uv, float px, vec4 dn, vec4 dl) {
	int id = int(round(dn.r * 255.0));
	float idx = (float(id) + 0.5) / n_terr;
	vec4 st = texture(state_tex, vec2(idx, 0.25));
	vec3 region_tint = texture(state_tex, vec2(idx, 0.75)).rgb;
	int flags = int(round(st.a * 255.0));
	float coast = (dl.g * 255.0 - 128.0) / 3.0;
	float bdist = dl.b * 255.0 / 8.0;
	float rdist = dl.a * 255.0 / 8.0;
	float aa = px * 0.9;
	vec3 sea = texture(sea_tex, mp / 700.0).rgb;
	sea = mix(sea, vec3(0.06, 0.12, 0.22), 0.25);
	float shore = clamp(1.0 + coast / 60.0, 0.0, 1.0);
	sea = mix(sea, vec3(0.22, 0.42, 0.52), shore * shore * 0.55);
	float ring = sin(-coast * 0.28 - TIME * 1.4);
	float foam = smoothstep(0.86, 1.0, ring) * smoothstep(34.0, 6.0, -coast) * smoothstep(0.0, 4.0, -coast);
	sea += vec3(0.55, 0.6, 0.55) * foam * 0.22;
	vec2 g = abs(fract(mp / 240.0) - 0.5);
	float grid = smoothstep(0.5 - px / 240.0 * 1.2, 0.5, max(g.x, g.y));
	sea = mix(sea, vec3(0.55, 0.62, 0.66), grid * 0.08);
	vec3 terrain = texture(land_tex, mp / 520.0).rgb;
	vec3 paper = texture(paper_tex, mp / 900.0).rgb;
	vec3 base = desat(terrain, 0.55) * 0.55 + paper * 0.55;
	vec3 owner = st.rgb;
	bool empty = (flags & F_EMPTY) != 0;
	vec3 land;
	if (view_mode == 1) {
		land = mix(base, region_tint, 0.66);
		float band_w = max(7.0 * px, 5.0);
		float band = 1.0 - smoothstep(band_w - aa, band_w + aa, bdist);
		if (!empty) {
			land = mix(land, owner * 1.05, band * 0.92);
		}
	} else {
		land = empty ? mix(base, paper * 0.95, 0.35) : mix(base, owner, 0.58);
		land *= mix(vec3(1.0), region_tint, 0.12);
		float glow = 1.0 - smoothstep(0.0, 22.0, bdist);
		if (!empty) {
			land = mix(land, owner * 1.12, glow * 0.4);
		}
	}
	float edge_d = min(rdist, max(coast, 0.0));
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
	float bw = max(1.1 * px, 1.2);
	float border = 1.0 - smoothstep(bw - aa, bw + aa, bdist);
	if (selected) {
		float sw = max(4.0 * px, 3.0);
		float sb = 1.0 - smoothstep(sw - aa, sw + aa, bdist);
		land = mix(land, vec3(1.0, 0.86, 0.4), sb);
	}
	land = mix(land, vec3(0.10, 0.08, 0.07), border * 0.85);
	float rw = max(3.6 * px, 3.0);
	float rb = 1.0 - smoothstep(rw - aa, rw + aa, rdist);
	float rcore = 1.0 - smoothstep(rw * 0.38 - aa, rw * 0.38 + aa, rdist);
	land = mix(land, vec3(0.1, 0.075, 0.04), rb * 0.95);
	land = mix(land, vec3(0.95, 0.78, 0.38), rcore * 0.9);
	float land_a = smoothstep(-aa, aa, coast);
	sea *= daylight;
	land *= mix(vec3(1.0), daylight, 0.35);
	vec3 col = mix(sea, land, land_a);
	float cw = max(1.4 * px, 1.4);
	float coast_line = 1.0 - smoothstep(cw - aa, cw + aa, abs(coast));
	col = mix(col, vec3(0.13, 0.1, 0.08), coast_line * 0.9);
	float shadow = smoothstep(-14.0, 0.0, coast) * (1.0 - land_a);
	col *= 1.0 - shadow * 0.28;
	col *= mix(vec3(1.0), paper * 1.15, 0.22);
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.55;
	return col;
}

void fragment() {
	vec2 uv = mp / map_size;
	vec4 dn = texture(data_n, uv);
	vec4 dl = texture(data_l, uv);
	float px = max(length(fwidth(mp)) * 0.7, 0.02);
	vec3 chart_col = chart(uv, px, dn, dl);

	// ---- the land itself
	float h = hgt(mp);
	float hl = hgt(mp - vec2(cell.x, 0.0));
	float hr = hgt(mp + vec2(cell.x, 0.0));
	float hu = hgt(mp - vec2(0.0, cell.y));
	float hd = hgt(mp + vec2(0.0, cell.y));
	vec3 n = normalize(vec3((hl - hr) * relief, 2.0 * cell.x, (hu - hd) * relief));
	float slope = 1.0 - n.y;
	vec3 gn = texture(grain_tex, mp / 38.0).rgb;
	vec3 gn2 = texture(grain_tex, mp / 160.0).rgb;
	// a little grain in the light, so the ground isn't plastic
	n = normalize(n + vec3(gn.r - 0.5, 0.0, gn.g - 0.5) * 0.18 * realism);

	vec4 gt = texture(ground_tex, uv);
	vec3 g = gt.rgb;
	float woods = gt.a;
	float det_k = 0.0;
	vec3 det_ratio = vec3(1.0);
	if (has_detail) {
		vec4 wa = texture(weights_a, uv);
		vec4 wb = texture(weights_b, uv);
		float tot = max(dot(wa, vec4(1.0)) + dot(wb, vec4(1.0)), 0.001);
		// two scales, a little turned, so the tiles don't show
		vec2 t1 = mp / detail_scale;
		vec2 t2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * mp / (detail_scale * 2.7);
		vec3 d = vec3(0.0);
		vec3 m = vec3(0.0);
		float ws[8] = float[8](wa.r, wa.g, wa.b, wa.a, wb.r, wb.g, wb.b, wb.a);
		for (int i = 0; i < 8; i++) {
			float wi = ws[i] / tot;
			if (wi > 0.015) {
				vec3 s1 = texture(detail_tex, vec3(t1, float(i))).rgb;
				vec3 s2 = texture(detail_tex, vec3(t2, float(i))).rgb;
				d += mix(s1, s2, 0.35) * wi;
				m += detail_mean[i] * wi;
			}
		}
		det_ratio = clamp(d / max(m, vec3(0.04)), vec3(0.35), vec3(1.9));
		det_k = 0.8;
		// the village fields: the field mat, rows and all, laid over the ground (its own colours)
		float fld = texture(fields_tex, uv).r;
		if (fld > 0.01) {
			vec3 fs = texture(detail_tex, vec3(mp / 70.0, 9.0)).rgb;
			float ragged = smoothstep(0.0, 0.6, fld + (gn2.r - 0.5) * 0.5); // a field's edge isn't ruled
			g = mix(g, mix(fs * 1.08, g, 0.3), ragged * 0.72);
			det_ratio = mix(det_ratio, vec3(1.0), fld);
		}
	}
	vec3 lt = texture(land_tex, mp / 150.0).rgb;
	float lum = dot(lt, vec3(0.3, 0.59, 0.11));
	float flat_n = smoothstep(0.55, 0.25, slope); // detail painted from above only where the ground faces up
	g *= mix(1.0, 0.78 + 0.45 * lum + (gn2.r - 0.5) * 0.25, flat_n * (1.0 - det_k * 0.7));
	g = mix(g, g * det_ratio, det_k * flat_n);
	// woods: dark canopy in clumps
	float clump = smoothstep(0.42, 0.62, gn2.g + woods * 0.55 - 0.25);
	g = mix(g, vec3(0.13, 0.21, 0.10) * (0.8 + 0.4 * gn.b), clump * woods * 0.85);
	// bare rock on the steep, snow on the high
	// rock, textured from the side on a cliff so it never smears
	vec3 an = abs(n);
	float rx = texture(grain_tex, vec2(mp.y, wy) / 22.0).r;
	float rz = texture(grain_tex, vec2(mp.x, wy) / 22.0).g;
	float rt = texture(grain_tex, mp / 22.0).b;
	float rgrain = (rx * an.x + rz * an.z + rt * an.y) / (an.x + an.y + an.z);
	float strata = 0.5 + 0.5 * sin(wy * 0.9 + rgrain * 3.0);
	vec3 rock = vec3(0.43, 0.40, 0.36) * (0.62 + 0.55 * rgrain) * (0.9 + 0.12 * strata);
	if (has_detail) {
		// the rock mat, laid on from the side the cliff faces
		vec3 rxs = texture(detail_tex, vec3(vec2(mp.y, wy) / 70.0, 7.0)).rgb;
		vec3 rzs = texture(detail_tex, vec3(vec2(mp.x, wy) / 70.0, 7.0)).rgb;
		vec3 rts = texture(detail_tex, vec3(mp / 70.0, 7.0)).rgb;
		vec3 rtex = (rxs * an.x + rzs * an.z + rts * an.y) / (an.x + an.y + an.z);
		rock = mix(rock, rock * clamp(rtex / max(detail_mean[7], vec3(0.04)), vec3(0.4), vec3(1.8)), 0.85);
	}
	float rocky = smoothstep(0.26, 0.48, slope + (gn.g - 0.5) * 0.12);
	g = mix(g, rock, rocky);
	float snow = smoothstep(snow_line - 15.0, snow_line + 20.0, h + (gn2.b - 0.5) * 40.0) * (1.0 - smoothstep(0.45, 0.7, slope));
	g = mix(g, vec3(0.92, 0.94, 0.98), snow);

	// hollows a shade darker and greener, ridges a shade paler (the land as a painter sees it)
	float avg = textureLod(height_mip, uv, 3.0).r;
	float cav = clamp((h - avg) / 14.0, -1.0, 1.0);
	g *= 1.0 + cav * 0.16;
	// a beach where low land meets the sea
	float beach_c = (dl.g * 255.0 - 128.0) / 3.0;
	float beach = (1.0 - smoothstep(3.0, 9.0 + gn.r * 6.0, beach_c)) * (1.0 - smoothstep(6.0, 14.0, h)) * step(0.0, beach_c);
	vec3 sandc = vec3(0.80, 0.72, 0.53) * (0.9 + 0.2 * gn.b);
	if (has_detail) {
		sandc *= clamp(texture(detail_tex, vec3(mp / 80.0, 8.0)).rgb / max(detail_mean[8], vec3(0.04)), vec3(0.5), vec3(1.6));
	}
	g = mix(g, sandc, beach * (1.0 - rocky));
	// fine colour in the grass: no two paces of ground the same
	float fine = texture(grain_tex, mp / 9.0).r;
	g *= mix(0.9 + 0.2 * fine, 1.0, rocky);
	// owners: a wash of colour inside each land's edge (the chart's glow, softly)
	int id = int(round(dn.r * 255.0));
	vec4 st = texture(state_tex, vec2((float(id) + 0.5) / n_terr, 0.25));
	int flags = int(round(st.a * 255.0));
	float coast = (dl.g * 255.0 - 128.0) / 3.0;
	float bdist = dl.b * 255.0 / 8.0;
	if ((flags & F_EMPTY) == 0) {
		float edge = 1.0 - smoothstep(0.0, 11.0, bdist);
		g = mix(g, st.rgb * 0.95, edge * edge * 0.38 + 0.05);
	}
	// the border between two lands: a river down in the lowlands, a dark crest line in the hills
	float landb = step(bdist + 1.5, coast);
	float wet = 1.0 - smoothstep(1.4, 2.6, bdist);
	float lowland = 1.0 - smoothstep(55.0, 80.0, h);
	vec3 river = vec3(0.16, 0.28, 0.31) + vec3(0.08) * gn.r;
	g = mix(g, river, wet * landb * lowland);
	float bank = (1.0 - smoothstep(2.4, 4.2, bdist)) * landb * lowland * (1.0 - wet);
	g = mix(g, g * vec3(0.72, 0.66, 0.55), bank);
	float crest = (1.0 - smoothstep(0.8, 2.2, bdist)) * landb * (1.0 - lowland);
	g = mix(g, vec3(0.16, 0.12, 0.10), crest * 0.8);
	// under the sea: wet sand going dark
	float sand = smoothstep(-1.0, 1.5, coast);
	g = mix(mix(vec3(0.42, 0.40, 0.30), vec3(0.12, 0.16, 0.16), smoothstep(0.0, 25.0, -coast)), g, sand);
	g *= mix(vec3(1.0), daylight, 0.6);
	// clouds' shadows drifting over the land
	float cloud = texture(grain_tex, mp / 1400.0 + TIME * vec2(0.0035, 0.0012)).g;
	g *= 1.0 - smoothstep(0.56, 0.74, cloud) * 0.16 * clouds;

	g = mix(g, chart_col * mix(vec3(1.0), g * 1.6, 0.25), paint);
	// the board's own marks on the lit land, at full strength: the land selected wears a gold rim,
	// the one under the cursor lightens
	float spx = max(length(fwidth(mp)) * 0.7, 0.02);
	if (id == select_id) {
		float sw = max(4.0 * spx, 3.0);
		g = g * 1.12 + vec3(0.03, 0.025, 0.0);
		g = mix(g, vec3(1.0, 0.84, 0.38), (1.0 - smoothstep(sw - spx, sw + spx, bdist)) * step(0.0, coast) * realism);
	}
	if (id == hover_id) {
		g = g * 1.08 + vec3(0.015);
	}
	ALBEDO = to_linear(clamp(g, 0.0, 1.0)) * realism;
	EMISSION = to_linear(chart_col) * (1.0 - realism);
	ROUGHNESS = mix(0.95, 0.25, wet * landb * lowland);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
}
