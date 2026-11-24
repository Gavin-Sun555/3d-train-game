shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Rich city park lawn: subtle mown-turf stripes, organic moss/clover patches,
// sunlit meadow variation, and close-up grass-blade roughness micro-detail.

uniform float depth_push = 0.28;
uniform vec3 tint_mul = vec3(1.0); // < 1 / > 1 per channel: drier rough grass on vacant plots
uniform float depth_slope = 0.0014;
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
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(17.3, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Regular parks sit behind water (0.20), streets (0.12) and tram tracks (0.0) while staying in front of
	// bare ground (0.35). Lake islands override depth_push to 0.14 so they sit cleanly above water!
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vp.xyz);
	vp.xyz *= 1.0 + (depth_push + d * depth_slope) / max(d, 0.001);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	vec2 p = v_world.xz;
	for (int pi = 0; pi < portal_count; pi++) {
		vec2 dp = p - portal_pos_hl[pi].xy;
		vec2 fw = portal_dir_hw[pi].xy;
		vec2 rt = vec2(-fw.y, fw.x);
		if (abs(dot(dp, fw)) < portal_pos_hl[pi].z && abs(dot(dp, rt)) < portal_dir_hw[pi].z) {
			discard;
		}
	}
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);

	// Broad meadow / turf tone variation
	float broad = fbm(p * 0.022);
	float patch_n = fbm(p * 0.085 + vec2(11.4, -5.7));
	float fine = vnoise(p * 2.4);

	// Subtle manicured park mowing stripes (fades smoothly at extreme distance)
	float stripe_coord = (p.x * 0.866 + p.y * 0.5) * 0.42;
	float stripe = sin(stripe_coord * 3.14159265) * 0.5 + 0.5;
	float stripe_fade = 1.0 - smoothstep(140.0, 460.0, cam_d);

	vec3 lush_dark = vec3(0.145, 0.285, 0.105);
	vec3 lush_mid = vec3(0.225, 0.385, 0.145);
	vec3 sun_clover = vec3(0.325, 0.455, 0.175);

	vec3 col = mix(lush_dark, lush_mid, smoothstep(0.25, 0.78, broad));
	col = mix(col, sun_clover, smoothstep(0.50, 0.85, patch_n) * 0.48);
	// Gentle mowing stripe contrast
	col *= mix(0.955, 1.045, stripe * stripe_fade + 0.5 * (1.0 - stripe_fade));

	// Close-range blade speckle + subtle micro-normal
	if (cam_d < 95.0) {
		float blade_fade = 1.0 - smoothstep(45.0, 95.0, cam_d);
		float blade = vnoise(p * 9.5);
		col *= mix(1.0, 0.88 + 0.24 * (fine * 0.5 + blade * 0.5), blade_fade);
		float bx = vnoise(p * 9.5 + vec2(0.15, 0.0)) - blade;
		float bz = vnoise(p * 9.5 + vec2(0.0, 0.15)) - blade;
		vec3 nw = normalize(vec3(-bx * 0.45 * blade_fade, 1.0, -bz * 0.45 * blade_fade));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}

	ALBEDO = col * tint_mul;
	ROUGHNESS = clamp(0.84 + (0.5 - fine) * 0.12, 0.72, 0.94);
	METALLIC = 0.0;
	SPECULAR = 0.18;
}
