shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Elliott Bay / Lake Union water: layered moving wave normals, Fresnel sky reflection, sun glint,
// darker deep-water tint further from shore (approximated by large-scale noise), fades detail with distance.

uniform vec3 shallow_col : source_color = vec3(0.13, 0.27, 0.32);
uniform vec3 deep_col : source_color = vec3(0.04, 0.12, 0.18);
uniform vec3 sky_col : source_color = vec3(0.62, 0.72, 0.82);
uniform float night_factor : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float waves(vec2 p, float t) {
	float h = 0.0;
	h += sin(dot(p, vec2(0.08, 0.05)) + t * 0.9) * 0.5;
	h += sin(dot(p, vec2(-0.05, 0.11)) + t * 1.3) * 0.35;
	h += (vnoise(p * 0.35 + vec2(t * 0.25, t * 0.18)) - 0.5) * 0.9;
	h += (vnoise(p * 1.1 - vec2(t * 0.4, t * 0.1)) - 0.5) * 0.35;
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz;
	float t = TIME;
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);
	float fw = max(length(dFdx(p)), length(dFdy(p)));
	float detail = 1.0 - smoothstep(0.15, 0.9, fw);
	float e = 0.35;
	float h0 = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t);
	vec3 n_world = normalize(vec3((h0 - hx) * 0.28 * detail, 1.0, (h0 - hz) * 0.28 * detail));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	vec3 view = normalize(CAMERA_POSITION_WORLD - v_world);
	float fres = pow(1.0 - clamp(dot(n_world, view), 0.0, 1.0), 4.0);
	float deep = smoothstep(0.35, 0.75, vnoise(p * 0.004));
	vec3 water = mix(shallow_col, deep_col, deep * 0.8 + 0.2);
	vec3 sky = mix(sky_col, vec3(0.03, 0.04, 0.07), night_factor);
	ALBEDO = mix(water, sky * 0.85, clamp(0.08 + fres * 0.75, 0.0, 0.85));
	ROUGHNESS = mix(0.06, 0.2, 1.0 - detail);
	METALLIC = 0.1;
	SPECULAR = 0.9;
}
