shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;

// A fountain jet column (cylinder, UV.y = 0 at the nozzle .. 1 at the top): streaks rising through it,
// thinning and breaking up toward the top where the water falls back as spray.

uniform vec3 water_col : source_color = vec3(0.90, 0.95, 1.0);
uniform float speed = 2.2;

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

void fragment() {
	float y = 1.0 - UV.y; // Godot cylinder UV.y runs top -> bottom
	float streak = vnoise(vec2(UV.x * 24.0, y * 6.0 - TIME * speed * 3.0));
	float breakup = vnoise(vec2(UV.x * 9.0 + 3.0, y * 14.0 - TIME * speed * 5.0));
	float body = smoothstep(1.0, 0.55, y) * (0.45 + 0.55 * streak);
	float spray = smoothstep(0.45, 1.0, y) * breakup;
	float a = clamp(body * 0.55 + spray * 0.45 - smoothstep(0.85, 1.0, y) * 0.6, 0.0, 0.7);
	ALBEDO = water_col;
	EMISSION = water_col * 0.08;
	ALPHA = a;
	ROUGHNESS = 0.15;
	SPECULAR = 0.7;
}
