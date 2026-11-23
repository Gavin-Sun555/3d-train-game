shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Paved plazas, squares, parking lots & brick plazas:
// Pushed behind water (0.20), islands (0.14), roads (0.12), road markings (0.09) and ALL tram tracks (0.0),
// while staying cleanly in front of park lawns (0.28) and bare ground (0.35).

uniform vec3 base_col : source_color = vec3(0.39, 0.38, 0.36);
uniform float rough_val = 0.86;
uniform float depth_push = 0.22;
uniform float depth_slope = 0.0010;
uniform int portal_count = 0;
uniform vec4 portal_pos_hl[16];
uniform vec4 portal_dir_hw[16];

varying vec3 v_world;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vp.xyz);
	vp.xyz *= 1.0 + (depth_push + d * depth_slope) / max(d, 0.001);
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
	float fw = max(length(dFdx(xz)), length(dFdy(xz)));
	float aa = 1.0 - smoothstep(0.04, 0.14, fw);
	vec2 cell = floor(xz / 1.2);
	vec2 uv = fract(xz / 1.2);
	float tone = hash21(cell);
	float gx = smoothstep(0.0, 0.03, uv.x) * smoothstep(0.0, 0.03, 1.0 - uv.x);
	float gy = smoothstep(0.0, 0.03, uv.y) * smoothstep(0.0, 0.03, 1.0 - uv.y);
	float joint = mix(0.88, 1.0, mix(1.0, gx * gy, aa));
	ALBEDO = base_col * (0.93 + 0.14 * tone) * joint;
	ROUGHNESS = rough_val;
	METALLIC = 0.0;
	SPECULAR = 0.22;
}
