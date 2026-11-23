shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform int portal_count = 0;
uniform vec4 portal_pos_hl[16];
uniform vec4 portal_dir_hw[16];

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.07;
		a *= 0.5;
	}
	return v;
}

float sidewalk_height(vec2 xz) {
	// 1.5m poured architectural concrete slabs + 0.75m saw-cut sub-grooves
	vec2 main_uv = fract(xz / 1.5);
	vec2 sub_uv = fract(xz / 0.75);
	float gx = smoothstep(0.0, 0.026, main_uv.x) * smoothstep(0.0, 0.026, 1.0 - main_uv.x);
	float gy = smoothstep(0.0, 0.026, main_uv.y) * smoothstep(0.0, 0.026, 1.0 - main_uv.y);
	float main_groove = gx * gy;

	float sx = smoothstep(0.0, 0.016, sub_uv.x) * smoothstep(0.0, 0.016, 1.0 - sub_uv.x);
	float sy = smoothstep(0.0, 0.016, sub_uv.y) * smoothstep(0.0, 0.016, 1.0 - sub_uv.y);
	float sub_groove = mix(0.65, 1.0, sx * sy);

	// Brushed concrete micro-grain + aggregate pitting
	float brush = sin(xz.x * 165.0 + vnoise(xz * 8.0) * 3.0) * 0.04;
	float agg = (vnoise(xz * 28.0) - 0.5) * 0.18;
	return main_groove * sub_groove + brush + agg;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// The bare ground (terrain): pushed further back in depth than the streets, so streets, lawns and plazas
	// draped onto it never get pierced by its own (differently triangulated) slopes
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vp.xyz);
	vp.xyz *= 1.0 + (0.42 + d * 0.0022) / max(d, 0.001);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	vec2 xz = v_world.xz;
	for (int pi = 0; pi < portal_count; pi++) {
		vec2 dp = xz - portal_pos_hl[pi].xy;
		vec2 fw = portal_dir_hw[pi].xy;
		vec2 rt = vec2(-fw.y, fw.x);
		if (abs(dot(dp, fw)) < portal_pos_hl[pi].z && abs(dot(dp, rt)) < portal_dir_hw[pi].z) {
			discard;
		}
	}
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);

	vec2 slab_id = floor(xz / 1.5);
	vec2 sub_id = floor(xz / 0.75);
	vec2 main_uv = fract(xz / 1.5);
	vec2 sub_uv = fract(xz / 0.75);

	float gx = smoothstep(0.0, 0.024, main_uv.x) * smoothstep(0.0, 0.024, 1.0 - main_uv.x);
	float gy = smoothstep(0.0, 0.024, main_uv.y) * smoothstep(0.0, 0.024, 1.0 - main_uv.y);
	float main_joint = gx * gy;

	float sx = smoothstep(0.0, 0.014, sub_uv.x) * smoothstep(0.0, 0.014, 1.0 - sub_uv.x);
	float sy = smoothstep(0.0, 0.014, sub_uv.y) * smoothstep(0.0, 0.014, 1.0 - sub_uv.y);
	float sub_joint = sx * sy;

	float slab_tone = hash21(slab_id);
	float tile_tone = hash21(sub_id * 1.37);
	float macro_dirty = fbm(xz * 0.085);
	float med_speckle = vnoise(xz * 11.5);
	float fw = max(length(dFdx(xz)), length(dFdy(xz)));
	float aa_fine = 1.0 - smoothstep(0.008, 0.022, fw);
	float aa_joint = 1.0 - smoothstep(0.03, 0.09, fw);
	float fine_sand = mix(0.5, hash21(floor(xz * 42.0)), aa_fine);
	main_joint = mix(0.9, main_joint, 1.0 - smoothstep(0.06, 0.2, fw));
	sub_joint = mix(0.9, sub_joint, aa_joint);

	// Realistic Cities: Skylines II medium-warm urban concrete (never blown-out white!)
	vec3 warm_conc = vec3(0.42, 0.405, 0.382);
	vec3 cool_conc = vec3(0.375, 0.372, 0.362);
	vec3 col = mix(cool_conc, warm_conc, slab_tone * 0.65 + tile_tone * 0.35);

	// Natural urban foot-traffic darkening, rain stains & aggregate speckle
	col *= (0.86 + 0.22 * macro_dirty);
	col *= (0.93 + 0.13 * med_speckle) * (0.95 + 0.10 * fine_sand);

	// Subtle cast-iron manhole cover at occasional slab intersections
	vec2 mh_cell = floor(xz / 18.0);
	vec2 mh_local = xz - (mh_cell + vec2(0.5)) * 18.0;
	float mh_seed = hash21(mh_cell + vec2(19.3, 7.1));
	float mh_r = length(mh_local);
	float rough = clamp(0.84 + 0.10 * (1.0 - macro_dirty) - 0.05 * slab_tone, 0.72, 0.95);
	float metal = 0.0;

	if (mh_seed > 0.72 && mh_r < 0.44) {
		float waffle = mix(0.42, step(0.35, fract(mh_local.x * 14.0)) * step(0.35, fract(mh_local.y * 14.0)), aa_joint);
		float rim = smoothstep(0.37, 0.42, mh_r);
		col = mix(vec3(0.16, 0.155, 0.15) * (0.82 + 0.25 * waffle), vec3(0.22, 0.21, 0.20), rim);
		rough = 0.52;
		metal = 0.62;
	} else {
		// Dark elastomeric joint sealant in expansion seams + subtle bevel highlight
		col *= mix(0.48, 1.0, main_joint);
		col *= mix(0.74, 1.0, sub_joint);
	}

	// Real bump-perturbed normal within 110m for crisp raking sunlight across concrete slabs!
	if (cam_d < 110.0) {
		float fade = (1.0 - smoothstep(65.0, 110.0, cam_d)) * aa_fine;
		float eps = 0.022;
		float h0 = sidewalk_height(xz);
		float hx = sidewalk_height(xz + vec2(eps, 0.0));
		float hz = sidewalk_height(xz + vec2(0.0, eps));
		vec3 world_n = normalize(vec3((h0 - hx) * 0.32 * fade, 1.0, (h0 - hz) * 0.32 * fade));
		NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.22;
}
