shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.90, 0.92, 0.94);
uniform float metallic_val : hint_range(0.0, 1.0) = 0.25;
uniform float rough_val : hint_range(0.04, 1.0) = 0.24;
uniform float clearcoat_val : hint_range(0.0, 1.0) = 0.85;
uniform float seam_strength : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_local;
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
	v_local = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	vec3 col = base_color;

	// Fine metallic flake / brushed paint micro-variation
	float flake = vnoise(v_local.zy * 28.0 + v_local.xy * 19.0);
	float grime = vnoise(v_local.zy * 4.5 + vec2(1.3, 7.1));
	col *= 0.965 + 0.055 * flake;

	// Subtle vertical railcar body panel seams & lower-skirt road dust weathering
	float z_mod = abs(fract(v_local.z * 0.62) - 0.5);
	float seam = smoothstep(0.012, 0.0, z_mod) * seam_strength * step(0.4, abs(v_nrm.x));
	col *= (1.0 - seam * 0.42);

	// Subtle brushed aluminum sheen on rooftop surfaces
	float is_roof = smoothstep(0.6, 0.95, v_nrm.y);
	float brush = vnoise(vec2(v_local.x * 48.0, v_local.z * 6.0));
	col = mix(col, col * (0.94 + 0.10 * brush), is_roof);

	// Very subtle urban grime near lower skirt
	float low_mask = smoothstep(0.95, 0.42, v_local.y) * (1.0 - is_roof);
	col = mix(col, col * vec3(0.84, 0.82, 0.79), low_mask * grime * 0.35);

	ALBEDO = col;
	METALLIC = mix(metallic_val, max(metallic_val, 0.45), is_roof);
	ROUGHNESS = clamp(rough_val + seam * 0.25 + low_mask * 0.12 - (1.0 - flake) * 0.03, 0.08, 0.92);
	CLEARCOAT = clearcoat_val * (1.0 - low_mask * 0.4);
	CLEARCOAT_ROUGHNESS = 0.09;
}
