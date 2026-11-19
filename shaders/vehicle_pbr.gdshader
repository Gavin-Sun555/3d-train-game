shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec4 v_col;
varying vec2 v_uv;
varying vec3 v_world;
varying vec3 v_world_nrm;
varying vec3 v_local_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void vertex() {
	v_col = COLOR;
	v_uv = UV;
	v_local_pos = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	int mat_id = int(round(v_col.a * 10.0));
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world);
	float ndotv = clamp(dot(v_world_nrm, view_dir), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 4.0);

	vec3 col = v_col.rgb;
	vec3 emit = vec3(0.0);
	float rough = 0.25;
	float metal = 0.30;
	float spec = 0.65;
	float ccoat = 0.0;
	float ccoat_rough = 0.08;

	if (mat_id == 0) {
		// === Automotive Clearcoat Metallic Body Paint ===
		float flake = hash21(floor(v_world.xz * 180.0 + v_world.y * 120.0));
		// Subtle lower-rocker panel road grime AO & crisp door seam line
		float lower_ao = smoothstep(0.18, 0.48, v_local_pos.y);
		float door_seam = 1.0;
		if (abs(v_local_pos.x) > 0.80 && v_local_pos.y > 0.26 && v_local_pos.y < 0.84) {
			float d1 = abs(v_local_pos.z + 0.68);
			float d2 = abs(v_local_pos.z - 0.32);
			float d3 = abs(v_local_pos.z - 1.18);
			door_seam = smoothstep(0.006, 0.022, min(min(d1, d2), d3));
		}
		col = v_col.rgb * (0.96 + 0.07 * flake) * mix(0.76, 1.0, lower_ao) * mix(0.32, 1.0, door_seam);
		rough = 0.20;
		metal = 0.42;
		spec = 0.85;
		ccoat = 0.90;
		ccoat_rough = 0.06;
	} else if (mat_id == 1) {
		// === Dark Tinted Automotive Glass with Sky Fresnel Reflection & Interior Silhouette ===
		vec3 sky_refl = vec3(0.54, 0.66, 0.78);
		vec3 cabin_dark = vec3(0.05, 0.065, 0.085);
		// Subtle black ceramic frit border around windshield/window edges
		float edge_frit = smoothstep(0.0, 0.08, v_uv.x) * smoothstep(0.0, 0.08, 1.0 - v_uv.x)
						* smoothstep(0.0, 0.10, v_uv.y) * smoothstep(0.0, 0.10, 1.0 - v_uv.y);
		col = mix(cabin_dark, sky_refl, clamp(0.14 + fresnel * 0.76, 0.0, 0.88));
		col = mix(vec3(0.04, 0.045, 0.05), col, edge_frit);
		rough = mix(0.35, 0.05, edge_frit);
		metal = 0.35;
		spec = 0.92;
		ccoat = 0.95;
		ccoat_rough = 0.03;
	} else if (mat_id == 2) {
		// === Tire Rubber Tread + 5-Spoke Brushed Silver Alloy Wheel Rim ===
		// v_uv encodes radial (x = 0 center -> 1 outer tire) & angular (y = angle -PI..PI) on wheel cap!
		if (v_uv.x > 0.01 && v_uv.x < 0.64) {
			float r = v_uv.x / 0.64;
			float ang = v_uv.y;
			float spokes = smoothstep(0.30, 0.55, cos(ang * 5.0));
			float hub = 1.0 - smoothstep(0.18, 0.26, r);
			float outer_lip = smoothstep(0.84, 0.94, r);
			float alloy_mask = clamp(spokes + hub + outer_lip, 0.0, 1.0);
			col = mix(vec3(0.08, 0.085, 0.095), vec3(0.74, 0.77, 0.81), alloy_mask);
			rough = mix(0.65, 0.24, alloy_mask);
			metal = mix(0.20, 0.86, alloy_mask);
			spec = 0.80;
		} else {
			// Grooved black tire rubber
			float tread = 0.90 + 0.14 * sin(v_local_pos.z * 95.0);
			col = vec3(0.09, 0.092, 0.098) * tread;
			rough = 0.88;
			metal = 0.02;
			spec = 0.18;
		}
	} else if (mat_id == 3) {
		// === Matte Dark Trim / Honeycomb Grille / Chrome ===
		float grille = 0.85 + 0.18 * sin(v_local_pos.x * 75.0) * sin(v_local_pos.y * 75.0);
		col = v_col.rgb * grille;
		rough = 0.42;
		metal = 0.55;
		spec = 0.60;
	} else if (mat_id == 4) {
		// === Warm Projector LED Headlight ===
		col = vec3(0.98, 0.96, 0.90);
		emit = vec3(1.0, 0.95, 0.82) * 2.3;
		rough = 0.10;
	} else if (mat_id == 5) {
		// === Ruby LED Taillight / Brake Bar ===
		col = vec3(0.88, 0.10, 0.10);
		emit = vec3(1.0, 0.12, 0.08) * 2.1;
		rough = 0.12;
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	CLEARCOAT = ccoat;
	CLEARCOAT_ROUGHNESS = ccoat_rough;
	EMISSION = emit;
}
