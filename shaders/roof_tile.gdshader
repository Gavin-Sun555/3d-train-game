shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Procedural Jiangnan / Contemporary Chinese pitched roof tile shader (陶瓦 / 黛瓦 / 彩钢瓦).
// Driven by vertex color (sampled/verified from Google Earth satellite imagery) with crisp
// overlapping tile courses, flute corrugations, weathering variation, and bump normal mapping.

varying vec3 v_world_pos;
varying vec3 v_world_nrm;
varying vec4 v_col;

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
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_col = COLOR;
}

void fragment() {
	// Convert sRGB vertex color from SurfaceTool into true linear PBR albedo
	// (prevents slate grey & terracotta clay roofs from washing out to pale grey/peach!)
	vec3 base_srgb = clamp(v_col.rgb, vec3(0.0), vec3(1.0));
	vec3 base = pow(base_srgb, vec3(2.2));
	vec3 n_w = normalize(v_world_nrm);
	// Ensure roof normal always faces upward even for cull_disabled back faces
	if (n_w.y < 0.0) {
		n_w = -n_w;
	}
	// Build slope-aligned local coordinates (u across slope / horizontal, v running down the slope)
	vec3 h_dir = normalize(vec3(n_w.x, 0.0, n_w.z) + vec3(1e-5, 0.0, 0.0));
	vec3 across = vec3(-h_dir.z, 0.0, h_dir.x);
	vec3 down_slope = normalize(cross(across, n_w));
	float u = dot(v_world_pos, across);
	float v = dot(v_world_pos, down_slope);

	// Distance-based AA fade so tiles stay crisp near camera and silky smooth from afar
	float cam_d = distance(v_world_pos, CAMERA_POSITION_WORLD);
	float fw = max(length(dFdx(v_world_pos.xz)), length(dFdy(v_world_pos.xz)));
	float aa = 1.0 - smoothstep(0.05, 0.22, fw);

	// Detect steel-blue industrial metal roof in sRGB space before gamma decode
	bool is_metal = (base_srgb.b > base_srgb.r + 0.12 && base_srgb.b > 0.36);

	// Overlapping roof tile courses (0.42m pitch down slope, 0.28m pantile flute across)
	float course_pitch = is_metal ? 2.4 : 0.42;
	float flute_pitch = is_metal ? 0.24 : 0.28;
	float cv = fract(v / course_pitch);
	float cu = fract(u / flute_pitch);
	float tile_id = hash21(vec2(floor(u / flute_pitch), floor(v / course_pitch)));

	// Smooth barrel-tile wave across flute + crisp stepped shadow lip at overlap of each course
	float flute_wave = sin(cu * 6.2831853);
	float course_lip = smoothstep(0.0, 0.18, cv) * (1.0 - 0.18 * smoothstep(0.84, 1.0, cv));
	float macro_w = vnoise(v_world_pos.xz * 0.18);
	float med_w = vnoise(v_world_pos.xz * 1.15);

	vec3 col = base;
	if (is_metal) {
		float rib = 0.86 + 0.18 * flute_wave;
		float seam = mix(0.76, 1.0, smoothstep(0.0, 0.045, cv));
		col *= mix(1.0, rib * seam, aa) * (0.90 + 0.16 * macro_w);
	} else {
		// Authentic Jiaxing terracotta clay / Jiangnan dark-slate pantiles with rich per-tile variation
		float tile_shade = mix(1.0, (0.80 + 0.24 * (0.5 + 0.5 * flute_wave)) * mix(0.58, 1.06, course_lip) * (0.88 + 0.22 * tile_id), aa);
		// Gentle urban weathering & rain streaking down the slope
		float streak = 0.88 + 0.20 * vnoise(vec2(u * 0.52, v * 0.11));
		col *= tile_shade * streak * (0.88 + 0.20 * macro_w) * (0.94 + 0.12 * med_w);
	}

	// Crisp bump perturbation along tile flutes & course steps within 160m
	vec3 pert_w = n_w;
	if (cam_d < 160.0 && aa > 0.04) {
		float fade = (1.0 - smoothstep(95.0, 160.0, cam_d)) * aa;
		float du = cos(cu * 6.2831853) * (is_metal ? 0.24 : 0.38) * fade;
		float dv = (cv < 0.18 ? -0.48 : 0.08) * (is_metal ? 0.35 : 1.0) * fade;
		pert_w = normalize(n_w + across * du + down_slope * dv);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(pert_w, 0.0)).xyz);

	ALBEDO = col;
	ROUGHNESS = is_metal ? (0.42 + 0.12 * macro_w) : clamp(0.76 + 0.14 * (1.0 - macro_w) - 0.06 * tile_id, 0.64, 0.92);
	METALLIC = is_metal ? 0.44 : 0.02;
	SPECULAR = is_metal ? 0.54 : 0.28;
}
