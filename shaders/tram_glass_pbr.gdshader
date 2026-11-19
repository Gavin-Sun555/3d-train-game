shader_type spatial;
render_mode blend_mix, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint_color : source_color = vec3(0.08, 0.15, 0.22);
uniform float base_alpha : hint_range(0.05, 0.95) = 0.42;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.2);
	vec3 sky_refl = vec3(0.58, 0.74, 0.88);
	ALBEDO = mix(tint_color, sky_refl, fres * 0.62);
	ALPHA = clamp(base_alpha + fres * 0.36, 0.10, 0.88);
	METALLIC = 0.18;
	ROUGHNESS = 0.05;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.04;
}
