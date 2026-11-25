shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

varying vec3 v_world;
varying vec3 v_local_nrm;
varying vec4 v_col;
varying vec2 v_uv;
uniform bool leaf_cards = false; // on only for the sculpted crowns, whose UVs mark their leaf cards

float hash31(vec3 p) {
	p = fract(p * vec3(127.1, 311.7, 74.7));
	p += dot(p, p.yzx + 19.19);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

void vertex() {
	// Subtle organic leaf-cluster displacement + gentle wind rustle!
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float disp = noise3(VERTEX * 3.4 + world_origin * 0.5) - 0.5;
	VERTEX += NORMAL * (disp * 0.26);
	float sway = sin(TIME * 1.45 + world_origin.x * 0.25 + world_origin.z * 0.21 + VERTEX.y * 0.8) * 0.045 * clamp(VERTEX.y + 1.0, 0.0, 2.0);
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;

	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_local_nrm = NORMAL;
	v_col = COLOR;
	v_uv = UV;
}

void fragment() {
	float cam_d = distance(v_world, CAMERA_POSITION_WORLD);
	// Leaf cards (UV >= 0): a ragged cluster of leaves cut out of the quad; crown clumps carry UV = -1
	if (leaf_cards && v_uv.x >= 0.0) {
		vec2 c = v_uv - 0.5;
		float d = length(c) * 2.0;
		float lobes = noise3(vec3(v_uv * 5.5, v_col.r * 7.0));
		float leaves = noise3(vec3(v_uv * 15.0, 3.7));
		float mask = (1.0 - d) + (lobes - 0.5) * 0.9 + (leaves - 0.5) * 0.45;
		if (mask < 0.12) {
			discard;
		}
	}

	// Multi-scale 3D leaf clusters so tree crowns never look like smooth plastic balls!
	float big_clump = noise3(v_world * 2.4);
	float med_leaf = noise3(v_world * 8.5);
	float fine_leaf = noise3(v_world * 24.0);

	// Deep shaded inner-bough pockets vs bright sunlit outer leaf tips
	float sun_tip = smoothstep(0.28, 0.78, big_clump * 0.55 + med_leaf * 0.45);
	float canopy_ao = mix(0.52, 1.08, clamp(v_local_nrm.y * 0.5 + 0.55, 0.0, 1.0));

	vec3 inner_shade = v_col.rgb * vec3(0.52, 0.64, 0.48);
	vec3 outer_sun = v_col.rgb * vec3(1.18, 1.15, 0.92);
	vec3 leaf_col = mix(inner_shade, outer_sun, sun_tip) * canopy_ao;
	leaf_col *= (0.86 + 0.28 * fine_leaf);

	// Perturb normal into distinct foliage tufts for realistic Cities: Skylines II canopy shading!
	if (cam_d < 150.0) {
		float fade = 1.0 - smoothstep(95.0, 150.0, cam_d);
		vec3 grad = vec3(
			noise3(v_world * 9.0 + vec3(0.08, 0.0, 0.0)) - med_leaf,
			noise3(v_world * 9.0 + vec3(0.0, 0.08, 0.0)) - med_leaf,
			noise3(v_world * 9.0 + vec3(0.0, 0.0, 0.08)) - med_leaf
		);
		vec3 wn = normalize((MODEL_MATRIX * vec4(v_local_nrm, 0.0)).xyz + grad * (2.2 * fade));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}

	ALBEDO = leaf_col;
	ROUGHNESS = clamp(0.76 - 0.14 * sun_tip + 0.12 * fine_leaf, 0.58, 0.90);
	METALLIC = 0.0;
	SPECULAR = 0.24;
	// Subsurface scattering glow when backlit by the sun!
	BACKLIGHT = v_col.rgb * vec3(0.38, 0.46, 0.16) * (0.5 + 0.5 * sun_tip);
}
