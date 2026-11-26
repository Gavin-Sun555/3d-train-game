shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Procedural Jiangnan Farmland & Paddy Field Shader (江南农田 / 水稻田 / 菜地 / 田埂 / 灌溉水渠).
// Produces crisp rectangular agricultural parcels with varied seasonal crop greens & plowed earth,
// earthen bund footpaths (田埂), fine parallel crop furrows with bump normals, and subtle wet
// irrigation ditches — anti-aliased smoothly across distance so aerial views never shimmer.

uniform float depth_push = 0.08;
uniform float depth_slope = 0.00025;

varying vec3 v_world;

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
	if (depth_push > 0.0 || depth_slope > 0.0) {
		vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float d = length(vp.xyz);
		vp.xyz *= 1.0 + (depth_push + d * depth_slope) / max(d, 0.001);
		POSITION = PROJECTION_MATRIX * vp;
	}
}

void fragment() {
	// Slight rotation (~14 deg) matching typical Jiangnan canal-aligned agricultural field orientation
	vec2 xz = v_world.xz;
	float ca = 0.9703, sa = 0.2419;
	vec2 uv = vec2(xz.x * ca - xz.y * sa, xz.x * sa + xz.y * ca);

	// Parcel grid (~42m x 22m rectangular paddy & vegetable plots)
	vec2 p_size = vec2(42.0, 22.0);
	vec2 cell = floor(uv / p_size);
	vec2 loc = fract(uv / p_size);
	float pid = hash21(cell);
	float pid2 = hash21(cell + vec2(19.3, 47.1));

	// Sub-divide ~45% of parcels into two smaller vegetable/rice strips
	if (pid2 > 0.55) {
		float sub_x = fract(loc.x * 2.0);
		pid = hash21(cell * 2.0 + vec2(floor(loc.x * 2.0), 0.0));
		loc.x = sub_x;
	}

	// Distance-based AA so furrows stay silky smooth from high aerial views
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);
	float fw = max(length(dFdx(xz)), length(dFdy(xz)));
	float aa_furrow = 1.0 - smoothstep(0.08, 0.35, fw);
	float aa_bund = 1.0 - smoothstep(0.6, 2.2, fw);

	// Authentic Jiangnan crop palette (linear PBR tones: lush rice paddy, deep emerald vegetable,
	// olive-gold ripening grain, wet dark-olive flooded paddy, freshly tilled brown loam)
	vec3 crop_col;
	bool is_wet_paddy = false;
	if (pid < 0.28) {
		crop_col = vec3(0.095, 0.195, 0.058); // Lush mid-season rice paddy green
	} else if (pid < 0.52) {
		crop_col = vec3(0.135, 0.225, 0.070); // Bright tender green shoots / vegetables
	} else if (pid < 0.72) {
		crop_col = vec3(0.165, 0.190, 0.068); // Olive-yellow ripening rice / rapeseed field
	} else if (pid < 0.86) {
		crop_col = vec3(0.068, 0.138, 0.056); // Deep flooded paddy field (subtle wet glint)
		is_wet_paddy = true;
	} else {
		crop_col = vec3(0.145, 0.118, 0.082); // Freshly tilled dark brown agricultural loam
	}

	// Macro organic variation & parallel crop furrows (alternate N-S vs E-W per plot!)
	float macro = vnoise(xz * 0.045);
	float med = vnoise(xz * 0.35);
	float f_coord = (pid2 > 0.48) ? (uv.x * 1.15) : (uv.y * 1.15);
	float furrow = sin(f_coord * 6.2831853);
	float furrow_shade = mix(1.0, 0.87 + 0.18 * (0.5 + 0.5 * furrow), aa_furrow);
	vec3 col = crop_col * (0.86 + 0.24 * macro) * (0.93 + 0.12 * med) * furrow_shade;

	// Earthen bund ridges (田埂, ~1.2m wide along parcel edges) & narrow irrigation ditch along every 3rd row
	float ex = min(loc.x * p_size.x, (1.0 - loc.x) * p_size.x);
	float ez = min(loc.y * p_size.y, (1.0 - loc.y) * p_size.y);
	float edge_d = min(ex, ez);
	bool is_ditch = (mod(cell.y, 3.0) < 0.5) && (loc.y * p_size.y < 1.8);
	float bund_mask = (1.0 - smoothstep(0.55, 1.35, edge_d)) * aa_bund;
	float ditch_mask = is_ditch ? (1.0 - smoothstep(0.7, 1.6, loc.y * p_size.y)) * aa_bund : 0.0;

	vec3 bund_col = vec3(0.18, 0.16, 0.11) * (0.88 + 0.22 * med);
	vec3 ditch_col = vec3(0.045, 0.095, 0.085);
	col = mix(col, bund_col, bund_mask * 0.85);
	col = mix(col, ditch_col, ditch_mask * 0.92);

	// Gentle upward normal perturbation along crop rows within 110m
	float nx = 0.0;
	float nz = 0.0;
	if (cam_d < 110.0 && aa_furrow > 0.05) {
		float fade = (1.0 - smoothstep(60.0, 110.0, cam_d)) * aa_furrow * 0.18 * (1.0 - bund_mask);
		float df = cos(f_coord * 6.2831853) * fade;
		if (pid2 > 0.48) { nx = df; } else { nz = df; }
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(nx, 1.0, nz)), 0.0)).xyz);

	ALBEDO = col;
	ROUGHNESS = ditch_mask > 0.35 ? 0.14 : (is_wet_paddy ? 0.46 : clamp(0.88 - 0.08 * macro, 0.78, 0.96));
	METALLIC = ditch_mask > 0.35 ? 0.15 : 0.0;
	SPECULAR = ditch_mask > 0.35 ? 0.65 : (is_wet_paddy ? 0.42 : 0.14);
}
