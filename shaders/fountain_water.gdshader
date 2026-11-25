shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

// Ornamental fountain / reflecting-pool water: animated interfering ripples, sky reflection with fresnel,
// darker clear water toward the centre over a tiled basin floor, and foam rings where jets land.

uniform vec3 deep_col : source_color = vec3(0.07, 0.22, 0.27);
uniform vec3 shallow_col : source_color = vec3(0.20, 0.42, 0.44);
uniform vec3 sky_col : source_color = vec3(0.62, 0.74, 0.86);
uniform float radius = 15.0;
uniform float jet_ring = -1.0; // radius where the ring of jets lands (< 0: none)
uniform float jet_count = 12.0;
uniform float ripple_speed = 1.0;

varying vec3 v_world;
varying vec2 v_center; // the pool mesh sits at its basin centre

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
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
	h += sin(dot(p, vec2(0.83, 0.55)) * 2.1 + t * 1.7) * 0.5;
	h += sin(dot(p, vec2(-0.42, 0.91)) * 3.3 - t * 2.3) * 0.3;
	h += (vnoise(p * 1.6 + vec2(t * 0.35, -t * 0.27)) - 0.5) * 0.8;
	return h;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xz;
}

void fragment() {
	float t = TIME * ripple_speed;
	vec2 p = v_world.xz;
	vec2 rel = p - v_center;
	float r = length(rel);
	// circular ripples spreading from the jets
	float ring_wave = 0.0;
	if (jet_ring > 0.0) {
		float a = atan(rel.y, rel.x);
		float seg = 6.28318 / jet_count;
		float ac = (floor(a / seg) + 0.5) * seg;
		vec2 jp = vec2(cos(ac), sin(ac)) * jet_ring;
		float dj = length(rel - jp);
		ring_wave = sin(dj * 9.0 - t * 7.0) * exp(-dj * 1.1);
	}
	float centre_wave = sin(r * 6.0 - t * 4.0) * exp(-r * 0.25) * 0.4;
	float e = 0.06;
	float h0 = waves(p, t) + ring_wave + centre_wave;
	float hx = waves(p + vec2(e, 0.0), t) - h0 + ring_wave * 0.0;
	float hz = waves(p + vec2(0.0, e), t) - h0;
	vec3 n_w = normalize(vec3(-hx * 0.9, 1.0, -hz * 0.9) + vec3(rel.x, 0.0, rel.y) * ring_wave * 0.02);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_w, 0.0)).xyz);

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world);
	float fres = pow(1.0 - clamp(dot(n_w, view_dir), 0.0, 1.0), 4.0);
	float depth_f = clamp(r / max(radius, 0.1), 0.0, 1.0);
	vec3 water = mix(deep_col, shallow_col, depth_f * 0.6 + 0.2 * vnoise(p * 0.7));
	// faint basin tiles seen through the water
	vec2 tile = abs(fract(p * 0.5) - 0.5);
	float grout = smoothstep(0.47, 0.5, max(tile.x, tile.y));
	water = mix(water, water * 0.82, grout * (1.0 - fres) * 0.6);
	vec3 col = mix(water, sky_col, clamp(0.18 + fres * 0.75, 0.0, 0.9));
	// foam where the jets land
	if (jet_ring > 0.0) {
		float a2 = atan(rel.y, rel.x);
		float seg2 = 6.28318 / jet_count;
		float ac2 = (floor(a2 / seg2) + 0.5) * seg2;
		float dj2 = length(rel - vec2(cos(ac2), sin(ac2)) * jet_ring);
		float foam = (1.0 - smoothstep(0.15, 0.9, dj2)) * (0.65 + 0.35 * vnoise(p * 9.0 + t * 3.0));
		col = mix(col, vec3(0.93, 0.96, 0.98), foam * 0.85);
	}
	ALBEDO = col;
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
