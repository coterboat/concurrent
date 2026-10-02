// A commander's colours on their staff (scenery.gd): a cloth that ripples in the wind, fixed at
// the staff (its left edge), shaded a little in its folds.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 colour : source_color = vec3(0.8, 0.1, 0.1);

varying float fold;

void vertex() {
	float k = UV.x; // 0 at the staff, 1 at the fly
	float w = sin(UV.x * 7.0 - TIME * 5.0) * k;
	VERTEX.z += w * 2.2;
	VERTEX.y -= k * k * 1.5;
	fold = w;
}

void fragment() {
	vec3 c = colour * (0.82 + 0.25 * fold);
	// a pale stripe at the hoist, so even a dark commander's colours read against the sky
	c = mix(c, vec3(0.95, 0.92, 0.84), step(UV.x, 0.12) * 0.7);
	ALBEDO = c;
	ROUGHNESS = 0.8;
}
