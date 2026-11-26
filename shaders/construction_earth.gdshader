shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Procedural rugged compacted earth, gravel & tire-track shader for active Jiaxing construction sites (在建工地泥土/碎石垫层)

varying vec3 v_world_pos;
varying vec4 v_col;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.53);
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

float fbm(vec2 p) {
	return vnoise(p) * 0.58 + vnoise(p * 2.3 + vec2(13.1, 7.4)) * 0.28 + vnoise(p * 5.7 + vec2(4.2, 19.8)) * 0.14;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_col = COLOR;
}

void fragment() {
	vec2 wp = v_world_pos.xz;
	float cam_dist = length(v_world_pos - CAMERA_POSITION_WORLD);
	float aa = 1.0 - smoothstep(60.0, 260.0, cam_dist);

	vec3 base_c = pow(clamp(v_col.rgb, vec3(0.0), vec3(1.0)), vec3(1.85));
	float macro = fbm(wp * 0.055);
	float mid = fbm(wp * 0.28);
	float gravel = vnoise(wp * 2.6);

	// Darker damp excavated clay patches & paler dry gravel/dust streaks
	vec3 damp_soil = base_c * vec3(0.68, 0.64, 0.58);
	vec3 dry_gravel = mix(base_c * 1.15, vec3(0.56, 0.54, 0.50), 0.35);
	vec3 col = mix(damp_soil, dry_gravel, smoothstep(0.28, 0.74, macro));
	col *= (0.86 + 0.22 * mid) * (0.93 + 0.14 * mix(0.5, gravel, aa));

	// Subtle tire-track & grading ruts across the earth pad
	float rut = sin(wp.x * 1.15 + macro * 3.0) * 0.5 + 0.5;
	col *= mix(1.0, 0.92 + 0.12 * rut, aa * 0.45);

	ALBEDO = col;
	ROUGHNESS = clamp(0.88 + 0.10 * (1.0 - macro), 0.78, 0.98);
	METALLIC = 0.0;
	SPECULAR = 0.12;
}
