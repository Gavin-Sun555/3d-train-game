shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.14, 0.16, 0.19);
uniform float is_wood : hint_range(0.0, 1.0) = 0.0;
uniform float rough_val : hint_range(0.1, 1.0) = 0.52;
uniform float metal_val : hint_range(0.0, 1.0) = 0.18;

varying vec3 v_local;

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
}

void fragment() {
	vec3 col = base_color;
	if (is_wood > 0.5) {
		// Satin varnished walnut/mahogany wood grain for vintage tram cabs!
		float grain = sin(v_local.x * 65.0 + vnoise(v_local.xz * 18.0) * 6.0) * 0.5 + 0.5;
		float fine = vnoise(v_local.xz * 75.0);
		col = mix(base_color * 0.78, base_color * 1.18, grain * 0.72 + fine * 0.28);
		ROUGHNESS = 0.28 + (1.0 - grain) * 0.12;
		CLEARCOAT = 0.65;
		CLEARCOAT_ROUGHNESS = 0.14;
		METALLIC = 0.04;
	} else {
		// Soft-touch matte dashboard leatherette / anti-glare polymer micro-pebble grain!
		float pebble = vnoise(v_local.xz * 140.0 + v_local.xy * 95.0);
		float macro = vnoise(v_local.xz * 16.0);
		col *= 0.90 + 0.16 * pebble + 0.05 * macro;
		ROUGHNESS = clamp(rough_val + (pebble - 0.5) * 0.14, 0.22, 0.88);
		METALLIC = metal_val;
		CLEARCOAT = 0.10;
	}
	ALBEDO = col;
}
