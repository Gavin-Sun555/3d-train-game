shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float night_factor : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_world_nrm;

float hash31(vec3 p) {
	p = fract(p * vec3(127.1, 311.7, 74.7));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Geodesic pentagon-hex-triangle steel diagrid lattice on sphere surface!
	vec3 dir = normalize(v_local);
	float phi = atan(dir.z, dir.x);
	float theta = acos(clamp(dir.y, -1.0, 1.0));

	// Tri-directional geodesic grid (Catalan-inspired structural lattice!)
	vec2 g_uv = vec2(phi * 5.72958, theta * 11.45916); // ~36 segments around equator
	float l1 = abs(fract(g_uv.y) - 0.5);
	float l2 = abs(fract(g_uv.x * 0.866 + g_uv.y * 0.5) - 0.5);
	float l3 = abs(fract(g_uv.x * 0.866 - g_uv.y * 0.5) - 0.5);

	// Primary white Catalan steel arches + slimmer secondary black glazing mullions
	float primary_a = abs(fract(g_uv.x * 0.28 + g_uv.y * 0.16) - 0.5);
	float primary_b = abs(fract(g_uv.x * 0.28 - g_uv.y * 0.16) - 0.5);
	float white_steel = 1.0 - smoothstep(0.028, 0.046, min(primary_a, primary_b));
	float sub_mullion = 1.0 - smoothstep(0.026, 0.048, min(min(l1, l2), l3));

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world);
	float ndotv = clamp(abs(dot(v_world_nrm, view_dir)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 3.5);

	// Individual glass facet subtle tilt shimmer!
	vec3 cell_id = floor(vec3(g_uv.x * 1.7, g_uv.y * 1.7, 0.0));
	float facet_var = hash31(cell_id);

	if (white_steel > 0.5) {
		// Iconic painted white structural Catalan steel ribs
		ALBEDO = vec3(0.92, 0.94, 0.95);
		ROUGHNESS = 0.30;
		METALLIC = 0.25;
		SPECULAR = 0.65;
		ALPHA = 1.0;
		EMISSION = vec3(0.0);
	} else if (sub_mullion > 0.5) {
		// Dark anodized aluminum glazing spider frames
		ALBEDO = vec3(0.18, 0.21, 0.23);
		ROUGHNESS = 0.36;
		METALLIC = 0.65;
		SPECULAR = 0.60;
		ALPHA = 0.96;
		EMISSION = vec3(0.0);
	} else {
		// Low-iron architectural conservatory double-glazing
		vec3 glass_tint = mix(vec3(0.16, 0.34, 0.36), vec3(0.46, 0.64, 0.74), fresnel * 0.75 + facet_var * 0.12);
		ALBEDO = glass_tint;
		ROUGHNESS = 0.06 + 0.03 * facet_var;
		METALLIC = 0.38;
		SPECULAR = 0.94;
		CLEARCOAT = 0.92;
		CLEARCOAT_ROUGHNESS = 0.04;
		ALPHA = clamp(0.32 + fresnel * 0.46, 0.30, 0.80);
		// Warm golden-green botanical conservatory glow at dusk/night!
		EMISSION = vec3(0.42, 0.52, 0.28) * night_factor * 0.55;
	}
}
