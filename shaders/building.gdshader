shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float night_factor : hint_range(0.0, 1.0) = 0.0;
uniform vec3 env_sky_tint = vec3(0.62, 0.72, 0.82);
uniform float chinese_style : hint_range(0.0, 1.0) = 0.0;

varying float v_up;
varying vec2 v_wall_uv;
varying vec4 v_bcol;
varying vec3 v_world_pos;
varying vec3 v_world_nrm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float fbm2(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.13 + vec2(17.3, 9.1)) * 0.35;
}

// Ray-box 3D interior room parallax mapping (with automatic distant skyline LOD!)
void trace_interior_room(
	vec2 win_uv,
	vec3 ray_local,
	float room_seed,
	bool is_office,
	float night_amt,
	float cam_dist,
	out vec3 out_albedo,
	out vec3 out_emit
) {
	if (cam_dist > 155.0) {
		out_albedo = is_office ? vec3(0.22, 0.25, 0.28) : vec3(0.26, 0.23, 0.20);
		out_emit = vec3(0.0);
		if (night_amt > 0.01 && room_seed > 0.60) {
			float turn_on = fract(room_seed * 31.7) * 0.55;
			float active = smoothstep(turn_on, turn_on + 0.22, night_amt);
			vec3 bulb = is_office ? vec3(0.95, 0.92, 0.84) : vec3(1.0, 0.83, 0.58);
			out_emit = bulb * active * 0.58;
		}
		return;
	}
	float depth = is_office ? 1.15 : 0.95;
	float rx = abs(ray_local.x) < 1e-4 ? 1e-4 : ray_local.x;
	float ry = abs(ray_local.y) < 1e-4 ? 1e-4 : ray_local.y;
	float rz = max(ray_local.z, 0.02);

	float tx = ((rx > 0.0 ? 1.0 : 0.0) - win_uv.x) / rx;
	float ty = ((ry > 0.0 ? 1.0 : 0.0) - win_uv.y) / ry;
	float tz = depth / rz;

	float t = min(min(tx, ty), tz);
	vec3 p = vec3(win_uv.x, win_uv.y, 0.0) + vec3(rx, ry, rz) * t;

	bool hit_ceil = (abs(t - ty) < 0.002) && (ry > 0.0);
	bool hit_floor = (abs(t - ty) < 0.002) && (ry < 0.0);
	bool hit_back = (abs(t - tz) < 0.002);

	// Varied interior wall/floor palette
	vec3 wall_col = is_office
		? mix(vec3(0.56, 0.58, 0.60), vec3(0.48, 0.50, 0.53), fract(room_seed * 7.3))
		: mix(vec3(0.62, 0.56, 0.48), vec3(0.54, 0.50, 0.46), fract(room_seed * 5.9));
	vec3 floor_col = is_office ? vec3(0.24, 0.25, 0.27) : vec3(0.36, 0.26, 0.18);
	vec3 ceil_col = vec3(0.70, 0.70, 0.69);

	vec3 surf = wall_col;
	float ceil_fixture = 0.0;

	if (hit_ceil) {
		surf = ceil_col;
		if (is_office) {
			// Recessed linear LED ceiling troffers
			float gx = abs(fract(p.x * 2.0) - 0.5);
			float gz = abs(fract(p.z * 2.2) - 0.5);
			ceil_fixture = (1.0 - smoothstep(0.10, 0.16, gx)) * (1.0 - smoothstep(0.28, 0.34, gz));
		} else {
			// Central warm ceiling lamp
			float d = length(vec2(p.x - 0.5, p.z - depth * 0.48));
			ceil_fixture = 1.0 - smoothstep(0.08, 0.18, d);
		}
	} else if (hit_floor) {
		surf = floor_col;
	} else if (hit_back) {
		// Subtle horizontal desk/shelf silhouette on back wall
		float furnish = step(0.34, p.y) + step(0.65, fract(p.x * 3.0 + room_seed));
		surf = wall_col * mix(0.62, 0.92, clamp(furnish, 0.0, 1.0));
	} else {
		// Side partition wall slightly shaded
		surf = wall_col * 0.80;
	}

	// Natural depth falloff inside the room
	float depth_ao = mix(1.0, 0.42, clamp(p.z / depth, 0.0, 1.0));
	surf *= depth_ao;

	// Partial Venetian blinds / roller shade on ~32% of windows
	float blind_r = fract(room_seed * 13.7);
	if (blind_r > 0.68) {
		float shade_top = 0.48 + 0.35 * fract(room_seed * 29.1);
		if (win_uv.y > shade_top) {
			float slats = 0.88 + 0.12 * sin(win_uv.y * 90.0);
			surf = vec3(0.68, 0.66, 0.62) * slats;
			ceil_fixture = 0.0;
		}
	}

	// Nighttime realistic room occupancy (~38% lit, varied warm/neutral Kelvin, never blown out!)
	bool occupied = (room_seed > 0.60);
	out_albedo = surf * 0.55;
	out_emit = vec3(0.0);

	if (night_amt > 0.01 && occupied) {
		// Staggered turn-on threshold so rooms light up gradually during dusk!
		float turn_on = fract(room_seed * 31.7) * 0.55;
		float active = smoothstep(turn_on, turn_on + 0.22, night_amt);
		vec3 bulb_tint = is_office
			? mix(vec3(0.92, 0.94, 0.98), vec3(1.0, 0.88, 0.70), step(0.45, fract(room_seed * 11.1)))
			: mix(vec3(1.0, 0.80, 0.52), vec3(1.0, 0.87, 0.66), fract(room_seed * 19.3));
		float room_dim = 0.38 + 0.52 * fract(room_seed * 43.1);
		// Soft bounced light on interior walls + brighter ceiling fixture
		float bounce = (0.35 + 0.45 * p.y) * depth_ao + ceil_fixture * 1.35;
		out_emit = bulb_tint * surf * active * room_dim * bounce * 1.55 + bulb_tint * ceil_fixture * active * 0.75;
	}
}

