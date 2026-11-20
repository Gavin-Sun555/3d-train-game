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
	float ndv = clamp(dot(normalize(v_nrm), view_dir), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 2.8);

	if (is_skin > 0.5) {
		// Warm natural skin with soft peach subsurface wrap and gentle cheek warmth (no texture swimming!)
		float micro = hash21(floor((v_local.xy + v_local.zy) * 280.0));
		float cheek_warm = exp(-pow((v_local.y + 0.01) * 22.0, 2.0)) * smoothstep(0.02, 0.06, abs(v_local.x)) * smoothstep(0.0, -0.05, v_local.z);
		vec3 warm_tint = mix(base_tint, base_tint * vec3(1.06, 0.93, 0.90), cheek_warm * 0.28);
		ALBEDO = warm_tint * (0.97 + 0.02 * micro + 0.045 * rim);
		ROUGHNESS = 0.62;
		METALLIC = 0.0;
		SPECULAR = 0.22;
		BACKLIGHT = vec3(0.38, 0.16, 0.11);
	} else {
		// Fine woven twill cloth in local coordinates (zero shimmering during walking) + soft garment fold shading
		vec2 fuv = (v_local.xy + v_local.zy) * 190.0;
		float twill = sin((fuv.x + fuv.y) * 1.8) * 0.5 + 0.5;
		float weave = hash21(floor(fuv));
		float fold = 0.94 + 0.055 * sin(v_local.x * 20.0 + v_local.y * 12.0) + 0.025 * cos(v_local.z * 24.0);
		float joint_ao = smoothstep(-0.30, 0.20, v_local.y) * 0.10 + 0.90;
		ALBEDO = base_tint * (0.95 + 0.04 * weave + 0.03 * twill) * fold * joint_ao + base_tint * rim * 0.10;
		ROUGHNESS = clamp(0.84 + 0.06 * (1.0 - twill), 0.78, 0.95);
		METALLIC = 0.0;
		SPECULAR = 0.15;
	}
}
