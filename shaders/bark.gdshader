shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

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
	float ang = atan(v_nrm.x, v_nrm.z);
	// Vertical fissured bark ridges + subtle moss near ground
	float fissure = vnoise(vec2(ang * 5.5, v_world.y * 2.8));
	float fine = vnoise(vec2(ang * 16.0, v_world.y * 9.0));
	float moss = smoothstep(1.3, 0.1, v_world.y) * step(0.45, fissure);

	vec3 dark_crevice = vec3(0.14, 0.105, 0.08);
	vec3 grey_brown_ridge = vec3(0.31, 0.255, 0.205);
	vec3 bark = mix(dark_crevice, grey_brown_ridge, smoothstep(0.25, 0.78, fissure * 0.7 + fine * 0.3));
	bark = mix(bark, vec3(0.20, 0.28, 0.15), moss * 0.45);

	ALBEDO = bark;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	SPECULAR = 0.14;
}
