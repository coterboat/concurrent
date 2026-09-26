// A die, drawn from its own local position: which face, where the pips sit, what it is
// made of. Faces: +Y 1, -Y 6, +X 2, -X 5, +Z 3, -Z 4 (opposite faces sum to seven).
// The material is set per die from its army's size: whittled wood for a lone holdout,
// bone, ivory with enamel pips, lacquer in the commander's colours, and gold with gem pips
// and an imperial star for a grand army.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 body_col : source_color = vec4(0.95, 0.92, 0.84, 1.0);
uniform vec4 pip_col : source_color = vec4(0.1, 0.07, 0.05, 1.0);
uniform vec4 edge_col : source_color = vec4(0.78, 0.6, 0.3, 1.0);
uniform vec4 glow_col : source_color = vec4(1.0, 0.8, 0.35, 1.0);
uniform float edge_w = 0.0; // brass trim along the edges (0 none, 1 full)
uniform float body_metal = 0.0;
uniform float body_rough = 0.5;
uniform float pip_metal = 0.0;
uniform float pip_rough = 0.5;
uniform float pip_glow = 0.0; // gem pips shine
uniform float grain = 0.0; // wood grain
uniform float star = 0.0; // the one face carries a star instead of a pip
uniform float dim = 0.0; // the loser of the duel
uniform float flash = 0.0; // the winner of the duel
uniform float wear = 0.0; // chips and dirt on a rough die

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float sd_star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-0.809016994375, -0.587785252292);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// signed distance to the nearest pip edge (negative inside a pip), and that pip's centre
float pips(vec2 uv, int v, out vec2 centre) {
	float k = 0.5;
	float r = 0.17;
	float best = 9.0;
	centre = vec2(0.0);
	vec2 c[6];
	int n = 0;
	if (v == 1) {
		centre = vec2(0.0);
		return length(uv) - 0.27;
	}
	if (v == 3 || v == 5) { c[n] = vec2(0.0); n++; }
	if (v >= 2) { c[n] = vec2(-k, -k); n++; c[n] = vec2(k, k); n++; }
	if (v >= 4) { c[n] = vec2(-k, k); n++; c[n] = vec2(k, -k); n++; }
	if (v == 6) { c[n] = vec2(-k, 0.0); n++; c[n] = vec2(k, 0.0); n++; }
	for (int i = 0; i < 6; i++) {
		if (i >= n) {
			break;
		}
		float d = length(uv - c[i]) - r;
		if (d < best) {
			best = d;
			centre = c[i];
		}
	}
	return best;
}

void fragment() {
	vec3 a = abs(lp);
	int face;
	vec2 uv;
	if (a.y >= a.x && a.y >= a.z) {
		face = lp.y > 0.0 ? 1 : 6;
		uv = lp.xz;
	} else if (a.x >= a.z) {
		face = lp.x > 0.0 ? 2 : 5;
		uv = lp.zy;
	} else {
		face = lp.z > 0.0 ? 3 : 4;
		uv = lp.xy;
	}
	uv /= 0.5;
	float mx = max(a.x, max(a.y, a.z));
	float mn = min(a.x, min(a.y, a.z));
	float mid = a.x + a.y + a.z - mx - mn;
	float edge = smoothstep(0.33, 0.41, mid);

	vec3 body = body_col.rgb;
	if (grain > 0.0) {
		float g = sin((lp.x * 2.3 + lp.z * 0.7 + sin(lp.z * 7.0 + lp.y * 4.0) * 0.28) * 34.0) * 0.5 + 0.5;
		body = mix(body, body * 0.62, g * grain);
	}
	if (wear > 0.0) {
		float h = hash3(floor(lp * 22.0));
		body = mix(body, body * 0.72, step(0.86, h) * wear);
		body = mix(body, body * 0.8, edge * wear * 0.8);
	}
	float metal = body_metal;
	float rough = body_rough;
	vec3 emit = vec3(0.0);
	if (edge_w > 0.0) {
		float trim = edge * edge_w;
		body = mix(body, edge_col.rgb, trim);
		metal = mix(metal, 0.9, trim);
		rough = mix(rough, 0.3, trim);
	}

	vec2 pc;
	float pd;
	if (face == 1 && star > 0.5) {
		pd = sd_star5(vec2(uv.x, -uv.y), 0.46, 0.45);
		pc = vec2(0.0);
	} else {
		pd = pips(uv, face, pc);
	}
	float inside = 1.0 - smoothstep(-0.015, 0.015, pd);
	// a pip is a hollow: dark on the side the light comes from, bright on the far lip
	vec2 off = uv - pc;
	float bowl = clamp(dot(off, vec2(0.6, 0.8)) * 2.4, -1.0, 1.0);
	vec3 pip = pip_col.rgb * (0.78 + 0.32 * bowl);
	float lip = smoothstep(0.035, 0.0, abs(pd)) * (1.0 - inside) * 0.35;
	body *= 1.0 - lip;
	vec3 col = mix(body, pip, inside);
	metal = mix(metal, pip_metal, inside);
	rough = mix(rough, pip_rough, inside);
	emit += pip_col.rgb * pip_glow * inside * (0.55 + 0.45 * bowl);

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	emit += glow_col.rgb * flash * (0.25 + 0.9 * fres);
	col = mix(col, col * 0.38, dim);
	rough = mix(rough, 0.9, dim);
	emit *= 1.0 - dim * 0.8;

	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
	EMISSION = emit;
}
