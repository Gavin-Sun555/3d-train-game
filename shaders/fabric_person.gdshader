shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_tint : source_color = vec3(0.24, 0.34, 0.48);
uniform float is_skin : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;
varying vec3 v_local;
varying vec3 v_nrm;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world);
	float rim = pow(1.0 - clamp(dot(v_nrm, view_dir), 0.0, 1.0), 3.0);

	if (is_skin > 0.5) {
		// Warm natural skin with soft subsurface scattering sheen & subtle micro-pore softness
		float pore = hash21(floor((v_world.xy + v_world.zy) * 260.0));
		ALBEDO = base_tint * (0.95 + 0.03 * pore + 0.06 * rim);
		ROUGHNESS = 0.58;
		METALLIC = 0.0;
		SPECULAR = 0.26;
		BACKLIGHT = vec3(0.34, 0.13, 0.09);
	} else {
		// Diagonal woven twill cloth micro-grain + garment fold shading + soft velvet/wool rim sheen
		vec2 fuv = (v_world.xy + v_world.zy) * 165.0;
		float twill = sin((fuv.x + fuv.y) * 1.6) * 0.5 + 0.5;
		float weave = hash21(floor(fuv));
		float fold = 0.91 + 0.10 * sin(v_local.x * 24.0 + v_local.y * 14.0) + 0.04 * cos(v_local.z * 28.0);
		float joint_ao = smoothstep(-0.28, 0.18, v_local.y) * 0.12 + 0.88;
		ALBEDO = base_tint * (0.93 + 0.06 * weave + 0.04 * twill) * fold * joint_ao + base_tint * rim * 0.12;
		ROUGHNESS = clamp(0.82 + 0.08 * (1.0 - twill), 0.74, 0.95);
		METALLIC = 0.0;
		SPECULAR = 0.18;
	}
}
