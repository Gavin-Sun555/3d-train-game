shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

varying vec3 v_world;
varying vec2 v_uv;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
}

void fragment() {
	vec2 xz = v_world.xz;
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);

	float blade = hash21(floor(xz * 55.0));
	float tuft = vnoise(xz * 9.5);
	float clump = vnoise(xz * 2.2);
	float lush = vnoise(xz * 0.22);

	float in_gauge = step(abs(v_uv.x), 0.68);
	vec3 deep_clover = vec3(0.17, 0.36, 0.13);
	vec3 sunlit_lawn = vec3(0.27, 0.46, 0.17);
	vec3 dry_tip = vec3(0.36, 0.44, 0.20);

	vec3 turf = mix(deep_clover, sunlit_lawn, lush) * (0.95 + 0.07 * in_gauge);
	turf = mix(turf, dry_tip, smoothstep(0.72, 0.96, clump) * 0.35);
	turf *= (0.82 + 0.30 * blade) * (0.88 + 0.22 * tuft);

	// Rich dark topsoil & ballast shadow under rails (+/- 0.7175m) and curbs
	float d_rail = abs(abs(v_uv.x) - 0.7175);
	float rail_ao = smoothstep(0.03, 0.22, d_rail);
	float edge_ao = smoothstep(0.0, 0.16, 1.36 - abs(v_uv.x));
	turf = mix(vec3(0.15, 0.12, 0.09), turf, rail_ao * edge_ao);

	if (cam_d < 85.0) {
		float fade = (1.0 - smoothstep(45.0, 85.0, cam_d)) * 0.35;
		float nx = (vnoise(xz * 32.0 + vec2(0.1, 0.0)) - tuft) * fade;
		float nz = (vnoise(xz * 32.0 + vec2(0.0, 0.1)) - tuft) * fade;
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(nx, 1.0, nz)), 0.0)).xyz);
	}

	ALBEDO = turf;
	ROUGHNESS = 0.88;
	METALLIC = 0.0;
	SPECULAR = 0.16;
	BACKLIGHT = vec3(0.14, 0.24, 0.06);
}
