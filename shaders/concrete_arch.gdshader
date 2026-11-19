shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

varying vec3 v_world;
varying vec3 v_nrm;

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
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Tri-planar world UV for precast / board-formed architectural concrete!
	vec2 uv = abs(v_nrm.y) > 0.65 ? v_world.xz : vec2(v_world.x + v_world.z, v_world.y);

	// 2.4m x 1.2m precast formwork panel joints + tie-rod pinholes
	vec2 panel_uv = fract(uv / vec2(2.4, 1.2));
	vec2 panel_id = floor(uv / vec2(2.4, 1.2));
	float seam_x = smoothstep(0.0, 0.016, panel_uv.x) * smoothstep(0.0, 0.016, 1.0 - panel_uv.x);
	float seam_y = smoothstep(0.0, 0.024, panel_uv.y) * smoothstep(0.0, 0.024, 1.0 - panel_uv.y);
	float seam = seam_x * seam_y;

	float per_panel = hash21(panel_id);
	float streak = vnoise(vec2(uv.x * 2.8, uv.y * 0.45));
	float fine = vnoise(uv * 22.0);
	float ground_damp = smoothstep(0.0, 2.2, v_world.y);

	vec3 conc = mix(vec3(0.42, 0.415, 0.40), vec3(0.49, 0.485, 0.47), per_panel);
	conc *= (0.90 + 0.16 * streak) * (0.94 + 0.12 * fine);
	conc *= mix(0.76, 1.0, ground_damp);
	conc *= mix(0.68, 1.0, seam);

	ALBEDO = conc;
	ROUGHNESS = clamp(0.84 + 0.08 * fine - 0.06 * streak, 0.72, 0.94);
	METALLIC = 0.0;
	SPECULAR = 0.22;
}
