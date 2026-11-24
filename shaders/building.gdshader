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
	vec3 base_col = v_bcol.rgb;
	int raw_a = int(round(v_bcol.a * 255.0));
	int style = raw_a / 64;
	float b_seed = float(raw_a % 64);

	if (v_up > 0.65) {
		// Realistic weathered gravel/membrane flat roof
		float g = hash21(floor(v_world_pos.xz * 4.0));
		float macro = hash21(floor(v_world_pos.xz * 0.35));
		ALBEDO = base_col * (0.52 + 0.08 * g + 0.06 * macro);
		ROUGHNESS = 0.92;
		METALLIC = 0.0;
		SPECULAR = 0.16;
	} else {
		float u = v_wall_uv.x;
		float h = v_wall_uv.y;
		float ground_ao = mix(0.80, 1.0, clamp(h / 7.5, 0.0, 1.0));

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

		vec3 col = base_col * ground_ao;
		vec3 emit = vec3(0.0);
		float rough = 0.85;
		float metal = 0.02;
		float spec = 0.25;

		if (chinese_style > 0.5) {
			// =========================================================================
			// AUTHENTIC CONTEMPORARY CHINESE & JIANGNAN URBAN ARCHITECTURE (嘉兴城市建筑)
			// Unified 1F granite commercial podium (y=0..4.6m) so ground-floor storefronts
			// (连排底商) integrate seamlessly into every residential, mixed-use & office block!
			// =========================================================================
			bool podium_cornice = (h >= 4.38 && h <= 4.68);
			if (podium_cornice && style != 0) {
				// Crisp overhanging architectural granite belt cornice separating 1F shops from upper tower
				col = mix(vec3(0.76, 0.74, 0.70), base_col * 0.92, 0.35) * ground_ao;
				rough = 0.68;
				metal = 0.05;
			} else if (h < 4.38 && style != 0) {
				// Unified Chinese dry-hung granite commercial podium base (干挂花岗岩底商裙楼)
				float sx = fract(u / 1.10);
				float sy = fract(h / 0.62);
				float sjoint = smoothstep(0.0, 0.018, sx) * smoothstep(1.0, 0.982, sx) * smoothstep(0.0, 0.028, sy);
				float sblock = hash21(vec2(floor(u / 1.10), floor(h / 0.62) + b_seed));
				vec3 granite = mix(vec3(0.66, 0.64, 0.60), base_col * 0.88, 0.35) * (0.94 + 0.08 * sblock);
				float bay_u = fract(u / 3.8);
				bool shop_win = (bay_u > 0.10 && bay_u < 0.90 && h > 0.42 && h < 3.45);
				bool shop_frame = (bay_u > 0.08 && bay_u < 0.92 && h > 0.38 && h < 3.52 && !shop_win);
				if (h < 0.42) {
					col = vec3(0.32, 0.33, 0.35) * ground_ao; // Dark grey granite plinth kickplate
					rough = 0.76;
				} else if (shop_frame || (shop_win && (abs(bay_u - 0.50) < 0.015 || abs(h - 2.65) < 0.035))) {
					col = vec3(0.18, 0.20, 0.22); // Dark broken-bridge aluminum storefront frame
					rough = 0.38;
					metal = 0.58;
				} else if (shop_win) {
					float r_shop = 0.70 + 0.26 * hash21(vec2(floor(u / 3.8), b_seed));
					vec2 suv = vec2((bay_u - 0.10) / 0.80, (h - 0.42) / 3.03);
					vec3 r_alb; vec3 r_em;
					trace_interior_room(suv, ray_local, r_shop, false, max(night_factor, 0.30), cam_dist, r_alb, r_em);
					col = mix(r_alb, env_sky_tint * 0.68, clamp(0.18 + fresnel * 0.48, 0.0, 0.72) * (1.0 - night_factor * 0.6));
					emit = r_em * 0.82;
					rough = 0.10;
					spec = 0.78;
				} else {
					col = mix(granite * 0.78, granite, sjoint) * ground_ao;
					rough = 0.74;
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
				bool fin = (fy < 0.095) && (h >= 5.2);
				bool spandrel = (fy < 0.24) && (h >= 5.2);
				if (fin) {
					col = vec3(0.68, 0.72, 0.76) * ground_ao; // Silver aluminum sun-shade fin
					rough = 0.30; metal = 0.78; spec = 0.72;
				} else if (mullion) {
					col = vec3(0.28, 0.32, 0.36) * ground_ao;
					rough = 0.34; metal = 0.72; spec = 0.65;
				} else if (spandrel) {
					col = mix(base_col * 0.56, vec3(0.22, 0.30, 0.38), 0.55) * ground_ao;
					rough = 0.20; metal = 0.35; spec = 0.60;
				} else {
					float r_seed = hash21(vec2(floor(bay_idx * 0.5) + b_seed * 11.3, floor_idx + b_seed * 5.7));
					vec2 room_uv = (h < 5.2)
						? vec2(fract(u / 3.9), clamp(h / 5.0, 0.01, 0.99))
						: vec2(fract(u / (bw * 2.0)), clamp((fy - 0.24) / 0.73, 0.01, 0.99));
					if (h < 5.2) r_seed = 0.86;
					vec3 r_alb; vec3 r_em;
					trace_interior_room(room_uv, ray_local, r_seed, true, night_factor, cam_dist, r_alb, r_em);
					vec3 ext_glass = mix(base_col * 0.78, env_sky_tint, 0.56);
					float refl_amt = clamp(0.26 + fresnel * 0.62, 0.0, 0.88) * (1.0 - night_factor * 0.65);
					col = mix(r_alb, ext_glass, refl_amt) * ground_ao;
					emit = r_em * (1.0 - refl_amt * 0.45);
					rough = 0.08; metal = 0.38; spec = 0.84;
				}
			} else if (style == 1) {
				// Chinese Style 1: Urban Commercial / Mixed-Use Dry-Hung Stone & Aluminum Complex (商住综合楼)
				float fh = 3.50;
				float bw = 3.60;
				float floor_idx = floor(h / fh);
				float bay_idx = floor(u / bw);
				float fy = fract(h / fh);
				float fx = fract(u / bw);
				float sjoint = smoothstep(0.0, 0.015, fract(u / 1.2)) * smoothstep(0.0, 0.022, fract(h / 0.70));
				vec3 stone_c = mix(base_col, vec3(0.82, 0.79, 0.73), 0.38) * (0.94 + 0.07 * hash21(vec2(floor(u / 1.2), floor(h / 0.70))));
				bool ac_slot = (fx > 0.05 && fx < 0.18 && fy > 0.16 && fy < 0.74);
				bool win_box = (fx > 0.22 && fx < 0.92 && fy > 0.16 && fy < 0.84);
				if (fy < 0.07) {
					col = stone_c * 0.84 * ground_ao; // Crisp horizontal floor-slab belt line
					rough = 0.72;
				} else if (ac_slot) {
					// Recessed dark-grey horizontal aluminum AC outdoor unit louvers (空调外机百叶)
					float slats = 0.68 + 0.32 * step(0.45, fract(h * 11.0));
					col = vec3(0.28, 0.30, 0.33) * slats * ground_ao;
					rough = 0.55; metal = 0.42;
				} else if (win_box) {
					bool mull = (abs(fx - 0.57) < 0.015 || abs(fy - 0.56) < 0.016 || fx < 0.24 || fx > 0.90 || fy < 0.18 || fy > 0.82);
					if (mull) {
						col = vec3(0.20, 0.22, 0.25); // Charcoal broken-bridge aluminum frame
						rough = 0.38; metal = 0.62;
					} else {
						float r_seed = hash21(vec2(bay_idx + b_seed * 8.3, floor_idx + b_seed * 4.9));
						vec2 wuv = vec2((fx - 0.24) / 0.66, (fy - 0.18) / 0.64);
						vec3 r_alb; vec3 r_em;
						trace_interior_room(wuv, ray_local, r_seed, true, night_factor, cam_dist, r_alb, r_em);
						col = mix(r_alb, env_sky_tint * 0.74, clamp(0.22 + fresnel * 0.55, 0.0, 0.78) * (1.0 - night_factor * 0.65));
						emit = r_em;
						rough = 0.11; spec = 0.76;
					}
				} else {
					col = mix(stone_c * 0.80, stone_c, sjoint) * ground_ao;
					rough = 0.78;
				}
			} else if (style == 2) {
				// Chinese Style 2: Authentic Modern Chinese Residential Slab Tower (现代小区高层板楼: 真石漆 + 封闭落地阳台 + 空调百叶)
				float fh = 3.05;
				float bw = 4.20;
				float floor_idx = floor(h / fh);
				float bay_idx = floor(u / bw);
				float fy = fract(h / fh);
				float fx = fract(u / bw);
				bool is_balcony_bay = (mod(bay_idx + floor(b_seed * 0.5), 2.0) < 0.5);
				vec3 wall_main = mix(base_col, vec3(0.84, 0.80, 0.73), 0.32);
				vec3 accent_trim = mix(wall_main * 0.78, vec3(0.46, 0.44, 0.42), 0.42);
				float grain = hash21(floor(vec2(u, h) * 10.0));
				bool slab_line = (fy < 0.085);
				bool pilaster = (fx < 0.045 || fx > 0.955);
				bool ac_louver = (!is_balcony_bay && fx > 0.06 && fx < 0.20 && fy > 0.14 && fy < 0.72);
				bool win_open = is_balcony_bay
					? (fx > 0.08 && fx < 0.92 && fy > 0.10 && fy < 0.88)
					: (fx > 0.25 && fx < 0.88 && fy > 0.24 && fy < 0.82);

				if (slab_line) {
					col = accent_trim * ground_ao; // Characteristic Chinese residential horizontal floor bands
					rough = 0.80;
				} else if (pilaster) {
					col = mix(wall_main * 1.04, accent_trim, 0.35) * ground_ao;
					rough = 0.82;
				} else if (ac_louver) {
					// Recessed AC outdoor-unit louver bay (every Chinese apartment unit!)
					float slats = 0.62 + 0.38 * step(0.46, fract(h * 12.0));
					col = vec3(0.30, 0.32, 0.34) * slats * ground_ao;
					rough = 0.58; metal = 0.35;
				} else if (win_open) {
					if (is_balcony_bay) {
						// Wide Enclosed Glazed Chinese Balcony (封闭式落地玻璃阳台 + 护栏横杆!)
						bool rail_bar = (abs(fy - 0.36) < 0.022 || abs(fx - 0.36) < 0.012 || abs(fx - 0.64) < 0.012 || fx < 0.10 || fx > 0.90 || fy > 0.86);
						bool lower_balustrade = (fy < 0.35);
						if (rail_bar) {
							col = vec3(0.24, 0.26, 0.29);
							rough = 0.40; metal = 0.58;
						} else {
							float r_seed = hash21(vec2(bay_idx + b_seed * 6.7, floor_idx + b_seed * 5.3));
							vec2 wuv = vec2((fx - 0.08) / 0.84, (fy - 0.10) / 0.78);
							vec3 r_alb; vec3 r_em;
							trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
							// Frosted/tinted lower balcony glass vs clear upper sliding glass
							vec3 balc_tint = lower_balustrade ? mix(vec3(0.42, 0.50, 0.56), env_sky_tint, 0.45) : env_sky_tint * 0.74;
							float balc_refl = lower_balustrade ? 0.58 : clamp(0.20 + fresnel * 0.55, 0.0, 0.76);
							col = mix(r_alb, balc_tint, balc_refl * (1.0 - night_factor * 0.55));
							emit = r_em * (lower_balustrade ? 0.45 : 0.92);
							rough = lower_balustrade ? 0.22 : 0.11;
							spec = 0.74;
						}
					} else {
						bool mull = (abs(fx - 0.56) < 0.015 || abs(fy - 0.62) < 0.015 || fx < 0.27 || fx > 0.86 || fy < 0.26 || fy > 0.80);
						if (mull) {
							col = vec3(0.24, 0.26, 0.28);
							rough = 0.42; metal = 0.55;
						} else {
							float r_seed = hash21(vec2(bay_idx + b_seed * 7.7, floor_idx + b_seed * 6.1));
							vec2 wuv = vec2((fx - 0.27) / 0.59, (fy - 0.26) / 0.54);
							vec3 r_alb; vec3 r_em;
							trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
							col = mix(r_alb, env_sky_tint * 0.72, clamp(0.18 + fresnel * 0.54, 0.0, 0.75) * (1.0 - night_factor * 0.65));
							emit = r_em;
							rough = 0.12; spec = 0.74;
						}
					}
				} else {
					// Textured warm Chinese Zhenshiqi stone paint (真石漆外墙)
					col = wall_main * (0.94 + 0.07 * grain) * ground_ao;
					rough = 0.86;
				}
			} else {
				// Chinese Style 3: Jiangnan Old-Community Multi-Story Slab / White-Wall Watertown Townhouse (老小区板楼 / 江南粉墙民居)
				float fh = 2.95;
				float bw = 3.50;
				float floor_idx = floor(h / fh);
				float bay_idx = floor(u / bw);
				float fy = fract(h / fh);
				float fx = fract(u / bw);
				// Authentic white Jiangnan lime plaster or classic ceramic facade mosaic tiles (外墙面砖)
				bool is_white_plaster = (b_seed < 24.0);
				float tx_j = smoothstep(0.0, 0.04, fract(u / 0.24)) * smoothstep(0.0, 0.06, fract(h / 0.12));
				float t_var = hash21(vec2(floor(u / 0.24), floor(h / 0.12)));
				vec3 plaster_c = mix(vec3(0.88, 0.87, 0.84), base_col, 0.30) * (0.96 + 0.05 * hash21(floor(vec2(u, h) * 3.0)));
				vec3 tile_c = mix(base_col * 0.84, base_col * (0.95 + 0.07 * t_var), tx_j);
				vec3 wall_c = is_white_plaster ? plaster_c : tile_c;
				bool is_balc = (mod(bay_idx, 2.0) < 0.5);
				bool win_open = is_balc
					? (fx > 0.12 && fx < 0.88 && fy > 0.14 && fy < 0.84)
					: (fx > 0.22 && fx < 0.78 && fy > 0.24 && fy < 0.78);
				if (fy < 0.06) {
					col = vec3(0.56, 0.56, 0.55) * ground_ao;
					rough = 0.85;
				} else if (win_open) {
					bool rail = (is_balc && abs(fy - 0.38) < 0.025) || abs(fx - 0.50) < 0.018 || (is_balc && fy < 0.36 && abs(fract(fx * 9.0) - 0.5) < 0.09);
					bool frame_b = (is_balc && (fx < 0.14 || fx > 0.86 || fy > 0.82)) || (!is_balc && (fx < 0.24 || fx > 0.76 || fy < 0.26 || fy > 0.76));
					if (rail || frame_b) {
						col = vec3(0.24, 0.26, 0.28); // Dark aluminum sliding window & balcony security rail
						rough = 0.48; metal = 0.45;
					} else {
						float r_seed = hash21(vec2(bay_idx + b_seed * 7.3, floor_idx + b_seed * 2.9));
						vec2 wuv = vec2(fract(fx * 1.4), clamp((fy - 0.14) / 0.70, 0.01, 0.99));
						vec3 r_alb; vec3 r_em;
						trace_interior_room(wuv, ray_local, r_seed, false, night_factor, cam_dist, r_alb, r_em);
						col = mix(r_alb, env_sky_tint * 0.68, clamp(0.18 + fresnel * 0.48, 0.0, 0.70) * (1.0 - night_factor * 0.65));
						emit = r_em * 0.85;
						rough = 0.14; spec = 0.68;
					}
				} else {
					col = wall_c * ground_ao;
					rough = is_white_plaster ? 0.88 : 0.74;
				}
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
