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
	// Draped on real terrain, the street and what is laid on it (tram track beds, kerbs, markings) are
	// separate meshes approximating the same ground with different triangles; push the street slightly
	// away in depth so things lying on it always win (never visibly moves the street itself)
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vp.xyz);
	vp.xyz *= 1.0 + (0.12 + d * 0.0002) / max(d, 0.001);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	vec2 xz = v_world.xz;
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);

	// Multi-scale crushed basalt aggregate, bitumen tar patches & polished wheel ruts
	// Fade sub-pixel aggregate noise by screen footprint (prevents sparkle/shimmer while driving)
	float fw = max(length(dFdx(xz)), length(dFdy(xz)));
	float fine_agg = mix(0.5, hash21(floor(xz * 48.0)), 1.0 - smoothstep(0.008, 0.02, fw));
	float med_agg = vnoise(xz * 7.5);
	float coarse_wear = vnoise(xz * 0.42);
	float patch_macro = vnoise(xz * 0.075);

	// Dual wheel-rut polish tracks per lane (v_uv.x is -1..+1 across roadway)
	float abs_u = abs(v_uv.x);
	float rut1 = exp(-pow((abs_u - 0.36) * 7.5, 2.0));
	float rut2 = exp(-pow((abs_u - 0.72) * 7.5, 2.0));
	float rut = clamp(rut1 + rut2, 0.0, 1.0);

	// Subtle dark bitumen crack-seal snakes on older patches
	float crack_w = abs(vnoise(xz * 0.85 + vec2(vnoise(xz * 2.2) * 1.4)) - 0.5);
	float tar_snake = (1.0 - smoothstep(0.006, 0.020, crack_w)) * step(0.55, patch_macro);

	// Realistic weathered urban asphalt (~0.21-0.27 reflectance, rich aggregate texture)
	vec3 base_asphalt = mix(vec3(0.215, 0.213, 0.208), vec3(0.275, 0.270, 0.262), patch_macro);
	base_asphalt *= (0.88 + 0.22 * fine_agg) * (0.92 + 0.15 * med_agg) * (0.94 + 0.12 * coarse_wear);

	// Slightly darker oil streak down lane center, slightly polished lighter aggregate in tire ruts
	float oil_center = exp(-pow((abs_u - 0.54) * 9.0, 2.0));
	base_asphalt *= (1.0 - 0.12 * oil_center + 0.06 * rut);
	base_asphalt = mix(base_asphalt, vec3(0.11, 0.11, 0.115), tar_snake * 0.75);

	// Gutter moisture/grime AO along street curbs
	float curb_ao = smoothstep(0.0, 0.11, 1.0 - abs_u);
	base_asphalt *= mix(0.66, 1.0, curb_ao);

	if (cam_d < 90.0) {
		float fade = (1.0 - smoothstep(50.0, 90.0, cam_d)) * 0.22;
		float nx = (vnoise(xz * 26.0 + vec2(0.15, 0.0)) - vnoise(xz * 26.0)) * fade;
		float nz = (vnoise(xz * 26.0 + vec2(0.0, 0.15)) - vnoise(xz * 26.0)) * fade;
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(nx, 1.0, nz)), 0.0)).xyz);
	}

	ALBEDO = base_asphalt;
	ROUGHNESS = clamp(0.89 + 0.07 * fine_agg - 0.11 * rut - 0.22 * tar_snake, 0.58, 0.96);
	METALLIC = 0.0;
	SPECULAR = 0.26 + 0.12 * rut;
}
