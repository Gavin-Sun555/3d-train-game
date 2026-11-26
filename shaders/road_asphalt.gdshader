shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform int portal_count = 0;
uniform vec4 portal_pos_hl[16];
uniform vec4 portal_dir_hw[16];

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
	vp.xyz *= 1.0 + (0.10 + d * 0.00035) / max(d, 0.001);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	vec2 xz = v_world.xz;
	for (int pi = 0; pi < min(portal_count, 16); pi++) {
		vec2 dp = xz - portal_pos_hl[pi].xy;
		vec2 fw = portal_dir_hw[pi].xy;
		vec2 rt = vec2(-fw.y, fw.x);
		if (abs(dot(dp, fw)) < portal_pos_hl[pi].z && abs(dot(dp, rt)) < portal_dir_hw[pi].z) {
			discard;
		}
	}
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

	// Weathered sunlit bituminous asphalt with rich dark-grey aggregate so white crosswalks & lane lines pop crisply
	vec3 base_asphalt = mix(vec3(0.066, 0.067, 0.070), vec3(0.096, 0.095, 0.094), patch_macro);
	base_asphalt *= (0.89 + 0.20 * fine_agg) * (0.93 + 0.14 * med_agg) * (0.95 + 0.10 * coarse_wear);

	// Slightly darker oil streak down lane center, slightly polished lighter aggregate in tire ruts
	float oil_center = exp(-pow((abs_u - 0.54) * 9.0, 2.0));
	base_asphalt *= (1.0 - 0.11 * oil_center + 0.07 * rut);
	base_asphalt = mix(base_asphalt, vec3(0.044, 0.044, 0.047), tar_snake * 0.72);

	// Gutter moisture/grime AO along street curbs
	float curb_ao = smoothstep(0.0, 0.11, 1.0 - abs_u);
	base_asphalt *= mix(0.68, 1.0, curb_ao);

	// Always enforce an upward (+Y) world normal at ALL distances (prevents cull_disabled back-face
	// segments from flipping to downward normals / pitch-black asphalt beyond 90m!)
	float nx = 0.0;
	float nz = 0.0;
	if (cam_d < 90.0) {
		float fade = (1.0 - smoothstep(50.0, 90.0, cam_d)) * 0.22;
		nx = (vnoise(xz * 26.0 + vec2(0.15, 0.0)) - vnoise(xz * 26.0)) * fade;
		nz = (vnoise(xz * 26.0 + vec2(0.0, 0.15)) - vnoise(xz * 26.0)) * fade;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(nx, 1.0, nz)), 0.0)).xyz);

	ALBEDO = base_asphalt;
	ROUGHNESS = clamp(0.88 + 0.07 * fine_agg - 0.12 * rut - 0.22 * tar_snake, 0.56, 0.95);
	METALLIC = 0.0;
	SPECULAR = 0.14 + 0.09 * rut;
}
