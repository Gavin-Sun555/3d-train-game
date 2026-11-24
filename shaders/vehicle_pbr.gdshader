shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

instance uniform float brake_on = 0.0;
instance uniform float turn_signal = 0.0;

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
		// Real car paint is a pigmented (dielectric) base coat under a clear coat: only silver / grey paints carry
		// metal flakes. A thin film of city dust and some wear keep the coat from mirroring the sky.
		vec3 base = v_col.rgb;
		float sat = max(max(base.r, base.g), base.b) - min(min(base.r, base.g), base.b);
		float val = max(max(base.r, base.g), base.b);
		float flake_paint = (1.0 - smoothstep(0.06, 0.14, sat)) * smoothstep(0.28, 0.40, val) * (1.0 - smoothstep(0.80, 0.90, val));
		float grime = hash21(floor(v_world.xz * 6.0)) * 0.5 + 0.5 * hash21(floor(v_world.xz * 23.0 + 7.0));
		float up = clamp(v_world_nrm.y, 0.0, 1.0);
		vec3 dust = vec3(0.56, 0.54, 0.50);
		col = base * (0.97 + 0.04 * flake * flake_paint) * mix(0.80, 1.0, lower_ao) * mix(0.35, 1.0, door_seam);
		col = mix(col, dust, 0.06 + 0.07 * up + 0.10 * (1.0 - lower_ao));
		rough = mix(0.46, 0.36, flake_paint) + 0.08 * grime;
		metal = mix(0.0, 0.22, flake_paint);
		spec = 0.42;
		ccoat = 0.2;
		ccoat_rough = 0.22 + 0.10 * grime;
	} else if (mat_id == 1) {
		// === Dark Tinted Automotive Glass with Sky Fresnel Reflection & Interior Silhouette ===
		vec3 sky_refl = vec3(0.54, 0.66, 0.78);
		vec3 cabin_dark = vec3(0.05, 0.065, 0.085);
		// Subtle black ceramic frit border around windshield/window edges
		float edge_frit = smoothstep(0.0, 0.08, v_uv.x) * smoothstep(0.0, 0.08, 1.0 - v_uv.x)
						* smoothstep(0.0, 0.10, v_uv.y) * smoothstep(0.0, 0.10, 1.0 - v_uv.y);
		col = mix(cabin_dark, sky_refl * 0.8, clamp(0.10 + fresnel * 0.55, 0.0, 0.65));
		col = mix(vec3(0.04, 0.045, 0.05), col, edge_frit);
		rough = mix(0.40, 0.08, edge_frit);
		metal = 0.0;
		spec = 0.5;
		ccoat = 0.0;
		ccoat_rough = 0.1;
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
			rough = mix(0.70, 0.38, alloy_mask);
			metal = mix(0.0, 0.70, alloy_mask);
			spec = 0.5;
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
		// Bumper / sill / trim plastic and the number plate: matte, non-metallic (faint texture, no checkerboard)
		float grille = 0.97 + 0.04 * sin(v_local_pos.x * 75.0) * sin(v_local_pos.y * 75.0);
		col = v_col.rgb * grille;
		rough = 0.66;
		metal = 0.0;
		spec = 0.38;
	} else if (mat_id == 4) {
		// === Warm Projector LED Headlight ===
		col = vec3(0.98, 0.96, 0.90);
		emit = vec3(1.0, 0.95, 0.82) * 2.3;
		rough = 0.10;
	} else if (mat_id == 5) {
		// === Ruby LED Taillight / Dynamic Brake Bar (brightens strongly when braking/stopped!) ===
		float brk = clamp(brake_on, 0.0, 1.0);
		col = mix(vec3(0.76, 0.08, 0.08), vec3(1.0, 0.14, 0.10), brk);
		emit = vec3(1.0, 0.11, 0.07) * mix(1.35, 4.6, brk);
		rough = 0.10;
	} else if (mat_id == 6) {
		// === Dynamic Amber LED Turn Indicator (blinks on left/right side when turning!) ===
		float side_match = step(0.5, turn_signal * sign(v_local_pos.x));
		float blink = step(0.45, fract(TIME * 1.65)) * side_match;
		col = mix(vec3(0.55, 0.34, 0.06), vec3(1.0, 0.68, 0.08), blink);
		emit = vec3(1.0, 0.62, 0.06) * (blink * 4.2);
		rough = 0.12;
	} else if (mat_id == 7) {
		// === Matte Woven Fabric / Clothing / Leather Seat (zero metallic shine, zero checkerboard!) ===
		float weave = 0.96 + 0.05 * hash21(floor(v_local_pos.xy * 110.0 + v_local_pos.z * 90.0));
		float fold = 0.94 + 0.06 * clamp(v_world_nrm.y * 0.5 + 0.5, 0.0, 1.0);
		col = v_col.rgb * weave * fold;
		rough = 0.90;
		metal = 0.0;
		spec = 0.14;
		ccoat = 0.0;
	} else if (mat_id == 8) {
		// === Matte Natural Skin & Hair (warm soft diffuse, non-metallic!) ===
		col = v_col.rgb;
		rough = 0.72;
		metal = 0.0;
		spec = 0.24;
		ccoat = 0.0;
	} else if (mat_id == 9) {
		// === Satin Matte Polymer / Scooter Seat Trim / Rubber Grips (clean, no honeycomb grille!) ===
		col = v_col.rgb;
		rough = 0.58;
		metal = 0.04;
		spec = 0.32;
		ccoat = 0.0;
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = spec;
	CLEARCOAT = ccoat;
	CLEARCOAT_ROUGHNESS = ccoat_rough;
	EMISSION = emit;
}
