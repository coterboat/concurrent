// v2.4: a musket ball's streak (diorama.gd _tracer). A ribbon along the ball's flight that always
// turns its face to the camera, so it has no facets: thin, soft at its edges, bright at the ball and
// fading to nothing behind it, in the firer's colour. It was a six-sided cone 2.7 wide (the owner:
// "bullet paths are a little too polygon-y and wide"). The quad's +Y is the flight, scaled to the
// streak's length; its width is set here, and never under a pixel and a half on screen.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform vec4 colour : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float width = 0.9; // world units across, at the ball
uniform float glow = 1.6; // over 1: the glow takes it

varying float along; // 0 at the tail, 1 at the ball

void vertex() {
	along = VERTEX.y + 0.5;
	vec3 axis = MODEL_MATRIX[1].xyz;
	vec3 mid = MODEL_MATRIX[3].xyz + axis * VERTEX.y;
	vec3 to_eye = CAMERA_POSITION_WORLD - mid;
	float dist = length(to_eye);
	vec3 side = normalize(cross(axis, to_eye));
	// a pixel and a half at least, however far the camera stands
	float px = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float w = max(width * mix(0.4, 1.0, along), px * 1.5);
	vec3 world = mid + side * VERTEX.x * w;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = normalize((VIEW_MATRIX * vec4(to_eye / max(dist, 0.001), 0.0)).xyz);
}

void fragment() {
	float across = abs(UV.x * 2.0 - 1.0);
	float edge = 1.0 - smoothstep(0.3, 1.0, across);
	float hot = smoothstep(0.85, 1.0, along) * (1.0 - across);
	ALBEDO = mix(colour.rgb, vec3(1.0, 0.95, 0.85), hot * 0.6) * glow;
	ALPHA = edge * smoothstep(0.0, 1.0, along) * colour.a;
}