void vertex() {
	v_up = NORMAL.y;
	v_wall_uv = UV;
	v_bcol = COLOR;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Calibrated gentle reflectance curve on Chinese facades so bright white, ivory, champagne,
	// terracotta, silver-aluminum & sky-blue curtain walls stay luminous and true to Google Earth daylight!
	vec3 base_col = (chinese_style > 0.5)
		? pow(clamp(v_bcol.rgb, vec3(0.0), vec3(1.0)), vec3(1.22))
		: v_bcol.rgb;
	int raw_a = int(round(v_bcol.a * 255.0));
	int style = raw_a / 64;
	float b_seed = float(raw_a % 64);

	if (v_up > 0.65) {
		// Realistic sunlit waterproof concrete / membrane flat roof with expansion joints
		float macro = fbm2(v_world_pos.xz * 0.16);
		float fine = vnoise(v_world_pos.xz * 2.4);
		float jx = smoothstep(0.0, 0.025, fract(v_world_pos.x / 4.5)) * smoothstep(0.0, 0.025, 1.0 - fract(v_world_pos.x / 4.5));
		float jz = smoothstep(0.0, 0.025, fract(v_world_pos.z / 4.5)) * smoothstep(0.0, 0.025, 1.0 - fract(v_world_pos.z / 4.5));
		float joint = mix(0.88, 1.0, jx * jz);
		vec3 roof_base = mix(vec3(0.56, 0.57, 0.58), base_col * 0.80, 0.42);
		ALBEDO = roof_base * (0.90 + 0.14 * macro + 0.05 * fine) * joint;
		ROUGHNESS = clamp(0.86 + 0.08 * (1.0 - macro), 0.76, 0.94);
		METALLIC = 0.0;
		SPECULAR = 0.16;
	} else {
		float u = v_wall_uv.x;
		float h = v_wall_uv.y;
		float ground_ao = mix(0.88, 1.0, clamp(h / 6.0, 0.0, 1.0));

		// Construct tangent basis along wall (+u, +up, -normal inward)
		vec3 n_horiz = normalize(vec3(v_world_nrm.x, 0.0, v_world_nrm.z) + vec3(1e-5, 0.0, 0.0));
		vec3 t_horiz = vec3(n_horiz.z, 0.0, -n_horiz.x);
		vec3 to_frag = v_world_pos - CAMERA_POSITION_WORLD;
		float cam_dist = length(to_frag);
		vec3 view_to_frag = to_frag / max(cam_dist, 1e-4);
		vec3 ray_local = vec3(
			dot(view_to_frag, t_horiz),
			view_to_frag.y,
			dot(view_to_frag, -n_horiz)
		);
		float ndotv = clamp(dot(n_horiz, -view_to_frag), 0.0, 1.0);
		float fresnel = pow(1.0 - ndotv, 4.0);
		float bump_u = 0.0;
		float bump_y = 0.0;
		float aa_wall = 1.0 - smoothstep(45.0, 125.0, cam_dist);

		vec3 col = base_col * ground_ao;
		vec3 emit = vec3(0.0);
		float rough = 0.85;
		float metal = 0.02;
		float spec = 0.25;

		if (chinese_style > 0.5) {
			// =========================================================================
			// HIGH-CRAFT CONTEMPORARY & CLASSIC JIANGNAN URBAN ARCHITECTURE (嘉兴城市建筑)
			// Smooth multi-scale weathering, recessed window lintel shadows, 3D bump normals,
			// and distinct modern slab vs classic 1990s-2000s walk-up residential archetypes!
			// =========================================================================
			float macro_w = fbm2(vec2(u, abs(h)) * 0.22 + vec2(b_seed * 3.1, b_seed * 1.7));
			float fine_stucco = fbm2(vec2(u, abs(h)) * 3.8);
			bool is_lpx_arch = (style == 2 && b_seed >= 48.0);
			bool is_rural_arch = (style == 3 && b_seed >= 32.0);
			bool skip_comm_podium = is_lpx_arch || is_rural_arch;
			bool podium_cornice = (h >= 4.38 && h <= 4.70) && !skip_comm_podium;
			if (h < -0.001) {
				// Clean gable attic triangle masonry wall (ZERO diagonally sliced windows!)
				float gh = -h;
				float eave_ao = mix(0.84, 1.0, smoothstep(0.0, 0.35, gh));
				vec3 g_wall = base_col * (0.92 + 0.12 * macro_w) * (0.97 + 0.06 * fine_stucco) * eave_ao;
				// Subtle horizontal cornice belt right along the eave base of the gable triangle
				if (gh < 0.18) {
					col = mix(g_wall * 0.72, vec3(0.32, 0.31, 0.30), 0.30);
					bump_y = -0.28;
					rough = 0.78;
				} else {
					col = g_wall;
					rough = 0.84;
				}
			} else if (podium_cornice && style != 0) {
				// Crisp overhanging architectural granite belt cornice separating 1F shops from upper tower
				float c_shade = smoothstep(4.38, 4.52, h);
				col = mix(vec3(0.54, 0.52, 0.49), mix(vec3(0.76, 0.73, 0.68), base_col * 0.90, 0.40), c_shade) * ground_ao;
				bump_y = (h < 4.46) ? -0.45 : (h > 4.62 ? 0.35 : 0.0);
				rough = 0.66;
				metal = 0.06;
			} else if (h < 4.38 && style != 0 && !skip_comm_podium) {
				// Unified Chinese dry-hung granite commercial podium base (干挂花岗岩底商裙楼)
				float sx = fract(u / 1.15);
				float sy = fract(h / 0.64);
				float sjoint = smoothstep(0.0, 0.022, sx) * smoothstep(1.0, 0.978, sx) * smoothstep(0.0, 0.030, sy) * smoothstep(1.0, 0.970, sy);
				float sblock = hash21(vec2(floor(u / 1.15), floor(h / 0.64) + b_seed));
				vec3 granite = mix(vec3(0.56, 0.54, 0.50), base_col * 0.80, 0.38) * (0.92 + 0.10 * sblock) * (0.95 + 0.08 * fine_stucco);
				float bay_u = fract(u / 3.8);
				bool shop_win = (bay_u > 0.10 && bay_u < 0.90 && h > 0.44 && h < 3.45);
				bool shop_frame = (bay_u > 0.075 && bay_u < 0.925 && h > 0.39 && h < 3.53 && !shop_win);
				if (h < 0.44) {
					col = vec3(0.26, 0.27, 0.29) * (0.92 + 0.12 * fine_stucco) * ground_ao; // Dark honed granite plinth
					rough = 0.72;
				} else if (shop_frame || (shop_win && (abs(bay_u - 0.50) < 0.015 || abs(h - 2.65) < 0.036))) {
					col = vec3(0.15, 0.17, 0.19); // Deep bronze-charcoal aluminum storefront frame
					rough = 0.34;
					metal = 0.64;
				} else if (shop_win) {
					float r_shop = 0.70 + 0.26 * hash21(vec2(floor(u / 3.8), b_seed));
					vec2 suv = vec2((bay_u - 0.10) / 0.80, (h - 0.44) / 3.01);
					vec3 r_alb; vec3 r_em;
					trace_interior_room(suv, ray_local, r_shop, false, max(night_factor, 0.28), cam_dist, r_alb, r_em);
					float top_sh = smoothstep(3.45, 3.10, h);
					col = mix(r_alb * (0.72 + 0.28 * top_sh), env_sky_tint * 0.70, clamp(0.18 + fresnel * 0.50, 0.0, 0.74) * (1.0 - night_factor * 0.6));
					emit = r_em * 0.82;
					rough = 0.08;
					spec = 0.82;
				} else {
					col = mix(granite * 0.68, granite, sjoint) * ground_ao;
					bump_u = (sx < 0.025 ? -0.30 : (sx > 0.975 ? 0.30 : 0.0));
					bump_y = (sy < 0.030 ? -0.30 : (sy > 0.970 ? 0.30 : 0.0));
					rough = 0.72;
				}
			} else if (style == 0) {
				// Chinese Style 0: Contemporary CBD Low-E Glass Curtain Wall Tower (现代玻璃幕墙写字楼)
				float fh = 3.85;
				float bw = 1.95;
				float floor_idx = floor(h / fh);
				float bay_idx = floor(u / bw);
				float fy = fract(h / fh);
				float fx = fract(u / bw);
				bool mullion = (fx < 0.042 || fx > 0.958 || fy < 0.036 || fy > 0.964);
				bool fin = (fy < 0.092) && (h >= 5.2);
				bool spandrel = (fy < 0.24) && (h >= 5.2);
				if (fin) {
					col = mix(vec3(0.60, 0.65, 0.70), base_col * 0.88, 0.30) * ground_ao;
					bump_y = 0.35;
					rough = 0.26; metal = 0.82; spec = 0.78;
				} else if (mullion) {
					col = vec3(0.22, 0.26, 0.31) * ground_ao;
					bump_u = (fx < 0.042 ? 0.25 : (fx > 0.958 ? -0.25 : 0.0));
					rough = 0.30; metal = 0.78; spec = 0.70;
				} else if (spandrel) {
					float sp_var = 0.94 + 0.10 * hash21(vec2(bay_idx, floor_idx + b_seed));
					col = mix(base_col * 0.76, vec3(0.32, 0.44, 0.56), 0.48) * sp_var * ground_ao;
					rough = 0.16; metal = 0.42; spec = 0.72;
				} else {
					float r_seed = hash21(vec2(floor(bay_idx * 0.5) + b_seed * 11.3, floor_idx + b_seed * 5.7));
					vec2 room_uv = (h < 5.2)
						? vec2(fract(u / 3.9), clamp(h / 5.0, 0.01, 0.99))
						: vec2(fract(u / (bw * 2.0)), clamp((fy - 0.24) / 0.73, 0.01, 0.99));
					if (h < 5.2) r_seed = 0.86;
					vec3 r_alb; vec3 r_em;
					trace_interior_room(room_uv, ray_local, r_seed, true, night_factor, cam_dist, r_alb, r_em);
					vec3 ext_glass = mix(base_col * 0.92, env_sky_tint * 1.04, 0.48);
					float refl_amt = clamp(0.36 + fresnel * 0.58, 0.0, 0.92) * (1.0 - night_factor * 0.65);
					col = mix(r_alb * 1.15, ext_glass, refl_amt) * ground_ao;
					emit = r_em * (1.0 - refl_amt * 0.45);
					rough = 0.06; metal = 0.44; spec = 0.88;
				}
			} else if (style == 1) {
				// Chinese Style 1: Urban Commercial / Civic Dry-Hung Stone & Aluminum Complex (商住综合/公建干挂石材)
				float fh = 3.50;
				float bw = 3.60;
				float floor_idx = floor(h / fh);
				float bay_idx = floor(u / bw);
				float fy = fract(h / fh);
				float fx = fract(u / bw);
				float sx = fract(u / 1.20);
				float sy = fract(h / 0.70);
				float sjoint = smoothstep(0.0, 0.018, sx) * smoothstep(1.0, 0.982, sx) * smoothstep(0.0, 0.025, sy) * smoothstep(1.0, 0.975, sy);
				float panel_v = hash21(vec2(floor(u / 1.20), floor(h / 0.70) + b_seed));
				vec3 stone_c = base_col * (0.91 + 0.11 * panel_v) * (0.94 + 0.10 * macro_w) * (0.97 + 0.06 * fine_stucco);
				bool ac_slot = (fx > 0.05 && fx < 0.18 && fy > 0.16 && fy < 0.76);
				bool win_box = (fx > 0.22 && fx < 0.92 && fy > 0.16 && fy < 0.84);
				if (fy < 0.075) {
					float ledge_ao = smoothstep(0.0, 0.075, fy);
					col = stone_c * mix(0.72, 0.94, ledge_ao) * ground_ao;
					bump_y = -0.32;
					rough = 0.70;
				} else if (ac_slot) {
					float slat_f = fract(h * 10.5);
					float slats = 0.56 + 0.44 * smoothstep(0.22, 0.65, slat_f);
					col = vec3(0.22, 0.24, 0.27) * slats * ground_ao;
					bump_y = (slat_f - 0.5) * 0.70;
					rough = 0.48; metal = 0.52;
				} else if (win_box) {
					bool mull = (abs(fx - 0.57) < 0.016 || abs(fy - 0.56) < 0.016 || fx < 0.242 || fx > 0.898 || fy < 0.182 || fy > 0.818);
					if (mull) {
						col = vec3(0.17, 0.19, 0.22);
						rough = 0.34; metal = 0.68;
					} else {
						float r_seed = hash21(vec2(bay_idx + b_seed * 8.3, floor_idx + b_seed * 4.9));
						vec2 wuv = vec2((fx - 0.242) / 0.656, (fy - 0.182) / 0.636);
						vec3 r_alb; vec3 r_em;
						trace_interior_room(wuv, ray_local, r_seed, true, night_factor, cam_dist, r_alb, r_em);
						float lintel_sh = smoothstep(0.82, 0.68, fy);
						float jamb_sh = smoothstep(0.24, 0.29, fx) * smoothstep(0.90, 0.85, fx);
						col = mix(r_alb * (0.68 + 0.32 * lintel_sh * jamb_sh), env_sky_tint * 0.76, clamp(0.22 + fresnel * 0.56, 0.0, 0.80) * (1.0 - night_factor * 0.65));
						emit = r_em;
						rough = 0.09; spec = 0.82;
					}
				} else {
					col = mix(stone_c * 0.72, stone_c, sjoint) * ground_ao;
					bump_u = (sx < 0.02 ? -0.25 : (sx > 0.98 ? 0.25 : 0.0));
					bump_y = (sy < 0.025 ? -0.25 : (sy > 0.975 ? 0.25 : 0.0));
					rough = 0.76;
				}
			} else if (style == 2) {
				bool is_laopoxiao = (b_seed >= 48.0);
				bool is_walkup_90s = (b_seed >= 32.0 && b_seed < 48.0);
				if (is_laopoxiao) {
					// Chinese Style 2C: Authentic 1980s-early-1990s "老破小" Weathered Old Walk-Up
					// (斑驳水刷石/旧马赛克外墙 + 雨水渍 + 裸露PVC落水管 + 凸出防盗窗/保笼 + 外挂空调外机 + 水泥花格楼梯窗)
					float fh = 2.85;
					float bw = 3.45;
					float floor_idx = floor(h / fh);
					float bay_idx = floor(u / bw);
					float fy = fract(h / fh);
					float fx = fract(u / bw);
					bool is_stair_bay = (mod(bay_idx + floor(b_seed * 0.3), 4.0) < 0.5);
					bool is_balcony_bay = (!is_stair_bay) && (mod(bay_idx + floor(b_seed * 0.5), 2.0) < 0.5);
					// Heavy authentic 35-year aging: blotchy moisture patches + faded mosaic tiles/pebble-dash
					float patina = fbm2(vec2(u * 0.35, h * 0.28) + vec2(b_seed * 2.3, b_seed * 4.1));
					float grime_streak = fbm2(vec2(u * 2.6, h * 0.16) + vec2(b_seed, 3.7));
					bool has_mosaic = (mod(b_seed, 3.0) < 1.5);
					float tx = fract(u / 0.20);
					float ty = fract(h / 0.10);
					float t_aa = 1.0 - smoothstep(18.0, 56.0, cam_dist);
					float t_joint = mix(1.0, smoothstep(0.0, 0.08, tx) * smoothstep(0.0, 0.11, ty), t_aa);
					float t_tone = mix(0.5, hash21(vec2(floor(u / 0.20), floor(h / 0.10))), t_aa);
					vec3 aged_wall = base_col * (0.78 + 0.22 * patina) * (0.90 + 0.12 * grime_streak) * (0.95 + 0.08 * fine_stucco);
					vec3 wall_surf = has_mosaic ? mix(aged_wall * 0.74, aged_wall * (0.90 + 0.16 * t_tone), t_joint) : aged_wall;
					// Exposed vertical PVC rainwater downspout pipe every 2nd bay seam
					bool pvc_pipe = (mod(bay_idx, 2.0) < 0.5) && (fx < 0.036);
					// Exposed weathered cantilevered AC outdoor unit box beneath/beside windows (~65% of units)
					float ac_r = hash21(vec2(bay_idx * 3.1 + b_seed, floor_idx * 5.7 + 1.3));
					bool has_ac = (!is_stair_bay) && (floor_idx >= 0.5) && (ac_r > 0.34);
					bool ac_box = has_ac && (fx > 0.045 && fx < 0.21 && fy > 0.18 && fy < 0.42);
					// Protruding iron burglar cage ("防盗窗 / 保笼") over ~75% of windows & balconies
					float cage_r = hash21(vec2(bay_idx * 7.3 + b_seed, floor_idx * 2.9));
					bool has_cage = (cage_r > 0.22);

					if (h < 0.62) {
						// Weathered dark grey cement plinth with damp ground-level splash staining
						col = vec3(0.32, 0.32, 0.30) * (0.86 + 0.18 * patina) * ground_ao;
						rough = 0.92;
					} else if (pvc_pipe) {
						// Exterior dark grey-white PVC drainpipe with cylindrical shading & pipe clamps
						float cyl = 0.68 + 0.32 * sin((fx / 0.036) * 3.14159);
						bool clamp_ring = (abs(fy - 0.50) < 0.025);
						col = (clamp_ring ? vec3(0.22, 0.20, 0.18) : vec3(0.56, 0.57, 0.56) * cyl) * ground_ao;
						bump_u = (fx < 0.018 ? -0.45 : 0.45);
						rough = 0.58;
					} else if (is_stair_bay && floor_idx < 0.5 && fx > 0.24 && fx < 0.76 && h < 2.25) {
						// Old green/brown steel community unit security door (老小区单元防盗门)
						bool door_frame = (fx < 0.28 || fx > 0.72 || h > 2.15);
						bool door_win = (fx > 0.40 && fx < 0.60 && h > 1.35 && h < 1.85);
						col = door_frame ? vec3(0.20, 0.22, 0.20) : (door_win ? vec3(0.14, 0.17, 0.19) : vec3(0.22, 0.30, 0.24) * ground_ao);
						rough = door_win ? 0.18 : 0.65; metal = 0.45;
					} else if (is_stair_bay && fx > 0.28 && fx < 0.72) {
						// Half-floor offset concrete-lattice stairwell opening (水泥花格楼梯间窗)
						float st_fy = fract((h + fh * 0.5) / fh);
						bool st_open = (st_fy > 0.18 && st_fy < 0.82 && fx > 0.31 && fx < 0.69);
						if (st_open) {
							float gx = fract((fx - 0.31) * 14.0);
							float gy = fract((st_fy - 0.18) * 9.0);
							bool concrete_grid = (gx < 0.28 || gy < 0.28);
							col = concrete_grid ? (vec3(0.58, 0.56, 0.52) * ground_ao) : vec3(0.15, 0.17, 0.19);
							emit = concrete_grid ? vec3(0.0) : vec3(1.0, 0.85, 0.55) * night_factor * 0.24;
							rough = concrete_grid ? 0.88 : 0.30;
						} else {
							col = wall_surf * 0.90 * ground_ao;
							rough = 0.88;
						}
					} else if (ac_box) {
						// Exposed weathered AC outdoor unit with louvered circular fan grille, metallic casing & top hood shadow
						vec2 auv = vec2((fx - 0.045) / 0.165, (fy - 0.18) / 0.24);
						float fan_d = length((auv - vec2(0.37, 0.50)) * vec2(1.0, 1.12));
						bool casing_edge = (auv.x < 0.06 || auv.x > 0.94 || auv.y < 0.08 || auv.y > 0.92);
						bool fan_grille = (fan_d < 0.30);
						bool right_vent = (auv.x > 0.72 && auv.x < 0.88 && auv.y > 0.24 && auv.y < 0.76);
						float louver = 0.65 + 0.35 * sin(auv.y * 58.0);
						if (casing_edge) {
							col = vec3(0.46, 0.45, 0.42) * ground_ao;
						} else if (fan_grille) {
							bool hub = (fan_d < 0.08);
							bool ring = (abs(fan_d - 0.28) < 0.03);
							col = (ring ? vec3(0.36, 0.37, 0.38) : (hub ? vec3(0.28, 0.29, 0.30) : vec3(0.14, 0.15, 0.17) * louver)) * ground_ao;
						} else if (right_vent) {
							col = vec3(0.42, 0.43, 0.41) * louver * ground_ao;
						} else {
							col = vec3(0.72, 0.70, 0.65) * (0.86 + 0.14 * auv.y) * ground_ao;
						}
						bump_u = (auv.x < 0.08 ? -0.50 : (auv.x > 0.92 ? 0.50 : 0.0));
						bump_y = (auv.y < 0.10 ? -0.50 : (auv.y > 0.90 ? 0.50 : 0.0));
						rough = 0.55; metal = 0.38;
					} else if (has_ac && fx > 0.045 && fx < 0.21 && fy > 0.11 && fy <= 0.18) {
						// Under-AC shadow + twin rusted steel support L-brackets
						bool bracket = (abs(fx - 0.07) < 0.008 || abs(fx - 0.185) < 0.008);
						col = bracket ? vec3(0.30, 0.24, 0.20) * ground_ao : wall_surf * 0.72 * ground_ao;
						rough = bracket ? 0.62 : 0.88;
					} else if (fy < 0.068) {
						// Weathered dark-streaked floor slab band
						col = aged_wall * 0.72 * ground_ao;
						bump_y = -0.30;
						rough = 0.88;
					} else if (is_balcony_bay && fx > 0.10 && fx < 0.90 && fy > 0.09 && fy < 0.87) {
						// Mismatched retrofitted old balcony: concrete parapet + varied silver/white/brown aluminum frames + burglar bars
						bool lower_wall = (fy < 0.39);
						float bframe_v = hash21(vec2(bay_idx + 11.0, floor_idx + b_seed));
						vec3 old_frame_c = (bframe_v < 0.35) ? vec3(0.68, 0.70, 0.72) : ((bframe_v < 0.70) ? vec3(0.32, 0.26, 0.22) : vec3(0.24, 0.28, 0.32));
						bool rail_bar = (abs(fy - 0.40) < 0.025 || abs(fx - 0.36) < 0.016 || abs(fx - 0.64) < 0.016 || fx < 0.122 || fx > 0.878 || fy > 0.845);
						bool cage_bar = has_cage && (cam_dist < 72.0) && (fract(fx * 18.0) < 0.11 || fract(fy * 12.0) < 0.09);
						if (lower_wall) {
							float stain = mix(0.82, 1.0, smoothstep(0.39, 0.18, fy));
							col = aged_wall * 0.88 * stain * ground_ao;
							bump_y = 0.18;
							rough = 0.86;
						} else if (rail_bar) {
							col = old_frame_c * ground_ao;
							rough = 0.46; metal = 0.52;
						} else if (cage_bar) {
							col = vec3(0.56, 0.58, 0.60) * ground_ao; // Stainless / weathered steel burglar cage
							rough = 0.36; metal = 0.72;
						} else {
							float r_seed = hash21(vec2(bay_idx + b_seed * 6.7, floor_idx + b_seed * 5.3));
							vec2 wuv = vec2((fx - 0.122) / 0.756, (fy - 0.40) / 0.445);
							vec3 r_alb; vec3 r_em;
							trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
							float lintel_sh = smoothstep(0.85, 0.70, fy);
							col = mix(r_alb * (0.68 + 0.32 * lintel_sh), env_sky_tint * 0.68, clamp(0.16 + fresnel * 0.48, 0.0, 0.70) * (1.0 - night_factor * 0.62));
							emit = r_em * 0.88;
							rough = 0.14; spec = 0.70;
						}
					} else if (!is_balcony_bay && fx > 0.25 && fx < 0.84 && fy > 0.24 && fy < 0.79) {
						bool mull = (abs(fx - 0.545) < 0.018 || abs(fy - 0.58) < 0.018 || fx < 0.275 || fx > 0.815 || fy < 0.265 || fy > 0.765);
						bool cage_bar = has_cage && (cam_dist < 72.0) && (fract(fx * 20.0) < 0.11 || fract(fy * 12.0) < 0.09);
						if (mull) {
							col = vec3(0.32, 0.30, 0.28);
							rough = 0.48; metal = 0.44;
						} else if (cage_bar) {
							col = vec3(0.54, 0.56, 0.58) * ground_ao;
							rough = 0.38; metal = 0.70;
						} else {
							float r_seed = hash21(vec2(bay_idx + b_seed * 7.7, floor_idx + b_seed * 6.1));
							vec2 wuv = vec2((fx - 0.275) / 0.54, (fy - 0.265) / 0.50);
							vec3 r_alb; vec3 r_em;
							trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
							float lintel_sh = smoothstep(0.77, 0.62, fy);
							col = mix(r_alb * (0.66 + 0.34 * lintel_sh), env_sky_tint * 0.68, clamp(0.16 + fresnel * 0.48, 0.0, 0.70) * (1.0 - night_factor * 0.65));
							emit = r_em;
							rough = 0.14; spec = 0.70;
						}
					} else {
						// Pronounced dark rainwater drip streaks below window sills & balcony ledges
						float sill_drip = (!is_balcony_bay && fx > 0.24 && fx < 0.85 && fy < 0.24)
							? mix(0.74, 1.0, smoothstep(0.24, 0.05, fy))
							: 1.0;
						col = wall_surf * sill_drip * ground_ao;
						rough = has_mosaic ? 0.78 : 0.90;
					}
				} else if (is_walkup_90s) {
					// Chinese Style 2B: Classic 1990s-2000s Jiaxing Multi-Storey Walk-Up (老小区多层板楼: 面砖/真石漆 + 封闭阳台 + 单元楼梯窗)
					float fh = 3.00;
					float bw = 3.80;
					float floor_idx = floor(h / fh);
					float bay_idx = floor(u / bw);
					float fy = fract(h / fh);
					float fx = fract(u / bw);
					bool is_stair_bay = (mod(bay_idx + floor(b_seed * 0.3), 5.0) < 0.5);
					bool is_balcony_bay = (!is_stair_bay) && (mod(bay_idx + floor(b_seed * 0.5), 2.0) < 0.5);
					// Classic ceramic facade mosaic tiles (0.28m x 0.14m) on ~55% of walk-ups, warm stucco on rest
					bool has_tiles = (mod(b_seed, 2.0) < 0.5);
					float tx = fract(u / 0.28);
					float ty = fract(h / 0.14);
					float t_aa = 1.0 - smoothstep(22.0, 68.0, cam_dist);
					float t_joint = mix(1.0, smoothstep(0.0, 0.06, tx) * smoothstep(0.0, 0.09, ty), t_aa);
					float t_tone = mix(0.5, hash21(vec2(floor(u / 0.28), floor(h / 0.14))), t_aa);
					vec3 wall_main = base_col * (0.92 + 0.12 * macro_w) * (0.96 + 0.07 * fine_stucco);
					vec3 wall_surf = has_tiles ? mix(wall_main * 0.80, wall_main * (0.94 + 0.10 * t_tone), t_joint) : wall_main;
					vec3 band_c = mix(base_col * 0.76, vec3(0.46, 0.44, 0.41), 0.38);

					if (is_stair_bay && fx > 0.28 && fx < 0.72) {
						// Iconic Chinese walk-up vertical stairwell strip (offset half-floor landing windows!)
						float st_fy = fract((h + fh * 0.5) / fh);
						bool st_win = (st_fy > 0.20 && st_fy < 0.82 && fx > 0.32 && fx < 0.68);
						bool st_frame = (st_fy > 0.16 && st_fy < 0.86 && fx > 0.29 && fx < 0.71 && !st_win);
						if (st_frame || (st_win && abs(fx - 0.50) < 0.018)) {
							col = vec3(0.28, 0.30, 0.33) * ground_ao;
							rough = 0.42; metal = 0.50;
						} else if (st_win) {
							vec3 frost = mix(vec3(0.42, 0.48, 0.52), env_sky_tint * 0.80, 0.45);
							col = frost * ground_ao;
							emit = vec3(1.0, 0.88, 0.62) * night_factor * 0.32;
							rough = 0.28; spec = 0.65;
						} else {
							col = wall_surf * 0.94 * ground_ao;
							rough = 0.82;
						}
					} else if (fy < 0.075) {
						col = band_c * ground_ao;
						bump_y = -0.25;
						rough = 0.82;
					} else if (is_balcony_bay && fx > 0.09 && fx < 0.91 && fy > 0.10 && fy < 0.88) {
						bool lower_wall = (fy < 0.37);
						bool rail_bar = (abs(fy - 0.38) < 0.022 || abs(fx - 0.36) < 0.014 || abs(fx - 0.64) < 0.014 || fx < 0.115 || fx > 0.885 || fy > 0.855);
						if (lower_wall) {
							// Solid plastered / tiled balcony spandrel parapet
							col = mix(wall_main * 0.92, band_c * 1.12, 0.28) * ground_ao;
							bump_y = 0.15;
							rough = 0.80;
						} else if (rail_bar) {
							col = vec3(0.24, 0.26, 0.29);
							rough = 0.40; metal = 0.52;
						} else {
							float r_seed = hash21(vec2(bay_idx + b_seed * 6.7, floor_idx + b_seed * 5.3));
							vec2 wuv = vec2((fx - 0.115) / 0.77, (fy - 0.38) / 0.475);
							vec3 r_alb; vec3 r_em;
							trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
							float lintel_sh = smoothstep(0.86, 0.72, fy);
							col = mix(r_alb * (0.70 + 0.30 * lintel_sh), env_sky_tint * 0.74, clamp(0.18 + fresnel * 0.52, 0.0, 0.74) * (1.0 - night_factor * 0.62));
							emit = r_em * 0.90;
							rough = 0.11; spec = 0.76;
						}
					} else if (!is_balcony_bay && fx > 0.22 && fx < 0.82 && fy > 0.25 && fy < 0.80) {
						bool mull = (abs(fx - 0.52) < 0.016 || abs(fy - 0.60) < 0.016 || fx < 0.245 || fx > 0.795 || fy < 0.275 || fy > 0.775);
						if (mull) {
							col = vec3(0.26, 0.28, 0.31);
							rough = 0.42; metal = 0.48;
						} else {
							float r_seed = hash21(vec2(bay_idx + b_seed * 7.7, floor_idx + b_seed * 6.1));
							vec2 wuv = vec2((fx - 0.245) / 0.55, (fy - 0.275) / 0.50);
							vec3 r_alb; vec3 r_em;
							trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
							float lintel_sh = smoothstep(0.78, 0.64, fy);
							col = mix(r_alb * (0.68 + 0.32 * lintel_sh), env_sky_tint * 0.72, clamp(0.18 + fresnel * 0.52, 0.0, 0.74) * (1.0 - night_factor * 0.65));
							emit = r_em;
							rough = 0.12; spec = 0.74;
						}
					} else {
						// Subtle rain-stain weathering beneath window sills
						float sill_drip = (!is_balcony_bay && fx > 0.22 && fx < 0.82 && fy < 0.25) ? mix(0.86, 1.0, smoothstep(0.25, 0.08, fy)) : 1.0;
						col = wall_surf * sill_drip * ground_ao;
						rough = has_tiles ? 0.72 : 0.84;
					}
				} else {
					// Chinese Style 2A: Contemporary Modern Jiaxing Residential Slab / 洋房 (真石漆/铝板分缝 + 落地玻璃阳台 + 3D空调百叶)
					float fh = 3.05;
					float bw = 4.20;
					float floor_idx = floor(h / fh);
					float bay_idx = floor(u / bw);
					float fy = fract(h / fh);
					float fx = fract(u / bw);
					bool is_balcony_bay = (mod(bay_idx + floor(b_seed * 0.5), 2.0) < 0.5);
					// Preserve bright, varied surveyed & satellite-matched compound wall colors!
					vec3 wall_main = base_col * (0.96 + 0.08 * macro_w) * (0.98 + 0.05 * fine_stucco);
					vec3 accent_trim = mix(base_col * 0.80, vec3(0.46, 0.45, 0.44), 0.25);
					// Crisp architectural Zhenshiqi / aluminum cladding panel score lines (1.40m x 0.76m)
					float px_j = fract(u / 1.40);
					float py_j = fract(h / 0.7625);
					float p_aa = 1.0 - smoothstep(28.0, 80.0, cam_dist);
					float p_seam = mix(1.0, smoothstep(0.0, 0.016, px_j) * smoothstep(1.0, 0.984, px_j) * smoothstep(0.0, 0.022, py_j) * smoothstep(1.0, 0.978, py_j), p_aa);

					bool slab_line = (fy < 0.115);
					bool pilaster = (fx < 0.068 || fx > 0.932);
					bool ac_louver = (!is_balcony_bay && fx > 0.075 && fx < 0.21 && fy > 0.16 && fy < 0.74);
					bool win_open = is_balcony_bay
						? (fx > 0.12 && fx < 0.88 && fy > 0.12 && fy < 0.87)
						: (fx > 0.26 && fx < 0.86 && fy > 0.24 && fy < 0.82);

					if (slab_line) {
						float sl_grad = smoothstep(0.0, 0.115, fy);
						col = mix(wall_main * 0.84, wall_main * 1.04, sl_grad) * ground_ao;
						bump_y = (fy < 0.045) ? -0.32 : 0.20;
						rough = 0.68; metal = 0.14;
					} else if (pilaster) {
						col = wall_main * 1.03 * ground_ao;
						bump_u = (fx < 0.068 ? 0.24 : -0.24);
						rough = 0.76;
					} else if (ac_louver) {
						// 3D normal-mapped recessed dark charcoal aluminum AC outdoor-unit louver bay
						float slat_f = fract(h * 11.5);
						float slats = 0.52 + 0.48 * smoothstep(0.20, 0.65, slat_f);
						col = vec3(0.24, 0.26, 0.29) * slats * ground_ao;
						bump_y = (slat_f - 0.5) * 0.75;
						rough = 0.46; metal = 0.54;
					} else if (win_open) {
						if (is_balcony_bay) {
							// Wide Panoramic Enclosed Glazed Chinese Balcony with building-colored solid/frosted parapet
							bool rail_bar = (abs(fy - 0.37) < 0.022 || abs(fx - 0.37) < 0.013 || abs(fx - 0.63) < 0.013 || fx < 0.14 || fx > 0.86 || fy > 0.85);
							bool lower_balustrade = (fy < 0.36);
							if (rail_bar) {
								col = vec3(0.22, 0.24, 0.27);
								rough = 0.32; metal = 0.64;
							} else if (lower_balustrade) {
								col = mix(wall_main * 0.94, env_sky_tint * 0.90, 0.22) * ground_ao;
								rough = 0.46; spec = 0.48;
							} else {
								float r_seed = hash21(vec2(bay_idx + b_seed * 6.7, floor_idx + b_seed * 5.3));
								vec2 wuv = vec2((fx - 0.14) / 0.72, (fy - 0.37) / 0.48);
								vec3 r_alb; vec3 r_em;
								trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
								float lintel_sh = smoothstep(0.86, 0.72, fy);
								col = mix(r_alb * (0.76 + 0.24 * lintel_sh), env_sky_tint * 0.88, clamp(0.24 + fresnel * 0.54, 0.0, 0.78) * (1.0 - night_factor * 0.58));
								emit = r_em * 0.94;
								rough = 0.08; spec = 0.84;
							}
						} else {
							bool mull = (abs(fx - 0.56) < 0.015 || abs(fy - 0.62) < 0.015 || fx < 0.272 || fx > 0.858 || fy < 0.252 || fy > 0.808);
							if (mull) {
								col = vec3(0.18, 0.20, 0.23);
								rough = 0.34; metal = 0.64;
							} else {
								float r_seed = hash21(vec2(bay_idx + b_seed * 7.7, floor_idx + b_seed * 6.1));
								vec2 wuv = vec2((fx - 0.272) / 0.586, (fy - 0.252) / 0.556);
								vec3 r_alb; vec3 r_em;
								trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
								float lintel_sh = smoothstep(0.82, 0.67, fy);
								float jamb_sh = smoothstep(0.27, 0.32, fx) * smoothstep(0.86, 0.81, fx);
								col = mix(r_alb * (0.68 + 0.32 * lintel_sh * jamb_sh), env_sky_tint * 0.76, clamp(0.20 + fresnel * 0.56, 0.0, 0.78) * (1.0 - night_factor * 0.65));
								emit = r_em;
								rough = 0.09; spec = 0.82;
							}
						}
					} else {
						col = mix(wall_main * 0.82, wall_main, p_seam) * ground_ao;
						bump_u = (px_j < 0.02 ? -0.18 : (px_j > 0.98 ? 0.18 : 0.0));
						bump_y = (py_j < 0.025 ? -0.18 : (py_j > 0.975 ? 0.18 : 0.0));
						rough = 0.80;
					}
				}
			} else if (b_seed >= 32.0) {
				// Chinese Style 3B: Jiangnan Rural Self-Built Villa House (江南农村自建房 / 乡村2-3层小洋楼)
				// Dark stone plinth, bright cream/ochre rural wall tiles, crisp white floor cornices & corner pilasters,
				// recessed 2F/3F balcony with white concrete Roman balusters (水泥罗马柱护栏), wide rural double gate!
				float rural_ao = mix(0.90, 1.0, clamp(h / 4.5, 0.0, 1.0));
				float fh = 3.25;
				float bw = 3.55;
				float floor_idx = floor(h / fh);
				float bay_idx = floor(u / bw);
				float fy = fract(h / fh);
				float fx = fract(u / bw);
				float t_aa = 1.0 - smoothstep(22.0, 68.0, cam_dist);
				float tx = fract(u / 0.30);
				float ty = fract(h / 0.15);
				float t_joint = mix(1.0, smoothstep(0.0, 0.055, tx) * smoothstep(0.0, 0.085, ty), t_aa);
				float t_var = mix(0.5, hash21(vec2(floor(u / 0.30), floor(h / 0.15))), t_aa);
				bool has_tiles = (mod(b_seed, 3.0) < 2.0);
				vec3 wall_base = base_col * (0.96 + 0.08 * macro_w) * (0.98 + 0.05 * fine_stucco);
				vec3 wall_surf = has_tiles ? mix(wall_base * 0.86, wall_base * (0.96 + 0.07 * t_var), t_joint) : wall_base;
				vec3 white_trim = vec3(0.90, 0.89, 0.86) * rural_ao;
				bool is_balc_bay = (floor_idx >= 0.5) && (mod(bay_idx + floor(b_seed * 0.5), 2.0) < 0.5);
				bool is_gate_bay = (floor_idx < 0.5) && (mod(bay_idx, 3.0) < 0.5);

				if (h < 0.52) {
					// Dark grey rural stone / granite moisture plinth
					col = vec3(0.30, 0.31, 0.32) * (0.92 + 0.12 * fine_stucco) * rural_ao;
					rough = 0.78;
				} else if (fy < 0.088 && floor_idx >= 0.5) {
					// Crisp overhanging white rural horizontal floor cornice band (白色腰线)
					col = white_trim * mix(0.86, 1.02, smoothstep(0.0, 0.088, fy));
					bump_y = (fy < 0.04 ? -0.35 : 0.25);
					rough = 0.68;
				} else if (fx < 0.048 || fx > 0.952) {
					// Subtle decorative rural vertical corner/bay pilaster strip
					col = mix(wall_base, white_trim, 0.48) * rural_ao;
					bump_u = (fx < 0.048 ? 0.22 : -0.22);
					rough = 0.72;
				} else if (is_gate_bay && fx > 0.14 && fx < 0.86 && h < 2.75) {
					// Ground-floor rural double-leaf bronze entry gate or grey roller-shutter garage door
					bool is_shutter = (mod(b_seed, 2.0) < 0.5);
					bool g_frame = (fx < 0.18 || fx > 0.82 || h > 2.62);
					if (g_frame) {
						col = white_trim * 0.95;
						rough = 0.68;
					} else if (is_shutter) {
						float slats = 0.84 + 0.16 * sin(h * 44.0);
						col = vec3(0.62, 0.64, 0.66) * slats * rural_ao;
						bump_y = cos(h * 44.0) * 0.35;
						rough = 0.45; metal = 0.52;
					} else {
						bool seam = abs(fx - 0.50) < 0.015;
						col = (seam ? vec3(0.16, 0.11, 0.08) : vec3(0.34, 0.20, 0.14)) * rural_ao;
						rough = 0.42; metal = 0.46;
					}
				} else if (is_balc_bay && fx > 0.10 && fx < 0.90 && fy > 0.09 && fy < 0.86) {
					// Iconic rural 2F/3F balcony with white concrete Roman balusters (水泥葫芦瓶护栏)
					if (fy < 0.37) {
						bool rail_top = (fy > 0.33 || fy < 0.13);
						float bal_f = fract((fx - 0.10) * 14.0);
						bool baluster = (bal_f > 0.28 && bal_f < 0.72);
						if (rail_top || baluster) {
							col = white_trim * (baluster ? (0.88 + 0.12 * sin((bal_f - 0.28) / 0.44 * 3.14159)) : 1.0);
							bump_u = baluster ? ((bal_f < 0.5) ? -0.35 : 0.35) : 0.0;
							rough = 0.70;
						} else {
							col = vec3(0.20, 0.21, 0.23) * rural_ao;
							rough = 0.85;
						}
					} else {
						bool b_frame = (fx < 0.125 || fx > 0.875 || fy > 0.835 || abs(fx - 0.50) < 0.018);
						if (b_frame) {
							col = vec3(0.20, 0.22, 0.24);
							rough = 0.36; metal = 0.56;
						} else {
							float r_seed = hash21(vec2(bay_idx + b_seed * 6.3, floor_idx + b_seed * 4.1));
							vec2 wuv = vec2((fx - 0.125) / 0.75, (fy - 0.37) / 0.465);
							vec3 r_alb; vec3 r_em;
							trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
							col = mix(r_alb * 0.78, env_sky_tint * 0.76, clamp(0.18 + fresnel * 0.50, 0.0, 0.74) * (1.0 - night_factor * 0.62));
							emit = r_em * 0.90;
							rough = 0.11; spec = 0.76;
						}
					}
				} else if (fx > 0.21 && fx < 0.79 && fy > 0.23 && fy < 0.81) {
					// Wide rural window with crisp white plaster surround trim & dark aluminum mullions
					bool outer_trim = (fx < 0.245 || fx > 0.755 || fy < 0.26 || fy > 0.78);
					bool mull = (abs(fx - 0.50) < 0.016 || abs(fy - 0.60) < 0.016 || fx < 0.265 || fx > 0.735 || fy < 0.28 || fy > 0.76);
					if (outer_trim) {
						col = white_trim;
						bump_y = (fy > 0.78 ? 0.30 : (fy < 0.26 ? -0.30 : 0.0));
						rough = 0.70;
					} else if (mull) {
						col = vec3(0.19, 0.21, 0.24);
						rough = 0.36; metal = 0.58;
					} else {
						float r_seed = hash21(vec2(bay_idx + b_seed * 7.3, floor_idx + b_seed * 3.7));
						vec2 wuv = vec2((fx - 0.265) / 0.47, (fy - 0.28) / 0.48);
						vec3 r_alb; vec3 r_em;
						trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
						float lintel_sh = smoothstep(0.76, 0.64, fy);
						col = mix(r_alb * (0.72 + 0.28 * lintel_sh), env_sky_tint * 0.76, clamp(0.18 + fresnel * 0.52, 0.0, 0.76) * (1.0 - night_factor * 0.65));
						emit = r_em;
						rough = 0.10; spec = 0.78;
					}
				} else {
					col = wall_surf * rural_ao;
					rough = has_tiles ? 0.54 : 0.78;
					spec = has_tiles ? 0.42 : 0.24;
				}
			} else {
				// Chinese Style 3A: Jiangnan White-Wall Watertown Townhouse (江南粉墙黛瓦民居)
				float fh = 2.95;
				float bw = 3.50;
				float floor_idx = floor(h / fh);
				float bay_idx = floor(u / bw);
				float fy = fract(h / fh);
				float fx = fract(u / bw);
				vec3 plaster_c = mix(vec3(0.86, 0.84, 0.80), base_col, 0.45) * (0.93 + 0.10 * macro_w) * (0.97 + 0.06 * fine_stucco);
				bool is_balc = (mod(bay_idx, 2.0) < 0.5);
				bool win_open = is_balc
					? (fx > 0.14 && fx < 0.86 && fy > 0.16 && fy < 0.82)
					: (fx > 0.24 && fx < 0.76 && fy > 0.24 && fy < 0.78);
				if (fy < 0.06) {
					col = vec3(0.46, 0.46, 0.45) * ground_ao;
					rough = 0.84;
				} else if (win_open) {
					bool rail = (is_balc && abs(fy - 0.38) < 0.025) || abs(fx - 0.50) < 0.018;
					bool frame_b = (is_balc && (fx < 0.16 || fx > 0.84 || fy > 0.80)) || (!is_balc && (fx < 0.26 || fx > 0.74 || fy < 0.26 || fy > 0.76));
					if (rail || frame_b) {
						col = vec3(0.24, 0.17, 0.12); // Dark Jiangnan timber lattice window frame
						rough = 0.54; metal = 0.15;
					} else {
						float r_seed = hash21(vec2(bay_idx + b_seed * 7.3, floor_idx + b_seed * 2.9));
						vec2 wuv = vec2(fract(fx * 1.4), clamp((fy - 0.16) / 0.66, 0.01, 0.99));
						vec3 r_alb; vec3 r_em;
						trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
						col = mix(r_alb, env_sky_tint * 0.68, clamp(0.18 + fresnel * 0.48, 0.0, 0.70) * (1.0 - night_factor * 0.65));
						emit = r_em * 0.85;
						rough = 0.12; spec = 0.72;
					}
				} else {
					col = plaster_c * ground_ao;
					rough = 0.86;
				}
			}
			// Apply procedural tangent-space bump normal for crisp raking sunlight on facades
			if (aa_wall > 0.02 && (abs(bump_u) > 0.01 || abs(bump_y) > 0.01)) {
				vec3 pert_n = normalize(n_horiz + t_horiz * (bump_u * aa_wall) + vec3(0.0, bump_y * aa_wall, 0.0));
				NORMAL = normalize((VIEW_MATRIX * vec4(pert_n, 0.0)).xyz);
			}
		} else if (style == 0) {
			// === STYLE 0: Realistic Curtain-Wall Office Tower ===
			float fh = 3.9;
			float bw = 1.85;
			float floor_idx = floor(h / fh);
			float bay_idx = floor(u / bw);
			float fy = fract(h / fh);
			float fx = fract(u / bw);

			bool mullion = (fx < 0.045 || fx > 0.955 || fy < 0.032 || fy > 0.968);
			bool spandrel = (fy < 0.24) && (h >= 5.2);

			if (mullion) {
				// Anodized silver-champagne or dark-bronze aluminum mullions
				col = mix(vec3(0.46, 0.48, 0.50), base_col * 0.72, 0.45) * ground_ao;
				rough = 0.36;
				metal = 0.72;
				spec = 0.65;
			} else if (spandrel) {
				// Tinted architectural spandrel panel hiding floor slab
				col = mix(base_col * 0.52, vec3(0.20, 0.25, 0.29), 0.55) * ground_ao;
				rough = 0.22;
				metal = 0.35;
				spec = 0.55;
			} else {
				// Vision glazing with 3D interior room parallax + Fresnel sky reflection
				float room_group = floor(bay_idx * 0.5);
				float r_seed = hash21(vec2(room_group + b_seed * 11.3, floor_idx + b_seed * 5.7));
				vec2 room_uv = vec2(fract(u / (bw * 2.0)), clamp((fy - 0.24) / 0.73, 0.01, 0.99));
				if (h < 5.2) {
					room_uv = vec2(fract(u / 3.7), clamp(h / 5.0, 0.01, 0.99));
					r_seed = 0.85; // Lobby warm light
				}
				vec3 r_alb;
				vec3 r_em;
				trace_interior_room(room_uv, ray_local, r_seed, true, night_factor, cam_dist, r_alb, r_em);

				vec3 ext_glass = mix(base_col * 0.75, env_sky_tint, 0.55);
				float refl_amt = clamp(0.24 + fresnel * 0.62, 0.0, 0.86) * (1.0 - night_factor * 0.65);
				col = mix(r_alb, ext_glass, refl_amt) * ground_ao;
				emit = r_em * (1.0 - refl_amt * 0.45);
				rough = 0.09;
				metal = 0.38;
				spec = 0.82;
			}
		} else if (style == 1) {
			// === STYLE 1: Historic Seattle Brick, Terracotta & Limestone Architecture ===
			float fh = 3.65;
			float bw = 3.0;
			float floor_idx = floor(h / fh);
			float bay_idx = floor(u / bw);
			float fy = fract(h / fh);
			float fx = fract(u / bw);

			// Realistic running-bond brick / ashlar stone texture
			float row = floor(h / 0.11);
			float bx = fract((u + mod(row, 2.0) * 0.14) / 0.28);
			float by = fract(h / 0.11);
			float mortar = smoothstep(0.04, 0.09, bx) * smoothstep(0.08, 0.18, by);
			float brick_id = hash21(vec2(floor((u + mod(row, 2.0) * 0.14) / 0.28), row));
			vec3 brick = base_col * (0.90 + 0.18 * brick_id);
			vec3 mortar_col = mix(base_col, vec3(0.74, 0.71, 0.66), 0.62);
			vec3 masonry = mix(mortar_col, brick, mortar);
			if (b_seed >= 60.0) {
				// Smooth glazed terracotta / cut ashlar: large blocks, fine joints, subtle glaze variation
				float arow = floor(h / 0.62);
				float ax = fract((u + mod(arow, 2.0) * 0.6) / 1.2);
				float ay = fract(h / 0.62);
				float joint_a = smoothstep(0.0, 0.015, ax) * smoothstep(1.0, 0.985, ax) * smoothstep(0.0, 0.03, ay);
				float block_id = hash21(vec2(floor((u + mod(arow, 2.0) * 0.6) / 1.2), arow));
				vec3 block = base_col * (0.95 + 0.07 * block_id);
				masonry = mix(base_col * 0.78, block, joint_a);
			}

			if (h < 4.5) {
				// Ground-floor retail storefront with fascia signboard, bronze mullions & 3D shop interior
				bool fascia = (h >= 3.85 && h <= 4.38 && fx > 0.08 && fx < 0.92);
				bool shop_open = (fx > 0.12 && fx < 0.88 && h > 0.55 && h < 3.85);
				bool shop_mullion = shop_open && (abs(fx - 0.50) < 0.018 || abs(h - 3.05) < 0.04);
				if (fascia) {
					float sg = hash21(vec2(floor(bay_idx * 0.5), b_seed * 3.7));
					vec3 sign_bg = sg < 0.33 ? vec3(0.10, 0.22, 0.18) : (sg < 0.66 ? vec3(0.14, 0.18, 0.28) : vec3(0.28, 0.12, 0.14));
					float letter_band = step(0.55, fract(u * 1.3)) * step(4.06, h) * step(h, 4.16) * step(0.30, fx) * step(fx, 0.70) * 0.35;
					col = mix(sign_bg, vec3(0.92, 0.88, 0.76), letter_band * 0.85);
					emit = vec3(0.96, 0.88, 0.68) * letter_band * (0.18 + night_factor * 0.85);
					rough = 0.35;
					metal = 0.25;
				} else if (shop_mullion) {
					col = vec3(0.18, 0.17, 0.16);
					rough = 0.45;
					metal = 0.55;
				} else if (shop_open) {
					float r_shop = 0.72 + 0.25 * hash21(vec2(bay_idx, b_seed));
					vec2 suv = vec2((fx - 0.12) / 0.76, (h - 0.55) / 3.30);
					vec3 r_alb;
					vec3 r_em;
					trace_interior_room(suv, ray_local, r_shop, false, max(night_factor, 0.35), cam_dist, r_alb, r_em);
					col = mix(r_alb, env_sky_tint * 0.6, fresnel * 0.42);
					emit = r_em * 0.85;
					rough = 0.12;
					spec = 0.72;
				} else {
					// Granite water-table & weathered masonry piers
					float micro = hash21(floor(vec2(u, h) * 18.0));
					col = (h < 0.55 ? vec3(0.36, 0.35, 0.34) * (0.92 + 0.10 * micro) : masonry * (0.90 + 0.08 * micro)) * ground_ao;
					rough = 0.86;
				}
			} else {
				// Upper facade: deeply framed double-hung sash windows
				bool stone_trim = (fx > 0.20 && fx < 0.80 && fy > 0.15 && fy < 0.83);
				bool win_pane = (fx > 0.25 && fx < 0.75 && fy > 0.20 && fy < 0.78);
				if (win_pane) {
					bool sash_bar = (abs(fy - 0.49) < 0.016 || abs(fx - 0.50) < 0.014);
					if (sash_bar) {
						col = vec3(0.76, 0.73, 0.68) * ground_ao;
						rough = 0.65;
					} else {
						float r_seed = hash21(vec2(bay_idx + b_seed * 9.1, floor_idx + b_seed * 4.3));
						vec2 wuv = vec2((fx - 0.25) / 0.50, (fy - 0.20) / 0.58);
						vec3 r_alb;
						vec3 r_em;
						trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
						// Shadow from recessed window lintel at top of window
						float lintel_ao = smoothstep(0.78, 0.64, fy);
						col = mix(r_alb * lintel_ao, env_sky_tint * 0.65, clamp(0.16 + fresnel * 0.50, 0.0, 0.70) * (1.0 - night_factor * 0.7));
						emit = r_em;
						rough = 0.14;
						spec = 0.68;
					}
				} else if (stone_trim) {
					// Limestone sill & lintel surround
					col = vec3(0.76, 0.73, 0.67) * ground_ao;
					rough = 0.82;
				} else {
					col = masonry * ground_ao;
					rough = 0.89;
				}
			}
		} else if (style == 2) {
			// === STYLE 2: Contemporary Architectural Precast Concrete & Metal Mid-Rise ===
			float fh = 3.55;
			float bw = 3.4;
			float floor_idx = floor(h / fh);
			float bay_idx = floor(u / bw);
			float fy = fract(h / fh);
			float fx = fract(u / bw);

			float panel_noise = hash21(vec2(bay_idx, floor_idx + b_seed));
			bool joint = (fx < 0.022 || fy < 0.028);
			bool win = (h > 4.2) && (fx > 0.13 && fx < 0.87) && (fy > 0.22 && fy < 0.80);

			if (win) {
				bool sub_mullion = (abs(fx - 0.38) < 0.012 || abs(fx - 0.62) < 0.012);
				if (sub_mullion) {
					col = vec3(0.24, 0.25, 0.27);
					rough = 0.42;
					metal = 0.60;
				} else {
					float r_seed = hash21(vec2(bay_idx + b_seed * 7.7, floor_idx + b_seed * 6.1));
					vec2 wuv = vec2((fx - 0.13) / 0.74, (fy - 0.22) / 0.58);
					vec3 r_alb;
					vec3 r_em;
					trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
					col = mix(r_alb, env_sky_tint * 0.72, clamp(0.20 + fresnel * 0.55, 0.0, 0.75) * (1.0 - night_factor * 0.65));
					emit = r_em;
					rough = 0.12;
					spec = 0.75;
				}
			} else if (h <= 4.2 && fx > 0.10 && fx < 0.90 && h >= 3.60 && h <= 4.10) {
				// Contemporary retail fascia signboard band
				float sg = hash21(vec2(floor(bay_idx * 0.5), b_seed * 4.3));
				vec3 sign_bg = sg < 0.5 ? vec3(0.12, 0.14, 0.18) : vec3(0.14, 0.24, 0.28);
				float lband = step(0.55, fract(u * 1.3)) * step(3.78, h) * step(h, 3.88) * step(0.30, fx) * step(fx, 0.70) * 0.35;
				col = mix(sign_bg, vec3(0.92, 0.94, 0.96), lband * 0.82);
				emit = vec3(0.86, 0.92, 1.0) * lband * (0.16 + night_factor * 0.80);
				rough = 0.34;
				metal = 0.30;
			} else if (h <= 4.2 && fx > 0.12 && fx < 0.88 && h > 0.45 && h < 3.6) {
				vec2 suv = vec2((fx - 0.12) / 0.76, (h - 0.45) / 3.15);
				vec3 r_alb;
				vec3 r_em;
				trace_interior_room(suv, ray_local, 0.78, true, max(night_factor, 0.28), cam_dist, r_alb, r_em);
				col = mix(r_alb, env_sky_tint * 0.65, fresnel * 0.45);
				emit = r_em * 0.8;
				rough = 0.14;
				spec = 0.70;
			} else {
				float c_grain = hash21(floor(vec2(u, h) * 14.0));
				vec3 conc = base_col * (0.92 + 0.08 * panel_noise + 0.04 * c_grain) * (joint ? 0.78 : 1.0);
				col = conc * ground_ao;
				rough = 0.84;
				metal = 0.02;
			}
		} else {
			// === STYLE 3: Seattle house: painted lap siding, white-trimmed double-hung windows, front door ===
			float fh = 3.0;
			float bw = 3.2;
			float floor_idx = floor(h / fh);
			float bay_idx = floor(u / bw);
			float fy = fract(h / fh);
			float fx = fract(u / bw);
			float board = fract(h / 0.19);
			float lap = 0.86 + 0.14 * smoothstep(0.0, 0.22, board); // shadow line under each board
			vec3 siding = base_col * lap * (0.96 + 0.06 * hash21(vec2(floor(u / 4.8), floor(h / 0.19))));
			bool has_door = (floor_idx < 0.5) && (abs(bay_idx - floor(b_seed * 0.13) - 1.0) < 0.5);
			bool door = has_door && fx > 0.33 && fx < 0.67 && h > 0.45 && h < 2.55;
			bool door_trim = has_door && fx > 0.30 && fx < 0.70 && h > 0.40 && h < 2.68 && !door;
			bool win = !has_door && fx > 0.34 && fx < 0.66 && fy > 0.31 && fy < 0.80;
			bool trim = !has_door && fx > 0.31 && fx < 0.69 && fy > 0.27 && fy < 0.84 && !win;
			if (h < 0.42) {
				col = vec3(0.50, 0.49, 0.47) * (0.92 + 0.08 * hash21(floor(vec2(u, h) * 9.0))); // concrete foundation
				rough = 0.9;
			} else if (door) {
				vec3 door_c = mix(vec3(0.20, 0.13, 0.09), base_col * 0.45, step(0.5, hash21(vec2(b_seed, 3.1))));
				col = door_c * (abs(fx - 0.5) > 0.12 && h > 1.0 && h < 2.2 ? 0.86 : 1.0);
				rough = 0.6;
			} else if (door_trim || trim) {
				col = vec3(0.90, 0.89, 0.85) * ground_ao;
				rough = 0.7;
			} else if (win) {
				bool sash = abs(fy - 0.555) < 0.018 || abs(fx - 0.5) < 0.012;
				if (sash) {
					col = vec3(0.92, 0.91, 0.87);
					rough = 0.6;
				} else {
					float r_seed = hash21(vec2(bay_idx + b_seed * 7.3, floor_idx + b_seed * 2.9));
					vec2 wuv = vec2((fx - 0.34) / 0.32, (fy - 0.31) / 0.49);
					vec3 r_alb;
					vec3 r_em;
					trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
					col = mix(r_alb, env_sky_tint * 0.7, clamp(0.18 + fresnel * 0.5, 0.0, 0.7) * (1.0 - night_factor * 0.65));
					emit = r_em * 0.85;
					rough = 0.14;
					spec = 0.7;
				}
			} else {
				col = siding * ground_ao;
				rough = 0.8;
			}
		}

		ALBEDO = col;
		ROUGHNESS = rough;
		METALLIC = metal;
		SPECULAR = spec;
		EMISSION = emit;
	}
}
