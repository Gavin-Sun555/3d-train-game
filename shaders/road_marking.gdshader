shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Road crosswalks, lane dashes & centre lines:
// Sit cleanly in front of road asphalt (0.12) while staying strictly behind ALL tram tracks (0.0),
// so road paint never covers or z-fights with grass, stone, or grooved tram trackbeds.

uniform vec3 paint_col : source_color = vec3(1.0, 1.0, 0.98);
uniform float rough_val = 0.52;

void vertex() {
	vec4 vp = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(vp.xyz);
	vp.xyz *= 1.0 + (0.07 + d * 0.00020) / max(d, 0.001);
	POSITION = PROJECTION_MATRIX * vp;
}

void fragment() {
	ALBEDO = paint_col;
	EMISSION = paint_col * 0.22;
	ROUGHNESS = rough_val;
	METALLIC = 0.0;
	SPECULAR = 0.34;
}
